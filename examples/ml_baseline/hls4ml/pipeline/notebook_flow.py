"""YAML-driven background runner for the pruned-QAT hls4ml notebook flow."""

from __future__ import annotations

import csv
import hashlib
import json
import math
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Iterable, Sequence

import numpy as np

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")

from .paths import COYOTE_ROOT as DEFAULT_COYOTE_ROOT
from .paths import EXAMPLE_ROOT, ML_BASELINE_ROOT, ensure_ml_baseline_on_path
from .qkeras_plots import build_split_info, history_rows_to_columns, write_fold_plots, write_kfold_plots

ensure_ml_baseline_on_path()

from dataset import bitstream_to_array, load_manifest  # noqa: E402
from train import compute_metrics_from_outputs, save_checkpoint_plots  # noqa: E402


SCALAR_METRIC_KEYS = [
    "bce_loss",
    "log_loss",
    "benign_log_loss",
    "standalone_log_loss",
    "brier_score",
    "accuracy",
    "balanced_accuracy",
    "precision",
    "recall",
    "f1",
    "mcc",
    "ece",
    "roc_auc",
    "pr_auc",
    "optimal_threshold",
    "optimal_accuracy",
    "optimal_f1",
    "benign_mean_score",
    "standalone_mean_score",
]


@dataclass(frozen=True)
class QATTrainConfig:
    candidate_name: str
    quantizer_tag: str
    fold: int
    epochs: int
    batch_size: int
    lr: float
    seed: int
    augment: bool
    flip_h_prob: float
    flip_v_prob: float
    crop_scale_min: float
    translate: float
    cache_data: bool
    max_train_samples: int | None = None
    max_val_samples: int | None = None
    gradcam: bool = False


DEFAULT_CONFIG: dict[str, Any] = {
    "run": {
        "iteration_name": "pruned_qat_w6_a6_s50_rf8",
        "output_root": "artifacts",
        "folds": None,
        "timestamped_root": True,
    },
    "candidate": {
        "name": "cnn_small_hls_opt_img512",
        "img_size": 512,
        "min_ro": 8000,
        "k_folds": 5,
        "primary_fold": 0,
        "seed": 42,
        "balance_classes": True,
    },
    "model": {
        "input_shape": [512, 512, 1],
        "conv_specs": [
            {"filters": 8, "kernel": [5, 5], "strides": [2, 2], "pad": 2, "name": "conv0"},
            {"filters": 16, "kernel": [3, 3], "strides": [1, 1], "pad": 1, "name": "conv1"},
            {"filters": 24, "kernel": [3, 3], "strides": [1, 1], "pad": 1, "name": "conv2"},
            {"filters": 24, "kernel": [3, 3], "strides": [1, 1], "pad": 1, "name": "conv3"},
            {"filters": 32, "kernel": [3, 3], "strides": [1, 1], "pad": 1, "name": "conv4"},
        ],
        "final_avg_pool": [8, 8],
        "output_units": 1,
    },
    "quantization": {
        "tag": "w6_a6",
        "weight_bits": 6,
        "weight_integer": 0,
        "activation_bits": 6,
        "activation_integer": [2, 2, 3, 4, 5],
        "alpha": 1,
    },
    "pruning": {
        "enabled": True,
        "final_sparsity": 0.5,
        "begin_epoch": 2,
        "end_epoch": 300,
        "frequency_epochs": 5,
        "prune_output_dense": False,
    },
    "training": {
        "epochs": 300,
        "batch_size": 16,
        "metrics_every_n_epochs": 1,
        "lr": 1e-4,
        "augment": True,
        "flip_h_prob": 0.5,
        "flip_v_prob": 0.5,
        "crop_scale_min": 1.0,
        "translate": 0.0,
        "cache_data": True,
        "max_train_samples": None,
        "max_val_samples": None,
    },
    "hls": {
        "backend": "Vitis",
        "sweep_name": "rf1",
        "io_type": "io_stream",
        "strategy": "Latency",
        "reuse_factor": 1,
        "resource_strategy_threshold": 4096,
        "resource_strategy": "Resource",
        "clock_period": 5.0,
        "part": "xcu55c-fsvh2892-2L-e",
        "run_csim": True,
        "run_cosim": False,
        "output_precision": None,
        "pool_accum_precision": None,
        "accum_precision": None,
        "n_emulation_samples": None,
        "n_layer_trace_samples": 4,
    },
    "synthesis": {
        "run": True,
    },
    "u55c": {
        "coyote_root": str(DEFAULT_COYOTE_ROOT),
        "build_jobs": None,
        "vfpga_id": 0,
        "abi": {
            "img_size": 512,
            "pixels_per_sample": 512 * 512,
            "axi_data_bits": 512,
            "fixed_width": 16,
            "fixed_integer": 6,
            "fixed_fraction": 10,
            "pixels_per_beat": 32,
            "beats_per_sample": 8192,
            "input_bytes_per_sample": 512 * 512 * 2,
            "output_bytes_per_sample": 64,
        },
    },
    "toolchain": {
        "auto_enable": True,
        "version": "latest",
    },
}


SOURCE_FILES_FOR_FINGERPRINT = [
    ML_BASELINE_ROOT / "dataset.py",
    ML_BASELINE_ROOT / "model.py",
    ML_BASELINE_ROOT / "train.py",
    EXAMPLE_ROOT / "pipeline" / "notebook_flow.py",
    EXAMPLE_ROOT / "pipeline" / "qkeras_plots.py",
]


def deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    out = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = deep_merge(out[key], value)
        else:
            out[key] = value
    return out


def load_config(path: Path) -> dict[str, Any]:
    text = path.read_text()
    try:
        import yaml

        raw = yaml.safe_load(text) or {}
    except ModuleNotFoundError:
        raw = json.loads(text)
    return deep_merge(DEFAULT_CONFIG, raw)


def canonical_json(payload: Any) -> str:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str)


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_payload(payload: Any) -> str:
    return hashlib.sha256(canonical_json(payload).encode()).hexdigest()


def sha256_tree(
    root: Path,
    patterns: tuple[str, ...] = (".cpp", ".h", ".hpp", ".svh", ".txt", ".cmake", "CMakeLists.txt"),
) -> str:
    h = hashlib.sha256()
    root = Path(root)
    if not root.exists():
        return ""
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        if path.name == "CMakeLists.txt" or any(path.name.endswith(pat) for pat in patterns):
            h.update(str(path.relative_to(root)).encode())
            h.update(path.read_bytes())
    return h.hexdigest()


def source_hashes() -> dict[str, str]:
    hashes = {}
    for path in SOURCE_FILES_FOR_FINGERPRINT:
        if path.exists():
            try:
                key = str(path.relative_to(EXAMPLE_ROOT.parent))
            except ValueError:
                key = str(path)
            hashes[key] = file_sha256(path)
    return hashes


def sanitize_label(value: str) -> str:
    label = "".join(ch if ch.isalnum() or ch in {"-", "_"} else "_" for ch in value).strip("_")
    return label or "default"


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True, default=str))


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def write_csv(path: Path, rows: Sequence[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("")
        return
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def metrics_summary_dict(metrics: dict[str, Any]) -> dict[str, Any]:
    summary = {}
    for key in SCALAR_METRIC_KEYS:
        value = metrics.get(key)
        if isinstance(value, np.generic):
            value = value.item()
        summary[key] = value
    cm = metrics.get("confusion_matrix")
    if cm is not None:
        summary["confusion_matrix"] = np.asarray(cm).tolist()
    return summary


def write_metrics_summary(path: Path, metrics: dict[str, Any], extra: dict[str, Any] | None = None) -> None:
    payload = metrics_summary_dict(metrics)
    if extra:
        payload.update(extra)
    write_json(path, payload)


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
        raise ValueError("Pruned QAT flow supports only 2d image candidates")
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


def metrics_from_logits(labels: np.ndarray, logits: np.ndarray) -> dict[str, Any]:
    probs = sigmoid(logits)
    eps = 1e-7
    clipped = np.clip(probs, eps, 1.0 - eps)
    loss = -np.mean(labels * np.log(clipped) + (1.0 - labels) * np.log(1.0 - clipped))
    return compute_metrics_from_outputs(float(loss), labels.astype(np.float32), probs.astype(np.float32))


def write_history(path: Path, rows: Sequence[dict[str, Any]]) -> None:
    write_csv(path, rows)


def write_qkeras_per_sample(path: Path, samples: Sequence[dict], labels: np.ndarray, logits: np.ndarray) -> list[dict[str, Any]]:
    rows = rows_from_logits(samples, labels.astype(int), logits)
    write_csv(path, rows)
    return rows


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def clean_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    return [row for row in read_csv(path) if row.get("sample_index") not in ("sample_index", "", None)]


def run_command(cmd: Sequence[str], cwd: Path, log_path: Path | None = None) -> subprocess.CompletedProcess:
    print("$", " ".join(map(str, cmd)))
    proc = subprocess.run(list(map(str, cmd)), cwd=str(cwd), text=True, capture_output=True)
    if log_path is not None:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text("STDOUT\n" + proc.stdout + "\nSTDERR\n" + proc.stderr)
    if proc.stdout:
        print(proc.stdout[-4000:])
    if proc.stderr:
        print(proc.stderr[-4000:])
    proc.check_returncode()
    return proc


@dataclass
class FlowContext:
    config: dict[str, Any]
    config_path: Path
    run_root: Path
    hls_sweep_root: Path
    training_fingerprint: str
    hls_fingerprint: str
    source_hashes: dict[str, str]

    @property
    def candidate_name(self) -> str:
        return str(self.config["candidate"]["name"])

    @property
    def primary_fold(self) -> int:
        return int(self.config["candidate"]["primary_fold"])

    @property
    def k_folds(self) -> int:
        return int(self.config["candidate"]["k_folds"])

    @property
    def folds(self) -> list[int]:
        return list(range(self.k_folds))

    @property
    def active_folds(self) -> list[int]:
        configured = self.config.get("run", {}).get("folds")
        if configured is None:
            return self.folds
        return [int(fold) for fold in configured]

    @property
    def quantizer_tag(self) -> str:
        return str(self.config["quantization"]["tag"])

    @property
    def hls_sweep_label(self) -> str:
        return sanitize_label(str(self.config["hls"]["sweep_name"]))

    @property
    def hls_project_dir(self) -> Path:
        return self.hls_sweep_root / f"fold_{self.primary_fold}" / "project"

    @property
    def u55c_root(self) -> Path:
        return self.hls_sweep_root / f"fold_{self.primary_fold}" / "u55c_deployment"

    @property
    def prepared_inputs_dir(self) -> Path:
        return self.u55c_root / "prepared_inputs"

    @property
    def validation_dir(self) -> Path:
        return self.hls_sweep_root / f"fold_{self.primary_fold}" / "u55c_validation"

    @property
    def coyote_root(self) -> Path:
        return Path(self.config["u55c"]["coyote_root"]).resolve()

    @property
    def abi(self) -> dict[str, Any]:
        return dict(self.config["u55c"]["abi"])


def build_context(
    config: dict[str, Any],
    config_path: Path,
    run_root_arg: Path | None = None,
    hls_sweep_root_arg: Path | None = None,
) -> FlowContext:
    hashes = source_hashes()
    training_config = {
        key: config[key]
        for key in ("run", "candidate", "model", "quantization", "pruning", "training")
    }
    training_fingerprint = sha256_payload({"training_config": training_config, "source_hashes": hashes})
    hls_fingerprint = sha256_payload(
        {
            "training_fingerprint": training_fingerprint,
            "hls_config": config["hls"],
            "synthesis_config": config.get("synthesis", {}),
            "source_hashes": hashes,
        }
    )
    candidate_name = str(config["candidate"]["name"])
    iteration_name = str(config["run"]["iteration_name"])
    if run_root_arg is not None:
        run_root = run_root_arg.resolve()
    else:
        output_root = Path(config["run"].get("output_root") or "artifacts")
        if not output_root.is_absolute():
            output_root = EXAMPLE_ROOT / output_root
        run_name = f"{iteration_name}_{training_fingerprint[:12]}"
        if bool(config["run"].get("timestamped_root", True)):
            timestamp = os.environ.get("HLS4ML_RUN_TIMESTAMP")
            if not timestamp:
                timestamp = time.strftime("%Y%m%d_%H%M%S")
                os.environ["HLS4ML_RUN_TIMESTAMP"] = timestamp
            run_name = f"{timestamp}_{run_name}"
        run_root = (
            output_root
            / candidate_name
            / "notebook_pruned_qat"
            / run_name
        ).resolve()
    if hls_sweep_root_arg is not None:
        hls_sweep_root = hls_sweep_root_arg.resolve()
    else:
        hls_label = sanitize_label(str(config["hls"]["sweep_name"]))
        hls_sweep_root = run_root / "hls_sweeps" / f"{hls_label}_hls_{hls_fingerprint[:12]}"
    return FlowContext(
        config=config,
        config_path=config_path,
        run_root=run_root,
        hls_sweep_root=hls_sweep_root,
        training_fingerprint=training_fingerprint,
        hls_fingerprint=hls_fingerprint,
        source_hashes=hashes,
    )


def write_top_manifests(ctx: FlowContext) -> None:
    ctx.run_root.mkdir(parents=True, exist_ok=True)
    ctx.hls_sweep_root.mkdir(parents=True, exist_ok=True)
    iteration_manifest = {
        "training_fingerprint": ctx.training_fingerprint,
        "training_short_fingerprint": ctx.training_fingerprint[:12],
        "created_or_reused_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "config_path": str(ctx.config_path),
        "training_config": {
            key: ctx.config[key]
            for key in ("run", "candidate", "model", "quantization", "pruning", "training")
        },
        "source_hashes": ctx.source_hashes,
    }
    old = ctx.run_root / "iteration_manifest.json"
    if old.exists() and read_json(old).get("training_fingerprint") != ctx.training_fingerprint:
        raise RuntimeError(f"Fingerprint collision or stale manifest in {ctx.run_root}")
    write_json(old, iteration_manifest)

    hls_manifest = {
        "training_fingerprint": ctx.training_fingerprint,
        "hls_fingerprint": ctx.hls_fingerprint,
        "hls_sweep_label": ctx.hls_sweep_label,
        "training_root": str(ctx.run_root),
        "hls_sweep_root": str(ctx.hls_sweep_root),
        "created_or_reused_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "hls_config": ctx.config["hls"],
        "synthesis_config": ctx.config.get("synthesis", {}),
        "source_hashes": ctx.source_hashes,
    }
    hls_path = ctx.hls_sweep_root / "hls_sweep_manifest.json"
    if hls_path.exists() and read_json(hls_path).get("hls_fingerprint") != ctx.hls_fingerprint:
        raise RuntimeError(f"Fingerprint collision or stale HLS manifest in {ctx.hls_sweep_root}")
    write_json(hls_path, hls_manifest)


def flow_candidate(ctx: FlowContext) -> SimpleNamespace:
    img_size = int(ctx.config["candidate"]["img_size"])
    return SimpleNamespace(
        name=ctx.candidate_name,
        model=ctx.candidate_name,
        representation="2d",
        img_size=img_size,
        sequence_length=img_size * img_size,
        min_ro=int(ctx.config["candidate"]["min_ro"]),
        target_part=str(ctx.config["hls"]["part"]),
        folds=tuple(ctx.folds),
    )


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


def class_counts(rows: list[dict[str, Any]]) -> dict[int, int]:
    return {label: sum(int(row["class_label"]) == label for row in rows) for label in (0, 1)}


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


def build_qkeras_notebook_model(ctx: FlowContext, name_suffix: str = ""):
    import tensorflow as tf
    from qkeras import QActivation, QConv2D, QDense

    layers = tf.keras.layers
    models = tf.keras.models
    model_cfg = ctx.config["model"]
    x = x_in = layers.Input(shape=tuple(model_cfg["input_shape"]), name="bitstream_input")
    for i, spec in enumerate(model_cfg["conv_specs"]):
        x = layers.ZeroPadding2D(padding=spec["pad"], name=f"pad_{spec['name']}")(x)
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
        x = layers.MaxPooling2D(pool_size=(2, 2), strides=(2, 2), name=f"pool{i}")(x)
    x = layers.AveragePooling2D(
        pool_size=tuple(model_cfg["final_avg_pool"]),
        strides=tuple(model_cfg["final_avg_pool"]),
        name="gap",
    )(x)
    x = layers.Flatten(name="flatten")(x)
    x = QDense(
        int(model_cfg["output_units"]),
        kernel_quantizer=weight_quantizer(ctx),
        bias_quantizer=weight_quantizer(ctx),
        kernel_initializer="lecun_uniform",
        use_bias=True,
        name="output_dense",
    )(x)
    return models.Model(inputs=[x_in], outputs=[x], name=f"qkeras_pruned_qat_{ctx.quantizer_tag}{name_suffix}")


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


def fold_dir(ctx: FlowContext, fold: int) -> Path:
    return ctx.run_root / f"fold_{fold}"


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
    return manifest.get("fingerprint") == ctx.training_fingerprint and manifest.get("fold") == fold


def load_fold_model(ctx: FlowContext, fold: int):
    model = build_qkeras_notebook_model(ctx, name_suffix=f"_fold{fold}")
    model.load_weights(fold_dir(ctx, fold) / "final_weights.weights.h5")
    return model


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
    if not bool(pruning.get("enabled", True)):
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
        metrics = metrics_from_stage_rows(read_csv(fdir / "per_sample.csv"))
        aug_metrics = metrics_from_stage_rows(read_csv(fdir / "augmented_per_sample.csv"))
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

    pruning_enabled = bool(ctx.config["pruning"].get("enabled", True))
    print(f"Fold {fold}: training {'pruned ' if pruning_enabled else ''}QAT model")
    tf.keras.backend.clear_session()
    tf.keras.utils.set_random_seed(int(ctx.config["candidate"]["seed"]) + fold)
    nsteps = math.ceil(len(train_samples) / int(ctx.config["training"]["batch_size"]))
    base_model = build_qkeras_notebook_model(ctx, name_suffix=f"_fold{fold}")
    pruned_model = tf.keras.models.clone_model(base_model, clone_function=prune_function_factory(ctx, nsteps))
    pruned_model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=float(ctx.config["training"]["lr"])),
        loss=tf.keras.losses.BinaryCrossentropy(from_logits=True),
        run_eagerly=True,
    )
    metrics_cb = EpochMetricsCallback(ctx, val_seq, aug_val_seq)
    callbacks = [metrics_cb.callback]
    if pruning_enabled:
        callbacks = [pruning_callbacks.UpdatePruningStep(), *callbacks]
    pruned_model.fit(
        KerasSequenceAdapter(train_seq).adapter,
        epochs=int(ctx.config["training"]["epochs"]),
        validation_data=KerasSequenceAdapter(val_seq).adapter,
        callbacks=callbacks,
        verbose=1,
    )
    stripped_model = tfmot.sparsity.keras.strip_pruning(pruned_model) if pruning_enabled else pruned_model
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
            "stage": "pruned_qat" if pruning_enabled else "qat",
            "candidate": ctx.candidate_name,
            "pruning_enabled": pruning_enabled,
        },
    )
    write_metrics_summary(
        fdir / "augmented_metrics_summary.json",
        aug_metrics,
        extra={
            "fingerprint": ctx.training_fingerprint,
            "fold": fold,
            "stage": "pruned_qat_augmented" if pruning_enabled else "qat_augmented",
            "candidate": ctx.candidate_name,
            "pruning_enabled": pruning_enabled,
        },
    )
    write_qkeras_per_sample(fdir / "per_sample.csv", val_samples, val_labels, val_logits)
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
            "quantizer": ctx.quantizer_tag,
        },
        final_epoch=int(ctx.config["training"]["epochs"]),
    )
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


def sigmoid(logits: np.ndarray) -> np.ndarray:
    logits = np.asarray(logits, dtype=np.float64)
    out = np.empty_like(logits)
    pos = logits >= 0
    out[pos] = 1.0 / (1.0 + np.exp(-logits[pos]))
    exp_x = np.exp(logits[~pos])
    out[~pos] = exp_x / (1.0 + exp_x)
    return out


def binary_log_loss(label: int, prob: float) -> float:
    clipped = min(max(float(prob), 1e-7), 1.0 - 1e-7)
    return -math.log(clipped) if int(label) == 1 else -math.log(1.0 - clipped)


def rows_from_logits(samples: Sequence[dict], labels: Sequence[int], logits: np.ndarray) -> list[dict[str, Any]]:
    probs = sigmoid(np.asarray(logits).reshape(-1))
    rows = []
    for idx, (sample, label, logit, prob) in enumerate(zip(samples, labels, logits, probs)):
        pred = int(prob >= 0.5)
        rows.append(
            {
                "sample_index": idx,
                "sample_id": sample.get("sample_id", ""),
                "app_name": sample.get("app_name", ""),
                "class_label": int(label),
                "class_name": sample.get("class_name", "standalone" if int(label) else "benign"),
                "ro_count": sample.get("ro_count", ""),
                "bitstream_path": sample.get("bitstream_path", ""),
                "logit": f"{float(logit):.9f}",
                "probability": f"{float(prob):.9f}",
                "predicted_label": pred,
                "correct": pred == int(label),
                "per_sample_bce_loss": f"{binary_log_loss(int(label), float(prob)):.9f}",
                "per_sample_log_loss": f"{binary_log_loss(int(label), float(prob)):.9f}",
            }
        )
    return rows


def metrics_from_stage_rows(rows: Sequence[dict[str, Any]]) -> dict:
    labels = np.asarray([int(row["class_label"]) for row in rows], dtype=np.float32)
    probs = np.asarray([float(row["probability"]) for row in rows], dtype=np.float32)
    losses = np.asarray([float(row["per_sample_bce_loss"]) for row in rows], dtype=np.float32)
    return compute_metrics_from_outputs(float(np.mean(losses)), labels, probs)


def public_metrics(metrics: dict[str, Any]) -> dict[str, Any]:
    return {
        key: (value.tolist() if isinstance(value, np.ndarray) else value)
        for key, value in metrics.items()
        if key not in {"labels", "probs", "preds", "reliability_bins"}
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
        plt.title(f"Pruned QAT Weights, Fold {fold}")
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
            "quantizer": ctx.quantizer_tag,
            "prune": ctx.config["pruning"]["final_sparsity"],
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
    pooled_metrics = metrics_from_stage_rows(pooled_rows)
    write_metrics_summary(
        pooled_dir / "metrics_summary.json",
        pooled_metrics,
        extra={"candidate": ctx.candidate_name, "stage": "pruned_qat", "folds": active_folds},
    )
    primary_model = fold_results[ctx.primary_fold].get("model") or load_fold_model(ctx, ctx.primary_fold)
    write_sparsity_report(ctx, primary_model, ctx.primary_fold)
    write_run_index(ctx)


def qkeras_hls_config_for_model(ctx: FlowContext, model) -> dict:
    import hls4ml
    import keras

    hls_cfg = ctx.config["hls"]
    keras_version = keras.__version__
    keras.__version__ = "2.15.0"
    try:
        config = hls4ml.utils.config_from_keras_model(model, granularity="name", backend=str(hls_cfg["backend"]))
    finally:
        keras.__version__ = keras_version
    config.setdefault("Model", {})
    config["Model"]["Strategy"] = str(hls_cfg["strategy"])
    config["Model"]["ReuseFactor"] = int(hls_cfg["reuse_factor"])
    _, _, _, strategy_overrides = weight_sparsity(ctx, model)
    for layer_name, layer_cfg in config.get("LayerName", {}).items():
        layer_cfg["ReuseFactor"] = int(hls_cfg["reuse_factor"])
        layer_cfg["Strategy"] = strategy_overrides.get(layer_name, str(hls_cfg["strategy"]))
        precision = layer_cfg.get("Precision")
        if hls_cfg.get("accum_precision") and isinstance(precision, dict) and "accum" in precision:
            precision["accum"] = hls_cfg["accum_precision"]
    if "output_dense" in config.get("LayerName", {}) and hls_cfg.get("output_precision") is not None:
        config["LayerName"]["output_dense"].setdefault("Precision", {})["result"] = hls_cfg["output_precision"]
    if "gap" in config.get("LayerName", {}) and hls_cfg.get("pool_accum_precision") is not None:
        config["LayerName"]["gap"].setdefault("Precision", {})["accum"] = hls_cfg["pool_accum_precision"]
    return config


def configure_hls_build_options(ctx: FlowContext, project_dir: Path) -> None:
    build_opt_path = project_dir / "build_opt.tcl"
    if not build_opt_path.exists():
        return
    text = build_opt_path.read_text()
    updated = text
    csim = 1 if bool(ctx.config["hls"].get("run_csim", True)) else 0
    cosim = 1 if bool(ctx.config["hls"].get("run_cosim", False)) else 0
    replacements = {
        "    csim       1": f"    csim       {csim}",
        "    csim       0": f"    csim       {csim}",
        "    cosim      1": f"    cosim      {cosim}",
        "    cosim      0": f"    cosim      {cosim}",
        "    validation 1": "    validation 0",
        "    validation 0": "    validation 0",
    }
    for old, new in replacements.items():
        updated = updated.replace(old, new)
    if updated != text:
        build_opt_path.write_text(updated)


def compile_hls_for_fold(ctx: FlowContext, fold: int, model, force: bool = False):
    import hls4ml
    import keras

    out_dir = ctx.hls_sweep_root / f"fold_{fold}" / "project"
    out_dir.mkdir(parents=True, exist_ok=True)
    project_name = (
        f"{ctx.candidate_name}_{ctx.config['run']['iteration_name']}_{ctx.hls_sweep_label}_"
        f"fold{fold}_hls_{ctx.hls_fingerprint[:8]}"
    )
    manifest_path = out_dir / "conversion_manifest.json"
    config = qkeras_hls_config_for_model(ctx, model)
    if not force and manifest_path.exists():
        manifest = read_json(manifest_path)
        if manifest.get("hls_fingerprint") == ctx.hls_fingerprint and (out_dir / "hls4ml_config.yml").exists():
            print(f"Fold {fold}: hls4ml exact cache hit at {out_dir}")
            keras_version = keras.__version__
            keras.__version__ = "2.15.0"
            try:
                hls_model = hls4ml.converters.convert_from_keras_model(
                    model,
                    hls_config=config,
                    output_dir=str(out_dir),
                    project_name=project_name,
                    backend=str(ctx.config["hls"]["backend"]),
                    io_type=str(ctx.config["hls"]["io_type"]),
                    part=str(ctx.config["hls"]["part"]),
                    clock_period=float(ctx.config["hls"]["clock_period"]),
                )
            finally:
                keras.__version__ = keras_version
            configure_hls_build_options(ctx, out_dir)
            hls_model.compile()
            return hls_model, config, out_dir

    keras_version = keras.__version__
    keras.__version__ = "2.15.0"
    try:
        hls_model = hls4ml.converters.convert_from_keras_model(
            model,
            hls_config=config,
            output_dir=str(out_dir),
            project_name=project_name,
            backend=str(ctx.config["hls"]["backend"]),
            io_type=str(ctx.config["hls"]["io_type"]),
            part=str(ctx.config["hls"]["part"]),
            clock_period=float(ctx.config["hls"]["clock_period"]),
        )
    finally:
        keras.__version__ = keras_version
    configure_hls_build_options(ctx, out_dir)
    hls_model.compile()
    write_json(
        manifest_path,
        {
            "training_fingerprint": ctx.training_fingerprint,
            "hls_fingerprint": ctx.hls_fingerprint,
            "fold": fold,
            "project_name": project_name,
            "hls_config": ctx.config["hls"],
            "hls_dir": str(out_dir),
        },
    )
    (out_dir / "full_hls_config.json").write_text(json.dumps(config, indent=2, sort_keys=True, default=str))
    try:
        hls_model.summary()
    except Exception:
        pass
    try:
        hls4ml.utils.plot_model(hls_model, show_shapes=True, show_precision=True, to_file=str(out_dir / "hls4ml_model.png"))
    except Exception as exc:
        print(f"[hls] plot_model failed: {exc}")
    return hls_model, config, out_dir


def validation_arrays_for_fold(ctx: FlowContext, splits: list[tuple[list[dict], list[dict]]], fold: int):
    candidate = flow_candidate(ctx)
    _, val_samples = splits[fold]
    x = np.stack([sample_to_nhwc(sample, candidate) for sample in val_samples]).astype(np.float32)
    labels = np.asarray([int(sample["class_label"]) for sample in val_samples], dtype=np.int32)
    n_samples = ctx.config["hls"].get("n_emulation_samples")
    if n_samples is not None:
        x = x[: int(n_samples)]
        labels = labels[: int(n_samples)]
        val_samples = val_samples[: int(n_samples)]
    return x, labels, val_samples


def parity_dir_for_fold(ctx: FlowContext, fold: int) -> Path:
    return ctx.hls_sweep_root / f"fold_{fold}" / "parity"


def save_stage_eval_artifacts(ctx: FlowContext, fold: int, parity_dir: Path, stage_name: str, metrics: dict, n_train: int, stage_label: str):
    stage_dir = parity_dir / f"{stage_name}_eval"
    stage_dir.mkdir(parents=True, exist_ok=True)
    write_metrics_summary(
        stage_dir / "metrics_summary.json",
        metrics,
        extra={
            "training_fingerprint": ctx.training_fingerprint,
            "hls_fingerprint": ctx.hls_fingerprint,
            "fold": fold,
            "stage": stage_name,
            "candidate": ctx.candidate_name,
        },
    )
    split_info = build_split_info(ctx.candidate_name, fold, n_train, len(metrics["labels"]))
    save_checkpoint_plots(
        str(stage_dir),
        "final",
        metrics,
        aug_metrics=None,
        split_info=split_info,
        run_params={
            "iteration": ctx.config["run"]["iteration_name"],
            "training_fp": ctx.training_fingerprint[:12],
            "hls_fp": ctx.hls_fingerprint[:12],
            "stage": stage_label,
            "reuse_factor": ctx.config["hls"]["reuse_factor"],
        },
    )
    return stage_dir / "final_evaluation_plots.png"


def emulate_fold(ctx: FlowContext, splits: list[tuple[list[dict], list[dict]]], fold: int, model, hls_model, force: bool = False) -> dict:
    parity_dir = parity_dir_for_fold(ctx, fold)
    parity_dir.mkdir(parents=True, exist_ok=True)
    summary_path = parity_dir / "summary.json"
    if not force and summary_path.exists() and read_json(summary_path).get("hls_fingerprint") == ctx.hls_fingerprint:
        print(f"Fold {fold}: parity exact cache hit at {parity_dir}")
        return read_json(summary_path)
    x, labels, val_samples = validation_arrays_for_fold(ctx, splits, fold)
    keras_logits = np.asarray(model.predict(x, verbose=0)).reshape(-1)
    hls_logits = np.asarray(hls_model.predict(np.ascontiguousarray(x))).reshape(-1)
    abs_err = np.abs(hls_logits - keras_logits)
    parity_rows = [
        {
            "idx": idx,
            "label": int(label),
            "keras_logit": float(k_logit),
            "hls_logit": float(h_logit),
            "abs_err": float(err),
            "rel_err": float(err / max(abs(float(k_logit)), 1e-6)),
        }
        for idx, (label, k_logit, h_logit, err) in enumerate(zip(labels, keras_logits, hls_logits, abs_err))
    ]
    write_csv(parity_dir / "parity.csv", parity_rows)
    keras_rows = rows_from_logits(val_samples, labels, keras_logits)
    hls_rows = rows_from_logits(val_samples, labels, hls_logits)
    write_csv(parity_dir / "qkeras_per_sample.csv", keras_rows)
    write_csv(parity_dir / "hls_per_sample.csv", hls_rows)
    keras_metrics = metrics_from_stage_rows(keras_rows)
    hls_metrics = metrics_from_stage_rows(hls_rows)
    qkeras_plot = save_stage_eval_artifacts(ctx, fold, parity_dir, "qkeras", keras_metrics, len(splits[fold][0]), "QKeras parity reference")
    hls_plot = save_stage_eval_artifacts(ctx, fold, parity_dir, "hls", hls_metrics, len(splits[fold][0]), "hls4ml bit-accurate")
    summary = {
        "training_fingerprint": ctx.training_fingerprint,
        "hls_fingerprint": ctx.hls_fingerprint,
        "fold": fold,
        "n": int(len(labels)),
        "logit_mae": float(abs_err.mean()),
        "logit_max_abs": float(abs_err.max()),
        "sign_mismatches": int(np.sum((keras_logits >= 0.0) != (hls_logits >= 0.0))),
        "qkeras_accuracy": float(keras_metrics["accuracy"]),
        "hls_accuracy": float(hls_metrics["accuracy"]),
        "qkeras_pr_auc": float(keras_metrics["pr_auc"]),
        "hls_pr_auc": float(hls_metrics["pr_auc"]),
        "qkeras_eval_plot": str(qkeras_plot),
        "hls_eval_plot": str(hls_plot),
    }
    write_json(summary_path, summary)
    return summary


def layer_precision_rows(config: dict) -> dict[str, dict[str, Any]]:
    rows = {}
    for name, layer_cfg in config.get("LayerName", {}).items():
        precision = layer_cfg.get("Precision", {})
        rows[name] = {
            "reuse_factor": layer_cfg.get("ReuseFactor"),
            "result_precision": precision.get("result") if isinstance(precision, dict) else precision,
            "accum_precision": precision.get("accum") if isinstance(precision, dict) else None,
            "weight_precision": precision.get("weight") if isinstance(precision, dict) else None,
        }
    return rows


def summarize_layer_divergence(k_trace, h_trace, precision_map) -> list[dict[str, Any]]:
    rows = []
    for layer_name, hls_out in h_trace.items():
        if layer_name not in k_trace:
            continue
        keras_out = np.asarray(k_trace[layer_name], dtype=np.float64)
        hls_out = np.asarray(hls_out, dtype=np.float64)
        if keras_out.shape != hls_out.shape:
            print(f"Skipping {layer_name}: shape mismatch {keras_out.shape} vs {hls_out.shape}")
            continue
        diff = hls_out - keras_out
        flat_diff = diff.reshape(diff.shape[0], -1)
        flat_keras = keras_out.reshape(keras_out.shape[0], -1)
        abs_diff = np.abs(flat_diff)
        rmse_per_sample = np.sqrt(np.mean(np.square(flat_diff), axis=1))
        keras_rms = np.sqrt(np.mean(np.square(flat_keras), axis=1))
        precision = precision_map.get(layer_name, {})
        rows.append(
            {
                "layer": layer_name,
                "shape": str(tuple(keras_out.shape[1:])),
                "n_values_per_sample": int(np.prod(keras_out.shape[1:])),
                "mean_abs_qkeras": float(np.mean(np.abs(flat_keras))),
                "mae": float(np.mean(abs_diff)),
                "rmse": float(np.mean(rmse_per_sample)),
                "max_abs": float(np.max(abs_diff)),
                "rel_rmse": float(np.mean(rmse_per_sample / np.maximum(keras_rms, 1e-12))),
                "cosine_similarity": float(
                    np.mean(
                        np.sum(flat_keras * hls_out.reshape(hls_out.shape[0], -1), axis=1)
                        / (
                            np.linalg.norm(flat_keras, axis=1)
                            * np.linalg.norm(hls_out.reshape(hls_out.shape[0], -1), axis=1)
                            + 1e-12
                        )
                    )
                ),
                "reuse_factor": precision.get("reuse_factor"),
                "result_precision": precision.get("result_precision"),
                "accum_precision": precision.get("accum_precision"),
                "weight_precision": precision.get("weight_precision"),
            }
        )
    return sorted(rows, key=lambda row: (row["rmse"], row["max_abs"]), reverse=True)


def compute_layer_trace_divergence(ctx: FlowContext, splits, fold: int, model, hls_model, hls_config: dict, force: bool = False) -> Path:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import tensorflow as tf

    n_trace = ctx.config["hls"].get("n_layer_trace_samples")
    tag = "all" if n_trace is None else f"n{int(n_trace)}"
    trace_dir = parity_dir_for_fold(ctx, fold) / f"layer_trace_{tag}"
    trace_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = trace_dir / "trace_manifest.json"
    summary_path = trace_dir / "layer_divergence_summary.csv"
    x_trace, _, trace_samples = validation_arrays_for_fold(ctx, splits, fold)
    if n_trace is not None:
        x_trace = x_trace[: int(n_trace)]
        trace_samples = trace_samples[: int(n_trace)]
    x_trace = np.ascontiguousarray(x_trace)
    if not force and manifest_path.exists() and summary_path.exists():
        manifest = read_json(manifest_path)
        if (
            manifest.get("hls_fingerprint") == ctx.hls_fingerprint
            and manifest.get("fold") == fold
            and manifest.get("n_trace_samples") == int(len(x_trace))
        ):
            print(f"Fold {fold}: layer-trace exact cache hit at {trace_dir}")
            return trace_dir
    for layer in hls_model.get_layers():
        if layer.get_attr("function_cpp", None):
            layer.set_attr("trace", True)
    _, hls_trace = hls_model.trace(x_trace)
    trace_names = [name for name in hls_trace.keys() if name in {layer.name for layer in model.layers}]
    keras_trace_model = tf.keras.Model(inputs=model.input, outputs=[model.get_layer(name).output for name in trace_names])
    keras_outputs = keras_trace_model.predict(x_trace, verbose=0)
    if not isinstance(keras_outputs, list):
        keras_outputs = [keras_outputs]
    keras_trace = {name: output for name, output in zip(trace_names, keras_outputs)}
    rows = summarize_layer_divergence(keras_trace, hls_trace, layer_precision_rows(hls_config))
    write_csv(summary_path, rows)
    write_json(
        manifest_path,
        {
            "training_fingerprint": ctx.training_fingerprint,
            "hls_fingerprint": ctx.hls_fingerprint,
            "fold": fold,
            "n_trace_samples": int(len(x_trace)),
            "sample_ids": [sample.get("sample_id", "") for sample in trace_samples],
        },
    )
    if rows:
        top_rmse = sorted(rows, key=lambda row: row["rmse"])[-min(12, len(rows)) :]
        top_max = sorted(rows, key=lambda row: row["max_abs"])[-min(12, len(rows)) :]
        fig, axes = plt.subplots(1, 2, figsize=(14, 6))
        axes[0].barh([row["layer"] for row in top_rmse], [row["rmse"] for row in top_rmse])
        axes[0].set_title("Top Layer RMSE")
        axes[0].set_xlabel("RMSE")
        axes[1].barh([row["layer"] for row in top_max], [row["max_abs"] for row in top_max])
        axes[1].set_title("Top Layer Max Abs Error")
        axes[1].set_xlabel("Max |HLS - QKeras|")
        fig.suptitle(f"Primary-Fold Layer Divergence (n={len(rows)} traced layers)")
        fig.tight_layout()
        fig.savefig(trace_dir / "layer_divergence.png", dpi=160)
        plt.close(fig)
    return trace_dir


def find_csynth_report(project_dir: Path) -> Path | None:
    candidates = sorted(Path(project_dir).glob("*_prj/solution1/syn/report/*_csynth.rpt"))
    if not candidates:
        return None
    project_reports = []
    for path in candidates:
        prj_dir = path.parents[3].name if len(path.parents) >= 4 else ""
        prj_prefix = prj_dir[:-4] if prj_dir.endswith("_prj") else prj_dir
        if prj_prefix and path.name.startswith(prj_prefix):
            project_reports.append(path)
    top = [path for path in candidates if "_hls_csynth" in path.name or path.name == "csynth.rpt"]
    chosen = project_reports or top or candidates
    return chosen[0]


def parse_csynth_report(report_path: Path | None) -> dict[str, Any]:
    if report_path is None or not Path(report_path).exists():
        return {}
    text = Path(report_path).read_text(errors="ignore").splitlines()
    out: dict[str, Any] = {"report": str(report_path)}
    in_timing_summary = False
    in_latency_summary = False
    in_utilization = False
    for i, line in enumerate(text):
        if line.strip().startswith("+ Timing:"):
            in_timing_summary = True
        if line.strip().startswith("+ Latency:"):
            in_latency_summary = True
        if line.strip().startswith("+ Detail:"):
            in_timing_summary = False
            in_latency_summary = False
        if "== Utilization Estimates" in line:
            in_utilization = True
        if in_timing_summary and line.strip().startswith("|ap_clk"):
            parts = [part.strip() for part in line.split("|")]
            nums = [part for part in parts if part.endswith("ns")]
            if len(nums) >= 3:
                out["target_clock_ns"] = nums[0]
                out["estimated_clock_ns"] = nums[1]
                out["clock_uncertainty_ns"] = nums[2]
        if in_latency_summary and "Latency (cycles)" in line:
            for row in text[i + 1 : i + 10]:
                parts = [part.strip() for part in row.split("|")]
                nums = [part for part in parts if part.replace("-", "").replace(".", "").isdigit()]
                if len(nums) >= 2:
                    out["latency_min_cycles"] = int(float(nums[0]))
                    out["latency_max_cycles"] = int(float(nums[1]))
                    break
        if in_latency_summary and "Latency (absolute)" in line:
            for row in text[i + 1 : i + 10]:
                parts = [part.strip() for part in row.split("|")]
                nums = [part for part in parts if re.match(r"^[0-9.]+\s*(ns|us|ms|s)$", part)]
                raw_nums = [part for part in parts if part.replace("-", "").replace(".", "").isdigit()]
                if len(nums) >= 2 and len(raw_nums) >= 3:
                    out["latency_absolute_min"] = nums[0]
                    out["latency_absolute_max"] = nums[1]
                    out["interval_cycles"] = int(float(raw_nums[2]))
                    break
        if in_utilization and line.startswith("|Total"):
            parts = [part.strip() for part in line.split("|")]
            if len(parts) >= 7:
                out["util_bram_18k"] = int(parts[2])
                out["util_dsp"] = int(parts[3])
                out["util_ff"] = int(parts[4])
                out["util_lut"] = int(parts[5])
                out["util_uram"] = int(parts[6])
            in_utilization = False
    return out


def write_hls_metrics_summary(ctx: FlowContext, row: dict[str, Any]) -> None:
    hls_metrics = {
        "training_fingerprint": ctx.training_fingerprint,
        "hls_fingerprint": ctx.hls_fingerprint,
        "run_root": str(ctx.run_root),
        "hls_sweep_root": str(ctx.hls_sweep_root),
        "fold": int(row.get("fold", ctx.primary_fold)),
        "cached": bool(row.get("cached", False)),
        "report": row.get("report"),
        "target_clock_ns": row.get("target_clock_ns"),
        "estimated_clock_ns": row.get("estimated_clock_ns"),
        "clock_uncertainty_ns": row.get("clock_uncertainty_ns"),
        "latency_min_cycles": row.get("latency_min_cycles"),
        "latency_max_cycles": row.get("latency_max_cycles"),
        "latency_absolute_min": row.get("latency_absolute_min"),
        "latency_absolute_max": row.get("latency_absolute_max"),
        "interval_cycles": row.get("interval_cycles"),
        "util_bram_18k": row.get("util_bram_18k"),
        "util_dsp": row.get("util_dsp"),
        "util_ff": row.get("util_ff"),
        "util_lut": row.get("util_lut"),
        "util_uram": row.get("util_uram"),
    }
    json_path = ctx.hls_sweep_root / "hls_metrics_summary.json"
    csv_path = ctx.hls_sweep_root / "hls_metrics_summary.csv"
    write_json(json_path, hls_metrics)
    write_csv(csv_path, [hls_metrics])


def synthesize_fold_if_needed(ctx: FlowContext, fold: int, force: bool = False) -> dict[str, Any]:
    project_dir = ctx.hls_sweep_root / f"fold_{fold}" / "project"
    synth_manifest = project_dir / "synthesis_manifest.json"
    report = find_csynth_report(project_dir)
    if not force and synth_manifest.exists() and report is not None:
        manifest = read_json(synth_manifest)
        if manifest.get("hls_fingerprint") == ctx.hls_fingerprint:
            print(f"Fold {fold}: synthesis exact cache hit")
            row = {"fold": fold, "project_dir": str(project_dir), "cached": True}
            row.update(parse_csynth_report(report))
            return row
    if shutil.which("vitis_hls") is None:
        raise RuntimeError("vitis_hls is not on PATH; enable Vitis or use toolchain.auto_enable.")
    if not (project_dir / "build_prj.tcl").exists():
        raise FileNotFoundError(f"Missing build_prj.tcl in {project_dir}")
    configure_hls_build_options(ctx, project_dir)
    run_command(["vitis_hls", "-f", "build_prj.tcl"], cwd=project_dir, log_path=project_dir / "vitis_hls.log")
    report = find_csynth_report(project_dir)
    write_json(
        synth_manifest,
        {
            "training_fingerprint": ctx.training_fingerprint,
            "hls_fingerprint": ctx.hls_fingerprint,
            "fold": fold,
            "completed_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        },
    )
    row = {"fold": fold, "project_dir": str(project_dir), "cached": False}
    row.update(parse_csynth_report(report))
    return row


def stage_hls(ctx: FlowContext, force: bool = False) -> None:
    write_top_manifests(ctx)
    splits = get_splits(ctx)
    fold = ctx.primary_fold
    if not fold_cache_valid(ctx, fold):
        raise FileNotFoundError(f"Missing trained primary fold; run train first: {fold_dir(ctx, fold)}")
    model = load_fold_model(ctx, fold)
    hls_model, hls_config, project_dir = compile_hls_for_fold(ctx, fold, model, force=force)
    emulate_fold(ctx, splits, fold, model, hls_model, force=force)
    compute_layer_trace_divergence(ctx, splits, fold, model, hls_model, hls_config, force=force)
    if bool(ctx.config.get("synthesis", {}).get("run", True)):
        row = synthesize_fold_if_needed(ctx, fold, force=force)
        write_csv(ctx.hls_sweep_root / "synthesis_summary.csv", [row])
        write_hls_metrics_summary(ctx, row)
    write_run_index(ctx)


def bitstream_to_sequence(bin_path: Path, sequence_length: int, invert: bool = True) -> np.ndarray:
    data = np.fromfile(bin_path, dtype=np.uint8)
    if len(data) <= sequence_length:
        window = np.zeros(sequence_length, dtype=np.uint8)
        window[: len(data)] = data
    else:
        indices = np.linspace(0, len(data) - 1, sequence_length, dtype=np.int64)
        window = data[indices]
    return 255 - window if invert else window


def sample_to_nhwc_for_u55c(ctx: FlowContext, row: dict[str, Any]) -> np.ndarray:
    img_size = int(ctx.config["candidate"]["img_size"])
    bin_path = Path(row["_bitstream_dir"]) / row["bitstream_path"]
    seq = bitstream_to_sequence(bin_path, img_size * img_size, invert=True)
    return (seq.reshape(img_size, img_size).astype(np.float32) / 255.0)[..., np.newaxis]


def fixed16_from_float(ctx: FlowContext, x: np.ndarray) -> np.ndarray:
    abi = ctx.abi
    scale = 1 << int(abi["fixed_fraction"])
    q = np.rint(np.asarray(x, dtype=np.float64) * scale)
    return np.clip(q, -(1 << 15), (1 << 15) - 1).astype("<i2")


def float_from_fixed16(ctx: FlowContext, q: np.ndarray) -> np.ndarray:
    return q.astype(np.float32) / float(1 << int(ctx.abi["fixed_fraction"]))


def prepare_u55c_inputs(ctx: FlowContext, splits, force: bool = False) -> None:
    fold = ctx.primary_fold
    _, val_samples = splits[fold]
    sample_ids = [row["sample_id"] for row in val_samples]
    input_fingerprint = {
        "training_fingerprint": ctx.training_fingerprint,
        "hls_fingerprint": ctx.hls_fingerprint,
        "fold": fold,
        "sample_ids": sample_ids,
        "abi": ctx.abi,
    }
    manifest_path = ctx.prepared_inputs_dir / "manifest.json"
    csv_manifest_path = ctx.prepared_inputs_dir / "manifest.csv"
    if not force and manifest_path.exists() and read_json(manifest_path).get("fingerprint") == input_fingerprint:
        print(f"prepared input cache hit: {ctx.prepared_inputs_dir}")
        return
    ctx.prepared_inputs_dir.mkdir(parents=True, exist_ok=True)
    rows = []
    all_x = []
    labels = []
    for idx, row in enumerate(val_samples):
        x = sample_to_nhwc_for_u55c(ctx, row).astype(np.float32)
        flat = x.reshape(-1)
        if flat.size != int(ctx.abi["pixels_per_sample"]):
            raise ValueError(f"unexpected input size {flat.size}")
        fixed = fixed16_from_float(ctx, flat)
        blob = ctx.prepared_inputs_dir / f"sample_{idx:04d}.bin"
        fixed.tofile(blob)
        all_x.append(x)
        labels.append(int(row["class_label"]))
        rows.append(
            {
                "sample_index": idx,
                "sample_id": row.get("sample_id", ""),
                "class_label": int(row["class_label"]),
                "class_name": row.get("class_name", "standalone" if int(row["class_label"]) else "benign"),
                "app_name": row.get("app_name", ""),
                "ro_count": row.get("ro_count", ""),
                "bitstream_path": row.get("bitstream_path", ""),
                "input_path": str(blob),
                "input_sha256": file_sha256(blob),
                "input_bytes": blob.stat().st_size,
            }
        )
    np.save(ctx.prepared_inputs_dir / "x_norm.npy", np.stack(all_x))
    np.save(ctx.prepared_inputs_dir / "labels.npy", np.asarray(labels, dtype=np.int32))
    write_csv(csv_manifest_path, rows)
    write_json(
        manifest_path,
        {
            "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "fingerprint": input_fingerprint,
            "csv_manifest": str(csv_manifest_path),
            "n_samples": len(rows),
            "input_bytes_per_sample": ctx.abi["input_bytes_per_sample"],
        },
    )


def rewrite_includes(text: str) -> str:
    text = text.replace('"nnet_utils/', '"').replace('"weights/', '"')
    return "\n".join(line for line in text.splitlines() if "#pragma HLS INTERFACE axis port=" not in line) + "\n"


def find_top_header(project_dir: Path, project_name: str) -> Path:
    header = project_dir / "firmware" / f"{project_name}.h"
    if header.exists():
        return header
    headers = sorted((project_dir / "firmware").glob("*.h"))
    matches = [path for path in headers if "defines" not in path.name and "parameters" not in path.name]
    if not matches:
        raise FileNotFoundError("could not find hls4ml top header")
    return matches[0]


def stage_kernel_sources(ctx: FlowContext, staged_hw_dir: Path) -> dict[str, Any]:
    conv = read_json(ctx.hls_project_dir / "conversion_manifest.json")
    project_name = conv["project_name"]
    firmware = ctx.hls_project_dir / "firmware"
    top_header = find_top_header(ctx.hls_project_dir, project_name)
    top_cpp = firmware / f"{top_header.stem}.cpp"
    if not top_cpp.exists():
        raise FileNotFoundError(top_cpp)
    kernel_dir = staged_hw_dir / "src" / "hls" / "coyote_qkeras_infer"
    if kernel_dir.exists():
        shutil.rmtree(kernel_dir)
    kernel_dir.mkdir(parents=True, exist_ok=True)
    srcs = list(firmware.glob("*.h")) + list(firmware.glob("*.hpp")) + list(firmware.glob("*.cpp"))
    srcs += list((firmware / "nnet_utils").glob("*.h")) + list((firmware / "nnet_utils").glob("*.hpp"))
    srcs += list((firmware / "weights").glob("*.h"))
    for src in srcs:
        (kernel_dir / src.name).write_text(rewrite_includes(src.read_text(errors="ignore")))
    abi = ctx.abi
    header = f"""
#pragma once

#include "ap_axi_sdata.h"
#include "ap_fixed.h"
#include "ap_int.h"
#include "hls_stream.h"

constexpr int AXI_DATA_BITS = {int(abi['axi_data_bits'])};
constexpr int INPUT_PIXELS = {int(abi['pixels_per_sample'])};
constexpr int FIXED_WIDTH = {int(abi['fixed_width'])};
constexpr int PIXELS_PER_BEAT = AXI_DATA_BITS / FIXED_WIDTH;
constexpr int INPUT_BEATS = INPUT_PIXELS / PIXELS_PER_BEAT;

typedef ap_axiu<AXI_DATA_BITS, 0, 0, 0> axi_s;
typedef ap_fixed<{int(abi['fixed_width'])},{int(abi['fixed_integer'])}> packed_input_t;
typedef ap_fixed<{int(abi['fixed_width'])},{int(abi['fixed_integer'])}> packed_output_t;

void coyote_qkeras_infer(hls::stream<axi_s> &s_axi_in, hls::stream<axi_s> &m_axi_out);
""".strip()
    (kernel_dir / "coyote_qkeras_infer.hpp").write_text(header + "\n")
    wrapper = f"""
#include "coyote_qkeras_infer.hpp"
#include "{top_header.name}"
#include "{top_cpp.name}"

static void read_input_frame(hls::stream<axi_s> &s_axi_in, hls::stream<input_t> &nn_in) {{
    #pragma HLS INLINE off
    for (int beat = 0; beat < INPUT_BEATS; ++beat) {{
        axi_s word = s_axi_in.read();
        for (int lane = 0; lane < PIXELS_PER_BEAT; ++lane) {{
            #pragma HLS PIPELINE II=1
            ap_int<FIXED_WIDTH> raw = word.data.range((lane + 1) * FIXED_WIDTH - 1, lane * FIXED_WIDTH);
            input_t item;
            packed_input_t value;
            value.range(FIXED_WIDTH - 1, 0) = raw;
            item[0] = value;
            nn_in.write(item);
        }}
    }}
}}

static void run_network(hls::stream<input_t> &nn_in, hls::stream<result_t> &nn_out) {{
    #pragma HLS INLINE off
    {top_header.stem}(nn_in, nn_out);
}}

static void write_output_frame(hls::stream<result_t> &nn_out, hls::stream<axi_s> &m_axi_out) {{
    #pragma HLS INLINE off
    result_t y = nn_out.read();
    axi_s out_word;
    out_word.data = 0;
    out_word.keep = -1;
    out_word.last = 1;
    packed_output_t out_value = y[0];
    out_word.data.range(FIXED_WIDTH - 1, 0) = out_value.range(FIXED_WIDTH - 1, 0);
    m_axi_out.write(out_word);
}}

void coyote_qkeras_infer(hls::stream<axi_s> &s_axi_in, hls::stream<axi_s> &m_axi_out) {{
    #pragma HLS INTERFACE ap_ctrl_hs port=return
    #pragma HLS INTERFACE axis register port=s_axi_in name=s_axi_in
    #pragma HLS INTERFACE axis register port=m_axi_out name=m_axi_out
    #pragma HLS DATAFLOW

    hls::stream<input_t> nn_in("nn_in");
    hls::stream<result_t> nn_out("nn_out");
    #pragma HLS STREAM variable=nn_in depth=1024
    #pragma HLS STREAM variable=nn_out depth=2

    read_input_frame(s_axi_in, nn_in);
    run_network(nn_in, nn_out);
    write_output_frame(nn_out, m_axi_out);
}}
""".strip()
    (kernel_dir / "coyote_qkeras_infer.cpp").write_text(wrapper + "\n")
    return {"kernel_dir": str(kernel_dir), "top_function": top_header.stem, "flattened_files": len(list(kernel_dir.iterdir()))}


def stage_coyote_hw_sw(ctx: FlowContext, force: bool = False) -> dict[str, Any]:
    staged_hw_dir = ctx.u55c_root / "coyote_hw"
    staged_sw_dir = ctx.u55c_root / "coyote_sw"
    staged_hw_dir.mkdir(parents=True, exist_ok=True)
    staged_sw_dir.mkdir(parents=True, exist_ok=True)
    src_dir = staged_hw_dir / "src"
    src_dir.mkdir(parents=True, exist_ok=True)
    kernel_info = stage_kernel_sources(ctx, staged_hw_dir)
    (staged_hw_dir / "CMakeLists.txt").write_text(
        f"""
cmake_minimum_required(VERSION 3.5)
set(CYT_DIR {ctx.coyote_root})
set(CMAKE_MODULE_PATH ${{CMAKE_MODULE_PATH}} ${{CYT_DIR}}/cmake)
find_package(CoyoteHW REQUIRED)

project(u55c_qkeras_hls4ml_infer)
message("*** Coyote U55C QKeras hls4ml inference [Hardware] ***")

set(EN_STRM 1)
set(N_STRM_AXI 1)
set(EN_MEM 0)
set(N_REGIONS 1)

validation_checks_hw()
load_apps(VFPGA_C0_0 "src")
create_hw()
""".strip()
        + "\n"
    )
    (src_dir / "vfpga_top.svh").write_text(
        """
coyote_qkeras_infer_hls_ip inst_coyote_qkeras_infer(
    .s_axi_in_TDATA         (axis_host_recv[0].tdata),
    .s_axi_in_TKEEP         (axis_host_recv[0].tkeep),
    .s_axi_in_TLAST         (axis_host_recv[0].tlast),
    .s_axi_in_TSTRB         (0),
    .s_axi_in_TVALID        (axis_host_recv[0].tvalid),
    .s_axi_in_TREADY        (axis_host_recv[0].tready),
    .m_axi_out_TDATA        (axis_host_send[0].tdata),
    .m_axi_out_TKEEP        (axis_host_send[0].tkeep),
    .m_axi_out_TLAST        (axis_host_send[0].tlast),
    .m_axi_out_TSTRB        (),
    .m_axi_out_TVALID       (axis_host_send[0].tvalid),
    .m_axi_out_TREADY       (axis_host_send[0].tready),
    .ap_clk                 (aclk),
    .ap_rst_n               (aresetn),
    .ap_start               (1'b1),
    .ap_done                (),
    .ap_idle                (),
    .ap_ready               ()
);

always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb notify.tie_off_m();
always_comb axi_ctrl.tie_off_s();
""".strip()
        + "\n"
    )
    sw_src = staged_sw_dir / "src"
    sw_src.mkdir(parents=True, exist_ok=True)
    (staged_sw_dir / "CMakeLists.txt").write_text(
        f"""
cmake_minimum_required(VERSION 3.5)
project(u55c_qkeras_hls4ml_infer_host)
set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
set(CMAKE_CXX_STANDARD 17)
add_subdirectory({ctx.coyote_root}/sw ${{CMAKE_BINARY_DIR}}/coyote)
add_executable(coyote_qkeras_host src/main.cpp)
target_link_libraries(coyote_qkeras_host PUBLIC Coyote)
find_package(Boost REQUIRED COMPONENTS program_options)
target_link_libraries(coyote_qkeras_host PUBLIC Boost::program_options)
""".strip()
        + "\n"
    )
    abi = ctx.abi
    vfpga_id = int(ctx.config["u55c"].get("vfpga_id", 0))
    (sw_src / "main.cpp").write_text(
        f"""
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
	#include <sstream>
	#include <stdexcept>
	#include <string>
	#include <thread>
	#include <vector>
#include <unistd.h>

#include <boost/program_options.hpp>
#include <coyote/cThread.hpp>

namespace {{
constexpr uint INPUT_BYTES = {int(abi['input_bytes_per_sample'])};
constexpr uint RESULT_BYTES = {int(abi['output_bytes_per_sample'])};
constexpr int DEFAULT_VFPGA_ID = {vfpga_id};

std::vector<std::string> split_csv_line(const std::string &line) {{
    std::vector<std::string> out;
    std::stringstream ss(line);
    std::string item;
    while (std::getline(ss, item, ',')) out.push_back(item);
    return out;
}}

struct Sample {{
    int sample_index;
    std::string input_path;
}};

std::vector<Sample> read_manifest(const std::string &path) {{
    std::ifstream f(path);
    if (!f) throw std::runtime_error("Could not open manifest: " + path);
    std::string header;
    std::getline(f, header);
    auto fields = split_csv_line(header);
    int idx_col = -1, path_col = -1;
    for (int i = 0; i < static_cast<int>(fields.size()); ++i) {{
        if (fields[i] == "sample_index") idx_col = i;
        if (fields[i] == "input_path") path_col = i;
    }}
    if (idx_col < 0 || path_col < 0) throw std::runtime_error("Manifest requires sample_index,input_path columns");
    std::vector<Sample> samples;
    std::string line;
    while (std::getline(f, line)) {{
        if (line.empty()) continue;
        auto cols = split_csv_line(line);
        if (static_cast<int>(cols.size()) <= std::max(idx_col, path_col)) continue;
        samples.push_back({{std::stoi(cols[idx_col]), cols[path_col]}});
    }}
    return samples;
}}
}}

int main(int argc, char *argv[]) {{
	    std::string manifest_path;
	    std::string output_csv;
	    int vfpga_id = DEFAULT_VFPGA_ID;
	    int max_samples = -1;
	    double timeout_s = 30.0;
	    boost::program_options::options_description opts("U55C hls4ml inference options");
	    opts.add_options()
	        ("manifest,m", boost::program_options::value<std::string>(&manifest_path)->required(), "prepared_inputs/manifest.csv")
	        ("output,o", boost::program_options::value<std::string>(&output_csv)->required(), "hardware_per_sample.csv")
	        ("vfpga", boost::program_options::value<int>(&vfpga_id)->default_value(DEFAULT_VFPGA_ID), "vFPGA id")
	        ("max-samples", boost::program_options::value<int>(&max_samples)->default_value(-1), "limit samples for debug runs")
	        ("timeout-s", boost::program_options::value<double>(&timeout_s)->default_value(30.0), "per-sample timeout in seconds");
    boost::program_options::variables_map args;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, opts), args);
    boost::program_options::notify(args);

	    auto samples = read_manifest(manifest_path);
	    std::ofstream out(output_csv);
	    out << "sample_index,logit_fixed_raw,logit,latency_us\\n";
	    out.flush();

    coyote::cThread coyote_thread(vfpga_id, getpid());
    auto *input_mem = reinterpret_cast<unsigned char *>(coyote_thread.getMem({{coyote::CoyoteAllocType::HPF, INPUT_BYTES}}));
    auto *output_mem = reinterpret_cast<unsigned char *>(coyote_thread.getMem({{coyote::CoyoteAllocType::HPF, RESULT_BYTES}}));
    if (!input_mem || !output_mem) throw std::runtime_error("Could not allocate Coyote buffers");

	    int processed = 0;
	    for (const auto &sample : samples) {{
	        if (max_samples >= 0 && processed >= max_samples) break;
	        std::cout << "starting sample=" << sample.sample_index << std::endl;
	        std::fill(input_mem, input_mem + INPUT_BYTES, 0);
        std::fill(output_mem, output_mem + RESULT_BYTES, 0);
        std::ifstream input_file(sample.input_path, std::ios::binary);
        if (!input_file) throw std::runtime_error("Could not open input blob: " + sample.input_path);
        input_file.read(reinterpret_cast<char *>(input_mem), INPUT_BYTES);
        if (input_file.gcount() != INPUT_BYTES) throw std::runtime_error("Short input blob: " + sample.input_path);

	        coyote::localSg sg_in = {{.addr = input_mem, .len = INPUT_BYTES, .dest = 0}};
	        coyote::localSg sg_out = {{.addr = output_mem, .len = RESULT_BYTES, .dest = 0}};
	        coyote_thread.clearCompleted();
	        auto t0 = std::chrono::high_resolution_clock::now();
	        coyote_thread.invoke(coyote::CoyoteOper::LOCAL_TRANSFER, sg_in, sg_out);
	        uint32_t done = 0;
	        while ((done = coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_TRANSFER)) != 1) {{
	            auto now = std::chrono::high_resolution_clock::now();
	            double elapsed_s = std::chrono::duration<double>(now - t0).count();
	            if (elapsed_s > timeout_s) {{
	                throw std::runtime_error("Timed out waiting for LOCAL_TRANSFER completion; completed=" + std::to_string(done));
	            }}
	            std::this_thread::sleep_for(std::chrono::milliseconds(1));
	        }}
	        auto t1 = std::chrono::high_resolution_clock::now();

        int16_t raw = 0;
        std::memcpy(&raw, output_mem, sizeof(raw));
	        double logit = static_cast<double>(raw) / {float(1 << int(abi['fixed_fraction']))};
	        double latency_us = std::chrono::duration<double, std::micro>(t1 - t0).count();
	        out << sample.sample_index << "," << raw << "," << std::setprecision(12) << logit << "," << latency_us << "\\n";
	        out.flush();
	        std::cout << "sample=" << sample.sample_index << " logit=" << logit << " latency_us=" << latency_us << std::endl;
	        processed++;
	    }}
    return 0;
}}
""".strip()
        + "\n"
    )
    return {**kernel_info, "hw_dir": str(staged_hw_dir), "sw_dir": str(staged_sw_dir)}


def stage_bitstream(ctx: FlowContext, force: bool = False) -> None:
    if not (ctx.hls_project_dir / "conversion_manifest.json").exists():
        raise FileNotFoundError(f"Missing HLS project; run hls first: {ctx.hls_project_dir}")
    splits = get_splits(ctx)
    prepare_u55c_inputs(ctx, splits, force=force)
    manifest_path = ctx.u55c_root / "bitstream_manifest.json"
    stage_fingerprint = {
        "u55c_stage_version": "2026-04-29-ap-ctrl-hs-canonical-dataflow",
        "project_name": read_json(ctx.hls_project_dir / "conversion_manifest.json")["project_name"],
        "hls_project": str(ctx.hls_project_dir),
        "hls_firmware_hash": sha256_tree(ctx.hls_project_dir / "firmware"),
        "prepared_inputs_manifest": read_json(ctx.prepared_inputs_dir / "manifest.json"),
        "coyote_root": str(ctx.coyote_root),
        "abi": ctx.abi,
    }
    if not force and manifest_path.exists() and read_json(manifest_path).get("stage_fingerprint") == stage_fingerprint:
        print("staged source cache hit")
    else:
        info = stage_coyote_hw_sw(ctx, force=force)
        write_json(
            manifest_path,
            {
                "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                "stage_fingerprint": stage_fingerprint,
                "stage_info": info,
                "hw_build_dir": str(ctx.u55c_root / "coyote_hw" / "build_u55c"),
                "bitstream_candidates": [],
            },
        )
    manifest = read_json(manifest_path)
    build_dir = Path(manifest["hw_build_dir"])
    build_fingerprint = {**manifest["stage_fingerprint"], "staged_source_hash": sha256_tree(ctx.u55c_root / "coyote_hw")}
    needs_build = force or manifest.get("build_fingerprint") != build_fingerprint or not manifest.get("bitstream_candidates")
    if needs_build:
        build_dir.mkdir(parents=True, exist_ok=True)
        jobs = ctx.config["u55c"].get("build_jobs") or os.cpu_count() or 4
        run_command(["cmake", "-DFDEV_NAME=u55c", ".."], cwd=build_dir, log_path=ctx.u55c_root / "logs" / "cmake_hw.log")
        run_command(["make", "project", "-j", str(jobs)], cwd=build_dir, log_path=ctx.u55c_root / "logs" / "make_project.log")
        run_command(["make", "bitgen", "-j", str(jobs)], cwd=build_dir, log_path=ctx.u55c_root / "logs" / "make_bitgen.log")
        manifest.update(
            {
                "build_fingerprint": build_fingerprint,
                "built_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                "bitstream_candidates": sorted(str(path) for path in build_dir.rglob("*.bit")),
                "report_candidates": sorted(str(path) for path in build_dir.rglob("*.rpt")),
                "dcp_candidates": sorted(str(path) for path in build_dir.rglob("*.dcp")),
            }
        )
        write_json(manifest_path, manifest)
    else:
        print("bitstream build cache hit")
    write_run_index(ctx)


def stage_deploy(ctx: FlowContext, force: bool = False) -> None:
    bit_manifest_path = ctx.u55c_root / "bitstream_manifest.json"
    if not bit_manifest_path.exists():
        raise FileNotFoundError(f"Run bitstream first: {bit_manifest_path}")
    bit_manifest = read_json(bit_manifest_path)
    bitstreams = [Path(path) for path in bit_manifest.get("bitstream_candidates", []) if Path(path).exists()]
    if not bitstreams:
        raise FileNotFoundError("No bitstream available from bitstream stage")
    staged_sw_dir = ctx.u55c_root / "coyote_sw"
    sw_build = staged_sw_dir / "build"
    sw_build.mkdir(parents=True, exist_ok=True)
    sw_fingerprint = {
        "sw_source_hash": sha256_tree(staged_sw_dir),
        "coyote_root": str(ctx.coyote_root),
        "prepared_manifest_hash": file_sha256(ctx.prepared_inputs_dir / "manifest.csv"),
    }
    deployment_manifest_path = ctx.u55c_root / "deployment_manifest.json"
    deployment_manifest = read_json(deployment_manifest_path) if deployment_manifest_path.exists() else {}
    host_exe = sw_build / "coyote_qkeras_host"
    jobs = ctx.config["u55c"].get("build_jobs") or os.cpu_count() or 4
    if force or deployment_manifest.get("sw_fingerprint") != sw_fingerprint or not host_exe.exists():
        run_command(["cmake", ".."], cwd=sw_build, log_path=ctx.u55c_root / "logs" / "cmake_sw.log")
        run_command(["make", "-j", str(jobs)], cwd=sw_build, log_path=ctx.u55c_root / "logs" / "make_sw.log")
        deployment_manifest["sw_fingerprint"] = sw_fingerprint
        deployment_manifest["host_executable"] = str(host_exe)
        write_json(deployment_manifest_path, deployment_manifest)
    bitstream = bitstreams[-1]
    driver_dir = ctx.coyote_root / "driver"
    driver = driver_dir / "build" / "coyote_driver.ko"
    if force or not driver.exists():
        driver_build = driver_dir / "build"
        driver_cflags = " ".join(
            [
                "-std=gnu11",
                "-Wno-declaration-after-statement",
                f"-I{driver_build / 'include'}",
                f"-I{driver_build / 'include' / 'reconfig'}",
                f"-I{driver_build / 'include' / 'vfpga'}",
                f"-I{driver_build / 'include' / 'platform'}",
                "-DPLATFORM_ULTRASCALE_PLUS",
            ]
        )
        run_command(["make", "clean"], cwd=driver_dir, log_path=ctx.u55c_root / "logs" / "make_driver_clean.log")
        run_command(["make", f"EXTRA_CFLAGS={driver_cflags}"], cwd=driver_dir, log_path=ctx.u55c_root / "logs" / "make_driver.log")
    if not driver.exists():
        raise FileNotFoundError(f"Could not build Coyote driver: {driver}")
    program_script = ctx.coyote_root / "util" / "program_hacc_local.sh"
    if not program_script.exists():
        raise FileNotFoundError(program_script)
    run_command(["bash", str(program_script), str(bitstream), str(driver)], cwd=ctx.coyote_root, log_path=ctx.u55c_root / "logs" / "program_u55c.log")
    hardware_csv = ctx.u55c_root / "hardware_per_sample.csv"
    run_command(
        [
            str(host_exe),
            "--manifest",
            str(ctx.prepared_inputs_dir / "manifest.csv"),
            "--output",
            str(hardware_csv),
        ],
        cwd=sw_build,
        log_path=ctx.u55c_root / "logs" / "host_run.log",
    )
    rows = clean_rows(hardware_csv)
    logits = np.asarray([float(row["logit"]) for row in rows], dtype=np.float32)
    lat = np.asarray([float(row["latency_us"]) for row in rows], dtype=np.float64)
    np.save(ctx.u55c_root / "y_hw.npy", logits)
    latency_summary = {
        "n_samples": int(len(rows)),
        "latency_us_mean": float(np.mean(lat)) if len(lat) else None,
        "latency_us_median": float(np.median(lat)) if len(lat) else None,
        "latency_us_min": float(np.min(lat)) if len(lat) else None,
        "latency_us_max": float(np.max(lat)) if len(lat) else None,
        "throughput_samples_per_s": float(1e6 / np.mean(lat)) if len(lat) else None,
    }
    write_json(ctx.u55c_root / "latency_summary.json", latency_summary)
    deployment_manifest.update(
        {
            "deployed_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "bitstream": str(bitstream),
            "driver": str(driver),
            "hardware_per_sample_csv": str(hardware_csv),
            "y_hw": str(ctx.u55c_root / "y_hw.npy"),
            "latency_summary": latency_summary,
        }
    )
    write_json(deployment_manifest_path, deployment_manifest)
    write_run_index(ctx)


def stage_validate(ctx: FlowContext, force: bool = False) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from sklearn.metrics import precision_recall_curve, roc_curve

    parity_dir = parity_dir_for_fold(ctx, ctx.primary_fold)
    qkeras_rows = clean_rows(parity_dir / "qkeras_per_sample.csv")
    hls_rows = clean_rows(parity_dir / "hls_per_sample.csv")
    prep_rows = clean_rows(ctx.prepared_inputs_dir / "manifest.csv")
    hw_raw_rows = clean_rows(ctx.u55c_root / "hardware_per_sample.csv")
    if not qkeras_rows or not hls_rows:
        raise FileNotFoundError(f"Missing parity rows in {parity_dir}")
    if not hw_raw_rows:
        raise FileNotFoundError(f"Missing U55C hardware rows: {ctx.u55c_root / 'hardware_per_sample.csv'}")
    hw_logits_by_idx = {int(row["sample_index"]): float(row["logit"]) for row in hw_raw_rows}
    hw_logits = np.asarray([hw_logits_by_idx[int(row["sample_index"])] for row in prep_rows], dtype=np.float32)
    hw_rows = rows_from_logits(prep_rows, [int(row["class_label"]) for row in prep_rows], hw_logits)
    write_csv(ctx.u55c_root / "hardware_per_sample_enriched.csv", hw_rows)
    np.save(ctx.u55c_root / "y_hw.npy", hw_logits)
    stages = {"QKeras CPU": qkeras_rows, "hls4ml CPU": hls_rows, "U55C hardware": hw_rows}
    summary = {}
    for name, rows in stages.items():
        metrics = metrics_from_stage_rows(rows)
        summary[name] = {key: float(metrics[key]) for key in ["accuracy", "balanced_accuracy", "roc_auc", "pr_auc", "bce_loss"]}
    ctx.validation_dir.mkdir(parents=True, exist_ok=True)
    write_json(ctx.validation_dir / "comparison_summary.json", summary)
    labels = np.asarray([int(row["class_label"]) for row in qkeras_rows], dtype=np.int32)
    fig, axes = plt.subplots(1, 3, figsize=(18, 5))
    for name, rows in stages.items():
        probs = np.asarray([float(row["probability"]) for row in rows], dtype=np.float32)
        fpr, tpr, _ = roc_curve(labels, probs)
        prec, rec, _ = precision_recall_curve(labels, probs)
        metrics = metrics_from_stage_rows(rows)
        axes[0].plot(fpr, tpr, label=f"{name} ({metrics['roc_auc']:.4f})")
        axes[1].plot(rec, prec, label=f"{name} ({metrics['pr_auc']:.4f})")
        axes[2].hist(probs[labels == 0], bins=20, range=(0, 1), histtype="step", density=True, label=f"{name} benign")
        axes[2].hist(probs[labels == 1], bins=20, range=(0, 1), histtype="step", density=True, linestyle="--", label=f"{name} standalone")
    axes[0].plot([0, 1], [0, 1], "k:", linewidth=1)
    axes[0].set_title("ROC")
    axes[0].set_xlabel("False positive rate")
    axes[0].set_ylabel("True positive rate")
    axes[1].set_title("Precision-Recall")
    axes[1].set_xlabel("Recall")
    axes[1].set_ylabel("Precision")
    axes[2].set_title("Score Histograms")
    axes[2].set_xlabel("Standalone probability")
    axes[2].set_ylabel("Density")
    for ax in axes:
        ax.legend(fontsize=8)
    fig.tight_layout()
    comparison_plot = ctx.validation_dir / "stage_comparison_plots.png"
    fig.savefig(comparison_plot, dpi=160)
    plt.close(fig)
    hw_metrics = metrics_from_stage_rows(hw_rows)
    save_checkpoint_plots(
        str(ctx.validation_dir),
        "final",
        canonical_metrics=hw_metrics,
        split_info=f"Candidate: {ctx.candidate_name} | Fold: {ctx.primary_fold} | Stage: U55C hardware",
        run_params={"hls_sweep": ctx.hls_sweep_root.name, "board": "u55c", "abi": "ap_fixed<16,6> packed AXI512"},
    )
    write_json(
        ctx.validation_dir / "validation_manifest.json",
        {
            "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "fold": ctx.primary_fold,
            "hls_sweep": ctx.hls_sweep_root.name,
            "comparison_summary": str(ctx.validation_dir / "comparison_summary.json"),
            "comparison_plot": str(comparison_plot),
            "final_evaluation_plots": str(ctx.validation_dir / "final_evaluation_plots.png"),
            "hardware_per_sample_enriched": str(ctx.u55c_root / "hardware_per_sample_enriched.csv"),
        },
    )
    write_run_index(ctx)


def write_run_index(ctx: FlowContext) -> None:
    n_trace = ctx.config["hls"].get("n_layer_trace_samples")
    trace_tag = "all" if n_trace is None else f"n{int(n_trace)}"
    paths = [
        ("Config", ctx.config_path),
        ("Iteration manifest", ctx.run_root / "iteration_manifest.json"),
        ("Split summary", ctx.run_root / "splits" / "summary.csv"),
        ("Pooled metrics", ctx.run_root / "pooled" / "metrics_summary.json"),
        ("K-fold training curves", ctx.run_root / "kfold_training_curves.png"),
        ("K-fold evaluation dashboard", ctx.run_root / "evaluation_dashboard.png"),
        ("K-fold final plots", ctx.run_root / "final_evaluation_plots.png"),
        ("Sparsity CSV", ctx.run_root / f"sparsity_fold_{ctx.primary_fold}.csv"),
        ("Sparsity plot", ctx.run_root / f"sparsity_fold_{ctx.primary_fold}.png"),
        ("HLS sweep manifest", ctx.hls_sweep_root / "hls_sweep_manifest.json"),
        ("HLS project", ctx.hls_project_dir),
        ("HLS config", ctx.hls_project_dir / "hls4ml_config.yml"),
        ("HLS model plot", ctx.hls_project_dir / "hls4ml_model.png"),
        ("Parity summary", parity_dir_for_fold(ctx, ctx.primary_fold) / "summary.json"),
        ("Layer divergence", parity_dir_for_fold(ctx, ctx.primary_fold) / f"layer_trace_{trace_tag}" / "layer_divergence.png"),
        ("Synthesis summary", ctx.hls_sweep_root / "synthesis_summary.csv"),
        ("HLS metrics summary", ctx.hls_sweep_root / "hls_metrics_summary.csv"),
        ("Prepared inputs", ctx.prepared_inputs_dir / "manifest.csv"),
        ("Bitstream manifest", ctx.u55c_root / "bitstream_manifest.json"),
        ("Deployment manifest", ctx.u55c_root / "deployment_manifest.json"),
        ("Latency summary", ctx.u55c_root / "latency_summary.json"),
        ("Hardware CSV", ctx.u55c_root / "hardware_per_sample.csv"),
        ("Validation manifest", ctx.validation_dir / "validation_manifest.json"),
        ("Validation comparison plot", ctx.validation_dir / "stage_comparison_plots.png"),
        ("Final validation plots", ctx.validation_dir / "final_evaluation_plots.png"),
    ]
    lines = [
        f"# hls4ml Run Index",
        "",
        f"- Run root: `{ctx.run_root}`",
        f"- HLS sweep root: `{ctx.hls_sweep_root}`",
        f"- Training fingerprint: `{ctx.training_fingerprint}`",
        f"- HLS fingerprint: `{ctx.hls_fingerprint}`",
        "",
        "## Artifacts",
    ]
    for label, path in paths:
        exists = Path(path).exists()
        lines.append(f"- {label}: `{path}`{' (missing)' if not exists else ''}")
    bit_manifest = ctx.u55c_root / "bitstream_manifest.json"
    if bit_manifest.exists():
        manifest = read_json(bit_manifest)
        for key in ("bitstream_candidates", "dcp_candidates", "report_candidates"):
            values = manifest.get(key, [])
            if values:
                lines.append("")
                lines.append(f"## {key}")
                lines.extend(f"- `{value}`" for value in values[:20])
    (ctx.run_root / "run_index.md").write_text("\n".join(lines) + "\n")


def discover_toolchain_version(requested: str = "latest") -> str | None:
    roots = [Path("/tools/Xilinx/Vivado"), Path("/tools/Xilinx/Vitis"), Path("/tools/Xilinx/Vitis_HLS")]
    versions_by_root = []
    for root in roots:
        if not root.exists():
            continue
        versions = {path.name for path in root.iterdir() if path.is_dir()}
        versions_by_root.append(versions)
    if not versions_by_root:
        return None
    common = set.intersection(*versions_by_root) if len(versions_by_root) > 1 else versions_by_root[0]
    if requested != "latest":
        return requested if requested in common or not common else None
    if not common:
        return None

    def sort_key(value: str):
        return [int(part) if part.isdigit() else part for part in re.split(r"([0-9]+)", value)]

    return sorted(common, key=sort_key)[-1]


def maybe_reexec_with_toolchain(ctx: FlowContext, stages: set[str], argv: Sequence[str]) -> None:
    needs_toolchain = bool(stages & {"hls", "bitstream"})
    toolchain = ctx.config.get("toolchain", {})
    if not needs_toolchain or not bool(toolchain.get("auto_enable", True)):
        return
    if os.environ.get("HLS4ML_RUN_TOOLCHAIN_ENABLED") == "1":
        return
    if shutil.which("vitis_hls") and shutil.which("vivado"):
        return
    version = discover_toolchain_version(str(toolchain.get("version", "latest")))
    if version is None:
        return
    python = shlex.quote(sys.executable)
    quoted_argv = " ".join(shlex.quote(arg) for arg in argv)
    prologue = "\n".join(
        [
            "export CLI_PATH=/opt/hdev/cli",
            "export TERM=${TERM:-xterm}",
            "export HLS4ML_RUN_TOOLCHAIN_ENABLED=1",
            f'source /opt/hdev/cli/enable/vivado -v "{version}"',
            f'source /opt/hdev/cli/enable/vitis -v "{version}"',
            f"exec {python} {quoted_argv}",
        ]
    )
    print(f"[toolchain] re-execing with Vivado/Vitis {version}")
    os.execv("/bin/bash", ["bash", "-lc", prologue])


STAGE_FUNCS = {
    "train": stage_train,
    "hls": stage_hls,
    "bitstream": stage_bitstream,
    "deploy": stage_deploy,
    "validate": stage_validate,
}


def run_stages(ctx: FlowContext, stages: Iterable[str], force: bool = False) -> None:
    write_top_manifests(ctx)
    for stage in stages:
        if stage not in STAGE_FUNCS:
            raise ValueError(f"Unknown stage {stage!r}; choose from {sorted(STAGE_FUNCS)}")
        print(f"[stage] {stage}")
        STAGE_FUNCS[stage](ctx, force=force)
    write_run_index(ctx)
