"""Part 3 of the notebook flow: hls4ml conversion, emulation, tracing, and synthesis."""

from __future__ import annotations

import json
import re
import shutil
import time
from pathlib import Path
from typing import Any

import numpy as np

from .part1_common import (
    FlowContext,
    fold_dir,
    flow_candidate,
    metrics_from_stage_rows,
    parity_dir_for_fold,
    read_json,
    rows_from_logits,
    run_command,
    write_csv,
    write_json,
    write_metrics_summary,
    write_run_index,
    write_top_manifests,
)
from .part2_train import fold_cache_valid, get_splits, load_fold_model, sample_to_nhwc, weight_sparsity
from .qkeras_plots import build_split_info

from train import save_checkpoint_plots  # noqa: E402

def hls_config_for_model(ctx: FlowContext, model) -> dict:
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


def qkeras_hls_config_for_model(ctx: FlowContext, model) -> dict:
    return hls_config_for_model(ctx, model)


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
    config = hls_config_for_model(ctx, model)
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
    changed_predictions = sum(
        int(keras_row["predicted_label"]) != int(hls_row["predicted_label"])
        for keras_row, hls_row in zip(keras_rows, hls_rows)
    )
    prediction_agreement = 1.0 - changed_predictions / len(keras_rows) if keras_rows else 0.0
    qkeras_plot = save_stage_eval_artifacts(
        ctx,
        fold,
        parity_dir,
        "qkeras",
        keras_metrics,
        len(splits[fold][0]),
        f"{ctx.training_stage} Keras reference",
    )
    hls_plot = save_stage_eval_artifacts(ctx, fold, parity_dir, "hls", hls_metrics, len(splits[fold][0]), "hls4ml bit-accurate")
    summary = {
        "training_fingerprint": ctx.training_fingerprint,
        "hls_fingerprint": ctx.hls_fingerprint,
        "fold": fold,
        "n": int(len(labels)),
        "logit_mae": float(abs_err.mean()),
        "logit_max_abs": float(abs_err.max()),
        "mean_output_difference": float(abs_err.mean()),
        "max_output_difference": float(abs_err.max()),
        "sign_mismatches": int(np.sum((keras_logits >= 0.0) != (hls_logits >= 0.0))),
        "changed_predictions": int(changed_predictions),
        "prediction_agreement": float(prediction_agreement),
        "keras_accuracy": float(keras_metrics["accuracy"]),
        "qkeras_accuracy": float(keras_metrics["accuracy"]),
        "hls_accuracy": float(hls_metrics["accuracy"]),
        "keras_pr_auc": float(keras_metrics["pr_auc"]),
        "qkeras_pr_auc": float(keras_metrics["pr_auc"]),
        "hls_pr_auc": float(hls_metrics["pr_auc"]),
        "keras_eval_plot": str(qkeras_plot),
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
                "mean_abs_keras": float(np.mean(np.abs(flat_keras))),
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
        axes[1].set_xlabel("Max |HLS - Keras|")
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
