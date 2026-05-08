"""Shared config, context, artifact, and metric helpers for the numbered hls4ml flow parts."""

from __future__ import annotations

import csv
import hashlib
import json
import math
import os
import re
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Sequence

import numpy as np

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")

from .paths import COYOTE_ROOT as DEFAULT_COYOTE_ROOT
from .paths import EXAMPLE_ROOT, ML_BASELINE_ROOT, ensure_ml_baseline_on_path

ensure_ml_baseline_on_path()

from train import compute_metrics_from_outputs  # noqa: E402

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
        "enabled": True,
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
        "allow_stale_fold_cache": False,
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
        "cmake_defines": {},
        "allow_timing_violating_deploy": False,
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
    EXAMPLE_ROOT / "pipeline" / "part1_common.py",
    EXAMPLE_ROOT / "pipeline" / "part2_train.py",
    EXAMPLE_ROOT / "pipeline" / "part3_hls.py",
    EXAMPLE_ROOT / "pipeline" / "part4_bitstream.py",
    EXAMPLE_ROOT / "pipeline" / "part5_deploy.py",
    EXAMPLE_ROOT / "pipeline" / "part6_validate.py",
    EXAMPLE_ROOT / "pipeline" / "part7_runner.py",
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
    exclude_dir_names: tuple[str, ...] = (),
) -> str:
    h = hashlib.sha256()
    root = Path(root)
    if not root.exists():
        return ""
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        if any(part in exclude_dir_names for part in path.relative_to(root).parts[:-1]):
            continue
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
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True, default=str))
    os.replace(tmp, path)


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



def metrics_from_logits(labels: np.ndarray, logits: np.ndarray) -> dict[str, Any]:
    probs = sigmoid(logits)
    eps = 1e-7
    clipped = np.clip(probs, eps, 1.0 - eps)
    loss = -np.mean(labels * np.log(clipped) + (1.0 - labels) * np.log(1.0 - clipped))
    return compute_metrics_from_outputs(float(loss), labels.astype(np.float32), probs.astype(np.float32))


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
        return str(self.config["quantization"].get("tag") or "float32")

    @property
    def quantization_enabled(self) -> bool:
        return bool(self.config.get("quantization", {}).get("enabled", True))

    @property
    def pruning_enabled(self) -> bool:
        return bool(self.config.get("pruning", {}).get("enabled", True))

    @property
    def training_stage(self) -> str:
        flavor = "qat" if self.quantization_enabled else "float"
        return f"pruned_{flavor}" if self.pruning_enabled else flavor

    @property
    def model_flavor_label(self) -> str:
        return self.quantizer_tag if self.quantization_enabled else "float32"

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
        flow_dir = "notebook_pruned_qat"
        if not bool(config.get("quantization", {}).get("enabled", True)):
            flow_dir = "notebook_pruned_float" if bool(config.get("pruning", {}).get("enabled", True)) else "notebook_float"
        elif not bool(config.get("pruning", {}).get("enabled", True)):
            flow_dir = "notebook_qat"
        run_root = (output_root / candidate_name / flow_dir / run_name).resolve()
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


def write_top_manifests(ctx: FlowContext, force_fingerprint: bool = False) -> None:
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
    old_payload = {}
    if old.exists():
        try:
            old_payload = read_json(old)
        except json.JSONDecodeError as exc:
            if not force_fingerprint:
                raise RuntimeError(f"Corrupt generated manifest in {ctx.run_root}: {old}") from exc
            print(f"[warn] overwriting corrupt generated manifest in {old} (--force-fingerprint)")
    if old.exists() and old_payload.get("training_fingerprint") != ctx.training_fingerprint:
        if not force_fingerprint:
            raise RuntimeError(f"Fingerprint collision or stale manifest in {ctx.run_root}")
        print(f"[warn] overwriting stale fingerprint in {old} (--force-fingerprint)")
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
    hls_payload = {}
    if hls_path.exists():
        try:
            hls_payload = read_json(hls_path)
        except json.JSONDecodeError as exc:
            if not force_fingerprint:
                raise RuntimeError(f"Corrupt generated HLS manifest in {ctx.hls_sweep_root}: {hls_path}") from exc
            print(f"[warn] overwriting corrupt generated HLS manifest in {hls_path} (--force-fingerprint)")
    if hls_path.exists() and hls_payload.get("hls_fingerprint") != ctx.hls_fingerprint:
        if not force_fingerprint:
            raise RuntimeError(f"Fingerprint collision or stale HLS manifest in {ctx.hls_sweep_root}")
        print(f"[warn] overwriting stale HLS fingerprint in {hls_path} (--force-fingerprint)")
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


def class_counts(rows: list[dict[str, Any]]) -> dict[int, int]:
    return {label: sum(int(row["class_label"]) == label for row in rows) for label in (0, 1)}


def fold_dir(ctx: FlowContext, fold: int) -> Path:
    return ctx.run_root / f"fold_{fold}"


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


def parity_dir_for_fold(ctx: FlowContext, fold: int) -> Path:
    return ctx.hls_sweep_root / f"fold_{fold}" / "parity"


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
        ("Pooled standalone probability vs RO count", ctx.run_root / "pooled" / "standalone_probability_vs_ro_count.png"),
        ("Pooled benign app standalone probability", ctx.run_root / "pooled" / "benign_app_standalone_probability.png"),
        ("Primary fold Grad-CAM overview", fold_dir(ctx, ctx.primary_fold) / "gradcam_final" / "overview_grid.png"),
        ("Primary fold high-RO standalone Grad-CAM", fold_dir(ctx, ctx.primary_fold) / "gradcam_final" / "high_ro_standalone_gradcam.png"),
        ("Primary fold high-RO standalone Grad-CAM (1024px)", fold_dir(ctx, ctx.primary_fold) / "gradcam_final" / "high_ro_standalone_gradcam_1024.png"),
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
