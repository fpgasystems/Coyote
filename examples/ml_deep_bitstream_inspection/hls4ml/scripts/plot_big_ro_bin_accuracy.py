#!/usr/bin/env python3
"""Plot standalone detection rate by model and RO LUT-share bin."""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline.experiment_cli import reexec_local_python_if_needed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts-root", type=Path, default=Path("artifacts_big_ro"))
    parser.add_argument("--output-dir", type=Path, default=Path("results/big_ro_training"))
    parser.add_argument("--bins", type=int, default=12)
    parser.add_argument("--full-device-luts", type=float, default=None)
    return parser.parse_args()


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    fieldnames = [
        "model",
        "experiment_name",
        "run_root",
        "bin_left",
        "bin_right",
        "bin_label",
        "standalone_total",
        "standalone_correct",
        "standalone_detection_rate",
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in fieldnames})


def to_float(value: Any) -> float | None:
    try:
        if value in ("", None):
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def row_correct(row: dict[str, str]) -> bool:
    value = str(row.get("correct", "")).strip().lower()
    if value in {"true", "1", "yes"}:
        return True
    if value in {"false", "0", "no"}:
        return False
    try:
        return int(float(row.get("predicted_label", ""))) == int(float(row.get("class_label", "")))
    except (TypeError, ValueError):
        return False


def is_standalone(row: dict[str, str]) -> bool:
    try:
        return int(float(row.get("class_label", ""))) == 1
    except (TypeError, ValueError):
        return str(row.get("class_name", "")).strip().lower() == "standalone"


def discover_per_sample_csvs(artifacts_root: Path) -> list[Path]:
    return sorted(Path(artifacts_root).glob("cnn_small_hls_opt_img*/notebook_*/res*/pooled/per_sample.csv"))


def model_sort_key(path: Path) -> tuple[int, int, str]:
    name = path.parents[1].name
    resolution = 0
    if "res" in name:
        try:
            resolution = int(name.split("res", 1)[1].split("_", 1)[0])
        except ValueError:
            resolution = 0
    quant_order = 1 if "W8A8" in name else 0
    return resolution, quant_order, name


def model_label(experiment_name: str) -> str:
    resolution = experiment_name.split("_", 1)[0].replace("res", "")
    if "W8A8" in experiment_name and "P50" in experiment_name:
        return f"{resolution} W8A8 P50"
    if "WfloatAfloat" in experiment_name:
        return f"{resolution} float"
    return experiment_name


def bin_edges(values: list[float], n_bins: int) -> list[float]:
    import numpy as np

    if not values:
        return []
    bins = np.linspace(float(min(values)), float(max(values)), n_bins + 1)
    bins = np.unique(np.round(bins, 6))
    if len(bins) < 2:
        value = float(values[0])
        bins = np.asarray([value - 0.01, value + 0.01])
    return [float(value) for value in bins]


def digitize(value: float, edges: list[float]) -> int:
    import numpy as np

    idx = int(np.digitize([value], edges, right=False)[0]) - 1
    return max(0, min(idx, len(edges) - 2))


def is_w8a8_p50_experiment(experiment_name: str) -> bool:
    return "W8A8" in experiment_name and "P50" in experiment_name


def experiment_resolution(experiment_name: str) -> int | None:
    try:
        return int(experiment_name.split("_", 1)[0].replace("res", ""))
    except ValueError:
        return None


def collect_rows(
    per_sample_paths: list[Path],
    full_device_luts: float,
    ro_luts_per_ro: float,
    n_bins: int,
    *,
    allowed_resolutions: set[int] | None = None,
) -> list[dict[str, Any]]:
    values: list[float] = []
    model_points: dict[str, dict[str, Any]] = {}
    for path in sorted(per_sample_paths, key=model_sort_key):
        run_root = path.parents[1]
        experiment_name = run_root.name
        if not is_w8a8_p50_experiment(experiment_name):
            continue
        resolution = experiment_resolution(experiment_name)
        if allowed_resolutions is not None and resolution not in allowed_resolutions:
            continue
        label = model_label(experiment_name)
        points = []
        for row in read_csv(path):
            if not is_standalone(row):
                continue
            ro_count = to_float(row.get("ro_count"))
            if ro_count is None:
                continue
            lut_percent = ro_count * ro_luts_per_ro / full_device_luts * 100.0
            values.append(lut_percent)
            points.append({"lut_percent": lut_percent, "correct": row_correct(row)})
        if points:
            model_points[label] = {
                "experiment_name": experiment_name,
                "run_root": str(run_root),
                "points": points,
            }

    edges = bin_edges(values, n_bins)
    if not edges:
        return []

    summary_rows: list[dict[str, Any]] = []
    for label, payload in model_points.items():
        buckets = [{"total": 0, "correct": 0} for _ in range(len(edges) - 1)]
        for point in payload["points"]:
            idx = digitize(float(point["lut_percent"]), edges)
            buckets[idx]["total"] += 1
            buckets[idx]["correct"] += int(bool(point["correct"]))
        for idx, bucket in enumerate(buckets):
            left = edges[idx]
            right = edges[idx + 1]
            total = int(bucket["total"])
            correct = int(bucket["correct"])
            rate = correct / total if total else ""
            summary_rows.append(
                {
                    "model": label,
                    "experiment_name": payload["experiment_name"],
                    "run_root": payload["run_root"],
                    "bin_left": f"{left:.6f}",
                    "bin_right": f"{right:.6f}",
                    "bin_label": f"{left:.2f}-{right:.2f}",
                    "standalone_total": total,
                    "standalone_correct": correct,
                    "standalone_detection_rate": f"{rate:.12g}" if rate != "" else "",
                }
            )
    return summary_rows


def plot_grouped_bars(rows: list[dict[str, Any]], path: Path, *, title: str) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Patch
    import numpy as np

    if not rows:
        path.parent.mkdir(parents=True, exist_ok=True)
        fig, ax = plt.subplots(figsize=(9, 4))
        ax.axis("off")
        ax.text(0.5, 0.5, "No standalone RO bin data", ha="center", va="center", transform=ax.transAxes)
        fig.tight_layout()
        fig.savefig(path, dpi=160)
        plt.close(fig)
        return

    models = list(dict.fromkeys(str(row["model"]) for row in rows))
    bins = list(dict.fromkeys(str(row["bin_label"]) for row in rows))
    rate_by_key = {
        (str(row["model"]), str(row["bin_label"])): to_float(row.get("standalone_detection_rate"))
        for row in rows
    }
    total_by_key = {
        (str(row["model"]), str(row["bin_label"])): int(row.get("standalone_total") or 0)
        for row in rows
    }

    x_positions = np.arange(len(bins), dtype=float)
    width = min(0.28, 0.82 / max(1, len(models)))
    fig_width = max(12.0, 0.75 * len(bins) + 3.5)
    fig, ax = plt.subplots(figsize=(fig_width, 6.0))
    hatches = ["", "///", "\\\\\\", "xx", "..", "++"]
    for model_idx, model in enumerate(models):
        offset = (model_idx - (len(models) - 1) / 2.0) * width
        values = [rate_by_key.get((model, bin_label)) for bin_label in bins]
        correct_rates = [0.0 if value is None else value for value in values]
        miss_rates = [1.0 - value if value is not None else 0.0 for value in values]
        hatch = hatches[model_idx % len(hatches)]
        ax.bar(
            x_positions + offset,
            correct_rates,
            width=width,
            color="tab:red",
            alpha=0.82,
            edgecolor="black",
            linewidth=0.25,
            hatch=hatch,
        )
        ax.bar(
            x_positions + offset,
            miss_rates,
            bottom=correct_rates,
            width=width,
            color="black",
            alpha=0.72,
            edgecolor="black",
            linewidth=0.25,
            hatch=hatch,
        )
        for xpos, rate, bin_label in zip(x_positions + offset, correct_rates, bins):
            total = total_by_key.get((model, bin_label), 0)
            if not total:
                continue
            ax.text(xpos, 1.015, f"n={total}", ha="center", va="bottom", fontsize=5.5, rotation=90)
            ax.text(xpos, max(0.04, rate / 2), f"{rate:.0%}", ha="center", va="center", fontsize=6, color="white")

    ax.axhline(0.5, color="gray", linestyle=":", linewidth=1)
    ax.set_title(title)
    ax.set_xlabel("RO LUTs (% of full-FPGA LUTs, binned)")
    ax.set_ylabel("Fraction of standalone samples")
    ax.set_xticks(x_positions)
    ax.set_xticklabels(bins, rotation=45, ha="right", fontsize=8)
    ax.set_ylim(0.0, 1.12)
    ax.grid(True, axis="y", alpha=0.25)
    class_handles = [
        Patch(facecolor="tab:red", alpha=0.82, label="correct standalone"),
        Patch(facecolor="black", alpha=0.72, label="miss"),
    ]
    model_handles = [
        Patch(facecolor="white", edgecolor="black", hatch=hatches[idx % len(hatches)], label=model)
        for idx, model in enumerate(models)
    ]
    ax.legend(handles=[*class_handles, *model_handles], fontsize=8, ncol=2, loc="lower right")
    fig.tight_layout()
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=180)
    plt.close(fig)


def main() -> None:
    args = parse_args()
    reexec_local_python_if_needed(EXAMPLE_ROOT)
    from pipeline.device_resources import RO_LUTS_PER_STANDALONE_RO, XCU55C_TOTAL_CLB_LUTS

    artifacts_root = args.artifacts_root.resolve()
    output_dir = args.output_dir.resolve()
    full_device_luts = float(args.full_device_luts or XCU55C_TOTAL_CLB_LUTS)
    per_sample_paths = discover_per_sample_csvs(artifacts_root)
    specs = [
        (
            "w8a8",
            None,
            "Pooled folds: W8A8 P50 Standalone Detection Rate vs Full-FPGA RO LUT Share",
            "standalone_detection_rate_by_model_vs_full_fpga_lut_percent",
        ),
        (
            "paper",
            {256, 512},
            "Pooled folds: W8A8 P50 Standalone Detection Rate vs Full-FPGA RO LUT Share (256/512)",
            "standalone_detection_rate_by_model_vs_full_fpga_lut_percent_paper",
        ),
    ]
    for name, allowed_resolutions, title, stem in specs:
        rows = collect_rows(
            per_sample_paths,
            full_device_luts,
            float(RO_LUTS_PER_STANDALONE_RO),
            int(args.bins),
            allowed_resolutions=allowed_resolutions,
        )
        csv_path = output_dir / f"{stem}.csv"
        plot_path = output_dir / f"{stem}.png"
        write_csv(csv_path, rows)
        plot_grouped_bars(rows, plot_path, title=title)
        print(
            f"[big-ro:{name}] models={len(set(row['model'] for row in rows))} "
            f"bins={len(set(row['bin_label'] for row in rows))}"
        )
        print(f"[big-ro:{name}] csv={csv_path}")
        print(f"[big-ro:{name}] plot={plot_path}")


if __name__ == "__main__":
    main()
