"""Grad-CAM verification for trained binary classifiers on bitstream images.

Usage example:
    .venv/bin/python gradcam.py \
        --model cnn_b \
        --run-dir /path/to/runs/20260410_103932_cnn_b_ro8000_ep200_kfold5 \
        --fold 0 \
        --checkpoint best \
        --min-ro 8000 \
        --sample-id it2_B064 \
        --sample-id it1_S074 \
        --output-dir /path/to/output_dir
"""

import argparse
import csv
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import torch
import torch.nn.functional as F

from dataset import bitstream_to_image, load_manifest
from model import build_model, MODEL_CHOICES


TARGET_CLASS_NAMES = ("benign", "standalone")
DEFAULT_TARGET_LAYERS = {
    "resnet18": "layer4.1.conv2",
    "cnn_a": "features.6",
    "cnn_b": "features.9",
}


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--model", type=str, required=True, choices=MODEL_CHOICES)
    p.add_argument("--run-dir", type=str, required=True,
                   help="Path to a run directory containing fold_* subdirectories")
    p.add_argument("--fold", type=int, default=None,
                   help="Fold index for k-fold runs. Omit for single-split runs.")
    p.add_argument("--checkpoint", type=str, default="best", choices=["best", "final"])
    p.add_argument("--min-ro", type=int, default=4000)
    p.add_argument("--sample-id", action="append", required=True,
                   help="Manifest-prefixed sample ID. Repeat for multiple samples.")
    p.add_argument("--output-dir", type=str, required=True)
    p.add_argument("--device", type=str, default=None,
                   help="Device override, e.g. cuda, cuda:0, cpu")
    p.add_argument("--target-layer", type=str, default=None,
                   help="Override target layer path, e.g. features.9")
    return p.parse_args()


def get_device(device_arg):
    if device_arg:
        return torch.device(device_arg)
    return torch.device("cuda" if torch.cuda.is_available() else "cpu")


def resolve_target_layer(model, layer_path):
    module = model
    for part in layer_path.split("."):
        if part.isdigit():
            module = module[int(part)]
        else:
            module = getattr(module, part)
    return module


def load_checkpoint(model, checkpoint_path, device):
    try:
        state = torch.load(checkpoint_path, map_location=device, weights_only=True)
    except TypeError:
        state = torch.load(checkpoint_path, map_location=device)
    model.load_state_dict(state)


def load_fold_predictions(fold_dir, checkpoint):
    csv_name = f"{checkpoint}_canonical_val_per_sample.csv"
    csv_path = os.path.join(fold_dir, csv_name)
    rows = {}
    with open(csv_path, newline="") as f:
        for row in csv.DictReader(f):
            rows[row["sample_id"]] = row
    return csv_path, rows


def resolve_eval_paths(run_dir, fold, checkpoint):
    if fold is None:
        eval_dir = run_dir
        split_label = "single_split"
    else:
        eval_dir = os.path.join(run_dir, f"fold_{fold}")
        split_label = f"fold_{fold}"

    checkpoint_path = os.path.join(eval_dir, f"{checkpoint}_model.pt")
    return eval_dir, split_label, checkpoint_path


def load_manifest_index(min_ro):
    manifest_rows = load_manifest(min_ro=min_ro)
    return {row["sample_id"]: row for row in manifest_rows}


def class_name_from_label(label):
    return "standalone" if int(label) == 1 else "benign"


def predicted_label_from_prob(prob):
    return 1 if prob >= 0.5 else 0


def normalize_array(arr):
    arr = arr.astype(np.float32)
    arr = arr - arr.min()
    max_val = arr.max()
    if max_val > 0:
        arr = arr / max_val
    return arr


def colorize_heatmap(cam):
    cmap = plt.get_cmap("jet")
    return cmap(cam)[..., :3]


def make_overlay(image_uint8, cam):
    gray = image_uint8.astype(np.float32) / 255.0
    gray_rgb = np.stack([gray, gray, gray], axis=-1)
    heat_rgb = colorize_heatmap(cam)
    alpha = 0.65 * cam[..., None]
    overlay = gray_rgb * (1.0 - alpha) + heat_rgb * alpha
    return np.clip(overlay, 0.0, 1.0)


class GradCAMRunner:
    def __init__(self, model, target_layer):
        self.model = model
        self.activations = None
        self.gradients = None

        def forward_hook(_module, _inputs, output):
            self.activations = output.detach()

            def grad_hook(grad):
                self.gradients = grad.detach()

            output.register_hook(grad_hook)

        self.handle = target_layer.register_forward_hook(forward_hook)

    def close(self):
        self.handle.remove()

    def compute(self, input_tensor, target_class):
        if target_class not in TARGET_CLASS_NAMES:
            raise ValueError(f"Unknown target_class={target_class!r}")

        self.gradients = None
        self.activations = None
        self.model.zero_grad(set_to_none=True)

        logits = self.model(input_tensor)
        standalone_logit = logits[0, 0]
        objective = standalone_logit if target_class == "standalone" else -standalone_logit
        objective.backward()

        if self.activations is None or self.gradients is None:
            raise RuntimeError("Grad-CAM hooks did not capture activations/gradients")

        activations = self.activations[0]
        gradients = self.gradients[0]
        weights = gradients.mean(dim=(1, 2), keepdim=True)
        cam = torch.relu((weights * activations).sum(dim=0, keepdim=True))
        cam = F.interpolate(
            cam.unsqueeze(0),
            size=input_tensor.shape[-2:],
            mode="bilinear",
            align_corners=False,
        )[0, 0]
        cam_np = cam.detach().cpu().numpy().astype(np.float32)
        cam_np = normalize_array(cam_np)

        prob = torch.sigmoid(standalone_logit).item()
        pred_label = predicted_label_from_prob(prob)
        return {
            "standalone_probability": prob,
            "predicted_label": pred_label,
            "cam": cam_np,
        }


def load_sample_tensor(sample_meta, device):
    bin_path = os.path.join(sample_meta["_bitstream_dir"], sample_meta["bitstream_path"])
    image_uint8 = bitstream_to_image(bin_path)
    tensor = torch.from_numpy(image_uint8.astype(np.float32) / 255.0).unsqueeze(0).unsqueeze(0)
    return image_uint8, tensor.to(device)


def save_gradcam_panel(out_path, image_uint8, cam, meta, target_class, fold_idx,
                       checkpoint_name, target_layer_name, pred_prob, expected_prob,
                       split_label):
    heat_rgb = colorize_heatmap(cam)
    overlay = make_overlay(image_uint8, cam)

    fig, axes = plt.subplots(1, 3, figsize=(15, 5))
    axes[0].imshow(image_uint8, cmap="gray", vmin=0, vmax=255)
    axes[0].set_title("Original")
    axes[1].imshow(heat_rgb)
    axes[1].set_title(f"Grad-CAM: {target_class}")
    axes[2].imshow(overlay)
    axes[2].set_title("Overlay")
    for ax in axes:
        ax.axis("off")

    footer = (
        f"sample_id={meta['sample_id']}  app={meta.get('app_name', '?')}  true_class={class_name_from_label(meta['class_label'])}  "
        f"target_class={target_class}  pred_prob={pred_prob:.6f}  expected_prob={expected_prob:.6f}  "
        f"pred_label={predicted_label_from_prob(pred_prob)}  split={split_label}  checkpoint={checkpoint_name}  "
        f"target_layer={target_layer_name}"
    )
    fig.suptitle(f"{meta['sample_id']} | {target_class}", fontsize=12)
    fig.text(0.01, 0.02, footer, fontsize=8, family="monospace")
    plt.tight_layout(rect=[0, 0.06, 1, 0.95])
    plt.savefig(out_path, dpi=160)
    plt.close(fig)


def save_overview_grid(out_path, rows, target_order):
    n_rows = len(rows)
    n_cols = len(target_order)
    fig, axes = plt.subplots(n_rows, n_cols, figsize=(6 * n_cols, 4 * n_rows))
    if n_rows == 1:
        axes = np.array([axes])
    if n_cols == 1:
        axes = axes[:, np.newaxis]

    for row_idx, row in enumerate(rows):
        for col_idx, target_class in enumerate(target_order):
            ax = axes[row_idx, col_idx]
            result = row["targets"][target_class]
            ax.imshow(result["overlay"])
            ax.axis("off")
            ax.set_title(
                f"{row['meta']['sample_id']} | true={class_name_from_label(row['meta']['class_label'])}\n"
                f"target={target_class} | p={row['pred_prob']:.6f}"
            )

    plt.tight_layout()
    plt.savefig(out_path, dpi=160)
    plt.close(fig)


def write_summary_csv(out_path, summary_rows):
    fieldnames = [
        "sample_id",
        "app_name",
        "true_class",
        "target_class",
        "predicted_probability",
        "expected_probability",
        "probability_delta",
        "predicted_label",
        "expected_predicted_label",
        "correct",
        "split",
        "checkpoint",
        "target_layer",
        "output_png",
    ]
    with open(out_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(summary_rows)


def write_run_command(out_path, command_text=None):
    with open(out_path, "w") as f:
        f.write((command_text or " ".join(sys.argv)) + "\n")


def select_default_sample_ids(prediction_rows, max_samples=4):
    """Pick a representative canonical validation subset for automatic Grad-CAM."""
    if isinstance(prediction_rows, dict):
        rows = list(prediction_rows.values())
    else:
        rows = list(prediction_rows)

    selected = []
    seen = set()

    def add_first(candidates):
        for row in candidates:
            sample_id = row["sample_id"]
            if sample_id not in seen:
                selected.append(sample_id)
                seen.add(sample_id)
                return

    correct_benign = sorted(
        [r for r in rows if int(r["class_label"]) == 0 and str(r["correct"]) == "True"],
        key=lambda r: float(r["probability"]),
    )
    correct_standalone = sorted(
        [r for r in rows if int(r["class_label"]) == 1 and str(r["correct"]) == "True"],
        key=lambda r: float(r["probability"]),
        reverse=True,
    )
    false_positives = sorted(
        [r for r in rows if int(r["class_label"]) == 0 and str(r["correct"]) != "True"],
        key=lambda r: float(r["per_sample_bce_loss"]),
        reverse=True,
    )
    false_negatives = sorted(
        [r for r in rows if int(r["class_label"]) == 1 and str(r["correct"]) != "True"],
        key=lambda r: float(r["per_sample_bce_loss"]),
        reverse=True,
    )

    for group in [correct_benign, correct_standalone, false_positives, false_negatives]:
        add_first(group)
        if len(selected) >= max_samples:
            return selected

    hardest_remaining = sorted(
        rows,
        key=lambda r: float(r["per_sample_bce_loss"]),
        reverse=True,
    )
    for row in hardest_remaining:
        sample_id = row["sample_id"]
        if sample_id not in seen:
            selected.append(sample_id)
            seen.add(sample_id)
        if len(selected) >= max_samples:
            break
    return selected


def generate_gradcam_bundle(model_name, eval_dir, checkpoint, min_ro, sample_ids,
                            output_dir, device_arg=None, target_layer_name=None,
                            split_label="single_split", command_text=None):
    """Generate a Grad-CAM bundle programmatically."""
    os.makedirs(output_dir, exist_ok=True)

    device = get_device(device_arg)
    checkpoint_path = os.path.join(eval_dir, f"{checkpoint}_model.pt")
    target_layer_name = target_layer_name or DEFAULT_TARGET_LAYERS[model_name]

    print(f"Eval dir: {eval_dir}")
    print(f"Checkpoint: {checkpoint_path}")
    print(f"Device: {device}")
    print(f"Target layer: {target_layer_name}")

    fold_csv_path, fold_predictions = load_fold_predictions(eval_dir, checkpoint)
    manifest_index = load_manifest_index(min_ro)
    print(f"Loaded fold predictions: {fold_csv_path}")
    print(f"Loaded manifest rows: {len(manifest_index)}")

    model = build_model(model_name).to(device)
    load_checkpoint(model, checkpoint_path, device)
    model.eval()

    target_layer = resolve_target_layer(model, target_layer_name)
    gradcam = GradCAMRunner(model, target_layer)

    overview_rows = []
    summary_rows = []

    try:
        for sample_id in sample_ids:
            if sample_id not in fold_predictions:
                raise KeyError(f"Sample {sample_id} not found in fold predictions: {fold_csv_path}")
            if sample_id not in manifest_index:
                raise KeyError(f"Sample {sample_id} not found in merged manifest")

            fold_row = fold_predictions[sample_id]
            meta = manifest_index[sample_id]
            image_uint8, input_tensor = load_sample_tensor(meta, device)

            print(f"Processing sample: {sample_id} ({class_name_from_label(meta['class_label'])})")

            row_targets = {}
            pred_prob = None

            for target_class in TARGET_CLASS_NAMES:
                result = gradcam.compute(input_tensor, target_class)
                cam = result["cam"]
                pred_prob = result["standalone_probability"]
                expected_prob = float(fold_row["probability"])

                png_name = f"{sample_id}_{target_class}_gradcam.png"
                out_png = os.path.join(output_dir, png_name)
                save_gradcam_panel(
                    out_png,
                    image_uint8,
                    cam,
                    meta,
                    target_class,
                    None,
                    checkpoint,
                    target_layer_name,
                    pred_prob,
                    expected_prob,
                    split_label,
                )
                print(f"  Saved: {out_png}")

                row_targets[target_class] = {
                    "cam": cam,
                    "overlay": make_overlay(image_uint8, cam),
                    "output_png": out_png,
                }
                summary_rows.append({
                    "sample_id": sample_id,
                    "app_name": meta.get("app_name", ""),
                    "true_class": class_name_from_label(meta["class_label"]),
                    "target_class": target_class,
                    "predicted_probability": f"{pred_prob:.6f}",
                    "expected_probability": f"{expected_prob:.6f}",
                    "probability_delta": f"{abs(pred_prob - expected_prob):.6e}",
                    "predicted_label": result["predicted_label"],
                    "expected_predicted_label": fold_row["predicted_label"],
                    "correct": fold_row["correct"],
                    "split": split_label,
                    "checkpoint": checkpoint,
                    "target_layer": target_layer_name,
                    "output_png": os.path.basename(out_png),
                })

            overview_rows.append({
                "meta": meta,
                "pred_prob": pred_prob,
                "targets": row_targets,
            })
    finally:
        gradcam.close()

    summary_csv = os.path.join(output_dir, "gradcam_summary.csv")
    overview_png = os.path.join(output_dir, "overview_grid.png")
    run_command_path = os.path.join(output_dir, "run_command.txt")

    write_summary_csv(summary_csv, summary_rows)
    save_overview_grid(overview_png, overview_rows, TARGET_CLASS_NAMES)
    write_run_command(run_command_path, command_text=command_text)

    print(f"Saved summary CSV: {summary_csv}")
    print(f"Saved overview grid: {overview_png}")
    print(f"Saved run command: {run_command_path}")
    return {
        "summary_csv": summary_csv,
        "overview_png": overview_png,
        "run_command_path": run_command_path,
        "sample_ids": list(sample_ids),
    }


def main():
    args = parse_args()
    eval_dir, split_label, checkpoint_path = resolve_eval_paths(args.run_dir, args.fold, args.checkpoint)
    print(f"Run dir: {args.run_dir}")
    generate_gradcam_bundle(
        model_name=args.model,
        eval_dir=eval_dir,
        checkpoint=args.checkpoint,
        min_ro=args.min_ro,
        sample_ids=args.sample_id,
        output_dir=args.output_dir,
        device_arg=args.device,
        target_layer_name=args.target_layer,
        split_label=split_label,
    )


if __name__ == "__main__":
    main()
