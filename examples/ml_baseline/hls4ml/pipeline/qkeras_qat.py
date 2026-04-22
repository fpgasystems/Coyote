"""QKeras quantization-aware training helpers for bitstream CNNs."""

from __future__ import annotations

import csv
import json
import math
import os
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable, Sequence

import numpy as np

os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")

from .candidates import CandidateConfig
from .evaluation import metrics_summary_dict, write_metrics_summary
from .paths import ARTIFACTS_ROOT, ensure_ml_baseline_on_path

ensure_ml_baseline_on_path()

from dataset import bitstream_to_array, load_manifest  # noqa: E402
from train import compute_metrics_from_outputs  # noqa: E402

from .qkeras_plots import (  # noqa: E402
    build_run_params,
    build_split_info,
    fold_result_from_disk,
    history_rows_to_columns,
    write_kfold_plots_from_disk,
    write_fold_plots,
    write_kfold_plots,
)
from .qkeras_gradcam import write_qkeras_gradcam_bundle  # noqa: E402


SUPPORTED_QKERAS_MODEL = "cnn_small_hls_opt_img512"
DEFAULT_QAT_TAGS = ("w6_a6", "w6_a8", "w6_a10")
DEFAULT_ACTIVATION_INTEGER_BITS = (2, 2, 3, 4, 5)
DEFAULT_POOL_ACCUM_PRECISION = "fixed<40,20>"
DEFAULT_OUTPUT_PRECISION = "fixed<16,6,RND,SAT>"


@dataclass(frozen=True)
class QuantizerSpec:
    tag: str
    weight_bits: int
    weight_integer: int
    activation_bits: int
    activation_integer: tuple[int, int, int, int, int]
    alpha: int = 1

    @property
    def weight_quantizer(self) -> str:
        return f"quantized_bits({self.weight_bits},{self.weight_integer},alpha={self.alpha})"

    @property
    def bias_quantizer(self) -> str:
        return self.weight_quantizer

    def activation_quantizer(self, block_index: int) -> str:
        integer = self.activation_integer[block_index]
        return f"quantized_relu({self.activation_bits},{integer})"


QUANTIZER_SPECS = {
    tag: QuantizerSpec(
        tag=tag,
        weight_bits=6,
        weight_integer=0,
        activation_bits=int(tag.split("_a", 1)[1]),
        activation_integer=DEFAULT_ACTIVATION_INTEGER_BITS,
    )
    for tag in DEFAULT_QAT_TAGS
}


@dataclass(frozen=True)
class QATTrainConfig:
    candidate_name: str
    quantizer_tag: str
    fold: int
    epochs: int = 300
    batch_size: int = 8
    lr: float = 1e-4
    seed: int = 42
    augment: bool = True
    flip_h_prob: float = 0.5
    flip_v_prob: float = 0.5
    crop_scale_min: float = 1.0
    translate: float = 0.0
    cache_data: bool = True
    max_train_samples: int | None = None
    max_val_samples: int | None = None
    gradcam: bool = True
    gradcam_samples: int = 4
    gradcam_target_layer: str = "act4"


def require_qkeras_stack():
    """Import TensorFlow/QKeras lazily so non-QAT tools keep starting quickly."""
    import tensorflow as tf
    from qkeras import QActivation, QConv2D, QDense

    return tf, QActivation, QConv2D, QDense


def qkeras_artifact_root(candidate: CandidateConfig, quantizer_tag: str, output_root: Path | None = None) -> Path:
    root = output_root or ARTIFACTS_ROOT
    return root / candidate.name / f"qkeras_qat_{quantizer_tag}"


def qkeras_fold_dir(
    candidate: CandidateConfig,
    quantizer_tag: str,
    fold: int,
    output_root: Path | None = None,
) -> Path:
    return qkeras_artifact_root(candidate, quantizer_tag, output_root) / f"fold_{fold}"


def build_qkeras_cnn_small_hls_opt_img512(quantizer: QuantizerSpec):
    """Build the QKeras NHWC clone of ``SmallCNNHlsOptimized512``."""
    tf, QActivation, QConv2D, QDense = require_qkeras_stack()
    layers = tf.keras.layers
    models = tf.keras.models

    x = x_in = layers.Input(shape=(512, 512, 1), name="bitstream_input")
    conv_specs = [
        (8, (5, 5), (2, 2), 2),
        (16, (3, 3), (1, 1), 1),
        (24, (3, 3), (1, 1), 1),
        (24, (3, 3), (1, 1), 1),
        (32, (3, 3), (1, 1), 1),
    ]
    for i, (filters, kernel, strides, pad) in enumerate(conv_specs):
        x = layers.ZeroPadding2D(padding=pad, name=f"pad_conv{i}")(x)
        x = QConv2D(
            filters,
            kernel_size=kernel,
            strides=strides,
            padding="valid",
            kernel_quantizer=quantizer.weight_quantizer,
            bias_quantizer=quantizer.bias_quantizer,
            kernel_initializer="lecun_uniform",
            use_bias=True,
            name=f"conv{i}",
        )(x)
        x = QActivation(quantizer.activation_quantizer(i), name=f"act{i}")(x)
        x = layers.MaxPooling2D(pool_size=(2, 2), strides=(2, 2), name=f"pool{i}")(x)

    x = layers.AveragePooling2D(pool_size=(8, 8), strides=(8, 8), name="gap")(x)
    x = layers.Flatten(name="flatten")(x)
    x = QDense(
        1,
        kernel_quantizer=quantizer.weight_quantizer,
        bias_quantizer=quantizer.bias_quantizer,
        kernel_initializer="lecun_uniform",
        use_bias=True,
        name="output_dense",
    )(x)
    return models.Model(inputs=[x_in], outputs=[x], name=f"qkeras_{SUPPORTED_QKERAS_MODEL}_{quantizer.tag}")


def build_qkeras_model(candidate: CandidateConfig, quantizer_tag: str):
    if candidate.name != SUPPORTED_QKERAS_MODEL and candidate.model != SUPPORTED_QKERAS_MODEL:
        raise ValueError(
            f"QKeras QAT currently supports {SUPPORTED_QKERAS_MODEL!r}, "
            f"got candidate={candidate.name!r} model={candidate.model!r}"
        )
    try:
        quantizer = QUANTIZER_SPECS[quantizer_tag]
    except KeyError as exc:
        raise ValueError(f"Unknown quantizer tag {quantizer_tag!r}; choose from {sorted(QUANTIZER_SPECS)}") from exc
    return build_qkeras_cnn_small_hls_opt_img512(quantizer)


def _validation_csv(candidate: CandidateConfig, fold: int, checkpoint_name: str = "final") -> Path:
    return candidate.run_dir / f"fold_{fold}" / f"{checkpoint_name}_canonical_val_per_sample.csv"


def sample_ids_for_fold(candidate: CandidateConfig, fold: int, checkpoint_name: str = "final") -> list[str]:
    path = _validation_csv(candidate, fold, checkpoint_name=checkpoint_name)
    with path.open(newline="") as handle:
        return [row["sample_id"] for row in csv.DictReader(handle)]


def load_balanced_samples(candidate: CandidateConfig, seed: int = 42) -> list[dict]:
    """Recreate the balanced sample list produced by ``train.py``."""
    samples = load_manifest(min_ro=candidate.min_ro)
    labels = [int(sample["class_label"]) for sample in samples]
    n_benign = sum(label == 0 for label in labels)
    n_stand = sum(label == 1 for label in labels)
    if n_benign <= n_stand:
        return samples

    rng = np.random.RandomState(seed)
    benign_samples = [sample for sample in samples if int(sample["class_label"]) == 0]
    stand_samples = [sample for sample in samples if int(sample["class_label"]) == 1]
    benign_keep = rng.choice(len(benign_samples), size=n_stand, replace=False)
    benign_samples = [benign_samples[i] for i in sorted(benign_keep)]
    return benign_samples + stand_samples


def fold_samples(candidate: CandidateConfig, fold: int, seed: int = 42) -> tuple[list[dict], list[dict]]:
    samples = load_balanced_samples(candidate, seed=seed)
    val_ids = set(sample_ids_for_fold(candidate, fold))
    val_samples = [sample for sample in samples if sample["sample_id"] in val_ids]
    train_samples = [sample for sample in samples if sample["sample_id"] not in val_ids]
    if len(val_samples) != len(val_ids):
        found = {sample["sample_id"] for sample in val_samples}
        missing = sorted(val_ids - found)
        raise ValueError(f"Could not reconstruct fold {fold}; missing validation samples: {missing[:5]}")
    return train_samples, val_samples


def _resolve_bin_path(row: dict) -> str:
    return os.path.join(row["_bitstream_dir"], row["bitstream_path"])


def sample_to_nhwc(row: dict, candidate: CandidateConfig) -> np.ndarray:
    arr = bitstream_to_array(
        _resolve_bin_path(row),
        representation=candidate.representation,
        img_size=candidate.img_size,
        sequence_length=candidate.sequence_length,
    )
    if candidate.representation != "2d":
        raise ValueError("QKeras QAT currently supports only 2d image candidates")
    return (arr.astype(np.float32) / 255.0)[..., np.newaxis]


def apply_numpy_augmentation(x: np.ndarray, cfg: QATTrainConfig, rng: np.random.RandomState) -> np.ndarray:
    if not cfg.augment:
        return x

    out = x
    if cfg.flip_h_prob > 0.0 and rng.random() < cfg.flip_h_prob:
        out = np.flip(out, axis=1)
    if cfg.flip_v_prob > 0.0 and rng.random() < cfg.flip_v_prob:
        out = np.flip(out, axis=0)

    # The archived target run is flip-only. Keep crop/translate support minimal
    # for compatibility with train.py arguments without making it the default.
    if cfg.crop_scale_min < 1.0:
        tf, _, _, _ = require_qkeras_stack()
        scale = float(rng.uniform(cfg.crop_scale_min, 1.0))
        crop_size = int(round(out.shape[0] * math.sqrt(scale)))
        crop_size = min(max(crop_size, 1), out.shape[0])
        max_i = out.shape[0] - crop_size
        max_j = out.shape[1] - crop_size
        i = int(rng.randint(0, max_i + 1)) if max_i > 0 else 0
        j = int(rng.randint(0, max_j + 1)) if max_j > 0 else 0
        cropped = out[i : i + crop_size, j : j + crop_size, :]
        out = tf.image.resize(cropped, (cfg_to_img_size(cfg), cfg_to_img_size(cfg)), antialias=True).numpy()

    if cfg.translate > 0.0:
        max_shift = int(cfg.translate * out.shape[0])
        if max_shift > 0:
            dy = int(rng.randint(-max_shift, max_shift + 1))
            dx = int(rng.randint(-max_shift, max_shift + 1))
            shifted = np.zeros_like(out)
            src_y0 = max(0, -dy)
            src_y1 = out.shape[0] - max(0, dy)
            dst_y0 = max(0, dy)
            dst_y1 = out.shape[0] - max(0, -dy)
            src_x0 = max(0, -dx)
            src_x1 = out.shape[1] - max(0, dx)
            dst_x0 = max(0, dx)
            dst_x1 = out.shape[1] - max(0, -dx)
            shifted[dst_y0:dst_y1, dst_x0:dst_x1, :] = out[src_y0:src_y1, src_x0:src_x1, :]
            out = shifted

    return np.ascontiguousarray(out)


def cfg_to_img_size(cfg: QATTrainConfig) -> int:
    # QAT v1 is deliberately scoped to the 512x512 candidate.
    return 512


class BitstreamKerasSequence:
    """Small Keras-compatible sequence backed by bitstream manifest rows."""

    def __init__(
        self,
        samples: Sequence[dict],
        candidate: CandidateConfig,
        cfg: QATTrainConfig,
        shuffle: bool,
        augment: bool,
    ):
        self.samples = list(samples)
        self.candidate = candidate
        self.cfg = cfg
        self.shuffle = shuffle
        self.augment = augment
        self.epoch = 0
        self.indices = np.arange(len(self.samples))
        self._cache: list[np.ndarray] | None = None
        if cfg.cache_data:
            self._cache = [sample_to_nhwc(sample, candidate) for sample in self.samples]
        self.on_epoch_end()

    def __len__(self) -> int:
        return int(math.ceil(len(self.samples) / self.cfg.batch_size))

    def on_epoch_end(self) -> None:
        if self.shuffle:
            rng = np.random.RandomState(self.cfg.seed + self.epoch)
            rng.shuffle(self.indices)
        self.epoch += 1

    def _sample_array(self, idx: int) -> np.ndarray:
        if self._cache is not None:
            return self._cache[idx]
        return sample_to_nhwc(self.samples[idx], self.candidate)

    def __getitem__(self, batch_idx: int) -> tuple[np.ndarray, np.ndarray]:
        start = batch_idx * self.cfg.batch_size
        stop = min(start + self.cfg.batch_size, len(self.samples))
        batch_indices = self.indices[start:stop]
        xs = []
        ys = []
        for idx in batch_indices:
            x = self._sample_array(int(idx))
            if self.augment:
                rng = np.random.RandomState(self.cfg.seed + self.epoch * 100_000 + int(idx))
                x = apply_numpy_augmentation(x, self.cfg, rng)
            xs.append(x)
            ys.append(float(self.samples[int(idx)]["class_label"]))
        return np.stack(xs).astype(np.float32), np.asarray(ys, dtype=np.float32).reshape(-1, 1)

    def labels_in_order(self) -> np.ndarray:
        return np.asarray([float(sample["class_label"]) for sample in self.samples], dtype=np.float32)


def make_sequences(
    candidate: CandidateConfig,
    fold: int,
    cfg: QATTrainConfig,
) -> tuple[BitstreamKerasSequence, BitstreamKerasSequence, BitstreamKerasSequence, list[dict], list[dict]]:
    train_samples, val_samples = fold_samples(candidate, fold=fold, seed=cfg.seed)
    if cfg.max_train_samples is not None:
        train_samples = train_samples[: cfg.max_train_samples]
    if cfg.max_val_samples is not None:
        val_samples = val_samples[: cfg.max_val_samples]

    train_seq = BitstreamKerasSequence(train_samples, candidate, cfg, shuffle=True, augment=cfg.augment)
    val_seq = BitstreamKerasSequence(val_samples, candidate, cfg, shuffle=False, augment=False)
    aug_val_seq = BitstreamKerasSequence(val_samples, candidate, cfg, shuffle=False, augment=cfg.augment)
    return train_seq, val_seq, aug_val_seq, train_samples, val_samples


def sigmoid(logits: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-logits))


def predict_sequence(model, seq: BitstreamKerasSequence) -> tuple[np.ndarray, np.ndarray]:
    logits = []
    labels = []
    for batch_idx in range(len(seq)):
        x, y = seq[batch_idx]
        pred = model.predict(x, verbose=0)
        logits.append(np.asarray(pred).reshape(-1))
        labels.append(y.reshape(-1))
    return np.concatenate(labels), np.concatenate(logits)


def metrics_from_logits(labels: np.ndarray, logits: np.ndarray) -> dict:
    probs = sigmoid(logits)
    eps = 1e-7
    clipped = np.clip(probs, eps, 1.0 - eps)
    loss = -np.mean(labels * np.log(clipped) + (1.0 - labels) * np.log(1.0 - clipped))
    return compute_metrics_from_outputs(float(loss), labels.astype(np.float32), probs.astype(np.float32))


def history_row(epoch: int, train_loss: float, val_metrics: dict, aug_metrics: dict) -> dict:
    row = {"epoch": epoch, "train_loss": train_loss}
    for key, value in metrics_summary_dict(val_metrics).items():
        if key != "confusion_matrix":
            row[f"val_{key}"] = value
    for key, value in metrics_summary_dict(aug_metrics).items():
        if key != "confusion_matrix":
            row[f"aug_val_{key}"] = value
    return row


def write_history(path: Path, rows: Sequence[dict]) -> None:
    if not rows:
        return
    fieldnames = list(rows[0].keys())
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def qkeras_per_sample_rows(samples: Sequence[dict], labels: np.ndarray, logits: np.ndarray) -> list[dict]:
    probs = sigmoid(logits)
    rows = []
    for idx, (sample, label, logit, prob) in enumerate(zip(samples, labels, logits, probs)):
        pred = int(prob >= 0.5)
        eps = 1e-7
        p = float(np.clip(prob, eps, 1.0 - eps))
        sample_loss = -math.log(p) if int(label) == 1 else -math.log(1.0 - p)
        rows.append(
            {
                "sample_index": idx,
                "sample_id": sample.get("sample_id", ""),
                "app_name": sample.get("app_name", ""),
                "class_label": sample.get("class_label", ""),
                "class_name": sample.get("class_name", ""),
                "ro_count": sample.get("ro_count", ""),
                "bitstream_path": sample.get("bitstream_path", ""),
                "logit": f"{float(logit):.6f}",
                "probability": f"{float(prob):.6f}",
                "predicted_label": pred,
                "correct": pred == int(label),
                "per_sample_bce_loss": f"{sample_loss:.6f}",
                "per_sample_log_loss": f"{sample_loss:.6f}",
            }
        )
    return rows


def write_qkeras_per_sample(path: Path, samples: Sequence[dict], labels: np.ndarray, logits: np.ndarray) -> list[dict]:
    rows = qkeras_per_sample_rows(samples, labels, logits)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    return rows


def train_qkeras_fold(
    candidate: CandidateConfig,
    cfg: QATTrainConfig,
    output_root: Path | None = None,
) -> dict:
    tf, _, _, _ = require_qkeras_stack()
    tf.keras.utils.set_random_seed(cfg.seed + cfg.fold)

    out_dir = qkeras_fold_dir(candidate, cfg.quantizer_tag, cfg.fold, output_root)
    out_dir.mkdir(parents=True, exist_ok=True)

    train_seq, val_seq, aug_val_seq, train_samples, val_samples = make_sequences(candidate, cfg.fold, cfg)
    model = build_qkeras_model(candidate, cfg.quantizer_tag)
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=cfg.lr),
        loss=tf.keras.losses.BinaryCrossentropy(from_logits=True),
        run_eagerly=True,
    )

    history = []
    for epoch in range(1, cfg.epochs + 1):
        losses = []
        for batch_idx in range(len(train_seq)):
            x, y = train_seq[batch_idx]
            loss = model.train_on_batch(x, y)
            losses.append(float(loss[0] if isinstance(loss, (list, tuple)) else loss))
        train_seq.on_epoch_end()
        train_loss = float(np.mean(losses)) if losses else float("nan")

        val_labels, val_logits = predict_sequence(model, val_seq)
        aug_labels, aug_logits = predict_sequence(model, aug_val_seq)
        val_metrics = metrics_from_logits(val_labels, val_logits)
        aug_metrics = metrics_from_logits(aug_labels, aug_logits)
        history.append(history_row(epoch, train_loss, val_metrics, aug_metrics))
        print(
            f"epoch={epoch:03d} train_loss={train_loss:.5f} "
            f"val_acc={val_metrics['accuracy']:.4f} val_pr_auc={val_metrics['pr_auc']:.4f} "
            f"aug_acc={aug_metrics['accuracy']:.4f}"
        )

    val_labels, val_logits = predict_sequence(model, val_seq)
    aug_labels, aug_logits = predict_sequence(model, aug_val_seq)
    val_metrics = metrics_from_logits(val_labels, val_logits)
    aug_metrics = metrics_from_logits(aug_labels, aug_logits)

    write_history(out_dir / "history.csv", history)
    write_metrics_summary(
        out_dir / "metrics_summary.json",
        val_metrics,
        extra={
            "candidate": candidate.name,
            "model": candidate.model,
            "stage": f"qkeras_qat_{cfg.quantizer_tag}",
            "fold": cfg.fold,
            "quantizer": asdict(QUANTIZER_SPECS[cfg.quantizer_tag]),
            "train_config": asdict(cfg),
            "source_run_dir": str(candidate.run_dir),
        },
    )
    write_metrics_summary(
        out_dir / "augmented_metrics_summary.json",
        aug_metrics,
        extra={
            "candidate": candidate.name,
            "model": candidate.model,
            "stage": f"qkeras_qat_{cfg.quantizer_tag}_augmented",
            "fold": cfg.fold,
        },
    )
    per_sample_rows = write_qkeras_per_sample(out_dir / "per_sample.csv", val_samples, val_labels, val_logits)
    write_qkeras_per_sample(out_dir / "augmented_per_sample.csv", val_samples, aug_labels, aug_logits)
    model.save_weights(out_dir / "final_weights.weights.h5")
    (out_dir / "model_config.json").write_text(model.to_json())
    training_manifest = {
        "candidate": candidate.name,
        "quantizer": asdict(QUANTIZER_SPECS[cfg.quantizer_tag]),
        "train_config": asdict(cfg),
        "n_train": len(train_samples),
        "n_val": len(val_samples),
        "source_run_dir": str(candidate.run_dir),
    }
    (out_dir / "training_manifest.json").write_text(
        json.dumps(training_manifest, indent=2, sort_keys=True)
    )

    history_columns = history_rows_to_columns(history)
    split_info = build_split_info(
        candidate.name, cfg.fold, len(train_samples), len(val_samples)
    )
    plot_run_params = build_run_params(training_manifest)
    write_fold_plots(
        out_dir,
        history_columns,
        val_metrics,
        aug_metrics,
        split_info=split_info,
        run_params=plot_run_params,
        final_epoch=cfg.epochs,
    )

    if cfg.gradcam:
        try:
            write_qkeras_gradcam_bundle(
                model,
                candidate,
                cfg,
                val_samples,
                per_sample_rows,
                out_dir / "gradcam_final",
                target_layer_name=cfg.gradcam_target_layer,
                max_samples=cfg.gradcam_samples,
            )
        except Exception as exc:
            print(
                f"[qat-gradcam] WARNING: failed quantizer={cfg.quantizer_tag} "
                f"fold={cfg.fold}: {exc}"
            )

    return {
        "out_dir": out_dir,
        "metrics": val_metrics,
        "aug_metrics": aug_metrics,
        "history_columns": history_columns,
        "final_epoch": cfg.epochs,
    }


def load_trained_qkeras_model(candidate: CandidateConfig, quantizer_tag: str, fold_dir: Path):
    model = build_qkeras_model(candidate, quantizer_tag)
    model.load_weights(fold_dir / "final_weights.weights.h5")
    return model


def _read_per_sample(path: Path) -> list[dict]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def write_kfold_artifacts(
    candidate: CandidateConfig,
    quantizer_tag: str,
    fold_results: Sequence[dict],
    output_root: Path | None = None,
    cfg: QATTrainConfig | None = None,
) -> Path:
    """Generate top-level k-fold plots/CSV using train.py utilities."""
    run_dir = qkeras_artifact_root(candidate, quantizer_tag, output_root)
    run_dir.mkdir(parents=True, exist_ok=True)

    fold_payload = []
    for result in fold_results:
        fold_payload.append({
            "fold_label": f"fold_{result.get('fold', '?')}",
            "history": result["history_columns"],
            "final_metrics": result["metrics"],
            "final_aug_metrics": result.get("aug_metrics"),
            "final_epoch": result.get("final_epoch") or len(result["history_columns"].get("train_loss", [])),
        })

    epochs = cfg.epochs if cfg is not None else fold_payload[0]["final_epoch"]
    split_info = (
        f"Candidate: {candidate.name}  |  Quantizer: {quantizer_tag}  |  "
        f"Folds: {len(fold_payload)}  |  Epochs: {epochs}"
    )
    run_params = None
    if cfg is not None:
        run_params = {
            "quantizer": quantizer_tag,
            "epochs": cfg.epochs,
            "batch_size": cfg.batch_size,
            "lr": cfg.lr,
            "seed": cfg.seed,
            "augment": cfg.augment,
        }
    write_kfold_plots(run_dir, fold_payload, split_info=split_info, run_params=run_params)
    return run_dir


def write_kfold_artifacts_from_disk(
    candidate: CandidateConfig,
    quantizer_tag: str,
    output_root: Path | None = None,
) -> Path:
    """Generate run-level k-fold plots from completed fold artifact dirs."""
    run_dir = qkeras_artifact_root(candidate, quantizer_tag, output_root)
    fold_dirs = [run_dir / f"fold_{fold}" for fold in candidate.folds]
    missing = [
        str(fold_dir)
        for fold_dir in fold_dirs
        if not (fold_dir / "history.csv").exists() or not (fold_dir / "per_sample.csv").exists()
    ]
    if missing:
        raise FileNotFoundError(
            "Cannot write QAT k-fold artifacts; missing history/per-sample files for: "
            + ", ".join(missing)
        )
    write_kfold_plots_from_disk(candidate, quantizer_tag, run_dir, fold_dirs)
    return run_dir


def aggregate_qkeras_metrics(candidate: CandidateConfig, quantizer_tag: str, output_root: Path | None = None) -> dict:
    root = qkeras_artifact_root(candidate, quantizer_tag, output_root)
    pooled_dir = root / "pooled"
    pooled_dir.mkdir(parents=True, exist_ok=True)

    rows: list[dict] = []
    for fold in candidate.folds:
        path = root / f"fold_{fold}" / "per_sample.csv"
        if not path.exists():
            raise FileNotFoundError(f"Missing QAT per-sample CSV: {path}")
        rows.extend(_read_per_sample(path))

    with (pooled_dir / "per_sample.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    labels = np.asarray([int(row["class_label"]) for row in rows], dtype=np.float32)
    probs = np.asarray([float(row["probability"]) for row in rows], dtype=np.float32)
    losses = np.asarray([float(row["per_sample_bce_loss"]) for row in rows], dtype=np.float32)
    metrics = compute_metrics_from_outputs(float(np.mean(losses)), labels, probs)
    write_metrics_summary(
        pooled_dir / "metrics_summary.json",
        metrics,
        extra={
            "candidate": candidate.name,
            "model": candidate.model,
            "stage": f"qkeras_qat_{quantizer_tag}",
            "folds": list(candidate.folds),
        },
    )
    return metrics


def select_best_quantizer(results: Iterable[tuple[str, dict]]) -> tuple[str, dict]:
    rows = list(results)
    if not rows:
        raise ValueError("No QAT results available for selection")
    return max(
        rows,
        key=lambda item: (
            float(item[1].get("pr_auc", float("-inf"))),
            float(item[1].get("accuracy", float("-inf"))),
            -float(item[1].get("bce_loss", float("inf"))),
        ),
    )


def qkeras_hls_config(
    model,
    backend: str = "Vitis",
    strategy: str = "Resource",
    reuse_factor: int = 8,
    accum_precision: str | None = None,
    output_precision: str = DEFAULT_OUTPUT_PRECISION,
    pool_accum_precision: str = DEFAULT_POOL_ACCUM_PRECISION,
) -> dict:
    import hls4ml
    import keras

    # hls4ml 1.3 chooses its Keras parser from the standalone ``keras``
    # package version. QKeras 0.9 trains correctly through legacy tf_keras, so
    # force the hls4ml Keras-v2 parser for this model object.
    keras_version = keras.__version__
    keras.__version__ = "2.15.0"
    try:
        config = hls4ml.utils.config_from_keras_model(model, granularity="name", backend=backend)
    finally:
        keras.__version__ = keras_version
    config.setdefault("Model", {})
    config["Model"]["Strategy"] = strategy
    config["Model"]["ReuseFactor"] = reuse_factor
    for layer in config.get("LayerName", {}).values():
        layer["ReuseFactor"] = reuse_factor
        precision = layer.get("Precision")
        if accum_precision and isinstance(precision, dict) and "accum" in precision:
            precision["accum"] = accum_precision
    if "output_dense" in config.get("LayerName", {}):
        precision = config["LayerName"]["output_dense"].setdefault("Precision", {})
        precision["result"] = output_precision
    if "gap" in config.get("LayerName", {}):
        precision = config["LayerName"]["gap"].setdefault("Precision", {})
        precision["accum"] = pool_accum_precision
    return config


def compile_qkeras_hls_model(
    candidate: CandidateConfig,
    quantizer_tag: str,
    fold: int,
    output_dir: Path,
    project_name: str,
    qat_output_root: Path | None = None,
    io_type: str = "io_stream",
    backend: str = "Vitis",
    strategy: str = "Resource",
    reuse_factor: int = 8,
    part: str | None = None,
    clock_period: float = 5.0,
    accum_precision: str | None = None,
    output_precision: str = DEFAULT_OUTPUT_PRECISION,
    pool_accum_precision: str = DEFAULT_POOL_ACCUM_PRECISION,
) :
    import hls4ml
    import keras

    fold_dir = qkeras_fold_dir(candidate, quantizer_tag, fold, qat_output_root)
    model = load_trained_qkeras_model(candidate, quantizer_tag, fold_dir)
    config = qkeras_hls_config(
        model,
        backend=backend,
        strategy=strategy,
        reuse_factor=reuse_factor,
        accum_precision=accum_precision,
        output_precision=output_precision,
        pool_accum_precision=pool_accum_precision,
    )

    keras_version = keras.__version__
    keras.__version__ = "2.15.0"
    try:
        hls_model = hls4ml.converters.convert_from_keras_model(
            model,
            hls_config=config,
            output_dir=str(output_dir),
            project_name=project_name,
            backend=backend,
            io_type=io_type,
            part=part or candidate.target_part,
            clock_period=clock_period,
        )
    finally:
        keras.__version__ = keras_version
    hls_model.compile()
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "conversion_manifest.json").write_text(
        json.dumps(
            {
                "candidate": candidate.name,
                "quantizer_tag": quantizer_tag,
                "fold": fold,
                "source_qat_dir": str(fold_dir),
                "project_name": project_name,
                "io_type": io_type,
                "backend": backend,
                "strategy": strategy,
                "reuse_factor": reuse_factor,
                "part": part or candidate.target_part,
                "clock_period": clock_period,
                "accum_precision": accum_precision,
                "output_precision": output_precision,
                "pool_accum_precision": pool_accum_precision,
            },
            indent=2,
            sort_keys=True,
        )
    )
    return hls_model


def build_qkeras_hls_project(
    candidate: CandidateConfig,
    quantizer_tag: str,
    fold: int,
    output_dir: Path,
    project_name: str,
    qat_output_root: Path | None = None,
    io_type: str = "io_stream",
    backend: str = "Vitis",
    strategy: str = "Resource",
    reuse_factor: int = 8,
    part: str | None = None,
    clock_period: float = 5.0,
    accum_precision: str | None = None,
    output_precision: str = DEFAULT_OUTPUT_PRECISION,
    pool_accum_precision: str = DEFAULT_POOL_ACCUM_PRECISION,
) -> Path:
    compile_qkeras_hls_model(
        candidate,
        quantizer_tag=quantizer_tag,
        fold=fold,
        output_dir=output_dir,
        project_name=project_name,
        qat_output_root=qat_output_root,
        io_type=io_type,
        backend=backend,
        strategy=strategy,
        reuse_factor=reuse_factor,
        part=part,
        clock_period=clock_period,
        accum_precision=accum_precision,
        output_precision=output_precision,
        pool_accum_precision=pool_accum_precision,
    )
    return output_dir
