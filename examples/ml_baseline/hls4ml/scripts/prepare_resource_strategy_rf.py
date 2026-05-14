#!/usr/bin/env python3
"""Prepare resource-strategy RF sweep configs for selected feasible P50 runs."""

from __future__ import annotations

import argparse
import csv
import json
import os
import shutil
import sys
import time
from copy import deepcopy
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline.experiment_cli import reexec_local_python_if_needed
from pipeline.experiment_suite import analyze_model_shape, load_yaml, metadata_for_config, write_csv, write_yaml


SOURCE_RUNS = [
    {
        "label": "res512_layers7",
        "config": Path("configs/hls4ml_selected_feasible_candidates/res512_layers7_W8A8_P50_RFbase.yaml"),
        "source_run_root": Path(
            "/mnt/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/"
            "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img512/notebook_pruned_qat/"
            "res512_layers7_W8A8_P50_RFbase_b3a09a3d898b"
        ),
    },
    {
        "label": "res256_layers6",
        "config": Path("configs/hls4ml_selected_feasible_candidates/res256_layers6_W8A8_P50_RFbase.yaml"),
        "source_run_root": Path(
            "/mnt/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/"
            "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img256/notebook_pruned_qat/"
            "res256_layers6_W8A8_P50_RFbase_e7705f9077f8"
        ),
    },
    {
        "label": "res256_layers7",
        "config": Path("configs/hls4ml_selected_feasible_candidates/res256_layers7_W8A8_P50_RFbase.yaml"),
        "source_run_root": Path(
            "/mnt/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/"
            "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img256/notebook_pruned_qat/"
            "res256_layers7_W8A8_P50_RFbase_74abd8967440"
        ),
    },
]
RF_VALUES = [32, 16, 8, 4, 2, 1]
WAVES = [
    ("wave1_rf32_rf16", [32, 16]),
    ("wave2_rf8_rf4", [8, 4]),
    ("wave3_rf2_rf1", [2, 1]),
]
RESOURCE_SUFFIX = "resource_strategy"


def read_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def write_rows(path: Path, rows: list[dict[str, Any]], fieldnames: list[str] | None = None) -> None:
    write_csv(path, rows, fieldnames=fieldnames)


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}


def symlink_or_check(src: Path, dst: Path) -> None:
    if not src.exists():
        raise FileNotFoundError(src)
    if dst.is_symlink():
        if dst.resolve() == src.resolve():
            return
        raise RuntimeError(f"refusing to replace existing symlink {dst} -> {os.readlink(dst)}")
    if dst.exists():
        return
    dst.symlink_to(src, target_is_directory=src.is_dir())


def stage_resource_run_root(source_run_root: Path, resource_run_root: Path) -> None:
    resource_run_root.mkdir(parents=True, exist_ok=True)
    for name in ["fold_0", "fold_1", "fold_2", "fold_3", "fold_4", "pooled"]:
        src = source_run_root / name
        if src.exists():
            symlink_or_check(src, resource_run_root / name)
    for pattern in [
        "kfold_summary.csv",
        "sparsity_fold_*.csv",
        "sparsity_fold_*.png",
        "final_evaluation_plots.png",
        "evaluation_dashboard.png",
        "kfold_training_curves.png",
    ]:
        for src in source_run_root.glob(pattern):
            symlink_or_check(src, resource_run_root / src.name)
    marker = {
        "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "source_run_root": str(source_run_root),
        "purpose": "Resource-strategy HLS-only RF sweep using cached trained folds.",
    }
    (resource_run_root / "resource_strategy_source.json").write_text(json.dumps(marker, indent=2, sort_keys=True) + "\n")


def resource_run_root_for(source_run_root: Path, cfg: dict[str, Any]) -> Path:
    training_manifest = load_json(source_run_root / "fold_0" / "training_manifest.json")
    short = str(training_manifest.get("fingerprint") or source_run_root.name.split("_")[-1])[:12]
    base_name = f"{cfg['run']['iteration_name']}_{RESOURCE_SUFFIX}_from_{short}"
    return source_run_root.parent / base_name


def resource_experiment_name(cfg: dict[str, Any], rf: int) -> str:
    resolution = int(cfg["candidate"]["img_size"])
    layers = len(cfg["model"]["conv_specs"])
    quant = cfg["quantization"]
    pruning = cfg["pruning"]
    pruning_label = int(round(float(pruning["final_sparsity"]) * 100.0))
    return (
        f"res{resolution}_layers{layers}_W{int(quant['weight_bits'])}A{int(quant['activation_bits'])}_"
        f"P{pruning_label}_RFResource{int(rf)}"
    )


def resource_config(source_cfg_path: Path, source_run_root: Path, rf: int) -> tuple[str, Path, dict[str, Any]]:
    cfg = deepcopy(load_yaml(source_cfg_path))
    resource_run_root = resource_run_root_for(source_run_root, cfg)
    stage_resource_run_root(source_run_root, resource_run_root)
    name = resource_experiment_name(cfg, rf)
    cfg["run"]["iteration_name"] = name
    cfg["run"]["output_root"] = "artifacts_selected_feasible_candidates"
    cfg["training"]["allow_stale_fold_cache"] = True
    cfg["hls"]["strategy"] = "Resource"
    cfg["hls"]["resource_strategy"] = "Resource"
    cfg["hls"]["reuse_factor"] = int(rf)
    cfg["hls"]["sweep_name"] = f"RFResource{int(rf)}"
    cfg.setdefault("experiment", {})
    cfg["experiment"].update(
        {
            "name": name,
            "phase": 5,
            "suite": "hls4ml_selected_feasible_candidates_resource_strategy",
            "source_experiment": source_cfg_path.stem,
            "selected_run_root": str(resource_run_root),
            "source_run_root": str(source_run_root),
            "strategy_variant": "Resource",
        }
    )
    return name, resource_run_root, cfg


def clean_yaml_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    for old in path.glob("*.yaml"):
        old.unlink()


def write_manifest(results_dir: Path, rows: list[dict[str, Any]]) -> None:
    fieldnames = [
        "wave",
        "experiment_name",
        "source_label",
        "reuse_factor",
        "strategy",
        "selected_run_root",
        "source_run_root",
        "config_path",
    ]
    write_rows(results_dir / "resource_strategy_manifest.csv", rows, fieldnames=fieldnames)
    lines = [
        "# Resource-Strategy RF Sweep",
        "",
        "HLS-only RF sweep for selected W8A8/P50 candidates with `hls.strategy=Resource`.",
        "",
        "| Wave | Experiment | RF | Source | Selected run root |",
        "| --- | --- | ---: | --- | --- |",
    ]
    for row in rows:
        lines.append(
            f"| `{row['wave']}` | `{row['experiment_name']}` | {row['reuse_factor']} | "
            f"`{row['source_label']}` | `{row['selected_run_root']}` |"
        )
    (results_dir / "resource_strategy_manifest.md").write_text("\n".join(lines) + "\n")


def verify_configs(config_dir: Path, wave_root: Path, results_dir: Path) -> None:
    import yaml

    config_paths = sorted(config_dir.glob("*.yaml"))
    if len(config_paths) != 18:
        raise SystemExit(f"expected 18 configs, found {len(config_paths)}")
    failures = []
    for path in config_paths:
        cfg = yaml.safe_load(path.read_text())
        if cfg["hls"]["strategy"] != "Resource":
            failures.append(f"{path}: hls.strategy={cfg['hls']['strategy']}")
        if cfg["hls"]["resource_strategy"] != "Resource":
            failures.append(f"{path}: hls.resource_strategy={cfg['hls']['resource_strategy']}")
        if not str(cfg["hls"]["sweep_name"]).startswith("RFResource"):
            failures.append(f"{path}: hls.sweep_name={cfg['hls']['sweep_name']}")
        selected_root = Path(cfg["experiment"]["selected_run_root"])
        if "artifacts_selected_feasible_candidates" not in selected_root.parts:
            failures.append(f"{path}: selected_run_root not under artifacts_selected_feasible_candidates")
        if not (selected_root / "fold_0" / "final_weights.weights.h5").exists():
            failures.append(f"{path}: missing selected fold_0 weights")
    wave1 = sorted((wave_root / "wave1_rf32_rf16").glob("*.yaml"))
    if len(wave1) != 6:
        failures.append(f"wave1 expected 6 configs, found {len(wave1)}")
    for path in wave1:
        cfg = yaml.safe_load(path.read_text())
        if int(cfg["hls"]["reuse_factor"]) not in {32, 16}:
            failures.append(f"{path}: unexpected wave1 RF={cfg['hls']['reuse_factor']}")
    if failures:
        raise SystemExit("\n".join(failures))
    write_rows(results_dir / "verification_prelaunch.csv", [{"check": "prelaunch", "status": "success", "configs": len(config_paths)}])
    print(f"[resource-rf] prelaunch verification passed: configs={len(config_paths)}")


def verify_outputs(config_dir: Path, results_dir: Path) -> None:
    import yaml

    rows: list[dict[str, Any]] = []
    failures = []
    for path in sorted(config_dir.glob("*.yaml")):
        cfg = yaml.safe_load(path.read_text())
        selected_root = Path(cfg["experiment"]["selected_run_root"])
        sweep_dirs = sorted((selected_root / "hls_sweeps").glob(f"{cfg['hls']['sweep_name']}_hls_*"))
        if not sweep_dirs:
            rows.append({"experiment_name": cfg["experiment"]["name"], "status": "missing_hls_sweep", "full_hls_config": ""})
            continue
        full_config = sweep_dirs[-1] / "fold_0" / "project" / "full_hls_config.json"
        if not full_config.exists():
            rows.append({"experiment_name": cfg["experiment"]["name"], "status": "missing_full_hls_config", "full_hls_config": str(full_config)})
            continue
        payload = json.loads(full_config.read_text())
        bad_layers = [
            name for name, layer in payload.get("LayerName", {}).items() if layer.get("Strategy") != "Resource"
        ]
        status = "success" if payload.get("Model", {}).get("Strategy") == "Resource" and not bad_layers else "failed"
        if status != "success":
            failures.append(cfg["experiment"]["name"])
        rows.append(
            {
                "experiment_name": cfg["experiment"]["name"],
                "status": status,
                "model_strategy": payload.get("Model", {}).get("Strategy", ""),
                "bad_layer_count": len(bad_layers),
                "full_hls_config": str(full_config),
            }
        )
    write_rows(results_dir / "verification_outputs.csv", rows)
    if failures:
        raise SystemExit(f"resource strategy verification failed for: {', '.join(failures)}")
    print(f"[resource-rf] output verification rows={len(rows)} failures={len(failures)}")


def prepare(args: argparse.Namespace) -> None:
    args.config_dir.mkdir(parents=True, exist_ok=True)
    args.results_dir.mkdir(parents=True, exist_ok=True)
    clean_yaml_dir(args.config_dir)
    args.wave_root.mkdir(parents=True, exist_ok=True)
    for wave_name, _ in WAVES:
        clean_yaml_dir(args.wave_root / wave_name)

    rows: list[dict[str, Any]] = []
    feasibility_rows: list[dict[str, Any]] = []
    for source in SOURCE_RUNS:
        cfg_path = source["config"]
        source_run_root = source["source_run_root"]
        if not cfg_path.exists():
            raise FileNotFoundError(cfg_path)
        if not source_run_root.exists():
            raise FileNotFoundError(source_run_root)
        for rf in RF_VALUES:
            name, resource_run_root, cfg = resource_config(cfg_path, source_run_root, rf)
            config_path = args.config_dir / f"{name}.yaml"
            write_yaml(config_path, cfg)
            wave_name = next(wave for wave, values in WAVES if rf in values)
            wave_path = args.wave_root / wave_name / f"{name}.yaml"
            write_yaml(wave_path, cfg)
            rows.append(
                {
                    "wave": wave_name,
                    "experiment_name": name,
                    "source_label": source["label"],
                    "reuse_factor": rf,
                    "strategy": "Resource",
                    "selected_run_root": str(resource_run_root),
                    "source_run_root": str(source_run_root),
                    "config_path": str(config_path),
                }
            )
            meta = metadata_for_config(cfg, config_path)
            shape = analyze_model_shape(cfg)
            meta.update(
                {
                    "status": "pending",
                    "skip_reason": "",
                    "final_feature_map_height": shape["final_feature_map_height"],
                    "final_feature_map_width": shape["final_feature_map_width"],
                    "final_channels": shape["final_channels"],
                    "final_avg_pool": shape["final_avg_pool"],
                    "final_pool_area": shape["final_pool_area"],
                    "final_pool_work": shape["final_pool_work"],
                }
            )
            feasibility_rows.append(meta)
    write_manifest(args.results_dir, rows)
    write_csv(args.results_dir / "feasibility_matrix.csv", feasibility_rows)
    verify_configs(args.config_dir, args.wave_root, args.results_dir)
    print(f"[resource-rf] wrote configs={len(rows)} config_dir={args.config_dir} wave_root={args.wave_root}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "verify-configs", "verify-outputs"])
    parser.add_argument("--config-dir", type=Path, default=Path("configs/hls4ml_selected_feasible_candidates_resource_strategy"))
    parser.add_argument("--wave-root", type=Path, default=Path("configs/hls4ml_selected_feasible_candidates_resource_strategy_waves"))
    parser.add_argument("--results-dir", type=Path, default=Path("results/selected_feasible_candidates_resource_strategy"))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    reexec_local_python_if_needed(EXAMPLE_ROOT)
    if args.action == "prepare":
        prepare(args)
    elif args.action == "verify-configs":
        verify_configs(args.config_dir, args.wave_root, args.results_dir)
    elif args.action == "verify-outputs":
        verify_outputs(args.config_dir, args.results_dir)


if __name__ == "__main__":
    main()
