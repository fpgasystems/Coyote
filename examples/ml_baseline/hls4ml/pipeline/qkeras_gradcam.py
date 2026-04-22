"""QKeras Grad-CAM artifact generation for QAT folds."""

from __future__ import annotations

from pathlib import Path
from typing import Sequence

import numpy as np

from dataset import bitstream_to_array
from gradcam import (
    TARGET_CLASS_NAMES,
    class_name_from_label,
    make_overlay,
    predicted_label_from_prob,
    save_gradcam_panel,
    save_overview_grid,
    select_default_sample_ids,
    write_run_command,
    write_summary_csv,
)


def _normalize_array(arr: np.ndarray) -> np.ndarray:
    arr = arr.astype(np.float32)
    arr = arr - arr.min()
    max_val = arr.max()
    if max_val > 0.0:
        arr = arr / max_val
    return arr


def _sigmoid(value: float) -> float:
    return float(1.0 / (1.0 + np.exp(-float(value))))


def _sample_image_and_input(sample: dict, candidate) -> tuple[np.ndarray, np.ndarray]:
    bin_path = Path(sample["_bitstream_dir"]) / sample["bitstream_path"]
    image_uint8 = bitstream_to_array(
        str(bin_path),
        representation=candidate.representation,
        img_size=candidate.img_size,
        sequence_length=candidate.sequence_length,
    )
    if candidate.representation != "2d":
        raise ValueError("QKeras Grad-CAM currently supports only 2d image candidates")
    x = (image_uint8.astype(np.float32) / 255.0)[np.newaxis, ..., np.newaxis]
    return image_uint8, x


class QKerasGradCAMRunner:
    """TensorFlow Grad-CAM runner for the QKeras binary logit model."""

    def __init__(self, model, target_layer_name: str):
        import tensorflow as tf

        self.tf = tf
        self.model = model
        self.target_layer_name = target_layer_name
        target_layer = model.get_layer(target_layer_name)
        self.grad_model = tf.keras.Model(
            inputs=model.inputs,
            outputs=[target_layer.output, model.output],
        )

    def compute(self, x: np.ndarray, target_class: str) -> dict:
        if target_class not in TARGET_CLASS_NAMES:
            raise ValueError(f"Unknown target_class={target_class!r}")

        tf = self.tf
        x_tensor = tf.convert_to_tensor(x.astype(np.float32))
        with tf.GradientTape() as tape:
            layer_output, logits = self.grad_model(x_tensor, training=False)
            standalone_logit = logits[:, 0]
            objective = standalone_logit if target_class == "standalone" else -standalone_logit

        gradients = tape.gradient(objective, layer_output)
        if gradients is None:
            raise RuntimeError("Grad-CAM gradient computation returned None")

        weights = tf.reduce_mean(gradients, axis=(1, 2), keepdims=True)
        cam = tf.nn.relu(tf.reduce_sum(weights * layer_output, axis=-1))
        cam = tf.image.resize(
            cam[..., tf.newaxis],
            size=x.shape[1:3],
            method="bilinear",
        )[0, ..., 0]
        cam_np = _normalize_array(cam.numpy())

        prob = _sigmoid(float(standalone_logit[0].numpy()))
        return {
            "standalone_probability": prob,
            "predicted_label": predicted_label_from_prob(prob),
            "cam": cam_np,
        }


def write_qkeras_gradcam_bundle(
    model,
    candidate,
    cfg,
    samples: Sequence[dict],
    prediction_rows: Sequence[dict],
    output_dir: Path,
    target_layer_name: str = "act4",
    max_samples: int = 4,
) -> dict | None:
    """Generate Grad-CAM panels and an overview grid for a completed QAT fold."""
    sample_ids = select_default_sample_ids(prediction_rows, max_samples=max_samples)
    if not sample_ids:
        print(f"[qat-gradcam] skip quantizer={cfg.quantizer_tag} fold={cfg.fold}: no candidate samples")
        return None

    output_dir.mkdir(parents=True, exist_ok=True)
    rows_by_id = {row["sample_id"]: row for row in prediction_rows}
    samples_by_id = {sample["sample_id"]: sample for sample in samples}
    runner = QKerasGradCAMRunner(model, target_layer_name=target_layer_name)

    overview_rows = []
    summary_rows = []
    print(
        f"[qat-gradcam] quantizer={cfg.quantizer_tag} fold={cfg.fold} "
        f"target_layer={target_layer_name} samples={', '.join(sample_ids)}"
    )

    for sample_id in sample_ids:
        if sample_id not in rows_by_id:
            raise KeyError(f"Sample {sample_id} not found in QAT prediction rows")
        if sample_id not in samples_by_id:
            raise KeyError(f"Sample {sample_id} not found in QAT validation samples")

        row = rows_by_id[sample_id]
        sample = samples_by_id[sample_id]
        image_uint8, x = _sample_image_and_input(sample, candidate)
        row_targets = {}
        pred_prob = None

        for target_class in TARGET_CLASS_NAMES:
            result = runner.compute(x, target_class)
            cam = result["cam"]
            pred_prob = result["standalone_probability"]
            expected_prob = float(row["probability"])

            png_name = f"{sample_id}_{target_class}_gradcam.png"
            out_png = output_dir / png_name
            save_gradcam_panel(
                str(out_png),
                image_uint8,
                cam,
                sample,
                target_class,
                cfg.fold,
                "final",
                target_layer_name,
                pred_prob,
                expected_prob,
                f"fold_{cfg.fold}",
                candidate.representation,
                candidate.img_size,
            )
            row_targets[target_class] = {
                "cam": cam,
                "overlay": make_overlay(image_uint8, cam),
                "output_png": str(out_png),
            }
            summary_rows.append({
                "sample_id": sample_id,
                "app_name": sample.get("app_name", ""),
                "true_class": class_name_from_label(sample["class_label"]),
                "target_class": target_class,
                "predicted_probability": f"{pred_prob:.6f}",
                "expected_probability": f"{expected_prob:.6f}",
                "probability_delta": f"{abs(pred_prob - expected_prob):.6e}",
                "predicted_label": result["predicted_label"],
                "expected_predicted_label": row["predicted_label"],
                "correct": row["correct"],
                "split": f"fold_{cfg.fold}",
                "checkpoint": "final",
                "target_layer": target_layer_name,
                "output_png": png_name,
            })
            print(f"[qat-gradcam] saved {out_png}")

        overview_rows.append({
            "meta": sample,
            "pred_prob": pred_prob,
            "targets": row_targets,
        })

    summary_csv = output_dir / "gradcam_summary.csv"
    overview_png = output_dir / "overview_grid.png"
    run_command_path = output_dir / "run_command.txt"
    command_text = (
        f"auto_from_train_qkeras_qat.py candidate={candidate.name} "
        f"quantizer={cfg.quantizer_tag} fold={cfg.fold} checkpoint=final "
        f"target_layer={target_layer_name} sample_ids={' '.join(sample_ids)}"
    )
    write_summary_csv(str(summary_csv), summary_rows)
    save_overview_grid(str(overview_png), overview_rows, TARGET_CLASS_NAMES)
    write_run_command(str(run_command_path), command_text=command_text)

    print(f"[qat-gradcam] saved summary CSV: {summary_csv}")
    print(f"[qat-gradcam] saved overview grid: {overview_png}")
    return {
        "summary_csv": str(summary_csv),
        "overview_png": str(overview_png),
        "run_command_path": str(run_command_path),
        "sample_ids": list(sample_ids),
    }
