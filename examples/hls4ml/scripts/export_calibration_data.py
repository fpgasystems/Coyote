#!/usr/bin/env python3
"""Export deterministic calibration inputs for HLS and hardware bring-up."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline import export_calibration_bundle, get_candidate


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=str, default=None, help="Candidate key from configs/candidates.yaml")
    parser.add_argument("--fold", type=int, default=0, help="Fold whose archived validation set is used")
    parser.add_argument("--checkpoint", type=str, default="final", choices=["best", "final"])
    parser.add_argument("--max-samples", type=int, default=16)
    parser.add_argument("--output-dir", type=Path, default=None)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    candidate = get_candidate(args.candidate)
    output_dir = args.output_dir or (Path("artifacts") / candidate.name / "exports" / f"fold_{args.fold}")
    path = export_calibration_bundle(
        candidate,
        fold=args.fold,
        output_dir=output_dir,
        max_samples=args.max_samples,
        checkpoint_name=args.checkpoint,
    )
    print(f"Exported calibration bundle to: {path}")


if __name__ == "__main__":
    main()
