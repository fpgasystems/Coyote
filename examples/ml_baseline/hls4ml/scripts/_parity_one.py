"""One-off parity test forcing explicit precision (not 'auto')."""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import onnx
import torch

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline import get_candidate  # noqa: E402
from pipeline.evaluation import load_checkpoint, resolve_device  # noqa: E402
from pipeline.hls import _patch_onnx_modelgraph_compat  # noqa: E402
from pipeline.paths import ensure_ml_baseline_on_path  # noqa: E402

ensure_ml_baseline_on_path()
from model import build_model  # noqa: E402


def force_explicit(cfg: dict, precision: str, accum: str) -> None:
    """Replace every 'auto' with explicit ap_fixed strings; accum gets wider precision."""
    layer_cfg = cfg.get("LayerName", {})
    for _name, layer in layer_cfg.items():
        prec = layer.get("Precision")
        if isinstance(prec, dict):
            for k, v in prec.items():
                if v == "auto":
                    prec[k] = accum if k == "accum" else precision
        elif prec == "auto":
            layer["Precision"] = precision


def main():
    precision = sys.argv[1] if len(sys.argv) > 1 else "fixed<24,8>"
    accum = sys.argv[2] if len(sys.argv) > 2 else "fixed<32,20>"
    fold = 0
    candidate = get_candidate(None)

    exports = EXAMPLE_ROOT / f"artifacts/{candidate.name}/exports/fold_{fold}"
    inputs = np.load(exports / "inputs_nchw.npy")[:2].astype(np.float32)

    device = resolve_device("cpu")
    model = build_model(candidate.model)
    ckpt = candidate.run_dir / f"fold_{fold}" / "final_model.pt"
    load_checkpoint(model, ckpt, device)
    model.to(device).eval()
    with torch.no_grad():
        pt = model(torch.from_numpy(inputs)).cpu().numpy().reshape(2, -1)
    print(f"[pt ] logits: {pt.flatten()}")

    import hls4ml

    _patch_onnx_modelgraph_compat(hls4ml)
    qonnx_path = EXAMPLE_ROOT / f"artifacts/{candidate.name}/qonnx/fold_{fold}/final_clean.onnx"
    onnx_model = onnx.load(str(qonnx_path))

    config = hls4ml.utils.config_from_onnx_model(
        onnx_model, granularity="name", backend="Vitis",
        default_precision=precision, default_reuse_factor=4,
    )
    force_explicit(config, precision, accum)
    # GlobalAveragePool layer needs a wide accum too (sums 64*64*29 ≈ 120K)
    gavg = config.get("LayerName", {}).get("GlobalAveragePool_0")
    if gavg is not None:
        gavg["Precision"] = {"result": precision, "accum": accum}
    print(f"[cfg] precision={precision} accum={accum}")
    config.setdefault("Model", {})
    config["Model"]["Strategy"] = "Resource"
    config["Model"]["ReuseFactor"] = 4
    config["Model"]["Precision"] = precision
    # Enable tracing on all layers
    for _n, layer in config.get("LayerName", {}).items():
        layer["Trace"] = True

    out_dir = EXAMPLE_ROOT / f"artifacts/{candidate.name}/hls/onnx_explicit/fold_{fold}"
    out_dir.mkdir(parents=True, exist_ok=True)
    hls_model = hls4ml.converters.convert_from_onnx_model(
        onnx_model, output_dir=str(out_dir),
        project_name="cnn_medium_onnx_explicit_hls",
        backend="Vitis", io_type="io_stream",
        hls_config=config, part=candidate.target_part, clock_period=5.0,
    )
    hls_model.compile()
    # Trace per-layer
    try:
        traced, _ = hls4ml.model.profiling.get_ymodel_keras  # no-op ref
    except Exception:
        pass
    try:
        pred, trace = hls_model.trace(np.ascontiguousarray(inputs[:1]))
        print("[trace] layer outputs (min, max, mean):")
        for name, arr in trace.items():
            arr = np.asarray(arr).ravel()
            if arr.size:
                print(f"  {name:30s} shape={arr.size:8d} min={arr.min():+.4f} max={arr.max():+.4f} mean={arr.mean():+.4f}")
    except Exception as e:
        print(f"[trace] failed: {type(e).__name__}: {e}")
    # Try NHWC-ordered input (io_stream typically expects channels-last)
    inputs_nhwc = np.ascontiguousarray(np.transpose(inputs, (0, 2, 3, 1)))
    print(f"[dbg] NHWC shape: {inputs_nhwc.shape}")
    y_nhwc = np.asarray(hls_model.predict(inputs_nhwc)).reshape(2, -1)
    print(f"[hls NHWC] logits ({precision}): {y_nhwc.flatten()}")
    y_nchw = np.asarray(hls_model.predict(np.ascontiguousarray(inputs))).reshape(2, -1)
    print(f"[hls NCHW] logits ({precision}): {y_nchw.flatten()}")
    print(f"[pt ] logits: {pt.flatten()}")
    print(f"[err NHWC] mae={np.abs(pt-y_nhwc).mean():.4g}  max_abs={np.abs(pt-y_nhwc).max():.4g}")
    print(f"[err NCHW] mae={np.abs(pt-y_nchw).mean():.4g}  max_abs={np.abs(pt-y_nchw).max():.4g}")


if __name__ == "__main__":
    main()
