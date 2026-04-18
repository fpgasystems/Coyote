#!/usr/bin/env python3
"""Evaluate a configured candidate against its archived fold splits."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline import aggregate_candidate_metrics, evaluate_candidate_fold, get_candidate


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=str, default=None, help="Candidate key from configs/candidates.yaml")
    parser.add_argument("--fold", type=int, default=None, help="Evaluate a single fold instead of all folds")
    parser.add_argument("--stage", type=str, default="pytorch_float")
    parser.add_argument("--checkpoint", type=str, default="final", choices=["best", "final"])
    parser.add_argument("--batch-size", type=int, default=8)
    parser.add_argument("--num-workers", type=int, default=0)
    parser.add_argument("--device", type=str, default=None)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    candidate = get_candidate(args.candidate)

    folds = [args.fold] if args.fold is not None else list(candidate.folds)
    for fold in folds:
        result = evaluate_candidate_fold(
            candidate,
            fold=fold,
            stage_name=args.stage,
            checkpoint_name=args.checkpoint,
            batch_size=args.batch_size,
            num_workers=args.num_workers,
            device_arg=args.device,
        )
        print(f"Evaluated {candidate.name} fold_{fold}: {result['stage_dir']}")

    if args.fold is None:
        metrics = aggregate_candidate_metrics(candidate, stage_name=args.stage)
        print(
            "Pooled metrics:",
            f"accuracy={metrics['accuracy']:.4f}",
            f"roc_auc={metrics['roc_auc']:.4f}",
            f"mcc={metrics['mcc']:.4f}",
        )


if __name__ == "__main__":
    main()
