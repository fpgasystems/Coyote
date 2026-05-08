#!/usr/bin/env python3
"""Merge a separate experiment suite into the global config/status/results set."""

from __future__ import annotations

import argparse
import csv
import shutil
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline.experiment_cli import reexec_local_python_if_needed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-configs", type=Path, required=True)
    parser.add_argument("--extra-configs", type=Path, required=True)
    parser.add_argument("--global-configs", type=Path, required=True)
    parser.add_argument("--global-results", type=Path, required=True)
    parser.add_argument("--extra-results", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, default=Path("artifacts"))
    parser.add_argument("--plots", type=Path, default=None)
    return parser.parse_args()


def copy_configs(source: Path, target: Path) -> int:
    count = 0
    if not source.exists():
        return count
    target.mkdir(parents=True, exist_ok=True)
    for path in sorted(source.glob("*.yaml")):
        shutil.copy2(path, target / path.name)
        count += 1
    return count


def read_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def write_rows(path: Path, rows: list[dict[str, str]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def merge_status(global_results: Path, extra_results: Path) -> int:
    global_status = global_results / "suite_status.csv"
    extra_status = extra_results / "suite_status.csv"
    rows = read_rows(global_status)
    extra_rows = read_rows(extra_status)
    if not extra_rows:
        return len(rows)
    fieldnames = list(rows[0].keys()) if rows else list(extra_rows[0].keys())
    by_key = {(row.get("experiment_name", ""), row.get("requested_stages", "")): row for row in rows}
    for row in extra_rows:
        normalized = {key: row.get(key, "") for key in fieldnames}
        by_key[(normalized.get("experiment_name", ""), normalized.get("requested_stages", ""))] = normalized
    merged = list(by_key.values())
    merged.sort(key=lambda row: (str(row.get("phase", "")), str(row.get("experiment_name", "")), str(row.get("requested_stages", ""))))
    write_rows(global_status, merged, fieldnames)
    return len(merged)


def main() -> None:
    args = parse_args()
    reexec_local_python_if_needed(EXAMPLE_ROOT)

    from pipeline.experiment_results import collect_results
    from pipeline.experiment_plots import plot_results

    base_count = copy_configs(args.base_configs, args.global_configs)
    extra_count = copy_configs(args.extra_configs, args.global_configs)
    status_count = merge_status(args.global_results, args.extra_results)
    rows = collect_results(args.global_configs, args.artifacts, args.global_results)
    plots_dir = args.plots or args.global_results / "plots"
    outputs = plot_results(args.global_results / "experiment_summary.csv", plots_dir)
    print(
        "[merge] "
        f"base_configs={base_count} extra_configs={extra_count} "
        f"status_rows={status_count} summary_rows={len(rows)} plots={len(outputs)}"
    )


if __name__ == "__main__":
    main()
