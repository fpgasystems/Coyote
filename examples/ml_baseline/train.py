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
from sklearn.model_selection import train_test_split
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


def save_training_curves(history, out_dir, split_info=None):
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

    if split_info:
        fig.text(
            0.01, 0.01, split_info,
            fontsize=8, family="monospace",
            verticalalignment="bottom",
        )

    plt.tight_layout(rect=[0, 0.04, 1, 1])
    path = os.path.join(out_dir, "training_curves.png")
    plt.savefig(path, dpi=150)
    plt.close()
    print(f"Saved training curves: {path}")


def main():
    args = parse_args()
    torch.manual_seed(args.seed)
    np.random.seed(args.seed)

    # --- Run directory ---
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    base_name = args.run_name or f"{args.model}_ro{args.min_ro}_ep{args.epochs}"
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

    train_samples, val_samples = train_test_split(
        samples, test_size=args.val_split, random_state=args.seed, stratify=labels
    )
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
        save_augmentation_grid(train_ds, run_dir, n_samples=4, n_augments=4)

    # --- Augmented-val cache (deterministic, built once) ---
    use_aug_val = not args.no_augment
    if use_aug_val:
        print("\nBuilding deterministic augmented-val cache...")
        aug_val_ds, aug_val_tensors, aug_val_params = build_augmented_val_cache(
            val_ds, args, run_dir,
        )
        aug_val_loader = DataLoader(
            aug_val_ds, batch_size=args.batch_size, shuffle=False,
            num_workers=0, pin_memory=True,  # num_workers=0: data already in memory
        )
        aug_val_ds_debug = CachedTensorDataset(
            aug_val_ds.tensors,
            aug_val_ds.labels,
            sample_list=val_ds.samples,
            return_index=True,
        )
        aug_val_loader_debug = DataLoader(
            aug_val_ds_debug, batch_size=args.batch_size, shuffle=False,
            num_workers=0, pin_memory=True,
        )
        save_augmented_val_sanity_check(val_ds, aug_val_tensors, aug_val_params, run_dir)

    # --- Model ---
    model = build_model(args.model)
    model = model.to(device)
    print(f"Model: {args.model} ({sum(p.numel() for p in model.parameters()):,} parameters)")

    # --- Training setup ---
    criterion = nn.BCEWithLogitsLoss()
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)

    # --- Training loop ---
    val_metric_suffixes = [
        "bce_loss", "log_loss", "benign_log_loss", "standalone_log_loss",
        "brier_score", "accuracy", "roc_auc", "f1",
        "optimal_threshold", "optimal_accuracy", "optimal_f1",
    ]
    history_keys = ["train_loss"]
    history_keys += [f"val_{s}" for s in val_metric_suffixes]
    if use_aug_val:
        history_keys += [f"aug_val_{s}" for s in val_metric_suffixes]
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
        for suffix in val_metric_suffixes:
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
            torch.save(model.state_dict(), os.path.join(run_dir, "best_model.pt"))

    # --- Final-epoch evaluation and artifacts ---
    final_model_path = os.path.join(run_dir, "final_model.pt")
    torch.save(model.state_dict(), final_model_path)
    print(f"\nSaved final-epoch model: {final_model_path}")

    final_epoch_metrics = validate(model, val_loader, criterion, device)
    final_eval_pairs = [("Final Epoch / Canonical Validation", final_epoch_metrics)]
    if use_aug_val:
        final_epoch_aug_metrics = validate(model, aug_val_loader, criterion, device)
        final_eval_pairs.append(("Final Epoch / Augmented Validation", final_epoch_aug_metrics))

    for label, m in final_eval_pairs:
        print(f"\n--- {label} Metrics (epoch {args.epochs}) ---")
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

    export_debug_bundle(
        model, val_loader_debug, val_ds_debug, run_dir,
        prefix="final_canonical_val", top_n=args.top_n_hardest,
        label="final epoch / canonical val",
    )
    if use_aug_val:
        export_debug_bundle(
            model, aug_val_loader_debug, aug_val_ds_debug, run_dir,
            prefix="final_augmented_val", top_n=args.top_n_hardest,
            label="final epoch / augmented val",
        )

    # --- Best-checkpoint evaluation and artifacts ---
    print(f"\nBest epoch: {best_epoch} (ROC-AUC = {best_auc:.4f})")
    model.load_state_dict(torch.load(os.path.join(run_dir, "best_model.pt"), weights_only=True))
    best_metrics = validate(model, val_loader, criterion, device)
    best_eval_pairs = [("Best Checkpoint / Canonical Validation", best_metrics)]
    if use_aug_val:
        best_aug_metrics = validate(model, aug_val_loader, criterion, device)
        best_eval_pairs.append(("Best Checkpoint / Augmented Validation", best_aug_metrics))

    for label, m in best_eval_pairs:
        print(f"\n--- {label} Metrics (epoch {best_epoch}) ---")
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

    export_debug_bundle(
        model, val_loader_debug, val_ds_debug, run_dir,
        prefix="best_canonical_val", top_n=args.top_n_hardest,
        label="best checkpoint / canonical val",
    )
    if use_aug_val:
        export_debug_bundle(
            model, aug_val_loader_debug, aug_val_ds_debug, run_dir,
            prefix="best_augmented_val", top_n=args.top_n_hardest,
            label="best checkpoint / augmented val",
        )

    # --- Save artifacts ---
    balance_tag = f", balanced from {n_total_raw}" if not args.no_balance and n_benign_raw > n_stand_raw else ""
    split_info = (f"Dataset: {len(samples)} ({n_benign} benign, {n_stand} standalone{balance_tag})  |  "
                  f"Train: {len(train_samples)} ({n_train_benign} benign, {n_train_stand} standalone)  |  "
                  f"Val: {len(val_samples)} ({n_val_benign} benign, {n_val_stand} standalone)")
    save_training_curves(history, run_dir, split_info=split_info)

    # Save history as CSV
    with open(os.path.join(run_dir, "history.csv"), "w") as f:
        f.write("epoch," + ",".join(history_keys) + "\n")
        for i in range(len(history["train_loss"])):
            vals = ",".join(f"{history[k][i]:.6f}" for k in history_keys)
            f.write(f"{i+1},{vals}\n")

    print(f"\nAll artifacts saved to: {run_dir}")


if __name__ == "__main__":
    main()
