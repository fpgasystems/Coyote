#!/usr/bin/env python3
"""Plot per-convolution-layer HLS LUT and cycle costs for hand tuning."""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline.experiment_cli import reexec_local_python_if_needed
from pipeline.device_resources import XCU55C_TOTAL_CLB_LUTS


CLOCK_PERIOD_NS = 4.0

SWEEPS = [
    {
        "input_size": 256,
        "sweep_label": "Latency RF1",
        "strategy_label": "Latency",
        "sweep_reuse_factor": 1,
        "bar_order": 0,
        "root": Path(
            "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/"
            "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img256/notebook_pruned_qat/"
            "res256_layers7_W8A8_P50_RFbase_74abd8967440/hls_sweeps/RF1_hls_ec24b5cc81fe"
        ),
    },
    {
        "input_size": 256,
        "sweep_label": "Resource RF1",
        "strategy_label": "Resource",
        "sweep_reuse_factor": 1,
        "bar_order": 1,
        "root": Path(
            "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/"
            "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img256/notebook_pruned_qat/"
            "res256_layers7_W8A8_P50_RFbase_resource_strategy_from_74abd8967440/"
            "hls_sweeps/RFResource1_hls_db0d83b80b6e"
        ),
    },
    {
        "input_size": 256,
        "sweep_label": "Resource RF2",
        "strategy_label": "Resource",
        "sweep_reuse_factor": 2,
        "bar_order": 2,
        "root": Path(
            "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/"
            "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img256/notebook_pruned_qat/"
            "res256_layers7_W8A8_P50_RFbase_resource_strategy_from_74abd8967440/"
            "hls_sweeps/RFResource2_hls_d4f551930017"
        ),
    },
    {
        "input_size": 256,
        "sweep_label": "Resource RF4",
        "strategy_label": "Resource",
        "sweep_reuse_factor": 4,
        "bar_order": 3,
        "root": Path(
            "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/"
            "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img256/notebook_pruned_qat/"
            "res256_layers7_W8A8_P50_RFbase_resource_strategy_from_74abd8967440/"
            "hls_sweeps/RFResource4_hls_c73fa830e212"
        ),
    },
    {
        "input_size": 256,
        "sweep_label": "Resource RF8",
        "strategy_label": "Resource",
        "sweep_reuse_factor": 8,
        "bar_order": 4,
        "root": Path(
            "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/"
            "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img256/notebook_pruned_qat/"
            "res256_layers7_W8A8_P50_RFbase_resource_strategy_from_74abd8967440/"
            "hls_sweeps/RFResource8_hls_9c3f5eeda556"
        ),
    },
    {
        "input_size": 256,
        "sweep_label": "Resource RF16",
        "strategy_label": "Resource",
        "sweep_reuse_factor": 16,
        "bar_order": 5,
        "root": Path(
            "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/"
            "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img256/notebook_pruned_qat/"
            "res256_layers7_W8A8_P50_RFbase_resource_strategy_from_74abd8967440/"
            "hls_sweeps/RFResource16_hls_bbab2a8cfb79"
        ),
    },
    {
        "input_size": 256,
        "sweep_label": "Resource RF32",
        "strategy_label": "Resource",
        "sweep_reuse_factor": 32,
        "bar_order": 6,
        "root": Path(
            "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/"
            "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img256/notebook_pruned_qat/"
            "res256_layers7_W8A8_P50_RFbase_resource_strategy_from_74abd8967440/"
            "hls_sweeps/RFResource32_hls_6b653c3fdc27"
        ),
    },
    {
        "input_size": 256,
        "sweep_label": "ManualA",
        "strategy_label": "ManualA",
        "sweep_reuse_factor": "mixed",
        "bar_order": 7,
        "root": Path(
            "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/"
            "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img256/notebook_pruned_qat/"
            "res256_layers7_W8A8_P50_manualA_ad5955bea6e9/hls_sweeps/manualA_hls_c73ef690acf2"
        ),
    },
    {
        "input_size": 512,
        "sweep_label": "Latency RF1",
        "strategy_label": "Latency",
        "sweep_reuse_factor": 1,
        "bar_order": 0,
        "root": Path(
            "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/"
            "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img512/notebook_pruned_qat/"
            "res512_layers7_W8A8_P50_RFbase_b3a09a3d898b/hls_sweeps/RFbase_hls_9f3541f73c5d"
        ),
    },
    {
        "input_size": 512,
        "sweep_label": "Resource RF1",
        "strategy_label": "Resource",
        "sweep_reuse_factor": 1,
        "bar_order": 1,
        "root": Path(
            "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/"
            "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img512/notebook_pruned_qat/"
            "res512_layers7_W8A8_P50_RFbase_resource_strategy_from_b3a09a3d898b/"
            "hls_sweeps/RFResource1_hls_d305ee5e13cc"
        ),
    },
    {
        "input_size": 512,
        "sweep_label": "Resource RF2",
        "strategy_label": "Resource",
        "sweep_reuse_factor": 2,
        "bar_order": 2,
        "root": Path(
            "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/"
            "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img512/notebook_pruned_qat/"
            "res512_layers7_W8A8_P50_RFbase_resource_strategy_from_b3a09a3d898b/"
            "hls_sweeps/RFResource2_hls_8c7b90ce3603"
        ),
    },
    {
        "input_size": 512,
        "sweep_label": "Resource RF4",
        "strategy_label": "Resource",
        "sweep_reuse_factor": 4,
        "bar_order": 3,
        "root": Path(
            "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/"
            "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img512/notebook_pruned_qat/"
            "res512_layers7_W8A8_P50_RFbase_resource_strategy_from_b3a09a3d898b/"
            "hls_sweeps/RFResource4_hls_151264670e00"
        ),
    },
    {
        "input_size": 512,
        "sweep_label": "Resource RF8",
        "strategy_label": "Resource",
        "sweep_reuse_factor": 8,
        "bar_order": 4,
        "root": Path(
            "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/"
            "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img512/notebook_pruned_qat/"
            "res512_layers7_W8A8_P50_RFbase_resource_strategy_from_b3a09a3d898b/"
            "hls_sweeps/RFResource8_hls_00d67c66dfd0"
        ),
    },
    {
        "input_size": 512,
        "sweep_label": "Resource RF16",
        "strategy_label": "Resource",
        "sweep_reuse_factor": 16,
        "bar_order": 5,
        "root": Path(
            "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/"
            "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img512/notebook_pruned_qat/"
            "res512_layers7_W8A8_P50_RFbase_resource_strategy_from_b3a09a3d898b/"
            "hls_sweeps/RFResource16_hls_bfa9ddb35197"
        ),
    },
    {
        "input_size": 512,
        "sweep_label": "Resource RF32",
        "strategy_label": "Resource",
        "sweep_reuse_factor": 32,
        "bar_order": 6,
        "root": Path(
            "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/"
            "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img512/notebook_pruned_qat/"
            "res512_layers7_W8A8_P50_RFbase_resource_strategy_from_b3a09a3d898b/"
            "hls_sweeps/RFResource32_hls_04a8ea59b68e"
        ),
    },
    {
        "input_size": 512,
        "sweep_label": "ManualA",
        "strategy_label": "ManualA",
        "sweep_reuse_factor": "mixed",
        "bar_order": 7,
        "root": Path(
            "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/"
            "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img512/notebook_pruned_qat/"
            "res512_layers7_W8A8_P50_manualA_53819173e114/hls_sweeps/manualA_hls_97999e7ec333"
        ),
    },
]

CSV_FIELDS = [
    "input_size",
    "sweep_label",
    "strategy_label",
    "sweep_reuse_factor",
    "layer",
    "layer_index",
    "actual_strategy",
    "reuse_factor",
    "config_name",
    "module_name",
    "latency_cycles_min",
    "latency_cycles_max",
    "interval_cycles_min",
    "interval_cycles_max",
    "latency_ms_min",
    "latency_ms_max",
    "interval_ms_min",
    "interval_ms_max",
    "bram_18k",
    "dsp",
    "ff",
    "lut",
    "lut_percent_xcu55c",
    "uram",
    "report_path",
    "sweep_root",
]

MODULE_CSV_FIELDS = [
    "input_size",
    "sweep_label",
    "strategy_label",
    "sweep_reuse_factor",
    "module_group",
    "layer",
    "config_name",
    "module_name",
    "latency_cycles",
    "latency_ms",
    "lut",
    "lut_percent_xcu55c",
    "report_path",
    "sweep_root",
]

SWEEP_LABELS = [
    "Latency RF1",
    "Resource RF1",
    "Resource RF2",
    "Resource RF4",
    "Resource RF8",
    "Resource RF16",
    "Resource RF32",
    "ManualA",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=Path("results/hand_optimized"))
    parser.add_argument("--show", action="store_true", help="Also display plots interactively")
    return parser.parse_args()


def pipe_cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def parse_int_cell(value: str) -> int | None:
    value = value.strip()
    if value in {"", "-"}:
        return None
    match = re.search(r"-?\d+", value.replace(",", ""))
    return int(match.group(0)) if match else None


def find_project_dir(sweep_root: Path) -> Path:
    project_root = sweep_root / "fold_0" / "project"
    candidates = sorted(project_root.glob("*_prj"))
    if len(candidates) != 1:
        raise FileNotFoundError(f"expected one *_prj under {project_root}, found {len(candidates)}")
    return candidates[0]


def find_firmware_cpp(sweep_root: Path) -> Path:
    firmware_dir = sweep_root / "fold_0" / "project" / "firmware"
    candidates = sorted(path for path in firmware_dir.glob("*.cpp") if not path.name.endswith("_bridge.cpp"))
    if len(candidates) != 1:
        raise FileNotFoundError(f"expected one firmware/*.cpp under {firmware_dir}, found {len(candidates)}")
    return candidates[0]


def conv_config_map(sweep_root: Path) -> dict[str, str]:
    text = find_firmware_cpp(sweep_root).read_text()
    out: dict[str, str] = {}
    pattern = re.compile(r"nnet::conv_2d_cl<[^;]*?,\s*(config\d+)\>\([^;]+;\s*//\s*(conv\d+)")
    for match in pattern.finditer(text):
        config_name, layer = match.groups()
        out[layer] = config_name
    if len(out) != 7:
        raise RuntimeError(f"expected 7 conv layer mappings in {find_firmware_cpp(sweep_root)}, found {len(out)}")
    return dict(sorted(out.items(), key=lambda item: int(item[0].replace("conv", ""))))


def layer_config_map(sweep_root: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    pattern = re.compile(r"nnet::\w+<[^;]*?,\s*((?:relu_)?config\d+)>\([^;]+;\s*//\s*([A-Za-z0-9_]+)")
    for line in find_firmware_cpp(sweep_root).read_text().splitlines():
        match = pattern.search(line)
        if match:
            config_name, layer = match.groups()
            out[config_name] = layer
    if not out:
        raise RuntimeError(f"could not map layer configs in {find_firmware_cpp(sweep_root)}")
    return out


def report_for_config(project_dir: Path, config_name: str) -> Path:
    report_dir = project_dir / "solution1" / "syn" / "report"
    candidates = sorted(report_dir.glob(f"conv_2d_cl_*_{config_name}_s_csynth.rpt"))
    if len(candidates) != 1:
        raise FileNotFoundError(f"expected one report for {config_name} under {report_dir}, found {len(candidates)}")
    return candidates[0]


def parse_latency(report_text: str) -> dict[str, int | None]:
    lines = report_text.splitlines()
    in_latency = False
    saw_latency_cycles = False
    for line in lines:
        if line.strip().startswith("+ Latency:"):
            in_latency = True
            continue
        if in_latency and "Latency (cycles)" in line:
            saw_latency_cycles = True
            continue
        if in_latency and line.strip().startswith("+ Detail:"):
            break
        if in_latency and saw_latency_cycles and line.lstrip().startswith("|"):
            cells = pipe_cells(line)
            if len(cells) >= 6 and parse_int_cell(cells[0]) is not None and parse_int_cell(cells[1]) is not None:
                return {
                    "latency_cycles_min": parse_int_cell(cells[0]),
                    "latency_cycles_max": parse_int_cell(cells[1]),
                    "interval_cycles_min": parse_int_cell(cells[4]),
                    "interval_cycles_max": parse_int_cell(cells[5]),
                }
    raise RuntimeError("could not parse latency summary")


def parse_utilization(report_text: str) -> dict[str, int | None]:
    for line in report_text.splitlines():
        if re.match(r"^\|Total\s*\|", line):
            cells = pipe_cells(line)
            if len(cells) >= 6:
                return {
                    "bram_18k": parse_int_cell(cells[1]),
                    "dsp": parse_int_cell(cells[2]),
                    "ff": parse_int_cell(cells[3]),
                    "lut": parse_int_cell(cells[4]),
                    "uram": parse_int_cell(cells[5]),
                }
    raise RuntimeError("could not parse utilization Total row")


def top_csynth_report(project_dir: Path) -> Path:
    path = project_dir / "solution1" / "syn" / "report" / "csynth.rpt"
    if not path.exists():
        raise FileNotFoundError(path)
    return path


def module_group(layer: str) -> str:
    if layer.startswith("conv"):
        return "Conv"
    if layer.startswith("pad_conv"):
        return "Padding"
    if layer.startswith("act"):
        return "Activation"
    if layer.startswith("pool"):
        return "Pooling"
    if layer == "gap":
        return "GlobalPool"
    if layer == "output_dense":
        return "Dense"
    if layer == "top_overhead":
        return "TopOverhead"
    return "Other"


def config_from_module(module_name: str) -> str:
    match = re.search(r"(relu_config\d+|config\d+)_s\b", module_name)
    return match.group(1) if match else ""


def parse_top_modules(report_path: Path, config_to_layer: dict[str, str]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    top_row: dict[str, Any] | None = None
    direct_lut_sum = 0
    for raw_line in report_path.read_text(errors="ignore").splitlines():
        is_top = raw_line.startswith("    |+ ")
        is_direct_module = raw_line.startswith("    | + ")
        if not is_top and not is_direct_module:
            continue
        cells = pipe_cells(raw_line)
        if len(cells) < 13:
            continue
        module_name = cells[0].lstrip("+ ").rstrip("*").strip()
        row = {
            "module_name": module_name,
            "latency_cycles": parse_int_cell(cells[3]),
            "latency_ms": (parse_int_cell(cells[3]) or 0) * CLOCK_PERIOD_NS / 1_000_000.0,
            "lut": parse_int_cell(cells[-2]) or 0,
            "lut_percent_xcu55c": (parse_int_cell(cells[-2]) or 0) * 100.0 / XCU55C_TOTAL_CLB_LUTS,
            "config_name": config_from_module(module_name),
        }
        if is_top:
            top_row = row
            continue
        row["layer"] = config_to_layer.get(str(row["config_name"]), str(row["config_name"]) or module_name)
        row["module_group"] = module_group(str(row["layer"]))
        direct_lut_sum += int(row["lut"])
        rows.append(row)

    if top_row is None:
        raise RuntimeError(f"could not parse top row from {report_path}")
    overhead_lut = max(int(top_row["lut"]) - direct_lut_sum, 0)
    rows.append(
        {
            "module_name": "top_level_residual",
            "latency_cycles": 0,
            "latency_ms": 0.0,
            "lut": overhead_lut,
            "lut_percent_xcu55c": overhead_lut * 100.0 / XCU55C_TOTAL_CLB_LUTS,
            "config_name": "",
            "layer": "top_overhead",
            "module_group": "TopOverhead",
        }
    )
    return rows


def hls_layer_config(sweep_root: Path) -> dict[str, dict[str, Any]]:
    path = sweep_root / "fold_0" / "project" / "full_hls_config.json"
    payload = json.loads(path.read_text())
    return payload.get("LayerName", {})


def collect_rows() -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for sweep in SWEEPS:
        sweep_root = Path(sweep["root"])
        if not sweep_root.exists():
            raise FileNotFoundError(sweep_root)
        project_dir = find_project_dir(sweep_root)
        config_by_layer = conv_config_map(sweep_root)
        hls_layers = hls_layer_config(sweep_root)
        for layer, config_name in config_by_layer.items():
            report_path = report_for_config(project_dir, config_name)
            report_text = report_path.read_text(errors="ignore")
            row: dict[str, Any] = {
                "input_size": sweep["input_size"],
                "sweep_label": sweep["sweep_label"],
                "strategy_label": sweep["strategy_label"],
                "sweep_reuse_factor": sweep["sweep_reuse_factor"],
                "bar_order": sweep["bar_order"],
                "layer": layer,
                "layer_index": int(layer.replace("conv", "")),
                "actual_strategy": hls_layers.get(layer, {}).get("Strategy", ""),
                "reuse_factor": hls_layers.get(layer, {}).get("ReuseFactor", ""),
                "config_name": config_name,
                "module_name": report_path.name.removesuffix("_csynth.rpt"),
                "report_path": str(report_path),
                "sweep_root": str(sweep_root),
            }
            try:
                latency = parse_latency(report_text)
                utilization = parse_utilization(report_text)
            except RuntimeError as exc:
                raise RuntimeError(f"{report_path}: {exc}") from exc
            row.update(latency)
            row.update(utilization)
            row.update(
                {
                    "latency_ms_min": (latency["latency_cycles_min"] or 0) * CLOCK_PERIOD_NS / 1_000_000.0,
                    "latency_ms_max": (latency["latency_cycles_max"] or 0) * CLOCK_PERIOD_NS / 1_000_000.0,
                    "interval_ms_min": (latency["interval_cycles_min"] or 0) * CLOCK_PERIOD_NS / 1_000_000.0,
                    "interval_ms_max": (latency["interval_cycles_max"] or 0) * CLOCK_PERIOD_NS / 1_000_000.0,
                    "lut_percent_xcu55c": (utilization["lut"] or 0) * 100.0 / XCU55C_TOTAL_CLB_LUTS,
                }
            )
            rows.append(row)
    rows.sort(key=lambda row: (int(row["input_size"]), int(row["bar_order"]), int(row["layer_index"])))
    return rows


def collect_module_rows() -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for sweep in SWEEPS:
        sweep_root = Path(sweep["root"])
        if not sweep_root.exists():
            raise FileNotFoundError(sweep_root)
        project_dir = find_project_dir(sweep_root)
        report_path = top_csynth_report(project_dir)
        config_to_layer = layer_config_map(sweep_root)
        for module_row in parse_top_modules(report_path, config_to_layer):
            row = {
                "input_size": sweep["input_size"],
                "sweep_label": sweep["sweep_label"],
                "strategy_label": sweep["strategy_label"],
                "sweep_reuse_factor": sweep["sweep_reuse_factor"],
                "bar_order": sweep["bar_order"],
                "report_path": str(report_path),
                "sweep_root": str(sweep_root),
            }
            row.update(module_row)
            rows.append(row)
    group_order = {
        "Conv": 0,
        "Padding": 1,
        "Activation": 2,
        "Pooling": 3,
        "GlobalPool": 4,
        "Dense": 5,
        "TopOverhead": 6,
        "Other": 7,
    }
    rows.sort(
        key=lambda row: (
            int(row["input_size"]),
            int(row["bar_order"]),
            group_order.get(str(row["module_group"]), 99),
            str(row["layer"]),
        )
    )
    return rows


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=CSV_FIELDS)
        writer.writeheader()
        writer.writerows([{key: row.get(key, "") for key in CSV_FIELDS} for row in rows])


def write_module_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=MODULE_CSV_FIELDS)
        writer.writeheader()
        writer.writerows([{key: row.get(key, "") for key in MODULE_CSV_FIELDS} for row in rows])


def plot_stacked_metric(
    rows: list[dict[str, Any]],
    metric: str,
    ylabel: str,
    title: str,
    path: Path,
    show: bool,
    total_format: str,
) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    input_sizes = sorted({int(row["input_size"]) for row in rows})
    sweep_labels = SWEEP_LABELS
    layers = [f"conv{idx}" for idx in range(7)]
    layer_colors = {
        "conv0": "#1f77b4",
        "conv1": "#ff7f0e",
        "conv2": "#2ca02c",
        "conv3": "#d62728",
        "conv4": "#9467bd",
        "conv5": "#8c564b",
        "conv6": "#17becf",
    }
    values = {
        (int(row["input_size"]), str(row["sweep_label"]), str(row["layer"])): float(row[metric])
        for row in rows
    }

    fig, ax = plt.subplots(figsize=(15, 7))
    bar_width = 0.11
    group_width = bar_width * len(sweep_labels)
    group_spacing = 0.32
    x_positions: list[float] = []
    x_labels: list[str] = []
    for group_index, input_size in enumerate(input_sizes):
        group_start = group_index * (group_width + group_spacing)
        x_positions.extend(group_start + idx * bar_width for idx in range(len(sweep_labels)))
        x_labels.extend(sweep_labels)

    totals_by_bar: dict[tuple[int, str], float] = {}
    for label_index, sweep_label in enumerate(sweep_labels):
        bottoms = [0 for _ in input_sizes]
        for layer in layers:
            heights = [values[(input_size, sweep_label, layer)] for input_size in input_sizes]
            bar_x = [
                group_index * (group_width + group_spacing) + label_index * bar_width
                for group_index in range(len(input_sizes))
            ]
            ax.bar(
                bar_x,
                heights,
                bar_width,
                bottom=bottoms,
                color=layer_colors[layer],
                edgecolor="white",
                linewidth=0.8,
                label=layer if label_index == 0 else None,
            )
            bottoms = [bottom + height for bottom, height in zip(bottoms, heights)]
        for input_size, total in zip(input_sizes, bottoms):
            totals_by_bar[(input_size, sweep_label)] = total

    for group_index, input_size in enumerate(input_sizes):
        for label_index, sweep_label in enumerate(sweep_labels):
            x = group_index * (group_width + group_spacing) + label_index * bar_width
            total = totals_by_bar[(input_size, sweep_label)]
            ax.text(
                x,
                total,
                total_format.format(total),
                ha="center",
                va="bottom",
                fontsize=7,
                rotation=75,
            )

    group_centers = [
        group_index * (group_width + group_spacing) + group_width / 2 - bar_width / 2
        for group_index in range(len(input_sizes))
    ]
    ax.set_xticks(x_positions, x_labels, rotation=35, ha="right")
    ax.set_xlabel("Sweep")
    ax.set_ylabel(ylabel)
    ax.grid(True, axis="y", alpha=0.3)
    ax.set_axisbelow(True)
    ax.legend(title="Layer", bbox_to_anchor=(1.02, 1), loc="upper left", borderaxespad=0)
    ymax = ax.get_ylim()[1]
    ax.set_ylim(top=ymax * 1.14)
    for center, input_size in zip(group_centers, input_sizes):
        ax.text(center, -0.22, f"{input_size}x{input_size}", ha="center", va="top", transform=ax.get_xaxis_transform())
    fig.suptitle(title)
    fig.tight_layout(rect=(0, 0.1, 0.87, 1))
    fig.savefig(path, dpi=180)
    if show:
        plt.show()
    plt.close(fig)


def plot_layer_groups(
    rows: list[dict[str, Any]],
    metric: str,
    ylabel: str,
    title: str,
    path: Path,
    show: bool,
    total_format: str,
    groups: list[tuple[str, set[str], str]],
) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    input_sizes = sorted({int(row["input_size"]) for row in rows})
    sweep_labels = SWEEP_LABELS
    values: dict[tuple[int, str, str], float] = {}
    for row in rows:
        key = (int(row["input_size"]), str(row["sweep_label"]), str(row["layer"]))
        values[key] = float(row[metric])

    fig, ax = plt.subplots(figsize=(15, 7))
    bar_width = 0.11
    group_width = bar_width * len(sweep_labels)
    group_spacing = 0.32
    x_positions: list[float] = []
    x_labels: list[str] = []
    for group_index, input_size in enumerate(input_sizes):
        group_start = group_index * (group_width + group_spacing)
        x_positions.extend(group_start + idx * bar_width for idx in range(len(sweep_labels)))
        x_labels.extend(sweep_labels)

    totals_by_bar: dict[tuple[int, str], float] = {}
    for label_index, sweep_label in enumerate(sweep_labels):
        bottoms = [0.0 for _ in input_sizes]
        bar_x = [
            group_index * (group_width + group_spacing) + label_index * bar_width
            for group_index in range(len(input_sizes))
        ]
        for group_name, layer_names, color in groups:
            heights = [
                sum(values[(input_size, sweep_label, layer)] for layer in layer_names)
                for input_size in input_sizes
            ]
            ax.bar(
                bar_x,
                heights,
                bar_width,
                bottom=bottoms,
                color=color,
                edgecolor="white",
                linewidth=0.8,
                label=group_name if label_index == 0 else None,
            )
            for x, bottom, height in zip(bar_x, bottoms, heights):
                if height > 0:
                    ax.text(
                        x,
                        bottom + height / 2,
                        total_format.format(height),
                        ha="center",
                        va="center",
                        fontsize=6,
                        color="white",
                        rotation=90,
                    )
            bottoms = [bottom + height for bottom, height in zip(bottoms, heights)]
        for input_size, total in zip(input_sizes, bottoms):
            totals_by_bar[(input_size, sweep_label)] = total

    for group_index, input_size in enumerate(input_sizes):
        for label_index, sweep_label in enumerate(sweep_labels):
            x = group_index * (group_width + group_spacing) + label_index * bar_width
            total = totals_by_bar[(input_size, sweep_label)]
            ax.text(
                x,
                total,
                total_format.format(total),
                ha="center",
                va="bottom",
                fontsize=7,
                rotation=75,
            )

    group_centers = [
        group_index * (group_width + group_spacing) + group_width / 2 - bar_width / 2
        for group_index in range(len(input_sizes))
    ]
    ax.set_xticks(x_positions, x_labels, rotation=35, ha="right")
    ax.set_xlabel("Sweep")
    ax.set_ylabel(ylabel)
    ax.grid(True, axis="y", alpha=0.3)
    ax.set_axisbelow(True)
    ax.legend(title="Layer group", bbox_to_anchor=(1.02, 1), loc="upper left", borderaxespad=0)
    ymax = ax.get_ylim()[1]
    ax.set_ylim(top=ymax * 1.14)
    for center, input_size in zip(group_centers, input_sizes):
        ax.text(center, -0.22, f"{input_size}x{input_size}", ha="center", va="top", transform=ax.get_xaxis_transform())
    fig.suptitle(title)
    fig.tight_layout(rect=(0, 0.1, 0.87, 1))
    fig.savefig(path, dpi=180)
    if show:
        plt.show()
    plt.close(fig)


def plot_module_group_metric(
    module_rows: list[dict[str, Any]],
    groups: list[tuple[str, str, str]],
    metric: str,
    ylabel: str,
    title: str,
    path: Path,
    show: bool,
    total_format: str,
) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    input_sizes = sorted({int(row["input_size"]) for row in module_rows})
    values: dict[tuple[int, str, str], float] = {}
    for row in module_rows:
        key = (int(row["input_size"]), str(row["sweep_label"]), str(row["module_group"]))
        values[key] = values.get(key, 0.0) + float(row[metric])

    fig, ax = plt.subplots(figsize=(15, 7))
    bar_width = 0.11
    group_width = bar_width * len(SWEEP_LABELS)
    group_spacing = 0.32
    x_positions: list[float] = []
    x_labels: list[str] = []
    for group_index, input_size in enumerate(input_sizes):
        group_start = group_index * (group_width + group_spacing)
        x_positions.extend(group_start + idx * bar_width for idx in range(len(SWEEP_LABELS)))
        x_labels.extend(SWEEP_LABELS)

    totals_by_bar: dict[tuple[int, str], float] = {}
    for label_index, sweep_label in enumerate(SWEEP_LABELS):
        bottoms = [0.0 for _ in input_sizes]
        bar_x = [
            group_index * (group_width + group_spacing) + label_index * bar_width
            for group_index in range(len(input_sizes))
        ]
        for group_name, group_key, color in groups:
            heights = [values.get((input_size, sweep_label, group_key), 0.0) for input_size in input_sizes]
            ax.bar(
                bar_x,
                heights,
                bar_width,
                bottom=bottoms,
                color=color,
                edgecolor="white",
                linewidth=0.8,
                label=group_name if label_index == 0 else None,
            )
            bottoms = [bottom + height for bottom, height in zip(bottoms, heights)]
        for input_size, total in zip(input_sizes, bottoms):
            totals_by_bar[(input_size, sweep_label)] = total

    for group_index, input_size in enumerate(input_sizes):
        for label_index, sweep_label in enumerate(SWEEP_LABELS):
            x = group_index * (group_width + group_spacing) + label_index * bar_width
            total = totals_by_bar[(input_size, sweep_label)]
            ax.text(
                x,
                total,
                total_format.format(total),
                ha="center",
                va="bottom",
                fontsize=7,
                rotation=75,
            )

    group_centers = [
        group_index * (group_width + group_spacing) + group_width / 2 - bar_width / 2
        for group_index in range(len(input_sizes))
    ]
    ax.set_xticks(x_positions, x_labels, rotation=35, ha="right")
    ax.set_xlabel("Sweep")
    ax.set_ylabel(ylabel)
    ax.grid(True, axis="y", alpha=0.3)
    ax.set_axisbelow(True)
    ax.legend(title="Module group", bbox_to_anchor=(1.02, 1), loc="upper left", borderaxespad=0)
    ymax = ax.get_ylim()[1]
    ax.set_ylim(top=ymax * 1.14)
    for center, input_size in zip(group_centers, input_sizes):
        ax.text(center, -0.22, f"{input_size}x{input_size}", ha="center", va="top", transform=ax.get_xaxis_transform())
    fig.suptitle(title)
    fig.tight_layout(rect=(0, 0.1, 0.87, 1))
    fig.savefig(path, dpi=180)
    if show:
        plt.show()
    plt.close(fig)


def plot_named_module_layers(
    module_rows: list[dict[str, Any]],
    layer_names: list[str],
    layer_colors: dict[str, str],
    metric: str,
    ylabel: str,
    title: str,
    path: Path,
    show: bool,
    total_format: str,
) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    input_sizes = sorted({int(row["input_size"]) for row in module_rows})
    values: dict[tuple[int, str, str], float] = {}
    for row in module_rows:
        layer = str(row["layer"])
        if layer not in layer_names:
            continue
        key = (int(row["input_size"]), str(row["sweep_label"]), layer)
        values[key] = values.get(key, 0.0) + float(row[metric])

    fig, ax = plt.subplots(figsize=(15, 7))
    bar_width = 0.11
    group_width = bar_width * len(SWEEP_LABELS)
    group_spacing = 0.32
    x_positions: list[float] = []
    x_labels: list[str] = []
    for group_index, input_size in enumerate(input_sizes):
        group_start = group_index * (group_width + group_spacing)
        x_positions.extend(group_start + idx * bar_width for idx in range(len(SWEEP_LABELS)))
        x_labels.extend(SWEEP_LABELS)

    totals_by_bar: dict[tuple[int, str], float] = {}
    for label_index, sweep_label in enumerate(SWEEP_LABELS):
        bottoms = [0.0 for _ in input_sizes]
        for layer in layer_names:
            heights = [values.get((input_size, sweep_label, layer), 0.0) for input_size in input_sizes]
            bar_x = [
                group_index * (group_width + group_spacing) + label_index * bar_width
                for group_index in range(len(input_sizes))
            ]
            ax.bar(
                bar_x,
                heights,
                bar_width,
                bottom=bottoms,
                color=layer_colors[layer],
                edgecolor="white",
                linewidth=0.8,
                label=layer if label_index == 0 else None,
            )
            bottoms = [bottom + height for bottom, height in zip(bottoms, heights)]
        for input_size, total in zip(input_sizes, bottoms):
            totals_by_bar[(input_size, sweep_label)] = total

    for group_index, input_size in enumerate(input_sizes):
        for label_index, sweep_label in enumerate(SWEEP_LABELS):
            x = group_index * (group_width + group_spacing) + label_index * bar_width
            total = totals_by_bar[(input_size, sweep_label)]
            ax.text(
                x,
                total,
                total_format.format(total),
                ha="center",
                va="bottom",
                fontsize=7,
                rotation=75,
            )

    group_centers = [
        group_index * (group_width + group_spacing) + group_width / 2 - bar_width / 2
        for group_index in range(len(input_sizes))
    ]
    ax.set_xticks(x_positions, x_labels, rotation=35, ha="right")
    ax.set_xlabel("Sweep")
    ax.set_ylabel(ylabel)
    ax.grid(True, axis="y", alpha=0.3)
    ax.set_axisbelow(True)
    ax.legend(title="Layer", bbox_to_anchor=(1.02, 1), loc="upper left", borderaxespad=0)
    ymax = ax.get_ylim()[1]
    ax.set_ylim(top=ymax * 1.14)
    for center, input_size in zip(group_centers, input_sizes):
        ax.text(center, -0.22, f"{input_size}x{input_size}", ha="center", va="top", transform=ax.get_xaxis_transform())
    fig.suptitle(title)
    fig.tight_layout(rect=(0, 0.1, 0.87, 1))
    fig.savefig(path, dpi=180)
    if show:
        plt.show()
    plt.close(fig)


def write_plots(output_dir: Path, rows: list[dict[str, Any]], module_rows: list[dict[str, Any]], show: bool) -> list[Path]:
    outputs = [
        output_dir / "layer_luts_by_strategy.png",
        output_dir / "layer_latency_ms_by_strategy.png",
        output_dir / "first_two_vs_rest_luts_by_strategy.png",
        output_dir / "first_two_vs_rest_latency_ms_by_strategy.png",
        output_dir / "first_vs_rest_luts_by_strategy.png",
        output_dir / "first_vs_rest_latency_ms_by_strategy.png",
        output_dir / "nonconv_module_luts_by_strategy.png",
        output_dir / "nonconv_module_latency_ms_by_strategy.png",
        output_dir / "whole_design_lut_composition_by_strategy.png",
        output_dir / "whole_design_latency_composition_by_strategy.png",
        output_dir / "activation_layer_luts_by_strategy.png",
        output_dir / "activation_layer_latency_ms_by_strategy.png",
        output_dir / "pooling_layer_luts_by_strategy.png",
        output_dir / "pooling_layer_latency_ms_by_strategy.png",
    ]
    plot_stacked_metric(
        rows,
        "lut_percent_xcu55c",
        "LUT (% of XCU55C CLB LUTs)",
        "Stacked Per-Conv Layer LUT Usage by Strategy",
        outputs[0],
        show,
        "{:.1f}%",
    )
    plot_stacked_metric(
        rows,
        "latency_ms_max",
        "Latency (ms @ 4.0 ns)",
        "Stacked Per-Conv Layer Latency by Strategy",
        outputs[1],
        show,
        "{:.3f}",
    )
    plot_layer_groups(
        rows,
        "lut_percent_xcu55c",
        "LUT (% of XCU55C CLB LUTs)",
        "First Two Conv Layers vs Rest: LUT Usage",
        outputs[2],
        show,
        "{:.1f}%",
        [
            ("First 2", {"conv0", "conv1"}, "#2563eb"),
            ("Rest", {f"conv{idx}" for idx in range(2, 7)}, "#f97316"),
        ],
    )
    plot_layer_groups(
        rows,
        "latency_ms_max",
        "Latency (ms @ 4.0 ns)",
        "First Two Conv Layers vs Rest: Latency",
        outputs[3],
        show,
        "{:.3f}",
        [
            ("First 2", {"conv0", "conv1"}, "#2563eb"),
            ("Rest", {f"conv{idx}" for idx in range(2, 7)}, "#f97316"),
        ],
    )
    plot_layer_groups(
        rows,
        "lut_percent_xcu55c",
        "LUT (% of XCU55C CLB LUTs)",
        "First Conv Layer vs Rest: LUT Usage",
        outputs[4],
        show,
        "{:.1f}%",
        [
            ("First", {"conv0"}, "#2563eb"),
            ("Rest", {f"conv{idx}" for idx in range(1, 7)}, "#f97316"),
        ],
    )
    plot_layer_groups(
        rows,
        "latency_ms_max",
        "Latency (ms @ 4.0 ns)",
        "First Conv Layer vs Rest: Latency",
        outputs[5],
        show,
        "{:.3f}",
        [
            ("First", {"conv0"}, "#2563eb"),
            ("Rest", {f"conv{idx}" for idx in range(1, 7)}, "#f97316"),
        ],
    )
    nonconv_groups = [
        ("Padding", "Padding", "#14b8a6"),
        ("Activation", "Activation", "#eab308"),
        ("Pooling", "Pooling", "#f97316"),
        ("GlobalPool", "GlobalPool", "#84cc16"),
        ("Dense", "Dense", "#a855f7"),
        ("Top overhead", "TopOverhead", "#64748b"),
        ("Other", "Other", "#94a3b8"),
    ]
    plot_module_group_metric(
        module_rows,
        nonconv_groups,
        "lut_percent_xcu55c",
        "LUT (% of XCU55C CLB LUTs)",
        "Non-Conv Module LUT Usage by Strategy",
        outputs[6],
        show,
        "{:.1f}%",
    )
    plot_module_group_metric(
        module_rows,
        nonconv_groups,
        "latency_ms",
        "Module latency (ms @ 4.0 ns)",
        "Non-Conv Module Latency by Strategy",
        outputs[7],
        show,
        "{:.3f}",
    )
    whole_design_groups = [
        ("Conv", "Conv", "#2563eb"),
        ("Padding", "Padding", "#14b8a6"),
        ("Activation", "Activation", "#eab308"),
        ("Pooling", "Pooling", "#f97316"),
        ("GlobalPool", "GlobalPool", "#84cc16"),
        ("Dense", "Dense", "#a855f7"),
        ("Top overhead", "TopOverhead", "#64748b"),
        ("Other", "Other", "#94a3b8"),
    ]
    plot_module_group_metric(
        module_rows,
        whole_design_groups,
        "lut_percent_xcu55c",
        "LUT (% of XCU55C CLB LUTs)",
        "Whole-Design LUT Composition by Strategy",
        outputs[8],
        show,
        "{:.1f}%",
    )
    plot_module_group_metric(
        module_rows,
        whole_design_groups,
        "latency_ms",
        "Module latency (ms @ 4.0 ns)",
        "Whole-Design Module Latency Composition by Strategy",
        outputs[9],
        show,
        "{:.3f}",
    )
    activation_layers = [f"act{idx}" for idx in range(7)]
    activation_colors = {
        "act0": "#facc15",
        "act1": "#eab308",
        "act2": "#ca8a04",
        "act3": "#a16207",
        "act4": "#854d0e",
        "act5": "#713f12",
        "act6": "#422006",
    }
    plot_named_module_layers(
        module_rows,
        activation_layers,
        activation_colors,
        "lut_percent_xcu55c",
        "LUT (% of XCU55C CLB LUTs)",
        "Per-Activation Layer LUT Usage by Strategy",
        outputs[10],
        show,
        "{:.1f}%",
    )
    plot_named_module_layers(
        module_rows,
        activation_layers,
        activation_colors,
        "latency_ms",
        "Module latency (ms @ 4.0 ns)",
        "Per-Activation Layer Latency by Strategy",
        outputs[11],
        show,
        "{:.3f}",
    )
    pooling_layers = [f"pool{idx}" for idx in range(7)] + ["gap"]
    pooling_colors = {
        "pool0": "#fed7aa",
        "pool1": "#fdba74",
        "pool2": "#fb923c",
        "pool3": "#f97316",
        "pool4": "#ea580c",
        "pool5": "#c2410c",
        "pool6": "#9a3412",
        "gap": "#84cc16",
    }
    plot_named_module_layers(
        module_rows,
        pooling_layers,
        pooling_colors,
        "lut_percent_xcu55c",
        "LUT (% of XCU55C CLB LUTs)",
        "Per-Pooling Layer LUT Usage by Strategy",
        outputs[12],
        show,
        "{:.1f}%",
    )
    plot_named_module_layers(
        module_rows,
        pooling_layers,
        pooling_colors,
        "latency_ms",
        "Module latency (ms @ 4.0 ns)",
        "Per-Pooling Layer Latency by Strategy",
        outputs[13],
        show,
        "{:.3f}",
    )
    return outputs


def main() -> None:
    args = parse_args()
    reexec_local_python_if_needed(EXAMPLE_ROOT)
    rows = collect_rows()
    module_rows = collect_module_rows()
    expected_rows = len(SWEEPS) * 7
    if len(rows) != expected_rows:
        raise RuntimeError(f"expected {expected_rows} rows, got {len(rows)}")
    missing = [
        row for row in rows
        if row.get("lut") in ("", None) or row.get("latency_cycles_max") in ("", None)
    ]
    if missing:
        raise RuntimeError(f"missing parsed values for {len(missing)} rows")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    csv_path = args.output_dir / "layer_costs.csv"
    module_csv_path = args.output_dir / "module_costs.csv"
    write_csv(csv_path, rows)
    write_module_csv(module_csv_path, module_rows)
    plot_paths = write_plots(args.output_dir, rows, module_rows, args.show)

    print(f"[layer-costs] rows={len(rows)}")
    print(f"[layer-costs] csv={csv_path}")
    print(f"[module-costs] rows={len(module_rows)}")
    print(f"[module-costs] csv={module_csv_path}")
    for path in plot_paths:
        print(f"[layer-costs] plot={path}")


if __name__ == "__main__":
    main()
