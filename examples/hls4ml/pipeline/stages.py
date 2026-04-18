"""Stage-ledger and stage-comparison helpers."""

from __future__ import annotations

import csv
import json
from pathlib import Path
from statistics import mean
from typing import Iterable, List

from .paths import ARTIFACTS_ROOT


def _iter_stage_csvs(artifact_root: Path, candidate: str | None = None, stage: str | None = None) -> Iterable[Path]:
    root = artifact_root / candidate if candidate else artifact_root
    if not root.exists():
        return []

    pattern = "*/*/per_sample.csv" if candidate else "*/*/*/per_sample.csv"
    paths = sorted(root.glob(pattern))
    if stage is None:
        return [path for path in paths if path.parent.name != "pooled"]
    return [path for path in paths if path.parent.name != "pooled" and path.parent.parent.name == stage]


def _augment_stage_row(csv_path: Path, row: dict) -> dict:
    fold_dir = csv_path.parent.name
    stage_dir = csv_path.parent.parent.name
    candidate_dir = csv_path.parent.parent.parent.name
    augmented = dict(row)
    augmented["candidate"] = candidate_dir
    augmented["stage"] = stage_dir
    augmented["fold"] = int(fold_dir.removeprefix("fold_"))
    return augmented


def collect_stage_rows(
    artifact_root: Path = ARTIFACTS_ROOT,
    candidate: str | None = None,
    stage: str | None = None,
) -> List[dict]:
    rows: List[dict] = []
    for csv_path in _iter_stage_csvs(artifact_root=artifact_root, candidate=candidate, stage=stage):
        with csv_path.open(newline="") as handle:
            reader = csv.DictReader(handle)
            for row in reader:
                rows.append(_augment_stage_row(csv_path, row))
    return rows


def write_stage_ledger(
    output_path: Path,
    artifact_root: Path = ARTIFACTS_ROOT,
    candidate: str | None = None,
    stage: str | None = None,
) -> Path:
    rows = collect_stage_rows(artifact_root=artifact_root, candidate=candidate, stage=stage)
    if not rows:
        raise FileNotFoundError(f"No per_sample.csv files found under {artifact_root}")

    fieldnames = sorted({key for row in rows for key in row.keys()})
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    return output_path


def _load_stage_rows(candidate_root: Path, stage_name: str) -> dict:
    stage_root = candidate_root / stage_name
    if not stage_root.exists():
        raise FileNotFoundError(f"Missing stage root: {stage_root}")

    rows = {}
    for csv_path in sorted(stage_root.glob("fold_*/per_sample.csv")):
        fold = int(csv_path.parent.name.removeprefix("fold_"))
        with csv_path.open(newline="") as handle:
            reader = csv.DictReader(handle)
            for row in reader:
                rows[(fold, row["sample_id"])] = row
    return rows


def compare_stage_predictions(
    candidate: str,
    left_stage: str,
    right_stage: str,
    artifact_root: Path = ARTIFACTS_ROOT,
    output_path: Path | None = None,
) -> tuple[dict, List[dict]]:
    candidate_root = artifact_root / candidate
    left_rows = _load_stage_rows(candidate_root, left_stage)
    right_rows = _load_stage_rows(candidate_root, right_stage)

    common_keys = sorted(set(left_rows) & set(right_rows))
    if not common_keys:
        raise ValueError(f"No overlapping samples between stages {left_stage} and {right_stage}")

    comparison_rows = []
    abs_prob_deltas = []
    abs_logit_deltas = []
    pred_changes = 0
    correctness_changes = 0

    for fold, sample_id in common_keys:
        left = left_rows[(fold, sample_id)]
        right = right_rows[(fold, sample_id)]
        left_prob = float(left["probability"])
        right_prob = float(right["probability"])
        left_logit = float(left["logit"])
        right_logit = float(right["logit"])
        left_pred = int(left["predicted_label"])
        right_pred = int(right["predicted_label"])
        left_correct = str(left["correct"]).lower() == "true"
        right_correct = str(right["correct"]).lower() == "true"
        abs_prob_delta = abs(right_prob - left_prob)
        abs_logit_delta = abs(right_logit - left_logit)

        abs_prob_deltas.append(abs_prob_delta)
        abs_logit_deltas.append(abs_logit_delta)
        pred_changes += int(left_pred != right_pred)
        correctness_changes += int(left_correct != right_correct)

        comparison_rows.append(
            {
                "candidate": candidate,
                "fold": fold,
                "sample_id": sample_id,
                "class_label": left["class_label"],
                "left_stage": left_stage,
                "right_stage": right_stage,
                "left_logit": left["logit"],
                "right_logit": right["logit"],
                "logit_delta": right_logit - left_logit,
                "abs_logit_delta": abs_logit_delta,
                "left_probability": left["probability"],
                "right_probability": right["probability"],
                "probability_delta": right_prob - left_prob,
                "abs_probability_delta": abs_prob_delta,
                "left_predicted_label": left["predicted_label"],
                "right_predicted_label": right["predicted_label"],
                "prediction_changed": int(left_pred != right_pred),
                "left_correct": left["correct"],
                "right_correct": right["correct"],
                "correctness_changed": int(left_correct != right_correct),
            }
        )

    summary = {
        "candidate": candidate,
        "left_stage": left_stage,
        "right_stage": right_stage,
        "samples_compared": len(common_keys),
        "mean_abs_probability_delta": mean(abs_prob_deltas),
        "max_abs_probability_delta": max(abs_prob_deltas),
        "mean_abs_logit_delta": mean(abs_logit_deltas),
        "max_abs_logit_delta": max(abs_logit_deltas),
        "prediction_changes": pred_changes,
        "correctness_changes": correctness_changes,
    }

    if output_path is not None:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        fieldnames = list(comparison_rows[0].keys())
        with output_path.open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(comparison_rows)
        output_path.with_suffix(".summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True))

    return summary, comparison_rows
