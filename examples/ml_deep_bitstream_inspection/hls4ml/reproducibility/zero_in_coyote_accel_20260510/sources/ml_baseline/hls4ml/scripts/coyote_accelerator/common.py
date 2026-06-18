"""Shared helpers for the zero-in CoyoteAccelerator scripts."""

from __future__ import annotations

import csv
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")

ML_BASELINE_ROOT = Path("/pub/scratch/sdeheredia/Coyote/examples/ml_baseline")
HLS4ML_FLOW_ROOT = ML_BASELINE_ROOT / "hls4ml"
DEFAULT_CONFIG = HLS4ML_FLOW_ROOT / "configs/hls4ml_experiment/res256_layers5_W8A8_P50_RFbase.yaml"
DEFAULT_RUN_ROOT = (
    HLS4ML_FLOW_ROOT
    / "artifacts/cnn_small_hls_opt_img256/notebook_pruned_qat/"
    "ZERO_IN_res256_layers5_W8A8_P50_RFbase_07faeca37cb7"
)
DEFAULT_INPUT_ROOT = (
    DEFAULT_RUN_ROOT
    / "hls_sweeps/RFbase_hls_a121fc48614f/fold_0/u55c_deployment/prepared_inputs"
)
DEFAULT_OUTPUT_PARENT = HLS4ML_FLOW_ROOT / "artifacts/coyote_accelerator_zero_in"


def ensure_flow_on_path() -> None:
    for path in (ML_BASELINE_ROOT, HLS4ML_FLOW_ROOT):
        value = str(path)
        if value not in sys.path:
            sys.path.insert(0, value)


def timestamp() -> str:
    return time.strftime("%Y%m%d_%H%M%S")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True, default=str))
    os.replace(tmp, path)


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("")
        return
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def load_context(config_path: Path, run_root: Path):
    ensure_flow_on_path()
    from pipeline.part1_common import build_context, load_config

    config = load_config(config_path)
    config["hls"]["backend"] = "CoyoteAccelerator"
    config["hls"]["io_type"] = "io_stream"
    config["hls"]["clock_period"] = 4.0
    config["hls"]["run_csim"] = True
    config["hls"]["run_cosim"] = False
    config["hls"]["sweep_name"] = "CoyoteAccelerator_io_stream"
    return build_context(config, config_path=config_path, run_root_arg=run_root)


def load_zero_in_model(config_path: Path = DEFAULT_CONFIG, run_root: Path = DEFAULT_RUN_ROOT, fold: int = 0):
    ensure_flow_on_path()
    from pipeline.part2_train import load_fold_model

    ctx = load_context(config_path, run_root)
    model = load_fold_model(ctx, fold)
    return ctx, model


def load_zero_in_arrays(input_root: Path = DEFAULT_INPUT_ROOT, n_samples: int | None = None):
    import numpy as np

    x_path = input_root / "x_norm.npy"
    labels_path = input_root / "labels.npy"
    if not x_path.exists():
        raise FileNotFoundError(x_path)
    if not labels_path.exists():
        raise FileNotFoundError(labels_path)
    x = np.load(x_path).astype(np.float32)
    labels = np.load(labels_path).astype(np.int32)
    if n_samples is not None:
        x = x[: int(n_samples)]
        labels = labels[: int(n_samples)]
    return x, labels, x_path, labels_path


def logit_validation_summary(cpu_logits, fpga_logits, labels, tolerance: float) -> dict[str, Any]:
    import numpy as np

    cpu = np.asarray(cpu_logits, dtype=np.float64).reshape(-1)
    fpga = np.asarray(fpga_logits, dtype=np.float64).reshape(-1)
    if cpu.shape != fpga.shape:
        raise ValueError(f"logit shape mismatch: CPU {cpu.shape}, FPGA {fpga.shape}")
    labels = np.asarray(labels, dtype=np.int32).reshape(-1)
    diff = fpga - cpu
    abs_diff = np.abs(diff)
    cpu_pred = (cpu >= 0.0).astype(np.int32)
    fpga_pred = (fpga >= 0.0).astype(np.int32)
    summary = {
        "n": int(cpu.size),
        "tolerance": float(tolerance),
        "passed": bool(np.all(abs_diff <= float(tolerance))),
        "logit_mae": float(abs_diff.mean()) if abs_diff.size else 0.0,
        "logit_max_abs": float(abs_diff.max()) if abs_diff.size else 0.0,
        "strict_atol_0p03_passed": bool(np.all(abs_diff <= 0.03)),
        "sign_mismatches": int(np.sum(cpu_pred != fpga_pred)),
        "prediction_agreement": float(np.mean(cpu_pred == fpga_pred)) if cpu.size else 0.0,
    }
    if labels.size == cpu.size:
        summary.update(
            {
                "cpu_accuracy": float(np.mean(cpu_pred == labels)),
                "fpga_accuracy": float(np.mean(fpga_pred == labels)),
            }
        )
    return summary


def prediction_rows(cpu_logits, fpga_logits, labels) -> list[dict[str, Any]]:
    import numpy as np

    cpu = np.asarray(cpu_logits, dtype=np.float64).reshape(-1)
    fpga = np.asarray(fpga_logits, dtype=np.float64).reshape(-1)
    labels = np.asarray(labels, dtype=np.int32).reshape(-1)
    rows = []
    for idx, (cpu_logit, fpga_logit) in enumerate(zip(cpu, fpga)):
        label = int(labels[idx]) if idx < labels.size else ""
        rows.append(
            {
                "sample_index": idx,
                "label": label,
                "cpu_logit": float(cpu_logit),
                "fpga_logit": float(fpga_logit),
                "abs_diff": float(abs(fpga_logit - cpu_logit)),
                "cpu_pred": int(cpu_logit >= 0.0),
                "fpga_pred": int(fpga_logit >= 0.0),
            }
        )
    return rows
