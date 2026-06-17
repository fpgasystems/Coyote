"""Cross-experiment plotting utilities for hls4ml suite summaries."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Sequence

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from .device_resources import XCU55C_TOTAL_CLB_LUTS
from .experiment_suite import read_csv, safe_float, safe_int, write_csv


DEFAULT_CLOCK_PERIOD_NS = 5.0
DEVICE_LUT_CAPACITY = float(XCU55C_TOTAL_CLB_LUTS)
PROGRESS_COLUMNS = [
    ("Baseline", "P1/2/3", {"kind": "phase", "phases": {"1", "2", "3"}}),
    ("Quantization", "W2A2", {"kind": "quantization", "bits": 2}),
    ("Quantization", "W3A3", {"kind": "quantization", "bits": 3}),
    ("Quantization", "W4A4", {"kind": "quantization", "bits": 4}),
    ("Quantization", "W6A6", {"kind": "quantization", "bits": 6}),
    ("Quantization", "W8A8", {"kind": "quantization", "bits": 8}),
    ("Pruning", "P25", {"kind": "pruning", "target": 25}),
    ("Pruning", "P50", {"kind": "pruning", "target": 50}),
    ("Pruning", "P75", {"kind": "pruning", "target": 75}),
    ("Reuse Factor", "RF1", {"kind": "reuse_factor", "rf": 1}),
    ("Reuse Factor", "RF2", {"kind": "reuse_factor", "rf": 2}),
    ("Reuse Factor", "RF4", {"kind": "reuse_factor", "rf": 4}),
    ("Reuse Factor", "RF8", {"kind": "reuse_factor", "rf": 8}),
    ("Reuse Factor", "RF16", {"kind": "reuse_factor", "rf": 16}),
    ("Reuse Factor", "RF32", {"kind": "reuse_factor", "rf": 32}),
]
PROGRESS_STATUS_COLORS = {
    "empty": "#ffffff",
    "success": "#4caf50",
    "failed": "#d9534f",
    "skipped_red": "#9e9e9e",
    "running": "#4f81bd",
    "other": "#d9d9d9",
}


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


def with_derived_metrics(rows: Sequence[dict[str, str]]) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    for row in rows:
        derived = dict(row)
        latency = safe_float(row.get("latency"))
        if latency is not None:
            derived["latency_ms_5ns"] = str(latency * DEFAULT_CLOCK_PERIOD_NS / 1_000_000.0)
        lut = safe_float(row.get("LUT"))
        if lut is not None:
            derived["LUT_percent"] = str(lut / DEVICE_LUT_CAPACITY * 100.0)
        out.append(derived)
    return out


def _is_hand_optimized(row: dict[str, str]) -> bool:
    name = str(row.get("experiment_name", "")).lower()
    return (
        str(row.get("phase", "")) == "hand_tuning"
        or str(row.get("hls_tuning_mode", "")) == "manual_layers"
        or "manual" in name
    )


def _hand_variant_label(row: dict[str, str] | dict[str, Any]) -> str:
    name = str(row.get("experiment_name", ""))
    lower_name = name.lower()
    if "manual_v1_global" in lower_name:
        return "Manual v1 global"
    if "manual_v" in lower_name:
        version = lower_name.split("manual_v", 1)[1].split("_", 1)[0]
        if version:
            return f"Manual v{version}"
    if "manuala" in lower_name or "manual_a" in lower_name:
        return "ManualA"
    if "manual" in lower_name:
        return "Manual"
    return name


def _short_hand_point_label(row: dict[str, str] | dict[str, Any]) -> str:
    resolution = safe_int(row.get("input_resolution")) or safe_int(row.get("resolution"))
    prefix = f"{resolution} " if resolution is not None else ""
    return f"{prefix}{_hand_variant_label(row).replace('Manual v1 global', 'Manual v1')}"


def _is_manual_a(row: dict[str, str] | dict[str, Any]) -> bool:
    name = str(row.get("experiment_name", "")).lower()
    return "manuala" in name or "manual_a" in name


def _is_paper_plot_row(row: dict[str, str]) -> bool:
    if str(row.get("status", "")).lower() != "success":
        return False
    if safe_int(row.get("weight_bits")) != 8 or safe_int(row.get("activation_bits")) != 8:
        return False
    if safe_int(row.get("pruning_target")) != 50:
        return False
    name = str(row.get("experiment_name", ""))
    return "RFResource" in name or (_is_hand_optimized(row) and not _is_manual_a(row))


def _paper_group_label(row: dict[str, str]) -> str:
    resolution = safe_int(row.get("input_resolution"))
    layers = safe_int(row.get("num_layers"))
    prefix = f"{resolution}x{layers}" if resolution is not None and layers is not None else "Model"
    if _is_hand_optimized(row):
        variant = _hand_variant_label(row).replace("Manual v1 global", "Manual v1")
        return f"{prefix} {variant}"
    return f"{prefix} Resource"


def _paper_point_label(row: dict[str, str]) -> str:
    if _is_hand_optimized(row):
        return _short_hand_point_label(row)
    rf = safe_int(row.get("reuse_factor"))
    return f"RF{rf}" if rf is not None else "RF?"


def _paper_plot_points(
    rows: Sequence[dict[str, str]],
    *,
    max_layers_only: bool = False,
) -> list[dict[str, Any]]:
    candidate_rows = [row for row in rows if _is_paper_plot_row(row)]
    if max_layers_only:
        max_layers_by_resolution: dict[int, int] = {}
        for row in candidate_rows:
            resolution = safe_int(row.get("input_resolution"))
            layers = safe_int(row.get("num_layers"))
            if resolution is not None and layers is not None:
                max_layers_by_resolution[resolution] = max(layers, max_layers_by_resolution.get(resolution, layers))
        candidate_rows = [
            row
            for row in candidate_rows
            if safe_int(row.get("num_layers")) == max_layers_by_resolution.get(safe_int(row.get("input_resolution")))
        ]

    points: list[dict[str, Any]] = []
    for row in candidate_rows:
        latency = safe_float(row.get("latency"))
        lut = safe_float(row.get("LUT"))
        latency_ms = safe_float(row.get("latency_ms_5ns"))
        lut_percent = safe_float(row.get("LUT_percent"))
        f1 = safe_float(row.get("software_f1"))
        resolution = safe_int(row.get("input_resolution"))
        layers = safe_int(row.get("num_layers"))
        rf = safe_int(row.get("reuse_factor"))
        if None in (latency, lut, latency_ms, lut_percent, f1, resolution, layers):
            continue
        hand_optimized = _is_hand_optimized(row)
        points.append(
            {
                "latency": latency,
                "lut": lut,
                "latency_ms": latency_ms,
                "lut_percent": lut_percent,
                "f1": f1,
                "resolution": resolution,
                "layers": layers,
                "rf": rf if rf is not None else 1,
                "experiment_name": str(row.get("experiment_name", "")),
                "hand_optimized": hand_optimized,
                "label": _paper_group_label(row),
                "point_label": _paper_point_label(row),
            }
        )
    return points


def _compact_annotation_texts(texts: Sequence[str]) -> str:
    if len(texts) <= 1:
        return texts[0] if texts else ""
    parts = [text.split(" ", 1) for text in texts]
    if all(len(part) == 2 and part[0] == parts[0][0] for part in parts):
        return f"{parts[0][0]} {'/'.join(part[1].replace('Manual v1 global', 'Manual v1') for part in parts)}"
    return " / ".join(text.replace("Manual v1 global", "Manual v1") for text in texts)


def _merge_annotation_items(items: Sequence[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[tuple[Any, ...], dict[str, Any]] = {}
    for item in items:
        x, y = item["xy"]
        key = (
            round(float(x), 9),
            round(float(y), 9),
            item.get("merge_group", ""),
            item.get("color", "black"),
            item.get("fontweight", "normal"),
        )
        text = str(item["text"])
        if key not in grouped:
            grouped[key] = dict(item)
            grouped[key]["_texts"] = [text]
            continue
        if text not in grouped[key]["_texts"]:
            grouped[key]["_texts"].append(text)
        grouped[key]["text"] = _compact_annotation_texts(grouped[key]["_texts"])
        grouped[key]["arrow"] = bool(grouped[key].get("arrow")) or bool(item.get("arrow"))
    return [{key: value for key, value in item.items() if key != "_texts"} for item in grouped.values()]


def _annotation_offsets(count: int) -> list[tuple[int, int]]:
    base = [
        (6, 7),
        (8, -11),
        (-24, 8),
        (-30, -12),
        (14, 18),
        (-42, 18),
        (18, -24),
        (-54, -24),
        (0, 31),
        (0, -34),
        (36, 2),
        (-70, 2),
    ]
    offsets: list[tuple[int, int]] = []
    for radius in range(max(4, count + 2)):
        grow_x = radius * 18
        grow_y = radius * 11
        for x, y in base:
            offsets.append(
                (
                    x + (grow_x if x >= 0 else -grow_x),
                    y + (grow_y if y >= 0 else -grow_y),
                )
            )
    return offsets


def _place_non_overlapping_annotations(
    ax: plt.Axes,
    items: Sequence[dict[str, Any]],
    *,
    fontsize: int = 7,
) -> list[Any]:
    merged = _merge_annotation_items(items)
    if not merged:
        return []
    fig = ax.figure
    offsets = _annotation_offsets(len(merged))
    placed = []
    annotations = []
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    axes_bbox = ax.get_window_extent(renderer).expanded(1.0, 0.96)
    for index, item in enumerate(merged):
        best_annotation = None
        best_bbox = None
        for offset in offsets:
            annotation = ax.annotate(
                str(item["text"]),
                item["xy"],
                textcoords="offset points",
                xytext=offset,
                fontsize=fontsize,
                color=item.get("color", "black"),
                fontweight=item.get("fontweight", "normal"),
                zorder=item.get("zorder", 7),
            )
            fig.canvas.draw()
            renderer = fig.canvas.get_renderer()
            bbox = annotation.get_window_extent(renderer).expanded(1.03, 1.12)
            within_vertical_axes = axes_bbox.y0 <= bbox.y0 and bbox.y1 <= axes_bbox.y1
            if within_vertical_axes and not any(bbox.overlaps(existing) for existing in placed):
                best_annotation = annotation
                best_bbox = bbox
                break
            annotation.remove()
        if best_annotation is None:
            fallback = (86 if index % 2 == 0 else -112, -80 + index * 12)
            best_annotation = ax.annotate(
                str(item["text"]),
                item["xy"],
                textcoords="offset points",
                xytext=fallback,
                fontsize=fontsize,
                color=item.get("color", "black"),
                fontweight=item.get("fontweight", "normal"),
                zorder=item.get("zorder", 7),
            )
            fig.canvas.draw()
            renderer = fig.canvas.get_renderer()
            best_bbox = best_annotation.get_window_extent(renderer).expanded(1.03, 1.12)
        placed.append(best_bbox)
        annotations.append(best_annotation)
    return annotations


def _assert_no_annotation_overlaps(fig: plt.Figure, annotations: Sequence[Any], plot_name: str) -> None:
    if len(annotations) < 2:
        return
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    boxes = [annotation.get_window_extent(renderer).expanded(1.01, 1.06) for annotation in annotations]
    for i, left in enumerate(boxes):
        for j, right in enumerate(boxes[i + 1 :], start=i + 1):
            if left.overlaps(right):
                raise RuntimeError(f"{plot_name}: annotation labels overlap at indices {i} and {j}")


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
    pts.sort(key=lambda point: (point[0], point[1] is None, point[1] or 0.0, point[2] is None, point[2] or 0.0, point[3] is None, point[3] or 0.0))
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


def latency_lut_combined_plot(rows: Sequence[dict[str, str]], path: Path) -> None:
    points = []
    for row in rows:
        latency = safe_float(row.get("latency"))
        lut = safe_float(row.get("LUT"))
        latency_ms = safe_float(row.get("latency_ms_5ns"))
        lut_percent = safe_float(row.get("LUT_percent"))
        resolution = safe_int(row.get("input_resolution"))
        layers = safe_int(row.get("num_layers"))
        if None not in (latency, lut, latency_ms, lut_percent, resolution, layers):
            points.append(
                {
                    "latency": latency,
                    "lut": lut,
                    "latency_ms": latency_ms,
                    "lut_percent": lut_percent,
                    "resolution": resolution,
                    "layers": layers,
                    "experiment_name": str(row.get("experiment_name", "")),
                    "hand_optimized": _is_hand_optimized(row),
                    "hand_label": _short_hand_point_label(row) if _is_hand_optimized(row) else "",
                }
            )
    if not points:
        _empty_plot(path, "Latency vs LUT", "No latency/LUT data")
        return

    resolutions = sorted({point["resolution"] for point in points})
    cmap = plt.get_cmap("tab10")
    colors = {resolution: cmap(i % 10) for i, resolution in enumerate(resolutions)}
    fig, axes = plt.subplots(1, 2, figsize=(12, 5))
    for ax, x_key, y_key, x_label, y_label, title in [
        (axes[0], "latency", "lut", "Latency cycles", "LUT count", "Cycles vs LUT Count"),
        (axes[1], "latency_ms", "lut_percent", "Latency (ms @ 5.0 ns)", "LUT utilization (%)", "Milliseconds vs LUT %"),
    ]:
        for resolution in resolutions:
            selected = [point for point in points if point["resolution"] == resolution]
            ax.scatter(
                [point[x_key] for point in selected],
                [point[y_key] for point in selected],
                s=28,
                alpha=0.75,
                color=colors[resolution],
                label=f"{resolution}px",
            )
        hand_points = [point for point in points if point["hand_optimized"]]
        annotations = []
        if hand_points:
            ax.scatter(
                [point[x_key] for point in hand_points],
                [point[y_key] for point in hand_points],
                s=150,
                marker="*",
                facecolors="#f2c14e",
                edgecolors="black",
                linewidths=0.8,
                label="Hand-optimized",
                zorder=5,
            )
            annotations = _place_non_overlapping_annotations(
                ax,
                [
                    {
                        "xy": (point[x_key], point[y_key]),
                        "text": point["hand_label"],
                        "merge_group": "hand",
                        "fontweight": "bold",
                        "color": "#7a1f1f",
                        "arrow": True,
                    }
                    for point in hand_points
                ],
            )
            _assert_no_annotation_overlaps(fig, annotations, f"{path.name}:{title}")
        ax.set_xlabel(x_label)
        ax.set_ylabel(y_label)
        ax.set_title(title)
        ax.grid(True, alpha=0.3)
    axes[0].legend(title="Resolution", fontsize=8)
    fig.suptitle("Latency + LUT Combined View")
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def latency_lut_f1_tradeoff_plot(rows: Sequence[dict[str, str]], path: Path) -> None:
    points = []
    allowed_precisions = {(6, 6), (8, 8)}
    candidate_rows = []
    for row in rows:
        if str(row.get("status", "")).lower() != "success":
            continue
        weight_bits_int = safe_int(row.get("weight_bits"))
        activation_bits_int = safe_int(row.get("activation_bits"))
        if (weight_bits_int, activation_bits_int) not in allowed_precisions:
            continue
        pruning_target = safe_int(row.get("pruning_target"))
        if pruning_target != 50:
            continue
        resolution = safe_int(row.get("input_resolution"))
        layers = safe_int(row.get("num_layers"))
        if resolution is None or layers is None:
            continue
        candidate_rows.append((row, weight_bits_int, activation_bits_int, pruning_target, resolution, layers))

    max_layers_by_resolution: dict[int, int] = {}
    for _, _, _, _, resolution, layers in candidate_rows:
        max_layers_by_resolution[resolution] = max(layers, max_layers_by_resolution.get(resolution, layers))

    for row, weight_bits_int, activation_bits_int, pruning_target, resolution, layers in candidate_rows:
        if layers != max_layers_by_resolution.get(resolution):
            continue
        latency_ms = safe_float(row.get("latency_ms_5ns"))
        lut_percent = safe_float(row.get("LUT_percent"))
        f1 = safe_float(row.get("software_f1"))
        rf = safe_int(row.get("reuse_factor"))
        if None in (latency_ms, lut_percent, f1, resolution, layers):
            continue
        sweep_name = str(row.get("experiment_name", ""))
        hand_optimized = _is_hand_optimized(row)
        strategy = _hand_variant_label(row) if hand_optimized else ("Resource" if "RFResource" in sweep_name else "Latency")
        precision = f"W{weight_bits_int}A{activation_bits_int}"
        points.append(
            {
                "latency_ms": latency_ms,
                "lut_percent": lut_percent,
                "f1": f1,
                "resolution": resolution,
                "layers": layers,
                "rf": rf if rf is not None else 1,
                "point_label": _short_hand_point_label(row) if hand_optimized else f"RF{rf}",
                "hand_optimized": hand_optimized,
                "label": f"{resolution}x{layers} {precision} P{pruning_target} {strategy}",
            }
        )
    if not points:
        _empty_plot(
            path,
            "Latency/LUT/F1 Tradeoff (P50, W6A6/W8A8, Max Layers)",
            "No complete P50 W6A6/W8A8 max-layer latency/LUT/F1 data",
        )
        return

    labels = sorted({point["label"] for point in points})
    markers = ["o", "s", "^", "D", "P", "X", "v", "<", ">"]
    marker_by_label = {
        label: "*" if "Manual" in label else markers[i % len(markers)]
        for i, label in enumerate(labels)
    }

    fig, ax = plt.subplots(figsize=(9.5, 6.2))
    annotations = []
    for label in labels:
        selected = sorted((point for point in points if point["label"] == label), key=lambda point: point["rf"])
        scatter = ax.scatter(
            [point["latency_ms"] for point in selected],
            [point["lut_percent"] for point in selected],
            c=[point["f1"] for point in selected],
            cmap="viridis",
            vmin=min(point["f1"] for point in points),
            vmax=max(point["f1"] for point in points),
            s=150 if "Manual" in label else 70,
            marker=marker_by_label[label],
            edgecolor="black",
            linewidth=0.9 if "Manual" in label else 0.5,
            label=label,
            zorder=5 if "Manual" in label else 3,
        )
        if not all(point["hand_optimized"] for point in selected):
            ax.plot(
                [point["latency_ms"] for point in selected],
                [point["lut_percent"] for point in selected],
                color="0.55",
                linewidth=0.9,
                alpha=0.65,
                zorder=2,
            )
        for point in selected:
            annotations.append(
                {
                    "xy": (point["latency_ms"], point["lut_percent"]),
                    "text": point["point_label"],
                    "merge_group": label,
                    "fontweight": "bold" if point["hand_optimized"] else "normal",
                    "color": "#7a1f1f" if point["hand_optimized"] else "black",
                    "arrow": bool(point["hand_optimized"]),
                }
            )

    label_annotations = _place_non_overlapping_annotations(ax, annotations)
    _assert_no_annotation_overlaps(fig, label_annotations, path.name)

    cbar = fig.colorbar(scatter, ax=ax)
    cbar.set_label("Software F1")
    ax.set_xlabel("Latency (ms @ 5.0 ns)")
    ax.set_ylabel("LUT utilization (% of device)")
    ax.set_title("Latency, LUT, and F1 Tradeoff (P50, W6A6/W8A8, Max Layers)")
    ax.grid(True, alpha=0.3)
    ax.legend(title="Resolution x layers", fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=180)
    plt.close(fig)


def lut_f1_frontier_plot(rows: Sequence[dict[str, str]], path: Path) -> None:
    points = []
    for row in rows:
        lut_percent = safe_float(row.get("LUT_percent"))
        f1 = safe_float(row.get("software_f1"))
        resolution = safe_int(row.get("input_resolution"))
        if lut_percent is not None and f1 is not None and resolution is not None:
            points.append(
                {
                    "lut_percent": lut_percent,
                    "f1": f1,
                    "resolution": resolution,
                    "experiment_name": str(row.get("experiment_name", "")),
                    "hand_optimized": _is_hand_optimized(row),
                    "hand_label": _short_hand_point_label(row) if _is_hand_optimized(row) else "",
                }
            )
    if not points:
        _empty_plot(path, "Best F1 vs LUT Utilization", "No F1/LUT data")
        return

    points.sort(key=lambda point: (point["lut_percent"], -point["f1"], point["experiment_name"]))
    frontier = []
    best_f1 = -np.inf
    for point in points:
        if point["f1"] > best_f1:
            frontier.append(point)
            best_f1 = point["f1"]

    resolutions = sorted({point["resolution"] for point in points})
    cmap = plt.get_cmap("tab10")
    colors = {resolution: cmap(i % 10) for i, resolution in enumerate(resolutions)}
    fig, ax = plt.subplots(figsize=(9, 5.5))
    for resolution in resolutions:
        selected = [point for point in points if point["resolution"] == resolution]
        ax.scatter(
            [point["lut_percent"] for point in selected],
            [point["f1"] for point in selected],
            s=24,
            alpha=0.35,
            color=colors[resolution],
            label=f"{resolution}px",
        )
    hand_points = [point for point in points if point["hand_optimized"]]
    if hand_points:
        ax.scatter(
            [point["lut_percent"] for point in hand_points],
            [point["f1"] for point in hand_points],
            s=150,
            marker="*",
            facecolors="#f2c14e",
            edgecolors="black",
            linewidths=0.8,
            label="Hand-optimized",
            zorder=6,
        )
    ax.step(
        [point["lut_percent"] for point in frontier],
        [point["f1"] for point in frontier],
        where="post",
        linewidth=2.4,
        color="black",
        label="Best F1 at or below LUT %",
    )
    ax.scatter(
        [point["lut_percent"] for point in frontier],
        [point["f1"] for point in frontier],
        s=42,
        color="black",
        zorder=5,
    )
    annotation_items = [
        {
            "xy": (point["lut_percent"], point["f1"]),
            "text": point["experiment_name"].replace("_RFbase", ""),
            "merge_group": "frontier",
        }
        for point in frontier[-6:]
    ]
    annotation_items.extend(
        {
            "xy": (point["lut_percent"], point["f1"]),
            "text": point["hand_label"],
            "merge_group": "hand",
            "fontweight": "bold",
            "color": "#7a1f1f",
            "arrow": True,
        }
        for point in hand_points
    )
    annotations = _place_non_overlapping_annotations(ax, annotation_items)
    _assert_no_annotation_overlaps(fig, annotations, path.name)
    ax.set_xlabel("LUT utilization (% of device)")
    ax.set_ylabel("Maximum F1")
    ax.set_title("Best Achievable F1 as LUT Budget Increases")
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def latency_f1_frontier_plot(rows: Sequence[dict[str, str]], path: Path) -> None:
    points = []
    for row in rows:
        latency_ms = safe_float(row.get("latency_ms_5ns"))
        f1 = safe_float(row.get("software_f1"))
        resolution = safe_int(row.get("input_resolution"))
        if latency_ms is not None and f1 is not None and resolution is not None:
            points.append(
                {
                    "latency_ms": latency_ms,
                    "f1": f1,
                    "resolution": resolution,
                    "experiment_name": str(row.get("experiment_name", "")),
                    "hand_optimized": _is_hand_optimized(row),
                    "hand_label": _short_hand_point_label(row) if _is_hand_optimized(row) else "",
                }
            )
    if not points:
        _empty_plot(path, "Best F1 vs Latency Budget", "No F1/latency data")
        return

    points.sort(key=lambda point: (point["latency_ms"], -point["f1"], point["experiment_name"]))
    frontier = []
    best_f1 = -np.inf
    for point in points:
        if point["f1"] > best_f1:
            frontier.append(point)
            best_f1 = point["f1"]

    resolutions = sorted({point["resolution"] for point in points})
    cmap = plt.get_cmap("tab10")
    colors = {resolution: cmap(i % 10) for i, resolution in enumerate(resolutions)}
    fig, ax = plt.subplots(figsize=(9, 5.5))
    for resolution in resolutions:
        selected = [point for point in points if point["resolution"] == resolution]
        ax.scatter(
            [point["latency_ms"] for point in selected],
            [point["f1"] for point in selected],
            s=24,
            alpha=0.35,
            color=colors[resolution],
            label=f"{resolution}px",
        )
    hand_points = [point for point in points if point["hand_optimized"]]
    if hand_points:
        ax.scatter(
            [point["latency_ms"] for point in hand_points],
            [point["f1"] for point in hand_points],
            s=150,
            marker="*",
            facecolors="#f2c14e",
            edgecolors="black",
            linewidths=0.8,
            label="Hand-optimized",
            zorder=6,
        )
    ax.step(
        [point["latency_ms"] for point in frontier],
        [point["f1"] for point in frontier],
        where="post",
        linewidth=2.4,
        color="black",
        label="Best F1 at or below latency",
    )
    ax.scatter(
        [point["latency_ms"] for point in frontier],
        [point["f1"] for point in frontier],
        s=42,
        color="black",
        zorder=5,
    )
    annotation_items = [
        {
            "xy": (point["latency_ms"], point["f1"]),
            "text": point["experiment_name"].replace("_RFbase", ""),
            "merge_group": "frontier",
        }
        for point in frontier[-6:]
    ]
    annotation_items.extend(
        {
            "xy": (point["latency_ms"], point["f1"]),
            "text": point["hand_label"],
            "merge_group": "hand",
            "fontweight": "bold",
            "color": "#7a1f1f",
        }
        for point in hand_points
    )
    annotations = _place_non_overlapping_annotations(ax, annotation_items)
    _assert_no_annotation_overlaps(fig, annotations, path.name)
    ax.set_xlabel("Latency (ms @ 5.0 ns)")
    ax.set_ylabel("Maximum F1")
    ax.set_title("Best Achievable F1 as Latency Budget Increases")
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def latency_lut_combined_paper_plot(rows: Sequence[dict[str, str]], path: Path) -> None:
    points = _paper_plot_points(rows)
    if not points:
        _empty_plot(path, "Latency vs LUT (W8A8 P50, Resource Strategy)", "No W8A8 P50 resource/manual paper data")
        return

    labels = sorted({point["label"] for point in points}, key=lambda label: ("Manual" in label, label))
    cmap = plt.get_cmap("tab10")
    colors = {label: cmap(i % 10) for i, label in enumerate(labels)}
    markers = {label: "*" if "Manual" in label else "o" for label in labels}
    sizes = {label: 150 if "Manual" in label else 42 for label in labels}

    fig, axes = plt.subplots(1, 2, figsize=(12, 5))
    for ax, x_key, y_key, x_label, y_label, title in [
        (axes[0], "latency", "lut", "Latency cycles", "LUT count", "Cycles vs LUT Count"),
        (axes[1], "latency_ms", "lut_percent", "Latency (ms @ 5.0 ns)", "LUT utilization (%)", "Milliseconds vs LUT %"),
    ]:
        annotations = []
        for label in labels:
            selected = sorted((point for point in points if point["label"] == label), key=lambda point: point["rf"])
            ax.scatter(
                [point[x_key] for point in selected],
                [point[y_key] for point in selected],
                s=sizes[label],
                marker=markers[label],
                alpha=0.9,
                color=colors[label],
                edgecolor="black",
                linewidth=0.8 if "Manual" in label else 0.5,
                label=label,
                zorder=5 if "Manual" in label else 3,
            )
            if "Manual" not in label:
                ax.plot(
                    [point[x_key] for point in selected],
                    [point[y_key] for point in selected],
                    color=colors[label],
                    linewidth=0.9,
                    alpha=0.55,
                    zorder=2,
                )
            for point in selected:
                annotations.append(
                    {
                        "xy": (point[x_key], point[y_key]),
                        "text": point["point_label"],
                        "merge_group": label,
                        "fontweight": "bold" if point["hand_optimized"] else "normal",
                        "color": "#7a1f1f" if point["hand_optimized"] else "black",
                    }
                )
        label_annotations = _place_non_overlapping_annotations(ax, annotations, fontsize=7)
        _assert_no_annotation_overlaps(fig, label_annotations, f"{path.name}:{title}")
        ax.set_xlabel(x_label)
        ax.set_ylabel(y_label)
        ax.set_title(title)
        ax.grid(True, alpha=0.3)
    axes[0].legend(title="Sweep", fontsize=8)
    fig.suptitle("Latency + LUT Combined View (W8A8 P50, Resource Strategy)")
    fig.tight_layout()
    fig.savefig(path, dpi=180)
    plt.close(fig)


def latency_lut_f1_tradeoff_paper_plot(rows: Sequence[dict[str, str]], path: Path) -> None:
    points = _paper_plot_points(rows, max_layers_only=True)
    if not points:
        _empty_plot(
            path,
            "Latency/LUT/F1 Tradeoff (W8A8 P50, Resource Strategy)",
            "No complete W8A8 P50 max-layer resource/manual paper data",
        )
        return

    labels = sorted({point["label"] for point in points}, key=lambda label: ("Manual" in label, label))
    markers = ["o", "s", "^", "D", "P", "X", "v", "<", ">"]
    marker_by_label = {
        label: "*" if "Manual" in label else markers[i % len(markers)]
        for i, label in enumerate(labels)
    }

    fig, ax = plt.subplots(figsize=(9.5, 6.2))
    annotations = []
    scatter = None
    for label in labels:
        selected = sorted((point for point in points if point["label"] == label), key=lambda point: point["rf"])
        scatter = ax.scatter(
            [point["latency_ms"] for point in selected],
            [point["lut_percent"] for point in selected],
            c=[point["f1"] for point in selected],
            cmap="viridis",
            vmin=min(point["f1"] for point in points),
            vmax=max(point["f1"] for point in points),
            s=150 if "Manual" in label else 70,
            marker=marker_by_label[label],
            edgecolor="black",
            linewidth=0.9 if "Manual" in label else 0.5,
            label=label,
            zorder=5 if "Manual" in label else 3,
        )
        if "Manual" not in label:
            ax.plot(
                [point["latency_ms"] for point in selected],
                [point["lut_percent"] for point in selected],
                color="0.55",
                linewidth=0.9,
                alpha=0.65,
                zorder=2,
            )
        for point in selected:
            annotations.append(
                {
                    "xy": (point["latency_ms"], point["lut_percent"]),
                    "text": point["point_label"],
                    "merge_group": label,
                    "fontweight": "bold" if point["hand_optimized"] else "normal",
                    "color": "#7a1f1f" if point["hand_optimized"] else "black",
                }
            )

    label_annotations = _place_non_overlapping_annotations(ax, annotations, fontsize=7)
    _assert_no_annotation_overlaps(fig, label_annotations, path.name)

    if scatter is not None:
        cbar = fig.colorbar(scatter, ax=ax)
        cbar.set_label("Software F1")
    ax.set_xlabel("Latency (ms @ 5.0 ns)")
    ax.set_ylabel("LUT utilization (% of device)")
    ax.set_title("Latency, LUT, and F1 Tradeoff (W8A8 P50, Resource Strategy)")
    ax.grid(True, alpha=0.3)
    ax.legend(title="Sweep", fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=180)
    plt.close(fig)


def latency_lut_f1_tradeoff_paper_no_colorbar_plot(rows: Sequence[dict[str, str]], path: Path) -> None:
    points = _paper_plot_points(rows, max_layers_only=True)
    if not points:
        _empty_plot(
            path,
            "Latency/LUT/F1 Tradeoff (W8A8 P50, Resource Strategy)",
            "No complete W8A8 P50 max-layer resource/manual paper data",
        )
        return

    labels = sorted({point["label"] for point in points}, key=lambda label: ("Manual" in label, label))
    resolutions = sorted({int(point["resolution"]) for point in points})
    cmap = plt.get_cmap("tab10")
    color_by_resolution = {resolution: cmap(i % 10) for i, resolution in enumerate(resolutions)}
    markers = ["o", "s", "^", "D", "P", "X", "v", "<", ">"]
    marker_by_label = {
        label: "*" if "Manual" in label else markers[i % len(markers)]
        for i, label in enumerate(labels)
    }

    fig, ax = plt.subplots(figsize=(9.5, 6.2))
    annotations = []
    for label in labels:
        selected = sorted((point for point in points if point["label"] == label), key=lambda point: point["rf"])
        f1_values = sorted({round(float(point["f1"]), 6) for point in selected})
        f1_text = f"{f1_values[0]:.3f}" if len(f1_values) == 1 else f"{min(f1_values):.3f}-{max(f1_values):.3f}"
        legend_label = f"{label} (F1={f1_text})"
        color = color_by_resolution[int(selected[0]["resolution"])]
        ax.scatter(
            [point["latency_ms"] for point in selected],
            [point["lut_percent"] for point in selected],
            s=150 if "Manual" in label else 70,
            marker=marker_by_label[label],
            color=color,
            edgecolor="black",
            linewidth=0.9 if "Manual" in label else 0.5,
            label=legend_label,
            zorder=5 if "Manual" in label else 3,
        )
        if "Manual" not in label:
            ax.plot(
                [point["latency_ms"] for point in selected],
                [point["lut_percent"] for point in selected],
                color=color,
                linewidth=0.9,
                alpha=0.65,
                zorder=2,
            )
        for point in selected:
            annotations.append(
                {
                    "xy": (point["latency_ms"], point["lut_percent"]),
                    "text": point["point_label"],
                    "merge_group": label,
                    "fontweight": "bold" if point["hand_optimized"] else "normal",
                    "color": "#7a1f1f" if point["hand_optimized"] else "black",
                }
            )

    label_annotations = _place_non_overlapping_annotations(ax, annotations, fontsize=7)
    _assert_no_annotation_overlaps(fig, label_annotations, path.name)
    ax.set_xlabel("Latency (ms @ 5.0 ns)")
    ax.set_ylabel("LUT utilization (% of device)")
    ax.set_title("Latency, LUT, and F1 Tradeoff (W8A8 P50, Resource Strategy)")
    ax.grid(True, alpha=0.3)
    ax.legend(title="Sweep", fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=180)
    plt.close(fig)


def lut_f1_frontier_paper_plot(rows: Sequence[dict[str, str]], path: Path) -> None:
    points = _paper_plot_points(rows)
    if not points:
        _empty_plot(path, "Best F1 vs LUT Utilization (W8A8 P50, Resource Strategy)", "No W8A8 P50 resource/manual paper data")
        return

    points.sort(key=lambda point: (point["lut_percent"], -point["f1"], point["experiment_name"]))
    frontier = []
    best_f1 = -np.inf
    for point in points:
        if point["f1"] > best_f1:
            frontier.append(point)
            best_f1 = point["f1"]

    labels = sorted({point["label"] for point in points}, key=lambda label: ("Manual" in label, label))
    cmap = plt.get_cmap("tab10")
    colors = {label: cmap(i % 10) for i, label in enumerate(labels)}
    fig, ax = plt.subplots(figsize=(9, 5.5))
    for label in labels:
        selected = [point for point in points if point["label"] == label]
        ax.scatter(
            [point["lut_percent"] for point in selected],
            [point["f1"] for point in selected],
            s=150 if "Manual" in label else 34,
            marker="*" if "Manual" in label else "o",
            alpha=0.9 if "Manual" in label else 0.55,
            color=colors[label],
            edgecolor="black",
            linewidth=0.8 if "Manual" in label else 0.4,
            label=label,
            zorder=6 if "Manual" in label else 3,
        )
    ax.step(
        [point["lut_percent"] for point in frontier],
        [point["f1"] for point in frontier],
        where="post",
        linewidth=2.4,
        color="black",
        label="Best F1 at or below LUT %",
    )
    ax.scatter(
        [point["lut_percent"] for point in frontier],
        [point["f1"] for point in frontier],
        s=42,
        color="black",
        zorder=5,
    )
    annotation_items = [
        {
            "xy": (point["lut_percent"], point["f1"]),
            "text": point["point_label"] if not point["hand_optimized"] else point["point_label"],
            "merge_group": point["label"],
            "fontweight": "bold" if point["hand_optimized"] else "normal",
            "color": "#7a1f1f" if point["hand_optimized"] else "black",
        }
        for point in frontier[-6:]
    ]
    for point in points:
        if point["hand_optimized"] and point not in frontier[-6:]:
            annotation_items.append(
                {
                    "xy": (point["lut_percent"], point["f1"]),
                    "text": point["point_label"],
                    "merge_group": point["label"],
                    "fontweight": "bold",
                    "color": "#7a1f1f",
                }
            )
    annotations = _place_non_overlapping_annotations(ax, annotation_items, fontsize=7)
    _assert_no_annotation_overlaps(fig, annotations, path.name)
    ax.set_xlabel("LUT utilization (% of device)")
    ax.set_ylabel("Maximum F1")
    ax.set_title("Best F1 vs LUT Utilization (W8A8 P50, Resource Strategy)")
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=180)
    plt.close(fig)


def latency_f1_frontier_paper_plot(rows: Sequence[dict[str, str]], path: Path) -> None:
    points = _paper_plot_points(rows)
    if not points:
        _empty_plot(path, "Best F1 vs Latency Budget (W8A8 P50, Resource Strategy)", "No W8A8 P50 resource/manual paper data")
        return

    points.sort(key=lambda point: (point["latency_ms"], -point["f1"], point["experiment_name"]))
    frontier = []
    best_f1 = -np.inf
    for point in points:
        if point["f1"] > best_f1:
            frontier.append(point)
            best_f1 = point["f1"]

    labels = sorted({point["label"] for point in points}, key=lambda label: ("Manual" in label, label))
    cmap = plt.get_cmap("tab10")
    colors = {label: cmap(i % 10) for i, label in enumerate(labels)}
    fig, ax = plt.subplots(figsize=(9, 5.5))
    for label in labels:
        selected = [point for point in points if point["label"] == label]
        ax.scatter(
            [point["latency_ms"] for point in selected],
            [point["f1"] for point in selected],
            s=150 if "Manual" in label else 34,
            marker="*" if "Manual" in label else "o",
            alpha=0.9 if "Manual" in label else 0.55,
            color=colors[label],
            edgecolor="black",
            linewidth=0.8 if "Manual" in label else 0.4,
            label=label,
            zorder=6 if "Manual" in label else 3,
        )
    ax.step(
        [point["latency_ms"] for point in frontier],
        [point["f1"] for point in frontier],
        where="post",
        linewidth=2.4,
        color="black",
        label="Best F1 at or below latency",
    )
    ax.scatter(
        [point["latency_ms"] for point in frontier],
        [point["f1"] for point in frontier],
        s=42,
        color="black",
        zorder=5,
    )
    annotation_items = [
        {
            "xy": (point["latency_ms"], point["f1"]),
            "text": point["point_label"],
            "merge_group": point["label"],
            "fontweight": "bold" if point["hand_optimized"] else "normal",
            "color": "#7a1f1f" if point["hand_optimized"] else "black",
        }
        for point in frontier[-6:]
    ]
    for point in points:
        if point["hand_optimized"] and point not in frontier[-6:]:
            annotation_items.append(
                {
                    "xy": (point["latency_ms"], point["f1"]),
                    "text": point["point_label"],
                    "merge_group": point["label"],
                    "fontweight": "bold",
                    "color": "#7a1f1f",
                }
            )
    annotations = _place_non_overlapping_annotations(ax, annotation_items, fontsize=7)
    _assert_no_annotation_overlaps(fig, annotations, path.name)
    ax.set_xlabel("Latency (ms @ 5.0 ns)")
    ax.set_ylabel("Maximum F1")
    ax.set_title("Best F1 vs Latency Budget (W8A8 P50, Resource Strategy)")
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=180)
    plt.close(fig)


def progress_column_matches(row: dict[str, str], spec: dict[str, Any]) -> bool:
    kind = spec["kind"]
    phase = str(row.get("phase", ""))
    if kind == "phase":
        return phase in spec["phases"]
    if kind == "quantization":
        bits = spec["bits"]
        return (
            phase in {"4", "4.5"}
            and safe_int(row.get("weight_bits")) == bits
            and safe_int(row.get("activation_bits")) == bits
            and (safe_int(row.get("pruning_target")) or 0) == 0
        )
    if kind == "pruning":
        return phase == "4.5" and safe_int(row.get("pruning_target")) == spec["target"]
    if kind == "reuse_factor":
        return phase == "5" and safe_int(row.get("reuse_factor")) == spec["rf"]
    return False


def progress_status(rows: Sequence[dict[str, str]]) -> tuple[str, str, dict[str, int]]:
    counts: dict[str, int] = {}
    for row in rows:
        status = str(row.get("status", "")) or "other"
        counts[status] = counts.get(status, 0) + 1
    if not counts:
        return "empty", "", counts
    parts = []
    for status, short in [("success", "ok"), ("failed", "fail"), ("running", "run"), ("skipped_red", "skip")]:
        count = counts.get(status, 0)
        if count:
            parts.append(f"{count} {short}" if count > 1 else short)
    other_count = sum(count for status, count in counts.items() if status not in {"success", "failed", "running", "skipped_red"})
    if other_count:
        parts.append(f"{other_count} other" if other_count > 1 else "other")
    if counts.get("success"):
        color_status = "success"
    elif counts.get("running"):
        color_status = "running"
    elif counts.get("failed"):
        color_status = "failed"
    elif counts.get("skipped_red"):
        color_status = "skipped_red"
    else:
        color_status = "other"
    return color_status, "\n".join(parts), counts


def experiment_progress_overview_plot(rows: Sequence[dict[str, str]], path: Path) -> None:
    configs = sorted(
        {
            (safe_int(row.get("input_resolution")), safe_int(row.get("num_layers")))
            for row in rows
            if safe_int(row.get("input_resolution")) is not None and safe_int(row.get("num_layers")) is not None
        }
    )
    if not configs:
        _empty_plot(path, "Experiment Progress Overview", "No experiment progress data")
        return

    rows_by_config: dict[tuple[int, int], list[dict[str, str]]] = {
        config: [
            row
            for row in rows
            if safe_int(row.get("input_resolution")) == config[0] and safe_int(row.get("num_layers")) == config[1]
        ]
        for config in configs
    }
    csv_rows = []
    fig_width = max(13.0, 0.78 * len(PROGRESS_COLUMNS) + 3.2)
    fig_height = max(8.0, 0.34 * len(configs) + 2.4)
    fig, ax = plt.subplots(figsize=(fig_width, fig_height))
    ax.set_xlim(0, len(PROGRESS_COLUMNS))
    ax.set_ylim(0, len(configs))
    ax.invert_yaxis()
    ax.set_xticks(np.arange(len(PROGRESS_COLUMNS)) + 0.5)
    ax.set_xticklabels([label for _, label, _ in PROGRESS_COLUMNS], rotation=45, ha="right")
    ax.set_yticks(np.arange(len(configs)) + 0.5)
    ax.set_yticklabels([f"{resolution}x{layers}" for resolution, layers in configs])
    ax.set_xlabel("Phase / setting")
    ax.set_ylabel("Input resolution x layers")
    ax.set_title("Global Experiment Progress Overview")

    for y, config in enumerate(configs):
        config_rows = rows_by_config[config]
        for x, (group, label, spec) in enumerate(PROGRESS_COLUMNS):
            matched = [row for row in config_rows if progress_column_matches(row, spec)]
            status, text, counts = progress_status(matched)
            rect = plt.Rectangle(
                (x, y),
                1,
                1,
                facecolor=PROGRESS_STATUS_COLORS[status],
                edgecolor="#bdbdbd",
                linewidth=0.8,
            )
            ax.add_patch(rect)
            if text:
                ax.text(x + 0.5, y + 0.5, text, ha="center", va="center", fontsize=6, color="black")
            csv_rows.append(
                {
                    "input_resolution": config[0],
                    "num_layers": config[1],
                    "column_group": group,
                    "column": label,
                    "status": status,
                    "success": counts.get("success", 0),
                    "failed": counts.get("failed", 0),
                    "running": counts.get("running", 0),
                    "skipped_red": counts.get("skipped_red", 0),
                    "other": sum(
                        count
                        for row_status, count in counts.items()
                        if row_status not in {"success", "failed", "running", "skipped_red"}
                    ),
                    "total": sum(counts.values()),
                    "experiments": ";".join(row.get("experiment_name", "") for row in matched),
                }
            )

    boundaries = []
    start = 0
    for i, (group, _, _) in enumerate(PROGRESS_COLUMNS + [("", "", {})]):
        if i == len(PROGRESS_COLUMNS) or group != PROGRESS_COLUMNS[start][0]:
            boundaries.append((start, i, PROGRESS_COLUMNS[start][0]))
            start = i
    for start, end, group in boundaries:
        if start:
            ax.axvline(start, color="#555555", linewidth=1.1)
        ax.text((start + end) / 2, -0.42, group, ha="center", va="center", fontsize=9, fontweight="bold")

    handles = [
        plt.Rectangle((0, 0), 1, 1, facecolor=PROGRESS_STATUS_COLORS[key], edgecolor="#bdbdbd", label=label)
        for key, label in [
            ("success", "success present"),
            ("failed", "failed only"),
            ("running", "running"),
            ("skipped_red", "skipped/red-tier"),
            ("empty", "not run"),
        ]
    ]
    ax.legend(handles=handles, loc="upper left", bbox_to_anchor=(1.01, 1.0), fontsize=8)
    ax.tick_params(length=0)
    for spine in ax.spines.values():
        spine.set_visible(False)
    fig.tight_layout()
    fig.savefig(path, dpi=170)
    plt.close(fig)

    write_csv(
        path.parent / "experiment_progress_summary.csv",
        csv_rows,
        fieldnames=[
            "input_resolution",
            "num_layers",
            "column_group",
            "column",
            "status",
            "success",
            "failed",
            "running",
            "skipped_red",
            "other",
            "total",
            "experiments",
        ],
    )


def plot_results(summary: Path, output_dir: Path) -> list[Path]:
    rows = with_derived_metrics(read_csv(summary))
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
        output_dir / "latency_ms_heatmap.png",
        output_dir / "lut_percent_heatmap.png",
        output_dir / "latency_lut_combined.png",
        output_dir / "lut_f1_frontier.png",
        output_dir / "latency_f1_frontier.png",
        output_dir / "latency_lut_f1_tradeoff.png",
        output_dir / "latency_lut_combined_paper.png",
        output_dir / "lut_f1_frontier_paper.png",
        output_dir / "latency_f1_frontier_paper.png",
        output_dir / "latency_lut_f1_tradeoff_paper.png",
        output_dir / "latency_lut_f1_tradeoff_paper_no_colorbar.png",
        output_dir / "experiment_progress_overview.png",
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
    heatmap(rows, "latency_ms_5ns", outputs[15], "Latency (ms @ 5.0 ns)", cmap="magma")
    heatmap(rows, "LUT_percent", outputs[16], "LUT Utilization (% of device)", cmap="magma")
    latency_lut_combined_plot(rows, outputs[17])
    lut_f1_frontier_plot(rows, outputs[18])
    latency_f1_frontier_plot(rows, outputs[19])
    latency_lut_f1_tradeoff_plot(rows, outputs[20])
    latency_lut_combined_paper_plot(rows, outputs[21])
    lut_f1_frontier_paper_plot(rows, outputs[22])
    latency_f1_frontier_paper_plot(rows, outputs[23])
    latency_lut_f1_tradeoff_paper_plot(rows, outputs[24])
    latency_lut_f1_tradeoff_paper_no_colorbar_plot(rows, outputs[25])
    experiment_progress_overview_plot(rows, outputs[26])
    return outputs
