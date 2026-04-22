#!/usr/bin/env python3
"""Evaluate QKeras-vs-hls4ml parity as classifier outputs.

This consumes the existing qkeras parity CSVs, treats the Keras logits and HLS
logits as two classifier stages, and writes per-fold plus pooled evaluation
artifacts for both.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import sys
from pathlib import Path

import numpy as np

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline import get_candidate  # noqa: E402
from pipeline.paths import ensure_ml_baseline_on_path  # noqa: E402

ensure_ml_baseline_on_path()

from train import (  # noqa: E402
    VAL_METRIC_SUFFIXES,
    compute_metrics_from_outputs,
    save_checkpoint_plots,
    save_evaluation_dashboard,
    save_kfold_evaluation_artifacts,
    save_kfold_summary,
)


STAGES = {
    "original": "keras_logit",
    "hls": "hls_logit",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", default="cnn_small_hls_opt_img512")
    parser.add_argument("--quantizer-tag", required=True)
    parser.add_argument("--fold", type=int, default=None)
    parser.add_argument("--folds", default=None,
                        help="Space-separated fold list; overrides candidate folds unless --fold is set")
    parser.add_argument("--parity-root", type=Path, default=None)
    parser.add_argument("--output-root", type=Path, default=None)
    return parser.parse_args()


def sigmoid(logits: np.ndarray) -> np.ndarray:
    logits = np.asarray(logits, dtype=np.float64)
    out = np.empty_like(logits, dtype=np.float64)
    pos = logits >= 0
    out[pos] = 1.0 / (1.0 + np.exp(-logits[pos]))
    exp_x = np.exp(logits[~pos])
    out[~pos] = exp_x / (1.0 + exp_x)
    return out


def binary_log_loss(label: int, prob: float) -> float:
    clipped = min(max(float(prob), 1e-7), 1.0 - 1e-7)
    if int(label) == 1:
        return -math.log(clipped)
    return -math.log(1.0 - clipped)


def metrics_to_jsonable(value):
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, list):
        return [metrics_to_jsonable(v) for v in value]
    if isinstance(value, dict):
        return {k: metrics_to_jsonable(v) for k, v in value.items()}
    if isinstance(value, (np.floating, np.integer)):
        return value.item()
    return value


def public_metrics(metrics: dict) -> dict:
    return {
        key: metrics_to_jsonable(value)
        for key, value in metrics.items()
        if key not in {"labels", "probs", "preds", "reliability_bins"}
    }


def read_csv(path: Path) -> list[dict]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        raise ValueError(f"No rows to write to {path}")
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def load_metadata(candidate_name: str, fold: int) -> list[dict]:
    path = EXAMPLE_ROOT / "artifacts" / candidate_name / "exports" / f"fold_{fold}" / "metadata.csv"
    if not path.exists():
        return []
    return read_csv(path)


def rows_for_stage(parity_rows: list[dict], metadata_rows: list[dict], logit_key: str) -> list[dict]:
    rows = []
    for row in parity_rows:
        idx = int(row["idx"])
        label = int(row["label"])
        logit = float(row[logit_key])
        prob = float(sigmoid(np.asarray([logit]))[0])
        pred = int(prob >= 0.5)
        sample_loss = binary_log_loss(label, prob)
        meta = metadata_rows[idx] if idx < len(metadata_rows) else {}
        rows.append(
            {
                "sample_index": idx,
                "sample_id": meta.get("sample_id", ""),
                "app_name": meta.get("app_name", ""),
                "class_label": label,
                "class_name": meta.get("class_name", "standalone" if label else "benign"),
                "ro_count": meta.get("ro_count", ""),
                "bitstream_path": meta.get("bitstream_path", ""),
                "logit": f"{logit:.9f}",
                "probability": f"{prob:.9f}",
                "predicted_label": pred,
                "correct": pred == label,
                "per_sample_bce_loss": f"{sample_loss:.9f}",
                "per_sample_log_loss": f"{sample_loss:.9f}",
            }
        )
    return rows


def metrics_from_rows(rows: list[dict]) -> dict:
    labels = np.asarray([int(row["class_label"]) for row in rows], dtype=np.float32)
    probs = np.asarray([float(row["probability"]) for row in rows], dtype=np.float32)
    losses = np.asarray([float(row["per_sample_bce_loss"]) for row in rows], dtype=np.float32)
    return compute_metrics_from_outputs(float(np.mean(losses)), labels, probs)


def history_from_metrics(metrics: dict) -> dict[str, list[float]]:
    history = {"train_loss": [float(metrics["bce_loss"])]}
    for suffix in VAL_METRIC_SUFFIXES:
        history[f"val_{suffix}"] = [float(metrics[suffix])]
    return history


def write_stage_artifacts(
    out_dir: Path,
    rows: list[dict],
    candidate_name: str,
    quantizer_tag: str,
    stage: str,
    fold: int | str,
) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    write_csv(out_dir / "per_sample.csv", rows)
    metrics = metrics_from_rows(rows)
    (out_dir / "metrics_summary.json").write_text(
        json.dumps(public_metrics(metrics), indent=2, sort_keys=True)
    )
    split_info = (
        f"Candidate: {candidate_name}  |  Quantizer: {quantizer_tag}  |  "
        f"Stage: {stage}  |  Fold: {fold}  |  Samples: {len(rows)}"
    )
    run_params = {
        "parity_evaluation": True,
        "threshold": 0.5,
        "logit_source": STAGES[stage],
    }
    save_checkpoint_plots(
        str(out_dir),
        "final",
        canonical_metrics=metrics,
        aug_metrics=None,
        split_info=split_info,
        run_params=run_params,
    )
    save_evaluation_dashboard(
        history_from_metrics(metrics),
        str(out_dir),
        split_info=split_info,
        run_params=run_params,
        final_epoch=1,
    )
    return metrics


def comparison_row(fold: int | str, original_metrics: dict, hls_metrics: dict, parity_rows: list[dict]) -> dict:
    sign_mismatches = sum(
        (float(row["keras_logit"]) >= 0.0) != (float(row["hls_logit"]) >= 0.0)
        for row in parity_rows
    )
    abs_err = np.asarray([float(row["abs_err"]) for row in parity_rows], dtype=np.float64)
    return {
        "fold": fold,
        "n": len(parity_rows),
        "original_accuracy": f"{original_metrics['accuracy']:.9f}",
        "hls_accuracy": f"{hls_metrics['accuracy']:.9f}",
        "accuracy_delta_hls_minus_original": f"{hls_metrics['accuracy'] - original_metrics['accuracy']:.9f}",
        "original_balanced_accuracy": f"{original_metrics['balanced_accuracy']:.9f}",
        "hls_balanced_accuracy": f"{hls_metrics['balanced_accuracy']:.9f}",
        "original_pr_auc": f"{original_metrics['pr_auc']:.9f}",
        "hls_pr_auc": f"{hls_metrics['pr_auc']:.9f}",
        "original_bce_loss": f"{original_metrics['bce_loss']:.9f}",
        "hls_bce_loss": f"{hls_metrics['bce_loss']:.9f}",
        "logit_mae": f"{float(abs_err.mean()):.9f}",
        "logit_max_abs": f"{float(abs_err.max()):.9f}",
        "sign_mismatches": int(sign_mismatches),
    }


def write_pooled_stage(
    root: Path,
    candidate_name: str,
    quantizer_tag: str,
    stage: str,
    fold_payloads: list[dict],
) -> dict:
    stage_root = root / stage
    pooled_rows = []
    for payload in fold_payloads:
        fold = payload["fold"]
        for row in payload[f"{stage}_rows"]:
            pooled = dict(row)
            pooled["fold"] = fold
            pooled_rows.append(pooled)
    metrics = write_stage_artifacts(
        stage_root,
        pooled_rows,
        candidate_name,
        quantizer_tag,
        stage,
        "pooled",
    )
    fold_results = [
        {
            "fold_label": f"fold_{payload['fold']}",
            "history": history_from_metrics(payload[f"{stage}_metrics"]),
            "final_metrics": payload[f"{stage}_metrics"],
            "final_aug_metrics": None,
            "final_epoch": 1,
        }
        for payload in fold_payloads
    ]
    split_info = (
        f"Candidate: {candidate_name}  |  Quantizer: {quantizer_tag}  |  "
        f"Stage: {stage}  |  Folds: {len(fold_payloads)}"
    )
    run_params = {
        "parity_evaluation": True,
        "threshold": 0.5,
        "logit_source": STAGES[stage],
    }
    save_kfold_evaluation_artifacts(
        fold_results,
        str(stage_root),
        split_info=split_info,
        run_params=run_params,
    )
    save_kfold_summary(fold_results, str(stage_root), n_folds=len(fold_results))
    return metrics


def main() -> None:
    args = parse_args()
    candidate = get_candidate(args.candidate)
    parity_root = args.parity_root or (
        EXAMPLE_ROOT / "artifacts" / candidate.name / "hls" / f"qkeras_parity_{args.quantizer_tag}"
    )
    output_root = args.output_root or (
        EXAMPLE_ROOT / "artifacts" / candidate.name / "hls" / f"qkeras_parity_eval_{args.quantizer_tag}"
    )
    if args.fold is not None:
        folds = [args.fold]
    elif args.folds:
        folds = [int(x) for x in args.folds.split()]
    else:
        folds = list(candidate.folds)

    output_root.mkdir(parents=True, exist_ok=True)
    fold_payloads = []
    comparison_rows = []

    for fold in folds:
        parity_csv = parity_root / f"fold_{fold}" / "parity.csv"
        if not parity_csv.exists():
            print(f"[parity-eval] skip fold={fold}: missing {parity_csv}")
            continue
        parity_rows = read_csv(parity_csv)
        metadata_rows = load_metadata(candidate.name, fold)
        payload = {"fold": fold}
        for stage, logit_key in STAGES.items():
            rows = rows_for_stage(parity_rows, metadata_rows, logit_key)
            metrics = write_stage_artifacts(
                output_root / f"fold_{fold}" / stage,
                rows,
                candidate.name,
                args.quantizer_tag,
                stage,
                fold,
            )
            payload[f"{stage}_rows"] = rows
            payload[f"{stage}_metrics"] = metrics
        comparison_rows.append(
            comparison_row(
                fold,
                payload["original_metrics"],
                payload["hls_metrics"],
                parity_rows,
            )
        )
        fold_payloads.append(payload)
        print(
            f"[parity-eval] quantizer={args.quantizer_tag} fold={fold} "
            f"original_acc={payload['original_metrics']['accuracy']:.4f} "
            f"hls_acc={payload['hls_metrics']['accuracy']:.4f}"
        )

    if not fold_payloads:
        raise SystemExit(f"No parity folds found under {parity_root}")

    original_pooled = write_pooled_stage(output_root, candidate.name, args.quantizer_tag, "original", fold_payloads)
    hls_pooled = write_pooled_stage(output_root, candidate.name, args.quantizer_tag, "hls", fold_payloads)
    comparison_rows.append(
        comparison_row(
            "pooled",
            original_pooled,
            hls_pooled,
            [
                row
                for payload in fold_payloads
                for row in read_csv(parity_root / f"fold_{payload['fold']}" / "parity.csv")
            ],
        )
    )
    write_csv(output_root / "comparison_summary.csv", comparison_rows)
    (output_root / "manifest.json").write_text(
        json.dumps(
            {
                "candidate": candidate.name,
                "quantizer_tag": args.quantizer_tag,
                "parity_root": str(parity_root),
                "output_root": str(output_root),
                "folds": [payload["fold"] for payload in fold_payloads],
                "stages": STAGES,
            },
            indent=2,
            sort_keys=True,
        )
    )
    print(f"[parity-eval] wrote {output_root}")
    print(
        f"[parity-eval] pooled quantizer={args.quantizer_tag} "
        f"original_acc={original_pooled['accuracy']:.4f} hls_acc={hls_pooled['accuracy']:.4f}"
    )


if __name__ == "__main__":
    main()
