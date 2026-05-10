#!/usr/bin/env python3
"""Probe the upstream CoyoteAccelerator hls4ml example with deterministic random input."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
from pathlib import Path
from typing import Any

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")

DEFAULT_EXAMPLE_ROOT = Path("/mnt/scratch/sdeheredia/main_Coyote/experiments/07_hls4ml")
DEFAULT_MODEL = DEFAULT_EXAMPLE_ROOT / "models/unsw_quantized.h5"
DEFAULT_OUTPUT_PARENT = Path(
    "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/artifacts/coyote_original_example"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("io_parallel", "io_stream"), required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--n-samples", type=int, default=4096)
    parser.add_argument("--seed", type=int, default=1347)
    parser.add_argument("--tolerance", type=float, default=0.20)
    parser.add_argument("--device", default="u55c")
    parser.add_argument("--hls-clock-period", type=float, default=4.0)
    parser.add_argument("--hls-clock-uncertainty", type=float, default=27.0)
    parser.add_argument("--cosim", action="store_true")
    parser.add_argument("--validation", action="store_true")
    parser.add_argument("--bitfile", action="store_true")
    parser.add_argument("--project-name", default=None)
    return parser.parse_args()


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True, default=str))


def write_summary(path: Path, manifest: dict[str, Any]) -> None:
    lines = [
        f"# Coyote Original Example Probe: {manifest['mode']}",
        "",
        f"- stage: `{manifest['stage']}`",
        f"- output: `{manifest['output_dir']}`",
        f"- project: `{manifest['project_dir']}`",
        f"- model: `{manifest['model']}`",
        f"- io_type: `{manifest['mode']}`",
        f"- n_samples: `{manifest['n_samples']}`",
        f"- compile smoke passed: `{manifest.get('compile_smoke', {}).get('passed')}`",
    ]
    report = manifest.get("csynth_report", {})
    if report:
        lines.extend(
            [
                "",
                "## C-Synthesis Report",
                "",
                f"- report exists: `{report.get('exists')}`",
                f"- report path: `{report.get('path')}`",
                f"- total HW-transform instructions: `{report.get('total_hw_transform_instructions')}`",
                f"- `axi_stream_to_data` HW-transform instructions: `{report.get('axi_stream_to_data_hw_transform_instructions')}`",
                f"- model HW-transform instructions: `{report.get('model_hw_transform_instructions')}`",
            ]
        )
    lines.append("")
    path.write_text("\n".join(lines))


def load_model_and_data(model_path: Path, n_samples: int, seed: int):
    import numpy as np
    from qkeras.utils import _add_supported_quantized_objects
    from tensorflow.keras.models import load_model

    if not model_path.exists():
        raise FileNotFoundError(model_path)
    custom_objects: dict[str, Any] = {}
    _add_supported_quantized_objects(custom_objects)
    model = load_model(model_path, custom_objects=custom_objects)
    if tuple(model.input_shape) != (None, 600):
        raise RuntimeError(f"unexpected example model input shape: {model.input_shape}")
    if tuple(model.output_shape) != (None, 1):
        raise RuntimeError(f"unexpected example model output shape: {model.output_shape}")

    rng = np.random.default_rng(seed)
    x = rng.normal(loc=0.0, scale=1.0, size=(n_samples, 600)).astype(np.float32)
    pred_tf = model.predict(x, verbose=0).astype(np.float32)
    return model, x, pred_tf


def convert_model(model, x, pred_tf, output_dir: Path, project_name: str, io_type: str):
    import keras
    import numpy as np
    from hls4ml.converters import convert_from_keras_model
    from hls4ml.utils import config_from_keras_model

    data_dir = output_dir / "data"
    data_dir.mkdir(parents=True, exist_ok=True)
    x_path = data_dir / "X.npy"
    y_path = data_dir / "pred_tf.npy"
    np.save(x_path, np.ascontiguousarray(x))
    np.save(y_path, np.ascontiguousarray(pred_tf.reshape(-1, 1)))

    keras_version = keras.__version__
    keras.__version__ = "2.15.0"
    try:
        hls_config = config_from_keras_model(
            model,
            granularity="name",
            default_precision="ap_fixed<12, 4>",
            backend="CoyoteAccelerator",
        )
        hls_model = convert_from_keras_model(
            model,
            hls_config=hls_config,
            output_dir=str(output_dir / "project"),
            project_name=project_name,
            backend="CoyoteAccelerator",
            io_type=io_type,
            clock_period=4,
            input_data_tb=str(x_path),
            output_data_tb=str(y_path),
        )
    finally:
        keras.__version__ = keras_version

    write_json(output_dir / "full_hls_config.json", hls_config)
    return hls_model, x_path, y_path


def patch_generated_coyote_header(project_dir: Path, project_name: str) -> None:
    wrapper_hpp = project_dir / "src/hls/model_wrapper/model_wrapper.hpp"
    if not wrapper_hpp.exists():
        return
    expected_header = f"firmware/{project_name}.h"
    text = wrapper_hpp.read_text()
    patched = text.replace("firmware/myproject.h", expected_header)
    if patched != text:
        wrapper_hpp.write_text(patched)


def patch_io_stream_wide_input_fifo(project_dir: Path, io_type: str) -> dict[str, Any]:
    if io_type != "io_stream":
        return {"enabled": False, "reason": "not_io_stream"}

    defines_h = project_dir / "src/hls/model_wrapper/firmware/defines.h"
    if not defines_h.exists():
        raise FileNotFoundError(defines_h)

    text = defines_h.read_text()
    pattern = re.compile(r"typedef\s+nnet::array<(.+),\s*600\*1>\s+input_t;")
    patched, count = pattern.subn(r"typedef nnet::array<\1, 300*1> input_t;", text)
    if count != 1:
        raise RuntimeError(f"failed to narrow io_stream input_t in {defines_h}")
    defines_h.write_text(patched)

    return {
        "enabled": True,
        "path": str(defines_h),
        "old_input_t": "nnet::array<ap_fixed<12,4>, 600*1>",
        "new_input_t": "nnet::array<ap_fixed<12,4>, 300*1>",
        "reason": "make the io_stream input FIFO element 3600 bits instead of 7200 bits, below Vitis' 4096-bit aggregate limit",
    }


def compile_smoke(hls_model, x, pred_tf, tolerance: float) -> dict[str, Any]:
    import numpy as np

    pred_hls = np.asarray(hls_model.predict(np.ascontiguousarray(x))).reshape(pred_tf.shape)
    cpu = np.asarray(pred_tf, dtype=np.float64).reshape(-1)
    hls = np.asarray(pred_hls, dtype=np.float64).reshape(-1)
    abs_diff = np.abs(hls - cpu)
    return {
        "passed": bool(np.all(abs_diff <= tolerance)),
        "tolerance": float(tolerance),
        "n": int(cpu.size),
        "mae": float(abs_diff.mean()) if abs_diff.size else 0.0,
        "max_abs": float(abs_diff.max()) if abs_diff.size else 0.0,
    }


def parse_int(value: str) -> int:
    return int(value.replace(",", "").replace("*", "").strip())


def parse_csynth_report(project_dir: Path, project_name: str) -> dict[str, Any]:
    report = (
        project_dir
        / f"build/{project_name}_cyt_hw/{project_name}_config_0/user_c0_0/hdl/ext/model_wrapper_hls/"
        "model_wrapper_c0_0/solution1/syn/report/csynth_design_size.rpt"
    )
    result: dict[str, Any] = {"path": str(report), "exists": report.exists()}
    if not report.exists():
        return result

    text = report.read_text(errors="replace")
    result["key_lines"] = [
        line
        for line in text.splitlines()
        if "axi_stream_to_data" in line
        or f"+ {project_name}" in line
        or "| + model_wrapper" in line
        or "| HW Transforms" in line
    ]

    for line in text.splitlines():
        if "| HW Transforms |" in line and "(2) optimizations" in line:
            fields = [field.strip() for field in line.strip("|").split("|")]
            if len(fields) >= 3:
                result["total_hw_transform_instructions"] = parse_int(fields[2])
        if "axi_stream_to_data" in line:
            fields = [field.strip() for field in line.strip("|").split("|")]
            if len(fields) >= 7:
                result["axi_stream_to_data_hw_transform_instructions"] = parse_int(fields[6])
        if f"+ {project_name}" in line:
            fields = [field.strip() for field in line.strip("|").split("|")]
            if len(fields) >= 7:
                result["model_hw_transform_instructions"] = parse_int(fields[6])

    reflow = (
        project_dir
        / f"build/{project_name}_cyt_hw/{project_name}_config_0/user_c0_0/hdl/ext/model_wrapper_hls/"
        "model_wrapper_c0_0/solution1/.autopilot/db/a.g.ld.0.bc.clang.reflow.err.log"
    )
    result["reflow_log"] = str(reflow)
    if reflow.exists():
        result["unroll_lines"] = [
            line
            for line in reflow.read_text(errors="replace").splitlines()
            if "axi_stream_to_data" in line and "Unrolling loop" in line
        ][:50]
    return result


def main() -> None:
    args = parse_args()
    output_dir = args.output_dir.resolve()
    project_name = args.project_name or f"unsw_{args.mode}"
    project_dir = output_dir / "project"
    if project_dir.exists() and any(project_dir.iterdir()):
        raise RuntimeError(f"refusing to reuse non-empty project directory: {project_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)

    model, x, pred_tf = load_model_and_data(args.model.resolve(), args.n_samples, args.seed)
    hls_model, x_path, y_path = convert_model(model, x, pred_tf, output_dir, project_name, args.mode)
    hls_model.write()
    patch_generated_coyote_header(project_dir, project_name)
    generated_patches = {
        "wide_io_stream_input_fifo": patch_io_stream_wide_input_fifo(project_dir, args.mode),
    }
    hls_model._compile()
    smoke = compile_smoke(hls_model, x, pred_tf, args.tolerance)

    manifest = {
        "stage": "compiled",
        "mode": args.mode,
        "model": str(args.model.resolve()),
        "output_dir": str(output_dir),
        "project_dir": str(project_dir),
        "project_name": project_name,
        "x_path": str(x_path),
        "pred_tf_path": str(y_path),
        "n_samples": int(args.n_samples),
        "seed": int(args.seed),
        "compile_smoke": smoke,
        "generated_patches": generated_patches,
    }
    write_json(output_dir / "manifest.json", manifest)
    write_summary(output_dir / "summary.md", manifest)

    hls_model.build(
        device=args.device,
        csim=True,
        synth=True,
        cosim=args.cosim,
        validation=args.validation,
        timing_opt=True,
        bitfile=args.bitfile,
        hls_clock_period=args.hls_clock_period,
        hls_clock_uncertainty=args.hls_clock_uncertainty,
    )

    report = parse_csynth_report(project_dir, project_name)
    bitstream = project_dir / f"build/{project_name}_cyt_hw/bitstreams/cyt_top.bit"
    host_lib = project_dir / f"build/{project_name}_cyt_sw/lib/libCoyoteInference.so"
    manifest.update(
        {
            "stage": "built",
            "csynth_report": report,
            "bitstream": str(bitstream),
            "bitstream_exists": bitstream.exists(),
            "host_library": str(host_lib),
            "host_library_exists": host_lib.exists(),
        }
    )
    if args.bitfile and not bitstream.exists():
        manifest["stage"] = "failed_missing_bitstream"
        write_json(output_dir / "manifest.json", manifest)
        write_summary(output_dir / "summary.md", manifest)
        raise RuntimeError(f"missing expected bitstream: {bitstream}")
    if not host_lib.exists():
        manifest["stage"] = "failed_missing_host_library"
        write_json(output_dir / "manifest.json", manifest)
        write_summary(output_dir / "summary.md", manifest)
        raise RuntimeError(f"missing expected host library: {host_lib}")

    write_json(output_dir / "manifest.json", manifest)
    write_summary(output_dir / "summary.md", manifest)
    print(f"[done] mode={args.mode}")
    print(f"[done] output_dir={output_dir}")
    print(f"[done] manifest={output_dir / 'manifest.json'}")


if __name__ == "__main__":
    main()
