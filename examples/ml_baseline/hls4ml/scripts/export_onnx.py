#!/usr/bin/env python3
"""Export a configured PyTorch checkpoint to ONNX."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline import export_candidate_onnx, get_candidate


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=str, default=None, help="Candidate key from configs/candidates.yaml")
    parser.add_argument("--fold", type=int, default=0)
    parser.add_argument("--checkpoint", type=str, default="final", choices=["best", "final"])
    parser.add_argument("--opset", type=int, default=17)
    parser.add_argument("--device", type=str, default=None)
    parser.add_argument("--output", type=Path, default=None)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    candidate = get_candidate(args.candidate)
    output = args.output or Path("artifacts") / candidate.name / "onnx" / f"fold_{args.fold}" / f"{args.checkpoint}.onnx"
    try:
        path = export_candidate_onnx(
            candidate,
            fold=args.fold,
            output_path=output,
            checkpoint_name=args.checkpoint,
            opset_version=args.opset,
            device_arg=args.device,
        )
    except ModuleNotFoundError as exc:
        raise SystemExit(str(exc)) from exc
    print(f"Exported ONNX model to: {path}")


if __name__ == "__main__":
    main()
