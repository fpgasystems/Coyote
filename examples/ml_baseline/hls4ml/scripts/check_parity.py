#!/usr/bin/env python3
"""Float HLS vs PyTorch parity check (PyTorch frontend only).

Builds or reloads the per-fold hls4ml project (the C++ compile is cached) and
runs `predict()` on the calibration NCHW tensors saved by
`export_calibration_data.py`.

Writes:
  - artifacts/<cand>/hls/parity/fold_{N}/parity.csv   (per-sample)
  - artifacts/<cand>/hls/parity/fold_{N}/summary.json (aggregate)
  - artifacts/<cand>/hls/parity/all_folds_summary.csv (one row per fold)
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any

import numpy as np
import torch

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline import get_candidate  # noqa: E402
from pipeline.evaluation import load_checkpoint, resolve_device  # noqa: E402
from pipeline.paths import ensure_ml_baseline_on_path  # noqa: E402

ensure_ml_baseline_on_path()

from model import build_model  # noqa: E402


def pytorch_logits(candidate, fold: int, inputs_nchw: np.ndarray) -> np.ndarray:
    device = resolve_device("cpu")
    model = build_model(candidate.model)
    ckpt = candidate.run_dir / f"fold_{fold}" / "final_model.pt"
    load_checkpoint(model, ckpt, device)
    model.to(device).eval()
    x = torch.from_numpy(inputs_nchw).float().to(device)
    with torch.no_grad():
        logits = model(x).cpu().numpy()
    return logits.reshape(logits.shape[0], -1)


def hls_logits(candidate, fold: int, inputs_nchw: np.ndarray, project_dir: Path,
               project_name: str = "cnn_medium_pytorch_hls",
               default_precision: str = "fixed<24,8>"):
    # Regenerates project metadata; hls4ml caches the C++ compile after the
    # first build for a given generated source.
    import inspect
    import hls4ml
    from pipeline.hls import (
        _apply_final_avgpool_precision,
        candidate_input_shape,
        load_candidate_model,
    )

    model = load_candidate_model(candidate, fold, device_arg="cpu")
    config_fn = hls4ml.utils.config_from_pytorch_model
    config_kwargs = {
        "granularity": "name",
        "backend": "Vitis",
        "default_precision": default_precision,
        "default_reuse_factor": 4,
    }
    config_sig = inspect.signature(config_fn)
    if "input_shape" in config_sig.parameters:
        config_kwargs["input_shape"] = candidate_input_shape(candidate)
    if "channels_last_conversion" in config_sig.parameters:
        config_kwargs["channels_last_conversion"] = "internal"
    config = config_fn(model, **config_kwargs)
    config.setdefault("Model", {})
    config["Model"]["Strategy"] = "Resource"
    config["Model"]["ReuseFactor"] = 4
    _apply_final_avgpool_precision(config, default_precision)

    hls_model = hls4ml.converters.convert_from_pytorch_model(
        model,
        output_dir=str(project_dir),
        project_name=project_name,
        backend="Vitis",
        io_type="io_stream",
        hls_config=config,
        part=candidate.target_part,
        clock_period=5.0,
        input_shape=candidate_input_shape(candidate),
    )
    hls_model.compile()
    y = hls_model.predict(np.ascontiguousarray(inputs_nchw.astype(np.float32)))
    y = np.asarray(y).reshape(inputs_nchw.shape[0], -1)
    return hls_model, y


def summarize(a: np.ndarray, b: np.ndarray) -> dict[str, float]:
    diff = a - b
    abs_err = np.abs(diff)
    denom = np.maximum(np.abs(b), 1e-6)
    rel_err = abs_err / denom
    return {
        "mae": float(abs_err.mean()),
        "max_abs": float(abs_err.max()),
        "max_rel": float(rel_err.max()),
        "median_abs": float(np.median(abs_err)),
        "n": int(a.size),
    }


def run_fold(candidate, fold: int, n_samples: int, out_root: Path,
             hls_subdir: str = "pytorch",
             project_name: str = "cnn_medium_pytorch_hls",
             default_precision: str = "fixed<24,8>") -> dict[str, Any]:
    t0 = time.time()
    exports = EXAMPLE_ROOT / f"artifacts/{candidate.name}/exports/fold_{fold}"
    project_dir = EXAMPLE_ROOT / f"artifacts/{candidate.name}/hls/{hls_subdir}/fold_{fold}"
    out_dir = out_root / f"fold_{fold}"
    out_dir.mkdir(parents=True, exist_ok=True)

    inputs = np.load(exports / "inputs_nchw.npy")
    labels = np.load(exports / "labels.npy")
    if n_samples > 0 and n_samples < inputs.shape[0]:
        inputs = inputs[:n_samples]
        labels = labels[:n_samples]

    t_pt = time.time()
    pt = pytorch_logits(candidate, fold, inputs)
    t_pt = time.time() - t_pt

    t_hls = time.time()
    hls_model, hls_out = hls_logits(candidate, fold, inputs, project_dir,
                                    project_name=project_name,
                                    default_precision=default_precision)
    t_hls = time.time() - t_hls

    summary = summarize(hls_out, pt)
    summary["n_samples"] = int(inputs.shape[0])
    summary["t_pytorch_s"] = round(t_pt, 3)
    summary["t_hls_s"] = round(t_hls, 3)
    summary["t_total_s"] = round(time.time() - t0, 3)

    import csv
    with (out_dir / "parity.csv").open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["idx", "label", "pytorch_logit", "hls_logit", "abs_err", "rel_err"])
        for i in range(inputs.shape[0]):
            a = float(pt[i, 0])
            b = float(hls_out[i, 0])
            abs_e = abs(a - b)
            rel_e = abs_e / max(abs(a), 1e-6)
            w.writerow([i, int(labels[i]), a, b, abs_e, rel_e])

    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2))
    return {"fold": fold, **summary, "out_dir": str(out_dir)}, hls_model


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--candidate", default=None)
    ap.add_argument("--folds", type=int, nargs="*", default=[0, 1, 2, 3, 4])
    ap.add_argument("--n-samples", type=int, default=4,
                    help="Samples per fold (simulator is slow for 1024x1024 inputs). Use -1 for all.")
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--hls-subdir", default="pytorch",
                    help="Subdir under artifacts/<cand>/hls/")
    ap.add_argument("--project-name", default=None,
                    help="hls4ml project name used when building")
    ap.add_argument("--default-precision", default="fixed<24,8>",
                    help="Default precision used for the build we're verifying")
    ap.add_argument("--profile-fold", type=int, default=0,
                    help="Fold to profile with hls4ml.profiling.numerical (set -1 to skip)")
    args = ap.parse_args()

    candidate = get_candidate(args.candidate)
    if args.out is None:
        args.out = EXAMPLE_ROOT / "artifacts" / candidate.name / "hls" / "parity"
    if args.project_name is None:
        args.project_name = f"{candidate.name}_pytorch_hls"
    args.out.mkdir(parents=True, exist_ok=True)

    all_rows = []
    last_model_for_profile = None
    for fold in args.folds:
        print(f"[parity] fold {fold} start")
        row, hls_model = run_fold(candidate, fold, args.n_samples, args.out,
                                  hls_subdir=args.hls_subdir,
                                  project_name=args.project_name,
                                  default_precision=args.default_precision)
        print(f"[parity] fold {fold}: mae={row['mae']:.4g} max_abs={row['max_abs']:.4g} "
              f"max_rel={row['max_rel']:.4g} n={row['n_samples']} "
              f"t_pt={row['t_pytorch_s']}s t_hls={row['t_hls_s']}s")
        all_rows.append(row)
        if fold == args.profile_fold:
            last_model_for_profile = hls_model

    import csv
    summary_path = args.out / "all_folds_summary.csv"
    with summary_path.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(all_rows[0].keys()))
        w.writeheader()
        w.writerows(all_rows)
    print(f"[parity] summary: {summary_path}")

    if args.profile_fold >= 0 and last_model_for_profile is not None:
        try:
            import matplotlib
            matplotlib.use("Agg")
            import matplotlib.pyplot as plt
            from hls4ml.model.profiling import numerical

            exports = EXAMPLE_ROOT / f"artifacts/{candidate.name}/exports/fold_{args.profile_fold}"
            X = np.load(exports / "inputs_nchw.npy")[:1].astype(np.float32)
            fig = numerical(hls_model=last_model_for_profile, X=X, plot="boxplot")
            prof_dir = args.out / f"fold_{args.profile_fold}"
            if isinstance(fig, (list, tuple)):
                for i, f in enumerate(fig):
                    p = prof_dir / f"profile_{i}.png"
                    f.savefig(p, bbox_inches="tight")
                    print(f"[parity] profile -> {p}")
                    plt.close(f)
            else:
                p = prof_dir / "profile.png"
                fig.savefig(p, bbox_inches="tight")
                print(f"[parity] profile -> {p}")
                plt.close(fig)
        except Exception as e:  # profiling is best-effort
            print(f"[parity] profiling failed: {type(e).__name__}: {e}")


if __name__ == "__main__":
    main()
