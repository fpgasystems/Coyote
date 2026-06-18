#!/usr/bin/env python3
"""Package production CoyoteAccelerator deployment artifacts for reproducibility."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


ML_ROOT = Path("/pub/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/ml_baseline")
HLS4ML_ROOT = ML_ROOT / "hls4ml"


def read_json(path: Path) -> dict[str, Any]:
    with path.open() as handle:
        return json.load(handle)


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, Any]], fieldnames: list[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if fieldnames is None:
        keys: list[str] = []
        for row in rows:
            for key in row:
                if key not in keys:
                    keys.append(key)
        fieldnames = keys
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def copy_file(src: Path, dst: Path) -> None:
    if not src.exists():
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["cp", "--reflink=auto", "-a", str(src), str(dst)], check=True)


def copy_tree(src: Path, dst: Path) -> None:
    if not src.exists():
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        raise FileExistsError(dst)
    subprocess.run(["cp", "--reflink=auto", "-a", str(src), str(dst)], check=True)


def find_one(root: Path, pattern: str) -> Path:
    matches = sorted(root.rglob(pattern))
    if not matches:
        raise FileNotFoundError(f"{pattern} under {root}")
    return matches[0]


def maybe_find_one(root: Path, pattern: str) -> Path | None:
    matches = sorted(root.rglob(pattern))
    return matches[0] if matches else None


def parse_num(cell: str) -> float | None:
    match = re.search(r"-?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?", cell.replace(",", ""), re.I)
    return float(match.group(0)) if match else None


def parse_vivado_util(path: Path) -> dict[str, dict[str, float | int | None]]:
    wanted = {
        "CLB LUTs": "clb_luts",
        "CLB Registers": "clb_registers",
        "Block RAM Tile": "bram_tile",
        "URAM": "uram",
        "DSPs": "dsp",
        "DSP": "dsp",
    }
    result: dict[str, dict[str, float | int | None]] = {}
    for line in path.read_text(errors="ignore").splitlines():
        if not line.startswith("|"):
            continue
        parts = [part.strip() for part in line.strip().strip("|").split("|")]
        if len(parts) < 5:
            continue
        name = parts[0].replace("*", "").strip()
        key = wanted.get(name)
        if key and key not in result:
            result[key] = {
                "used": parse_num(parts[1]),
                "fixed": parse_num(parts[2]) if len(parts) >= 6 else None,
                "available": parse_num(parts[-2]),
                "util_percent": parse_num(parts[-1]),
            }
    return result


def parse_shell_timing(path: Path) -> dict[str, Any]:
    text = path.read_text(errors="ignore")
    status = "met" if "All user specified timing constraints are met." in text else "unknown"
    if "Timing constraints are not met" in text:
        status = "not_met"
    summary: dict[str, Any] = {
        "source": str(path),
        "status": status,
    }
    match = re.search(
        r"WNS\(ns\)\s+TNS\(ns\)\s+TNS Failing Endpoints.*?\n\s*-+\s+-+\s+-+.*?\n\s*"
        r"(?P<wns>-?\d+(?:\.\d+)?)\s+(?P<tns>-?\d+(?:\.\d+)?)\s+(?P<fail>\d+)",
        text,
        re.S,
    )
    if match:
        summary.update(
            {
                "wns_ns": float(match.group("wns")),
                "tns_ns": float(match.group("tns")),
                "tns_failing_endpoints": int(match.group("fail")),
            }
        )
        if summary["wns_ns"] < 0 or summary["tns_failing_endpoints"] > 0:
            summary["status"] = "not_met"
    return summary


def parse_hls_modules(path: Path) -> dict[str, Any]:
    modules: dict[str, Any] = {}
    for line in path.read_text(errors="ignore").splitlines():
        if not line.startswith("    |"):
            continue
        parts = [part.strip() for part in line.strip().strip("|").split("|")]
        if len(parts) < 14:
            continue
        raw_name = parts[0]
        name = raw_name.lstrip("+o ").strip().rstrip("*")
        if name not in {"model_wrapper", "raw_bitstream_downsample_to_input_stream"} and not name.endswith("_coyote_accel"):
            continue
        latency_cycles = parse_num(parts[3])
        interval_cycles = parse_num(parts[6])
        modules[name] = {
            "latency_cycles": int(latency_cycles) if latency_cycles is not None else None,
            "latency_ns": parse_num(parts[4]),
            "interval_cycles": int(interval_cycles) if interval_cycles is not None else None,
            "pipelined": parts[8],
            "resources_estimated": {
                "bram_18k": int(parse_num(parts[9]) or 0),
                "dsp": int(parse_num(parts[10]) or 0),
                "ff": int(parse_num(parts[11]) or 0),
                "lut": int(parse_num(parts[12]) or 0),
                "uram": int(parse_num(parts[13]) or 0),
            },
        }
        if modules[name]["latency_cycles"] is not None:
            modules[name]["latency_ms_at_250mhz"] = modules[name]["latency_cycles"] * 4e-6
    return modules


def model_module_name(modules: dict[str, Any]) -> str | None:
    for name in modules:
        if name.endswith("_coyote_accel"):
            return name
    return "zero_in_coyote_accel" if "zero_in_coyote_accel" in modules else None


def metric_subset(metrics: dict[str, Any]) -> dict[str, Any]:
    keys = [
        "accuracy",
        "balanced_accuracy",
        "precision",
        "recall",
        "f1",
        "roc_auc",
        "pr_auc",
        "bce_loss",
        "log_loss",
        "mcc",
    ]
    return {key: metrics[key] for key in keys if key in metrics}


def classification_metrics_from_rows(rows: list[dict[str, str]]) -> dict[str, Any]:
    labels: list[int] = []
    predictions: list[int] = []
    for row in rows:
        label_raw = row.get("class_label")
        if label_raw is None:
            continue
        label = int(float(label_raw))
        pred_raw = row.get("predicted_label")
        if pred_raw not in (None, ""):
            pred = int(float(pred_raw))
        else:
            pred = sign(float(row["logit"]))
        labels.append(label)
        predictions.append(pred)

    tn = sum(label == 0 and pred == 0 for label, pred in zip(labels, predictions))
    fp = sum(label == 0 and pred == 1 for label, pred in zip(labels, predictions))
    fn = sum(label == 1 and pred == 0 for label, pred in zip(labels, predictions))
    tp = sum(label == 1 and pred == 1 for label, pred in zip(labels, predictions))

    def div(num: float, den: float) -> float | None:
        return num / den if den else None

    precision = div(tp, tp + fp)
    tpr = div(tp, tp + fn)
    tnr = div(tn, tn + fp)
    fpr = div(fp, fp + tn)
    fnr = div(fn, fn + tp)
    f1 = div(2 * precision * tpr, precision + tpr) if precision is not None and tpr is not None and (precision + tpr) else None
    return {
        "n": len(labels),
        "tn": tn,
        "fp": fp,
        "fn": fn,
        "tp": tp,
        "accuracy": div(tp + tn, len(labels)),
        "balanced_accuracy": div((tpr or 0.0) + (tnr or 0.0), 2.0) if tpr is not None and tnr is not None else None,
        "precision": precision,
        "recall": tpr,
        "f1": f1,
        "tpr": tpr,
        "fnr": fnr,
        "tnr": tnr,
        "fpr": fpr,
        "confusion_matrix": [[tn, fp], [fn, tp]],
    }


def merge_stage_metrics(base: dict[str, Any], rows: list[dict[str, str]], extra: dict[str, Any] | None = None) -> dict[str, Any]:
    merged = dict(base)
    merged.update(classification_metrics_from_rows(rows))
    if extra:
        for key, value in extra.items():
            if value is not None:
                merged[key] = value
    return merged


def sign(value: float) -> int:
    return 1 if value >= 0.0 else 0


def parity_metrics(left_rows: list[dict[str, str]], right_rows: list[dict[str, str]]) -> dict[str, Any]:
    left = {int(row["sample_index"]): float(row["logit"]) for row in left_rows}
    right = {int(row["sample_index"]): float(row["logit"]) for row in right_rows}
    common = sorted(set(left) & set(right))
    diffs = [abs(left[idx] - right[idx]) for idx in common]
    if not common:
        return {"n": 0}
    return {
        "n": len(common),
        "logit_mae": sum(diffs) / len(diffs),
        "logit_max_abs": max(diffs),
        "prediction_agreement": sum(sign(left[idx]) == sign(right[idx]) for idx in common) / len(common),
        "sign_mismatches": sum(sign(left[idx]) != sign(right[idx]) for idx in common),
    }


def summarize(values: list[float]) -> dict[str, Any]:
    if not values:
        return {"count": 0, "mean": None, "min": None, "max": None}
    return {
        "count": len(values),
        "mean": sum(values) / len(values),
        "min": min(values),
        "max": max(values),
    }


def parse_deploy_log(path: Path | None) -> dict[str, Any]:
    if path is None or not path.exists():
        return {
            "source": str(path) if path is not None else None,
            "latency_ms_per_batch": [],
            "throughput_samples_per_s": [],
            "latency_ms_per_batch_summary": summarize([]),
            "throughput_samples_per_s_summary": summarize([]),
        }
    text = path.read_text(errors="ignore")
    latency_ms = [
        float(match) / 1000.0
        for match in re.findall(r"Mean latency:\s*([0-9.]+)us\s*\(inference only\)", text)
    ]
    throughput = [
        float(match)
        for match in re.findall(r"Mean throughput:\s*([0-9.]+)\s+samples/s\s*\(inference only\)", text)
    ]
    return {
        "source": str(path),
        "latency_ms_per_batch": latency_ms,
        "throughput_samples_per_s": throughput,
        "latency_ms_per_batch_summary": summarize(latency_ms),
        "throughput_samples_per_s_summary": summarize(throughput),
    }


def raw_latency_for_rows(rows: list[dict[str, str]]) -> tuple[int, float]:
    cycles = sum(math.ceil(int(row["raw_input_bytes"]) / 64) for row in rows if row.get("raw_input_bytes"))
    return cycles, cycles * 4e-6


def raw_latency_samples_ms(rows: list[dict[str, str]]) -> list[float]:
    return [math.ceil(int(row["raw_input_bytes"]) / 64) * 4e-6 for row in rows if row.get("raw_input_bytes")]


def compute_performance(
    *,
    package_name: str,
    run_root: Path,
    hls_sweep_root: Path,
    u55c_root: Path,
    reports: dict[str, Path],
    deploy_log: Path | None = None,
) -> dict[str, Any]:
    validation_dir = hls_sweep_root / "production/u55c_validation"
    if not validation_dir.exists():
        validation_dir = hls_sweep_root / "production/validation"
    csynth_modules = parse_hls_modules(reports["csynth"])
    latency_summary = read_json(u55c_root / "latency_summary.json")
    deployment_manifest = read_json(u55c_root / "deployment_manifest.json")
    comparison = read_json(validation_dir / "comparison_summary.json")
    validation_manifest = read_json(validation_dir / "validation_manifest.json")
    qkeras_metrics = read_json(hls_sweep_root / "production/parity/qkeras_eval/metrics_summary.json")
    hls_metrics = read_json(hls_sweep_root / "production/parity/hls_eval/metrics_summary.json")
    parity_summary = read_json(hls_sweep_root / "production/parity/summary.json")
    prep_rows = read_csv(u55c_root / "prepared_inputs/manifest.csv")
    batch_rows = read_csv(u55c_root / "hardware_batches.csv")
    qkeras_rows = read_csv(hls_sweep_root / "production/parity/qkeras_per_sample.csv")
    hls_rows = read_csv(hls_sweep_root / "production/parity/hls_per_sample.csv")
    hw_rows = read_csv(u55c_root / "hardware_per_sample_enriched.csv")
    qkeras_stage = next((name for name in comparison if "Keras CPU" in name), "pruned_qat Keras CPU")
    hls_stage = next((name for name in comparison if "hls4ml CPU" in name), "hls4ml CPU")
    u55c_stage = next((name for name in comparison if "U55C" in name), "U55C hardware")
    classification_metrics = {
        u55c_stage: merge_stage_metrics(comparison.get(u55c_stage, {}), hw_rows),
        hls_stage: merge_stage_metrics(comparison.get(hls_stage, {}), hls_rows, metric_subset(hls_metrics)),
        qkeras_stage: merge_stage_metrics(comparison.get(qkeras_stage, {}), qkeras_rows, metric_subset(qkeras_metrics)),
    }
    model_name = model_module_name(csynth_modules)
    model_cycles = int(csynth_modules.get(model_name or "", {}).get("latency_cycles") or 0)
    model_ms_per_sample = model_cycles * 4e-6
    deploy_log_summary = parse_deploy_log(deploy_log)
    inference_ms = deploy_log_summary["latency_ms_per_batch"]
    per_batch = []
    for row in batch_rows:
        start = int(row["first_sample_index"])
        stop = int(row["last_sample_index"])
        real_batch_size = int(row.get("real_batch_size") or (stop - start + 1))
        sample_rows = prep_rows[start : stop + 1]
        down_cycles, down_ms = raw_latency_for_rows(sample_rows)
        model_ms = model_cycles * real_batch_size * 4e-6
        observed_ms = float(row["wall_latency_us"]) / 1000.0
        per_batch.append(
            {
                "batch_index": int(row["batch_index"]),
                "real_batch_size": real_batch_size,
                "observed_ms": observed_ms,
                "inference_only_observed_ms": inference_ms[int(row["batch_index"])] if int(row["batch_index"]) < len(inference_ms) else None,
                "downsampler_estimated_ms": down_ms,
                "model_estimated_ms": model_ms,
                "coyote_shell_host_residual_ms": observed_ms - down_ms - model_ms,
                "raw_bytes": sum(int(sample["raw_input_bytes"]) for sample in sample_rows),
                "raw_axi_payload_beats": down_cycles,
            }
        )
    def mean(key: str) -> float | None:
        vals = [float(row[key]) for row in per_batch if row.get(key) is not None]
        return sum(vals) / len(vals) if vals else None

    batch_size = int(latency_summary.get("batch_size") or 0)
    raw_scan_samples = raw_latency_samples_ms(prep_rows)
    critical_samples = [raw_ms + model_ms_per_sample for raw_ms in raw_scan_samples]
    outer_minus_inference = [
        float(row["observed_ms"]) - float(row["inference_only_observed_ms"])
        for row in per_batch
        if row.get("inference_only_observed_ms") is not None
    ]

    shell = parse_vivado_util(reports["shell_top_util"])
    user_ip = parse_vivado_util(reports["model_wrapper_util"])
    full = parse_vivado_util(reports["shell_util"])
    added_over_shell: dict[str, Any] = {}
    integration_remainder: dict[str, Any] = {}
    fixed_static_platform: dict[str, Any] = {}
    dynamic_nonfixed: dict[str, Any] = {}
    post_route_residual_excluding_fixed: dict[str, Any] = {}
    for key, full_val in full.items():
        if key in shell and full_val.get("used") is not None and shell[key].get("used") is not None:
            added_over_shell[key] = (full_val["used"] or 0) - (shell[key]["used"] or 0)
        if full_val.get("used") is not None:
            fixed_static_platform[key] = full_val.get("fixed") or 0
            dynamic_nonfixed[key] = (full_val["used"] or 0) - (full_val.get("fixed") or 0)
        if (
            key in shell
            and key in user_ip
            and full_val.get("used") is not None
            and shell[key].get("used") is not None
            and user_ip[key].get("used") is not None
        ):
            integration_remainder[key] = (full_val["used"] or 0) - (shell[key]["used"] or 0) - (user_ip[key]["used"] or 0)
            post_route_residual_excluding_fixed[key] = (
                (full_val["used"] or 0)
                - (full_val.get("fixed") or 0)
                - (shell[key]["used"] or 0)
                - (user_ip[key]["used"] or 0)
            )

    return {
        "package_name": package_name,
        "run_root": str(run_root),
        "hls_sweep_root": str(hls_sweep_root),
        "deployment_manifest": deployment_manifest,
        "actual_observed": latency_summary,
        "latency_breakdown": {
            "semantics": "Separate FPGA critical-path estimate, observed Coyote inference-only timing, and observed Python outer wall timing.",
            "per_batch": per_batch,
            "fpga_critical_path_estimate": {
                "semantics": "Estimated per-sample device-side latency if raw downsampler plus hls4ml CNN are inserted into an FPGA critical path. It excludes Coyote host setup, Python overhead, and output readback.",
                "raw_scan_estimated_ms_per_sample": summarize(raw_scan_samples),
                "model_estimated_ms_per_sample": model_ms_per_sample,
                "total_estimated_ms_per_sample": summarize(critical_samples),
            },
            "inference_only_observed": {
                "semantics": "Observed timing printed by RawCoyoteOverlay around CoyoteInference::predict(); includes Coyote LOCAL_TRANSFER behavior and waits until the output transfer completes.",
                **deploy_log_summary,
                "latency_ms_per_full_batch_share_summary": summarize([value / batch_size for value in inference_ms]) if batch_size else summarize([]),
                "latency_ms_per_real_sample_share": (sum(inference_ms) / len(prep_rows)) if inference_ms and prep_rows else None,
            },
            "outer_wall_observed": {
                "semantics": "Observed Python wall time around overlay.predict_raw(...); includes raw setup/copy, flush, Coyote inference, output readback, and cleanup.",
                "latency_ms_per_batch_summary": summarize([float(row["observed_ms"]) for row in per_batch]),
                "throughput_samples_per_s": latency_summary.get("throughput_samples_per_s"),
                "sample_share_wall_latency_ms_mean": (latency_summary.get("sample_share_wall_latency_us_mean") or 0) / 1000.0,
            },
            "host_setup_copy_readback_overhead": {
                "semantics": "Outer wall time minus inference-only time for matching batches.",
                "latency_ms_per_batch_summary": summarize(outer_minus_inference),
            },
            "mean_ms_per_batch": {
                "observed_outer_wall": mean("observed_ms"),
                "observed_inference_only": mean("inference_only_observed_ms"),
                "host_setup_copy_readback_overhead": summarize(outer_minus_inference)["mean"],
                "downsampler_estimated": mean("downsampler_estimated_ms"),
                "model_estimated": mean("model_estimated_ms"),
                "hls_estimated_total": mean("downsampler_estimated_ms") + mean("model_estimated_ms") if mean("downsampler_estimated_ms") is not None and mean("model_estimated_ms") is not None else None,
            },
        },
        "hls_estimates": {
            "modules": csynth_modules,
            "model_module": model_name,
            "source": str(reports["csynth"]),
        },
        "implementation_vivado": {
            "shell_only_synth": {**shell, "source": str(reports["shell_top_util"])},
            "model_wrapper_hls_ip_synth": {**user_ip, "source": str(reports["model_wrapper_util"])},
            "full_cyt_top_post_route": {**full, "source": str(reports["shell_util"])},
            "added_over_shell": added_over_shell,
            "integration_remainder": integration_remainder,
            "resource_decomposition": {
                "semantics": "This decomposes the full routed cyt_top report into fixed static platform resources, shell_top synth, standalone model-wrapper IP synth, and the remaining non-fixed post-route/integration residual. This is not a true incremental-over-Coyote baseline; that requires a matched routed no-op Coyote build.",
                "fixed_static_platform": fixed_static_platform,
                "full_dynamic_nonfixed": dynamic_nonfixed,
                "post_route_residual_excluding_fixed": post_route_residual_excluding_fixed,
            },
            "timing_post_route": parse_shell_timing(reports["shell_timing"]),
        },
        "final_metrics": {
            "comparison_summary": comparison,
            "classification_metrics_by_stage": classification_metrics,
            "qkeras_cpu": metric_subset(qkeras_metrics),
            "hls4ml_cpu": metric_subset(hls_metrics),
            "u55c_hardware": metric_subset(next((v for k, v in comparison.items() if "U55C" in k), {})),
            "parity_summary": parity_summary,
            "u55c_vs_qkeras": parity_metrics(qkeras_rows, hw_rows),
            "u55c_vs_hls4ml": parity_metrics(hls_rows, hw_rows),
            "raw_reference_max_abs": validation_manifest.get("raw_reference_max_abs"),
            "sources": {
                "comparison_summary": str(validation_dir / "comparison_summary.json"),
                "validation_manifest": str(validation_dir / "validation_manifest.json"),
                "hardware_per_sample_enriched": str(u55c_root / "hardware_per_sample_enriched.csv"),
                "qkeras_metrics": str(hls_sweep_root / "production/parity/qkeras_eval/metrics_summary.json"),
                "hls_metrics": str(hls_sweep_root / "production/parity/hls_eval/metrics_summary.json"),
                "parity_summary": str(hls_sweep_root / "production/parity/summary.json"),
            },
        },
    }


def format_resource_table(perf: dict[str, Any]) -> str:
    scopes = [
        ("Shell-only synth", perf["implementation_vivado"]["shell_only_synth"]),
        ("Model wrapper IP synth", perf["implementation_vivado"]["model_wrapper_hls_ip_synth"]),
        ("Full routed cyt_top", perf["implementation_vivado"]["full_cyt_top_post_route"]),
    ]
    rows = ["| Scope | LUT | Registers | BRAM tile | URAM | DSP |", "| --- | ---: | ---: | ---: | ---: | ---: |"]
    for name, data in scopes:
        def cell(key: str) -> str:
            val = data.get(key, {})
            if not isinstance(val, dict) or val.get("used") is None:
                return "-"
            return f"{val['used']:g} / {val.get('util_percent', 0):g}%"
        rows.append(f"| {name} | {cell('clb_luts')} | {cell('clb_registers')} | {cell('bram_tile')} | {cell('uram')} | {cell('dsp')} |")
    return "\n".join(rows)


def _resource_keys() -> list[tuple[str, str]]:
    return [
        ("clb_luts", "LUT"),
        ("clb_registers", "Registers"),
        ("bram_tile", "BRAM tile"),
        ("uram", "URAM"),
        ("dsp", "DSP"),
    ]


def _resource_percent(value: Any, full: dict[str, Any], key: str) -> str:
    available = full.get(key, {}).get("available") if isinstance(full.get(key), dict) else None
    if value is None or not available:
        return "-"
    return f"{100.0 * float(value) / float(available):.4g}%"


def format_routed_resource_decomposition_table(perf: dict[str, Any]) -> str:
    impl = perf["implementation_vivado"]
    shell = impl.get("shell_only_synth", {})
    user_ip = impl.get("model_wrapper_hls_ip_synth", {})
    full = impl.get("full_cyt_top_post_route", {})
    decomposition = impl.get("resource_decomposition", {})
    fixed = decomposition.get("fixed_static_platform", {})
    residual = decomposition.get("post_route_residual_excluding_fixed", {})
    if not fixed:
        fixed = {key: full.get(key, {}).get("fixed") or 0 for key, _ in _resource_keys()}
    if not residual:
        residual = {}
        for key, _ in _resource_keys():
            full_used = full.get(key, {}).get("used") if isinstance(full.get(key), dict) else None
            shell_used = shell.get(key, {}).get("used") if isinstance(shell.get(key), dict) else None
            ip_used = user_ip.get(key, {}).get("used") if isinstance(user_ip.get(key), dict) else None
            fixed_used = fixed.get(key) or 0
            if full_used is not None and shell_used is not None and ip_used is not None:
                residual[key] = full_used - fixed_used - shell_used - ip_used

    rows = [
        "| Resource | shell_top synth | Model wrapper IP synth | Fixed static platform in routed cyt_top | Post-route integration residual | Full routed cyt_top |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for key, label in _resource_keys():
        def amount_with_pct(amount: Any) -> str:
            if amount is None:
                return "-"
            return f"{float(amount):g} / {_resource_percent(amount, full, key)}"

        shell_used = shell.get(key, {}).get("used") if isinstance(shell.get(key), dict) else None
        ip_used = user_ip.get(key, {}).get("used") if isinstance(user_ip.get(key), dict) else None
        full_used = full.get(key, {}).get("used") if isinstance(full.get(key), dict) else None
        rows.append(
            f"| {label} | {amount_with_pct(shell_used)} | {amount_with_pct(ip_used)} | "
            f"{amount_with_pct(fixed.get(key))} | {amount_with_pct(residual.get(key))} | "
            f"{amount_with_pct(full_used)} |"
        )
    return "\n".join(rows)


def format_hierarchy_resource_breakdown_table(perf: dict[str, Any]) -> str:
    impl = perf["implementation_vivado"]
    hierarchy = impl.get("routed_hierarchy_resource_breakdown", {})
    full = impl.get("full_cyt_top_post_route", {})
    rows = [
        "| Category | Instance(s) | LUT | Registers | BRAM tile | URAM | DSP |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    order = [
        "static_coyote_xdma_platform",
        "dynamic_coyote_control",
        "dynamic_coyote_mmu",
        "coyote_local_credit_fifos",
        "hls_model_wrapper_user_logic",
        "other_routed_glue_or_debug",
        "full_routed_cyt_top",
    ]
    if not hierarchy:
        return "\n".join(rows + ["| - | - | - | - | - | - | - |"])
    for key in order:
        data = hierarchy.get(key)
        if not isinstance(data, dict):
            continue
        label = data.get("label", key)
        instances = data.get("instances", "-")

        def cell(resource: str) -> str:
            value = data.get(resource)
            if value is None:
                return "-"
            return f"{float(value):g} / {_resource_percent(value, full, resource)}"

        rows.append(
            f"| {label} | `{instances}` | {cell('clb_luts')} | {cell('clb_registers')} | "
            f"{cell('bram_tile')} | {cell('uram')} | {cell('dsp')} |"
        )
    return "\n".join(rows)


def format_noop_coyote_reference_table(perf: dict[str, Any]) -> str:
    impl = perf["implementation_vivado"]
    noop = impl.get("noop_coyote_reference", {})
    full = impl.get("full_cyt_top_post_route", {})
    noop_full = noop.get("full_routed_cyt_top", {})
    delta = noop.get("production_minus_noop_full_routed", {})
    if not noop_full or not delta:
        return "No no-op Coyote reference is recorded in `results/performance_summary.json`."

    rows = [
        "| Resource | No-op Coyote full routed | Production full routed | Production minus no-op |",
        "| --- | ---: | ---: | ---: |",
    ]
    for key, label in _resource_keys():
        def cell(data: dict[str, Any], *, is_delta: bool = False) -> str:
            value = data.get(key)
            if value is None:
                return "-"
            if is_delta:
                return f"{float(value):g} / {_resource_percent(value, full, key)}"
            if isinstance(value, dict):
                return f"{float(value.get('used')):g} / {float(value.get('util_percent', 0.0)):.4g}%"
            return f"{float(value):g} / {_resource_percent(value, full, key)}"

        rows.append(f"| {label} | {cell(noop_full)} | {cell(full)} | {cell(delta, is_delta=True)} |")
    return "\n".join(rows)


def format_added_resource_attribution_comparison_table(perf: dict[str, Any]) -> str:
    impl = perf["implementation_vivado"]
    hierarchy = impl.get("routed_hierarchy_resource_breakdown", {})
    analytical = hierarchy.get("hls_model_wrapper_user_logic", {})
    noop = impl.get("noop_coyote_reference", {})
    delta = noop.get("production_minus_noop_full_routed", {})
    full = impl.get("full_cyt_top_post_route", {})
    if not analytical or not delta:
        return "Added-resource attribution comparison is not recorded in `results/performance_summary.json`."

    rows = [
        "| Resource | Analytical hierarchy: `inst_user_c0_0` | Full routed: production minus no-op |",
        "| --- | ---: | ---: |",
    ]
    for key, label in _resource_keys():
        def cell(value: Any) -> str:
            if value is None:
                return "-"
            return f"{float(value):g} / {_resource_percent(value, full, key)}"

        rows.append(f"| {label} | {cell(analytical.get(key))} | {cell(delta.get(key))} |")
    return "\n".join(rows)


def format_metrics_table(summary: dict[str, Any]) -> str:
    rows = [
        "| Stage | Acc | Bal acc | F1 | Precision | TPR/Recall | FPR | FNR | TNR | ROC AUC | PR AUC | BCE loss | TN | FP | FN | TP |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for stage, metrics in summary.items():
        rows.append(
            "| {stage} | {accuracy} | {balanced_accuracy} | {f1} | {precision} | {tpr} | {fpr} | {fnr} | {tnr} | {roc_auc} | {pr_auc} | {bce_loss} | {tn} | {fp} | {fn} | {tp} |".format(
                stage=stage,
                accuracy=fmt_num(metrics.get("accuracy")),
                balanced_accuracy=fmt_num(metrics.get("balanced_accuracy")),
                f1=fmt_num(metrics.get("f1")),
                precision=fmt_num(metrics.get("precision")),
                tpr=fmt_num(metrics.get("tpr", metrics.get("recall"))),
                fpr=fmt_num(metrics.get("fpr")),
                fnr=fmt_num(metrics.get("fnr")),
                tnr=fmt_num(metrics.get("tnr")),
                roc_auc=fmt_num(metrics.get("roc_auc")),
                pr_auc=fmt_num(metrics.get("pr_auc")),
                bce_loss=fmt_num(metrics.get("bce_loss")),
                tn=metrics.get("tn", "-"),
                fp=metrics.get("fp", "-"),
                fn=metrics.get("fn", "-"),
                tp=metrics.get("tp", "-"),
            )
        )
    return "\n".join(rows)


def fmt_num(value: Any, suffix: str = "") -> str:
    if value is None:
        return "-"
    try:
        return f"{float(value):.6g}{suffix}"
    except (TypeError, ValueError):
        return str(value)


def format_hls_component_table(perf: dict[str, Any]) -> str:
    modules = perf["hls_estimates"].get("modules", {})
    model_name = perf["hls_estimates"].get("model_module")
    rows = [
        "| Component | HLS module | Latency | BRAM_18K | DSP | FF | LUT | URAM |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    component_names = [
        ("Wrapper", "model_wrapper"),
        ("Downsampler", "raw_bitstream_downsample_to_input_stream"),
        ("hls4ml CNN", model_name),
    ]
    for label, module_name in component_names:
        data = modules.get(module_name or "", {})
        res = data.get("resources_estimated", {}) if isinstance(data, dict) else {}
        latency = "-"
        if data.get("latency_ms_at_250mhz") is not None:
            latency = f"{data['latency_ms_at_250mhz']:.6g} ms"
        rows.append(
            f"| {label} | `{module_name or '-'}` | {latency} | "
            f"{res.get('bram_18k', '-')} | {res.get('dsp', '-')} | {res.get('ff', '-')} | "
            f"{res.get('lut', '-')} | {res.get('uram', '-')} |"
        )
    return "\n".join(rows)


def write_report(package_dir: Path, package_name: str, perf: dict[str, Any]) -> None:
    observed = perf["actual_observed"]
    means = perf["latency_breakdown"]["mean_ms_per_batch"]
    critical = perf["latency_breakdown"]["fpga_critical_path_estimate"]
    inference = perf["latency_breakdown"]["inference_only_observed"]
    outer = perf["latency_breakdown"]["outer_wall_observed"]
    overhead = perf["latency_breakdown"]["host_setup_copy_readback_overhead"]
    timing = perf["implementation_vivado"]["timing_post_route"]
    final_metrics = perf["final_metrics"]
    qpar = final_metrics["u55c_vs_qkeras"]
    hpar = final_metrics["u55c_vs_hls4ml"]
    report = f"""# {package_name}

Production CoyoteAccelerator deployment package for raw-bitstream input, FPGA downsampling, and hls4ml CNN inference.

## Outcome

- Samples: `{observed.get('n_samples')}`
- Batch size: `{observed.get('batch_size')}`
- Timing status: `{timing.get('status')}`, WNS `{timing.get('wns_ns')}` ns, TNS `{timing.get('tns_ns')}` ns
- Raw downsampling parity max abs: `{final_metrics.get('raw_reference_max_abs')}`

## Final Classification Metrics

{format_metrics_table(final_metrics['classification_metrics_by_stage'])}

Parity against U55C hardware:

| Comparison | Agreement | Logit MAE | Max abs logit diff | Sign mismatches |
| --- | ---: | ---: | ---: | ---: |
| U55C vs Keras CPU | {qpar.get('prediction_agreement', float('nan')):.6g} | {qpar.get('logit_mae', float('nan')):.6g} | {qpar.get('logit_max_abs', float('nan')):.6g} | {qpar.get('sign_mismatches', '')} |
| U55C vs hls4ml CPU | {hpar.get('prediction_agreement', float('nan')):.6g} | {hpar.get('logit_mae', float('nan')):.6g} | {hpar.get('logit_max_abs', float('nan')):.6g} | {hpar.get('sign_mismatches', '')} |

## Latency

These are separate latency scopes. For "how much latency would this add to an FPGA critical path?", use the FPGA critical-path estimate.

### FPGA Critical-Path Estimate

| Metric | Value |
| --- | ---: |
| Estimated raw downsampler scan, mean | {fmt_num(critical['raw_scan_estimated_ms_per_sample']['mean'])} ms/sample |
| Estimated raw downsampler scan, min | {fmt_num(critical['raw_scan_estimated_ms_per_sample']['min'])} ms/sample |
| Estimated raw downsampler scan, max | {fmt_num(critical['raw_scan_estimated_ms_per_sample']['max'])} ms/sample |
| Estimated hls4ml CNN | {fmt_num(critical['model_estimated_ms_per_sample'])} ms/sample |
| Estimated FPGA critical-path total, mean | {fmt_num(critical['total_estimated_ms_per_sample']['mean'])} ms/sample |
| Estimated FPGA critical-path total, min | {fmt_num(critical['total_estimated_ms_per_sample']['min'])} ms/sample |
| Estimated FPGA critical-path total, max | {fmt_num(critical['total_estimated_ms_per_sample']['max'])} ms/sample |

This estimate covers raw bytes entering the HLS wrapper, FPGA downsampling, hls4ml CNN execution, and logit production. It excludes Python, host memory copies, Coyote driver setup, and output pointer conversion.

### Observed Coyote Inference-Only

| Metric | Value |
| --- | ---: |
| Observed inference-only mean | {fmt_num(inference['latency_ms_per_batch_summary']['mean'])} ms/batch |
| Observed inference-only min | {fmt_num(inference['latency_ms_per_batch_summary']['min'])} ms/batch |
| Observed inference-only max | {fmt_num(inference['latency_ms_per_batch_summary']['max'])} ms/batch |
| Inference-only full-batch share | {fmt_num(inference['latency_ms_per_full_batch_share_summary']['mean'])} ms/sample |
| Inference-only real-sample share | {fmt_num(inference['latency_ms_per_real_sample_share'])} ms/sample |
| Inference-only throughput | {fmt_num(inference['throughput_samples_per_s_summary']['mean'])} samples/s |

This is the timing printed by `RawCoyoteOverlay` around `CoyoteInference::predict()`. It includes Coyote `LOCAL_TRANSFER` behavior and waits until the output transfer completes.

### Observed Python Outer Wall

| Metric | Value |
| --- | ---: |
| Observed outer wall latency | {fmt_num(outer['latency_ms_per_batch_summary']['mean'])} ms/batch |
| Observed outer wall sample-share latency | {fmt_num(outer['sample_share_wall_latency_ms_mean'])} ms/sample |
| Observed outer wall throughput | {fmt_num(outer['throughput_samples_per_s'])} samples/s |
| Host setup/copy/readback overhead | {fmt_num(overhead['latency_ms_per_batch_summary']['mean'])} ms/batch |
| Estimated downsampler per batch | {means.get('downsampler_estimated', 0):.6g} ms |
| Estimated model per batch | {means.get('model_estimated', 0):.6g} ms |
| HLS estimated downsampler + model per batch | {means.get('hls_estimated_total', 0):.6g} ms |

Machine-readable latency scopes and per-batch values are in `results/performance_summary.json`.

## HLS Component Estimates

{format_hls_component_table(perf)}

## Resources

{format_resource_table(perf)}

### Routed Hierarchy Resource Breakdown

This uses the routed `cyt_top` hierarchy report. It is the clearest attribution for the apparent BRAM overhead: the non-model BRAM comes from Coyote/XDMA static resources, Coyote control/MMU logic, and local credit FIFOs around the user wrapper.

{format_hierarchy_resource_breakdown_table(perf)}

Important: this is not a true incremental-over-Coyote-shell baseline. A true paper-grade "added over Coyote" number needs a matched routed no-op Coyote build and should subtract that full routed baseline from this full routed design.

### Added Resource Attribution Comparison

This table keeps the two useful attribution views side-by-side. The hierarchy column is the routed HLS user-wrapper instance itself. The no-op column is the full routed production design minus the routed no-op/hello-world Coyote design.

{format_added_resource_attribution_comparison_table(perf)}

### No-op Coyote Reference

This compares against the no-op/hello-world Coyote routed build at `/mnt/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/datasets/full_dataset_it1/builds/BENIGN_FP00/build_hw/reports/config_0`. Use `Production minus no-op` as the best available full-design overhead relative to a basic Coyote design.

{format_noop_coyote_reference_table(perf)}

Machine-readable resource and latency details are in `results/performance_summary.json`.

## Important Files

| Artifact | Path |
| --- | --- |
| Bitstream manifest | `results/build_manifest.json` |
| Deployment manifest | `results/fpga_validation/deployment_manifest.json` |
| Validation manifest | `results/fpga_validation/validation_manifest.json` |
| Comparison summary | `results/fpga_validation/comparison_summary.json` |
| Performance summary | `results/performance_summary.json` |
| HLS synthesis report | `results/reports/model_wrapper_csynth.rpt` |
| Full routed utilization | `results/reports/shell_utilization.rpt` |
| Full routed hierarchical utilization | `results/reports/shell_routed_hierarchical_utilization.rpt` |
| No-op Coyote full routed utilization | `results/reports/noop_coyote_shell_utilization_c0.rpt` |
| No-op Coyote user synth utilization | `results/reports/noop_coyote_user_synthed_c0_0.rpt` |
| Full routed timing | `results/reports/shell_timing_summary.rpt` |

## Replay

From the FPGA host:

```bash
cd {package_dir}
./run_replay_raw_validation.sh
```

If the bitstream is already programmed:

```bash
PROGRAM=0 ./run_replay_raw_validation.sh
```

## Notes

- Heavy runtime artifacts and copied raw bitstreams live under `non_vcs_artifacts/`.
- `manifest.json` records SHA-256 and size for packaged files.
- Use the FPGA critical-path estimate for device-path impact, the inference-only timing for Coyote predict-call behavior, and the outer wall timing for application-level host runtime.
"""
    (package_dir / "MILESTONE_REPORT.md").write_text(report)


def write_manifest(package_dir: Path, name: str) -> dict[str, Any]:
    files = []
    for path in sorted(package_dir.rglob("*")):
        if path.is_file() and path.name != "manifest.json":
            rel = path.relative_to(package_dir)
            files.append(
                {
                    "path": str(rel),
                    "bytes": path.stat().st_size,
                    "sha256": sha256_file(path),
                }
            )
    manifest = {"name": name, "files": files}
    write_json(package_dir / "manifest.json", manifest)
    return manifest


def write_helpers(package_dir: Path) -> None:
    (package_dir / ".gitignore").write_text("non_vcs_artifacts/\nreplay/\n")
    (package_dir / "verify_manifest.py").write_text(
        """#!/usr/bin/env python3
import hashlib, json
from pathlib import Path
root = Path(__file__).resolve().parent
manifest = json.loads((root / "manifest.json").read_text())
for item in manifest["files"]:
    path = root / item["path"]
    if not path.exists():
        raise SystemExit(f"missing {path}")
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    if path.stat().st_size != item["bytes"] or h.hexdigest() != item["sha256"]:
        raise SystemExit(f"mismatch {path}")
print("manifest OK")
"""
    )
    os.chmod(package_dir / "verify_manifest.py", 0o755)
    (package_dir / "make_manifest.py").write_text(
        """#!/usr/bin/env python3
import subprocess, sys
subprocess.run([sys.executable, "verify_manifest.py"], check=True)
"""
    )
    os.chmod(package_dir / "make_manifest.py", 0o755)


def write_replay_script(package_dir: Path, project_name: str) -> None:
    script = f"""#!/usr/bin/env bash
set -euo pipefail

PKG=${{PKG:-{package_dir}}}
ML_ROOT=${{ML_ROOT:-/pub/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/ml_baseline}}
VENV=${{VENV:-$ML_ROOT/.venv_hls4ml}}
PROGRAM=${{PROGRAM:-1}}
NTFY_TOPIC=${{NTFY_TOPIC:-coyote-build-sdeheredia}}
LOG_DIR="$PKG/replay/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/replay_$(date +%Y%m%d_%H%M%S).log"

notify() {{
  curl -s -d "$1" "https://ntfy.sh/$NTFY_TOPIC" >/dev/null || true
}}

trap 'status=$?; if [ "$status" -eq 0 ]; then notify "{project_name} replay OK on $(hostname); log=$LOG"; else notify "{project_name} replay FAILED status=$status on $(hostname); log=$LOG"; fi' EXIT

{{
  echo "[replay] host=$(hostname)"
  echo "[replay] start=$(date -Is)"
  set +u
  source "$VENV/bin/activate"
  source /tools/Xilinx/Vitis/2024.2/settings64.sh
  set -u
  export PYTHONPATH="$ML_ROOT/hls4ml:$ML_ROOT:${{PYTHONPATH:-}}"
  cd "$ML_ROOT"
  if [ "$PROGRAM" = "1" ]; then
    echo "[replay] programming FPGA is handled by the packaged validation helper"
  fi
  python "$PKG/replay_validate.py" --package "$PKG" --project-name "{project_name}" --program "$PROGRAM"
  echo "[replay] end=$(date -Is)"
}} 2>&1 | tee "$LOG"
"""
    path = package_dir / "run_replay_raw_validation.sh"
    path.write_text(script)
    os.chmod(path, 0o755)
    (package_dir / "replay_validate.py").write_text(
        """#!/usr/bin/env python3
from __future__ import annotations
import argparse, csv, json, sys
from pathlib import Path
import numpy as np

ML_ROOT = Path("/pub/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/ml_baseline")
sys.path.insert(0, str(ML_ROOT / "hls4ml"))
sys.path.insert(0, str(ML_ROOT))
from pipeline.coyote_accelerator.raw_overlay import RawCoyoteOverlay

def read_csv(path):
    with open(path, newline="") as handle:
        return list(csv.DictReader(handle))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--package", required=True, type=Path)
    ap.add_argument("--project-name", required=True)
    ap.add_argument("--program", default="1")
    args = ap.parse_args()
    pkg = args.package.resolve()
    runtime_project = pkg / "non_vcs_artifacts/runtime_project"
    rows = read_csv(pkg / "non_vcs_artifacts/prepared_inputs/manifest.csv")
    labels = np.load(pkg / "non_vcs_artifacts/prepared_inputs/labels.npy").astype(np.int32)
    overlay = RawCoyoteOverlay(runtime_project, project_name=args.project_name)
    if args.program == "1":
        overlay.program_hacc_fpga()
    raw = [np.fromfile(row["raw_input_path"], dtype=np.uint8) for row in rows]
    batch_size = int(json.loads((pkg / "results/performance_summary.json").read_text())["actual_observed"]["batch_size"])
    pad = (-len(raw)) % batch_size
    if pad:
        raw.extend([raw[-1]] * pad)
    pred = overlay.predict_raw(raw, (1,), batch_size).reshape(-1)[:len(rows)]
    out = pkg / "replay/fpga_validation"
    out.mkdir(parents=True, exist_ok=True)
    with (out / "predictions.csv").open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["sample_index", "label", "logit", "predicted_label", "correct"])
        for idx, (label, logit) in enumerate(zip(labels, pred)):
            plabel = int(float(logit) >= 0.0)
            writer.writerow([idx, int(label), float(logit), plabel, plabel == int(label)])
    acc = float(np.mean((pred >= 0.0).astype(np.int32) == labels))
    (out / "replay_summary.json").write_text(json.dumps({"n": len(labels), "accuracy": acc}, indent=2) + "\\n")
    print(json.dumps({"n": len(labels), "accuracy": acc}, indent=2))

if __name__ == "__main__":
    main()
"""
    )
    os.chmod(package_dir / "replay_validate.py", 0o755)


def package(args: argparse.Namespace) -> None:
    run_root = args.run_root.resolve()
    hls_sweep_root = args.hls_sweep_root.resolve()
    package_dir = args.output.resolve()
    if package_dir.exists():
        raise FileExistsError(package_dir)
    package_dir.mkdir(parents=True)

    u55c_root = hls_sweep_root / "production/u55c_deployment"
    validation_dir = hls_sweep_root / "production/u55c_validation"
    if not validation_dir.exists():
        validation_dir = hls_sweep_root / "production/validation"
    bit_manifest = read_json(u55c_root / "bitstream_manifest.json")
    project_dir = Path(bit_manifest["project_dir"])
    build_root = project_dir / "build"
    reports = {
        "csynth": find_one(build_root, "csynth.rpt"),
        "csynth_design_size": find_one(build_root, "csynth_design_size.rpt"),
        "model_wrapper_util": find_one(build_root, "model_wrapper_hls_ip_utilization_synth.rpt"),
        "shell_top_util": find_one(build_root, "shell_top_utilization_synth.rpt"),
        "shell_util": find_one(build_root, "shell_utilization.rpt"),
        "shell_timing": find_one(build_root, "shell_timing_summary.rpt"),
    }
    perf = compute_performance(
        package_name=args.name,
        run_root=run_root,
        hls_sweep_root=hls_sweep_root,
        u55c_root=u55c_root,
        reports=reports,
        deploy_log=args.log,
    )

    # Reports and validation outputs.
    copy_file(reports["csynth"], package_dir / "results/reports/model_wrapper_csynth.rpt")
    copy_file(reports["csynth_design_size"], package_dir / "results/reports/csynth_design_size.rpt")
    copy_file(reports["model_wrapper_util"], package_dir / "results/reports/model_wrapper_hls_ip_utilization_synth.rpt")
    copy_file(reports["shell_top_util"], package_dir / "results/reports/shell_top_utilization_synth.rpt")
    copy_file(reports["shell_util"], package_dir / "results/reports/shell_utilization.rpt")
    copy_file(reports["shell_timing"], package_dir / "results/reports/shell_timing_summary.rpt")
    for src, dst in [
        (u55c_root / "bitstream_manifest.json", package_dir / "results/build_manifest.json"),
        (u55c_root / "deployment_manifest.json", package_dir / "results/fpga_validation/deployment_manifest.json"),
        (u55c_root / "latency_summary.json", package_dir / "results/fpga_validation/latency_summary.json"),
        (u55c_root / "hardware_batches.csv", package_dir / "results/fpga_validation/hardware_batches.csv"),
        (u55c_root / "hardware_per_sample.csv", package_dir / "results/fpga_validation/hardware_per_sample.csv"),
        (u55c_root / "hardware_per_sample_enriched.csv", package_dir / "results/fpga_validation/hardware_per_sample_enriched.csv"),
        (validation_dir / "comparison_summary.json", package_dir / "results/fpga_validation/comparison_summary.json"),
        (validation_dir / "validation_manifest.json", package_dir / "results/fpga_validation/validation_manifest.json"),
        (validation_dir / "stage_comparison_plots.png", package_dir / "results/fpga_validation/stage_comparison_plots.png"),
        (u55c_root / "coyote_accelerator_project/compile_smoke_summary.json", package_dir / "results/compile_smoke/compile_smoke_summary.json"),
        (u55c_root / "coyote_accelerator_project/compile_smoke_predictions.csv", package_dir / "results/compile_smoke/compile_smoke_predictions.csv"),
        (args.log, package_dir / "results/logs/deploy_validate.log"),
        (hls_sweep_root / "production/parity/summary.json", package_dir / "results/parity/summary.json"),
        (hls_sweep_root / "production/parity/parity.csv", package_dir / "results/parity/parity.csv"),
        (hls_sweep_root / "production/parity/qkeras_per_sample.csv", package_dir / "results/parity/qkeras_per_sample.csv"),
        (hls_sweep_root / "production/parity/hls_per_sample.csv", package_dir / "results/parity/hls_per_sample.csv"),
        (hls_sweep_root / "production/parity/qkeras_eval/metrics_summary.json", package_dir / "results/parity/qkeras_metrics_summary.json"),
        (hls_sweep_root / "production/parity/hls_eval/metrics_summary.json", package_dir / "results/parity/hls_metrics_summary.json"),
    ]:
        if src:
            copy_file(Path(src), dst)
    write_json(package_dir / "results/performance_summary.json", perf)

    # Sources and configs.
    copy_file(args.config.resolve(), package_dir / "sources/configs/production.yaml")
    copy_file(HLS4ML_ROOT / "configs/hls4ml_hand_tuning" / args.hand_config, package_dir / "sources/configs/hand_tuning.yaml")
    copy_file(HLS4ML_ROOT / "AGENT_DOWNSAMPLING.md", package_dir / "sources/docs/AGENT_DOWNSAMPLING.md")
    for rel in [
        "pipeline/coyote_accelerator/project.py",
        "pipeline/coyote_accelerator/raw_data.py",
        "pipeline/coyote_accelerator/raw_overlay.py",
        "pipeline/coyote_accelerator/templates/host_libs.cpp",
        "pipeline/coyote_accelerator/templates/host_libs.hpp",
        "pipeline/coyote_accelerator/templates/zero_in_raw_downsample.hpp.in",
    ]:
        copy_file(HLS4ML_ROOT / rel, package_dir / "sources/ml_baseline/hls4ml" / rel)
    copy_tree(project_dir / "src", package_dir / "sources/generated_project/src")
    for fname in ["CMakeLists.txt", "hls4ml_config.yml"]:
        copy_file(project_dir / fname, package_dir / "sources/generated_project" / fname)
    for fname in ["full_hls_config.json", "build_manifest.json"]:
        copy_file(u55c_root / "coyote_accelerator_project" / fname, package_dir / "sources/generated_project" / fname)

    # Heavy artifacts.
    copy_tree(u55c_root / "prepared_inputs", package_dir / "non_vcs_artifacts/prepared_inputs")
    copy_tree(project_dir, package_dir / "non_vcs_artifacts/runtime_project")
    raw_rows = read_csv(u55c_root / "prepared_inputs/manifest.csv")
    raw_dir = package_dir / "non_vcs_artifacts/raw_bitstreams_by_vault"
    rewritten_rows = []
    for row in raw_rows:
        raw_src = Path(row["raw_input_path"])
        dst_name = f"{int(row['sample_index']):04d}_{raw_src.name}"
        raw_dst = raw_dir / dst_name
        copy_file(raw_src, raw_dst)
        new_row = dict(row)
        new_row["raw_input_path"] = str(raw_dst)
        rewritten_rows.append(new_row)
    write_csv(raw_dir / "production_test.csv", rewritten_rows)
    write_csv(package_dir / "non_vcs_artifacts/prepared_inputs/manifest.csv", rewritten_rows)
    raw_manifest = {
        "n_samples": len(rewritten_rows),
        "total_raw_bytes": sum(int(row["raw_input_bytes"]) for row in rewritten_rows),
        "csv": str(raw_dir / "production_test.csv"),
    }
    write_json(raw_dir / "raw_manifest.json", raw_manifest)

    write_report(package_dir, args.name, perf)
    write_helpers(package_dir)
    write_replay_script(package_dir, str(bit_manifest["project_name"]))
    write_manifest(package_dir, args.name)
    print(f"[package] wrote {package_dir}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--run-root", required=True, type=Path)
    parser.add_argument("--hls-sweep-root", required=True, type=Path)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--hand-config", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--log", required=True, type=Path)
    return parser.parse_args()


if __name__ == "__main__":
    package(parse_args())
