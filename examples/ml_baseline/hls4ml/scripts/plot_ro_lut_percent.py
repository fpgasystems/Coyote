#!/usr/bin/env python3
"""Create RO-count LUT-percentage diagnostic plots from per_sample.csv."""

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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--per-sample-csv", type=Path, help="Input per_sample.csv or pooled/per_sample.csv")
    source.add_argument("--run-root", type=Path, help="Run root containing pooled/per_sample.csv")
    parser.add_argument("--output-dir", type=Path, help="Directory for generated plots")
    parser.add_argument("--title-prefix", default=None, help="Optional plot title prefix")
    parser.add_argument("--full-device-luts", type=float, default=None, help="Override full-FPGA LUT denominator")
    parser.add_argument("--dynamic-region-luts", type=float, default=None, help="Override dynamic-region LUT denominator")
    return parser.parse_args()


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def main() -> None:
    args = parse_args()
    reexec_local_python_if_needed(EXAMPLE_ROOT)
    from pipeline.device_resources import XCU55C_DYNAMIC_REGION_CLB_LUTS, XCU55C_TOTAL_CLB_LUTS
    from pipeline.qkeras_plots import write_ro_lut_percent_diagnostic_plots

    if args.run_root is not None:
        per_sample_csv = args.run_root / "pooled" / "per_sample.csv"
        output_dir = args.output_dir or args.run_root / "pooled"
        title_prefix = args.title_prefix if args.title_prefix is not None else "Pooled folds"
    else:
        per_sample_csv = args.per_sample_csv
        output_dir = args.output_dir or per_sample_csv.parent
        title_prefix = args.title_prefix

    if per_sample_csv is None:
        raise ValueError("missing per-sample CSV path")
    if not per_sample_csv.exists():
        raise FileNotFoundError(f"missing per-sample CSV: {per_sample_csv}")

    rows = read_rows(per_sample_csv)
    outputs = write_ro_lut_percent_diagnostic_plots(
        output_dir,
        rows,
        title_prefix=title_prefix,
        full_device_luts=args.full_device_luts or XCU55C_TOTAL_CLB_LUTS,
        dynamic_region_luts=args.dynamic_region_luts or XCU55C_DYNAMIC_REGION_CLB_LUTS,
    )
    for name, path in outputs.items():
        print(f"[plot] {name}: {path}")


if __name__ == "__main__":
    main()
