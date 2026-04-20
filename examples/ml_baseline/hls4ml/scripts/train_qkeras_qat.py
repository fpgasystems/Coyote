#!/usr/bin/env python3
"""Train/evaluate QKeras QAT folds for configured hls4ml candidates."""

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
    DEFAULT_QAT_TAGS,
    QATTrainConfig,
    aggregate_qkeras_metrics,
    select_best_quantizer,
    train_qkeras_fold,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", default="cnn_small_hls_opt_img512")
    parser.add_argument("--quantizer-tag", default="w6_a8",
                        help=f"One of {DEFAULT_QAT_TAGS}, or 'sweep'")
    parser.add_argument("--fold", type=int, default=0,
                        help="Fold to train when --all-folds is not set")
    parser.add_argument("--all-folds", action="store_true",
                        help="Train all folds configured for the candidate")
    parser.add_argument("--epochs", type=int, default=300)
    parser.add_argument("--batch-size", type=int, default=8)
    parser.add_argument("--lr", type=float, default=1e-4)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--no-augment", action="store_true")
    parser.add_argument("--flip-h-prob", type=float, default=0.5)
    parser.add_argument("--flip-v-prob", type=float, default=0.5)
    parser.add_argument("--crop-scale-min", type=float, default=1.0)
    parser.add_argument("--translate", type=float, default=0.0)
    parser.add_argument("--no-cache-data", action="store_true")
    parser.add_argument("--max-train-samples", type=int, default=None,
                        help="Debug/smoke limit; leave unset for full folds")
    parser.add_argument("--max-val-samples", type=int, default=None,
                        help="Debug/smoke limit; leave unset for full folds")
    parser.add_argument("--output-root", type=Path, default=None)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    candidate = get_candidate(args.candidate)
    quantizer_tags = list(DEFAULT_QAT_TAGS) if args.quantizer_tag == "sweep" else [args.quantizer_tag]
    folds = list(candidate.folds) if args.all_folds else [args.fold]

    fold0_results: list[tuple[str, dict]] = []
    for quantizer_tag in quantizer_tags:
        for fold in folds:
            cfg = QATTrainConfig(
                candidate_name=candidate.name,
                quantizer_tag=quantizer_tag,
                fold=fold,
                epochs=args.epochs,
                batch_size=args.batch_size,
                lr=args.lr,
                seed=args.seed,
                augment=not args.no_augment,
                flip_h_prob=args.flip_h_prob,
                flip_v_prob=args.flip_v_prob,
                crop_scale_min=args.crop_scale_min,
                translate=args.translate,
                cache_data=not args.no_cache_data,
                max_train_samples=args.max_train_samples,
                max_val_samples=args.max_val_samples,
            )
            print(f"[qat] train candidate={candidate.name} quantizer={quantizer_tag} fold={fold}")
            result = train_qkeras_fold(candidate, cfg, output_root=args.output_root)
            print(
                f"[qat] done quantizer={quantizer_tag} fold={fold} "
                f"accuracy={result['metrics']['accuracy']:.4f} "
                f"pr_auc={result['metrics']['pr_auc']:.4f} out={result['out_dir']}"
            )
            if fold == 0:
                fold0_results.append((quantizer_tag, result["metrics"]))

        if args.all_folds and args.max_train_samples is None and args.max_val_samples is None:
            metrics = aggregate_qkeras_metrics(candidate, quantizer_tag, output_root=args.output_root)
            print(
                f"[qat] pooled quantizer={quantizer_tag} "
                f"accuracy={metrics['accuracy']:.4f} pr_auc={metrics['pr_auc']:.4f}"
            )

    if len(fold0_results) > 1:
        best_tag, best_metrics = select_best_quantizer(fold0_results)
        print(
            f"[qat] selected fold0 quantizer={best_tag} "
            f"accuracy={best_metrics['accuracy']:.4f} "
            f"pr_auc={best_metrics['pr_auc']:.4f} "
            f"bce={best_metrics['bce_loss']:.4f}"
        )


if __name__ == "__main__":
    main()
