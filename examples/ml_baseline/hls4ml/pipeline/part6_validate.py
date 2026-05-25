"""Part 6 of the notebook flow: final Keras/hls4ml/U55C validation."""

from __future__ import annotations

import time

import numpy as np

from .coyote_accelerator.raw_data import load_raw_arrays, raw_reference_nhwc
from .part1_common import (
    FlowContext,
    clean_rows,
    metrics_from_stage_rows,
    parity_dir_for_fold,
    rows_from_logits,
    write_csv,
    write_json,
    write_run_index,
)

from train import save_checkpoint_plots  # noqa: E402

def stage_validate(ctx: FlowContext, force: bool = False) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from sklearn.metrics import precision_recall_curve, roc_curve

    parity_dir = parity_dir_for_fold(ctx, ctx.model_slot)
    qkeras_rows = clean_rows(parity_dir / "qkeras_per_sample.csv")
    hls_rows = clean_rows(parity_dir / "hls_per_sample.csv")
    prep_rows = clean_rows(ctx.prepared_inputs_dir / "manifest.csv")
    hw_raw_rows = clean_rows(ctx.u55c_root / "hardware_per_sample.csv")
    if not qkeras_rows or not hls_rows:
        raise FileNotFoundError(f"Missing parity rows in {parity_dir}")
    if not hw_raw_rows:
        raise FileNotFoundError(f"Missing U55C hardware rows: {ctx.u55c_root / 'hardware_per_sample.csv'}")

    x_prepared = np.load(ctx.prepared_inputs_dir / "x_norm.npy").astype(np.float32)
    raw_reference = raw_reference_nhwc(ctx, load_raw_arrays(prep_rows))
    if raw_reference.shape != x_prepared.shape:
        raise RuntimeError(f"raw reference shape {raw_reference.shape} != prepared input shape {x_prepared.shape}")
    raw_reference_max_abs = float(np.max(np.abs(raw_reference - x_prepared))) if x_prepared.size else 0.0
    if raw_reference_max_abs > 1e-7:
        raise RuntimeError(f"raw downsampling reference does not match prepared inputs: max_abs={raw_reference_max_abs}")

    hw_logits_by_idx = {int(row["sample_index"]): float(row["logit"]) for row in hw_raw_rows}
    hw_logits = np.asarray([hw_logits_by_idx[int(row["sample_index"])] for row in prep_rows], dtype=np.float32)
    hw_rows = rows_from_logits(prep_rows, [int(row["class_label"]) for row in prep_rows], hw_logits)
    write_csv(ctx.u55c_root / "hardware_per_sample_enriched.csv", hw_rows)
    np.save(ctx.u55c_root / "y_hw.npy", hw_logits)
    stages = {f"{ctx.training_stage} Keras CPU": qkeras_rows, "hls4ml CPU": hls_rows, "U55C hardware": hw_rows}
    summary = {}
    summary_keys = [
        "accuracy",
        "balanced_accuracy",
        "precision",
        "recall",
        "f1",
        "roc_auc",
        "pr_auc",
        "bce_loss",
        "log_loss",
        "mcc",
    ]
    for name, rows in stages.items():
        metrics = metrics_from_stage_rows(rows)
        summary[name] = {key: float(metrics[key]) for key in summary_keys if key in metrics}
        if "confusion_matrix" in metrics:
            summary[name]["confusion_matrix"] = np.asarray(metrics["confusion_matrix"]).astype(int).tolist()
    ctx.validation_dir.mkdir(parents=True, exist_ok=True)
    write_json(ctx.validation_dir / "comparison_summary.json", summary)
    labels = np.asarray([int(row["class_label"]) for row in qkeras_rows], dtype=np.int32)
    fig, axes = plt.subplots(1, 3, figsize=(18, 5))
    for name, rows in stages.items():
        probs = np.asarray([float(row["probability"]) for row in rows], dtype=np.float32)
        fpr, tpr, _ = roc_curve(labels, probs)
        prec, rec, _ = precision_recall_curve(labels, probs)
        metrics = metrics_from_stage_rows(rows)
        axes[0].plot(fpr, tpr, label=f"{name} ({metrics['roc_auc']:.4f})")
        axes[1].plot(rec, prec, label=f"{name} ({metrics['pr_auc']:.4f})")
        axes[2].hist(probs[labels == 0], bins=20, range=(0, 1), histtype="step", density=True, label=f"{name} benign")
        axes[2].hist(probs[labels == 1], bins=20, range=(0, 1), histtype="step", density=True, linestyle="--", label=f"{name} standalone")
    axes[0].plot([0, 1], [0, 1], "k:", linewidth=1)
    axes[0].set_title("ROC")
    axes[0].set_xlabel("False positive rate")
    axes[0].set_ylabel("True positive rate")
    axes[1].set_title("Precision-Recall")
    axes[1].set_xlabel("Recall")
    axes[1].set_ylabel("Precision")
    axes[2].set_title("Score Histograms")
    axes[2].set_xlabel("Standalone probability")
    axes[2].set_ylabel("Density")
    for ax in axes:
        ax.legend(fontsize=8)
    fig.tight_layout()
    comparison_plot = ctx.validation_dir / "stage_comparison_plots.png"
    fig.savefig(comparison_plot, dpi=160)
    plt.close(fig)
    hw_metrics = metrics_from_stage_rows(hw_rows)
    save_checkpoint_plots(
        str(ctx.validation_dir),
        "final",
        canonical_metrics=hw_metrics,
        split_info=f"Candidate: {ctx.candidate_name} | Model: {ctx.model_slot} | Stage: U55C hardware",
        run_params={
            "hls_sweep": ctx.hls_sweep_root.name,
            "board": "u55c",
            "abi": "raw bitstream bytes -> FPGA downsampler -> ap_fixed<16,6> hls4ml stream",
        },
    )
    write_json(
        ctx.validation_dir / "validation_manifest.json",
        {
            "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "fold": ctx.primary_fold,
            "model_slot": ctx.model_slot,
            "hls_sweep": ctx.hls_sweep_root.name,
            "comparison_summary": str(ctx.validation_dir / "comparison_summary.json"),
            "comparison_plot": str(comparison_plot),
            "final_evaluation_plots": str(ctx.validation_dir / "final_evaluation_plots.png"),
            "hardware_per_sample_enriched": str(ctx.u55c_root / "hardware_per_sample_enriched.csv"),
            "raw_reference_max_abs": raw_reference_max_abs,
            "raw_reference_shape": list(raw_reference.shape),
        },
    )
    write_run_index(ctx)
