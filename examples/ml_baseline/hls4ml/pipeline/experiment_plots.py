"""Cross-experiment plotting utilities for hls4ml suite summaries."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Sequence

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from .experiment_suite import read_csv, safe_float, safe_int


def _ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def _empty_plot(path: Path, title: str, message: str = "No data") -> None:
    fig, ax = plt.subplots(figsize=(7, 4))
    ax.text(0.5, 0.5, message, ha="center", va="center", transform=ax.transAxes)
    ax.set_axis_off()
    ax.set_title(title)
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def _numeric_rows(rows: Sequence[dict[str, str]], key: str) -> list[dict[str, Any]]:
    out = []
    for row in rows:
        value = safe_float(row.get(key))
        res = safe_int(row.get("input_resolution"))
        layers = safe_int(row.get("num_layers"))
        if value is not None and res is not None and layers is not None:
            out.append({"resolution": res, "layers": layers, "value": value, "row": row})
    return out


def heatmap(rows: Sequence[dict[str, str]], key: str, path: Path, title: str, cmap: str = "viridis") -> None:
    points = _numeric_rows(rows, key)
    if not points:
        _empty_plot(path, title)
        return
    resolutions = sorted({point["resolution"] for point in points})
    layers = sorted({point["layers"] for point in points})
    grid = np.full((len(layers), len(resolutions)), np.nan)
    for point in points:
        i = layers.index(point["layers"])
        j = resolutions.index(point["resolution"])
        grid[i, j] = point["value"]
    fig, ax = plt.subplots(figsize=(8, 5))
    image = ax.imshow(grid, cmap=cmap, aspect="auto")
    ax.set_xticks(range(len(resolutions)), [str(v) for v in resolutions])
    ax.set_yticks(range(len(layers)), [str(v) for v in layers])
    ax.set_xlabel("Input resolution")
    ax.set_ylabel("Layers")
    ax.set_title(title)
    for i, layer in enumerate(layers):
        for j, resolution in enumerate(resolutions):
            value = grid[i, j]
            label = "" if np.isnan(value) else f"{value:.3g}"
            ax.text(j, i, label, ha="center", va="center", color="white" if not np.isnan(value) else "black")
    fig.colorbar(image, ax=ax, shrink=0.85)
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def feasibility_heatmap(rows: Sequence[dict[str, str]], path: Path) -> None:
    tier_value = {"green": 2.0, "yellow": 1.0, "red": 0.0}
    mapped = []
    for row in rows:
        res = safe_int(row.get("input_resolution"))
        layers = safe_int(row.get("num_layers"))
        tier = str(row.get("tier", ""))
        if res is not None and layers is not None and tier in tier_value:
            mapped.append({**row, "feasibility_value": str(tier_value[tier])})
    heatmap(mapped, "feasibility_value", path, "Feasibility Tier", cmap="RdYlGn")


def line_by_resolution(rows: Sequence[dict[str, str]], metrics: Sequence[str], path: Path, title: str) -> None:
    fig, axes = plt.subplots(len(metrics), 1, figsize=(8, max(3, 2.7 * len(metrics))), sharex=True)
    if len(metrics) == 1:
        axes = [axes]
    has_data = False
    for ax, metric in zip(axes, metrics):
        for resolution in sorted({safe_int(row.get("input_resolution")) for row in rows if safe_int(row.get("input_resolution"))}):
            pts = []
            for row in rows:
                if safe_int(row.get("input_resolution")) != resolution:
                    continue
                value = safe_float(row.get(metric))
                layers = safe_int(row.get("num_layers"))
                if value is not None and layers is not None:
                    pts.append((layers, value))
            if pts:
                has_data = True
                pts.sort()
                ax.plot([p[0] for p in pts], [p[1] for p in pts], marker="o", label=str(resolution))
        if not any(safe_float(row.get(metric)) is not None for row in rows):
            ax.text(
                0.5,
                0.5,
                missing_metric_message(rows, metric),
                ha="center",
                va="center",
                transform=ax.transAxes,
                fontsize=9,
            )
            ax.set_yticks([])
        ax.set_ylabel(metric)
        ax.grid(True, alpha=0.3)
    axes[0].set_title(title)
    axes[-1].set_xlabel("Layers")
    if has_data:
        axes[0].legend(title="Resolution", fontsize=8)
        fig.tight_layout()
        fig.savefig(path, dpi=160)
        plt.close(fig)
    else:
        plt.close(fig)
        _empty_plot(path, title)


def missing_metric_message(rows: Sequence[dict[str, str]], metric: str) -> str:
    if not rows:
        return "No data"
    hls_rows = [row for row in rows if str(row.get("failure_stage", "")).lower() == "hls"]
    timeout_rows = [row for row in hls_rows if "timeout" in str(row.get("failure_reason", "")).lower()]
    if metric in {"latency", "LUT", "BRAM", "DSP"}:
        if len(timeout_rows) == len(rows):
            return f"No {metric} data\nall {len(rows)} candidates timed out in HLS"
        if hls_rows:
            return f"No {metric} data\n{len(hls_rows)}/{len(rows)} candidates failed in HLS"
        return f"No {metric} data\nsynthesis metrics are unavailable"
    return f"No {metric} data"


def diagonal_plot(rows: Sequence[dict[str, str]], pool_dim: int, path: Path, title: str) -> None:
    selected = []
    for row in rows:
        final = str(row.get("final_avg_pool", ""))
        if final in {f"[{pool_dim}, {pool_dim}]", f"[{pool_dim},{pool_dim}]"}:
            selected.append(row)
    line_by_resolution(selected, ["software_auc", "latency", "LUT", "BRAM", "DSP"], path, title)


def quantization_plot(rows: Sequence[dict[str, str]], path: Path) -> None:
    quant_rows = [row for row in rows if safe_int(row.get("weight_bits")) is not None]
    if not quant_rows:
        _empty_plot(path, "Quantization Sweep")
        return
    fig, axes = plt.subplots(2, 1, figsize=(8, 6), sharex=True)
    for metric, ax in [("software_auc", axes[0]), ("keras_hls4ml_prediction_agreement", axes[1])]:
        pts = []
        for row in quant_rows:
            bits = safe_int(row.get("weight_bits"))
            value = safe_float(row.get(metric))
            if bits is not None and value is not None:
                pts.append((bits, value))
        if pts:
            pts.sort(reverse=True)
            ax.plot([p[0] for p in pts], [p[1] for p in pts], marker="o")
        ax.set_ylabel(metric)
        ax.grid(True, alpha=0.3)
    axes[-1].set_xlabel("Weight/activation bits")
    axes[0].set_title("Quantization Sweep")
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def pruning_plot(rows: Sequence[dict[str, str]], path: Path) -> None:
    prune_rows = [row for row in rows if (safe_int(row.get("pruning_target")) or 0) > 0 or str(row.get("phase")) == "4.5"]
    if not prune_rows:
        _empty_plot(path, "Pruning Sweep")
        return
    fig, axes = plt.subplots(2, 1, figsize=(8, 6), sharex=True)
    for metric, ax in [("software_auc", axes[0]), ("actual_global_sparsity", axes[1])]:
        pts = []
        for row in prune_rows:
            target = safe_int(row.get("pruning_target"))
            value = safe_float(row.get(metric))
            if target is not None and value is not None:
                pts.append((target, value))
        if pts:
            pts.sort()
            ax.plot([p[0] for p in pts], [p[1] for p in pts], marker="o")
        ax.set_ylabel(metric)
        ax.grid(True, alpha=0.3)
    axes[-1].set_xlabel("Target sparsity (%)")
    axes[0].set_title("Pruning Sweep")
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def reuse_factor_plot(rows: Sequence[dict[str, str]], path: Path) -> None:
    rf_rows = [row for row in rows if str(row.get("phase")) == "5" or safe_int(row.get("reuse_factor")) not in (None, 1)]
    pts = []
    for row in rf_rows:
        rf = safe_int(row.get("reuse_factor"))
        latency = safe_float(row.get("latency"))
        lut = safe_float(row.get("LUT"))
        dsp = safe_float(row.get("DSP"))
        if rf is not None:
            pts.append((rf, latency, lut, dsp))
    if not pts:
        _empty_plot(path, "Reuse-Factor Sweep")
        return
    pts.sort()
    fig, axes = plt.subplots(1, 2, figsize=(10, 4))
    if any(p[1] is not None for p in pts):
        axes[0].plot([p[0] for p in pts], [p[1] for p in pts], marker="o")
    axes[0].set_xlabel("ReuseFactor")
    axes[0].set_ylabel("Latency cycles")
    axes[0].grid(True, alpha=0.3)
    for label, index in [("LUT", 2), ("DSP", 3)]:
        values = [(p[1], p[index]) for p in pts if p[1] is not None and p[index] is not None]
        if values:
            axes[1].scatter([p[0] for p in values], [p[1] for p in values], label=label)
    axes[1].set_xlabel("Latency cycles")
    axes[1].set_ylabel("Resource")
    if axes[1].get_legend_handles_labels()[0]:
        axes[1].legend()
    axes[1].grid(True, alpha=0.3)
    fig.suptitle("Reuse-Factor Sweep")
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def plot_results(summary: Path, output_dir: Path) -> list[Path]:
    rows = read_csv(summary)
    _ensure_dir(output_dir)
    outputs = [
        output_dir / "feasibility_heatmap.png",
        output_dir / "accuracy_heatmap.png",
        output_dir / "auc_heatmap.png",
        output_dir / "f1_heatmap.png",
        output_dir / "fnr_heatmap.png",
        output_dir / "latency_heatmap.png",
        output_dir / "lut_heatmap.png",
        output_dir / "bram_heatmap.png",
        output_dir / "dsp_heatmap.png",
        output_dir / "fixed_resolution_depth.png",
        output_dir / "final_pool_16_diagonal.png",
        output_dir / "final_pool_32_diagonal.png",
        output_dir / "quantization_sweep.png",
        output_dir / "pruning_sweep.png",
        output_dir / "reuse_factor_sweep.png",
    ]
    feasibility_heatmap(rows, outputs[0])
    heatmap(rows, "software_accuracy", outputs[1], "Software Accuracy")
    heatmap(rows, "software_auc", outputs[2], "ROC AUC")
    heatmap(rows, "software_f1", outputs[3], "F1")
    heatmap(rows, "false_negative_rate", outputs[4], "False Negative Rate", cmap="magma_r")
    heatmap(rows, "latency", outputs[5], "Latency Cycles", cmap="magma")
    heatmap(rows, "LUT", outputs[6], "LUT", cmap="magma")
    heatmap(rows, "BRAM", outputs[7], "BRAM", cmap="magma")
    heatmap(rows, "DSP", outputs[8], "DSP", cmap="magma")
    line_by_resolution(rows, ["software_auc", "software_f1", "latency", "LUT"], outputs[9], "Fixed-Resolution Depth Comparison")
    diagonal_plot(rows, 16, outputs[10], "16x16 Final-Pool Diagonal")
    diagonal_plot(rows, 32, outputs[11], "32x32 Final-Pool Diagonal")
    quantization_plot(rows, outputs[12])
    pruning_plot(rows, outputs[13])
    reuse_factor_plot(rows, outputs[14])
    return outputs
