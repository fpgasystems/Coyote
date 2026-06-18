"""Aggregate generated experiment configs and per-run artifacts into master tables."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Sequence

from .experiment_suite import (
    analyze_model_shape,
    load_generated_configs,
    metadata_for_config,
    read_csv,
    safe_float,
    safe_int,
    write_csv,
)


SUMMARY_FIELDS = [
    "experiment_name",
    "phase",
    "status",
    "tier",
    "input_resolution",
    "num_layers",
    "conv_filters",
    "final_feature_map_shape",
    "final_avg_pool",
    "final_pool_area",
    "final_pool_work",
    "weight_bits",
    "activation_bits",
    "pruning_target",
    "actual_global_sparsity",
    "actual_sparsity_per_layer",
    "nonzero_parameter_count",
    "reuse_factor",
    "hls_tuning_mode",
    "hls_layer_knob_signature",
    "software_accuracy",
    "software_auc",
    "software_pr_auc",
    "software_precision",
    "software_recall",
    "software_f1",
    "false_positive_rate",
    "false_negative_rate",
    "confusion_matrix",
    "keras_hls4ml_prediction_agreement",
    "changed_predictions",
    "mean_output_difference",
    "max_output_difference",
    "hls4ml_conversion_status",
    "hls4ml_csim_status",
    "synthesis_status",
    "LUT",
    "FF",
    "BRAM",
    "DSP",
    "latency",
    "clock_period",
    "failure_stage",
    "failure_reason",
    "run_root",
    "hls_sweep_root",
    "config_path",
]


def read_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}


def status_rows(results_dir: Path) -> dict[str, dict[str, str]]:
    rows = read_csv(results_dir / "suite_status.csv")
    out: dict[str, dict[str, str]] = {}
    for row in rows:
        out[str(row.get("experiment_name", ""))] = row
    return out


def build_context_roots(config_path: Path, config: dict[str, Any]) -> tuple[str, str]:
    from pipeline.notebook_flow import build_context, load_config

    loaded = load_config(config_path)
    experiment = loaded.get("experiment", {})
    selected_run_root = experiment.get("selected_run_root")
    selected_hls_sweep_root = experiment.get("selected_hls_sweep_root")
    ctx = build_context(
        loaded,
        config_path=config_path.resolve(),
        run_root_arg=Path(selected_run_root) if selected_run_root else None,
        hls_sweep_root_arg=Path(selected_hls_sweep_root) if selected_hls_sweep_root else None,
    )
    return str(ctx.run_root), str(ctx.hls_sweep_root)


def confusion_rates(confusion_matrix: Any) -> tuple[float | None, float | None]:
    if isinstance(confusion_matrix, str):
        try:
            confusion_matrix = json.loads(confusion_matrix)
        except Exception:
            return None, None
    try:
        tn, fp = [float(v) for v in confusion_matrix[0]]
        fn, tp = [float(v) for v in confusion_matrix[1]]
    except Exception:
        return None, None
    fpr = fp / (fp + tn) if fp + tn > 0 else None
    fnr = fn / (fn + tp) if fn + tp > 0 else None
    return fpr, fnr


def load_sparsity(run_root: Path) -> tuple[float | None, str, int | None]:
    rows = read_csv(run_root / "sparsity_fold_0.csv")
    if not rows:
        return None, "", None
    total = 0
    nonzero = 0
    per_layer: dict[str, float] = {}
    for row in rows:
        n_weights = safe_int(row.get("n_weights")) or 0
        n_nonzero = safe_int(row.get("n_nonzero_weights")) or 0
        total += n_weights
        nonzero += n_nonzero
        layer = str(row.get("layer", ""))
        zero_fraction = safe_float(row.get("zero_fraction"))
        if layer and zero_fraction is not None:
            per_layer[layer] = zero_fraction
    global_sparsity = 1.0 - (nonzero / total) if total else None
    return global_sparsity, json.dumps(per_layer, sort_keys=True), nonzero if total else None


def parity_from_files(hls_sweep_root: Path, primary_fold: int = 0) -> dict[str, Any]:
    parity_dir = hls_sweep_root / f"fold_{primary_fold}" / "parity"
    summary = read_json(parity_dir / "summary.json")
    keras_rows = read_csv(parity_dir / "qkeras_per_sample.csv")
    hls_rows = read_csv(parity_dir / "hls_per_sample.csv")
    changed = None
    agreement = None
    if keras_rows and hls_rows and len(keras_rows) == len(hls_rows):
        changed = sum(
            int(k.get("predicted_label", -1)) != int(h.get("predicted_label", -2))
            for k, h in zip(keras_rows, hls_rows)
        )
        agreement = 1.0 - changed / len(keras_rows) if keras_rows else None
    return {
        "changed_predictions": summary.get("changed_predictions", changed),
        "keras_hls4ml_prediction_agreement": summary.get("prediction_agreement", agreement),
        "mean_output_difference": summary.get("mean_output_difference", summary.get("logit_mae")),
        "max_output_difference": summary.get("max_output_difference", summary.get("logit_max_abs")),
        "hls4ml_csim_status": "success" if summary else "",
    }


def hls_from_files(hls_sweep_root: Path) -> dict[str, Any]:
    metrics = read_json(hls_sweep_root / "hls_metrics_summary.json")
    if not metrics:
        synth_rows = read_csv(hls_sweep_root / "synthesis_summary.csv")
        metrics = synth_rows[0] if synth_rows else {}
    return {
        "synthesis_status": "success" if metrics else "",
        "LUT": metrics.get("util_lut"),
        "FF": metrics.get("util_ff"),
        "BRAM": metrics.get("util_bram_18k"),
        "DSP": metrics.get("util_dsp"),
        "latency": metrics.get("latency_max_cycles"),
        "clock_period": metrics.get("target_clock_ns"),
    }


def training_metrics(run_root: Path) -> dict[str, Any]:
    metrics = read_json(run_root / "pooled" / "metrics_summary.json")
    if not metrics:
        metrics = read_json(run_root / "fold_0" / "metrics_summary.json")
    fpr, fnr = confusion_rates(metrics.get("confusion_matrix"))
    return {
        "software_accuracy": metrics.get("accuracy"),
        "software_auc": metrics.get("roc_auc"),
        "software_pr_auc": metrics.get("pr_auc"),
        "software_precision": metrics.get("precision"),
        "software_recall": metrics.get("recall"),
        "software_f1": metrics.get("f1"),
        "confusion_matrix": metrics.get("confusion_matrix"),
        "false_positive_rate": fpr,
        "false_negative_rate": fnr,
    }


def row_for_config(config_path: Path, config: dict[str, Any], statuses: dict[str, dict[str, str]]) -> dict[str, Any]:
    meta = metadata_for_config(config, config_path)
    shape = analyze_model_shape(config)
    exp_name = str(meta["experiment_name"])
    status = statuses.get(exp_name, {})
    run_root = status.get("run_root") or ""
    hls_sweep_root = status.get("hls_sweep_root") or ""
    if not run_root or not hls_sweep_root:
        try:
            run_root, hls_sweep_root = build_context_roots(config_path, config)
        except Exception:
            run_root, hls_sweep_root = "", ""
    run_path = Path(run_root) if run_root else Path()
    hls_path = Path(hls_sweep_root) if hls_sweep_root else Path()
    row: dict[str, Any] = {
        **meta,
        "status": status.get("status") or ("skipped_red" if meta["tier"] == "red" else "not_run"),
        "final_feature_map_shape": f"{shape['final_feature_map_height']}x{shape['final_feature_map_width']}x{shape['final_channels']}",
        "hls4ml_conversion_status": "success" if (hls_path / "fold_0" / "project" / "conversion_manifest.json").exists() else "",
        "failure_stage": status.get("failure_stage", ""),
        "failure_reason": status.get("failure_reason", ""),
        "run_root": run_root,
        "hls_sweep_root": hls_sweep_root,
    }
    row.update(training_metrics(run_path))
    row.update(parity_from_files(hls_path, int(config["candidate"].get("primary_fold", 0))))
    row.update(hls_from_files(hls_path))
    sparsity, per_layer, nonzero = load_sparsity(run_path)
    row.update(
        {
            "actual_global_sparsity": sparsity,
            "actual_sparsity_per_layer": per_layer,
            "nonzero_parameter_count": nonzero,
        }
    )
    if row["status"] == "not_run" and row.get("synthesis_status") == "success":
        row["status"] = "success"
    return row


def collect_results(config_dir: Path | str | Sequence[Path | str], artifacts_dir: Path, results_dir: Path) -> list[dict[str, Any]]:
    _ = artifacts_dir
    config_dirs = [config_dir] if isinstance(config_dir, (str, Path)) else list(config_dir)
    configs: list[tuple[Path, dict[str, Any]]] = []
    for current_config_dir in config_dirs:
        configs.extend(load_generated_configs(Path(current_config_dir)))
    statuses = status_rows(results_dir)
    rows = [row_for_config(path, cfg, statuses) for path, cfg in configs]
    rows.sort(key=lambda row: (int(row.get("input_resolution") or 0), int(row.get("num_layers") or 0), str(row["experiment_name"])))
    write_csv(results_dir / "experiment_summary.csv", rows, fieldnames=SUMMARY_FIELDS)
    res_depth = [row for row in rows if str(row.get("phase")) in {"1", "2", "3"} or row.get("weight_bits") == "float"]
    write_csv(results_dir / "resolution_depth_results.csv", res_depth, fieldnames=SUMMARY_FIELDS)
    return rows
