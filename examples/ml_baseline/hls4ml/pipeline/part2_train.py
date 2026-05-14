"""Part 2 of the notebook flow: deterministic k-fold TensorFlow training."""

from __future__ import annotations

import csv
import math
import os
from pathlib import Path
from typing import Any, Sequence

import numpy as np

from .part1_common import (
    FlowContext,
    QATTrainConfig,
    class_counts,
    fold_dir,
    flow_candidate,
    metrics_from_logits,
    metrics_from_stage_rows,
    metrics_summary_dict,
    read_csv,
    read_json,
    rows_from_logits,
    write_csv,
    write_json,
    write_metrics_summary,
    write_run_index,
    write_top_manifests,
)
from .experiment_suite import analyze_model_shape
from .qkeras_plots import (
    build_split_info,
    history_rows_to_columns,
    write_fold_plots,
    write_kfold_plots,
    write_per_sample_diagnostic_plots,
    write_qkeras_gradcam_bundle,
)

from dataset import bitstream_to_array, load_manifest  # noqa: E402

def _resolve_bin_path(row: dict[str, Any]) -> str:
    return os.path.join(row["_bitstream_dir"], row["bitstream_path"])


def sample_to_nhwc(row: dict[str, Any], candidate) -> np.ndarray:
    arr = bitstream_to_array(
        _resolve_bin_path(row),
        representation=candidate.representation,
        img_size=candidate.img_size,
        sequence_length=candidate.sequence_length,
    )
    if candidate.representation != "2d":
        raise ValueError("hls4ml training flow supports only 2d image candidates")
    return (arr.astype(np.float32) / 255.0)[..., np.newaxis]


def apply_numpy_augmentation(x: np.ndarray, cfg: QATTrainConfig, rng: np.random.RandomState) -> np.ndarray:
    if not cfg.augment:
        return x
    out = x
    if cfg.flip_h_prob > 0.0 and rng.random() < cfg.flip_h_prob:
        out = np.flip(out, axis=1)
    if cfg.flip_v_prob > 0.0 and rng.random() < cfg.flip_v_prob:
        out = np.flip(out, axis=0)
    if cfg.crop_scale_min < 1.0:
        import tensorflow as tf

        scale = float(rng.uniform(cfg.crop_scale_min, 1.0))
        crop_size = int(round(out.shape[0] * math.sqrt(scale)))
        crop_size = min(max(crop_size, 1), out.shape[0])
        max_i = out.shape[0] - crop_size
        max_j = out.shape[1] - crop_size
        i = int(rng.randint(0, max_i + 1)) if max_i > 0 else 0
        j = int(rng.randint(0, max_j + 1)) if max_j > 0 else 0
        cropped = out[i : i + crop_size, j : j + crop_size, :]
        out = tf.image.resize(cropped, (x.shape[0], x.shape[1]), antialias=True).numpy()
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


class BitstreamKerasSequence:
    def __init__(self, samples: Sequence[dict], candidate, cfg: QATTrainConfig, shuffle: bool, augment: bool):
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


def predict_sequence(model, seq: BitstreamKerasSequence) -> tuple[np.ndarray, np.ndarray]:
    logits = []
    labels = []
    for batch_idx in range(len(seq)):
        x, y = seq[batch_idx]
        pred = model.predict(x, verbose=0)
        logits.append(np.asarray(pred).reshape(-1))
        labels.append(y.reshape(-1))
    return np.concatenate(labels), np.concatenate(logits)


def write_history(path: Path, rows: Sequence[dict[str, Any]]) -> None:
    write_csv(path, rows)


def write_qkeras_per_sample(path: Path, samples: Sequence[dict], labels: np.ndarray, logits: np.ndarray) -> list[dict[str, Any]]:
    rows = rows_from_logits(samples, labels.astype(int), logits)
    write_csv(path, rows)
    return rows



def load_balanced_samples(ctx: FlowContext) -> list[dict[str, Any]]:
    candidate = ctx.config["candidate"]
    samples = load_manifest(min_ro=int(candidate["min_ro"]))
    if not bool(candidate.get("balance_classes", True)):
        return samples
    labels = [int(sample["class_label"]) for sample in samples]
    n_benign = sum(label == 0 for label in labels)
    n_stand = sum(label == 1 for label in labels)
    if n_benign <= n_stand:
        return samples
    rng = np.random.RandomState(int(candidate["seed"]))
    benign_samples = [sample for sample in samples if int(sample["class_label"]) == 0]
    stand_samples = [sample for sample in samples if int(sample["class_label"]) == 1]
    benign_keep = rng.choice(len(benign_samples), size=n_stand, replace=False)
    return [benign_samples[i] for i in sorted(benign_keep)] + stand_samples


def make_kfold_splits(samples: list[dict[str, Any]], k_folds: int, seed: int) -> list[tuple[list[dict], list[dict]]]:
    from sklearn.model_selection import StratifiedKFold

    labels = np.asarray([int(sample["class_label"]) for sample in samples])
    skf = StratifiedKFold(n_splits=k_folds, shuffle=True, random_state=seed)
    return [([samples[i] for i in train_idx], [samples[i] for i in val_idx]) for train_idx, val_idx in skf.split(samples, labels)]


def get_splits(ctx: FlowContext) -> list[tuple[list[dict], list[dict]]]:
    split_dir = ctx.run_root / "splits"
    expected = [split_dir / f"fold_{fold}_{kind}.csv" for fold in ctx.folds for kind in ("train", "val")]
    if all(path.exists() for path in expected):
        splits = []
        for fold in ctx.folds:
            splits.append((read_csv(split_dir / f"fold_{fold}_train.csv"), read_csv(split_dir / f"fold_{fold}_val.csv")))
        return splits

    samples = load_balanced_samples(ctx)
    splits = make_kfold_splits(samples, ctx.k_folds, int(ctx.config["candidate"]["seed"]))
    split_dir.mkdir(parents=True, exist_ok=True)
    summary_rows = []
    for fold, (train_samples, val_samples) in enumerate(splits):
        summary_rows.append(
            {
                "fold": fold,
                "n_train": len(train_samples),
                "train_benign": class_counts(train_samples)[0],
                "train_standalone": class_counts(train_samples)[1],
                "n_val": len(val_samples),
                "val_benign": class_counts(val_samples)[0],
                "val_standalone": class_counts(val_samples)[1],
            }
        )
        for name, rows in (("train", train_samples), ("val", val_samples)):
            fieldnames = sorted({key for row in rows for key in row.keys()})
            with (split_dir / f"fold_{fold}_{name}.csv").open("w", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=fieldnames)
                writer.writeheader()
                writer.writerows(rows)
    write_csv(split_dir / "summary.csv", summary_rows)
    return splits


def weight_quantizer(ctx: FlowContext) -> str:
    q = ctx.config["quantization"]
    return f"quantized_bits({int(q['weight_bits'])},{int(q['weight_integer'])},alpha={int(q['alpha'])})"


def activation_quantizer(ctx: FlowContext, block_idx: int) -> str:
    q = ctx.config["quantization"]
    return f"quantized_relu({int(q['activation_bits'])},{int(q['activation_integer'][block_idx])})"


def build_notebook_model(ctx: FlowContext, name_suffix: str = ""):
    import tensorflow as tf

    layers = tf.keras.layers
    models = tf.keras.models
    model_cfg = ctx.config["model"]
    x = x_in = layers.Input(shape=tuple(model_cfg["input_shape"]), name="bitstream_input")
    if ctx.quantization_enabled:
        from qkeras import QActivation, QConv2D, QDense

    for i, spec in enumerate(model_cfg["conv_specs"]):
        x = layers.ZeroPadding2D(padding=spec["pad"], name=f"pad_{spec['name']}")(x)
        if ctx.quantization_enabled:
            x = QConv2D(
                int(spec["filters"]),
                kernel_size=tuple(spec["kernel"]),
                strides=tuple(spec["strides"]),
                padding="valid",
                kernel_quantizer=weight_quantizer(ctx),
                bias_quantizer=weight_quantizer(ctx),
                kernel_initializer="lecun_uniform",
                use_bias=True,
                name=spec["name"],
            )(x)
            x = QActivation(activation_quantizer(ctx, i), name=f"act{i}")(x)
        else:
            x = layers.Conv2D(
                int(spec["filters"]),
                kernel_size=tuple(spec["kernel"]),
                strides=tuple(spec["strides"]),
                padding="valid",
                kernel_initializer="lecun_uniform",
                use_bias=True,
                name=spec["name"],
            )(x)
            x = layers.ReLU(name=f"act{i}")(x)
        x = layers.MaxPooling2D(pool_size=(2, 2), strides=(2, 2), name=f"pool{i}")(x)
    x = layers.AveragePooling2D(
        pool_size=tuple(model_cfg["final_avg_pool"]),
        strides=tuple(model_cfg["final_avg_pool"]),
        name="gap",
    )(x)
    x = layers.Flatten(name="flatten")(x)
    if ctx.quantization_enabled:
        x = QDense(
            int(model_cfg["output_units"]),
            kernel_quantizer=weight_quantizer(ctx),
            bias_quantizer=weight_quantizer(ctx),
            kernel_initializer="lecun_uniform",
            use_bias=True,
            name="output_dense",
        )(x)
    else:
        x = layers.Dense(
            int(model_cfg["output_units"]),
            kernel_initializer="lecun_uniform",
            use_bias=True,
            name="output_dense",
        )(x)
    return models.Model(inputs=[x_in], outputs=[x], name=f"{ctx.training_stage}_{ctx.model_flavor_label}{name_suffix}")


def build_qkeras_notebook_model(ctx: FlowContext, name_suffix: str = ""):
    return build_notebook_model(ctx, name_suffix=name_suffix)


class KerasSequenceAdapter:
    def __init__(self, seq, **kwargs):
        import tensorflow as tf

        class _Adapter(tf.keras.utils.Sequence):
            def __init__(self, wrapped, **adapter_kwargs):
                super().__init__(**adapter_kwargs)
                self.wrapped = wrapped

            def __len__(self):
                return len(self.wrapped)

            def __getitem__(self, idx):
                return self.wrapped[idx]

            def on_epoch_end(self):
                if hasattr(self.wrapped, "on_epoch_end"):
                    self.wrapped.on_epoch_end()

        self.adapter = _Adapter(seq, **kwargs)

    def __getattr__(self, name):
        return getattr(self.adapter, name)


def qat_train_config(ctx: FlowContext, fold: int) -> QATTrainConfig:
    t = ctx.config["training"]
    return QATTrainConfig(
        candidate_name=ctx.candidate_name,
        quantizer_tag=ctx.quantizer_tag,
        fold=fold,
        epochs=int(t["epochs"]),
        batch_size=int(t["batch_size"]),
        lr=float(t["lr"]),
        seed=int(ctx.config["candidate"]["seed"]),
        augment=bool(t["augment"]),
        flip_h_prob=float(t["flip_h_prob"]),
        flip_v_prob=float(t["flip_v_prob"]),
        crop_scale_min=float(t["crop_scale_min"]),
        translate=float(t["translate"]),
        cache_data=bool(t["cache_data"]),
        max_train_samples=t.get("max_train_samples"),
        max_val_samples=t.get("max_val_samples"),
        gradcam=False,
    )


def make_sequences(ctx: FlowContext, splits: list[tuple[list[dict], list[dict]]], fold: int):
    candidate = flow_candidate(ctx)
    cfg = qat_train_config(ctx, fold)
    train_samples, val_samples = splits[fold]
    if cfg.max_train_samples is not None:
        train_samples = train_samples[: int(cfg.max_train_samples)]
    if cfg.max_val_samples is not None:
        val_samples = val_samples[: int(cfg.max_val_samples)]
    train_seq = BitstreamKerasSequence(train_samples, candidate, cfg, shuffle=True, augment=cfg.augment)
    val_seq = BitstreamKerasSequence(val_samples, candidate, cfg, shuffle=False, augment=False)
    aug_val_seq = BitstreamKerasSequence(val_samples, candidate, cfg, shuffle=False, augment=cfg.augment)
    return cfg, train_seq, val_seq, aug_val_seq, train_samples, val_samples


def fold_cache_valid(ctx: FlowContext, fold: int) -> bool:
    fdir = fold_dir(ctx, fold)
    manifest_path = fdir / "training_manifest.json"
    required = [
        manifest_path,
        fdir / "final_weights.weights.h5",
        fdir / "history.csv",
        fdir / "per_sample.csv",
        fdir / "metrics_summary.json",
    ]
    if not all(path.exists() for path in required):
        return False
    try:
        manifest = read_json(manifest_path)
    except Exception:
        return False
    if bool(ctx.config.get("training", {}).get("allow_stale_fold_cache", False)):
        return manifest.get("fold") == fold
    return manifest.get("fingerprint") == ctx.training_fingerprint and manifest.get("fold") == fold


def load_fold_model(ctx: FlowContext, fold: int):
    model = build_notebook_model(ctx, name_suffix=f"_fold{fold}")
    model.load_weights(fold_dir(ctx, fold) / "final_weights.weights.h5")
    return model


def qkeras_gradcam_target_layer(ctx: FlowContext) -> str:
    conv_specs = ctx.config["model"].get("conv_specs", [])
    if not conv_specs:
        raise ValueError("Grad-CAM requires at least one convolution layer")
    return str(conv_specs[-1]["name"])


def qkeras_gradcam_target_layers(ctx: FlowContext, target_sizes: Sequence[int] = (64, 32)) -> list[dict[str, Any]]:
    """Choose conv layers with exact spatial sizes for interpretable Grad-CAM bundles."""
    conv_specs = ctx.config["model"].get("conv_specs", [])
    if not conv_specs:
        raise ValueError("Grad-CAM requires at least one convolution layer")
    shape_rows = analyze_model_shape(ctx.config)["shape_trace"]
    conv_by_size: dict[int, dict[str, Any]] = {}
    for row in shape_rows:
        if row.get("kind") != "conv":
            continue
        height = int(row["height"])
        width = int(row["width"])
        if height != width:
            continue
        # Keep the deepest conv at a given spatial size.
        conv_by_size[height] = {
            "target_size": height,
            "layer_name": str(row["layer"]),
            "shape": f"{height}x{width}x{int(row['channels'])}",
        }
    return [conv_by_size[int(size)] for size in target_sizes if int(size) in conv_by_size]


def _gradcam_bundle_complete(gradcam_dir: Path) -> bool:
    return (
        (gradcam_dir / "overview_grid.png").exists()
        and (gradcam_dir / "gradcam_summary.csv").exists()
        and (gradcam_dir / "high_ro_standalone_gradcam.png").exists()
        and (gradcam_dir / "high_ro_standalone_gradcam_1024.png").exists()
    )


def write_fold_extra_plots(
    ctx: FlowContext,
    fold: int,
    val_samples: Sequence[dict],
    prediction_rows: Sequence[dict[str, Any]],
    model=None,
) -> None:
    fdir = fold_dir(ctx, fold)
    write_per_sample_diagnostic_plots(fdir, prediction_rows, title_prefix=f"Fold {fold}")
    target_layers = qkeras_gradcam_target_layers(ctx)
    legacy_gradcam_dir = fdir / "gradcam_final"
    if all(_gradcam_bundle_complete(fdir / f"gradcam_final_{target['target_size']}x{target['target_size']}") for target in target_layers) and _gradcam_bundle_complete(legacy_gradcam_dir):
        return
    if model is None:
        model = load_fold_model(ctx, fold)
    candidate = flow_candidate(ctx)
    for target in target_layers:
        size = int(target["target_size"])
        write_qkeras_gradcam_bundle(
            model,
            val_samples,
            prediction_rows,
            fdir / f"gradcam_final_{size}x{size}",
            image_getter=lambda sample: sample_to_nhwc(sample, candidate),
            target_layer_name=str(target["layer_name"]),
            target_layer_shape=str(target["shape"]),
            split_label=f"fold_{fold}",
            command_text=(
                f"auto_from_hls4ml_notebook_flow.py candidate={ctx.candidate_name} "
                f"model_flavor={ctx.training_stage} precision={ctx.model_flavor_label} "
                f"fold={fold} checkpoint=final target_layer={target['layer_name']} target_shape={target['shape']}"
            ),
        )
    if not _gradcam_bundle_complete(legacy_gradcam_dir):
        write_qkeras_gradcam_bundle(
            model,
            val_samples,
            prediction_rows,
            legacy_gradcam_dir,
            image_getter=lambda sample: sample_to_nhwc(sample, candidate),
            target_layer_name=qkeras_gradcam_target_layer(ctx),
            split_label=f"fold_{fold}",
            command_text=(
                f"auto_from_hls4ml_notebook_flow.py candidate={ctx.candidate_name} "
                f"model_flavor={ctx.training_stage} precision={ctx.model_flavor_label} fold={fold} checkpoint=final"
            ),
        )


class EpochMetricsCallback:
    def __init__(self, ctx: FlowContext, val_seq, aug_val_seq):
        import tensorflow as tf

        class _Callback(tf.keras.callbacks.Callback):
            def __init__(self, outer):
                super().__init__()
                self.outer = outer

            def on_epoch_end(self, epoch, logs=None):
                self.outer.on_epoch_end(self.model, epoch, logs)

        self.ctx = ctx
        self.val_seq = val_seq
        self.aug_val_seq = aug_val_seq
        self.every_n_epochs = int(ctx.config["training"]["metrics_every_n_epochs"])
        self.rows: list[dict[str, Any]] = []
        self.callback = _Callback(self)

    def on_epoch_end(self, model, epoch: int, logs=None) -> None:
        logs = logs or {}
        epoch_num = epoch + 1
        if epoch_num % self.every_n_epochs != 0 and epoch_num != int(self.ctx.config["training"]["epochs"]):
            return
        val_labels, val_logits = predict_sequence(model, self.val_seq)
        aug_labels, aug_logits = predict_sequence(model, self.aug_val_seq)
        val_metrics = metrics_from_logits(val_labels, val_logits)
        aug_metrics = metrics_from_logits(aug_labels, aug_logits)
        row = {"epoch": epoch_num, "train_loss": float(logs.get("loss", float("nan")))}
        for key, value in metrics_summary_dict(val_metrics).items():
            if key != "confusion_matrix":
                row[f"val_{key}"] = value
        for key, value in metrics_summary_dict(aug_metrics).items():
            if key != "confusion_matrix":
                row[f"aug_val_{key}"] = value
        self.rows.append(row)
        print(
            f" metrics: val_acc={val_metrics['accuracy']:.4f} "
            f"val_pr_auc={val_metrics['pr_auc']:.4f} aug_acc={aug_metrics['accuracy']:.4f}"
        )


def prune_function_factory(ctx: FlowContext, nsteps: int):
    import tensorflow_model_optimization as tfmot

    pruning = ctx.config["pruning"]
    if not ctx.pruning_enabled:
        return lambda layer: layer
    pruning_params = {
        "pruning_schedule": tfmot.sparsity.keras.PolynomialDecay(
            initial_sparsity=0.0,
            final_sparsity=float(pruning["final_sparsity"]),
            begin_step=nsteps * int(pruning["begin_epoch"]),
            end_step=nsteps * int(pruning["end_epoch"]),
            frequency=max(1, nsteps * int(pruning["frequency_epochs"])),
        )
    }

    def prune_function(layer):
        if layer.name == "output_dense" and not bool(pruning["prune_output_dense"]):
            return layer
        if layer.__class__.__name__ in {"Conv2D", "Dense", "QConv2D", "QDense"}:
            return tfmot.sparsity.keras.prune_low_magnitude(layer, **pruning_params)
        return layer

    return prune_function


def train_or_load_fold(ctx: FlowContext, splits: list[tuple[list[dict], list[dict]]], fold: int, force: bool = False) -> dict:
    import tensorflow as tf
    import tensorflow_model_optimization as tfmot
    from tensorflow_model_optimization.python.core.sparsity.keras import pruning_callbacks

    fdir = fold_dir(ctx, fold)
    fdir.mkdir(parents=True, exist_ok=True)
    cfg, train_seq, val_seq, aug_val_seq, train_samples, val_samples = make_sequences(ctx, splits, fold)
    if not force and fold_cache_valid(ctx, fold):
        print(f"Fold {fold}: exact cache hit at {fdir}")
        history_rows = read_csv(fdir / "history.csv")
        val_rows = read_csv(fdir / "per_sample.csv")
        metrics = metrics_from_stage_rows(val_rows)
        aug_metrics = metrics_from_stage_rows(read_csv(fdir / "augmented_per_sample.csv"))
        write_fold_extra_plots(ctx, fold, val_samples, val_rows, model=None)
        return {
            "fold": fold,
            "out_dir": fdir,
            "model": None,
            "metrics": metrics,
            "aug_metrics": aug_metrics,
            "history_columns": history_rows_to_columns(history_rows),
            "train_samples": train_samples,
            "val_samples": val_samples,
            "final_epoch": cfg.epochs,
        }

    pruning_enabled = ctx.pruning_enabled
    print(f"Fold {fold}: training {ctx.training_stage} model")
    tf.keras.backend.clear_session()
    tf.keras.utils.set_random_seed(int(ctx.config["candidate"]["seed"]) + fold)
    nsteps = math.ceil(len(train_samples) / int(ctx.config["training"]["batch_size"]))
    base_model = build_notebook_model(ctx, name_suffix=f"_fold{fold}")
    train_model = tf.keras.models.clone_model(base_model, clone_function=prune_function_factory(ctx, nsteps))
    train_model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=float(ctx.config["training"]["lr"])),
        loss=tf.keras.losses.BinaryCrossentropy(from_logits=True),
        run_eagerly=True,
    )
    metrics_cb = EpochMetricsCallback(ctx, val_seq, aug_val_seq)
    callbacks = [metrics_cb.callback]
    if pruning_enabled:
        callbacks = [pruning_callbacks.UpdatePruningStep(), *callbacks]
    train_model.fit(
        KerasSequenceAdapter(train_seq).adapter,
        epochs=int(ctx.config["training"]["epochs"]),
        validation_data=KerasSequenceAdapter(val_seq).adapter,
        callbacks=callbacks,
        verbose=1,
    )
    stripped_model = tfmot.sparsity.keras.strip_pruning(train_model) if pruning_enabled else train_model
    val_labels, val_logits = predict_sequence(stripped_model, val_seq)
    aug_labels, aug_logits = predict_sequence(stripped_model, aug_val_seq)
    val_metrics = metrics_from_logits(val_labels, val_logits)
    aug_metrics = metrics_from_logits(aug_labels, aug_logits)

    write_history(fdir / "history.csv", metrics_cb.rows)
    write_metrics_summary(
        fdir / "metrics_summary.json",
        val_metrics,
        extra={
            "fingerprint": ctx.training_fingerprint,
            "fold": fold,
            "stage": ctx.training_stage,
            "candidate": ctx.candidate_name,
            "quantization_enabled": ctx.quantization_enabled,
            "pruning_enabled": pruning_enabled,
        },
    )
    write_metrics_summary(
        fdir / "augmented_metrics_summary.json",
        aug_metrics,
        extra={
            "fingerprint": ctx.training_fingerprint,
            "fold": fold,
            "stage": f"{ctx.training_stage}_augmented",
            "candidate": ctx.candidate_name,
            "quantization_enabled": ctx.quantization_enabled,
            "pruning_enabled": pruning_enabled,
        },
    )
    val_rows = write_qkeras_per_sample(fdir / "per_sample.csv", val_samples, val_labels, val_logits)
    write_qkeras_per_sample(fdir / "augmented_per_sample.csv", val_samples, aug_labels, aug_logits)
    stripped_model.save_weights(fdir / "final_weights.weights.h5")
    (fdir / "model_config.json").write_text(stripped_model.to_json())
    write_json(
        fdir / "training_manifest.json",
        {
            "fingerprint": ctx.training_fingerprint,
            "fold": fold,
            "candidate": ctx.candidate_name,
            "config": {
                key: ctx.config[key]
                for key in ("run", "candidate", "model", "quantization", "pruning", "training")
            },
            "n_train": len(train_samples),
            "n_val": len(val_samples),
            "train_counts": class_counts(train_samples),
            "val_counts": class_counts(val_samples),
        },
    )
    history_columns = history_rows_to_columns(metrics_cb.rows)
    split_info = build_split_info(ctx.candidate_name, fold, len(train_samples), len(val_samples))
    write_fold_plots(
        fdir,
        history_columns,
        val_metrics,
        aug_metrics,
        split_info=split_info,
        run_params={
            "iteration": ctx.config["run"]["iteration_name"],
            "fingerprint": ctx.training_fingerprint[:12],
            "prune": ctx.config["pruning"]["final_sparsity"] if pruning_enabled else 0.0,
            "quantizer": ctx.model_flavor_label,
        },
        final_epoch=int(ctx.config["training"]["epochs"]),
    )
    write_fold_extra_plots(ctx, fold, val_samples, val_rows, model=stripped_model)
    return {
        "fold": fold,
        "out_dir": fdir,
        "model": stripped_model,
        "metrics": val_metrics,
        "aug_metrics": aug_metrics,
        "history_columns": history_columns,
        "train_samples": train_samples,
        "val_samples": val_samples,
        "final_epoch": int(ctx.config["training"]["epochs"]),
    }


def write_sparsity_report(ctx: FlowContext, model, fold: int) -> tuple[Path, Path | None, dict[str, str]]:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    rows, weights_by_layer, labels, overrides = weight_sparsity(ctx, model)
    out_csv = ctx.run_root / f"sparsity_fold_{fold}.csv"
    write_csv(out_csv, rows)
    plot_path = None
    if weights_by_layer:
        fig = plt.figure(figsize=(10, 6))
        plt.hist(weights_by_layer, bins=np.linspace(-1.2, 1.2, 80), histtype="stepfilled", stacked=True, label=labels, alpha=0.75)
        plt.legend(fontsize=8)
        plt.xlabel("Weight")
        plt.ylabel("Count")
        plt.title(f"{ctx.training_stage} Weights, Fold {fold}")
        fig.tight_layout()
        plot_path = ctx.run_root / f"sparsity_fold_{fold}.png"
        fig.savefig(plot_path, dpi=160)
        plt.close(fig)
    return out_csv, plot_path, overrides


def weight_sparsity(ctx: FlowContext, model) -> tuple[list[dict[str, Any]], list[np.ndarray], list[str], dict[str, str]]:
    rows = []
    weights_by_layer = []
    labels = []
    strategy_overrides = {}
    threshold = int(ctx.config["hls"]["resource_strategy_threshold"])
    resource_strategy = str(ctx.config["hls"]["resource_strategy"])
    default_strategy = str(ctx.config["hls"]["strategy"])
    for layer in model.layers:
        ws = layer.get_weights()
        if not ws:
            continue
        w = np.asarray(ws[0]).reshape(-1)
        n_weights = int(w.size)
        n_nonzero = int(np.count_nonzero(w))
        suggested = resource_strategy if n_nonzero > threshold else default_strategy
        rows.append(
            {
                "layer": layer.name,
                "class": layer.__class__.__name__,
                "n_weights": n_weights,
                "n_nonzero_weights": n_nonzero,
                "zero_fraction": float(np.mean(w == 0.0)),
                "min": float(np.min(w)),
                "max": float(np.max(w)),
                "suggested_hls_strategy": suggested,
            }
        )
        weights_by_layer.append(w)
        labels.append(layer.name)
        strategy_overrides[layer.name] = suggested
    return rows, weights_by_layer, labels, strategy_overrides


def stage_train(ctx: FlowContext, force: bool = False) -> None:
    write_top_manifests(ctx)
    splits = get_splits(ctx)
    active_folds = ctx.active_folds
    if ctx.primary_fold not in active_folds:
        raise ValueError(f"primary_fold={ctx.primary_fold} must be included in run.folds={active_folds}")
    fold_results = {}
    for fold in active_folds:
        fold_results[fold] = train_or_load_fold(ctx, splits, fold, force=force)
    ordered = [fold_results[fold] for fold in active_folds]
    plot_payload = [
        {
            "fold_label": f"fold_{result['fold']}",
            "history": result["history_columns"],
            "final_metrics": result["metrics"],
            "final_aug_metrics": result.get("aug_metrics"),
            "final_epoch": result["final_epoch"],
        }
        for result in ordered
    ]
    write_kfold_plots(
        ctx.run_root,
        plot_payload,
        split_info=(
            f"Candidate: {ctx.candidate_name} | Iteration: {ctx.config['run']['iteration_name']} | "
            f"Fingerprint: {ctx.training_fingerprint[:12]}"
        ),
        run_params={
            "quantizer": ctx.model_flavor_label,
            "prune": ctx.config["pruning"]["final_sparsity"] if ctx.pruning_enabled else 0.0,
            "epochs": ctx.config["training"]["epochs"],
            "batch_size": ctx.config["training"]["batch_size"],
            "lr": ctx.config["training"]["lr"],
        },
    )
    pooled_rows = []
    for fold in active_folds:
        for row in read_csv(fold_dir(ctx, fold) / "per_sample.csv"):
            pooled = dict(row)
            pooled["fold"] = fold
            pooled_rows.append(pooled)
    pooled_dir = ctx.run_root / "pooled"
    write_csv(pooled_dir / "per_sample.csv", pooled_rows)
    write_per_sample_diagnostic_plots(pooled_dir, pooled_rows, title_prefix="Pooled folds")
    pooled_metrics = metrics_from_stage_rows(pooled_rows)
    write_metrics_summary(
        pooled_dir / "metrics_summary.json",
        pooled_metrics,
        extra={"candidate": ctx.candidate_name, "stage": ctx.training_stage, "folds": active_folds},
    )
    primary_model = fold_results[ctx.primary_fold].get("model") or load_fold_model(ctx, ctx.primary_fold)
    write_sparsity_report(ctx, primary_model, ctx.primary_fold)
    write_run_index(ctx)
