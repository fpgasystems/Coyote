"""Part 5 of the notebook flow: CoyoteAccelerator programming and raw inference."""

from __future__ import annotations

import time
from pathlib import Path
from typing import Any

import numpy as np

from .coyote_accelerator.raw_data import load_raw_arrays
from .coyote_accelerator.raw_overlay import RawCoyoteOverlay
from .part1_common import FlowContext, clean_rows, read_json, write_csv, write_json, write_run_index
from .part4_bitstream import coyote_accelerator_config


def _existing_paths(paths: list[str]) -> list[Path]:
    return [Path(path) for path in paths if Path(path).exists()]


def _timing_guard(ctx: FlowContext, bit_manifest: dict[str, Any]) -> None:
    timing_summary = bit_manifest.get("timing_summary") or {}
    if (
        timing_summary.get("timing_clean") is False
        and not bool(ctx.config.get("u55c", {}).get("allow_timing_violating_deploy", False))
    ):
        raise RuntimeError(
            "Refusing to deploy a timing-violating bitstream. "
            f"WNS={timing_summary.get('wns')} TNS={timing_summary.get('tns')} "
            f"failing_endpoints={timing_summary.get('failing_endpoints')}. "
            "Set u55c.allow_timing_violating_deploy=true only for explicit diagnostics."
        )


def _load_overlay(project_dir: Path, project_name: str):
    return RawCoyoteOverlay(project_dir, project_name=project_name)


def _predict_raw_batches(overlay, raw_arrays: list[np.ndarray], batch_size: int) -> tuple[np.ndarray, list[dict[str, Any]]]:
    if batch_size <= 0:
        raise ValueError(f"batch_size must be positive, got {batch_size}")
    if not raw_arrays:
        return np.empty((0,), dtype=np.float32), []

    logits: list[np.ndarray] = []
    batch_rows: list[dict[str, Any]] = []
    n_batches = int(np.ceil(len(raw_arrays) / batch_size))
    for batch_idx in range(n_batches):
        start = batch_idx * batch_size
        stop = min(start + batch_size, len(raw_arrays))
        raw_batch = raw_arrays[start:stop]
        real_batch_size = len(raw_batch)
        if real_batch_size < batch_size:
            raw_batch = [*raw_batch, *([raw_batch[-1]] * (batch_size - real_batch_size))]
        t0 = time.time_ns()
        pred = np.asarray(overlay.predict_raw(raw_batch, (1,), batch_size)).reshape(batch_size)
        t1 = time.time_ns()
        elapsed_us = (t1 - t0) / 1000.0
        logits.append(pred[:real_batch_size].astype(np.float32))
        batch_rows.append(
            {
                "batch_index": batch_idx,
                "first_sample_index": start,
                "last_sample_index": stop - 1,
                "batch_size": batch_size,
                "real_batch_size": real_batch_size,
                "padding_samples": batch_size - real_batch_size,
                "wall_latency_us": f"{elapsed_us:.3f}",
                "wall_throughput_samples_per_s": f"{real_batch_size / (elapsed_us * 1e-6):.6f}" if elapsed_us else "",
            }
        )
        print(f"[deploy] FPGA raw batch {batch_idx + 1}/{n_batches}: {elapsed_us:.3f} us wall")
    return np.concatenate(logits, axis=0) if logits else np.empty((0,), dtype=np.float32), batch_rows


def stage_deploy(ctx: FlowContext, force: bool = False) -> None:
    bit_manifest_path = ctx.u55c_root / "bitstream_manifest.json"
    if not bit_manifest_path.exists():
        raise FileNotFoundError(f"Run bitstream first: {bit_manifest_path}")
    bit_manifest = read_json(bit_manifest_path)
    if bit_manifest.get("backend") != "CoyoteAccelerator" or not bit_manifest.get("raw_input_mode"):
        raise RuntimeError(f"Expected a raw-input CoyoteAccelerator bitstream manifest, got {bit_manifest_path}")
    _timing_guard(ctx, bit_manifest)

    cfg = coyote_accelerator_config(ctx)
    project_name = str(bit_manifest.get("project_name") or cfg["project_name"])
    project_dir = Path(bit_manifest["project_dir"]).resolve()
    host_library = Path(bit_manifest.get("host_library") or project_dir / "build" / f"{project_name}_cyt_sw" / "lib/libCoyoteInference.so")
    bitstreams = _existing_paths(list(bit_manifest.get("bitstream_candidates", [])))
    if not bitstreams:
        raise FileNotFoundError("No bitstream available from bitstream stage")
    if not host_library.exists():
        raise FileNotFoundError(f"Generated CoyoteAccelerator host library is missing: {host_library}")

    prep_rows = clean_rows(ctx.prepared_inputs_dir / "manifest.csv")
    if not prep_rows:
        raise FileNotFoundError(f"Missing prepared raw input manifest: {ctx.prepared_inputs_dir / 'manifest.csv'}")
    raw_arrays = load_raw_arrays(prep_rows)
    labels = np.load(ctx.prepared_inputs_dir / "labels.npy").astype(np.int32).reshape(-1)
    if len(labels) != len(prep_rows):
        raise RuntimeError(f"labels.npy has {len(labels)} labels but manifest has {len(prep_rows)} rows")

    overlay = _load_overlay(project_dir, project_name)
    if bool(cfg.get("program_fpga", True)):
        print("[deploy] programming Coyote FPGA")
        overlay.program_hacc_fpga()
    logits, batch_rows = _predict_raw_batches(overlay, raw_arrays, int(cfg["batch_size"]))
    if len(logits) != len(prep_rows):
        raise RuntimeError(f"FPGA returned {len(logits)} logits for {len(prep_rows)} prepared samples")

    hardware_rows: list[dict[str, Any]] = []
    batch_latency_by_index = {
        int(row["batch_index"]): float(row["wall_latency_us"])
        for row in batch_rows
    }
    batch_real_size_by_index = {
        int(row["batch_index"]): int(row.get("real_batch_size", row["batch_size"]))
        for row in batch_rows
    }
    for idx, (sample, label, logit) in enumerate(zip(prep_rows, labels, logits)):
        batch_index = idx // int(cfg["batch_size"])
        batch_latency = batch_latency_by_index.get(batch_index, 0.0)
        real_batch_size = max(1, batch_real_size_by_index.get(batch_index, int(cfg["batch_size"])))
        hardware_rows.append(
            {
                "sample_index": int(sample["sample_index"]),
                "sample_id": sample.get("sample_id", ""),
                "app_name": sample.get("app_name", ""),
                "class_label": int(label),
                "class_name": sample.get("class_name", "standalone" if int(label) else "benign"),
                "ro_count": sample.get("ro_count", ""),
                "bitstream_path": sample.get("bitstream_path", ""),
                "raw_input_path": sample.get("raw_input_path", ""),
                "raw_input_bytes": sample.get("raw_input_bytes", ""),
                "logit": f"{float(logit):.9f}",
                "batch_index": batch_index,
                "batch_wall_latency_us": f"{batch_latency:.3f}",
                "sample_share_wall_latency_us": f"{batch_latency / real_batch_size:.3f}",
            }
        )

    hardware_csv = ctx.u55c_root / "hardware_per_sample.csv"
    write_csv(hardware_csv, hardware_rows)
    write_csv(ctx.u55c_root / "hardware_batches.csv", batch_rows)
    np.save(ctx.u55c_root / "y_hw.npy", logits.astype(np.float32))

    batch_lat = np.asarray([float(row["wall_latency_us"]) for row in batch_rows], dtype=np.float64)
    total_batch_wall_us = float(batch_lat.sum()) if batch_lat.size else 0.0
    latency_summary = {
        "n_samples": int(len(logits)),
        "batch_size": int(cfg["batch_size"]),
        "n_batches": int(len(batch_rows)),
        "batch_wall_latency_us_mean": float(np.mean(batch_lat)) if batch_lat.size else None,
        "batch_wall_latency_us_median": float(np.median(batch_lat)) if batch_lat.size else None,
        "batch_wall_latency_us_min": float(np.min(batch_lat)) if batch_lat.size else None,
        "batch_wall_latency_us_max": float(np.max(batch_lat)) if batch_lat.size else None,
        "sample_share_wall_latency_us_mean": float(total_batch_wall_us / len(logits)) if len(logits) else None,
        "throughput_samples_per_s": float(len(logits) / (total_batch_wall_us * 1e-6)) if total_batch_wall_us else None,
        "padded_samples": int(sum(int(row.get("padding_samples", 0)) for row in batch_rows)),
        "measurement_scope": "Python RawCoyoteOverlay.predict_raw call wall time per batch; RawCoyoteOverlay also prints inference-only timing from the generated host library.",
    }
    write_json(ctx.u55c_root / "latency_summary.json", latency_summary)

    deployment_manifest = {
        "deployed_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "backend": "CoyoteAccelerator",
        "raw_input_mode": True,
        "programmed_fpga": bool(cfg.get("program_fpga", True)),
        "project_name": project_name,
        "project_dir": str(project_dir),
        "host_library": str(host_library),
        "bitstream": str(bitstreams[-1]),
        "hardware_per_sample_csv": str(hardware_csv),
        "hardware_batches_csv": str(ctx.u55c_root / "hardware_batches.csv"),
        "y_hw": str(ctx.u55c_root / "y_hw.npy"),
        "latency_summary": latency_summary,
        "bitstream_manifest": str(bit_manifest_path),
    }
    write_json(ctx.u55c_root / "deployment_manifest.json", deployment_manifest)
    write_run_index(ctx)
