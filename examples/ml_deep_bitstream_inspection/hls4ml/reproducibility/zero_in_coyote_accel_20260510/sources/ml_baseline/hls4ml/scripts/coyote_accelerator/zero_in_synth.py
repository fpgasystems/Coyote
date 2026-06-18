#!/usr/bin/env python3
"""Build the zero-in model with the hls4ml CoyoteAccelerator backend."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from common import (
    DEFAULT_CONFIG,
    DEFAULT_INPUT_ROOT,
    DEFAULT_OUTPUT_PARENT,
    DEFAULT_RUN_ROOT,
    load_zero_in_arrays,
    load_zero_in_model,
    logit_validation_summary,
    prediction_rows,
    timestamp,
    write_csv,
    write_json,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--run-root", type=Path, default=DEFAULT_RUN_ROOT)
    parser.add_argument("--input-root", type=Path, default=DEFAULT_INPUT_ROOT)
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--project-name", default="zero_in_coyote_accel")
    parser.add_argument("--n-samples", type=int, default=48)
    parser.add_argument("--tolerance", type=float, default=0.20)
    parser.add_argument("--device", default="u55c")
    parser.add_argument("--hls-clock-period", type=float, default=4.0)
    parser.add_argument("--hls-clock-uncertainty", type=float, default=27.0)
    parser.add_argument("--no-bitfile", action="store_true", help="Stop after Coyote project synthesis target")
    parser.add_argument(
        "--disable-adapter-pipeline-fix",
        action="store_true",
        help="Do not patch the generated AXI stream input adapter pipeline pragma",
    )
    return parser.parse_args()


def convert_model(ctx, model, x, keras_logits, output_dir: Path, project_name: str):
    import keras
    import numpy as np
    from hls4ml.converters import convert_from_keras_model
    from hls4ml.utils import config_from_keras_model
    from pipeline.part2_train import weight_sparsity

    tb_dir = output_dir / "tb_data_np"
    tb_dir.mkdir(parents=True, exist_ok=True)
    input_tb = tb_dir / "input.npy"
    output_tb = tb_dir / "keras_logits.npy"
    np.save(input_tb, np.ascontiguousarray(x))
    np.save(output_tb, np.ascontiguousarray(keras_logits.reshape(-1, 1).astype(np.float32)))

    keras_version = keras.__version__
    keras.__version__ = "2.15.0"
    try:
        hls_cfg = ctx.config["hls"]
        hls_config = config_from_keras_model(model, granularity="name", backend="CoyoteAccelerator")
        hls_config.setdefault("Model", {})
        hls_config["Model"]["Strategy"] = str(hls_cfg["strategy"])
        hls_config["Model"]["ReuseFactor"] = int(hls_cfg["reuse_factor"])
        _, _, _, strategy_overrides = weight_sparsity(ctx, model)
        for layer_name, layer_cfg in hls_config.get("LayerName", {}).items():
            layer_cfg["ReuseFactor"] = int(hls_cfg["reuse_factor"])
            layer_cfg["Strategy"] = strategy_overrides.get(layer_name, str(hls_cfg["strategy"]))
            precision = layer_cfg.get("Precision")
            if hls_cfg.get("accum_precision") and isinstance(precision, dict) and "accum" in precision:
                precision["accum"] = hls_cfg["accum_precision"]
        if "output_dense" in hls_config.get("LayerName", {}) and hls_cfg.get("output_precision") is not None:
            hls_config["LayerName"]["output_dense"].setdefault("Precision", {})["result"] = hls_cfg["output_precision"]
        if "gap" in hls_config.get("LayerName", {}) and hls_cfg.get("pool_accum_precision") is not None:
            hls_config["LayerName"]["gap"].setdefault("Precision", {})["accum"] = hls_cfg["pool_accum_precision"]
        hls_config.setdefault("Model", {})["Trace"] = False
        hls_model = convert_from_keras_model(
            model,
            hls_config=hls_config,
            output_dir=str(output_dir / "project"),
            project_name=project_name,
            backend="CoyoteAccelerator",
            io_type="io_stream",
            clock_period=4,
            input_data_tb=str(input_tb),
            output_data_tb=str(output_tb),
        )
    finally:
        keras.__version__ = keras_version
    (output_dir / "full_hls_config.json").write_text(json.dumps(hls_config, indent=2, sort_keys=True, default=str))
    return hls_model, hls_config


def patch_axi_stream_input_adapter(project_dir: Path) -> dict[str, str]:
    adapter_h = project_dir / "src/hls/model_wrapper/firmware/nnet_utils/nnet_axi_utils_stream.h"
    if not adapter_h.exists():
        raise FileNotFoundError(adapter_h)

    text = adapter_h.read_text()
    fn_start = text.find("void axi_stream_to_data")
    if fn_start < 0:
        raise RuntimeError(f"could not find axi_stream_to_data function boundaries in {adapter_h}")
    next_template = text.find("\ntemplate ", fn_start + 1)
    if next_template >= 0:
        fn_end = next_template
    else:
        namespace_close = text.find("\n}\n\n}", fn_start)
        if namespace_close < 0:
            raise RuntimeError(f"could not find axi_stream_to_data function end in {adapter_h}")
        fn_end = namespace_close + len("\n}")

    block = text[fn_start:fn_end]
    original_block = block

    pipeline_before_constexpr = "    #pragma HLS PIPELINE\n\n    constexpr"
    if pipeline_before_constexpr in block:
        block = block.replace(pipeline_before_constexpr, "    constexpr", 1)

    loop_header = "    for (int i = 0; i < NUM_BEATS; i++) {\n"
    loop_with_pipeline = loop_header + "        #pragma HLS PIPELINE II=1\n"
    if loop_with_pipeline not in block:
        if loop_header not in block:
            raise RuntimeError(f"could not find NUM_BEATS loop in axi_stream_to_data: {adapter_h}")
        block = block.replace(loop_header, loop_with_pipeline, 1)

    pre_constexpr = block.split("constexpr", 1)[0]
    if "#pragma HLS PIPELINE" in pre_constexpr:
        raise RuntimeError(f"function-level pipeline pragma still present in axi_stream_to_data: {adapter_h}")
    if loop_with_pipeline not in block:
        raise RuntimeError(f"outer-loop pipeline pragma was not inserted in axi_stream_to_data: {adapter_h}")
    if "#pragma HLS UNROLL" not in block:
        raise RuntimeError(f"inner lane unroll pragma is missing from axi_stream_to_data: {adapter_h}")

    if block != original_block:
        adapter_h.write_text(text[:fn_start] + block + text[fn_end:])

    return {
        "adapter_path": str(adapter_h),
        "removed_function_pipeline": "true",
        "outer_loop_pipeline": "II=1",
        "inner_lane_unroll": "kept",
    }


def patch_generated_coyote_sources(project_dir: Path, project_name: str, *, adapter_pipeline_fix: bool) -> dict[str, object]:
    wrapper_hpp = project_dir / "src/hls/model_wrapper/model_wrapper.hpp"
    if not wrapper_hpp.exists():
        raise FileNotFoundError(wrapper_hpp)

    expected_header = f'firmware/{project_name}.h'
    header_path = project_dir / "src/hls/model_wrapper" / expected_header
    if not header_path.exists():
        raise FileNotFoundError(header_path)

    text = wrapper_hpp.read_text()
    patched = text.replace('firmware/myproject.h', expected_header)
    if patched != text:
        wrapper_hpp.write_text(patched)
    if expected_header not in patched:
        raise RuntimeError(f"generated wrapper header does not include {expected_header}: {wrapper_hpp}")

    patches: dict[str, object] = {
        "wrapper_header_include": expected_header,
        "adapter_pipeline_fix": bool(adapter_pipeline_fix),
    }
    if adapter_pipeline_fix:
        patches["axi_stream_input_adapter"] = patch_axi_stream_input_adapter(project_dir)
    return patches


def main() -> None:
    args = parse_args()
    import numpy as np

    output_dir = args.output_dir or (DEFAULT_OUTPUT_PARENT / timestamp())
    output_dir = output_dir.resolve()
    project_dir = output_dir / "project"
    if project_dir.exists() and any(project_dir.iterdir()):
        raise RuntimeError(f"refusing to reuse non-empty project directory: {project_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)

    ctx, model = load_zero_in_model(args.config.resolve(), args.run_root.resolve(), fold=0)
    x, labels, x_path, labels_path = load_zero_in_arrays(args.input_root.resolve(), n_samples=args.n_samples)
    keras_logits = np.asarray(model.predict(x, verbose=0)).reshape(-1)

    hls_model, _hls_config = convert_model(ctx, model, x, keras_logits, output_dir, args.project_name)
    hls_model.compile()
    generated_patches = patch_generated_coyote_sources(
        project_dir,
        args.project_name,
        adapter_pipeline_fix=not args.disable_adapter_pipeline_fix,
    )

    wrapper_hpp = project_dir / "src/hls/model_wrapper/model_wrapper.hpp"
    if not wrapper_hpp.exists():
        raise FileNotFoundError(wrapper_hpp)
    if f'firmware/{args.project_name}.h' not in wrapper_hpp.read_text():
        raise RuntimeError(f"generated Coyote wrapper includes the wrong firmware header: {wrapper_hpp}")

    wrapper_cpp = project_dir / "src/hls/model_wrapper/model_wrapper.cpp"
    if not wrapper_cpp.exists():
        raise FileNotFoundError(wrapper_cpp)
    wrapper_text = wrapper_cpp.read_text()
    if "hls::stream" not in wrapper_text or "axi_stream_to_data" not in wrapper_text:
        raise RuntimeError(f"generated Coyote wrapper does not look stream based: {wrapper_cpp}")

    hls_logits = np.asarray(hls_model.predict(np.ascontiguousarray(x))).reshape(-1)
    smoke = logit_validation_summary(keras_logits, hls_logits, labels, args.tolerance)
    write_json(output_dir / "compile_smoke_summary.json", smoke)
    write_csv(output_dir / "compile_smoke_predictions.csv", prediction_rows(keras_logits, hls_logits, labels))
    if not smoke["passed"]:
        raise RuntimeError(f"hls4ml compile smoke check failed: {smoke}")

    manifest = {
        "stage": "converted",
        "backend": "CoyoteAccelerator",
        "io_type": "io_stream",
        "project_name": args.project_name,
        "output_dir": str(output_dir),
        "project_dir": str(project_dir),
        "config": str(args.config.resolve()),
        "run_root": str(args.run_root.resolve()),
        "input_root": str(args.input_root.resolve()),
        "x_path": str(x_path),
        "labels_path": str(labels_path),
        "n_samples": int(len(x)),
        "compile_smoke": smoke,
        "generated_patches": generated_patches,
    }
    write_json(output_dir / "build_manifest.json", manifest)

    hls_model.build(
        device=args.device,
        csim=True,
        synth=True,
        cosim=False,
        validation=False,
        timing_opt=True,
        bitfile=not args.no_bitfile,
        hls_clock_period=args.hls_clock_period,
        hls_clock_uncertainty=args.hls_clock_uncertainty,
    )

    bitstream = project_dir / f"build/{args.project_name}_cyt_hw/bitstreams/cyt_top.bit"
    host_lib = project_dir / f"build/{args.project_name}_cyt_sw/lib/libCoyoteInference.so"
    expected = [host_lib]
    if not args.no_bitfile:
        expected.append(bitstream)
    missing = [str(path) for path in expected if not path.exists()]
    if missing:
        raise RuntimeError("missing expected build artifacts: " + ", ".join(missing))

    manifest.update(
        {
            "stage": "built",
            "bitstream": str(bitstream),
            "host_library": str(host_lib),
            "bitstream_size": bitstream.stat().st_size if bitstream.exists() else None,
            "host_library_size": host_lib.stat().st_size,
        }
    )
    write_json(output_dir / "build_manifest.json", manifest)
    print(f"[done] output_dir={output_dir}")
    print(f"[done] project_dir={project_dir}")
    print(f"[done] bitstream={bitstream}")
    print(f"[done] host_library={host_lib}")


if __name__ == "__main__":
    main()
