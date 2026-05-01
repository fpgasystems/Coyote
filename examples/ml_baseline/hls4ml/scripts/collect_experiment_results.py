#!/usr/bin/env python3
"""Collect generated hls4ml experiment artifacts into master CSV files."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline.experiment_cli import reexec_local_python_if_needed
from pipeline.experiment_results import collect_results


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configs", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--results-dir", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    reexec_local_python_if_needed(EXAMPLE_ROOT)
    rows = collect_results(args.configs, args.artifacts, args.results_dir)
    print(f"[collect] wrote {len(rows)} rows to {args.results_dir / 'experiment_summary.csv'}")


if __name__ == "__main__":
    main()
