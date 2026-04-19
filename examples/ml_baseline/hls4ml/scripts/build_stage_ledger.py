#!/usr/bin/env python3
"""Write one consolidated ledger of per-sample outputs across stages."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline import write_stage_ledger


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact-root", type=Path, default=Path("artifacts"))
    parser.add_argument("--candidate", type=str, default=None)
    parser.add_argument("--stage", type=str, default=None)
    parser.add_argument("--output", type=Path, default=Path("artifacts/stage_ledger.csv"))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    path = write_stage_ledger(
        output_path=args.output,
        artifact_root=args.artifact_root,
        candidate=args.candidate,
        stage=args.stage,
    )
    print(f"Wrote stage ledger: {path}")


if __name__ == "__main__":
    main()
