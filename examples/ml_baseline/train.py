"""Training script for grayscale ResNet-18 binary classifier.

Usage:
    python train.py                    # default 50 epochs, no train augmentation
    python train.py --epochs 1         # quick smoke test
    python train.py --batch-size 4     # reduce if OOM
    python train.py --lr 1e-3          # override learning rate
    python train.py --augment          # enable train augmentation
"""

import argparse
import csv
import os
import time
import textwrap

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import torch
import torch.nn as nn
import torchvision.transforms as T
from sklearn.metrics import (
    accuracy_score,
    brier_score_loss,
    confusion_matrix,
    f1_score,
    log_loss,
    precision_score,
    recall_score,
    roc_auc_score,
    roc_curve,
)
from sklearn.model_selection import train_test_split, StratifiedKFold
from torch.utils.data import DataLoader

import torchvision.transforms.functional as TF

from dataset import (
    BitstreamDataset, CachedTensorDataset,
    load_manifest, bitstream_to_image, IMG_SIZE,
)
from model import build_model, MODEL_CHOICES
from visualize import save_hardest_samples, save_augmentation_grid, save_augmented_val_sanity_check

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "runs")


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--model", type=str, default="resnet18", choices=MODEL_CHOICES,
                   help="Model architecture: resnet18, cnn_a, cnn_b")
    p.add_argument("--epochs", type=int, default=50)
    p.add_argument("--batch-size", type=int, default=8)
    p.add_argument("--lr", type=float, default=1e-4)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--val-split", type=float, default=0.2)
    p.add_argument("--min-ro", type=int, default=4000)
    p.add_argument("--num-workers", type=int, default=4)
    p.add_argument("--run-name", type=str, default=None)
    p.add_argument("--kfold", type=int, default=None,
                   help="Number of folds for cross-validation (default: disabled)")
    # Augmentation
    p.add_argument("--augment", dest="no_augment", action="store_false",
                   help="Enable train augmentation")
    p.add_argument("--no-augment", dest="no_augment", action="store_true",
                   help="Disable train augmentation")
    p.set_defaults(no_augment=True)
    p.add_argument("--flip-h-prob", type=float, default=0.5)
    p.add_argument("--flip-v-prob", type=float, default=0.5)
    p.add_argument("--crop-scale-min", type=float, default=0.8)
    p.add_argument("--translate", type=float, default=0.05, help="Max translation fraction")
    # Balancing
    p.add_argument("--no-balance", action="store_true", help="Disable class balancing (use all samples as-is)")
    # Debug
    p.add_argument("--top-n-hardest", type=int, default=10, help="Number of hardest samples to save")
    return p.parse_args()


def build_run_parameters(args, use_aug_val):
    """Return a stable, human-readable mapping of run parameters."""
    return {
        "model": args.model,
        "epochs": args.epochs,
        "batch_size": args.batch_size,
        "lr": args.lr,
        "seed": args.seed,
        "val_split": args.val_split,
        "min_ro": args.min_ro,
        "num_workers": args.num_workers,
        "run_name": args.run_name,
        "kfold": args.kfold,
        "augment_enabled": not args.no_augment,
        "flip_h_prob": args.flip_h_prob,
        "flip_v_prob": args.flip_v_prob,
        "crop_scale_min": args.crop_scale_min,
        "translate": args.translate,
        "class_balancing_enabled": not args.no_balance,
        "augmented_validation_enabled": use_aug_val,
        "top_n_hardest": args.top_n_hardest,
    }


def save_run_parameters(run_params, run_dir):
    """Write the run parameters to a dedicated text artifact."""
    path = os.path.join(run_dir, "run_parameters.txt")
    with open(path, "w") as f:
        for key, value in run_params.items():
            f.write(f"{key}: {value}\n")
    print(f"Saved run parameters: {path}")


def build_plot_annotation(split_info=None, run_params=None, width=130):
    """Build a wrapped footer block for training curve figures."""
    blocks = []
    if split_info:
        blocks.append(textwrap.fill(
            split_info,
            width=width,
            break_long_words=False,
            break_on_hyphens=False,
        ))
    if run_params:
        params_line = "Parameters: " + ", ".join(
            f"{key}={value}" for key, value in run_params.items()
        )
        blocks.append(textwrap.fill(
            params_line,
            width=width,
            break_long_words=False,
            break_on_hyphens=False,
        ))
    if not blocks:
        return None
    return "\n\n".join(blocks)


def build_train_transform(args):
    """Build train-only augmentation pipeline. Returns None when augmentation is disabled."""
    if args.no_augment:
        return None
    return T.Compose([
        T.RandomHorizontalFlip(p=args.flip_h_prob),
        T.RandomVerticalFlip(p=args.flip_v_prob),
        T.RandomResizedCrop(
            size=(IMG_SIZE, IMG_SIZE),
            scale=(args.crop_scale_min, 1.0),
            ratio=(0.95, 1.05),
            antialias=True,
        ),
        T.RandomAffine(
            degrees=0,
            translate=(args.translate, args.translate),
        ),
    ])


def build_augmented_val_cache(val_dataset, args, run_dir):
    """Build a deterministic augmented copy of the validation set.

    For each val sample, seeds an RNG with (run_seed + sample_index), samples
    augmentation parameters, applies them with functional transforms, and caches
    the result. Returns a CachedTensorDataset and the per-sample param records.
    """
    aug_tensors = []
    aug_labels = []
    aug_params = []

    for idx in range(len(val_dataset)):
        meta = val_dataset.get_metadata(idx)
        bin_path = val_dataset._resolve_bin_path(meta)
        img = bitstream_to_image(bin_path, val_dataset.img_size)
        tensor = torch.from_numpy(img.astype(np.float32) / 255.0).unsqueeze(0)  # [1, H, W]

        # Per-sample deterministic RNG
        rng = np.random.RandomState(args.seed + idx)

        # Sample parameters
        do_hflip = rng.random() < args.flip_h_prob
        do_vflip = rng.random() < args.flip_v_prob

        # RandomResizedCrop params
        scale = rng.uniform(args.crop_scale_min, 1.0)
        crop_size = int(round(IMG_SIZE * np.sqrt(scale)))
        crop_size = min(crop_size, IMG_SIZE)
        max_i = IMG_SIZE - crop_size
        max_j = IMG_SIZE - crop_size
        crop_i = rng.randint(0, max_i + 1) if max_i > 0 else 0
        crop_j = rng.randint(0, max_j + 1) if max_j > 0 else 0

        # Translation params
        max_tx = int(args.translate * IMG_SIZE)
        max_ty = int(args.translate * IMG_SIZE)
        translate_x = rng.randint(-max_tx, max_tx + 1) if max_tx > 0 else 0
        translate_y = rng.randint(-max_ty, max_ty + 1) if max_ty > 0 else 0

        # Apply transforms functionally
        t = tensor
        if do_hflip:
            t = TF.hflip(t)
        if do_vflip:
            t = TF.vflip(t)
        t = TF.crop(t, crop_i, crop_j, crop_size, crop_size)
        t = TF.resize(t, [IMG_SIZE, IMG_SIZE], antialias=True)
        if translate_x != 0 or translate_y != 0:
            t = TF.affine(t, angle=0, translate=[translate_x, translate_y],
                          scale=1.0, shear=0)

        aug_tensors.append(t)
        aug_labels.append(float(meta["class_label"]))
        aug_params.append({
            "sample_index": idx,
            "sample_id": meta.get("sample_id", ""),
            "class_label": meta.get("class_label", ""),
            "hflip": do_hflip,
            "vflip": do_vflip,
            "crop_scale": f"{scale:.4f}",
            "crop_i": crop_i,
            "crop_j": crop_j,
            "crop_size": crop_size,
            "translate_x": translate_x,
            "translate_y": translate_y,
        })

    # Save manifest
    manifest_path = os.path.join(run_dir, "augmented_val_manifest.csv")
    fieldnames = list(aug_params[0].keys())
    with open(manifest_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(aug_params)
    print(f"Saved augmented-val manifest: {manifest_path}")

    # Save cache
    cache_path = os.path.join(run_dir, "augmented_val_cache.pt")
    torch.save({
        "tensors": torch.stack(aug_tensors),
        "labels": torch.tensor(aug_labels, dtype=torch.float32),
    }, cache_path)
    print(f"Saved augmented-val cache: {cache_path} "
          f"({torch.stack(aug_tensors).shape})")

    cached_ds = CachedTensorDataset(
        aug_tensors, aug_labels,
        sample_list=val_dataset.samples,
    )
    return cached_ds, aug_tensors, aug_params


def train_one_epoch(model, loader, criterion, optimizer, device):
    model.train()
    total_loss = 0.0
    n = 0
    for images, labels in loader:
        images = images.to(device)
        labels = labels.to(device).unsqueeze(1)  # [B] -> [B, 1]

        optimizer.zero_grad()
        logits = model(images)  # [B, 1]
        loss = criterion(logits, labels)
        loss.backward()
        optimizer.step()

        total_loss += loss.item() * images.size(0)
        n += images.size(0)
    return total_loss / n


@torch.no_grad()
def validate(model, loader, criterion, device):
    """Run validation, returning aggregate metrics."""
    model.eval()
    total_loss = 0.0
    all_labels = []
    all_probs = []
    n = 0

    for batch in loader:
        images, labels = batch[0], batch[1]
        images = images.to(device)
        labels = labels.to(device).unsqueeze(1)

        logits = model(images)
        loss = criterion(logits, labels)

        total_loss += loss.item() * images.size(0)
        n += images.size(0)

        probs = torch.sigmoid(logits).cpu().numpy().flatten()
        all_probs.extend(probs)
        all_labels.extend(labels.cpu().numpy().flatten())

    all_labels = np.array(all_labels)
    all_probs = np.array(all_probs)
    all_preds = (all_probs >= 0.5).astype(int)

    # Per-class log loss
    benign_mask = all_labels == 0
    stand_mask = all_labels == 1
    eps = 1e-7
    clipped = np.clip(all_probs, eps, 1 - eps)

    metrics = {
        "bce_loss": total_loss / n,
        "log_loss": log_loss(all_labels, all_probs, labels=[0, 1]),
        "benign_log_loss": log_loss(all_labels[benign_mask], all_probs[benign_mask], labels=[0, 1]) if benign_mask.any() else float("nan"),
        "standalone_log_loss": log_loss(all_labels[stand_mask], all_probs[stand_mask], labels=[0, 1]) if stand_mask.any() else float("nan"),
        "brier_score": brier_score_loss(all_labels, all_probs),
        "accuracy": accuracy_score(all_labels, all_preds),
        "precision": precision_score(all_labels, all_preds, zero_division=0),
        "recall": recall_score(all_labels, all_preds, zero_division=0),
        "f1": f1_score(all_labels, all_preds, zero_division=0),
        "confusion_matrix": confusion_matrix(all_labels, all_preds),
    }
    if len(np.unique(all_labels)) > 1:
        metrics["roc_auc"] = roc_auc_score(all_labels, all_probs)
        # Optimal threshold via Youden's J statistic (max TPR - FPR)
        fpr, tpr, thresholds = roc_curve(all_labels, all_probs)
        finite_mask = np.isfinite(thresholds)
        if finite_mask.any():
            j_scores = tpr[finite_mask] - fpr[finite_mask]
            optimal_idx = np.argmax(j_scores)
            optimal_threshold = float(thresholds[finite_mask][optimal_idx])
        else:
            optimal_threshold = 0.5
        optimal_preds = (all_probs >= optimal_threshold).astype(int)
        metrics["optimal_threshold"] = optimal_threshold
        metrics["optimal_accuracy"] = accuracy_score(all_labels, optimal_preds)
        metrics["optimal_f1"] = f1_score(all_labels, optimal_preds, zero_division=0)
    else:
        metrics["roc_auc"] = float("nan")
        metrics["optimal_threshold"] = 0.5
        metrics["optimal_accuracy"] = metrics["accuracy"]
        metrics["optimal_f1"] = metrics["f1"]

    return metrics


@torch.no_grad()
def validate_per_sample(model, loader, device):
    """Run validation returning per-sample results for debugging.

    Expects loader built from a dataset with return_index=True.
    Returns list of dicts, one per sample.
    """
    model.eval()
    criterion_none = nn.BCEWithLogitsLoss(reduction="none")
    results = []

    for images, labels, indices in loader:
        images = images.to(device)
        labels_dev = labels.to(device).unsqueeze(1)

        logits = model(images)  # [B, 1]
        per_sample_bce = criterion_none(logits, labels_dev).cpu().numpy().flatten()

        probs = torch.sigmoid(logits).cpu().numpy().flatten()
        logits_np = logits.cpu().numpy().flatten()

        for i in range(len(labels)):
            prob = float(probs[i])
            true_label = int(labels[i].item())
            pred_label = 1 if prob >= 0.5 else 0
            eps = 1e-7
            p_clipped = np.clip(prob, eps, 1 - eps)
            if true_label == 1:
                sample_log_loss = -np.log(p_clipped)
            else:
                sample_log_loss = -np.log(1 - p_clipped)

            results.append({
                "dataset_index": int(indices[i].item()),
                "logit": float(logits_np[i]),
                "probability": prob,
                "predicted_label": pred_label,
                "correct": pred_label == true_label,
                "per_sample_bce_loss": float(per_sample_bce[i]),
                "per_sample_log_loss": float(sample_log_loss),
            })

    return results


def write_per_sample_csv(per_sample_results, val_dataset, out_path):
    """Merge per-sample model outputs with manifest metadata and write CSV."""
    rows = []
    for r in per_sample_results:
        meta = val_dataset.get_metadata(r["dataset_index"])
        rows.append({
            "sample_index": r["dataset_index"],
            "sample_id": meta.get("sample_id", ""),
            "app_name": meta.get("app_name", ""),
            "class_label": meta.get("class_label", ""),
            "class_name": meta.get("class_name", ""),
            "ro_count": meta.get("ro_count", ""),
            "bitstream_path": meta.get("bitstream_path", ""),
            "logit": f"{r['logit']:.6f}",
            "probability": f"{r['probability']:.6f}",
            "predicted_label": r["predicted_label"],
            "correct": r["correct"],
            "per_sample_bce_loss": f"{r['per_sample_bce_loss']:.6f}",
            "per_sample_log_loss": f"{r['per_sample_log_loss']:.6f}",
        })

    fieldnames = list(rows[0].keys())
    with open(out_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(f"Saved per-sample CSV: {out_path}")
    return rows


def write_hardest_csv(all_rows, out_dir, prefix, top_n=10):
    """Write CSVs for hardest samples, top FPs, and top FNs."""
    fieldnames = list(all_rows[0].keys())

    # Sort by loss descending
    sorted_by_loss = sorted(all_rows, key=lambda r: float(r["per_sample_bce_loss"]), reverse=True)

    # Top hardest overall
    path = os.path.join(out_dir, f"{prefix}_hardest_samples.csv")
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(sorted_by_loss[:top_n])
    print(f"Saved hardest samples CSV: {path}")

    # Top false positives (predicted 1, true 0)
    fps = [r for r in sorted_by_loss if int(r["class_label"]) == 0 and r["predicted_label"] == 1]
    if fps:
        path = os.path.join(out_dir, f"{prefix}_top_false_positives.csv")
        with open(path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(fps[:top_n])
        print(f"Saved top FPs CSV: {path} ({len(fps[:top_n])} rows)")

    # Top false negatives (predicted 0, true 1)
    fns = [r for r in sorted_by_loss if int(r["class_label"]) == 1 and r["predicted_label"] == 0]
    if fns:
        path = os.path.join(out_dir, f"{prefix}_top_false_negatives.csv")
        with open(path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(fns[:top_n])
        print(f"Saved top FNs CSV: {path} ({len(fns[:top_n])} rows)")

    return sorted_by_loss[:top_n]


def export_debug_bundle(model, loader_debug, dataset_debug, run_dir, prefix, top_n, label):
    """Export per-sample CSVs and hardest images for one evaluation slice."""
    print(f"\nCollecting per-sample results for {label}...")
    per_sample = validate_per_sample(model, loader_debug, device=next(model.parameters()).device)
    all_rows = write_per_sample_csv(
        per_sample,
        dataset_debug,
        os.path.join(run_dir, f"{prefix}_per_sample.csv"),
    )
    hardest = write_hardest_csv(all_rows, run_dir, prefix=prefix, top_n=top_n)
    save_hardest_samples(
        hardest,
        dataset_debug,
        run_dir,
        out_name=f"{prefix}_hardest_images",
        top_n=top_n,
    )


def save_training_curves(history, out_dir, split_info=None, run_params=None):
    has_aug = "aug_val_bce_loss" in history and len(history["aug_val_bce_loss"]) > 0

    fig, axes = plt.subplots(2, 3, figsize=(15, 8))

    # BCE Loss
    axes[0, 0].plot(history["train_loss"], label="train")
    axes[0, 0].plot(history["val_bce_loss"], label="val")
    if has_aug:
        axes[0, 0].plot(history["aug_val_bce_loss"], label="aug_val", linestyle="--", alpha=0.7)
    axes[0, 0].set_xlabel("Epoch")
    axes[0, 0].set_ylabel("Loss")
    axes[0, 0].legend()
    axes[0, 0].set_title("BCE Loss")

    # Accuracy
    axes[0, 1].plot(history["val_accuracy"], label="val")
    if has_aug:
        axes[0, 1].plot(history["aug_val_accuracy"], label="aug_val", linestyle="--", alpha=0.7)
    if "val_optimal_accuracy" in history and len(history["val_optimal_accuracy"]) > 0:
        axes[0, 1].plot(history["val_optimal_accuracy"], label="val (opt thr)", linestyle=":", alpha=0.8)
    if has_aug and "aug_val_optimal_accuracy" in history and len(history["aug_val_optimal_accuracy"]) > 0:
        axes[0, 1].plot(history["aug_val_optimal_accuracy"], label="aug_val (opt thr)", linestyle=":", alpha=0.8)
    axes[0, 1].set_xlabel("Epoch")
    axes[0, 1].set_ylabel("Accuracy")
    axes[0, 1].legend(fontsize=7)
    axes[0, 1].set_title("Accuracy")
    axes[0, 1].set_ylim([0, 1.05])

    # ROC-AUC
    axes[0, 2].plot(history["val_roc_auc"], label="val")
    if has_aug:
        axes[0, 2].plot(history["aug_val_roc_auc"], label="aug_val", linestyle="--", alpha=0.7)
    axes[0, 2].set_xlabel("Epoch")
    axes[0, 2].set_ylabel("ROC-AUC")
    axes[0, 2].legend()
    axes[0, 2].set_title("ROC-AUC")
    axes[0, 2].set_ylim([0, 1.05])

    # Log Loss
    axes[1, 0].plot(history["val_log_loss"], label="val", color="tab:orange")
    if has_aug:
        axes[1, 0].plot(history["aug_val_log_loss"], label="aug_val", color="tab:orange",
                        linestyle="--", alpha=0.7)
    axes[1, 0].set_xlabel("Epoch")
    axes[1, 0].set_ylabel("Log Loss")
    axes[1, 0].legend()
    axes[1, 0].set_title("Log Loss")

    # Per-Class Log Loss
    axes[1, 1].plot(history["val_benign_log_loss"], label="val benign", color="tab:blue")
    axes[1, 1].plot(history["val_standalone_log_loss"], label="val standalone", color="tab:red")
    if has_aug:
        axes[1, 1].plot(history["aug_val_benign_log_loss"], label="aug benign",
                        color="tab:blue", linestyle="--", alpha=0.7)
        axes[1, 1].plot(history["aug_val_standalone_log_loss"], label="aug standalone",
                        color="tab:red", linestyle="--", alpha=0.7)
    axes[1, 1].set_xlabel("Epoch")
    axes[1, 1].set_ylabel("Log Loss")
    axes[1, 1].legend(fontsize=7)
    axes[1, 1].set_title("Per-Class Log Loss")

    # Brier Score
    axes[1, 2].plot(history["val_brier_score"], label="val", color="tab:green")
    if has_aug:
        axes[1, 2].plot(history["aug_val_brier_score"], label="aug_val",
                        color="tab:green", linestyle="--", alpha=0.7)
    axes[1, 2].set_xlabel("Epoch")
    axes[1, 2].set_ylabel("Brier Score")
    axes[1, 2].legend()
    axes[1, 2].set_title("Brier Score")

    annotation = build_plot_annotation(split_info=split_info, run_params=run_params)
    if annotation:
        footer_lines = annotation.count("\n") + 1
        footer_height = min(0.34, 0.04 + footer_lines * 0.028)
        fig.text(
            0.01, 0.01, annotation,
            fontsize=8, family="monospace",
            verticalalignment="bottom",
        )
    else:
        footer_height = 0.04

    plt.tight_layout(rect=[0, footer_height, 1, 1])
    path = os.path.join(out_dir, "training_curves.png")
    plt.savefig(path, dpi=150)
    plt.close()
    print(f"Saved training curves: {path}")


VAL_METRIC_SUFFIXES = [
    "bce_loss", "log_loss", "benign_log_loss", "standalone_log_loss",
    "brier_score", "accuracy", "roc_auc", "f1",
    "optimal_threshold", "optimal_accuracy", "optimal_f1",
]


def print_metrics(label, m, epoch_label=""):
    """Print a metrics summary block."""
    print(f"\n--- {label} Metrics{' (epoch ' + str(epoch_label) + ')' if epoch_label else ''} ---")
    print(f"  BCE Loss:            {m['bce_loss']:.4f}")
    print(f"  Log Loss:            {m['log_loss']:.4f}")
    print(f"  Benign Log Loss:     {m['benign_log_loss']:.4f}")
    print(f"  Standalone Log Loss: {m['standalone_log_loss']:.4f}")
    print(f"  Brier Score:         {m['brier_score']:.4f}")
    print(f"  Accuracy:            {m['accuracy']:.4f}")
    print(f"  Precision:           {m['precision']:.4f}")
    print(f"  Recall:              {m['recall']:.4f}")
    print(f"  F1:                  {m['f1']:.4f}")
    print(f"  ROC-AUC:             {m['roc_auc']:.4f}")
    print(f"  Optimal Threshold:   {m['optimal_threshold']:.6f}")
    print(f"  Optimal Accuracy:    {m['optimal_accuracy']:.4f}")
    print(f"  Optimal F1:          {m['optimal_f1']:.4f}")
    print(f"  Confusion matrix (rows=true, cols=pred):")
    print(f"    [benign]     {m['confusion_matrix'][0]}")
    print(f"    [standalone] {m['confusion_matrix'][1]}")


def format_dataset_summary(samples, n_benign, n_stand, balance_tag="", fold_label=""):
    parts = []
    if fold_label:
        parts.append(f"Fold: {fold_label}")
    parts.append(f"Dataset: {len(samples)} ({n_benign} benign, {n_stand} standalone{balance_tag})")
    return "  |  ".join(parts)


def train_fold(args, train_samples, val_samples, fold_dir, device, use_aug_val,
               fold_label="", dataset_summary=None, run_params=None):
    """Train one fold. Returns dict with history, best_metrics, best_epoch."""
    os.makedirs(fold_dir, exist_ok=True)

    train_labels = [int(s["class_label"]) for s in train_samples]
    val_labels = [int(s["class_label"]) for s in val_samples]
    n_train_benign = sum(1 for l in train_labels if l == 0)
    n_train_stand = sum(1 for l in train_labels if l == 1)
    n_val_benign = sum(1 for l in val_labels if l == 0)
    n_val_stand = sum(1 for l in val_labels if l == 1)
    print(f"Train: {len(train_samples)} ({n_train_benign} benign, {n_train_stand} standalone)")
    print(f"Val:   {len(val_samples)} ({n_val_benign} benign, {n_val_stand} standalone)")

    # --- Transforms ---
    train_transform = build_train_transform(args)
    if train_transform is not None:
        print(f"Train augmentation: ON (flip_h={args.flip_h_prob}, flip_v={args.flip_v_prob}, "
              f"crop_scale={args.crop_scale_min}-1.0, translate={args.translate})")
    else:
        print("Train augmentation: OFF")

    # --- Datasets ---
    train_ds = BitstreamDataset(train_samples, transform=train_transform)
    val_ds = BitstreamDataset(val_samples)
    val_ds_debug = BitstreamDataset(val_samples, return_index=True)

    train_loader = DataLoader(
        train_ds, batch_size=args.batch_size, shuffle=True,
        num_workers=args.num_workers, pin_memory=True,
    )
    val_loader = DataLoader(
        val_ds, batch_size=args.batch_size, shuffle=False,
        num_workers=args.num_workers, pin_memory=True,
    )
    val_loader_debug = DataLoader(
        val_ds_debug, batch_size=args.batch_size, shuffle=False,
        num_workers=args.num_workers, pin_memory=True,
    )

    # --- Augmentation sanity check ---
    if train_transform is not None:
        save_augmentation_grid(train_ds, fold_dir, n_samples=4, n_augments=4)

    # --- Augmented-val cache ---
    if use_aug_val:
        print("\nBuilding deterministic augmented-val cache...")
        aug_val_ds, aug_val_tensors, aug_val_params = build_augmented_val_cache(
            val_ds, args, fold_dir,
        )
        aug_val_loader = DataLoader(
            aug_val_ds, batch_size=args.batch_size, shuffle=False,
            num_workers=0, pin_memory=True,
        )
        aug_val_ds_debug = CachedTensorDataset(
            aug_val_ds.tensors, aug_val_ds.labels,
            sample_list=val_ds.samples, return_index=True,
        )
        aug_val_loader_debug = DataLoader(
            aug_val_ds_debug, batch_size=args.batch_size, shuffle=False,
            num_workers=0, pin_memory=True,
        )
        save_augmented_val_sanity_check(val_ds, aug_val_tensors, aug_val_params, fold_dir)

    # --- Model ---
    model = build_model(args.model)
    model = model.to(device)
    print(f"Model: {args.model} ({sum(p.numel() for p in model.parameters()):,} parameters)")

    # --- Training setup ---
    criterion = nn.BCEWithLogitsLoss()
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)

    # --- Training loop ---
    history_keys = ["train_loss"]
    history_keys += [f"val_{s}" for s in VAL_METRIC_SUFFIXES]
    if use_aug_val:
        history_keys += [f"aug_val_{s}" for s in VAL_METRIC_SUFFIXES]
    history = {k: [] for k in history_keys}
    best_auc = -1.0
    best_epoch = -1

    if use_aug_val:
        header = (f"{'Ep':>3} {'TrLoss':>8} {'VaBCE':>8} {'AugBCE':>8} "
                  f"{'Acc':>6} {'AugAcc':>6} {'OptAcc':>6} {'AUC':>6} {'AugAUC':>6} {'OptThr':>8} {'Time':>6}")
    else:
        header = (f"{'Ep':>3} {'TrLoss':>8} {'VaBCE':>8} "
                  f"{'Acc':>6} {'OptAcc':>6} {'AUC':>6} {'OptThr':>8} {'Time':>6}")
    print(f"\n{header}")
    print("-" * len(header))

    for epoch in range(1, args.epochs + 1):
        t0 = time.time()

        train_loss = train_one_epoch(model, train_loader, criterion, optimizer, device)
        val_metrics = validate(model, val_loader, criterion, device)
        if use_aug_val:
            aug_val_metrics = validate(model, aug_val_loader, criterion, device)

        elapsed = time.time() - t0

        history["train_loss"].append(train_loss)
        for suffix in VAL_METRIC_SUFFIXES:
            history[f"val_{suffix}"].append(val_metrics[suffix])
            if use_aug_val:
                history[f"aug_val_{suffix}"].append(aug_val_metrics[suffix])

        if use_aug_val:
            print(
                f"{epoch:3d} {train_loss:8.4f} {val_metrics['bce_loss']:8.4f} "
                f"{aug_val_metrics['bce_loss']:8.4f} "
                f"{val_metrics['accuracy']:6.3f} {aug_val_metrics['accuracy']:6.3f} "
                f"{val_metrics['optimal_accuracy']:6.3f} "
                f"{val_metrics['roc_auc']:6.3f} {aug_val_metrics['roc_auc']:6.3f} "
                f"{val_metrics['optimal_threshold']:8.6f} "
                f"{elapsed:5.1f}s"
            )
        else:
            print(
                f"{epoch:3d} {train_loss:8.4f} {val_metrics['bce_loss']:8.4f} "
                f"{val_metrics['accuracy']:6.3f} "
                f"{val_metrics['optimal_accuracy']:6.3f} "
                f"{val_metrics['roc_auc']:6.3f} "
                f"{val_metrics['optimal_threshold']:8.6f} "
                f"{elapsed:5.1f}s"
            )

        # Save best model by canonical val ROC-AUC
        if val_metrics["roc_auc"] > best_auc:
            best_auc = val_metrics["roc_auc"]
            best_epoch = epoch
            torch.save(model.state_dict(), os.path.join(fold_dir, "best_model.pt"))

    # --- Final-epoch evaluation and artifacts ---
    final_model_path = os.path.join(fold_dir, "final_model.pt")
    torch.save(model.state_dict(), final_model_path)
    print(f"\nSaved final-epoch model: {final_model_path}")

    final_epoch_metrics = validate(model, val_loader, criterion, device)
    print_metrics("Final Epoch / Canonical Validation", final_epoch_metrics, epoch_label=args.epochs)
    if use_aug_val:
        final_epoch_aug_metrics = validate(model, aug_val_loader, criterion, device)
        print_metrics("Final Epoch / Augmented Validation", final_epoch_aug_metrics, epoch_label=args.epochs)

    export_debug_bundle(
        model, val_loader_debug, val_ds_debug, fold_dir,
        prefix="final_canonical_val", top_n=args.top_n_hardest,
        label="final epoch / canonical val",
    )
    if use_aug_val:
        export_debug_bundle(
            model, aug_val_loader_debug, aug_val_ds_debug, fold_dir,
            prefix="final_augmented_val", top_n=args.top_n_hardest,
            label="final epoch / augmented val",
        )

    # --- Best-checkpoint evaluation and artifacts ---
    print(f"\nBest epoch: {best_epoch} (ROC-AUC = {best_auc:.4f})")
    model.load_state_dict(torch.load(os.path.join(fold_dir, "best_model.pt"), weights_only=True))
    best_metrics = validate(model, val_loader, criterion, device)
    print_metrics("Best Checkpoint / Canonical Validation", best_metrics, epoch_label=best_epoch)
    if use_aug_val:
        best_aug_metrics = validate(model, aug_val_loader, criterion, device)
        print_metrics("Best Checkpoint / Augmented Validation", best_aug_metrics, epoch_label=best_epoch)

    export_debug_bundle(
        model, val_loader_debug, val_ds_debug, fold_dir,
        prefix="best_canonical_val", top_n=args.top_n_hardest,
        label="best checkpoint / canonical val",
    )
    if use_aug_val:
        export_debug_bundle(
            model, aug_val_loader_debug, aug_val_ds_debug, fold_dir,
            prefix="best_augmented_val", top_n=args.top_n_hardest,
            label="best checkpoint / augmented val",
        )

    # --- Save per-fold artifacts ---
    split_parts = []
    if dataset_summary:
        split_parts.append(dataset_summary)
    if fold_label:
        split_parts.append(f"Fold: {fold_label}")
    split_parts.append(f"Train: {len(train_samples)} ({n_train_benign} benign, {n_train_stand} standalone)")
    split_parts.append(f"Val: {len(val_samples)} ({n_val_benign} benign, {n_val_stand} standalone)")
    split_info = "  |  ".join(split_parts)
    save_training_curves(history, fold_dir, split_info=split_info, run_params=run_params)

    with open(os.path.join(fold_dir, "history.csv"), "w") as f:
        f.write("epoch," + ",".join(history_keys) + "\n")
        for i in range(len(history["train_loss"])):
            vals = ",".join(f"{history[k][i]:.6f}" for k in history_keys)
            f.write(f"{i+1},{vals}\n")

    print(f"\nFold artifacts saved to: {fold_dir}")
    return {
        "fold_label": fold_label or os.path.basename(fold_dir),
        "history": history,
        "best_metrics": best_metrics,
        "best_epoch": best_epoch,
    }


def save_kfold_summary(fold_results, run_dir, n_folds):
    """Write kfold_summary.csv and print mean +/- std."""
    if not fold_results:
        raise ValueError("save_kfold_summary() requires at least one fold result")

    rows = []
    for i, r in enumerate(fold_results):
        m = r["best_metrics"]
        rows.append({
            "fold": i,
            "best_epoch": r["best_epoch"],
            "val_roc_auc": m["roc_auc"],
            "val_accuracy": m["accuracy"],
            "val_optimal_accuracy": m["optimal_accuracy"],
            "val_optimal_f1": m["optimal_f1"],
            "val_optimal_threshold": m["optimal_threshold"],
            "val_bce_loss": m["bce_loss"],
        })

    path = os.path.join(run_dir, "kfold_summary.csv")
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"\nSaved k-fold summary: {path}")

    print(f"\nK-Fold Cross-Validation Summary ({n_folds} folds)")
    print("-" * 50)
    pretty_names = {
        "val_roc_auc": "ROC-AUC",
        "val_accuracy": "Accuracy (0.5)",
        "val_optimal_accuracy": "Optimal Accuracy",
        "val_optimal_f1": "Optimal F1",
        "val_optimal_threshold": "Optimal Threshold",
        "val_bce_loss": "BCE Loss",
    }
    for key in [
        "val_roc_auc",
        "val_accuracy",
        "val_optimal_accuracy",
        "val_optimal_f1",
        "val_optimal_threshold",
        "val_bce_loss",
    ]:
        vals = [r[key] for r in rows]
        print(f"  {pretty_names[key]:>20s}:  {np.mean(vals):.4f} +/- {np.std(vals):.4f}")


def save_kfold_curves(fold_results, run_dir, split_info=None, run_params=None):
    """Overlay training curves from all folds on one plot."""
    colors = plt.cm.tab10.colors

    fig, axes = plt.subplots(2, 3, figsize=(15, 8))
    for i, r in enumerate(fold_results):
        h = r["history"]
        c = colors[i % len(colors)]
        label = r.get("fold_label", f"fold_{i}")

        axes[0, 0].plot(h["val_bce_loss"], label=label, color=c, alpha=0.85)
        axes[0, 0].plot(h["train_loss"], color=c, alpha=0.25, linestyle="--")

        axes[0, 1].plot(h["val_accuracy"], label=label, color=c, alpha=0.85)
        if "val_optimal_accuracy" in h:
            axes[0, 1].plot(h["val_optimal_accuracy"], color=c, alpha=0.5, linestyle=":")

        axes[0, 2].plot(h["val_roc_auc"], label=label, color=c, alpha=0.85)

        axes[1, 0].plot(h["val_log_loss"], label=label, color=c, alpha=0.85)

        axes[1, 1].plot(h["val_standalone_log_loss"], label=label, color=c, alpha=0.85)
        axes[1, 1].plot(h["val_benign_log_loss"], color=c, alpha=0.5, linestyle="--")

        axes[1, 2].plot(h["val_brier_score"], label=label, color=c, alpha=0.85)

    axes[0, 0].set_title("BCE Loss (solid=val, dashed=train)")
    axes[0, 1].set_title("Accuracy (solid=0.5, dotted=opt)")
    axes[0, 2].set_title("ROC-AUC")
    axes[1, 0].set_title("Log Loss")
    axes[1, 1].set_title("Per-Class Log Loss (solid=standalone, dashed=benign)")
    axes[1, 2].set_title("Brier Score")

    for ax, ylabel in [
        (axes[0, 0], "Loss"),
        (axes[0, 1], "Accuracy"),
        (axes[0, 2], "ROC-AUC"),
        (axes[1, 0], "Log Loss"),
        (axes[1, 1], "Log Loss"),
        (axes[1, 2], "Brier Score"),
    ]:
        ax.set_xlabel("Epoch")
        ax.set_ylabel(ylabel)
        ax.legend(fontsize=7)

    axes[0, 1].set_ylim([0, 1.05])
    axes[0, 2].set_ylim([0, 1.05])

    annotation = build_plot_annotation(split_info=split_info, run_params=run_params)
    if annotation:
        footer_lines = annotation.count("\n") + 1
        footer_height = min(0.34, 0.04 + footer_lines * 0.028)
        fig.text(0.01, 0.01, annotation, fontsize=8, family="monospace",
                 verticalalignment="bottom")
    else:
        footer_height = 0.04

    plt.tight_layout(rect=[0, footer_height, 1, 1])
    path = os.path.join(run_dir, "kfold_training_curves.png")
    plt.savefig(path, dpi=150)
    plt.close()
    print(f"Saved k-fold training curves: {path}")


def main():
    args = parse_args()
    if args.kfold is not None and args.kfold < 2:
        raise SystemExit("--kfold must be at least 2")

    torch.manual_seed(args.seed)
    np.random.seed(args.seed)

    # --- Run directory ---
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    base_name = args.run_name or f"{args.model}_ro{args.min_ro}_ep{args.epochs}"
    if args.kfold:
        base_name = f"{base_name}_kfold{args.kfold}"
    run_name = f"{timestamp}_{base_name}"
    run_dir = os.path.join(OUTPUT_DIR, run_name)
    os.makedirs(run_dir, exist_ok=True)
    print(f"Run directory: {run_dir}")

    # --- Device ---
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")

    # --- Data ---
    samples = load_manifest(min_ro=args.min_ro)
    labels = [int(s["class_label"]) for s in samples]
    n_benign_raw = sum(1 for l in labels if l == 0)
    n_stand_raw = sum(1 for l in labels if l == 1)
    n_total_raw = len(samples)
    print(f"Loaded: {n_total_raw} samples ({n_benign_raw} benign, {n_stand_raw} standalone)")

    # --- Class balancing (on by default) ---
    if not args.no_balance and n_benign_raw > n_stand_raw:
        rng = np.random.RandomState(args.seed)
        benign_samples = [s for s in samples if int(s["class_label"]) == 0]
        stand_samples = [s for s in samples if int(s["class_label"]) == 1]
        benign_keep = rng.choice(len(benign_samples), size=n_stand_raw, replace=False)
        benign_samples = [benign_samples[i] for i in sorted(benign_keep)]
        samples = benign_samples + stand_samples
        labels = [int(s["class_label"]) for s in samples]
        n_dropped = n_benign_raw - n_stand_raw
        print(f"Balanced: {len(samples)} ({n_stand_raw} benign, {n_stand_raw} standalone) "
              f"[dropped {n_dropped} benign]")

    n_benign = sum(1 for l in labels if l == 0)
    n_stand = sum(1 for l in labels if l == 1)
    print(f"Dataset: {len(samples)} samples ({n_benign} benign, {n_stand} standalone)")
    dataset_summary = format_dataset_summary(
        samples, n_benign, n_stand,
        balance_tag=f", balanced from {n_total_raw}" if not args.no_balance and n_benign_raw > n_stand_raw else "",
    )

    if args.kfold and min(n_benign, n_stand) < args.kfold:
        raise SystemExit(
            f"--kfold={args.kfold} is too large for the balanced dataset "
            f"({n_benign} benign, {n_stand} standalone)"
        )

    use_aug_val = (not args.no_augment) and not args.kfold
    if args.kfold and not args.no_augment:
        print("K-fold mode: augmented validation is disabled; only canonical validation will be used.")
    run_params = build_run_parameters(args, use_aug_val)
    save_run_parameters(run_params, run_dir)

    if args.kfold:
        # --- K-Fold Cross-Validation ---
        skf = StratifiedKFold(n_splits=args.kfold, shuffle=True, random_state=args.seed)
        fold_results = []

        for fold_idx, (train_idx, val_idx) in enumerate(skf.split(samples, labels)):
            fold_train = [samples[i] for i in train_idx]
            fold_val = [samples[i] for i in val_idx]
            fold_dir = os.path.join(run_dir, f"fold_{fold_idx}")

            print(f"\n{'=' * 60}")
            print(f"FOLD {fold_idx + 1}/{args.kfold}")
            print(f"{'=' * 60}")

            # Different seed per fold for model init, but reproducible
            torch.manual_seed(args.seed + fold_idx)
            np.random.seed(args.seed + fold_idx)

            result = train_fold(
                args, fold_train, fold_val, fold_dir, device, use_aug_val,
                fold_label=f"fold_{fold_idx}",
                dataset_summary=dataset_summary,
                run_params=run_params,
            )
            fold_results.append(result)

        # --- Aggregation ---
        save_kfold_summary(fold_results, run_dir, n_folds=args.kfold)
        split_info = f"{dataset_summary}  |  {args.kfold}-fold CV"
        save_kfold_curves(fold_results, run_dir, split_info=split_info, run_params=run_params)
        print(f"\nAll k-fold artifacts saved to: {run_dir}")

    else:
        # --- Single split (original behavior) ---
        train_samples, val_samples = train_test_split(
            samples, test_size=args.val_split, random_state=args.seed, stratify=labels
        )
        train_fold(
            args, train_samples, val_samples, run_dir, device, use_aug_val,
            dataset_summary=dataset_summary,
            run_params=run_params,
        )

        print(f"\nAll artifacts saved to: {run_dir}")


if __name__ == "__main__":
    main()
