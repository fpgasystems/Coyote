#!/usr/bin/env python3
"""Validate zero-in Keras CPU predictions against CoyoteAccelerator FPGA output."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from common import (
    DEFAULT_CONFIG,
    DEFAULT_INPUT_ROOT,
    DEFAULT_RUN_ROOT,
    DEFAULT_SPLIT_CSV,
    load_zero_in_arrays,
    load_zero_in_model,
    load_zero_in_raw_samples,
    prepare_zero_in_raw_reference,
    logit_validation_summary,
    prediction_rows,
    write_csv,
    write_json,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True, help="build_manifest.json from zero_in_synth.py")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--run-root", type=Path, default=DEFAULT_RUN_ROOT)
    parser.add_argument("--input-root", type=Path, default=DEFAULT_INPUT_ROOT)
    parser.add_argument("--split-csv", type=Path, default=DEFAULT_SPLIT_CSV)
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--n-samples", type=int, default=48)
    parser.add_argument("--tolerance", type=float, default=0.20)
    parser.add_argument("--program", action="store_true", help="Program the HACC FPGA before inference")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    import numpy as np

    manifest = json.loads(args.manifest.read_text())
    project_dir = Path(manifest["project_dir"]).resolve()
    project_name = str(manifest["project_name"])
    output_dir = Path(manifest["output_dir"]).resolve()
    validation_dir = output_dir / "fpga_validation"
    validation_dir.mkdir(parents=True, exist_ok=True)

    _ctx, model = load_zero_in_model(args.config.resolve(), args.run_root.resolve(), fold=0)
    x, labels, x_path, labels_path = load_zero_in_arrays(args.input_root.resolve(), n_samples=args.n_samples)
    raw_arrays, raw_labels, raw_samples, split_csv = load_zero_in_raw_samples(args.split_csv.resolve(), n_samples=args.n_samples)
    raw_reference = prepare_zero_in_raw_reference(raw_arrays)
    if raw_reference.shape != x.shape:
        raise RuntimeError(f"raw reference shape {raw_reference.shape} != prepared x shape {x.shape}")
    raw_reference_max_abs = float(np.max(np.abs(raw_reference - x))) if x.size else 0.0
    if raw_reference_max_abs > 1e-7:
        raise RuntimeError(f"raw downsampling reference does not match prepared inputs: max_abs={raw_reference_max_abs}")
    if not np.array_equal(raw_labels, labels):
        raise RuntimeError("raw split labels do not match prepared input labels")
    if len(x) % args.batch_size != 0:
        raise RuntimeError(f"{len(x)} samples is not divisible by batch size {args.batch_size}")

    # Importing a top-level hls4ml module first avoids a backend package
    # initialization cycle in the checked-out CoyoteAccelerator branch.
    from hls4ml.converters import convert_from_keras_model as _hls4ml_import_order_guard  # noqa: F401
    from hls4ml.backends.coyote_accelerator.coyote_accelerator_overlay import CoyoteOverlay

    overlay = CoyoteOverlay(str(project_dir), project_name=project_name)
    if args.program:
        overlay.program_hacc_fpga()

    cpu_batches = []
    fpga_batches = []
    n_batches = len(x) // args.batch_size
    x_batches = x.reshape((n_batches, args.batch_size, *x.shape[1:]))
    raw_batches = [raw_arrays[i * args.batch_size : (i + 1) * args.batch_size] for i in range(n_batches)]
    for batch_idx, x_batch in enumerate(x_batches):
        cpu = np.asarray(model.predict(x_batch, verbose=0)).reshape(args.batch_size, 1)
        fpga = np.asarray(overlay.predict_raw(raw_batches[batch_idx], (1,), args.batch_size)).reshape(args.batch_size, 1)
        cpu_batches.append(cpu)
        fpga_batches.append(fpga)
        print(f"[validate] batch {batch_idx + 1}/{n_batches}")

    cpu_logits = np.concatenate(cpu_batches, axis=0).reshape(-1)
    fpga_logits = np.concatenate(fpga_batches, axis=0).reshape(-1)
    summary = logit_validation_summary(cpu_logits, fpga_logits, labels, args.tolerance)
    summary.update(
        {
            "project_dir": str(project_dir),
            "project_name": project_name,
            "x_path": str(x_path),
            "labels_path": str(labels_path),
            "split_csv": str(split_csv),
            "raw_input_mode": True,
            "raw_reference_max_abs": raw_reference_max_abs,
            "raw_samples": [
                {
                    "sample_id": sample["sample_id"],
                    "path": str(sample["path"]),
                    "raw_len": int(sample["raw_len"]),
                    "label": int(sample["label"]),
                }
                for sample in raw_samples
            ],
            "batch_size": int(args.batch_size),
            "programmed_fpga": bool(args.program),
        }
    )
    write_json(validation_dir / "validation_summary.json", summary)
    write_csv(validation_dir / "predictions.csv", prediction_rows(cpu_logits, fpga_logits, labels))
    print(json.dumps(summary, indent=2, sort_keys=True))
    if not summary["passed"]:
        raise RuntimeError(f"FPGA validation failed: {summary}")


if __name__ == "__main__":
    main()
