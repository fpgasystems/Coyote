#!/usr/bin/env python3
"""Convert a trained QKeras QAT fold to an hls4ml project."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline import get_candidate  # noqa: E402
from pipeline.qkeras_qat import (  # noqa: E402
    DEFAULT_OUTPUT_PRECISION,
    DEFAULT_POOL_ACCUM_PRECISION,
    build_qkeras_hls_project,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", default="cnn_small_hls_opt_img512")
    parser.add_argument("--quantizer-tag", default="w6_a8")
    parser.add_argument("--fold", type=int, default=0)
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--project-name", default=None)
    parser.add_argument("--qat-output-root", type=Path, default=None)
    parser.add_argument("--io-type", default="io_stream")
    parser.add_argument("--backend", default="Vitis")
    parser.add_argument("--strategy", default="Resource")
    parser.add_argument("--reuse-factor", type=int, default=8)
    parser.add_argument("--part", default=None)
    parser.add_argument("--clock-period", type=float, default=5.0)
    parser.add_argument("--accum-precision", default=None)
    parser.add_argument("--output-precision", default=DEFAULT_OUTPUT_PRECISION)
    parser.add_argument("--pool-accum-precision", default=DEFAULT_POOL_ACCUM_PRECISION)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    candidate = get_candidate(args.candidate)
    project_name = args.project_name or f"{candidate.name}_{args.quantizer_tag}_qkeras_hls"
    output_dir = args.output_dir or (
        Path("artifacts") / candidate.name / "hls" / f"qkeras_{args.quantizer_tag}" / f"fold_{args.fold}"
    )
    path = build_qkeras_hls_project(
        candidate,
        quantizer_tag=args.quantizer_tag,
        fold=args.fold,
        output_dir=output_dir,
        project_name=project_name,
        qat_output_root=args.qat_output_root,
        io_type=args.io_type,
        backend=args.backend,
        strategy=args.strategy,
        reuse_factor=args.reuse_factor,
        part=args.part,
        clock_period=args.clock_period,
        accum_precision=args.accum_precision,
        output_precision=args.output_precision,
        pool_accum_precision=args.pool_accum_precision,
    )
    print(f"Wrote QKeras hls4ml project under: {path}")


if __name__ == "__main__":
    main()
