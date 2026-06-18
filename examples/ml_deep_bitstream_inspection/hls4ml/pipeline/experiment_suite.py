"""Experiment-suite generation, shape prechecks, and result helpers."""

from __future__ import annotations

import csv
import json
import math
import re
from copy import deepcopy
from pathlib import Path
from typing import Any, Iterable, Sequence

from .hls_layer_tuning import hls_tuning_mode, layer_tuning_signature


def load_yaml(path: Path) -> dict[str, Any]:
    import yaml

    return yaml.safe_load(Path(path).read_text()) or {}


def write_yaml(path: Path, payload: dict[str, Any]) -> None:
    import yaml

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(payload, sort_keys=False))


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: Sequence[dict[str, Any]], fieldnames: Sequence[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if fieldnames is None:
        keys: list[str] = []
        for row in rows:
            for key in row:
                if key not in keys:
                    keys.append(key)
        fieldnames = keys
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(fieldnames))
        writer.writeheader()
        for row in rows:
            writer.writerow({key: _csv_value(row.get(key, "")) for key in fieldnames})


def _csv_value(value: Any) -> Any:
    if isinstance(value, (dict, list, tuple)):
        return json.dumps(value, sort_keys=True)
    return value


def safe_float(value: Any) -> float | None:
    try:
        if value in ("", None):
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def safe_int(value: Any) -> int | None:
    try:
        if value in ("", None):
            return None
        return int(float(value))
    except (TypeError, ValueError):
        return None


def experiment_sort_key(name: str) -> tuple[int, int, str]:
    match = re.search(r"res(\d+)_layers(\d+)", name)
    if not match:
        return (0, 0, name)
    return (int(match.group(1)), int(match.group(2)), name)


def conv_output_size(size: int, kernel: int, stride: int, pad: int) -> int:
    return math.floor((size + 2 * pad - kernel) / stride) + 1


def pool_output_size(size: int, pool: int = 2, stride: int = 2) -> int:
    return math.floor((size - pool) / stride) + 1


def analyze_model_shape(config: dict[str, Any]) -> dict[str, Any]:
    input_shape = config["model"]["input_shape"]
    height = int(input_shape[0])
    width = int(input_shape[1])
    channels = int(input_shape[2])
    rows: list[dict[str, Any]] = [
        {"layer": "input", "kind": "input", "height": height, "width": width, "channels": channels}
    ]
    for index, spec in enumerate(config["model"]["conv_specs"]):
        kernel_h, kernel_w = [int(v) for v in spec["kernel"]]
        stride_h, stride_w = [int(v) for v in spec["strides"]]
        pad = int(spec["pad"])
        height = conv_output_size(height, kernel_h, stride_h, pad)
        width = conv_output_size(width, kernel_w, stride_w, pad)
        channels = int(spec["filters"])
        rows.append(
            {
                "layer": str(spec["name"]),
                "kind": "conv",
                "height": height,
                "width": width,
                "channels": channels,
            }
        )
        height = pool_output_size(height)
        width = pool_output_size(width)
        rows.append(
            {
                "layer": f"pool{index}",
                "kind": "maxpool",
                "height": height,
                "width": width,
                "channels": channels,
            }
        )
    final_avg_pool = [int(height), int(width)]
    return {
        "shape_trace": rows,
        "final_feature_map_height": int(height),
        "final_feature_map_width": int(width),
        "final_channels": int(channels),
        "final_avg_pool": final_avg_pool,
        "final_pool_area": int(height * width),
        "final_pool_work": int(height * width * channels),
    }


def classify_feasibility(shape: dict[str, Any], thresholds: dict[str, Any]) -> str:
    height = int(shape["final_feature_map_height"])
    width = int(shape["final_feature_map_width"])
    if height <= 0 or width <= 0:
        return "red"
    max_dim = max(height, width)
    if max_dim <= int(thresholds.get("green_max_pool", 16)):
        return "green"
    if height == int(thresholds.get("yellow_pool", 32)) and width == int(thresholds.get("yellow_pool", 32)):
        return "yellow"
    return "red"


def base_experiment_name(
    resolution: int,
    layers: int,
    weight_label: str,
    activation_label: str,
    pruning_label: str,
    rf_label: str,
) -> str:
    return f"res{resolution}_layers{layers}_W{weight_label}A{activation_label}_P{pruning_label}_RF{rf_label}"


def candidate_name(suite: dict[str, Any], resolution: int) -> str:
    prefix = str(suite["defaults"].get("candidate_name_prefix", "cnn_small_hls_opt_img"))
    return f"{prefix}{resolution}"


def abi_for_resolution(suite: dict[str, Any], resolution: int) -> dict[str, Any]:
    abi = deepcopy(suite["defaults"]["u55c_abi"])
    fixed_width = int(abi["fixed_width"])
    axi_data_bits = int(abi["axi_data_bits"])
    pixels = int(resolution * resolution)
    pixels_per_beat = axi_data_bits // fixed_width
    abi.update(
        {
            "img_size": int(resolution),
            "pixels_per_sample": pixels,
            "pixels_per_beat": pixels_per_beat,
            "beats_per_sample": math.ceil(pixels / pixels_per_beat),
            "input_bytes_per_sample": pixels * fixed_width // 8,
        }
    )
    return abi


def phase_number(value: Any) -> str:
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def build_training_config(
    suite: dict[str, Any],
    experiment_name: str,
    resolution: int,
    layers: int,
    *,
    quantized: bool,
    weight_bits: int | None = None,
    activation_bits: int | None = None,
    pruning_target: int = 0,
    timestamped_root: bool | None = None,
) -> dict[str, Any]:
    defaults = suite["defaults"]
    anchor = suite["model_anchor"]
    conv_specs = deepcopy(anchor["conv_specs"][:layers])
    cfg: dict[str, Any] = {
        "run": {
            "iteration_name": experiment_name,
            "output_root": defaults.get("output_root", "artifacts"),
            "folds": None,
            "timestamped_root": defaults.get("timestamped_root", False)
            if timestamped_root is None
            else bool(timestamped_root),
        },
        "candidate": {
            "name": candidate_name(suite, resolution),
            "img_size": int(resolution),
            "min_ro": int(defaults.get("min_ro", 8000)),
            "k_folds": int(defaults.get("k_folds", 5)),
            "primary_fold": int(defaults.get("primary_fold", 0)),
            "seed": int(defaults.get("seed", 42)),
            "balance_classes": bool(defaults.get("balance_classes", True)),
        },
        "model": {
            "input_shape": [int(resolution), int(resolution), int(anchor.get("input_channels", 1))],
            "conv_specs": conv_specs,
            "final_avg_pool": [1, 1],
            "output_units": int(anchor.get("output_units", 1)),
        },
        "training": deepcopy(defaults["training"]),
        "hls": {
            "backend": defaults.get("hls_backend", "Vitis"),
            "sweep_name": defaults.get("hls_sweep_name_base", "RFbase"),
            "io_type": defaults.get("hls_io_type", "io_stream"),
            "strategy": defaults.get("hls_strategy", "Latency"),
            "reuse_factor": int(defaults.get("base_reuse_factor", 1)),
            "resource_strategy_threshold": 4096,
            "resource_strategy": "Resource",
            "clock_period": float(defaults.get("hls_clock_period", 5.0)),
            "part": defaults.get("hls_part", "xcu55c-fsvh2892-2L-e"),
            "run_csim": bool(defaults.get("hls_run_csim", True)),
            "run_cosim": bool(defaults.get("hls_run_cosim", False)),
            "output_precision": None,
            "pool_accum_precision": None,
            "accum_precision": None,
            "n_emulation_samples": None,
            "n_layer_trace_samples": 4,
        },
        "synthesis": {"run": bool(defaults.get("synthesis_run", True))},
        "u55c": {
            "coyote_root": "/pub/scratch/sdeheredia/Coyote",
            "build_jobs": None,
            "vfpga_id": 0,
            "abi": abi_for_resolution(suite, resolution),
        },
        "toolchain": {"auto_enable": True, "version": "latest"},
    }
    if quantized:
        q_defaults = defaults["quantization"]
        anchor_ints = list(q_defaults.get("activation_integer_anchor", [2, 2, 3, 4, 5]))[:layers]
        max_activation_integer = max(0, int(activation_bits or 1) - 1)
        cfg["quantization"] = {
            "enabled": True,
            "tag": f"w{weight_bits}_a{activation_bits}",
            "weight_bits": int(weight_bits or 6),
            "weight_integer": int(q_defaults.get("weight_integer", 0)),
            "activation_bits": int(activation_bits or 6),
            "activation_integer": [min(int(value), max_activation_integer) for value in anchor_ints],
            "alpha": int(q_defaults.get("alpha", 1)),
        }
    else:
        cfg["quantization"] = {"enabled": False, "tag": "float32"}
    pruning_enabled = int(pruning_target) > 0
    schedule = defaults["pruning_schedule"]
    cfg["pruning"] = {
        "enabled": pruning_enabled,
        "final_sparsity": float(pruning_target) / 100.0,
        "begin_epoch": int(schedule.get("begin_epoch", 2)),
        "end_epoch": int(schedule.get("end_epoch", 250)),
        "frequency_epochs": int(schedule.get("frequency_epochs", 5)),
        "prune_output_dense": bool(schedule.get("prune_output_dense", False)),
    }
    shape = analyze_model_shape(cfg)
    cfg["model"]["final_avg_pool"] = shape["final_avg_pool"]
    return cfg


def metadata_for_config(config: dict[str, Any], config_path: Path | None = None) -> dict[str, Any]:
    exp = config.get("experiment", {})
    shape = analyze_model_shape(config)
    conv_filters = [int(spec["filters"]) for spec in config["model"]["conv_specs"]]
    quant = config.get("quantization", {})
    pruning = config.get("pruning", {})
    hls = config.get("hls", {})
    row = {
        "experiment_name": exp.get("name") or config["run"]["iteration_name"],
        "phase": exp.get("phase", ""),
        "input_resolution": int(config["candidate"]["img_size"]),
        "num_layers": len(config["model"]["conv_specs"]),
        "conv_filters": conv_filters,
        "final_feature_map_height": shape["final_feature_map_height"],
        "final_feature_map_width": shape["final_feature_map_width"],
        "final_channels": shape["final_channels"],
        "final_avg_pool": shape["final_avg_pool"],
        "final_pool_area": shape["final_pool_area"],
        "final_pool_work": shape["final_pool_work"],
        "tier": exp.get("tier", ""),
        "weight_bits": quant.get("weight_bits", "float" if not quant.get("enabled", True) else ""),
        "activation_bits": quant.get("activation_bits", "float" if not quant.get("enabled", True) else ""),
        "pruning_target": int(round(float(pruning.get("final_sparsity", 0.0)) * 100.0)),
        "reuse_factor": int(hls.get("reuse_factor", 1)),
        "hls_tuning_mode": hls_tuning_mode(config),
        "hls_layer_knob_signature": layer_tuning_signature(config),
        "config_path": str(config_path or ""),
    }
    return row


def feasibility_row(config: dict[str, Any], config_path: Path | None = None) -> dict[str, Any]:
    row = metadata_for_config(config, config_path)
    row.update(
        {
            "status": "skipped_red" if row["tier"] == "red" else "pending",
            "skip_reason": skip_reason_for_row(row) if row["tier"] == "red" else "",
        }
    )
    return row


def skip_reason_for_row(row: dict[str, Any]) -> str:
    height = safe_int(row.get("final_feature_map_height"))
    width = safe_int(row.get("final_feature_map_width"))
    if height is not None and width is not None and (height <= 0 or width <= 0):
        return "final_avg_pool has nonpositive dimension"
    return "final_avg_pool > 32x32"


def phase_matches(config: dict[str, Any], requested: set[str]) -> bool:
    if not requested:
        return True
    phase = phase_number(config.get("experiment", {}).get("phase", ""))
    return phase in requested


def load_generated_configs(config_dir: Path, phases: Iterable[str] = ()) -> list[tuple[Path, dict[str, Any]]]:
    requested = {phase_number(value.strip()) for value in phases if str(value).strip()}
    out: list[tuple[Path, dict[str, Any]]] = []
    for path in sorted(Path(config_dir).glob("*.yaml")):
        raw_cfg = load_yaml(path)
        if not raw_cfg.get("experiment"):
            continue
        cfg = raw_cfg
        if raw_cfg.get("extends"):
            from .part1_common import load_config

            cfg = load_config(path)
            cfg["experiment"] = {**cfg.get("experiment", {}), **raw_cfg["experiment"]}
        if phase_matches(cfg, requested):
            out.append((path, cfg))
    return out


def write_generation_outputs(rows: Sequence[dict[str, Any]], results_dir: Path) -> None:
    fieldnames = [
        "experiment_name",
        "phase",
        "input_resolution",
        "num_layers",
        "conv_filters",
        "final_feature_map_height",
        "final_feature_map_width",
        "final_channels",
        "final_avg_pool",
        "final_pool_area",
        "final_pool_work",
        "tier",
        "weight_bits",
        "activation_bits",
        "pruning_target",
        "reuse_factor",
        "hls_tuning_mode",
        "hls_layer_knob_signature",
        "status",
        "skip_reason",
        "config_path",
    ]
    write_csv(Path(results_dir) / "feasibility_matrix.csv", rows, fieldnames=fieldnames)


def selected_rows(path: Path | None) -> list[dict[str, str]]:
    return read_csv(path) if path else []


def parse_selected_config(row: dict[str, str]) -> dict[str, Any] | None:
    config_path = row.get("config_path")
    if not config_path:
        return None
    path = Path(config_path)
    if not path.exists():
        return None
    return load_yaml(path)


def generated_config_path(output_dir: Path, experiment_name: str) -> Path:
    return Path(output_dir) / f"{experiment_name}.yaml"


def resolution_depth_points(phase_cfg: dict[str, Any]) -> list[tuple[int, int]]:
    explicit = phase_cfg.get("points")
    if explicit:
        points: list[tuple[int, int]] = []
        for item in explicit:
            if isinstance(item, dict):
                points.append((int(item["resolution"]), int(item["layers"])))
            else:
                resolution, layers = item
                points.append((int(resolution), int(layers)))
        return points
    return [
        (int(resolution), int(layers))
        for resolution in phase_cfg["resolutions"]
        for layers in phase_cfg["depths"]
    ]


def generate_phase123(suite: dict[str, Any], output_dir: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    thresholds = suite["feasibility"]
    phase_cfg = suite["phases"]["resolution_depth"]
    for resolution, layers in resolution_depth_points(phase_cfg):
        name = base_experiment_name(resolution, layers, "float", "float", "0", "base")
        cfg = build_training_config(suite, name, resolution, layers, quantized=False, pruning_target=0)
        shape = analyze_model_shape(cfg)
        tier = classify_feasibility(shape, thresholds)
        experiment_name = f"{name}_boundary" if tier == "yellow" else name
        if experiment_name != name:
            cfg["run"]["iteration_name"] = experiment_name
        phase_id = 1 if resolution == 512 and layers == 5 else 2
        cfg["experiment"] = {
            "name": experiment_name,
            "phase": phase_id,
            "suite": suite["suite"]["name"],
            "tier": tier,
            "shape_trace": shape["shape_trace"],
        }
        path = generated_config_path(output_dir, experiment_name)
        write_yaml(path, cfg)
        rows.append(feasibility_row(cfg, path))
    return sorted(rows, key=lambda row: experiment_sort_key(str(row["experiment_name"])))


def _selected_architecture_rows(rows: Sequence[dict[str, str]]) -> list[tuple[dict[str, str], dict[str, Any]]]:
    out = []
    for row in rows:
        cfg = parse_selected_config(row)
        if cfg is not None:
            out.append((row, cfg))
    return out


def generate_phase4(suite: dict[str, Any], output_dir: Path, selected: Sequence[dict[str, str]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for _, selected_cfg in _selected_architecture_rows(selected):
        resolution = int(selected_cfg["candidate"]["img_size"])
        layers = len(selected_cfg["model"]["conv_specs"])
        for bits in suite["phases"]["quantization"]["bit_widths"]:
            name = base_experiment_name(resolution, layers, str(bits), str(bits), "0", "base")
            cfg = build_training_config(
                suite,
                name,
                resolution,
                layers,
                quantized=True,
                weight_bits=int(bits),
                activation_bits=int(bits),
                pruning_target=0,
            )
            tier = selected_cfg.get("experiment", {}).get("tier", "")
            cfg["experiment"] = {
                "name": name,
                "phase": 4,
                "suite": suite["suite"]["name"],
                "tier": tier,
                "source_experiment": selected_cfg.get("experiment", {}).get("name", selected_cfg["run"]["iteration_name"]),
            }
            path = generated_config_path(output_dir, name)
            write_yaml(path, cfg)
            rows.append(feasibility_row(cfg, path))
    return rows


def generate_phase45(suite: dict[str, Any], output_dir: Path, selected: Sequence[dict[str, str]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for _, selected_cfg in _selected_architecture_rows(selected):
        resolution = int(selected_cfg["candidate"]["img_size"])
        layers = len(selected_cfg["model"]["conv_specs"])
        quant = selected_cfg["quantization"]
        if not quant.get("enabled", True):
            continue
        for target in suite["phases"]["pruning"]["targets"]:
            bits_w = int(quant["weight_bits"])
            bits_a = int(quant["activation_bits"])
            name = base_experiment_name(resolution, layers, str(bits_w), str(bits_a), str(int(target)), "base")
            cfg = build_training_config(
                suite,
                name,
                resolution,
                layers,
                quantized=True,
                weight_bits=bits_w,
                activation_bits=bits_a,
                pruning_target=int(target),
            )
            cfg["experiment"] = {
                "name": name,
                "phase": 4.5,
                "suite": suite["suite"]["name"],
                "tier": selected_cfg.get("experiment", {}).get("tier", ""),
                "source_experiment": selected_cfg.get("experiment", {}).get("name", selected_cfg["run"]["iteration_name"]),
            }
            path = generated_config_path(output_dir, name)
            write_yaml(path, cfg)
            rows.append(feasibility_row(cfg, path))
    return rows


def generate_phase5(suite: dict[str, Any], output_dir: Path, selected: Sequence[dict[str, str]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for row, selected_cfg in _selected_architecture_rows(selected):
        selected_run_root = row.get("run_root") or selected_cfg.get("experiment", {}).get("selected_run_root", "")
        if not selected_run_root:
            continue
        resolution = int(selected_cfg["candidate"]["img_size"])
        layers = len(selected_cfg["model"]["conv_specs"])
        quant = selected_cfg.get("quantization", {})
        pruning = selected_cfg.get("pruning", {})
        w_label = str(quant.get("weight_bits", "float" if not quant.get("enabled", True) else ""))
        a_label = str(quant.get("activation_bits", "float" if not quant.get("enabled", True) else ""))
        p_label = str(int(round(float(pruning.get("final_sparsity", 0.0)) * 100.0)))
        source_name = selected_cfg.get("experiment", {}).get("name", selected_cfg["run"]["iteration_name"])
        for reuse_factor in suite["phases"]["reuse_factor"]["values"]:
            name = base_experiment_name(resolution, layers, w_label, a_label, p_label, str(int(reuse_factor)))
            cfg = deepcopy(selected_cfg)
            cfg["hls"]["reuse_factor"] = int(reuse_factor)
            cfg["hls"]["sweep_name"] = f"RF{int(reuse_factor)}"
            cfg["experiment"] = {
                "name": name,
                "phase": 5,
                "suite": suite["suite"]["name"],
                "tier": selected_cfg.get("experiment", {}).get("tier", ""),
                "source_experiment": source_name,
                "selected_run_root": selected_run_root,
            }
            path = generated_config_path(output_dir, name)
            write_yaml(path, cfg)
            rows.append(feasibility_row(cfg, path))
    return rows


def generate_configs(
    suite_path: Path,
    output_dir: Path,
    results_dir: Path,
    phases: Iterable[str],
    selected_candidates: Path | None = None,
) -> list[dict[str, Any]]:
    suite = load_yaml(suite_path)
    output_dir.mkdir(parents=True, exist_ok=True)
    phase_set = {phase_number(phase) for phase in phases}
    if not phase_set:
        phase_set = {"1", "2", "3"}
    selected = selected_rows(selected_candidates)
    rows: list[dict[str, Any]] = []
    if phase_set & {"1", "2", "3"}:
        rows.extend(generate_phase123(suite, output_dir))
    if "4" in phase_set:
        rows.extend(generate_phase4(suite, output_dir, selected))
    if "4.5" in phase_set:
        rows.extend(generate_phase45(suite, output_dir, selected))
    if "5" in phase_set:
        rows.extend(generate_phase5(suite, output_dir, selected))
    write_generation_outputs(rows, results_dir)
    return rows
