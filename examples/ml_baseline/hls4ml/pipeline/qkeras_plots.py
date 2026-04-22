"""Reuse parent train.py plotting utilities for QKeras QAT artifacts."""

from __future__ import annotations

import csv
import json
from pathlib import Path
from typing import Sequence

import numpy as np

from .candidates import CandidateConfig
from .paths import ensure_ml_baseline_on_path

ensure_ml_baseline_on_path()

import matplotlib  # noqa: E402

matplotlib.use("Agg")

from train import (  # noqa: E402
    compute_metrics_from_outputs,
    save_checkpoint_plots,
    save_evaluation_dashboard,
    save_kfold_curves,
    save_kfold_evaluation_artifacts,
    save_kfold_summary,
    save_training_curves,
)

_HISTORY_NONNUMERIC = {"epoch"}


def _to_float(value) -> float:
    if value is None or value == "" or value == "nan":
        return float("nan")
    try:
        return float(value)
    except (TypeError, ValueError):
        return float("nan")


def history_rows_to_columns(rows: Sequence[dict]) -> dict[str, list[float]]:
    cols: dict[str, list[float]] = {}
    for row in rows:
        for key, value in row.items():
            if key in _HISTORY_NONNUMERIC:
                continue
            cols.setdefault(key, []).append(_to_float(value))
    return cols


def load_history_columns(fold_dir: Path) -> dict[str, list[float]]:
    with (Path(fold_dir) / "history.csv").open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    return history_rows_to_columns(rows)


def _metrics_from_per_sample_rows(rows: Sequence[dict]) -> dict:
    labels = np.asarray([int(row["class_label"]) for row in rows], dtype=np.float32)
    probs = np.asarray([float(row["probability"]) for row in rows], dtype=np.float32)
    losses = np.asarray([float(row["per_sample_bce_loss"]) for row in rows], dtype=np.float32)
    return compute_metrics_from_outputs(float(np.mean(losses)), labels, probs)


def load_final_metrics(fold_dir: Path, filename: str = "per_sample.csv") -> dict | None:
    path = Path(fold_dir) / filename
    if not path.exists():
        return None
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        return None
    return _metrics_from_per_sample_rows(rows)


def load_training_manifest(fold_dir: Path) -> dict:
    path = Path(fold_dir) / "training_manifest.json"
    if not path.exists():
        return {}
    return json.loads(path.read_text())


def build_run_params(training_manifest: dict) -> dict:
    cfg = training_manifest.get("train_config", {}) or {}
    quantizer = training_manifest.get("quantizer", {}) or {}
    params = {
        "quantizer": quantizer.get("tag", ""),
        "weight_bits": quantizer.get("weight_bits", ""),
        "activation_bits": quantizer.get("activation_bits", ""),
        "epochs": cfg.get("epochs", ""),
        "batch_size": cfg.get("batch_size", ""),
        "lr": cfg.get("lr", ""),
        "seed": cfg.get("seed", ""),
        "augment": cfg.get("augment", ""),
    }
    return {k: v for k, v in params.items() if v not in ("", None)}


def build_split_info(
    candidate_name: str,
    fold: int | str,
    n_train: int | str,
    n_val: int | str,
) -> str:
    return (
        f"Candidate: {candidate_name}  |  Fold: {fold}  |  "
        f"Train: {n_train}  |  Val: {n_val}"
    )


def build_split_info_from_manifest(training_manifest: dict) -> str:
    cfg = training_manifest.get("train_config", {}) or {}
    return build_split_info(
        training_manifest.get("candidate", ""),
        cfg.get("fold", ""),
        training_manifest.get("n_train", ""),
        training_manifest.get("n_val", ""),
    )


def write_fold_plots(
    fold_dir: Path,
    history_columns: dict,
    final_metrics: dict,
    aug_metrics: dict | None = None,
    split_info: str | None = None,
    run_params: dict | None = None,
    final_epoch: int | None = None,
) -> None:
    fold_dir = Path(fold_dir)
    if final_epoch is None:
        final_epoch = len(history_columns.get("train_loss", [])) or None
    save_evaluation_dashboard(
        history_columns,
        str(fold_dir),
        split_info=split_info,
        run_params=run_params,
        final_epoch=final_epoch,
    )
    save_training_curves(
        history_columns,
        str(fold_dir),
        split_info=split_info,
        run_params=run_params,
    )
    if final_metrics is not None:
        save_checkpoint_plots(
            str(fold_dir),
            "final",
            canonical_metrics=final_metrics,
            aug_metrics=aug_metrics,
            split_info=split_info,
            run_params=run_params,
        )


def write_fold_plots_from_disk(fold_dir: Path) -> None:
    fold_dir = Path(fold_dir)
    history_columns = load_history_columns(fold_dir)
    final_metrics = load_final_metrics(fold_dir, "per_sample.csv")
    aug_metrics = load_final_metrics(fold_dir, "augmented_per_sample.csv")
    manifest = load_training_manifest(fold_dir)
    split_info = build_split_info_from_manifest(manifest) if manifest else None
    run_params = build_run_params(manifest) if manifest else None
    cfg = manifest.get("train_config", {}) if manifest else {}
    final_epoch = cfg.get("epochs") or None
    write_fold_plots(
        fold_dir,
        history_columns,
        final_metrics,
        aug_metrics,
        split_info=split_info,
        run_params=run_params,
        final_epoch=final_epoch,
    )


def fold_result_from_disk(fold_dir: Path) -> dict:
    fold_dir = Path(fold_dir)
    history_columns = load_history_columns(fold_dir)
    final_metrics = load_final_metrics(fold_dir, "per_sample.csv")
    aug_metrics = load_final_metrics(fold_dir, "augmented_per_sample.csv")
    manifest = load_training_manifest(fold_dir)
    cfg = manifest.get("train_config", {}) if manifest else {}
    fold_idx = cfg.get("fold", fold_dir.name.replace("fold_", ""))
    return {
        "fold_label": f"fold_{fold_idx}",
        "history": history_columns,
        "final_metrics": final_metrics,
        "final_aug_metrics": aug_metrics,
        "final_epoch": cfg.get("epochs") or len(history_columns.get("train_loss", [])),
    }


def write_kfold_plots(
    run_dir: Path,
    fold_results: list[dict],
    split_info: str | None = None,
    run_params: dict | None = None,
) -> None:
    run_dir = Path(run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    save_kfold_curves(
        fold_results,
        str(run_dir),
        split_info=split_info,
        run_params=run_params,
    )
    save_kfold_evaluation_artifacts(
        fold_results,
        str(run_dir),
        split_info=split_info,
        run_params=run_params,
    )
    save_kfold_summary(fold_results, str(run_dir), n_folds=len(fold_results))


def write_kfold_plots_from_disk(
    candidate: CandidateConfig,
    quantizer_tag: str,
    run_dir: Path,
    fold_dirs: Sequence[Path],
) -> None:
    fold_results = [fold_result_from_disk(fd) for fd in fold_dirs]
    manifest = load_training_manifest(Path(fold_dirs[0])) if fold_dirs else {}
    cfg = manifest.get("train_config", {}) if manifest else {}
    run_params = build_run_params(manifest) if manifest else None
    split_info = (
        f"Candidate: {candidate.name}  |  Quantizer: {quantizer_tag}  |  "
        f"Folds: {len(fold_results)}  |  Epochs: {cfg.get('epochs', '')}"
    )
    write_kfold_plots(run_dir, fold_results, split_info=split_info, run_params=run_params)
