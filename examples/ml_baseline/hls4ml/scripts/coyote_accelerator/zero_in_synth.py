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
    DEFAULT_SPLIT_CSV,
    load_zero_in_arrays,
    load_zero_in_model,
    load_zero_in_raw_samples,
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
    parser.add_argument("--raw-csim-samples", type=int, default=1)
    parser.add_argument("--split-csv", type=Path, default=DEFAULT_SPLIT_CSV)
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


RAW_DOWNSAMPLE_HEADER = r'''#ifndef ZERO_IN_RAW_DOWNSAMPLE_HPP_
#define ZERO_IN_RAW_DOWNSAMPLE_HPP_

#include "ap_int.h"
#include "hls_stream.h"
#include "ap_axi_sdata.h"
#include "defines.h"

namespace zero_in_raw {

static const unsigned int ZERO_IN_PIXELS = 256 * 256;
static const unsigned int COYOTE_AXI_BYTES = COYOTE_AXI_STREAM_BITS / 8;
static const unsigned long long ONE_SAMPLE_PER_BEAT_MIN_LEN =
    ((unsigned long long) ZERO_IN_PIXELS - 1) * COYOTE_AXI_BYTES + 1;

static ap_uint<8> get_byte(const axi_s &packet, unsigned int byte_idx) {
    #pragma HLS INLINE
    return packet.data.range((byte_idx + 1) * 8 - 1, byte_idx * 8);
}

static unsigned long long read_len_le(const axi_s &packet) {
    #pragma HLS INLINE
    unsigned long long raw_len = 0;
    for (unsigned int b = 0; b < 8; b++) {
        #pragma HLS UNROLL
        raw_len |= ((unsigned long long) get_byte(packet, b)) << (8 * b);
    }
    return raw_len;
}

static void write_normalized_token(ap_uint<8> raw_byte, hls::stream<input_t> &data_out) {
    #pragma HLS INLINE
    ap_uint<8> inverted = 255 - raw_byte;
    input_t token;
    token[0] = input_t::value_type((float) inverted / 255.0f);
    data_out.write(token);
}

static void write_padding_tokens(unsigned int already_written, hls::stream<input_t> &data_out) {
    for (unsigned int i = already_written; i < ZERO_IN_PIXELS; i++) {
        #pragma HLS PIPELINE II=1
        write_normalized_token(0, data_out);
    }
}

static void raw_bitstream_downsample_to_input_stream(
    hls::stream<axi_s> &axi_in,
    hls::stream<input_t> &data_out
) {
    #pragma HLS INLINE OFF

    axi_s header = axi_in.read();
    unsigned long long raw_len = read_len_le(header);

    if (raw_len == 0) {
        write_padding_tokens(0, data_out);
        return;
    }

    if (raw_len <= ZERO_IN_PIXELS) {
        unsigned int written = 0;
        axi_s packet;
        for (unsigned long long raw_idx = 0; raw_idx < raw_len; raw_idx++) {
            #pragma HLS PIPELINE II=1
            unsigned int lane = raw_idx % COYOTE_AXI_BYTES;
            if (lane == 0) {
                packet = axi_in.read();
            }
            write_normalized_token(get_byte(packet, lane), data_out);
            written++;
        }
        write_padding_tokens(written, data_out);
        return;
    }

    const unsigned long long numerator = raw_len - 1;
    const unsigned long long denom = ZERO_IN_PIXELS - 1;
    const unsigned long long stride = numerator / denom;
    const unsigned long long remainder_step = numerator % denom;

    if (raw_len < ONE_SAMPLE_PER_BEAT_MIN_LEN) {
        unsigned long long target_idx = 0;
        unsigned long long remainder_acc = 0;
        unsigned int sample_idx = 0;
        axi_s packet;

        for (unsigned long long raw_idx = 0; raw_idx < raw_len; raw_idx++) {
            #pragma HLS PIPELINE II=1
            unsigned int lane = raw_idx % COYOTE_AXI_BYTES;
            if (lane == 0) {
                packet = axi_in.read();
            }
            if (raw_idx == target_idx) {
                write_normalized_token(get_byte(packet, lane), data_out);
                sample_idx++;
                target_idx += stride;
                remainder_acc += remainder_step;
                if (remainder_acc >= denom) {
                    target_idx++;
                    remainder_acc -= denom;
                }
            }
        }
        return;
    }

    unsigned long long target_idx = 0;
    unsigned long long remainder_acc = 0;
    unsigned int sample_idx = 0;
    const unsigned long long num_beats = (raw_len + COYOTE_AXI_BYTES - 1) / COYOTE_AXI_BYTES;

    for (unsigned long long beat = 0; beat < num_beats; beat++) {
        #pragma HLS PIPELINE II=1
        axi_s packet = axi_in.read();
        unsigned long long beat_base = beat * COYOTE_AXI_BYTES;
        if (target_idx >= beat_base && target_idx < beat_base + COYOTE_AXI_BYTES) {
            unsigned int lane = target_idx - beat_base;
            write_normalized_token(get_byte(packet, lane), data_out);
            sample_idx++;
            target_idx += stride;
            remainder_acc += remainder_step;
            if (remainder_acc >= denom) {
                target_idx++;
                remainder_acc -= denom;
            }
        }
    }
}

}

#endif
'''


RAW_TESTBENCH = r'''/**
 * @brief zero-in raw-input CoyoteAccelerator CSim/CoSim testbench.
 *
 * This testbench feeds model_wrapper with the production raw input ABI:
 * one 512-bit header beat carrying little-endian raw_len, followed by raw bytes.
 */

#include <vector>
#include <fstream>
#include <iostream>
#include <cstring>
#include <stdexcept>

#include "hls_stream.h"
#include "ap_axi_sdata.h"

#include "model_wrapper.hpp"
#include "firmware/PROJECT_NAME.h"
#include "firmware/nnet_utils/nnet_helpers.h"
#include "firmware/nnet_utils/nnet_axi_utils.h"
#include "firmware/nnet_utils/nnet_axi_utils_stream.h"

#define CHECKPOINT 1
#define COYOTE_AXI_STREAM_BITS 512
#define COYOTE_AXI_BYTES 64
typedef ap_axiu<COYOTE_AXI_STREAM_BITS, 0, 0, 0> axi_s;

static void set_byte(axi_s &packet, unsigned int byte_idx, unsigned char value) {
    packet.data.range((byte_idx + 1) * 8 - 1, byte_idx * 8) = value;
}

static void write_raw_payload(hls::stream<axi_s> &data_in, const std::vector<unsigned char> &raw) {
    axi_s header;
    header.data = 0;
    header.keep = -1;
    header.strb = -1;
    header.last = 0;
    unsigned long long raw_len = raw.size();
    for (unsigned int b = 0; b < 8; b++) {
        set_byte(header, b, (raw_len >> (8 * b)) & 0xff);
    }
    data_in.write(header);

    for (unsigned long long offset = 0; offset < raw_len; offset += COYOTE_AXI_BYTES) {
        axi_s packet;
        packet.data = 0;
        packet.keep = 0;
        packet.strb = 0;
        packet.last = ((offset + COYOTE_AXI_BYTES) >= raw_len);
        for (unsigned int b = 0; b < COYOTE_AXI_BYTES && offset + b < raw_len; b++) {
            set_byte(packet, b, raw[offset + b]);
            packet.keep[b] = 1;
            packet.strb[b] = 1;
        }
        data_in.write(packet);
    }
}

static std::vector<unsigned char> read_raw_file(const std::string &path) {
    std::ifstream fin(path, std::ios::binary);
    if (!fin.is_open()) {
        throw std::runtime_error("Could not open raw bitstream: " + path);
    }
    fin.seekg(0, std::ios::end);
    std::streamsize size = fin.tellg();
    fin.seekg(0, std::ios::beg);
    std::vector<unsigned char> data(size);
    if (size > 0 && !fin.read(reinterpret_cast<char *>(data.data()), size)) {
        throw std::runtime_error("Could not read raw bitstream: " + path);
    }
    return data;
}

int main(int argc, char **argv) {
    std::ifstream fraw("tb_data/tb_input_raw_manifest.dat");
    std::ifstream fpr("tb_data/tb_output_predictions.dat");

    #ifdef RTL_SIM
        std::string RESULTS_LOG = "tb_data/rtl_cosim_results.log";
    #else
        std::string RESULTS_LOG = "tb_data/csim_results.log";
    #endif
    std::ofstream fout(RESULTS_LOG);

    std::string raw_path;
    std::string pline;
    int e = 0;

    if (fraw.is_open() && fpr.is_open()) {
        while (std::getline(fraw, raw_path) && std::getline(fpr, pline)) {
            if (raw_path.empty()) {
                continue;
            }
            if (e % CHECKPOINT == 0) {
                std::cout << "Processing raw input " << e << ": " << raw_path << std::endl;
            }
            char *cstr = const_cast<char *>(pline.c_str());
            char *current;
            std::vector<float> pr;
            current = strtok(cstr, " ");
            while (current != NULL) {
                pr.push_back(atof(current));
                current = strtok(NULL, " ");
            }

            std::vector<unsigned char> raw = read_raw_file(raw_path);
            hls::stream<axi_s> data_in;
            write_raw_payload(data_in, raw);
            float layer29_out[1];
            hls::stream<axi_s> data_out;

            model_wrapper(data_in, data_out);
            nnet::axi_stream_to_data<float, float, 1, COYOTE_AXI_STREAM_BITS, 8 * sizeof(float)>(data_out, layer29_out);

            if (e % CHECKPOINT == 0) {
                std::cout << "Prediction reference" << std::endl;
                for(int i = 0; i < 1; i++) {
                  std::cout << pr[i] << " ";
                }
                std::cout << std::endl;
                std::cout << "Quantized prediction" << std::endl;
                nnet::print_result<float, 1>(layer29_out, std::cout, true);
            }
            e++;
            nnet::print_result<float, 1>(layer29_out, fout);
        }
        fraw.close();
        fpr.close();
    } else {
        std::cout << "INFO: Unable to open raw input/predictions file, using empty raw input." << std::endl;
        hls::stream<axi_s> data_in;
        std::vector<unsigned char> raw;
        write_raw_payload(data_in, raw);
        float layer29_out[1];
        hls::stream<axi_s> data_out;
        model_wrapper(data_in, data_out);
        nnet::axi_stream_to_data<float, float, 1, COYOTE_AXI_STREAM_BITS, 8 * sizeof(float)>(data_out, layer29_out);
        nnet::print_result<float, 1>(layer29_out, std::cout, true);
        nnet::print_result<float, 1>(layer29_out, fout);
    }

    fout.close();
    std::cout << "INFO: Saved inference results to file: " << RESULTS_LOG << std::endl;
    return 0;
}
'''


def patch_model_wrapper_for_raw_input(project_dir: Path) -> dict[str, str]:
    helper_path = project_dir / "src/hls/model_wrapper/firmware/zero_in_raw_downsample.hpp"
    helper_path.write_text(RAW_DOWNSAMPLE_HEADER)

    wrapper_hpp = project_dir / "src/hls/model_wrapper/model_wrapper.hpp"
    text = wrapper_hpp.read_text()
    include = '#include "firmware/zero_in_raw_downsample.hpp"\n'
    if include not in text:
        text = text.replace('#include "firmware/nnet_utils/nnet_axi_utils_stream.h"\n', '#include "firmware/nnet_utils/nnet_axi_utils_stream.h"\n' + include)
        wrapper_hpp.write_text(text)

    wrapper_cpp = project_dir / "src/hls/model_wrapper/model_wrapper.cpp"
    text = wrapper_cpp.read_text()
    old = "    nnet::axi_stream_to_data<input_t, float, 256*256*1, COYOTE_AXI_STREAM_BITS, 8 * sizeof(float)>(data_in, bitstream_input);\n"
    new = "    zero_in_raw::raw_bitstream_downsample_to_input_stream(data_in, bitstream_input);\n"
    if old not in text:
        raise RuntimeError(f"could not find float input adapter call in {wrapper_cpp}")
    text = text.replace(old, new, 1)
    wrapper_cpp.write_text(text)

    return {
        "raw_downsample_header": str(helper_path),
        "wrapper_cpp": str(wrapper_cpp),
        "input_abi": "64-byte header beat with little-endian uint64 raw_len, followed by raw bytes",
    }


def patch_raw_testbench(project_dir: Path, project_name: str, raw_samples: list[dict[str, object]], csim_samples: int) -> dict[str, object]:
    tb_path = project_dir / f"src/{project_name}_test.cpp"
    if not tb_path.exists():
        raise FileNotFoundError(tb_path)
    tb_path.write_text(RAW_TESTBENCH.replace("PROJECT_NAME", project_name))

    tb_data = project_dir / "tb_data"
    tb_data.mkdir(parents=True, exist_ok=True)
    selected = raw_samples[: max(0, int(csim_samples))]
    manifest_path = tb_data / "tb_input_raw_manifest.dat"
    manifest_path.write_text("".join(f"{sample['path']}\n" for sample in selected))
    return {
        "testbench": str(tb_path),
        "raw_manifest": str(manifest_path),
        "raw_csim_samples": len(selected),
    }


def patch_host_libs_for_raw_input(project_dir: Path) -> dict[str, str]:
    hpp = project_dir / "src/host_libs.hpp"
    cpp = project_dir / "src/host_libs.cpp"
    if not hpp.exists():
        raise FileNotFoundError(hpp)
    if not cpp.exists():
        raise FileNotFoundError(cpp)

    hpp_text = hpp.read_text()
    hpp_text = hpp_text.replace("#include <vector>\n", "#include <vector>\n#include <cstdint>\n")
    hpp_text = hpp_text.replace(
        "    CoyoteInference(unsigned int batch_size, unsigned int in_size, unsigned int out_size);\n",
        "    CoyoteInference(unsigned int batch_size, unsigned int in_size, unsigned int out_size);\n"
        "    CoyoteInference(unsigned int batch_size, unsigned int max_input_bytes, unsigned int out_size, bool raw_input_mode);\n",
    )
    hpp_text = hpp_text.replace(
        "    void set_data(float *x, unsigned int i);\n",
        "    void set_data(float *x, unsigned int i);\n"
        "    void set_raw_data(const uint8_t *x, unsigned int raw_len, unsigned int i);\n",
    )
    hpp_text = hpp_text.replace(
        "    unsigned int batch_size, in_size, out_size;\n",
        "    unsigned int batch_size, in_size, out_size;\n"
        "    bool raw_input_mode = false;\n"
        "    static constexpr unsigned int RAW_HEADER_BYTES = 64;\n",
    )
    hpp_text = hpp_text.replace(
        "    std::vector<float*> src_mems, dst_mems;\n",
        "    std::vector<float*> src_mems, dst_mems;\n"
        "    std::vector<uint8_t*> raw_src_mems;\n",
    )
    hpp.write_text(hpp_text)

    cpp_text = cpp.read_text()
    cpp_text = cpp_text.replace(
        "#include \"host_libs.hpp\"\n",
        "#include \"host_libs.hpp\"\n#include <algorithm>\n#include <cstring>\n",
    )
    ctor_marker = "CoyoteInference::~CoyoteInference() {}\n"
    raw_ctor = r'''
CoyoteInference::CoyoteInference(unsigned int batch_size, unsigned int max_input_bytes, unsigned int out_size, bool raw_input_mode):
    batch_size(batch_size), in_size(max_input_bytes), out_size(out_size), raw_input_mode(raw_input_mode),
    coyote_thread(DEFAULT_VFPGA_ID, getpid())
{
    if (!raw_input_mode) { throw std::runtime_error("raw constructor requires raw_input_mode=true"); }
    for (unsigned int i = 0; i < batch_size; i++) {
        raw_src_mems.emplace_back((uint8_t *) coyote_thread.getMem({coyote::CoyoteAllocType::HPF, (uint) (RAW_HEADER_BYTES + max_input_bytes)}));
        dst_mems.emplace_back((float *) coyote_thread.getMem({coyote::CoyoteAllocType::HPF, (uint) (out_size * sizeof(float))}));
        if (!raw_src_mems[i] || !dst_mems[i]) { throw std::runtime_error("Could not allocate memory; exiting..."); }

        coyote::localSg src_sg = { .addr = raw_src_mems[i], .len = RAW_HEADER_BYTES };
        coyote::localSg dst_sg = { .addr = dst_mems[i], .len = (uint) (out_size * sizeof(float))};
        src_sgs.emplace_back(src_sg);
        dst_sgs.emplace_back(dst_sg);
    }
}

'''
    if raw_ctor not in cpp_text:
        cpp_text = cpp_text.replace(ctor_marker, raw_ctor + ctor_marker)
    cpp_text = cpp_text.replace(
        "        memset(dst_mems[i], 0, out_size);\n",
        "        memset(dst_mems[i], 0, out_size * sizeof(float));\n",
    )
    set_data_marker = "float* CoyoteInference::get_predictions(unsigned int i) { return dst_mems[i]; }\n"
    set_raw = r'''
void CoyoteInference::set_raw_data(const uint8_t *x, unsigned int raw_len, unsigned int i) {
    if (!raw_input_mode) { throw std::runtime_error("set_raw_data called on non-raw CoyoteInference"); }
    if (i >= batch_size) { throw std::runtime_error("raw batch index out of range"); }
    if (raw_len > in_size) { throw std::runtime_error("raw input is larger than allocated max_input_bytes"); }

    uint8_t *dst = raw_src_mems[i];
    memset(dst, 0, RAW_HEADER_BYTES);
    uint64_t raw_len_64 = raw_len;
    for (unsigned int b = 0; b < 8; b++) {
        dst[b] = (raw_len_64 >> (8 * b)) & 0xff;
    }
    if (raw_len > 0) {
        memcpy(dst + RAW_HEADER_BYTES, x, raw_len);
    }
    src_sgs[i].addr = raw_src_mems[i];
    src_sgs[i].len = RAW_HEADER_BYTES + raw_len;
}

'''
    if set_raw not in cpp_text:
        cpp_text = cpp_text.replace(set_data_marker, set_raw + set_data_marker)
    cpp_text = cpp_text.replace(
        "    CoyoteInference* init_model_inference(unsigned int batch_size, unsigned int in_size, unsigned int out_size) {\n"
        "        return new CoyoteInference(batch_size, in_size, out_size);\n"
        "    }\n",
        "    CoyoteInference* init_model_inference(unsigned int batch_size, unsigned int in_size, unsigned int out_size) {\n"
        "        return new CoyoteInference(batch_size, in_size, out_size);\n"
        "    }\n\n"
        "    CoyoteInference* init_model_inference_raw(unsigned int batch_size, unsigned int max_input_bytes, unsigned int out_size) {\n"
        "        return new CoyoteInference(batch_size, max_input_bytes, out_size, true);\n"
        "    }\n",
    )
    cpp_text = cpp_text.replace(
        "    void set_inference_data(CoyoteInference* obj, float *x, unsigned int i) {\n"
        "        obj->set_data(x, i);\n"
        "    }\n",
        "    void set_inference_data(CoyoteInference* obj, float *x, unsigned int i) {\n"
        "        obj->set_data(x, i);\n"
        "    }\n\n"
        "    void set_inference_raw_data(CoyoteInference* obj, uint8_t *x, unsigned int raw_len, unsigned int i) {\n"
        "        obj->set_raw_data(x, raw_len, i);\n"
        "    }\n",
    )
    cpp.write_text(cpp_text)
    return {"host_libs_hpp": str(hpp), "host_libs_cpp": str(cpp)}


def patch_generated_coyote_sources(
    project_dir: Path,
    project_name: str,
    *,
    adapter_pipeline_fix: bool,
    raw_samples: list[dict[str, object]],
    raw_csim_samples: int,
) -> dict[str, object]:
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
        "raw_input_mode": True,
    }
    patches["raw_downsampler"] = patch_model_wrapper_for_raw_input(project_dir)
    patches["raw_testbench"] = patch_raw_testbench(project_dir, project_name, raw_samples, raw_csim_samples)
    patches["raw_host_libs"] = patch_host_libs_for_raw_input(project_dir)
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
    _raw_arrays, raw_labels, raw_samples, split_csv = load_zero_in_raw_samples(args.split_csv.resolve(), n_samples=args.n_samples)
    if len(raw_labels) != len(labels):
        raise RuntimeError(f"raw split sample count {len(raw_labels)} != prepared input count {len(labels)}")
    if not np.array_equal(raw_labels, labels):
        raise RuntimeError("raw split labels do not match prepared input labels")
    keras_logits = np.asarray(model.predict(x, verbose=0)).reshape(-1)

    hls_model, _hls_config = convert_model(ctx, model, x, keras_logits, output_dir, args.project_name)
    hls_model.compile()
    generated_patches = patch_generated_coyote_sources(
        project_dir,
        args.project_name,
        adapter_pipeline_fix=not args.disable_adapter_pipeline_fix,
        raw_samples=raw_samples,
        raw_csim_samples=args.raw_csim_samples,
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
    if "hls::stream" not in wrapper_text or "raw_bitstream_downsample_to_input_stream" not in wrapper_text:
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
        "split_csv": str(split_csv.resolve()),
        "x_path": str(x_path),
        "labels_path": str(labels_path),
        "raw_input_mode": True,
        "raw_input_abi": "64-byte header beat with little-endian uint64 raw_len, followed by raw bytes",
        "raw_csim_samples": int(args.raw_csim_samples),
        "raw_samples": [
            {
                "sample_id": sample["sample_id"],
                "path": str(sample["path"]),
                "raw_len": int(sample["raw_len"]),
                "label": int(sample["label"]),
            }
            for sample in raw_samples
        ],
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
