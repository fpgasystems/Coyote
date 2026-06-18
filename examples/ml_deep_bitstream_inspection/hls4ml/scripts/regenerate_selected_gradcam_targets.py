#!/usr/bin/env python3
"""Regenerate selected-candidate Grad-CAM bundles at fixed activation sizes."""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline.experiment_cli import reexec_local_python_if_needed
from pipeline.experiment_suite import load_yaml
from pipeline.notebook_flow import build_context
from pipeline.part1_common import fold_dir, flow_candidate, read_csv
from pipeline.part2_train import (
    get_splits,
    load_fold_model,
    qkeras_gradcam_target_layers,
    sample_to_nhwc,
)
from pipeline.qkeras_plots import write_qkeras_gradcam_bundle


def read_status(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def selected_rows(results_dir: Path, configs_dir: Path, phases: set[str]) -> list[dict[str, str]]:
    rows = []
    seen: set[tuple[str, str]] = set()
    for row in read_status(results_dir / "suite_status.csv"):
        phase = str(row.get("phase", ""))
        run_root = row.get("run_root", "")
        config_path = row.get("config_path", "")
        if phase not in phases or not run_root or not config_path:
            continue
        # Include failed train,hls rows too: these may have finished training and failed in HLS.
        if not (Path(run_root) / "fold_0" / "final_weights.weights.h5").exists():
            continue
        key = (row.get("experiment_name", ""), run_root)
        if key in seen:
            continue
        seen.add(key)
        rows.append(row)
    if rows:
        return rows

    # Fallback for manual artifact roots: derive run roots from config filenames.
    for path in sorted(configs_dir.glob("*.yaml")):
        cfg = load_yaml(path)
        phase = str(cfg.get("experiment", {}).get("phase", ""))
        if phase not in phases:
            continue
        run_root = cfg.get("run", {}).get("output_root", "")
        if run_root:
            rows.append({"experiment_name": cfg["experiment"]["name"], "phase": phase, "config_path": str(path), "run_root": run_root})
    return rows


def regenerate_row(row: dict[str, str], args: argparse.Namespace) -> None:
    config_path = Path(row["config_path"]).resolve()
    run_root = Path(row["run_root"]).resolve()
    cfg = load_yaml(config_path)
    ctx = build_context(cfg, config_path=config_path, run_root_arg=run_root)
    target_layers = qkeras_gradcam_target_layers(ctx, tuple(args.target_sizes))
    if not target_layers:
        print(f"[gradcam] skip {row['experiment_name']}: no exact target sizes {args.target_sizes}")
        return
    splits = get_splits(ctx)
    candidate = flow_candidate(ctx)
    folds = args.folds if args.folds is not None else ctx.active_folds
    print(
        f"[gradcam] {row['experiment_name']} run_root={ctx.run_root} "
        f"targets={[(t['target_size'], t['layer_name'], t['shape']) for t in target_layers]} folds={folds}"
    )
    for fold in folds:
        fdir = fold_dir(ctx, int(fold))
        weights = fdir / "final_weights.weights.h5"
        per_sample = fdir / "per_sample.csv"
        if not weights.exists() or not per_sample.exists():
            print(f"[gradcam] skip {row['experiment_name']} fold={fold}: missing weights/per_sample")
            continue
        val_samples = splits[int(fold)][1]
        prediction_rows = read_csv(per_sample)
        model = load_fold_model(ctx, int(fold))
        for target in target_layers:
            size = int(target["target_size"])
            out_dir = fdir / f"gradcam_final_{size}x{size}"
            write_qkeras_gradcam_bundle(
                model,
                val_samples,
                prediction_rows,
                out_dir,
                image_getter=lambda sample: sample_to_nhwc(sample, candidate),
                target_layer_name=str(target["layer_name"]),
                target_layer_shape=str(target["shape"]),
                split_label=f"fold_{fold}",
                command_text=(
                    f"regenerate_selected_gradcam_targets.py experiment={row['experiment_name']} "
                    f"fold={fold} target_layer={target['layer_name']} target_shape={target['shape']}"
                ),
            )
            print(f"[gradcam] wrote {out_dir}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results-dir", type=Path, default=Path("results/selected_feasible_candidates"))
    parser.add_argument("--configs-dir", type=Path, default=Path("configs/hls4ml_selected_feasible_candidates"))
    parser.add_argument("--phases", default="4.5", help="Comma-separated phases to regenerate, default: 4.5")
    parser.add_argument("--target-sizes", type=int, nargs="+", default=[64, 32])
    parser.add_argument("--folds", type=int, nargs="*", default=None, help="Optional fold list; default: all active folds")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    reexec_local_python_if_needed(EXAMPLE_ROOT)
    phases = {item.strip() for item in str(args.phases).split(",") if item.strip()}
    rows = selected_rows(args.results_dir, args.configs_dir, phases)
    if not rows:
        raise SystemExit(f"no rows with weights found under {args.results_dir} for phases={sorted(phases)}")
    for row in rows:
        regenerate_row(row, args)


if __name__ == "__main__":
    main()
