#!/usr/bin/env python3
"""Convert a candidate PyTorch checkpoint into an hls4ml project."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline import build_pytorch_hls_project, get_candidate


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=str, default=None, help="Candidate key from configs/candidates.yaml")
    parser.add_argument("--fold", type=int, default=0)
    parser.add_argument("--checkpoint", type=str, default="final", choices=["best", "final"])
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--project-name", type=str, default=None)
    parser.add_argument("--io-type", type=str, default="io_stream")
    parser.add_argument("--reuse-factor", type=int, default=4)
    parser.add_argument("--strategy", type=str, default="Resource")
    parser.add_argument("--backend", type=str, default="Vitis")
    parser.add_argument("--part", type=str, default=None)
    parser.add_argument("--clock-period", type=float, default=5.0)
    parser.add_argument("--default-precision", type=str, default="fixed<24,8>")
    parser.add_argument("--accum-precision", type=str, default=None)
    parser.add_argument("--dense-precision", type=str, default=None)
    parser.add_argument("--pool-accum-precision", type=str, default="fixed<40,20>")
    parser.add_argument("--device", type=str, default=None)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    candidate = get_candidate(args.candidate)
    project_name = args.project_name or f"{candidate.name}_pytorch_hls"
    output_dir = args.output_dir or Path("artifacts") / candidate.name / "hls" / "pytorch" / f"fold_{args.fold}"

    try:
        path = build_pytorch_hls_project(
            candidate,
            fold=args.fold,
            output_dir=output_dir,
            checkpoint_name=args.checkpoint,
            io_type=args.io_type,
            reuse_factor=args.reuse_factor,
            strategy=args.strategy,
            backend=args.backend,
            part=args.part,
            clock_period=args.clock_period,
            default_precision=args.default_precision,
            accum_precision=args.accum_precision,
            dense_precision=args.dense_precision,
            pool_accum_precision=args.pool_accum_precision,
            project_name=project_name,
            device_arg=args.device,
        )
    except ModuleNotFoundError as exc:
        raise SystemExit(str(exc)) from exc
    print(f"Wrote hls4ml project under: {path}")


if __name__ == "__main__":
    main()
