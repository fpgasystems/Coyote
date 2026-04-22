#!/usr/bin/env python3
"""Post-hoc plot generation for existing QKeras QAT fold directories.

Reads history.csv, per_sample.csv, augmented_per_sample.csv, and
training_manifest.json under each fold_k directory, then writes the same
evaluation_dashboard.png / training_curves.png / final_evaluation_plots.png
plots produced inline by train_qkeras_qat.py. When --all-folds is set,
kfold_training_curves.png, kfold_summary.csv, and run-level dashboards are
written at the quantizer root.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline import get_candidate  # noqa: E402
from pipeline.qkeras_qat import DEFAULT_QAT_TAGS, qkeras_artifact_root, qkeras_fold_dir  # noqa: E402
from pipeline.qkeras_plots import (  # noqa: E402
    write_fold_plots_from_disk,
    write_kfold_plots_from_disk,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", default="cnn_small_hls_opt_img512")
    parser.add_argument("--quantizer-tag", default="w6_a8",
                        help=f"One of {DEFAULT_QAT_TAGS}, or 'sweep' or 'all'")
    parser.add_argument("--fold", type=int, default=None,
                        help="Only plot this fold (default: all present folds)")
    parser.add_argument("--all-folds", action="store_true",
                        help="Also emit k-fold-level plots at the quantizer root")
    parser.add_argument("--output-root", type=Path, default=None)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    candidate = get_candidate(args.candidate)
    if args.quantizer_tag in ("sweep", "all"):
        tags = list(DEFAULT_QAT_TAGS)
    else:
        tags = [args.quantizer_tag]

    for tag in tags:
        root = qkeras_artifact_root(candidate, tag, args.output_root)
        if not root.exists():
            print(f"[plot] skip quantizer={tag}: root does not exist ({root})")
            continue

        if args.fold is not None:
            candidate_folds = [args.fold]
        else:
            candidate_folds = [f for f in candidate.folds
                               if qkeras_fold_dir(candidate, tag, f, args.output_root).exists()]
        fold_dirs: list[Path] = []
        for fold in candidate_folds:
            fold_dir = qkeras_fold_dir(candidate, tag, fold, args.output_root)
            if not (fold_dir / "history.csv").exists():
                print(f"[plot] skip quantizer={tag} fold={fold}: history.csv missing")
                continue
            print(f"[plot] per-fold quantizer={tag} fold={fold} -> {fold_dir}")
            write_fold_plots_from_disk(fold_dir)
            fold_dirs.append(fold_dir)

        if args.all_folds and len(fold_dirs) >= 2:
            print(f"[plot] kfold quantizer={tag} folds={len(fold_dirs)} -> {root}")
            write_kfold_plots_from_disk(candidate, tag, root, fold_dirs)


if __name__ == "__main__":
    main()
