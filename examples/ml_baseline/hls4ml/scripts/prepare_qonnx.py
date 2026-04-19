#!/usr/bin/env python3
"""Clean an ONNX file with QONNX and convert CNNs to channels-last format."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline import clean_qonnx_model


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--no-channels-last", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    try:
        path = clean_qonnx_model(
            onnx_path=args.input,
            output_path=args.output,
            convert_channels_last=not args.no_channels_last,
        )
    except ModuleNotFoundError as exc:
        raise SystemExit(str(exc)) from exc
    print(f"Wrote cleaned QONNX model to: {path}")


if __name__ == "__main__":
    main()
