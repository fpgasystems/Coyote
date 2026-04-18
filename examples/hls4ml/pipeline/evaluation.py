"""Evaluation and export helpers for the hls4ml workspace."""

from __future__ import annotations

import csv
import json
import shutil
from dataclasses import asdict
from pathlib import Path
from typing import Dict, Iterable, List, Sequence

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader

from .candidates import CandidateConfig
from .paths import ARTIFACTS_ROOT, ensure_ml_baseline_on_path

ensure_ml_baseline_on_path()

from dataset import BitstreamDataset, load_manifest  # noqa: E402
from model import build_model  # noqa: E402
from train import (  # noqa: E402
    compute_metrics_from_outputs,
    validate_per_sample,
    write_per_sample_csv,
)


SCALAR_METRIC_KEYS = [
    "bce_loss",
    "log_loss",
    "benign_log_loss",
    "standalone_log_loss",
    "brier_score",
    "accuracy",
    "balanced_accuracy",
    "precision",
    "recall",
    "f1",
    "mcc",
    "ece",
    "roc_auc",
    "pr_auc",
    "optimal_threshold",
    "optimal_accuracy",
    "optimal_f1",
    "benign_mean_score",
    "standalone_mean_score",
]


def resolve_device(device_arg: str | None) -> torch.device:
    if device_arg:
        return torch.device(device_arg)
    return torch.device("cuda" if torch.cuda.is_available() else "cpu")


def load_checkpoint(model: nn.Module, checkpoint_path: Path, device: torch.device) -> None:
    try:
        state = torch.load(checkpoint_path, map_location=device, weights_only=True)
    except TypeError:
        state = torch.load(checkpoint_path, map_location=device)
    model.load_state_dict(state)


def _fold_dir(candidate: CandidateConfig, fold: int) -> Path:
    return candidate.run_dir / f"fold_{fold}"


def _validation_csv(candidate: CandidateConfig, fold: int, checkpoint_name: str) -> Path:
    return _fold_dir(candidate, fold) / f"{checkpoint_name}_canonical_val_per_sample.csv"


def sample_ids_for_fold(
    candidate: CandidateConfig,
    fold: int,
    checkpoint_name: str = "final",
) -> List[str]:
    path = _validation_csv(candidate, fold, checkpoint_name)
    with path.open(newline="") as handle:
        return [row["sample_id"] for row in csv.DictReader(handle)]


def manifest_index(candidate: CandidateConfig) -> Dict[str, dict]:
    samples = load_manifest(min_ro=candidate.min_ro)
    return {row["sample_id"]: row for row in samples}


def dataset_for_fold(
    candidate: CandidateConfig,
    fold: int,
    checkpoint_name: str = "final",
) -> BitstreamDataset:
    wanted_ids = sample_ids_for_fold(candidate, fold, checkpoint_name=checkpoint_name)
    sample_map = manifest_index(candidate)
    selected = [sample_map[sample_id] for sample_id in wanted_ids]
    return BitstreamDataset(
        selected,
        img_size=candidate.img_size,
        sequence_length=candidate.sequence_length,
        representation=candidate.representation,
        return_index=True,
    )


def build_loader(dataset: BitstreamDataset, batch_size: int, num_workers: int) -> DataLoader:
    return DataLoader(
        dataset,
        batch_size=batch_size,
        shuffle=False,
        num_workers=num_workers,
        pin_memory=torch.cuda.is_available(),
    )


def metrics_summary_dict(metrics: dict) -> dict:
    summary = {}
    for key in SCALAR_METRIC_KEYS:
        value = metrics.get(key)
        if isinstance(value, np.generic):
            value = value.item()
        summary[key] = value
    cm = metrics.get("confusion_matrix")
    if cm is not None:
        summary["confusion_matrix"] = np.asarray(cm).tolist()
    return summary


def write_metrics_summary(path: Path, metrics: dict, extra: dict | None = None) -> None:
    payload = metrics_summary_dict(metrics)
    if extra:
        payload.update(extra)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True))


def _labels_probs_from_results(results: Sequence[dict], dataset: BitstreamDataset) -> tuple[np.ndarray, np.ndarray]:
    labels = []
    probs = []
    losses = []
    for row in results:
        meta = dataset.get_metadata(row["dataset_index"])
        labels.append(float(meta["class_label"]))
        probs.append(float(row["probability"]))
        losses.append(float(row["per_sample_bce_loss"]))
    all_labels = np.asarray(labels, dtype=np.float32)
    all_probs = np.asarray(probs, dtype=np.float32)
    total_loss = float(np.mean(losses)) if losses else float("nan")
    return total_loss, all_labels, all_probs


def evaluate_candidate_fold(
    candidate: CandidateConfig,
    fold: int,
    stage_name: str = "pytorch_float",
    checkpoint_name: str = "final",
    batch_size: int = 8,
    num_workers: int = 0,
    device_arg: str | None = None,
    output_root: Path | None = None,
) -> dict:
    device = resolve_device(device_arg)
    model = build_model(candidate.model)
    model.to(device)
    checkpoint_path = _fold_dir(candidate, fold) / f"{checkpoint_name}_model.pt"
    load_checkpoint(model, checkpoint_path, device)

    dataset = dataset_for_fold(candidate, fold, checkpoint_name=checkpoint_name)
    loader = build_loader(dataset, batch_size=batch_size, num_workers=num_workers)
    results = validate_per_sample(model, loader, device)

    total_loss, all_labels, all_probs = _labels_probs_from_results(results, dataset)
    metrics = compute_metrics_from_outputs(total_loss, all_labels, all_probs)

    stage_dir = (output_root or ARTIFACTS_ROOT) / candidate.name / stage_name / f"fold_{fold}"
    stage_dir.mkdir(parents=True, exist_ok=True)

    csv_path = stage_dir / "per_sample.csv"
    write_per_sample_csv(results, dataset, str(csv_path))
    write_metrics_summary(
        stage_dir / "metrics_summary.json",
        metrics,
        extra={
            "candidate": candidate.name,
            "model": candidate.model,
            "fold": fold,
            "stage": stage_name,
            "checkpoint": checkpoint_name,
            "checkpoint_path": str(checkpoint_path),
        },
    )

    return {"metrics": metrics, "stage_dir": stage_dir, "csv_path": csv_path}


def _read_per_sample_csv(path: Path) -> List[dict]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def _aggregate_rows(rows: Iterable[dict]) -> dict:
    labels = np.asarray([int(row["class_label"]) for row in rows], dtype=np.float32)
    probs = np.asarray([float(row["probability"]) for row in rows], dtype=np.float32)
    losses = np.asarray([float(row["per_sample_bce_loss"]) for row in rows], dtype=np.float32)
    return compute_metrics_from_outputs(float(np.mean(losses)), labels, probs)


def aggregate_candidate_metrics(
    candidate: CandidateConfig,
    stage_name: str = "pytorch_float",
    output_root: Path | None = None,
) -> dict:
    root = output_root or ARTIFACTS_ROOT
    stage_root = root / candidate.name / stage_name
    pooled_dir = stage_root / "pooled"
    pooled_dir.mkdir(parents=True, exist_ok=True)

    all_rows: List[dict] = []
    for fold in candidate.folds:
        csv_path = stage_root / f"fold_{fold}" / "per_sample.csv"
        if not csv_path.exists():
            raise FileNotFoundError(f"Missing fold artifact: {csv_path}")
        all_rows.extend(_read_per_sample_csv(csv_path))

    fieldnames = list(all_rows[0].keys())
    with (pooled_dir / "per_sample.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(all_rows)

    metrics = _aggregate_rows(all_rows)
    write_metrics_summary(
        pooled_dir / "metrics_summary.json",
        metrics,
        extra={
            "candidate": candidate.name,
            "model": candidate.model,
            "stage": stage_name,
            "folds": list(candidate.folds),
        },
    )
    return metrics


def export_calibration_bundle(
    candidate: CandidateConfig,
    fold: int,
    output_dir: Path,
    max_samples: int = 16,
    checkpoint_name: str = "final",
) -> Path:
    dataset = dataset_for_fold(candidate, fold, checkpoint_name=checkpoint_name)
    output_dir.mkdir(parents=True, exist_ok=True)
    blob_dir = output_dir / "sample_blobs"
    blob_dir.mkdir(parents=True, exist_ok=True)

    raw_uint8 = []
    inputs_nchw = []
    inputs_nhwc = []
    labels = []
    meta_rows = []

    limit = min(max_samples, len(dataset))
    for idx in range(limit):
        tensor = dataset.get_raw_tensor(idx)
        meta = dataset.get_metadata(idx)
        image = dataset.get_raw_array(idx)
        flat = image.reshape(-1).astype(np.uint8)

        blob_name = f"{idx:03d}_{meta['sample_id']}.bin"
        (blob_dir / blob_name).write_bytes(flat.tobytes())

        nchw = tensor.numpy()
        nhwc = np.transpose(nchw, (1, 2, 0))
        raw_uint8.append(flat)
        inputs_nchw.append(nchw)
        inputs_nhwc.append(nhwc)
        labels.append(int(meta["class_label"]))
        meta_rows.append(
            {
                "index": idx,
                "sample_id": meta["sample_id"],
                "class_label": meta["class_label"],
                "class_name": meta.get("class_name", ""),
                "ro_count": meta.get("ro_count", ""),
                "bitstream_path": meta.get("bitstream_path", ""),
                "blob_path": str(blob_dir / blob_name),
            }
        )

    np.save(output_dir / "inputs_uint8.npy", np.stack(raw_uint8))
    np.save(output_dir / "inputs_nchw.npy", np.stack(inputs_nchw))
    np.save(output_dir / "inputs_nhwc.npy", np.stack(inputs_nhwc))
    np.save(output_dir / "labels.npy", np.asarray(labels, dtype=np.int64))

    with (output_dir / "metadata.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(meta_rows[0].keys()))
        writer.writeheader()
        writer.writerows(meta_rows)

    return output_dir
