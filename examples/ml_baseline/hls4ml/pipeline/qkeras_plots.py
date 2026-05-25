"""Reuse parent train.py plotting utilities for QKeras QAT artifacts."""

from __future__ import annotations

import csv
import json
from pathlib import Path
from typing import Any, Callable, Sequence

import numpy as np

from .paths import ensure_ml_baseline_on_path

ensure_ml_baseline_on_path()

import matplotlib  # noqa: E402

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

from .device_resources import (
    RO_LUTS_PER_STANDALONE_RO,
    XCU55C_DYNAMIC_REGION_CLB_LUTS,
    XCU55C_TOTAL_CLB_LUTS,
)

from gradcam import select_default_sample_ids  # noqa: E402
from train import (  # noqa: E402
    compute_metrics_from_outputs,
    save_checkpoint_plots,
    save_evaluation_dashboard,
    save_kfold_curves,
    save_kfold_evaluation_artifacts,
    save_kfold_summary,
    save_training_curves,
)

TARGET_CLASS_NAMES = ("benign", "standalone")
_HISTORY_NONNUMERIC = {"epoch"}


def _to_float(value) -> float:
    if value is None or value == "" or value == "nan":
        return float("nan")
    try:
        return float(value)
    except (TypeError, ValueError):
        return float("nan")


def _to_int(value, default: int | None = None) -> int | None:
    if value is None or value == "":
        return default
    try:
        return int(value)
    except (TypeError, ValueError):
        try:
            return int(float(value))
        except (TypeError, ValueError):
            return default


def _row_correct(row: dict[str, Any]) -> bool:
    value = row.get("correct")
    if isinstance(value, bool):
        return value
    if value is None:
        pred = _to_int(row.get("predicted_label"))
        label = _to_int(row.get("class_label"))
        return pred is not None and label is not None and pred == label
    return str(value).strip().lower() in {"true", "1", "yes"}


def _sample_id(row: dict[str, Any]) -> str:
    return str(row.get("sample_id", ""))


def _class_name(label: int) -> str:
    return "standalone" if int(label) == 1 else "benign"


def _rows_for_class(rows: Sequence[dict[str, Any]], class_label: int) -> list[dict[str, Any]]:
    return [row for row in rows if _to_int(row.get("class_label")) == class_label]


def _write_empty_plot(path: Path, title: str, message: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fig, ax = plt.subplots(figsize=(8, 4))
    ax.axis("off")
    ax.set_title(title)
    ax.text(0.5, 0.5, message, ha="center", va="center", transform=ax.transAxes)
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def write_per_sample_diagnostic_plots(
    out_dir: Path,
    rows: Sequence[dict[str, Any]],
    title_prefix: str | None = None,
) -> dict[str, Path]:
    """Write per-sample score diagnostics from QKeras-style per-sample rows."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    prefix = f"{title_prefix}: " if title_prefix else ""
    paths = {
        "standalone_probability_vs_ro_count": out_dir / "standalone_probability_vs_ro_count.png",
        "standalone_probability_vs_full_fpga_lut_percent": out_dir
        / "standalone_probability_vs_full_fpga_lut_percent.png",
        "standalone_probability_vs_full_fpga_lut_percent_bubble_counts": out_dir
        / "standalone_probability_vs_full_fpga_lut_percent_bubble_counts.png",
        "standalone_detection_rate_vs_full_fpga_lut_percent": out_dir
        / "standalone_detection_rate_vs_full_fpga_lut_percent.png",
        "standalone_probability_vs_estimated_ro_lut_utilization": out_dir
        / "standalone_probability_vs_estimated_ro_lut_utilization.png",
        "benign_app_standalone_probability": out_dir / "benign_app_standalone_probability.png",
    }
    _plot_standalone_probability_vs_ro(rows, paths["standalone_probability_vs_ro_count"], prefix)
    write_ro_lut_percent_diagnostic_plots(out_dir, rows, title_prefix=title_prefix)
    write_ro_lut_utilization_diagnostic_plots(out_dir, rows, title_prefix=title_prefix)
    _plot_benign_app_standalone_probability(rows, paths["benign_app_standalone_probability"], prefix)
    return paths


def write_ro_lut_utilization_diagnostic_plots(
    out_dir: Path,
    rows: Sequence[dict[str, Any]],
    title_prefix: str | None = None,
    full_device_luts: int | float = XCU55C_TOTAL_CLB_LUTS,
    dynamic_region_luts: int | float = XCU55C_DYNAMIC_REGION_CLB_LUTS,
    ro_luts_per_ro: int | float = RO_LUTS_PER_STANDALONE_RO,
) -> dict[str, Path]:
    """Write standalone probability plots against RO LUT utilization."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    paths = {
        "standalone_probability_vs_estimated_ro_lut_utilization": out_dir
        / "standalone_probability_vs_estimated_ro_lut_utilization.png",
    }
    prefix = f"{title_prefix}: " if title_prefix else ""
    _plot_standalone_probability_vs_ro_lut_utilization(
        rows,
        paths["standalone_probability_vs_estimated_ro_lut_utilization"],
        prefix,
        full_device_luts,
        dynamic_region_luts,
        ro_luts_per_ro,
    )
    return paths


def write_ro_lut_percent_diagnostic_plots(
    out_dir: Path,
    rows: Sequence[dict[str, Any]],
    title_prefix: str | None = None,
    full_device_luts: int | float = XCU55C_TOTAL_CLB_LUTS,
    dynamic_region_luts: int | float = XCU55C_DYNAMIC_REGION_CLB_LUTS,
    ro_luts_per_ro: int | float = RO_LUTS_PER_STANDALONE_RO,
) -> dict[str, Path]:
    """Write standalone probability plots with RO LUTs normalized by LUT capacity."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    prefix = f"{title_prefix}: " if title_prefix else ""
    paths = {
        "standalone_probability_vs_full_fpga_lut_percent": out_dir
        / "standalone_probability_vs_full_fpga_lut_percent.png",
        "standalone_probability_vs_full_fpga_lut_percent_bubble_counts": out_dir
        / "standalone_probability_vs_full_fpga_lut_percent_bubble_counts.png",
        "standalone_detection_rate_vs_full_fpga_lut_percent": out_dir
        / "standalone_detection_rate_vs_full_fpga_lut_percent.png",
    }
    _plot_standalone_probability_vs_lut_percent(
        rows,
        paths["standalone_probability_vs_full_fpga_lut_percent"],
        prefix,
        denominator_luts=full_device_luts,
        ro_luts_per_ro=ro_luts_per_ro,
        title_suffix="Full-FPGA RO LUT Share",
        x_label="RO LUTs (% of full-FPGA LUTs)",
    )
    _plot_standalone_probability_vs_lut_percent_bubble_counts(
        rows,
        paths["standalone_probability_vs_full_fpga_lut_percent_bubble_counts"],
        prefix,
        denominator_luts=full_device_luts,
        ro_luts_per_ro=ro_luts_per_ro,
        title_suffix="Full-FPGA RO LUT Share",
        x_label="RO LUTs (% of full-FPGA LUTs)",
    )
    _plot_standalone_detection_rate_vs_lut_percent(
        rows,
        paths["standalone_detection_rate_vs_full_fpga_lut_percent"],
        prefix,
        denominator_luts=full_device_luts,
        ro_luts_per_ro=ro_luts_per_ro,
        title_suffix="Full-FPGA RO LUT Share",
        x_label="RO LUTs (% of full-FPGA LUTs, binned)",
    )
    return paths


def _plot_standalone_probability_vs_ro(rows: Sequence[dict[str, Any]], path: Path, prefix: str) -> None:
    points = []
    for row in _rows_for_class(rows, 1):
        ro = _to_float(row.get("ro_count"))
        prob = _to_float(row.get("probability"))
        if np.isfinite(ro) and np.isfinite(prob):
            points.append((ro, prob, _row_correct(row), _sample_id(row)))
    if not points:
        _write_empty_plot(path, f"{prefix}Standalone Probability vs RO Count", "No standalone rows with numeric ro_count")
        return

    fig, ax = plt.subplots(figsize=(9, 5))
    for correct, marker, color, label in [
        (True, "o", "tab:red", "correct standalone"),
        (False, "x", "black", "miss"),
    ]:
        xs = [p[0] for p in points if p[2] is correct]
        ys = [p[1] for p in points if p[2] is correct]
        if xs:
            ax.scatter(xs, ys, marker=marker, s=54, color=color, alpha=0.85, label=label)
    ax.axhline(0.5, color="gray", linestyle=":", linewidth=1)
    ax.set_title(f"{prefix}Standalone Probability vs RO Count")
    ax.set_xlabel("RO count")
    ax.set_ylabel("Standalone probability")
    ax.set_ylim(-0.03, 1.03)
    ax.grid(True, axis="y", alpha=0.25)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def _plot_standalone_probability_vs_lut_percent(
    rows: Sequence[dict[str, Any]],
    path: Path,
    prefix: str,
    denominator_luts: int | float,
    ro_luts_per_ro: int | float,
    title_suffix: str,
    x_label: str,
) -> None:
    try:
        denominator = float(denominator_luts)
    except (TypeError, ValueError):
        denominator = float("nan")
    try:
        ro_luts = float(ro_luts_per_ro)
    except (TypeError, ValueError):
        ro_luts = float("nan")
    if not np.isfinite(denominator) or denominator <= 0:
        _write_empty_plot(path, f"{prefix}Standalone Probability vs {title_suffix}", "Invalid LUT denominator")
        return
    if not np.isfinite(ro_luts) or ro_luts <= 0:
        _write_empty_plot(path, f"{prefix}Standalone Probability vs {title_suffix}", "Invalid LUTs-per-RO value")
        return

    points = []
    for row in _rows_for_class(rows, 1):
        ro = _to_float(row.get("ro_count"))
        prob = _to_float(row.get("probability"))
        if np.isfinite(ro) and np.isfinite(prob):
            points.append((ro * ro_luts / denominator * 100.0, prob, _row_correct(row), _sample_id(row)))
    if not points:
        _write_empty_plot(path, f"{prefix}Standalone Probability vs {title_suffix}", "No standalone rows with numeric ro_count")
        return

    fig, ax = plt.subplots(figsize=(9, 5))
    for correct, marker, color, label in [
        (True, "o", "tab:red", "correct standalone"),
        (False, "x", "black", "miss"),
    ]:
        xs = [p[0] for p in points if p[2] is correct]
        ys = [p[1] for p in points if p[2] is correct]
        if xs:
            ax.scatter(xs, ys, marker=marker, s=54, color=color, alpha=0.85, label=label)
    ax.axhline(0.5, color="gray", linestyle=":", linewidth=1)
    ax.set_title(f"{prefix}Standalone Probability vs {title_suffix}")
    ax.set_xlabel(x_label)
    ax.set_ylabel("Standalone probability")
    ax.set_ylim(-0.03, 1.03)
    ax.grid(True, axis="y", alpha=0.25)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def _plot_standalone_probability_vs_lut_percent_bubble_counts(
    rows: Sequence[dict[str, Any]],
    path: Path,
    prefix: str,
    denominator_luts: int | float,
    ro_luts_per_ro: int | float,
    title_suffix: str,
    x_label: str,
) -> None:
    try:
        denominator = float(denominator_luts)
    except (TypeError, ValueError):
        denominator = float("nan")
    try:
        ro_luts = float(ro_luts_per_ro)
    except (TypeError, ValueError):
        ro_luts = float("nan")
    if not np.isfinite(denominator) or denominator <= 0:
        _write_empty_plot(path, f"{prefix}Standalone Probability vs {title_suffix} Counts", "Invalid LUT denominator")
        return
    if not np.isfinite(ro_luts) or ro_luts <= 0:
        _write_empty_plot(path, f"{prefix}Standalone Probability vs {title_suffix} Counts", "Invalid LUTs-per-RO value")
        return

    buckets: dict[tuple[float, float, bool], int] = {}
    for row in _rows_for_class(rows, 1):
        ro = _to_float(row.get("ro_count"))
        prob = _to_float(row.get("probability"))
        if not (np.isfinite(ro) and np.isfinite(prob)):
            continue
        x_percent = ro * ro_luts / denominator * 100.0
        key = (round(x_percent, 2), round(prob, 2), _row_correct(row))
        buckets[key] = buckets.get(key, 0) + 1
    if not buckets:
        _write_empty_plot(path, f"{prefix}Standalone Probability vs {title_suffix} Counts", "No standalone rows with numeric ro_count")
        return

    max_count = max(buckets.values())

    def marker_size(count: int) -> float:
        return 45.0 + 320.0 * np.sqrt(count / max_count)

    fig, ax = plt.subplots(figsize=(9, 5))
    for correct, marker, color, label in [
        (True, "o", "tab:red", "correct standalone"),
        (False, "x", "black", "miss"),
    ]:
        selected = [(x, y, count) for (x, y, is_correct), count in buckets.items() if is_correct is correct]
        if not selected:
            continue
        ax.scatter(
            [item[0] for item in selected],
            [item[1] for item in selected],
            marker=marker,
            s=[marker_size(item[2]) for item in selected],
            color=color,
            alpha=0.75,
            label=label,
        )
        for x, y, count in selected:
            if count >= 3:
                ax.annotate(
                    str(count),
                    (x, y),
                    xytext=(0, 0),
                    textcoords="offset points",
                    ha="center",
                    va="center",
                    fontsize=7,
                    color="white" if correct else "black",
                )

    count_markers = sorted({1, max(2, int(round(max_count / 2))), max_count})
    handles, labels = ax.get_legend_handles_labels()
    for count in count_markers:
        handles.append(ax.scatter([], [], s=marker_size(count), marker="o", color="gray", alpha=0.35))
        labels.append(f"n={count}")

    ax.axhline(0.5, color="gray", linestyle=":", linewidth=1)
    ax.set_title(f"{prefix}Standalone Probability vs {title_suffix} Counts")
    ax.set_xlabel(x_label)
    ax.set_ylabel("Standalone probability")
    ax.set_ylim(-0.03, 1.03)
    ax.grid(True, axis="y", alpha=0.25)
    ax.legend(handles, labels, fontsize=8, loc="best")
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def _standalone_lut_percent_points(
    rows: Sequence[dict[str, Any]],
    denominator_luts: int | float,
    ro_luts_per_ro: int | float,
) -> tuple[list[tuple[float, bool]], str | None]:
    try:
        denominator = float(denominator_luts)
    except (TypeError, ValueError):
        denominator = float("nan")
    try:
        ro_luts = float(ro_luts_per_ro)
    except (TypeError, ValueError):
        ro_luts = float("nan")
    if not np.isfinite(denominator) or denominator <= 0:
        return [], "Invalid LUT denominator"
    if not np.isfinite(ro_luts) or ro_luts <= 0:
        return [], "Invalid LUTs-per-RO value"

    points = []
    for row in _rows_for_class(rows, 1):
        ro = _to_float(row.get("ro_count"))
        if np.isfinite(ro):
            points.append((ro * ro_luts / denominator * 100.0, _row_correct(row)))
    if not points:
        return [], "No standalone rows with numeric ro_count"
    return points, None


def _plot_standalone_detection_rate_vs_lut_percent(
    rows: Sequence[dict[str, Any]],
    path: Path,
    prefix: str,
    denominator_luts: int | float,
    ro_luts_per_ro: int | float,
    title_suffix: str,
    x_label: str,
) -> None:
    points, error = _standalone_lut_percent_points(rows, denominator_luts, ro_luts_per_ro)
    title = f"{prefix}Standalone Detection Rate vs {title_suffix}"
    if error is not None:
        _write_empty_plot(path, title, error)
        return

    xs = np.asarray([point[0] for point in points], dtype=float)
    correct = np.asarray([point[1] for point in points], dtype=bool)
    unique_x = np.unique(np.round(xs, 2))
    bucket_labels: list[str] = []
    bucket_indices: list[np.ndarray] = []

    if len(unique_x) <= 14:
        for value in unique_x:
            mask = np.isclose(np.round(xs, 2), value)
            bucket_labels.append(f"{value:.2f}")
            bucket_indices.append(np.flatnonzero(mask))
    else:
        bins = np.linspace(float(np.min(xs)), float(np.max(xs)), 13)
        bins = np.unique(np.round(bins, 6))
        if len(bins) < 2:
            bins = np.asarray([float(np.min(xs)) - 0.01, float(np.max(xs)) + 0.01])
        digitized = np.digitize(xs, bins, right=False) - 1
        digitized = np.clip(digitized, 0, len(bins) - 2)
        for idx in range(len(bins) - 1):
            bucket = np.flatnonzero(digitized == idx)
            if len(bucket) == 0:
                continue
            left = bins[idx]
            right = bins[idx + 1]
            bucket_labels.append(f"{left:.2f}-{right:.2f}")
            bucket_indices.append(bucket)

    if not bucket_indices:
        _write_empty_plot(path, title, "No non-empty RO LUT percentage buckets")
        return

    counts = np.asarray([len(indices) for indices in bucket_indices], dtype=float)
    correct_counts = np.asarray([np.count_nonzero(correct[indices]) for indices in bucket_indices], dtype=float)
    correct_rates = correct_counts / counts
    miss_rates = 1.0 - correct_rates
    x_positions = np.arange(len(bucket_labels))

    fig_width = max(9.0, 0.55 * len(bucket_labels))
    fig, ax = plt.subplots(figsize=(fig_width, 5))
    ax.bar(x_positions, correct_rates, color="tab:red", alpha=0.82, label="correct standalone")
    ax.bar(x_positions, miss_rates, bottom=correct_rates, color="black", alpha=0.72, label="miss")
    for xpos, total, rate in zip(x_positions, counts, correct_rates):
        ax.text(xpos, 1.015, f"n={int(total)}", ha="center", va="bottom", fontsize=7, rotation=90)
        ax.text(xpos, max(0.04, rate / 2), f"{rate:.0%}", ha="center", va="center", fontsize=7, color="white")

    ax.axhline(0.5, color="gray", linestyle=":", linewidth=1)
    ax.set_title(title)
    ax.set_xlabel(x_label)
    ax.set_ylabel("Fraction of standalone samples")
    ax.set_xticks(x_positions)
    ax.set_xticklabels(bucket_labels, rotation=45, ha="right", fontsize=8)
    ax.set_ylim(0, 1.12)
    ax.grid(True, axis="y", alpha=0.25)
    ax.legend(fontsize=8, loc="lower right")
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def _plot_standalone_probability_vs_ro_lut_utilization(
    rows: Sequence[dict[str, Any]],
    path: Path,
    prefix: str,
    full_device_luts: int | float,
    dynamic_region_luts: int | float,
    ro_luts_per_ro: int | float,
) -> None:
    try:
        full_luts = float(full_device_luts)
    except (TypeError, ValueError):
        full_luts = float("nan")
    try:
        ro_luts = float(ro_luts_per_ro)
    except (TypeError, ValueError):
        ro_luts = float("nan")
    if not np.isfinite(full_luts) or full_luts <= 0:
        _write_empty_plot(path, f"{prefix}Standalone Probability vs RO LUT Utilization", "Invalid full-FPGA LUT denominator")
        return
    if not np.isfinite(ro_luts) or ro_luts <= 0:
        _write_empty_plot(path, f"{prefix}Standalone Probability vs RO LUT Utilization", "Invalid LUTs-per-RO value")
        return

    points = []
    for row in _rows_for_class(rows, 1):
        ro_count = _to_float(row.get("ro_count"))
        probability = _to_float(row.get("probability"))
        if not (np.isfinite(ro_count) and np.isfinite(probability)):
            continue
        ro_lut_count = ro_count * ro_luts
        points.append(
            {
                "full_percent": ro_lut_count / full_luts * 100.0,
                "probability": probability,
                "correct": _row_correct(row),
            }
        )
    if not points:
        _write_empty_plot(path, f"{prefix}Standalone Probability vs RO LUT Utilization", "No standalone rows with RO counts and probabilities")
        return

    fig, ax = plt.subplots(figsize=(9, 5))
    for correct, marker, color, label in [
        (True, "o", "tab:red", "correct standalone"),
        (False, "x", "black", "miss"),
    ]:
        selected = [point for point in points if point["correct"] is correct]
        if selected:
            ax.scatter(
                [point["full_percent"] for point in selected],
                [point["probability"] for point in selected],
                marker=marker,
                s=54,
                color=color,
                alpha=0.85,
                label=label,
            )
    ax.axhline(0.5, color="gray", linestyle=":", linewidth=1)
    ax.set_title(f"{prefix}Standalone Probability vs Full-FPGA RO LUT Share")
    ax.set_xlabel("RO LUTs (% of full-FPGA LUTs)")
    ax.set_ylabel("Standalone probability")
    ax.grid(True, axis="y", alpha=0.25)
    ax.set_ylim(-0.03, 1.03)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def _plot_benign_app_standalone_probability(rows: Sequence[dict[str, Any]], path: Path, prefix: str) -> None:
    points = []
    for row in _rows_for_class(rows, 0):
        prob = _to_float(row.get("probability"))
        if np.isfinite(prob):
            app = str(row.get("app_name") or "unknown_app")
            points.append((app, prob, _row_correct(row), _sample_id(row)))
    if not points:
        _write_empty_plot(path, f"{prefix}Standalone Probability per Benign App", "No benign rows with probabilities")
        return

    apps = sorted({p[0] for p in points})
    app_to_x = {app: idx for idx, app in enumerate(apps)}
    rng = np.random.RandomState(12345)

    fig_width = max(9, min(18, 0.55 * len(apps) + 4))
    fig, ax = plt.subplots(figsize=(fig_width, 5.5))
    for correct, marker, color, label in [
        (True, "o", "tab:blue", "correct benign"),
        (False, "x", "black", "false positive"),
    ]:
        subset = [p for p in points if p[2] is correct]
        if not subset:
            continue
        xs = [app_to_x[p[0]] + float(rng.uniform(-0.16, 0.16)) for p in subset]
        ys = [p[1] for p in subset]
        ax.scatter(xs, ys, marker=marker, s=48, color=color, alpha=0.85, label=label)
    ax.axhline(0.5, color="gray", linestyle=":", linewidth=1)
    ax.set_title(f"{prefix}Standalone Probability per Benign App")
    ax.set_xlabel("Benign app class")
    ax.set_ylabel("Standalone probability")
    ax.set_ylim(-0.03, 1.03)
    ax.set_xticks(range(len(apps)))
    ax.set_xticklabels(apps, rotation=45, ha="right", fontsize=8)
    ax.grid(True, axis="y", alpha=0.25)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def _normalize_image(x: np.ndarray) -> np.ndarray:
    arr = np.asarray(x)
    if arr.ndim == 4:
        arr = arr[0]
    if arr.ndim == 3 and arr.shape[-1] == 1:
        arr = arr[..., 0]
    arr = arr.astype(np.float32)
    if arr.size == 0:
        return arr
    if arr.max() <= 1.0 and arr.min() >= 0.0:
        return arr
    arr = arr - arr.min()
    denom = arr.max()
    return arr / denom if denom > 0 else arr


def _normalize_cam(cam: np.ndarray) -> np.ndarray:
    cam = np.asarray(cam, dtype=np.float32)
    cam = cam - np.min(cam)
    denom = np.max(cam)
    return cam / denom if denom > 0 else cam


def _make_overlay(image: np.ndarray, cam: np.ndarray) -> np.ndarray:
    gray = _normalize_image(image)
    cam = _normalize_cam(cam)
    heat = plt.get_cmap("jet")(cam)[..., :3]
    gray_rgb = np.stack([gray, gray, gray], axis=-1)
    alpha = 0.65 * cam[..., None]
    return np.clip(gray_rgb * (1.0 - alpha) + heat * alpha, 0.0, 1.0)


def _upscale_to(arr: np.ndarray, size: int) -> np.ndarray:
    """Bilinear upscale a 2-D (H, W) or 3-D (H, W, C) float array to (size, size[, C])."""
    from scipy.ndimage import zoom

    h = arr.shape[0]
    if h == size:
        return arr
    factor = size / h
    zoom_factors = (factor, factor) if arr.ndim == 2 else (factor, factor, 1.0)
    return zoom(arr.astype(np.float32), zoom_factors, order=1)


def _matches_qkeras_target_layer(layer, target_layer_name: str) -> bool:
    if layer.name == target_layer_name:
        return True
    if layer.name == f"prune_low_magnitude_{target_layer_name}":
        return True
    wrapped = getattr(layer, "layer", None)
    return bool(wrapped is not None and getattr(wrapped, "name", None) == target_layer_name)


def _call_layer_inference(layer, x):
    try:
        return layer(x, training=False)
    except TypeError:
        return layer(x)


def _build_qkeras_gradcam_probe(model, target_layer_name: str):
    import tensorflow as tf

    if len(model.inputs) != 1:
        raise ValueError(f"Grad-CAM expects a single-input model, got {len(model.inputs)} inputs")

    input_shape = tuple(model.inputs[0].shape.as_list()[1:])
    probe_input = tf.keras.Input(shape=input_shape, dtype=model.inputs[0].dtype, name="gradcam_probe_input")
    y = probe_input
    target_activations = None
    saw_any_layer = False
    for layer in model.layers:
        if layer.__class__.__name__ == "InputLayer":
            continue
        saw_any_layer = True
        y = _call_layer_inference(layer, y)
        if _matches_qkeras_target_layer(layer, target_layer_name):
            target_activations = y

    if target_activations is None:
        layer_names = ", ".join(layer.name for layer in model.layers)
        raise ValueError(f"No such Grad-CAM target layer: {target_layer_name}. Existing layers: {layer_names}")
    if not saw_any_layer:
        raise ValueError("Grad-CAM cannot probe a model with no non-input layers")
    return tf.keras.Model(inputs=probe_input, outputs=[target_activations, y])


def _compute_qkeras_gradcam(model, x: np.ndarray, target_layer_name: str, target_class: str) -> tuple[np.ndarray, float, int]:
    import tensorflow as tf

    if target_class not in TARGET_CLASS_NAMES:
        raise ValueError(f"Unknown target_class={target_class!r}")
    x_batch = np.asarray(x, dtype=np.float32)
    if x_batch.ndim == 3:
        x_batch = x_batch[np.newaxis, ...]
    gradcam_model = _build_qkeras_gradcam_probe(model, target_layer_name)
    with tf.GradientTape() as tape:
        activations, logits = gradcam_model(x_batch, training=False)
        tape.watch(activations)
        if isinstance(logits, (list, tuple)):
            logits = logits[0]
        standalone_logit = logits[:, 0]
        objective = standalone_logit if target_class == "standalone" else -standalone_logit
    grads = tape.gradient(objective, activations)
    if grads is None:
        raise RuntimeError(f"No gradients captured for target layer {target_layer_name}")
    weights = tf.reduce_mean(grads, axis=(1, 2), keepdims=True)
    cam = tf.nn.relu(tf.reduce_sum(weights * activations, axis=-1))[0]
    cam = tf.image.resize(cam[..., tf.newaxis], x_batch.shape[1:3], method="bilinear")[..., 0]
    prob = tf.sigmoid(standalone_logit)[0].numpy().item()
    return _normalize_cam(cam.numpy()), float(prob), int(prob >= 0.5)


def write_qkeras_gradcam_bundle(
    model,
    samples: Sequence[dict[str, Any]],
    prediction_rows: Sequence[dict[str, Any]],
    output_dir: Path,
    image_getter: Callable[[dict[str, Any]], np.ndarray],
    target_layer_name: str,
    target_layer_shape: str | None = None,
    sample_ids: Sequence[str] | None = None,
    split_label: str = "fold",
    command_text: str | None = None,
) -> dict[str, Any] | None:
    """Write a train.py-like Grad-CAM bundle for a TensorFlow/QKeras fold."""
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    rows_by_id = {_sample_id(row): row for row in prediction_rows}
    samples_by_id = {str(sample.get("sample_id", "")): sample for sample in samples}
    if sample_ids is None:
        sample_ids = select_default_sample_ids(prediction_rows)
    sample_ids = [sid for sid in sample_ids if sid in rows_by_id and sid in samples_by_id]
    if not sample_ids:
        _write_empty_plot(output_dir / "overview_grid.png", "Grad-CAM", "No representative samples available")
        _write_gradcam_summary(output_dir / "gradcam_summary.csv", [])
        (output_dir / "run_command.txt").write_text(command_text or "")
        return None

    summary_rows = []
    overview_rows = []
    for sample_id in sample_ids:
        pred_row = rows_by_id[sample_id]
        sample = samples_by_id[sample_id]
        image = image_getter(sample)
        true_label = _to_int(pred_row.get("class_label"), _to_int(sample.get("class_label"), 0)) or 0
        target_outputs = {}
        pred_prob = float("nan")
        pred_label = 0
        for target_class in TARGET_CLASS_NAMES:
            cam, pred_prob, pred_label = _compute_qkeras_gradcam(model, image, target_layer_name, target_class)
            overlay = _make_overlay(image, cam)
            png_name = f"{sample_id}_{target_class}_gradcam.png"
            _save_gradcam_panel(
                output_dir / png_name,
                image,
                cam,
                overlay,
                pred_row,
                target_class,
                target_layer_name,
                target_layer_shape,
                pred_prob,
                split_label,
            )
            image_1024 = _upscale_to(image, 1024)
            cam_1024 = _upscale_to(cam, 1024)
            overlay_1024 = _make_overlay(image_1024, cam_1024)
            _save_gradcam_panel(
                output_dir / f"{sample_id}_{target_class}_gradcam_1024.png",
                image_1024,
                cam_1024,
                overlay_1024,
                pred_row,
                target_class,
                target_layer_name,
                target_layer_shape,
                pred_prob,
                split_label,
            )
            target_outputs[target_class] = {"cam": cam, "overlay": overlay}
            expected_prob = _to_float(pred_row.get("probability"))
            summary_rows.append(
                {
                    "sample_id": sample_id,
                    "app_name": sample.get("app_name", pred_row.get("app_name", "")),
                    "true_class": _class_name(true_label),
                    "target_class": target_class,
                    "predicted_probability": f"{pred_prob:.6f}",
                    "expected_probability": f"{expected_prob:.6f}" if np.isfinite(expected_prob) else "",
                    "probability_delta": f"{abs(pred_prob - expected_prob):.6e}" if np.isfinite(expected_prob) else "",
                    "predicted_label": pred_label,
                    "expected_predicted_label": pred_row.get("predicted_label", ""),
                    "correct": pred_row.get("correct", ""),
                    "split": split_label,
                    "checkpoint": "final",
                    "target_layer": target_layer_name,
                    "target_layer_shape": target_layer_shape or "",
                    "output_png": png_name,
                }
            )
        overview_rows.append({"row": pred_row, "image": image, "pred_prob": pred_prob, "targets": target_outputs})

    _write_gradcam_summary(output_dir / "gradcam_summary.csv", summary_rows)
    _save_gradcam_overview(output_dir / "overview_grid.png", overview_rows)
    _save_high_ro_standalone_gradcam(
        output_dir / "high_ro_standalone_gradcam.png",
        output_dir / "high_ro_standalone_gradcam.csv",
        model,
        samples_by_id,
        prediction_rows,
        image_getter,
        target_layer_name,
        target_layer_shape,
        split_label,
        png_path_1024=output_dir / "high_ro_standalone_gradcam_1024.png",
    )
    (output_dir / "run_command.txt").write_text(command_text or "")
    return {
        "summary_csv": str(output_dir / "gradcam_summary.csv"),
        "overview_png": str(output_dir / "overview_grid.png"),
        "high_ro_standalone_png": str(output_dir / "high_ro_standalone_gradcam.png"),
        "high_ro_standalone_png_1024": str(output_dir / "high_ro_standalone_gradcam_1024.png"),
        "sample_ids": list(sample_ids),
    }


def _save_gradcam_panel(
    path: Path,
    image: np.ndarray,
    cam: np.ndarray,
    overlay: np.ndarray,
    row: dict[str, Any],
    target_class: str,
    target_layer_name: str,
    target_layer_shape: str | None,
    pred_prob: float,
    split_label: str,
) -> None:
    fig, axes = plt.subplots(1, 3, figsize=(12, 4))
    axes[0].imshow(_normalize_image(image), cmap="gray", vmin=0, vmax=1)
    axes[0].set_title("Input")
    axes[1].imshow(cam, cmap="jet", vmin=0, vmax=1)
    axes[1].set_title(f"CAM: {target_class}")
    axes[2].imshow(overlay)
    axes[2].set_title("Overlay")
    for ax in axes:
        ax.axis("off")
    meta = (
        f"{row.get('sample_id', '')}  app={row.get('app_name', '')}  "
        f"true={_class_name(_to_int(row.get('class_label'), 0) or 0)}  "
        f"p={pred_prob:.4f}  target={target_class}  layer={target_layer_name}"
        f"{' ' + target_layer_shape if target_layer_shape else ''}  {split_label}"
    )
    fig.suptitle(meta, fontsize=9)
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def _save_gradcam_overview(path: Path, overview_rows: Sequence[dict[str, Any]]) -> None:
    if not overview_rows:
        _write_empty_plot(path, "Grad-CAM Overview", "No Grad-CAM rows")
        return
    n_rows = len(overview_rows)
    n_cols = 1 + len(TARGET_CLASS_NAMES)
    fig, axes = plt.subplots(n_rows, n_cols, figsize=(4 * n_cols, 3.2 * n_rows), squeeze=False)
    for r_idx, item in enumerate(overview_rows):
        row = item["row"]
        axes[r_idx, 0].imshow(_normalize_image(item["image"]), cmap="gray", vmin=0, vmax=1)
        axes[r_idx, 0].set_title(
            f"{row.get('sample_id', '')}\n{_class_name(_to_int(row.get('class_label'), 0) or 0)} p={item['pred_prob']:.3f}",
            fontsize=9,
        )
        axes[r_idx, 0].axis("off")
        for c_idx, target_class in enumerate(TARGET_CLASS_NAMES, start=1):
            axes[r_idx, c_idx].imshow(item["targets"][target_class]["overlay"])
            axes[r_idx, c_idx].set_title(target_class, fontsize=9)
            axes[r_idx, c_idx].axis("off")
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def _high_ro_standalone_rows(rows: Sequence[dict[str, Any]], max_samples: int = 4) -> list[dict[str, Any]]:
    candidates = []
    for row in _rows_for_class(rows, 1):
        ro = _to_float(row.get("ro_count"))
        if np.isfinite(ro):
            candidates.append((ro, row))
    return [row for _, row in sorted(candidates, key=lambda item: item[0], reverse=True)[:max_samples]]


def _save_high_ro_standalone_gradcam(
    png_path: Path,
    csv_path: Path,
    model,
    samples_by_id: dict[str, dict[str, Any]],
    prediction_rows: Sequence[dict[str, Any]],
    image_getter: Callable[[dict[str, Any]], np.ndarray],
    target_layer_name: str,
    target_layer_shape: str | None,
    split_label: str,
    png_path_1024: Path | None = None,
) -> None:
    rows = [row for row in _high_ro_standalone_rows(prediction_rows, max_samples=4) if _sample_id(row) in samples_by_id]
    if not rows:
        _write_empty_plot(png_path, "High-RO Standalone Grad-CAM", "No standalone rows with numeric ro_count")
        if png_path_1024 is not None:
            _write_empty_plot(png_path_1024, "High-RO Standalone Grad-CAM (1024px)", "No standalone rows with numeric ro_count")
        _write_high_ro_summary(csv_path, [])
        return

    summary_rows = []
    fig, axes = plt.subplots(len(rows), 3, figsize=(12, 3.2 * len(rows)), squeeze=False)
    fig_1024, axes_1024 = plt.subplots(len(rows), 3, figsize=(12, 3.2 * len(rows)), squeeze=False) if png_path_1024 is not None else (None, None)
    for idx, row in enumerate(rows):
        sample_id = _sample_id(row)
        image = image_getter(samples_by_id[sample_id])
        cam, pred_prob, pred_label = _compute_qkeras_gradcam(model, image, target_layer_name, "standalone")
        overlay = _make_overlay(image, cam)
        panels = [
            (_normalize_image(image), {"cmap": "gray", "vmin": 0, "vmax": 1}, "Input"),
            (cam, {"cmap": "jet", "vmin": 0, "vmax": 1}, "Standalone CAM"),
            (overlay, {}, "Overlay"),
        ]
        for col, (img, kwargs, title) in enumerate(panels):
            axes[idx, col].imshow(img, **kwargs)
            axes[idx, col].axis("off")
            axes[idx, col].set_title(title, fontsize=9)
        axes[idx, 0].set_ylabel(
            f"{sample_id}\nro={row.get('ro_count', '')}\np={pred_prob:.3f}",
            fontsize=8,
            rotation=0,
            labelpad=42,
            va="center",
        )
        if axes_1024 is not None:
            image_1024 = _upscale_to(image, 1024)
            cam_1024 = _upscale_to(cam, 1024)
            overlay_1024 = _make_overlay(image_1024, cam_1024)
            panels_1024 = [
                (_normalize_image(image_1024), {"cmap": "gray", "vmin": 0, "vmax": 1}, "Input (1024px)"),
                (cam_1024, {"cmap": "jet", "vmin": 0, "vmax": 1}, "Standalone CAM (1024px)"),
                (overlay_1024, {}, "Overlay (1024px)"),
            ]
            for col, (img, kwargs, title) in enumerate(panels_1024):
                axes_1024[idx, col].imshow(img, **kwargs)
                axes_1024[idx, col].axis("off")
                axes_1024[idx, col].set_title(title, fontsize=9)
            axes_1024[idx, 0].set_ylabel(
                f"{sample_id}\nro={row.get('ro_count', '')}\np={pred_prob:.3f}",
                fontsize=8,
                rotation=0,
                labelpad=42,
                va="center",
            )
        summary_rows.append(
            {
                "sample_id": sample_id,
                "app_name": row.get("app_name", ""),
                "ro_count": row.get("ro_count", ""),
                "probability": f"{pred_prob:.6f}",
                "predicted_label": pred_label,
                "correct": row.get("correct", ""),
                "split": split_label,
                "target_class": "standalone",
                "target_layer": target_layer_name,
                "target_layer_shape": target_layer_shape or "",
            }
        )
    suffix = f" ({target_layer_name} {target_layer_shape})" if target_layer_shape else f" ({target_layer_name})"
    fig.suptitle(f"Highest-RO Standalone Validation Samples: Standalone Grad-CAM{suffix}", fontsize=12)
    fig.tight_layout()
    fig.savefig(png_path, dpi=160)
    plt.close(fig)
    if fig_1024 is not None:
        fig_1024.suptitle(f"Highest-RO Standalone Validation Samples: Standalone Grad-CAM (1024px){suffix}", fontsize=12)
        fig_1024.tight_layout()
        fig_1024.savefig(png_path_1024, dpi=160)
        plt.close(fig_1024)
    _write_high_ro_summary(csv_path, summary_rows)


def _write_high_ro_summary(path: Path, rows: Sequence[dict[str, Any]]) -> None:
    fieldnames = [
        "sample_id",
        "app_name",
        "ro_count",
        "probability",
        "predicted_label",
        "correct",
        "split",
        "target_class",
        "target_layer",
        "target_layer_shape",
    ]
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def _write_gradcam_summary(path: Path, rows: Sequence[dict[str, Any]]) -> None:
    fieldnames = [
        "sample_id",
        "app_name",
        "true_class",
        "target_class",
        "predicted_probability",
        "expected_probability",
        "probability_delta",
        "predicted_label",
        "expected_predicted_label",
        "correct",
        "split",
        "checkpoint",
        "target_layer",
        "target_layer_shape",
        "output_png",
    ]
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def history_rows_to_columns(rows: Sequence[dict]) -> dict[str, list[float]]:
    cols: dict[str, list[float]] = {}
    for row in rows:
        for key, value in row.items():
            if key in _HISTORY_NONNUMERIC:
                continue
            cols.setdefault(key, []).append(_to_float(value))
    return cols


def load_history_columns(fold_dir: Path) -> dict[str, list[float]]:
    with (Path(fold_dir) / "history.csv").open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    return history_rows_to_columns(rows)


def _metrics_from_per_sample_rows(rows: Sequence[dict]) -> dict:
    labels = np.asarray([int(row["class_label"]) for row in rows], dtype=np.float32)
    probs = np.asarray([float(row["probability"]) for row in rows], dtype=np.float32)
    losses = np.asarray([float(row["per_sample_bce_loss"]) for row in rows], dtype=np.float32)
    return compute_metrics_from_outputs(float(np.mean(losses)), labels, probs)


def load_final_metrics(fold_dir: Path, filename: str = "per_sample.csv") -> dict | None:
    path = Path(fold_dir) / filename
    if not path.exists():
        return None
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        return None
    return _metrics_from_per_sample_rows(rows)


def load_training_manifest(fold_dir: Path) -> dict:
    path = Path(fold_dir) / "training_manifest.json"
    if not path.exists():
        return {}
    return json.loads(path.read_text())


def build_run_params(training_manifest: dict) -> dict:
    cfg = training_manifest.get("train_config", {}) or {}
    quantizer = training_manifest.get("quantizer", {}) or {}
    params = {
        "quantizer": quantizer.get("tag", ""),
        "weight_bits": quantizer.get("weight_bits", ""),
        "activation_bits": quantizer.get("activation_bits", ""),
        "epochs": cfg.get("epochs", ""),
        "batch_size": cfg.get("batch_size", ""),
        "lr": cfg.get("lr", ""),
        "seed": cfg.get("seed", ""),
        "augment": cfg.get("augment", ""),
    }
    return {k: v for k, v in params.items() if v not in ("", None)}


def build_split_info(
    candidate_name: str,
    fold: int | str,
    n_train: int | str,
    n_val: int | str,
) -> str:
    return (
        f"Candidate: {candidate_name}  |  Fold: {fold}  |  "
        f"Train: {n_train}  |  Val: {n_val}"
    )


def build_split_info_from_manifest(training_manifest: dict) -> str:
    cfg = training_manifest.get("train_config", {}) or {}
    return build_split_info(
        training_manifest.get("candidate", ""),
        cfg.get("fold", ""),
        training_manifest.get("n_train", ""),
        training_manifest.get("n_val", ""),
    )


def write_fold_plots(
    fold_dir: Path,
    history_columns: dict,
    final_metrics: dict,
    aug_metrics: dict | None = None,
    split_info: str | None = None,
    run_params: dict | None = None,
    final_epoch: int | None = None,
) -> None:
    fold_dir = Path(fold_dir)
    if final_epoch is None:
        final_epoch = len(history_columns.get("train_loss", [])) or None
    save_evaluation_dashboard(
        history_columns,
        str(fold_dir),
        split_info=split_info,
        run_params=run_params,
        final_epoch=final_epoch,
    )
    save_training_curves(
        history_columns,
        str(fold_dir),
        split_info=split_info,
        run_params=run_params,
    )
    if final_metrics is not None:
        save_checkpoint_plots(
            str(fold_dir),
            "final",
            canonical_metrics=final_metrics,
            aug_metrics=aug_metrics,
            split_info=split_info,
            run_params=run_params,
        )


def write_heldout_test_plots(
    production_dir: Path,
    test_metrics: dict,
    split_info: str | None = None,
    run_params: dict | None = None,
) -> Path:
    out_dir = Path(production_dir) / "heldout_test_diagnostics"
    out_dir.mkdir(parents=True, exist_ok=True)
    save_checkpoint_plots(
        str(out_dir),
        "final",
        canonical_metrics=test_metrics,
        split_info=split_info,
        run_params=run_params,
        canonical_label="test",
        canonical_summary_label="Held-out Test",
    )
    return out_dir / "final_evaluation_plots.png"


def write_fold_plots_from_disk(fold_dir: Path) -> None:
    fold_dir = Path(fold_dir)
    history_columns = load_history_columns(fold_dir)
    final_metrics = load_final_metrics(fold_dir, "per_sample.csv")
    aug_metrics = load_final_metrics(fold_dir, "augmented_per_sample.csv")
    manifest = load_training_manifest(fold_dir)
    split_info = build_split_info_from_manifest(manifest) if manifest else None
    run_params = build_run_params(manifest) if manifest else None
    cfg = manifest.get("train_config", {}) if manifest else {}
    final_epoch = cfg.get("epochs") or None
    write_fold_plots(
        fold_dir,
        history_columns,
        final_metrics,
        aug_metrics,
        split_info=split_info,
        run_params=run_params,
        final_epoch=final_epoch,
    )


def fold_result_from_disk(fold_dir: Path) -> dict:
    fold_dir = Path(fold_dir)
    history_columns = load_history_columns(fold_dir)
    final_metrics = load_final_metrics(fold_dir, "per_sample.csv")
    aug_metrics = load_final_metrics(fold_dir, "augmented_per_sample.csv")
    manifest = load_training_manifest(fold_dir)
    cfg = manifest.get("train_config", {}) if manifest else {}
    fold_idx = cfg.get("fold", fold_dir.name.replace("fold_", ""))
    return {
        "fold_label": f"fold_{fold_idx}",
        "history": history_columns,
        "final_metrics": final_metrics,
        "final_aug_metrics": aug_metrics,
        "final_epoch": cfg.get("epochs") or len(history_columns.get("train_loss", [])),
    }


def write_kfold_plots(
    run_dir: Path,
    fold_results: list[dict],
    split_info: str | None = None,
    run_params: dict | None = None,
) -> None:
    run_dir = Path(run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    save_kfold_curves(
        fold_results,
        str(run_dir),
        split_info=split_info,
        run_params=run_params,
    )
    save_kfold_evaluation_artifacts(
        fold_results,
        str(run_dir),
        split_info=split_info,
        run_params=run_params,
    )
    save_kfold_summary(fold_results, str(run_dir), n_folds=len(fold_results))


def write_kfold_plots_from_disk(
    candidate: Any,
    quantizer_tag: str,
    run_dir: Path,
    fold_dirs: Sequence[Path],
) -> None:
    fold_results = [fold_result_from_disk(fd) for fd in fold_dirs]
    manifest = load_training_manifest(Path(fold_dirs[0])) if fold_dirs else {}
    cfg = manifest.get("train_config", {}) if manifest else {}
    run_params = build_run_params(manifest) if manifest else None
    split_info = (
        f"Candidate: {candidate.name}  |  Quantizer: {quantizer_tag}  |  "
        f"Folds: {len(fold_results)}  |  Epochs: {cfg.get('epochs', '')}"
    )
    write_kfold_plots(run_dir, fold_results, split_info=split_info, run_params=run_params)
