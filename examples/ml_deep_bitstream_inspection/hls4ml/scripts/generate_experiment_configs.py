#!/usr/bin/env python3
"""Generate hls4ml experiment configs and feasibility metadata."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline.experiment_cli import reexec_local_python_if_needed
from pipeline.experiment_suite import generate_configs


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--results-dir", type=Path, required=True)
    parser.add_argument("--phases", default="1,2,3")
    parser.add_argument("--selected-candidates", type=Path, default=None)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    reexec_local_python_if_needed(EXAMPLE_ROOT)
    phases = [phase.strip() for phase in args.phases.split(",") if phase.strip()]
    rows = generate_configs(args.suite, args.output_dir, args.results_dir, phases, args.selected_candidates)
    print(f"[generate] wrote {len(rows)} configs/rows")
    print(f"[generate] feasibility={args.results_dir / 'feasibility_matrix.csv'}")


if __name__ == "__main__":
    main()
