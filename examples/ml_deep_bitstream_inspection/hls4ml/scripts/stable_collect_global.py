#!/usr/bin/env python3
"""Collect terminal experiment rows from base and extension suites into global results."""

from __future__ import annotations

import argparse
import csv
import shutil
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline.experiment_cli import reexec_local_python_if_needed
from pipeline.experiment_results import collect_results
from pipeline.experiment_plots import plot_results
from pipeline.experiment_suite import (
    feasibility_row,
    load_generated_configs,
    metadata_for_config,
    write_csv,
    write_generation_outputs,
)

STATUS_TERMINAL = {"success", "failed", "skipped_red"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-configs", type=Path, required=True)
    parser.add_argument("--base-results", type=Path, required=True)
    parser.add_argument("--global-configs", type=Path, required=True)
    parser.add_argument("--global-results", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, default=Path("artifacts"))
    parser.add_argument("--plots", type=Path, default=None)
    parser.add_argument(
        "--extra",
        action="append",
        nargs=2,
        metavar=("CONFIG_DIR", "RESULTS_DIR"),
        default=[],
        help="Extra config/results pair. May be repeated.",
    )
    parser.add_argument("--snapshot", action="store_true", help="Snapshot current global files before rewriting")
    return parser.parse_args()


def read_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def snapshot_global(global_configs: Path, global_results: Path) -> Path:
    snapshot = global_results / "_snapshots" / f"{time.strftime('%Y%m%d_%H%M%S')}_stable_collect_global"
    snapshot.mkdir(parents=True, exist_ok=False)
    for name in [
        "suite_status.csv",
        "experiment_summary.csv",
        "resolution_depth_results.csv",
        "feasibility_matrix.csv",
        "phase4_selection.csv",
        "phase45_selection.csv",
    ]:
        src = global_results / name
        if src.exists():
            shutil.copy2(src, snapshot / name)
    plots = global_results / "plots"
    if plots.exists():
        shutil.copytree(plots, snapshot / "plots")
    if global_configs.exists():
        shutil.copytree(global_configs, snapshot / global_configs.name)
    return snapshot


def terminal_rows(results_dir: Path) -> list[dict[str, str]]:
    return [row for row in read_rows(results_dir / "suite_status.csv") if row.get("status") in STATUS_TERMINAL]


def config_names(config_dir: Path) -> set[str]:
    return {path.stem for path in config_dir.glob("*.yaml")}


def copy_config(config_dir: Path, name: str, global_configs: Path) -> Path:
    src = config_dir / f"{name}.yaml"
    if not src.exists():
        raise FileNotFoundError(src)
    dst = global_configs / src.name
    shutil.copy2(src, dst)
    return dst


def main() -> None:
    args = parse_args()
    reexec_local_python_if_needed(EXAMPLE_ROOT)

    snapshot = snapshot_global(args.global_configs, args.global_results) if args.snapshot else None

    suites: list[tuple[Path, Path]] = [(args.base_configs, args.base_results)]
    suites.extend((Path(config_dir), Path(results_dir)) for config_dir, results_dir in args.extra)

    args.global_configs.mkdir(parents=True, exist_ok=True)
    for old in args.global_configs.glob("*.yaml"):
        old.unlink()

    status_fieldnames: list[str] = []
    status_rows_by_key: dict[tuple[str, str], dict[str, str]] = {}
    copied = 0

    for config_dir, results_dir in suites:
        names = config_names(config_dir)
        for row in terminal_rows(results_dir):
            name = row.get("experiment_name", "")
            if name not in names:
                continue
            dst = copy_config(config_dir, name, args.global_configs)
            copied += 1
            if not status_fieldnames:
                status_fieldnames = list(row.keys())
            normalized = {key: row.get(key, "") for key in status_fieldnames}
            normalized["config_path"] = str(dst)
            status_rows_by_key[(normalized.get("experiment_name", ""), normalized.get("requested_stages", ""))] = normalized

    configs = {
        metadata_for_config(cfg, path)["experiment_name"]: metadata_for_config(cfg, path)
        for path, cfg in load_generated_configs(args.global_configs)
    }
    status_rows = list(status_rows_by_key.values())
    for row in status_rows:
        meta = configs.get(row.get("experiment_name", ""))
        if not meta:
            continue
        row["phase"] = str(meta.get("phase", row.get("phase", "")))
        row["tier"] = str(meta.get("tier", row.get("tier", "")))
        row["config_path"] = str(meta.get("config_path", row.get("config_path", "")))
    status_rows.sort(key=lambda row: (str(row.get("phase", "")), str(row.get("experiment_name", "")), str(row.get("requested_stages", ""))))
    write_csv(args.global_results / "suite_status.csv", status_rows, fieldnames=status_fieldnames)

    feasibility_rows = [feasibility_row(cfg, path) for path, cfg in load_generated_configs(args.global_configs)]
    feasibility_rows.sort(key=lambda row: (int(row.get("input_resolution") or 0), int(row.get("num_layers") or 0), str(row.get("experiment_name", ""))))
    write_generation_outputs(feasibility_rows, args.global_results)

    summary_rows = collect_results(args.global_configs, args.artifacts, args.global_results)
    plots_dir = args.plots or args.global_results / "plots"
    outputs = plot_results(args.global_results / "experiment_summary.csv", plots_dir)
    print(
        "[stable_collect_global] "
        f"copied_configs={copied} status_rows={len(status_rows)} "
        f"summary_rows={len(summary_rows)} plots={len(outputs)}"
    )
    if snapshot:
        print(f"[stable_collect_global] snapshot={snapshot}")


if __name__ == "__main__":
    main()
