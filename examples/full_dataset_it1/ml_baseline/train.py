"""Training script for grayscale ResNet-18 binary classifier.

Usage:
    python train.py                    # default 50 epochs
    python train.py --epochs 1         # quick smoke test
    python train.py --batch-size 4     # reduce if OOM
    python train.py --lr 1e-3          # override learning rate
    python train.py --no-augment       # disable train augmentation
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
)
from sklearn.model_selection import train_test_split
from torch.utils.data import DataLoader

from dataset import BitstreamDataset, load_manifest, bitstream_to_image, BITSTREAM_DIR, IMG_SIZE
from model import grayscale_resnet18
from visualize import save_hardest_samples, save_augmentation_grid

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "runs")


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--epochs", type=int, default=50)
    p.add_argument("--batch-size", type=int, default=8)
    p.add_argument("--lr", type=float, default=1e-4)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--val-split", type=float, default=0.2)
    p.add_argument("--min-ro", type=int, default=4000)
    p.add_argument("--num-workers", type=int, default=4)
    p.add_argument("--run-name", type=str, default=None)
    # Augmentation
    p.add_argument("--no-augment", action="store_true", help="Disable train augmentation")
    p.add_argument("--flip-h-prob", type=float, default=0.5)
    p.add_argument("--flip-v-prob", type=float, default=0.5)
    p.add_argument("--crop-scale-min", type=float, default=0.8)
    p.add_argument("--translate", type=float, default=0.05, help="Max translation fraction")
    # Debug
    p.add_argument("--top-n-hardest", type=int, default=10, help="Number of hardest samples to save")
    return p.parse_args()


def build_train_transform(args):
    """Build train-only augmentation pipeline. Returns None if --no-augment."""
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
    else:
        metrics["roc_auc"] = float("nan")

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


def write_hardest_csv(all_rows, out_dir, top_n=10):
    """Write CSVs for hardest samples, top FPs, and top FNs."""
    fieldnames = list(all_rows[0].keys())

    # Sort by loss descending
    sorted_by_loss = sorted(all_rows, key=lambda r: float(r["per_sample_bce_loss"]), reverse=True)

    # Top hardest overall
    path = os.path.join(out_dir, "hardest_samples.csv")
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(sorted_by_loss[:top_n])
    print(f"Saved hardest samples CSV: {path}")

    # Top false positives (predicted 1, true 0)
    fps = [r for r in sorted_by_loss if int(r["class_label"]) == 0 and r["predicted_label"] == 1]
    if fps:
        path = os.path.join(out_dir, "top_false_positives.csv")
        with open(path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(fps[:top_n])
        print(f"Saved top FPs CSV: {path} ({len(fps[:top_n])} rows)")

    # Top false negatives (predicted 0, true 1)
    fns = [r for r in sorted_by_loss if int(r["class_label"]) == 1 and r["predicted_label"] == 0]
    if fns:
        path = os.path.join(out_dir, "top_false_negatives.csv")
        with open(path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(fns[:top_n])
        print(f"Saved top FNs CSV: {path} ({len(fns[:top_n])} rows)")

    return sorted_by_loss[:top_n]


def save_training_curves(history, out_dir, split_info=None):
    fig, axes = plt.subplots(2, 3, figsize=(15, 8))

    axes[0, 0].plot(history["train_loss"], label="train")
    axes[0, 0].plot(history["val_bce_loss"], label="val")
    axes[0, 0].set_xlabel("Epoch")
    axes[0, 0].set_ylabel("Loss")
    axes[0, 0].legend()
    axes[0, 0].set_title("BCE Loss")

    axes[0, 1].plot(history["val_accuracy"], label="accuracy")
    axes[0, 1].set_xlabel("Epoch")
    axes[0, 1].set_ylabel("Accuracy")
    axes[0, 1].set_title("Validation Accuracy")
    axes[0, 1].set_ylim([0, 1.05])

    axes[0, 2].plot(history["val_roc_auc"], label="ROC-AUC")
    axes[0, 2].set_xlabel("Epoch")
    axes[0, 2].set_ylabel("ROC-AUC")
    axes[0, 2].set_title("Validation ROC-AUC")
    axes[0, 2].set_ylim([0, 1.05])

    axes[1, 0].plot(history["val_log_loss"], label="log_loss", color="tab:orange")
    axes[1, 0].set_xlabel("Epoch")
    axes[1, 0].set_ylabel("Log Loss")
    axes[1, 0].set_title("Validation Log Loss")

    axes[1, 1].plot(history["val_benign_log_loss"], label="benign", color="tab:blue")
    axes[1, 1].plot(history["val_standalone_log_loss"], label="standalone", color="tab:red")
    axes[1, 1].set_xlabel("Epoch")
    axes[1, 1].set_ylabel("Log Loss")
    axes[1, 1].legend()
    axes[1, 1].set_title("Per-Class Log Loss")

    axes[1, 2].plot(history["val_brier_score"], label="Brier", color="tab:green")
    axes[1, 2].set_xlabel("Epoch")
    axes[1, 2].set_ylabel("Brier Score")
    axes[1, 2].set_title("Validation Brier Score")

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
    run_name = args.run_name or f"resnet18_ro{args.min_ro}_ep{args.epochs}"
    run_dir = os.path.join(OUTPUT_DIR, run_name)
    os.makedirs(run_dir, exist_ok=True)
    print(f"Run directory: {run_dir}")

    # --- Device ---
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")

    # --- Data ---
    samples = load_manifest(min_ro=args.min_ro)
    labels = [int(s["class_label"]) for s in samples]
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

    # --- Model ---
    model = grayscale_resnet18(pretrained=False)
    model = model.to(device)
    print(f"Model parameters: {sum(p.numel() for p in model.parameters()):,}")

    # --- Training setup ---
    criterion = nn.BCEWithLogitsLoss()
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)

    # --- Training loop ---
    history_keys = [
        "train_loss", "val_bce_loss", "val_log_loss",
        "val_benign_log_loss", "val_standalone_log_loss",
        "val_brier_score", "val_accuracy", "val_roc_auc", "val_f1",
    ]
    history = {k: [] for k in history_keys}
    best_auc = -1.0
    best_epoch = -1

    header = (f"{'Ep':>3} {'TrLoss':>8} {'VaBCE':>8} {'LogL':>8} "
              f"{'Brier':>7} {'Acc':>6} {'AUC':>6} {'F1':>6} {'Time':>6}")
    print(f"\n{header}")
    print("-" * len(header))

    for epoch in range(1, args.epochs + 1):
        t0 = time.time()

        train_loss = train_one_epoch(model, train_loader, criterion, optimizer, device)
        val_metrics = validate(model, val_loader, criterion, device)

        elapsed = time.time() - t0

        history["train_loss"].append(train_loss)
        for key in history_keys:
            if key == "train_loss":
                continue
            metric_key = key.replace("val_", "")
            history[key].append(val_metrics[metric_key])

        print(
            f"{epoch:3d} {train_loss:8.4f} {val_metrics['bce_loss']:8.4f} "
            f"{val_metrics['log_loss']:8.4f} {val_metrics['brier_score']:7.4f} "
            f"{val_metrics['accuracy']:6.3f} {val_metrics['roc_auc']:6.3f} "
            f"{val_metrics['f1']:6.3f} {elapsed:5.1f}s"
        )

        # Save best model by ROC-AUC
        if val_metrics["roc_auc"] > best_auc:
            best_auc = val_metrics["roc_auc"]
            best_epoch = epoch
            torch.save(model.state_dict(), os.path.join(run_dir, "best_model.pt"))

    # --- Final evaluation ---
    print(f"\nBest epoch: {best_epoch} (ROC-AUC = {best_auc:.4f})")
    model.load_state_dict(torch.load(os.path.join(run_dir, "best_model.pt"), weights_only=True))
    final = validate(model, val_loader, criterion, device)

    print(f"\n--- Final Validation Metrics (epoch {best_epoch}) ---")
    print(f"  BCE Loss:            {final['bce_loss']:.4f}")
    print(f"  Log Loss:            {final['log_loss']:.4f}")
    print(f"  Benign Log Loss:     {final['benign_log_loss']:.4f}")
    print(f"  Standalone Log Loss: {final['standalone_log_loss']:.4f}")
    print(f"  Brier Score:         {final['brier_score']:.4f}")
    print(f"  Accuracy:            {final['accuracy']:.4f}")
    print(f"  Precision:           {final['precision']:.4f}")
    print(f"  Recall:              {final['recall']:.4f}")
    print(f"  F1:                  {final['f1']:.4f}")
    print(f"  ROC-AUC:             {final['roc_auc']:.4f}")
    print(f"\nConfusion matrix (rows=true, cols=pred):")
    print(f"  [benign]     {final['confusion_matrix'][0]}")
    print(f"  [standalone] {final['confusion_matrix'][1]}")

    # --- Per-sample debug ---
    print("\nCollecting per-sample validation results...")
    per_sample = validate_per_sample(model, val_loader_debug, device)
    all_rows = write_per_sample_csv(
        per_sample, val_ds_debug,
        os.path.join(run_dir, "val_per_sample.csv"),
    )
    hardest = write_hardest_csv(all_rows, run_dir, top_n=args.top_n_hardest)

    # Save debug images for hardest samples
    save_hardest_samples(hardest, run_dir, top_n=args.top_n_hardest)

    # --- Save artifacts ---
    split_info = (f"Train: {len(train_samples)} ({n_train_benign} benign, {n_train_stand} standalone)  |  "
                  f"Val: {len(val_samples)} ({n_val_benign} benign, {n_val_stand} standalone)")
    save_training_curves(history, run_dir, split_info=split_info)
    torch.save(model.state_dict(), os.path.join(run_dir, "final_model.pt"))

    # Save history as CSV
    with open(os.path.join(run_dir, "history.csv"), "w") as f:
        f.write("epoch," + ",".join(history_keys) + "\n")
        for i in range(len(history["train_loss"])):
            vals = ",".join(f"{history[k][i]:.6f}" for k in history_keys)
            f.write(f"{i+1},{vals}\n")

    print(f"\nAll artifacts saved to: {run_dir}")


if __name__ == "__main__":
    main()
