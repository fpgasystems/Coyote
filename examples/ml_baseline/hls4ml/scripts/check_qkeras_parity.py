#!/usr/bin/env python3
"""Check trained QKeras model parity against its hls4ml emulation."""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import time
from pathlib import Path

import numpy as np

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline import get_candidate  # noqa: E402
from pipeline.qkeras_qat import (  # noqa: E402
    DEFAULT_OUTPUT_PRECISION,
    DEFAULT_POOL_ACCUM_PRECISION,
    build_qkeras_hls_project,
    compile_qkeras_hls_model,
    load_trained_qkeras_model,
    qkeras_fold_dir,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", default="cnn_small_hls_opt_img512")
    parser.add_argument("--quantizer-tag", default="w6_a8")
    parser.add_argument("--fold", type=int, default=0)
    parser.add_argument("--n-samples", type=int, default=48)
    parser.add_argument("--hls-dir", type=Path, default=None,
                        help="Existing hls4ml project dir; generated when absent")
    parser.add_argument("--out", type=Path, default=None)
    parser.add_argument("--project-name", default=None)
    parser.add_argument("--reuse-factor", type=int, default=8)
    parser.add_argument("--accum-precision", default=None)
    parser.add_argument("--output-precision", default=DEFAULT_OUTPUT_PRECISION)
    parser.add_argument("--pool-accum-precision", default=DEFAULT_POOL_ACCUM_PRECISION)
    parser.add_argument("--qat-output-root", type=Path, default=None)
    return parser.parse_args()


def summarize(hls_logits: np.ndarray, keras_logits: np.ndarray) -> dict:
    diff = hls_logits - keras_logits
    abs_err = np.abs(diff)
    denom = np.maximum(np.abs(keras_logits), 1e-6)
    sign_mismatches = int(np.sum((hls_logits >= 0.0) != (keras_logits >= 0.0)))
    return {
        "mae": float(abs_err.mean()),
        "max_abs": float(abs_err.max()),
        "max_rel": float((abs_err / denom).max()),
        "median_abs": float(np.median(abs_err)),
        "sign_mismatches": sign_mismatches,
        "n": int(keras_logits.size),
    }


def main() -> None:
    args = parse_args()
    candidate = get_candidate(args.candidate)
    project_name = args.project_name or f"{candidate.name}_{args.quantizer_tag}_qkeras_hls"
    hls_dir = args.hls_dir or (
        EXAMPLE_ROOT / "artifacts" / candidate.name / "hls" / f"qkeras_{args.quantizer_tag}" / f"fold_{args.fold}"
    )
    out_dir = args.out or (
        EXAMPLE_ROOT / "artifacts" / candidate.name / "hls" / f"qkeras_parity_{args.quantizer_tag}" / f"fold_{args.fold}"
    )
    out_dir.mkdir(parents=True, exist_ok=True)

    exports = EXAMPLE_ROOT / "artifacts" / candidate.name / "exports" / f"fold_{args.fold}"
    x_path = exports / "inputs_nhwc.npy"
    label_path = exports / "labels.npy"
    if not x_path.exists():
        raise FileNotFoundError(f"Missing calibration input {x_path}; run export_calibration_data.py first")
    x = np.load(x_path).astype(np.float32)
    labels = np.load(label_path)
    if args.n_samples > 0:
        x = x[: args.n_samples]
        labels = labels[: args.n_samples]

    keras_model = load_trained_qkeras_model(
        candidate,
        args.quantizer_tag,
        qkeras_fold_dir(candidate, args.quantizer_tag, args.fold, args.qat_output_root),
    )
    t0 = time.time()
    keras_logits = np.asarray(keras_model.predict(x, verbose=0)).reshape(-1)
    t_keras = time.time() - t0

    if not (hls_dir / "hls4ml_config.yml").exists():
        build_qkeras_hls_project(
            candidate,
            quantizer_tag=args.quantizer_tag,
            fold=args.fold,
            output_dir=hls_dir,
            project_name=project_name,
            qat_output_root=args.qat_output_root,
            reuse_factor=args.reuse_factor,
            accum_precision=args.accum_precision,
            output_precision=args.output_precision,
            pool_accum_precision=args.pool_accum_precision,
        )
    hls_model = compile_qkeras_hls_model(
        candidate,
        quantizer_tag=args.quantizer_tag,
        fold=args.fold,
        output_dir=hls_dir,
        project_name=project_name,
        qat_output_root=args.qat_output_root,
        reuse_factor=args.reuse_factor,
        accum_precision=args.accum_precision,
        output_precision=args.output_precision,
        pool_accum_precision=args.pool_accum_precision,
    )
    t0 = time.time()
    hls_logits = np.asarray(hls_model.predict(np.ascontiguousarray(x))).reshape(-1)
    t_hls = time.time() - t0

    summary = summarize(hls_logits, keras_logits)
    summary.update(
        {
            "candidate": candidate.name,
            "quantizer_tag": args.quantizer_tag,
            "fold": args.fold,
            "n_samples": int(x.shape[0]),
            "t_keras_s": round(t_keras, 3),
            "t_hls_s": round(t_hls, 3),
            "hls_dir": str(hls_dir),
            "accum_precision": args.accum_precision,
            "output_precision": args.output_precision,
            "pool_accum_precision": args.pool_accum_precision,
        }
    )

    with (out_dir / "parity.csv").open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["idx", "label", "keras_logit", "hls_logit", "abs_err", "rel_err"])
        for idx, (label, k_logit, h_logit) in enumerate(zip(labels, keras_logits, hls_logits)):
            abs_err = abs(float(h_logit) - float(k_logit))
            rel_err = abs_err / max(abs(float(k_logit)), 1e-6)
            writer.writerow([idx, int(label), float(k_logit), float(h_logit), abs_err, rel_err])

    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True))
    print(
        f"[qkeras-parity] mae={summary['mae']:.5g} max_abs={summary['max_abs']:.5g} "
        f"sign_mismatches={summary['sign_mismatches']} out={out_dir}"
    )


if __name__ == "__main__":
    main()
