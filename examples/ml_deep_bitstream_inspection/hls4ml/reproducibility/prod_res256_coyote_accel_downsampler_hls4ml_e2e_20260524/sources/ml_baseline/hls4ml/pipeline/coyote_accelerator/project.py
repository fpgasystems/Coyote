"""Generated-project patching for raw-input CoyoteAccelerator builds."""

from __future__ import annotations

import json
import re
import shutil
from pathlib import Path
from typing import Any, Sequence

import numpy as np

from ..hls_layer_tuning import apply_manual_layer_tuning
from ..part1_common import FlowContext, file_sha256, write_csv, write_json
from ..part2_train import weight_sparsity

TEMPLATE_DIR = Path(__file__).resolve().parent / "templates"


def render_template(name: str, **values: object) -> str:
    text = (TEMPLATE_DIR / name).read_text()
    for key, value in values.items():
        text = text.replace("{{" + key + "}}", str(value))
    return text


def template_hashes() -> dict[str, str]:
    return {path.name: file_sha256(path) for path in sorted(TEMPLATE_DIR.iterdir()) if path.is_file()}


def coyote_hls_config_for_model(ctx: FlowContext, model) -> dict[str, Any]:
    import keras
    from hls4ml.utils import config_from_keras_model

    hls_cfg = ctx.config["hls"]
    keras_version = keras.__version__
    keras.__version__ = "2.15.0"
    try:
        config = config_from_keras_model(model, granularity="name", backend="CoyoteAccelerator")
    finally:
        keras.__version__ = keras_version
    config.setdefault("Model", {})
    config["Model"]["Strategy"] = str(hls_cfg["strategy"])
    config["Model"]["ReuseFactor"] = int(hls_cfg["reuse_factor"])
    _, _, _, strategy_overrides = weight_sparsity(ctx, model)
    for layer_name, layer_cfg in config.get("LayerName", {}).items():
        layer_cfg["ReuseFactor"] = int(hls_cfg["reuse_factor"])
        layer_cfg["Strategy"] = strategy_overrides.get(layer_name, str(hls_cfg["strategy"]))
    apply_manual_layer_tuning(ctx.config, config)
    for layer_cfg in config.get("LayerName", {}).values():
        precision = layer_cfg.get("Precision")
        if hls_cfg.get("accum_precision") and isinstance(precision, dict) and "accum" in precision:
            precision["accum"] = hls_cfg["accum_precision"]
    if "output_dense" in config.get("LayerName", {}) and hls_cfg.get("output_precision") is not None:
        config["LayerName"]["output_dense"].setdefault("Precision", {})["result"] = hls_cfg["output_precision"]
    if "gap" in config.get("LayerName", {}) and hls_cfg.get("pool_accum_precision") is not None:
        config["LayerName"]["gap"].setdefault("Precision", {})["accum"] = hls_cfg["pool_accum_precision"]
    config.setdefault("Model", {})["Trace"] = False
    return config


def convert_coyote_model(
    ctx: FlowContext,
    model,
    x_reference: np.ndarray,
    keras_logits: np.ndarray,
    output_dir: Path,
    project_name: str,
) -> tuple[Any, dict[str, Any]]:
    import keras
    from hls4ml.converters import convert_from_keras_model

    tb_dir = output_dir / "tb_data_np"
    tb_dir.mkdir(parents=True, exist_ok=True)
    input_tb = tb_dir / "input.npy"
    output_tb = tb_dir / "keras_logits.npy"
    np.save(input_tb, np.ascontiguousarray(x_reference.astype(np.float32)))
    np.save(output_tb, np.ascontiguousarray(keras_logits.reshape(-1, 1).astype(np.float32)))

    hls_config = coyote_hls_config_for_model(ctx, model)
    coyote_cfg = ctx.config.get("u55c", {}).get("coyote_accelerator", {}) or {}
    keras_version = keras.__version__
    keras.__version__ = "2.15.0"
    try:
        hls_model = convert_from_keras_model(
            model,
            hls_config=hls_config,
            output_dir=str(output_dir / "project"),
            project_name=project_name,
            backend="CoyoteAccelerator",
            io_type="io_stream",
            clock_period=float(coyote_cfg.get("hls_clock_period", 4.0)),
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
        raise RuntimeError(f"could not find axi_stream_to_data in {adapter_h}")
    next_template = text.find("\ntemplate ", fn_start + 1)
    namespace_close = text.find("\n}\n\n}", fn_start)
    fn_end = next_template if next_template >= 0 else namespace_close + len("\n}")
    if fn_end <= fn_start:
        raise RuntimeError(f"could not find axi_stream_to_data function end in {adapter_h}")

    block = text[fn_start:fn_end]
    original_block = block
    block = block.replace("    #pragma HLS PIPELINE\n\n    constexpr", "    constexpr", 1)
    loop_header = "    for (int i = 0; i < NUM_BEATS; i++) {\n"
    loop_with_pipeline = loop_header + "        #pragma HLS PIPELINE II=1\n"
    if loop_with_pipeline not in block:
        if loop_header not in block:
            raise RuntimeError(f"could not find NUM_BEATS loop in {adapter_h}")
        block = block.replace(loop_header, loop_with_pipeline, 1)
    pre_constexpr = block.split("constexpr", 1)[0]
    if "#pragma HLS PIPELINE" in pre_constexpr:
        raise RuntimeError(f"function-level pipeline pragma still present in {adapter_h}")
    if "#pragma HLS UNROLL" not in block:
        raise RuntimeError(f"inner lane unroll pragma missing from {adapter_h}")
    if block != original_block:
        adapter_h.write_text(text[:fn_start] + block + text[fn_end:])
    return {
        "adapter_path": str(adapter_h),
        "removed_function_pipeline": "true",
        "outer_loop_pipeline": "II=1",
        "inner_lane_unroll": "kept",
    }


def patch_model_wrapper_for_raw_input(project_dir: Path, project_name: str, pixels_per_sample: int) -> dict[str, str]:
    helper_path = project_dir / "src/hls/model_wrapper/firmware/zero_in_raw_downsample.hpp"
    helper_path.write_text(render_template("zero_in_raw_downsample.hpp.in", ZERO_IN_PIXELS=pixels_per_sample))

    wrapper_hpp = project_dir / "src/hls/model_wrapper/model_wrapper.hpp"
    text = wrapper_hpp.read_text()
    expected_header = f'firmware/{project_name}.h'
    text = text.replace("firmware/myproject.h", expected_header)
    include = '#include "firmware/zero_in_raw_downsample.hpp"\n'
    if include not in text:
        anchor = '#include "firmware/nnet_utils/nnet_axi_utils_stream.h"\n'
        if anchor not in text:
            raise RuntimeError(f"could not find nnet_axi_utils_stream include in {wrapper_hpp}")
        text = text.replace(anchor, anchor + include, 1)
    wrapper_hpp.write_text(text)

    wrapper_cpp = project_dir / "src/hls/model_wrapper/model_wrapper.cpp"
    text = wrapper_cpp.read_text()
    pattern = re.compile(
        r"^(\s*)nnet::axi_stream_to_data<[^;]+>\(data_in,\s*bitstream_input\);\s*$",
        re.MULTILINE,
    )
    text, replacements = pattern.subn(r"\1zero_in_raw::raw_bitstream_downsample_to_input_stream(data_in, bitstream_input);", text, count=1)
    if replacements != 1:
        raise RuntimeError(f"could not replace float input adapter call in {wrapper_cpp}")
    wrapper_cpp.write_text(text)

    return {
        "raw_downsample_header": str(helper_path),
        "wrapper_hpp": str(wrapper_hpp),
        "wrapper_cpp": str(wrapper_cpp),
        "input_abi": "64-byte header beat with little-endian uint64 raw_len, followed by raw bytes",
    }


def patch_raw_testbench(
    project_dir: Path,
    project_name: str,
    raw_samples: Sequence[dict[str, Any]],
    csim_samples: int,
) -> dict[str, object]:
    tb_path = project_dir / f"src/{project_name}_test.cpp"
    tb_path.write_text(render_template("raw_test.cpp.in", PROJECT_NAME=project_name))
    tb_data = project_dir / "tb_data"
    tb_data.mkdir(parents=True, exist_ok=True)
    selected = list(raw_samples[: max(0, int(csim_samples))])
    manifest_path = tb_data / "tb_input_raw_manifest.dat"
    manifest_path.write_text("".join(f"{sample['raw_input_path']}\n" for sample in selected))
    return {
        "testbench": str(tb_path),
        "raw_manifest": str(manifest_path),
        "raw_csim_samples": len(selected),
    }


def patch_host_libs_for_raw_input(project_dir: Path) -> dict[str, str]:
    hpp = project_dir / "src/host_libs.hpp"
    cpp = project_dir / "src/host_libs.cpp"
    shutil.copyfile(TEMPLATE_DIR / "host_libs.hpp", hpp)
    shutil.copyfile(TEMPLATE_DIR / "host_libs.cpp", cpp)
    return {"host_libs_hpp": str(hpp), "host_libs_cpp": str(cpp)}


def patch_generated_project(
    project_dir: Path,
    project_name: str,
    *,
    pixels_per_sample: int,
    raw_samples: Sequence[dict[str, Any]],
    raw_csim_samples: int,
) -> dict[str, object]:
    wrapper_hpp = project_dir / "src/hls/model_wrapper/model_wrapper.hpp"
    if not wrapper_hpp.exists():
        raise FileNotFoundError(wrapper_hpp)
    expected_header = project_dir / "src/hls/model_wrapper/firmware" / f"{project_name}.h"
    if not expected_header.exists():
        raise FileNotFoundError(expected_header)

    patches: dict[str, object] = {
        "template_hashes": template_hashes(),
        "raw_input_mode": True,
        "wrapper_header_include": f"firmware/{project_name}.h",
    }
    patches["raw_downsampler"] = patch_model_wrapper_for_raw_input(project_dir, project_name, pixels_per_sample)
    patches["raw_testbench"] = patch_raw_testbench(project_dir, project_name, raw_samples, raw_csim_samples)
    patches["raw_host_libs"] = patch_host_libs_for_raw_input(project_dir)
    patches["axi_stream_input_adapter"] = patch_axi_stream_input_adapter(project_dir)

    wrapper_text = (project_dir / "src/hls/model_wrapper/model_wrapper.cpp").read_text()
    if "raw_bitstream_downsample_to_input_stream" not in wrapper_text:
        raise RuntimeError("generated model_wrapper.cpp does not call raw downsampler")
    return patches


def write_compile_smoke(output_dir: Path, keras_logits: np.ndarray, hls_logits: np.ndarray, labels: np.ndarray, tolerance: float) -> dict[str, Any]:
    diff = np.asarray(hls_logits).reshape(-1) - np.asarray(keras_logits).reshape(-1)
    abs_diff = np.abs(diff)
    cpu_pred = (np.asarray(keras_logits).reshape(-1) >= 0.0).astype(np.int32)
    hls_pred = (np.asarray(hls_logits).reshape(-1) >= 0.0).astype(np.int32)
    labels = np.asarray(labels, dtype=np.int32).reshape(-1)
    summary = {
        "n": int(abs_diff.size),
        "tolerance": float(tolerance),
        "passed": bool(np.all(abs_diff <= tolerance)),
        "logit_mae": float(abs_diff.mean()) if abs_diff.size else 0.0,
        "logit_max_abs": float(abs_diff.max()) if abs_diff.size else 0.0,
        "sign_mismatches": int(np.sum(cpu_pred != hls_pred)),
        "prediction_agreement": float(np.mean(cpu_pred == hls_pred)) if abs_diff.size else 0.0,
    }
    if labels.size == cpu_pred.size:
        summary["cpu_accuracy"] = float(np.mean(cpu_pred == labels))
        summary["hls_accuracy"] = float(np.mean(hls_pred == labels))
    rows = [
        {
            "sample_index": idx,
            "label": int(labels[idx]) if idx < labels.size else "",
            "cpu_logit": float(cpu),
            "hls_logit": float(hls),
            "abs_diff": float(abs(hls - cpu)),
            "cpu_pred": int(cpu >= 0.0),
            "hls_pred": int(hls >= 0.0),
        }
        for idx, (cpu, hls) in enumerate(zip(np.asarray(keras_logits).reshape(-1), np.asarray(hls_logits).reshape(-1)))
    ]
    write_json(output_dir / "compile_smoke_summary.json", summary)
    write_csv(output_dir / "compile_smoke_predictions.csv", rows)
    return summary
