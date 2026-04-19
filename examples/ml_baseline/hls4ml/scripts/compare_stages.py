#!/usr/bin/env python3
"""Compare per-sample predictions between two named stages."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline import compare_stage_predictions


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", required=True, type=str)
    parser.add_argument("--left-stage", required=True, type=str)
    parser.add_argument("--right-stage", required=True, type=str)
    parser.add_argument("--artifact-root", type=Path, default=Path("artifacts"))
    parser.add_argument("--output", type=Path, default=None)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    summary, _ = compare_stage_predictions(
        candidate=args.candidate,
        left_stage=args.left_stage,
        right_stage=args.right_stage,
        artifact_root=args.artifact_root,
        output_path=args.output,
    )
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
