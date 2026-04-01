"""Training script for grayscale ResNet-18 binary classifier.

Usage:
    python train.py                    # default 50 epochs
    python train.py --epochs 1         # quick smoke test
    python train.py --batch-size 4     # reduce if OOM
    python train.py --lr 1e-3          # override learning rate
"""

import argparse
import os
import time

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import torch
import torch.nn as nn
from sklearn.metrics import (
    accuracy_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.model_selection import train_test_split
from torch.utils.data import DataLoader

from dataset import BitstreamDataset, load_manifest
from model import grayscale_resnet18

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
    return p.parse_args()


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
    model.eval()
    total_loss = 0.0
    all_labels = []
    all_probs = []
    n = 0

    for images, labels in loader:
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

    metrics = {
        "loss": total_loss / n,
        "accuracy": accuracy_score(all_labels, all_preds),
        "precision": precision_score(all_labels, all_preds, zero_division=0),
        "recall": recall_score(all_labels, all_preds, zero_division=0),
        "f1": f1_score(all_labels, all_preds, zero_division=0),
        "confusion_matrix": confusion_matrix(all_labels, all_preds),
    }
    # ROC-AUC requires both classes present
    if len(np.unique(all_labels)) > 1:
        metrics["roc_auc"] = roc_auc_score(all_labels, all_probs)
    else:
        metrics["roc_auc"] = float("nan")

    return metrics


def save_training_curves(history, out_dir):
    fig, axes = plt.subplots(1, 3, figsize=(15, 4))

    axes[0].plot(history["train_loss"], label="train")
    axes[0].plot(history["val_loss"], label="val")
    axes[0].set_xlabel("Epoch")
    axes[0].set_ylabel("Loss")
    axes[0].legend()
    axes[0].set_title("Loss")

    axes[1].plot(history["val_accuracy"], label="accuracy")
    axes[1].set_xlabel("Epoch")
    axes[1].set_ylabel("Accuracy")
    axes[1].set_title("Validation Accuracy")
    axes[1].set_ylim([0, 1.05])

    axes[2].plot(history["val_roc_auc"], label="ROC-AUC")
    axes[2].set_xlabel("Epoch")
    axes[2].set_ylabel("ROC-AUC")
    axes[2].set_title("Validation ROC-AUC")
    axes[2].set_ylim([0, 1.05])

    plt.tight_layout()
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
    print(f"Train: {len(train_samples)}, Val: {len(val_samples)}")

    train_ds = BitstreamDataset(train_samples)
    val_ds = BitstreamDataset(val_samples)
    train_loader = DataLoader(
        train_ds, batch_size=args.batch_size, shuffle=True,
        num_workers=args.num_workers, pin_memory=True,
    )
    val_loader = DataLoader(
        val_ds, batch_size=args.batch_size, shuffle=False,
        num_workers=args.num_workers, pin_memory=True,
    )

    # --- Model ---
    model = grayscale_resnet18(pretrained=False)
    model = model.to(device)
    print(f"Model parameters: {sum(p.numel() for p in model.parameters()):,}")

    # --- Training setup ---
    criterion = nn.BCEWithLogitsLoss()
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)

    # --- Training loop ---
    history = {
        "train_loss": [], "val_loss": [], "val_accuracy": [],
        "val_roc_auc": [], "val_f1": [],
    }
    best_auc = -1.0
    best_epoch = -1

    print(f"\n{'Epoch':>5} {'TrLoss':>8} {'VaLoss':>8} {'Acc':>6} {'AUC':>6} {'F1':>6} {'Time':>6}")
    print("-" * 55)

    for epoch in range(1, args.epochs + 1):
        t0 = time.time()

        train_loss = train_one_epoch(model, train_loader, criterion, optimizer, device)
        val_metrics = validate(model, val_loader, criterion, device)

        elapsed = time.time() - t0

        history["train_loss"].append(train_loss)
        history["val_loss"].append(val_metrics["loss"])
        history["val_accuracy"].append(val_metrics["accuracy"])
        history["val_roc_auc"].append(val_metrics["roc_auc"])
        history["val_f1"].append(val_metrics["f1"])

        print(
            f"{epoch:5d} {train_loss:8.4f} {val_metrics['loss']:8.4f} "
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
    print(f"  Loss:      {final['loss']:.4f}")
    print(f"  Accuracy:  {final['accuracy']:.4f}")
    print(f"  Precision: {final['precision']:.4f}")
    print(f"  Recall:    {final['recall']:.4f}")
    print(f"  F1:        {final['f1']:.4f}")
    print(f"  ROC-AUC:   {final['roc_auc']:.4f}")
    print(f"\nConfusion matrix (rows=true, cols=pred):")
    print(f"  [benign]     {final['confusion_matrix'][0]}")
    print(f"  [standalone] {final['confusion_matrix'][1]}")

    # --- Save artifacts ---
    save_training_curves(history, run_dir)
    torch.save(model.state_dict(), os.path.join(run_dir, "final_model.pt"))

    # Save history as CSV
    with open(os.path.join(run_dir, "history.csv"), "w") as f:
        f.write("epoch,train_loss,val_loss,val_accuracy,val_roc_auc,val_f1\n")
        for i in range(len(history["train_loss"])):
            f.write(
                f"{i+1},{history['train_loss'][i]:.6f},{history['val_loss'][i]:.6f},"
                f"{history['val_accuracy'][i]:.6f},{history['val_roc_auc'][i]:.6f},"
                f"{history['val_f1'][i]:.6f}\n"
            )

    print(f"\nAll artifacts saved to: {run_dir}")


if __name__ == "__main__":
    main()
