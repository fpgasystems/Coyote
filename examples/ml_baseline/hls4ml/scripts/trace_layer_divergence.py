#!/usr/bin/env python3
"""Compare PyTorch activations against hls4ml layer traces for one precision point."""

from __future__ import annotations

import argparse
import csv
import inspect
import json
import sys
from pathlib import Path
from typing import Any

import numpy as np
import torch

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline import get_candidate  # noqa: E402
from pipeline.hls import (  # noqa: E402
    _apply_accum_precision,
    _apply_dense_precision,
    _apply_pool_accum_precision,
    candidate_input_shape,
    load_candidate_model,
)


PYTORCH_LAYER_ORDER = [
    ("features_0", "features.0"),
    ("features_1", "features.1"),
    ("features_2", "features.2"),
    ("features_3", "features.3"),
    ("features_4", "features.4"),
    ("features_5", "features.5"),
    ("features_6", "features.6"),
    ("features_7", "features.7"),
    ("features_8", "features.8"),
    ("features_9", "features.9"),
    ("features_10", "features.10"),
    ("features_11", "features.11"),
    ("features_12", "features.12"),
    ("features_13", "features.13"),
    ("features_14", "features.14"),
    ("gap", "gap"),
    ("classifier", "classifier"),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", default="cnn_small_hls_opt_img512")
    parser.add_argument("--fold", type=int, default=0)
    parser.add_argument("--sample-index", type=int, default=24)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--default-precision", required=True)
    parser.add_argument("--dense-precision", default=None)
    parser.add_argument("--accum-precision", default=None)
    parser.add_argument("--pool-accum-precision", default="fixed<40,20>")
    parser.add_argument("--reuse-factor", type=int, default=8)
    parser.add_argument("--project-name", default=None)
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--out", type=Path, default=None)
    return parser.parse_args()


def module_by_name(model: torch.nn.Module, name: str) -> torch.nn.Module:
    modules = dict(model.named_modules())
    return modules[name]


def pytorch_activations(model: torch.nn.Module, x: np.ndarray) -> dict[str, np.ndarray]:
    activations: dict[str, np.ndarray] = {}
    handles = []

    for hls_name, pt_name in PYTORCH_LAYER_ORDER:
        if pt_name == "classifier":
            continue
        module = module_by_name(model, pt_name)

        def hook(_module, _inputs, output, hls_name=hls_name):
            activations[hls_name] = output.detach().cpu().numpy()

        handles.append(module.register_forward_hook(hook))

    with torch.no_grad():
        tensor = torch.from_numpy(x).float()
        out = model(tensor)
        activations["classifier"] = out.detach().cpu().numpy()

    for handle in handles:
        handle.remove()

    return activations


def build_trace_model(args: argparse.Namespace, candidate) -> Any:
    import hls4ml

    model = load_candidate_model(candidate, args.fold, device_arg="cpu")
    config_fn = hls4ml.utils.config_from_pytorch_model
    config_kwargs = {
        "granularity": "name",
        "backend": "Vitis",
        "default_precision": args.default_precision,
        "default_reuse_factor": args.reuse_factor,
    }
    config_sig = inspect.signature(config_fn)
    if "input_shape" in config_sig.parameters:
        config_kwargs["input_shape"] = candidate_input_shape(candidate)
    if "channels_last_conversion" in config_sig.parameters:
        config_kwargs["channels_last_conversion"] = "internal"
    config = config_fn(model, **config_kwargs)
    config.setdefault("Model", {})
    config["Model"]["Strategy"] = "Resource"
    config["Model"]["ReuseFactor"] = args.reuse_factor
    config["Model"]["TraceOutput"] = True
    _apply_accum_precision(config, args.accum_precision)
    _apply_pool_accum_precision(model, config, args.default_precision, args.pool_accum_precision)
    _apply_dense_precision(model, config, args.dense_precision)
    for layer in config.get("LayerName", {}).values():
        layer["Trace"] = True

    project_name = args.project_name or f"{candidate.name}_{args.tag}_trace_hls"
    output_dir = args.output_dir or EXAMPLE_ROOT / "artifacts" / candidate.name / "hls" / f"trace_{args.tag}" / f"fold_{args.fold}"
    hls_model = hls4ml.converters.convert_from_pytorch_model(
        model,
        output_dir=str(output_dir),
        project_name=project_name,
        backend="Vitis",
        io_type="io_stream",
        hls_config=config,
        part=candidate.target_part,
        clock_period=5.0,
        input_shape=candidate_input_shape(candidate),
    )
    hls_model.compile()
    return model, hls_model, output_dir


def squeeze_batch(arr: np.ndarray) -> np.ndarray:
    arr = np.asarray(arr)
    if arr.ndim > 0 and arr.shape[0] == 1:
        return arr[0]
    return arr


def align_hls_to_pytorch(hls: np.ndarray, pt: np.ndarray) -> tuple[np.ndarray, str]:
    h = squeeze_batch(np.asarray(hls))
    p = squeeze_batch(np.asarray(pt))

    if h.shape == p.shape:
        return h, "same"

    if p.ndim == 3:
        chw = p.shape
        hwc = (p.shape[1], p.shape[2], p.shape[0])
        if h.shape == hwc:
            return np.transpose(h, (2, 0, 1)), "hwc_to_chw"
        if h.size == p.size:
            return h.reshape(hwc).transpose(2, 0, 1), "flat_hwc_to_chw"

    if p.ndim == 1 and h.size == p.size:
        return h.reshape(p.shape), "flat"

    if p.ndim == 2 and h.size == p.size:
        return h.reshape(p.shape), "flat"

    return h.reshape(-1), f"unaligned_hls{h.shape}_pt{p.shape}"


def summarize_layer(hls_name: str, pt: np.ndarray, hls: np.ndarray) -> dict[str, Any]:
    aligned, alignment = align_hls_to_pytorch(hls, pt)
    p = squeeze_batch(pt)
    if aligned.shape != p.shape:
        p_cmp = p.reshape(-1)
        h_cmp = aligned.reshape(-1)
        n = min(p_cmp.size, h_cmp.size)
        p_cmp = p_cmp[:n]
        h_cmp = h_cmp[:n]
    else:
        p_cmp = p.reshape(-1)
        h_cmp = aligned.reshape(-1)

    diff = h_cmp - p_cmp
    abs_diff = np.abs(diff)
    sign_mask = np.signbit(h_cmp) != np.signbit(p_cmp)
    pt_range = float(np.max(p_cmp) - np.min(p_cmp)) if p_cmp.size else 0.0
    return {
        "layer": hls_name,
        "alignment": alignment,
        "shape_pt": list(p.shape),
        "shape_hls": list(squeeze_batch(np.asarray(hls)).shape),
        "pt_min": float(np.min(p_cmp)),
        "pt_max": float(np.max(p_cmp)),
        "pt_mean": float(np.mean(p_cmp)),
        "hls_min": float(np.min(h_cmp)),
        "hls_max": float(np.max(h_cmp)),
        "hls_mean": float(np.mean(h_cmp)),
        "mae": float(np.mean(abs_diff)),
        "max_abs": float(np.max(abs_diff)),
        "mae_over_pt_range": float(np.mean(abs_diff) / max(pt_range, 1e-9)),
        "sign_mismatch_frac": float(np.mean(sign_mask)),
        "n": int(p_cmp.size),
    }


def main() -> None:
    args = parse_args()
    candidate = get_candidate(args.candidate)
    exports = EXAMPLE_ROOT / "artifacts" / candidate.name / "exports" / f"fold_{args.fold}"
    x_nchw = np.load(exports / "inputs_nchw.npy")[args.sample_index : args.sample_index + 1]
    x_nhwc = np.load(exports / "inputs_nhwc.npy")[args.sample_index : args.sample_index + 1]
    labels = np.load(exports / "labels.npy")

    model, hls_model, project_dir = build_trace_model(args, candidate)
    pt_trace = pytorch_activations(model, x_nchw)
    hls_pred, hls_trace = hls_model.trace(np.ascontiguousarray(x_nhwc.astype(np.float32)))

    rows = []
    for hls_name, _pt_name in PYTORCH_LAYER_ORDER:
        if hls_name not in pt_trace or hls_name not in hls_trace:
            continue
        rows.append(summarize_layer(hls_name, pt_trace[hls_name], hls_trace[hls_name]))

    out_dir = args.out or EXAMPLE_ROOT / "artifacts" / candidate.name / "hls" / "trace_reports"
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / f"{args.tag}_fold{args.fold}_sample{args.sample_index}.csv"
    json_path = out_dir / f"{args.tag}_fold{args.fold}_sample{args.sample_index}.json"
    if rows:
        with csv_path.open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)

    pt_out = pt_trace["classifier"].reshape(-1)
    hls_out = np.asarray(hls_pred).reshape(-1)
    payload = {
        "candidate": candidate.name,
        "fold": args.fold,
        "sample_index": args.sample_index,
        "label": int(labels[args.sample_index]),
        "tag": args.tag,
        "default_precision": args.default_precision,
        "dense_precision": args.dense_precision,
        "accum_precision": args.accum_precision,
        "pool_accum_precision": args.pool_accum_precision,
        "reuse_factor": args.reuse_factor,
        "project_dir": str(project_dir),
        "pytorch_output": pt_out.tolist(),
        "hls_output": hls_out.tolist(),
        "rows": rows,
    }
    json_path.write_text(json.dumps(payload, indent=2))

    print(f"trace_csv={csv_path}")
    print(f"trace_json={json_path}")
    print(f"sample={args.sample_index} label={payload['label']} pytorch={pt_out.tolist()} hls={hls_out.tolist()}")
    for row in rows:
        print(
            f"{row['layer']:>12} mae={row['mae']:.6g} "
            f"max={row['max_abs']:.6g} sign={row['sign_mismatch_frac']:.3f} "
            f"pt=[{row['pt_min']:.4g},{row['pt_max']:.4g}] "
            f"hls=[{row['hls_min']:.4g},{row['hls_max']:.4g}]"
        )


if __name__ == "__main__":
    main()
