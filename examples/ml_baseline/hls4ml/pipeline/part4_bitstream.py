"""Part 4 of the notebook flow: U55C input preparation and Coyote bitstream build."""

from __future__ import annotations

import os
import re
import shutil
import time
from pathlib import Path
from typing import Any

import numpy as np

from .part1_common import (
    FlowContext,
    file_sha256,
    read_json,
    run_command,
    sha256_tree,
    write_csv,
    write_json,
    write_run_index,
)
from .part2_train import get_splits

def bitstream_to_sequence(bin_path: Path, sequence_length: int, invert: bool = True) -> np.ndarray:
    data = np.fromfile(bin_path, dtype=np.uint8)
    if len(data) <= sequence_length:
        window = np.zeros(sequence_length, dtype=np.uint8)
        window[: len(data)] = data
    else:
        indices = np.linspace(0, len(data) - 1, sequence_length, dtype=np.int64)
        window = data[indices]
    return 255 - window if invert else window


def sample_to_nhwc_for_u55c(ctx: FlowContext, row: dict[str, Any]) -> np.ndarray:
    img_size = int(ctx.config["candidate"]["img_size"])
    bin_path = Path(row["_bitstream_dir"]) / row["bitstream_path"]
    seq = bitstream_to_sequence(bin_path, img_size * img_size, invert=True)
    return (seq.reshape(img_size, img_size).astype(np.float32) / 255.0)[..., np.newaxis]


def fixed16_from_float(ctx: FlowContext, x: np.ndarray) -> np.ndarray:
    abi = ctx.abi
    scale = 1 << int(abi["fixed_fraction"])
    width = int(abi["fixed_width"])
    q = np.trunc(np.asarray(x, dtype=np.float64) * scale)
    return np.clip(q, -(1 << (width - 1)), (1 << (width - 1)) - 1).astype("<i2")


def float_from_fixed16(ctx: FlowContext, q: np.ndarray) -> np.ndarray:
    return q.astype(np.float32) / float(1 << int(ctx.abi["fixed_fraction"]))


def prepare_u55c_inputs(ctx: FlowContext, splits, force: bool = False) -> None:
    fold = ctx.primary_fold
    _, val_samples = splits[fold]
    sample_ids = [row["sample_id"] for row in val_samples]
    input_fingerprint = {
        "training_fingerprint": ctx.training_fingerprint,
        "hls_fingerprint": ctx.hls_fingerprint,
        "fold": fold,
        "sample_ids": sample_ids,
        "abi": ctx.abi,
        "input_quantization": "ap_fixed_default_trunc",
    }
    manifest_path = ctx.prepared_inputs_dir / "manifest.json"
    csv_manifest_path = ctx.prepared_inputs_dir / "manifest.csv"
    if not force and manifest_path.exists() and read_json(manifest_path).get("fingerprint") == input_fingerprint:
        print(f"prepared input cache hit: {ctx.prepared_inputs_dir}")
        return
    ctx.prepared_inputs_dir.mkdir(parents=True, exist_ok=True)
    rows = []
    all_x = []
    labels = []
    for idx, row in enumerate(val_samples):
        x = sample_to_nhwc_for_u55c(ctx, row).astype(np.float32)
        flat = x.reshape(-1)
        if flat.size != int(ctx.abi["pixels_per_sample"]):
            raise ValueError(f"unexpected input size {flat.size}")
        fixed = fixed16_from_float(ctx, flat)
        blob = ctx.prepared_inputs_dir / f"sample_{idx:04d}.bin"
        fixed.tofile(blob)
        all_x.append(x)
        labels.append(int(row["class_label"]))
        rows.append(
            {
                "sample_index": idx,
                "sample_id": row.get("sample_id", ""),
                "class_label": int(row["class_label"]),
                "class_name": row.get("class_name", "standalone" if int(row["class_label"]) else "benign"),
                "app_name": row.get("app_name", ""),
                "ro_count": row.get("ro_count", ""),
                "bitstream_path": row.get("bitstream_path", ""),
                "input_path": str(blob),
                "input_sha256": file_sha256(blob),
                "input_bytes": blob.stat().st_size,
            }
        )
    np.save(ctx.prepared_inputs_dir / "x_norm.npy", np.stack(all_x))
    np.save(ctx.prepared_inputs_dir / "labels.npy", np.asarray(labels, dtype=np.int32))
    write_csv(csv_manifest_path, rows)
    write_json(
        manifest_path,
        {
            "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "fingerprint": input_fingerprint,
            "csv_manifest": str(csv_manifest_path),
            "n_samples": len(rows),
            "input_bytes_per_sample": ctx.abi["input_bytes_per_sample"],
            "input_quantization": "ap_fixed_default_trunc",
        },
    )


def rewrite_includes(text: str) -> str:
    text = text.replace('"nnet_utils/', '"').replace('"weights/', '"')
    return "\n".join(line for line in text.splitlines() if "#pragma HLS INTERFACE axis port=" not in line) + "\n"


def find_top_header(project_dir: Path, project_name: str) -> Path:
    header = project_dir / "firmware" / f"{project_name}.h"
    if header.exists():
        return header
    headers = sorted((project_dir / "firmware").glob("*.h"))
    matches = [path for path in headers if "defines" not in path.name and "parameters" not in path.name]
    if not matches:
        raise FileNotFoundError("could not find hls4ml top header")
    return matches[0]


def diagnostic_mode(ctx: FlowContext) -> str:
    diagnostic = ctx.config.get("u55c", {}).get("diagnostic", {}) or {}
    mode = str(diagnostic.get("mode", "baseline")).strip().lower().replace("-", "_")
    allowed = {
        "baseline",
        "lane_probe",
        "full_streaming",
        "h1_framing_probe",
        "h1_delayed_probe",
        "framed_buffered_cnn",
        "replicated_logit_2beat_cnn",
        "rom_cnn",
        "rom_control_probe",
        "rom_layer_probe",
    }
    if mode not in allowed:
        raise ValueError(f"unknown u55c.diagnostic.mode={mode!r}; choose from {sorted(allowed)}")
    return mode


def baseline_wrapper_source(top_header_name: str, top_function: str) -> str:
    return f"""
#include "coyote_qkeras_infer.hpp"
#include "{top_header_name}"
#include "{top_function}.cpp"

static void read_input_frame(hls::stream<axi_s> &s_axi_in, hls::stream<input_t> &nn_in) {{
    #pragma HLS INLINE off
    for (int beat = 0; beat < INPUT_BEATS; ++beat) {{
        axi_s word = s_axi_in.read();
        for (int lane = 0; lane < PIXELS_PER_BEAT; ++lane) {{
            #pragma HLS PIPELINE II=1
            ap_int<FIXED_WIDTH> raw = word.data.range((lane + 1) * FIXED_WIDTH - 1, lane * FIXED_WIDTH);
            input_t item;
            packed_input_t value;
            value.range(FIXED_WIDTH - 1, 0) = raw;
            item[0] = value;
            nn_in.write(item);
        }}
    }}
}}

static void run_network(hls::stream<input_t> &nn_in, hls::stream<result_t> &nn_out) {{
    #pragma HLS INLINE off
    {top_function}(nn_in, nn_out);
}}

static void write_output_frame(hls::stream<result_t> &nn_out, hls::stream<axi_s> &m_axi_out) {{
    #pragma HLS INLINE off
    result_t y = nn_out.read();
    axi_s out_word;
    out_word.data = 0;
    out_word.keep = -1;
    out_word.last = 1;
    packed_output_t out_value = y[0];
    out_word.data.range(FIXED_WIDTH - 1, 0) = out_value.range(FIXED_WIDTH - 1, 0);
    m_axi_out.write(out_word);
}}

void coyote_qkeras_infer(hls::stream<axi_s> &s_axi_in, hls::stream<axi_s> &m_axi_out) {{
    #pragma HLS INTERFACE ap_ctrl_none port=return
    #pragma HLS INTERFACE axis register port=s_axi_in name=s_axi_in
    #pragma HLS INTERFACE axis register port=m_axi_out name=m_axi_out
    #pragma HLS DATAFLOW

    hls::stream<input_t> nn_in("nn_in");
    hls::stream<result_t> nn_out("nn_out");
    #pragma HLS STREAM variable=nn_in depth=1024
    #pragma HLS STREAM variable=nn_out depth=2

    read_input_frame(s_axi_in, nn_in);
    run_network(nn_in, nn_out);
    write_output_frame(nn_out, m_axi_out);
}}
""".strip()


def full_streaming_wrapper_source(top_header_name: str, top_function: str) -> str:
    return f"""
#include "coyote_qkeras_infer.hpp"
#include "{top_header_name}"
#include "{top_function}.cpp"

static void read_input_frame_streaming(hls::stream<axi_s> &s_axi_in, hls::stream<input_t> &nn_in) {{
    #pragma HLS INLINE off
    bool saw_last = false;
    for (int beat = 0; beat < INPUT_BEATS; ++beat) {{
        axi_s word = s_axi_in.read();
        saw_last = saw_last || bool(word.last);
        for (int lane = 0; lane < PIXELS_PER_BEAT; ++lane) {{
            #pragma HLS PIPELINE II=1
            ap_int<FIXED_WIDTH> raw = word.data.range((lane + 1) * FIXED_WIDTH - 1, lane * FIXED_WIDTH);
            input_t item;
            packed_input_t value;
            value.range(FIXED_WIDTH - 1, 0) = raw;
            item[0] = value;
            nn_in.write(item);
        }}
    }}
}}

static void run_network(hls::stream<input_t> &nn_in, hls::stream<result_t> &nn_out) {{
    #pragma HLS INLINE off
    {top_function}(nn_in, nn_out);
}}

static void write_output_frame(hls::stream<result_t> &nn_out, hls::stream<axi_s> &m_axi_out) {{
    #pragma HLS INLINE off
    result_t y = nn_out.read();
    axi_s out_word;
    out_word.data = 0;
    out_word.keep = -1;
    out_word.last = 1;
    packed_output_t out_value = y[0];
    out_word.data.range(FIXED_WIDTH - 1, 0) = out_value.range(FIXED_WIDTH - 1, 0);
    m_axi_out.write(out_word);
}}

void coyote_qkeras_infer(hls::stream<axi_s> &s_axi_in, hls::stream<axi_s> &m_axi_out) {{
    #pragma HLS INTERFACE ap_ctrl_none port=return
    #pragma HLS INTERFACE axis register port=s_axi_in name=s_axi_in
    #pragma HLS INTERFACE axis register port=m_axi_out name=m_axi_out
    #pragma HLS DATAFLOW

    hls::stream<input_t> nn_in("nn_in");
    hls::stream<result_t> nn_out("nn_out");
    #pragma HLS STREAM variable=nn_in depth=64
    #pragma HLS STREAM variable=nn_out depth=2

    read_input_frame_streaming(s_axi_in, nn_in);
    run_network(nn_in, nn_out);
    write_output_frame(nn_out, m_axi_out);
}}
""".strip()


def lane_probe_wrapper_source() -> str:
    return """
#include "coyote_qkeras_infer.hpp"

void coyote_qkeras_infer(hls::stream<axi_s> &s_axi_in, hls::stream<axi_s> &m_axi_out) {
    #pragma HLS INTERFACE ap_ctrl_none port=return
    #pragma HLS INTERFACE axis register port=s_axi_in name=s_axi_in
    #pragma HLS INTERFACE axis register port=m_axi_out name=m_axi_out

    ap_int<48> lane_sum[PIXELS_PER_BEAT];
    #pragma HLS ARRAY_PARTITION variable=lane_sum complete
    ap_int<48> full_sum = 0;
    ap_int<64> weighted_sum = 0;

    for (int lane = 0; lane < PIXELS_PER_BEAT; ++lane) {
        #pragma HLS UNROLL
        lane_sum[lane] = 0;
    }

    for (int beat = 0; beat < INPUT_BEATS; ++beat) {
        axi_s word = s_axi_in.read();
        for (int lane = 0; lane < PIXELS_PER_BEAT; ++lane) {
            #pragma HLS PIPELINE II=1
            ap_int<FIXED_WIDTH> raw = word.data.range((lane + 1) * FIXED_WIDTH - 1, lane * FIXED_WIDTH);
            ap_int<48> value = raw;
            lane_sum[lane] += value;
            full_sum += value;
            weighted_sum += value * (lane + 1);
        }
    }

    axi_s out0;
    out0.data = 0;
    out0.keep = -1;
    out0.last = 0;
    for (int lane = 0; lane < PIXELS_PER_BEAT; ++lane) {
        #pragma HLS UNROLL
        ap_uint<16> checksum = lane_sum[lane].range(15, 0);
        out0.data.range((lane + 1) * FIXED_WIDTH - 1, lane * FIXED_WIDTH) = checksum;
    }
    m_axi_out.write(out0);

    axi_s out1;
    out1.data = 0;
    out1.keep = -1;
    out1.last = 1;
    out1.data.range(15, 0) = ap_uint<16>(full_sum.range(15, 0));
    out1.data.range(31, 16) = ap_uint<16>(weighted_sum.range(15, 0));
    m_axi_out.write(out1);
}
""".strip()


def h1_probe_wrapper_source(*, delayed: bool) -> str:
    delay_block = ""
    delay_lane = "0"
    if delayed:
        delay_block = """
    ap_uint<32> delay_acc = ap_uint<16>(full_sum.range(15, 0));
    for (int i = 0; i < 200000; ++i) {
        #pragma HLS PIPELINE II=1
        delay_acc += (ap_uint<32>(i) ^ ap_uint<16>(full_sum.range(15, 0)));
    }
"""
        delay_lane = "delay_acc.range(15, 0)"

    return f"""
#include "coyote_qkeras_infer.hpp"

void coyote_qkeras_infer(hls::stream<axi_s> &s_axi_in, hls::stream<axi_s> &m_axi_out) {{
    #pragma HLS INTERFACE ap_ctrl_none port=return
    #pragma HLS INTERFACE axis register port=s_axi_in name=s_axi_in
    #pragma HLS INTERFACE axis register port=m_axi_out name=m_axi_out

    static ap_uint<16> frame_counter = 0;

    ap_uint<16> this_frame = frame_counter;
    ap_int<48> full_sum = 0;
    ap_int<64> weighted_sum = 0;
    ap_int<16> first_lane0 = 0;
    ap_int<16> last_lane0 = 0;
    ap_uint<16> tlast_count = 0;
    ap_uint<16> first_tlast_beat = 0xffff;
    ap_uint<16> last_tlast_beat = 0xffff;
    ap_uint<16> keep_error_count = 0;
    ap_uint<16> early_tlast = 0;
    ap_uint<16> missing_tlast = 0;

    for (int beat = 0; beat < INPUT_BEATS; ++beat) {{
        axi_s word = s_axi_in.read();
        if (word.keep != ap_uint<64>(-1)) {{
            keep_error_count++;
        }}
        if (word.last) {{
            if (tlast_count == 0) {{
                first_tlast_beat = beat;
            }}
            last_tlast_beat = beat;
            tlast_count++;
            if (beat != INPUT_BEATS - 1) {{
                early_tlast = 1;
            }}
        }}
        ap_int<FIXED_WIDTH> lane0 = word.data.range(FIXED_WIDTH - 1, 0);
        if (beat == 0) {{
            first_lane0 = lane0;
        }}
        if (beat == INPUT_BEATS - 1) {{
            last_lane0 = lane0;
        }}
        for (int lane = 0; lane < PIXELS_PER_BEAT; ++lane) {{
            #pragma HLS PIPELINE II=1
            ap_int<FIXED_WIDTH> raw = word.data.range((lane + 1) * FIXED_WIDTH - 1, lane * FIXED_WIDTH);
            ap_int<48> value = raw;
            full_sum += value;
            weighted_sum += value * (beat * PIXELS_PER_BEAT + lane + 1);
        }}
    }}

    if (tlast_count == 0 || last_tlast_beat != INPUT_BEATS - 1) {{
        missing_tlast = 1;
    }}
{delay_block}
    axi_s out;
    out.data = 0;
    out.keep = -1;
    out.last = 1;
    out.data.range(15, 0) = ap_uint<16>(0x4831);
    out.data.range(31, 16) = this_frame;
    out.data.range(47, 32) = ap_uint<16>(INPUT_BEATS);
    out.data.range(63, 48) = tlast_count;
    out.data.range(79, 64) = first_tlast_beat;
    out.data.range(95, 80) = last_tlast_beat;
    out.data.range(111, 96) = early_tlast;
    out.data.range(127, 112) = missing_tlast;
    out.data.range(143, 128) = keep_error_count;
    out.data.range(159, 144) = ap_uint<16>(full_sum.range(15, 0));
    out.data.range(175, 160) = ap_uint<16>(weighted_sum.range(15, 0));
    out.data.range(191, 176) = ap_uint<16>(first_lane0.range(15, 0));
    out.data.range(207, 192) = ap_uint<16>(last_lane0.range(15, 0));
    out.data.range(223, 208) = ap_uint<16>({delay_lane});
    out.data.range(239, 224) = ap_uint<16>(0);
    out.data.range(255, 240) = ap_uint<16>(0);
    m_axi_out.write(out);
    frame_counter = this_frame + 1;
}}
""".strip()


def framed_buffered_cnn_wrapper_source(top_header_name: str, top_function: str) -> str:
    return f"""
#include "coyote_qkeras_infer.hpp"
#include "{top_header_name}"
#include "{top_function}.cpp"

void coyote_qkeras_infer(hls::stream<axi_s> &s_axi_in, hls::stream<axi_s> &m_axi_out) {{
    #pragma HLS INTERFACE ap_ctrl_none port=return
    #pragma HLS INTERFACE axis register port=s_axi_in name=s_axi_in
    #pragma HLS INTERFACE axis register port=m_axi_out name=m_axi_out

    static ap_uint<16> frame_counter = 0;

    hls::stream<input_t> nn_in("nn_in");
    hls::stream<result_t> nn_out("nn_out");
    #pragma HLS STREAM variable=nn_in depth=INPUT_PIXELS
    #pragma HLS STREAM variable=nn_out depth=2
    #pragma HLS bind_storage variable=nn_in type=fifo impl=bram

    ap_uint<16> this_frame = frame_counter;
    ap_int<48> full_sum = 0;
    ap_int<64> weighted_sum = 0;
    ap_int<16> first_lane0 = 0;
    ap_int<16> last_lane0 = 0;
    ap_uint<16> tlast_count = 0;
    ap_uint<16> first_tlast_beat = 0xffff;
    ap_uint<16> last_tlast_beat = 0xffff;
    ap_uint<16> keep_error_count = 0;
    ap_uint<16> early_tlast = 0;
    ap_uint<16> missing_tlast = 0;

    for (int beat = 0; beat < INPUT_BEATS; ++beat) {{
        axi_s word = s_axi_in.read();
        if (word.keep != ap_uint<64>(-1)) {{
            keep_error_count++;
        }}
        if (word.last) {{
            if (tlast_count == 0) {{
                first_tlast_beat = beat;
            }}
            last_tlast_beat = beat;
            tlast_count++;
            if (beat != INPUT_BEATS - 1) {{
                early_tlast = 1;
            }}
        }}

        ap_int<FIXED_WIDTH> lane0 = word.data.range(FIXED_WIDTH - 1, 0);
        if (beat == 0) {{
            first_lane0 = lane0;
        }}
        if (beat == INPUT_BEATS - 1) {{
            last_lane0 = lane0;
        }}

        for (int lane = 0; lane < PIXELS_PER_BEAT; ++lane) {{
            #pragma HLS PIPELINE II=1
            ap_int<FIXED_WIDTH> raw = word.data.range((lane + 1) * FIXED_WIDTH - 1, lane * FIXED_WIDTH);
            input_t item;
            packed_input_t value;
            value.range(FIXED_WIDTH - 1, 0) = raw;
            item[0] = value;
            nn_in.write(item);
            ap_int<48> signed_raw = raw;
            full_sum += signed_raw;
            weighted_sum += signed_raw * (beat * PIXELS_PER_BEAT + lane + 1);
        }}
    }}

    if (tlast_count == 0 || last_tlast_beat != INPUT_BEATS - 1) {{
        missing_tlast = 1;
    }}

    {top_function}(nn_in, nn_out);
    result_t y = nn_out.read();

    axi_s out_word;
    out_word.data = 0;
    out_word.keep = -1;
    out_word.last = 1;
    packed_output_t out_value = y[0];
    out_word.data.range(15, 0) = out_value.range(15, 0);
    out_word.data.range(31, 16) = ap_uint<16>(0x4642);
    out_word.data.range(47, 32) = this_frame;
    out_word.data.range(63, 48) = ap_uint<16>(INPUT_BEATS);
    out_word.data.range(79, 64) = tlast_count;
    out_word.data.range(95, 80) = first_tlast_beat;
    out_word.data.range(111, 96) = last_tlast_beat;
    out_word.data.range(127, 112) = early_tlast;
    out_word.data.range(143, 128) = missing_tlast;
    out_word.data.range(159, 144) = keep_error_count;
    out_word.data.range(175, 160) = ap_uint<16>(full_sum.range(15, 0));
    out_word.data.range(191, 176) = ap_uint<16>(weighted_sum.range(15, 0));
    out_word.data.range(207, 192) = ap_uint<16>(first_lane0.range(15, 0));
    out_word.data.range(223, 208) = ap_uint<16>(last_lane0.range(15, 0));
    m_axi_out.write(out_word);
    frame_counter = this_frame + 1;
}}
""".strip()


def replicated_logit_2beat_cnn_wrapper_source(top_header_name: str, top_function: str) -> str:
    return f"""
#include "coyote_qkeras_infer.hpp"
#include "{top_header_name}"
#include "{top_function}.cpp"

void coyote_qkeras_infer(hls::stream<axi_s> &s_axi_in, hls::stream<axi_s> &m_axi_out) {{
    #pragma HLS INTERFACE ap_ctrl_none port=return
    #pragma HLS INTERFACE axis register port=s_axi_in name=s_axi_in
    #pragma HLS INTERFACE axis register port=m_axi_out name=m_axi_out

    static ap_uint<16> frame_counter = 0;

    hls::stream<input_t> nn_in("nn_in");
    hls::stream<result_t> nn_out("nn_out");
    #pragma HLS STREAM variable=nn_in depth=INPUT_PIXELS
    #pragma HLS STREAM variable=nn_out depth=2
    #pragma HLS bind_storage variable=nn_in type=fifo impl=bram

    ap_uint<16> this_frame = frame_counter;
    ap_int<48> full_sum = 0;
    ap_int<64> weighted_sum = 0;
    ap_int<16> first_lane0 = 0;
    ap_int<16> last_lane0 = 0;
    ap_uint<16> tlast_count = 0;
    ap_uint<16> first_tlast_beat = 0xffff;
    ap_uint<16> last_tlast_beat = 0xffff;
    ap_uint<16> keep_error_count = 0;
    ap_uint<16> early_tlast = 0;
    ap_uint<16> missing_tlast = 0;

    for (int beat = 0; beat < INPUT_BEATS; ++beat) {{
        axi_s word = s_axi_in.read();
        if (word.keep != ap_uint<64>(-1)) {{
            keep_error_count++;
        }}
        if (word.last) {{
            if (tlast_count == 0) {{
                first_tlast_beat = beat;
            }}
            last_tlast_beat = beat;
            tlast_count++;
            if (beat != INPUT_BEATS - 1) {{
                early_tlast = 1;
            }}
        }}

        ap_int<FIXED_WIDTH> lane0 = word.data.range(FIXED_WIDTH - 1, 0);
        if (beat == 0) {{
            first_lane0 = lane0;
        }}
        if (beat == INPUT_BEATS - 1) {{
            last_lane0 = lane0;
        }}

        for (int lane = 0; lane < PIXELS_PER_BEAT; ++lane) {{
            #pragma HLS PIPELINE II=1
            ap_int<FIXED_WIDTH> raw = word.data.range((lane + 1) * FIXED_WIDTH - 1, lane * FIXED_WIDTH);
            input_t item;
            packed_input_t value;
            value.range(FIXED_WIDTH - 1, 0) = raw;
            item[0] = value;
            nn_in.write(item);
            ap_int<48> signed_raw = raw;
            full_sum += signed_raw;
            weighted_sum += signed_raw * (beat * PIXELS_PER_BEAT + lane + 1);
        }}
    }}

    if (tlast_count == 0 || last_tlast_beat != INPUT_BEATS - 1) {{
        missing_tlast = 1;
    }}

    {top_function}(nn_in, nn_out);
    result_t y = nn_out.read();
    packed_output_t out_value = y[0];
    ap_uint<16> raw_logit = out_value.range(15, 0);

    axi_s debug_word;
    debug_word.data = 0;
    debug_word.keep = -1;
    debug_word.last = 0;
    debug_word.data.range(15, 0) = ap_uint<16>(0x5232);
    debug_word.data.range(31, 16) = this_frame;
    debug_word.data.range(47, 32) = ap_uint<16>(INPUT_BEATS);
    debug_word.data.range(63, 48) = tlast_count;
    debug_word.data.range(79, 64) = first_tlast_beat;
    debug_word.data.range(95, 80) = last_tlast_beat;
    debug_word.data.range(111, 96) = early_tlast;
    debug_word.data.range(127, 112) = missing_tlast;
    debug_word.data.range(143, 128) = keep_error_count;
    debug_word.data.range(159, 144) = ap_uint<16>(full_sum.range(15, 0));
    debug_word.data.range(175, 160) = ap_uint<16>(weighted_sum.range(15, 0));
    debug_word.data.range(191, 176) = ap_uint<16>(first_lane0.range(15, 0));
    debug_word.data.range(207, 192) = ap_uint<16>(last_lane0.range(15, 0));
    debug_word.data.range(223, 208) = raw_logit;
    debug_word.data.range(239, 224) = ap_uint<16>(1);
    m_axi_out.write(debug_word);

    axi_s logit_word;
    logit_word.data = 0;
    logit_word.keep = -1;
    logit_word.last = 1;
    for (int lane = 0; lane < PIXELS_PER_BEAT; ++lane) {{
        #pragma HLS UNROLL
        logit_word.data.range((lane + 1) * FIXED_WIDTH - 1, lane * FIXED_WIDTH) = raw_logit;
    }}
    m_axi_out.write(logit_word);
    frame_counter = this_frame + 1;
}}
""".strip()


def rom_cnn_wrapper_source(top_header_name: str, top_function: str) -> str:
    return f"""
#include "coyote_qkeras_infer.hpp"
#include "rom_input_values.hpp"
#include "{top_header_name}"
#include "{top_function}.cpp"

void coyote_qkeras_infer(hls::stream<axi_s> &s_axi_in, hls::stream<axi_s> &m_axi_out) {{
    #pragma HLS INTERFACE ap_ctrl_none port=return
    #pragma HLS INTERFACE axis register port=s_axi_in name=s_axi_in
    #pragma HLS INTERFACE axis register port=m_axi_out name=m_axi_out

    static ap_uint<16> frame_counter = 0;

    hls::stream<input_t> nn_in("nn_in");
    hls::stream<result_t> nn_out("nn_out");
    #pragma HLS STREAM variable=nn_in depth=INPUT_PIXELS
    #pragma HLS STREAM variable=nn_out depth=2
    #pragma HLS bind_storage variable=nn_in type=fifo impl=bram

    ap_uint<16> this_frame = frame_counter;
    ap_int<48> full_sum = 0;
    ap_int<64> weighted_sum = 0;
    ap_int<16> first_lane0 = 0;
    ap_int<16> last_lane0 = 0;
    ap_uint<16> tlast_count = 0;
    ap_uint<16> first_tlast_beat = 0xffff;
    ap_uint<16> last_tlast_beat = 0xffff;
    ap_uint<16> keep_error_count = 0;
    ap_uint<16> early_tlast = 0;
    ap_uint<16> missing_tlast = 0;

    for (int beat = 0; beat < INPUT_BEATS; ++beat) {{
        axi_s word = s_axi_in.read();
        if (word.keep != ap_uint<64>(-1)) {{
            keep_error_count++;
        }}
        if (word.last) {{
            if (tlast_count == 0) {{
                first_tlast_beat = beat;
            }}
            last_tlast_beat = beat;
            tlast_count++;
            if (beat != INPUT_BEATS - 1) {{
                early_tlast = 1;
            }}
        }}

        ap_int<FIXED_WIDTH> lane0 = word.data.range(FIXED_WIDTH - 1, 0);
        if (beat == 0) {{
            first_lane0 = lane0;
        }}
        if (beat == INPUT_BEATS - 1) {{
            last_lane0 = lane0;
        }}

        for (int lane = 0; lane < PIXELS_PER_BEAT; ++lane) {{
            #pragma HLS PIPELINE II=1
            ap_int<FIXED_WIDTH> raw = word.data.range((lane + 1) * FIXED_WIDTH - 1, lane * FIXED_WIDTH);
            ap_int<48> signed_raw = raw;
            full_sum += signed_raw;
            weighted_sum += signed_raw * (beat * PIXELS_PER_BEAT + lane + 1);
        }}
    }}

    if (tlast_count == 0 || last_tlast_beat != INPUT_BEATS - 1) {{
        missing_tlast = 1;
    }}

    for (int pix = 0; pix < INPUT_PIXELS; ++pix) {{
        #pragma HLS PIPELINE II=1
        input_t item;
        packed_input_t value;
        value.range(FIXED_WIDTH - 1, 0) = ROM_INPUT_VALUES[pix];
        item[0] = value;
        nn_in.write(item);
    }}

    {top_function}(nn_in, nn_out);
    result_t y = nn_out.read();

    axi_s out_word;
    out_word.data = 0;
    out_word.keep = -1;
    out_word.last = 1;
    packed_output_t out_value = y[0];
    out_word.data.range(15, 0) = out_value.range(15, 0);
    out_word.data.range(31, 16) = ap_uint<16>(0x524d);
    out_word.data.range(47, 32) = this_frame;
    out_word.data.range(63, 48) = ap_uint<16>(INPUT_BEATS);
    out_word.data.range(79, 64) = tlast_count;
    out_word.data.range(95, 80) = first_tlast_beat;
    out_word.data.range(111, 96) = last_tlast_beat;
    out_word.data.range(127, 112) = early_tlast;
    out_word.data.range(143, 128) = missing_tlast;
    out_word.data.range(159, 144) = keep_error_count;
    out_word.data.range(175, 160) = ap_uint<16>(full_sum.range(15, 0));
    out_word.data.range(191, 176) = ap_uint<16>(weighted_sum.range(15, 0));
    out_word.data.range(207, 192) = ap_uint<16>(first_lane0.range(15, 0));
    out_word.data.range(223, 208) = ap_uint<16>(last_lane0.range(15, 0));
    out_word.data.range(239, 224) = ap_uint<16>(ROM_INPUT_KIND);
    out_word.data.range(255, 240) = ap_uint<16>(ROM_INPUT_SAMPLE_INDEX);
    m_axi_out.write(out_word);
    frame_counter = this_frame + 1;
}}
""".strip()


def rom_control_probe_wrapper_source(top_header_name: str, top_function: str, delay_cycles: int) -> str:
    return f"""
#include "coyote_qkeras_infer.hpp"
#include "rom_input_values.hpp"
#include "{top_header_name}"
#include "{top_function}.cpp"

static void fill_rom_input(hls::stream<input_t> &nn_in, bool zero_input) {{
    #pragma HLS INLINE off
    for (int pix = 0; pix < INPUT_PIXELS; ++pix) {{
        #pragma HLS PIPELINE II=1
        input_t item;
        packed_input_t value;
        if (zero_input) {{
            value = 0;
        }} else {{
            value.range(FIXED_WIDTH - 1, 0) = ROM_INPUT_VALUES[pix];
        }}
        item[0] = value;
        nn_in.write(item);
    }}
}}

static ap_uint<16> run_rom_network(bool zero_input) {{
    #pragma HLS INLINE off
    hls::stream<input_t> nn_in("nn_in_control");
    hls::stream<result_t> nn_out("nn_out_control");
    #pragma HLS STREAM variable=nn_in depth=INPUT_PIXELS
    #pragma HLS STREAM variable=nn_out depth=2
    #pragma HLS bind_storage variable=nn_in type=fifo impl=bram

    fill_rom_input(nn_in, zero_input);
    {top_function}(nn_in, nn_out);
    result_t y = nn_out.read();
    packed_output_t out_value = y[0];
    return out_value.range(15, 0);
}}

void coyote_qkeras_infer(hls::stream<axi_s> &s_axi_in, hls::stream<axi_s> &m_axi_out) {{
    #pragma HLS INTERFACE ap_ctrl_none port=return
    #pragma HLS INTERFACE axis register port=s_axi_in name=s_axi_in
    #pragma HLS INTERFACE axis register port=m_axi_out name=m_axi_out

    static ap_uint<16> frame_counter = 0;

    ap_uint<16> this_frame = frame_counter;
    ap_int<48> full_sum = 0;
    ap_int<64> weighted_sum = 0;
    ap_int<16> first_lane0 = 0;
    ap_int<16> last_lane0 = 0;
    ap_uint<16> tlast_count = 0;
    ap_uint<16> first_tlast_beat = 0xffff;
    ap_uint<16> last_tlast_beat = 0xffff;
    ap_uint<16> keep_error_count = 0;
    ap_uint<16> early_tlast = 0;
    ap_uint<16> missing_tlast = 0;

    for (int beat = 0; beat < INPUT_BEATS; ++beat) {{
        axi_s word = s_axi_in.read();
        if (word.keep != ap_uint<64>(-1)) {{
            keep_error_count++;
        }}
        if (word.last) {{
            if (tlast_count == 0) {{
                first_tlast_beat = beat;
            }}
            last_tlast_beat = beat;
            tlast_count++;
            if (beat != INPUT_BEATS - 1) {{
                early_tlast = 1;
            }}
        }}

        ap_int<FIXED_WIDTH> lane0 = word.data.range(FIXED_WIDTH - 1, 0);
        if (beat == 0) {{
            first_lane0 = lane0;
        }}
        if (beat == INPUT_BEATS - 1) {{
            last_lane0 = lane0;
        }}

        for (int lane = 0; lane < PIXELS_PER_BEAT; ++lane) {{
            #pragma HLS PIPELINE II=1
            ap_int<FIXED_WIDTH> raw = word.data.range((lane + 1) * FIXED_WIDTH - 1, lane * FIXED_WIDTH);
            ap_int<48> signed_raw = raw;
            full_sum += signed_raw;
            weighted_sum += signed_raw * (beat * PIXELS_PER_BEAT + lane + 1);
        }}
    }}

    if (tlast_count == 0 || last_tlast_beat != INPUT_BEATS - 1) {{
        missing_tlast = 1;
    }}

    ap_uint<32> delay_acc = 0;
    for (int i = 0; i < {delay_cycles}; ++i) {{
        #pragma HLS PIPELINE II=1
        delay_acc += ap_uint<32>(i) ^ ap_uint<16>(this_frame);
    }}

    ap_uint<16> logit_a = run_rom_network(false);
    ap_uint<16> logit_b = run_rom_network(false);
    ap_uint<16> logit_c = run_rom_network(true);
    ap_uint<16> logit_d = run_rom_network(false);

    axi_s out_word;
    out_word.data = 0;
    out_word.keep = -1;
    out_word.last = 1;
    out_word.data.range(15, 0) = logit_a;
    out_word.data.range(31, 16) = logit_b;
    out_word.data.range(47, 32) = logit_c;
    out_word.data.range(63, 48) = logit_d;
    out_word.data.range(79, 64) = ap_uint<16>(0x4350);
    out_word.data.range(95, 80) = this_frame;
    out_word.data.range(111, 96) = ap_uint<16>({delay_cycles} & 0xffff);
    out_word.data.range(127, 112) = ap_uint<16>((delay_acc >> 16) & 0xffff);
    out_word.data.range(143, 128) = ap_uint<16>(INPUT_BEATS);
    out_word.data.range(159, 144) = tlast_count;
    out_word.data.range(175, 160) = first_tlast_beat;
    out_word.data.range(191, 176) = last_tlast_beat;
    out_word.data.range(207, 192) = early_tlast;
    out_word.data.range(223, 208) = missing_tlast;
    out_word.data.range(239, 224) = keep_error_count;
    out_word.data.range(255, 240) = ROM_INPUT_SAMPLE_INDEX;
    m_axi_out.write(out_word);
    frame_counter = this_frame + 1;
}}
""".strip()


def rom_layer_probe_wrapper_source(top_header_name: str, top_function: str) -> str:
    return f"""
#include "coyote_qkeras_infer.hpp"
#include "rom_input_values.hpp"
#include "{top_header_name}"
#include "{top_function}.cpp"

template <typename T>
static void checksum_stream(hls::stream<T> &src, hls::stream<T> &dst, int n_words, hls::stream<ap_uint<16> > &checksum_out) {{
    #pragma HLS INLINE off
    ap_fixed<48, 24> sum = 0;
    for (int i = 0; i < n_words; ++i) {{
        T item = src.read();
        for (unsigned lane = 0; lane < T::size; ++lane) {{
            #pragma HLS UNROLL
            sum += item[lane];
        }}
        dst.write(item);
    }}
    ap_int<48> scaled = sum * ap_int<16>(1024);
    checksum_out.write(ap_uint<16>(scaled.range(15, 0)));
}}

template <typename T>
static void checksum_sink(hls::stream<T> &src, int n_words, hls::stream<ap_uint<16> > &checksum_out) {{
    #pragma HLS INLINE off
    ap_fixed<48, 24> sum = 0;
    for (int i = 0; i < n_words; ++i) {{
        T item = src.read();
        for (unsigned lane = 0; lane < T::size; ++lane) {{
            #pragma HLS UNROLL
            sum += item[lane];
        }}
    }}
    ap_int<48> scaled = sum * ap_int<16>(1024);
    checksum_out.write(ap_uint<16>(scaled.range(15, 0)));
}}

static void feed_rom_input(hls::stream<input_t> &bitstream_input, hls::stream<ap_uint<16> > &input_debug) {{
    #pragma HLS INLINE off
    ap_fixed<48, 24> sum = 0;
    for (int pix = 0; pix < INPUT_PIXELS; ++pix) {{
        #pragma HLS PIPELINE II=1
        input_t item;
        packed_input_t value;
        value.range(FIXED_WIDTH - 1, 0) = ROM_INPUT_VALUES[pix];
        item[0] = value;
        bitstream_input.write(item);
        sum += value;
        if (pix < 8) {{
            input_debug.write(ap_uint<16>(value.range(15, 0)));
        }}
    }}
    ap_int<48> scaled = sum * ap_int<16>(1024);
    input_debug.write(ap_uint<16>(scaled.range(15, 0)));
}}

static void probed_network(
    hls::stream<input_t> &bitstream_input,
    hls::stream<result_t> &layer29_out,
    hls::stream<ap_uint<16> > &conv0_checksum,
    hls::stream<ap_uint<16> > &pool0_checksum,
    hls::stream<ap_uint<16> > &conv4_checksum,
    hls::stream<ap_uint<16> > &gap_checksum,
    hls::stream<ap_uint<16> > &gap_first
) {{
    #pragma HLS INLINE off
    #pragma HLS DATAFLOW

#ifndef __SYNTHESIS__
    static bool loaded_weights = false;
    if (!loaded_weights) {{
        nnet::load_weights_from_txt<weight3_t, 200>(w3, "w3.txt");
        nnet::load_weights_from_txt<bias3_t, 8>(b3, "b3.txt");
        nnet::load_weights_from_txt<weight8_t, 1152>(w8, "w8.txt");
        nnet::load_weights_from_txt<bias8_t, 16>(b8, "b8.txt");
        nnet::load_weights_from_txt<weight13_t, 3456>(w13, "w13.txt");
        nnet::load_weights_from_txt<bias13_t, 24>(b13, "b13.txt");
        nnet::load_weights_from_txt<weight18_t, 5184>(w18, "w18.txt");
        nnet::load_weights_from_txt<bias18_t, 24>(b18, "b18.txt");
        nnet::load_weights_from_txt<weight23_t, 6912>(w23, "w23.txt");
        nnet::load_weights_from_txt<bias23_t, 32>(b23, "b23.txt");
        nnet::load_weights_from_txt<weight29_t, 32>(w29, "w29.txt");
        nnet::load_weights_from_txt<bias29_t, 1>(b29, "b29.txt");
        loaded_weights = true;
    }}
#endif

    hls::stream<layer2_t> layer2_out("layer2_out");
    #pragma HLS STREAM variable=layer2_out depth=67600
    hls::stream<conv0_result_t> layer3_raw("layer3_raw");
    hls::stream<conv0_result_t> layer3_out("layer3_out");
    #pragma HLS STREAM variable=layer3_raw depth=16384
    #pragma HLS STREAM variable=layer3_out depth=16384
    hls::stream<layer5_t> layer5_out("layer5_out");
    #pragma HLS STREAM variable=layer5_out depth=16384
    hls::stream<layer6_t> layer6_raw("layer6_raw");
    hls::stream<layer6_t> layer6_out("layer6_out");
    #pragma HLS STREAM variable=layer6_raw depth=4096
    #pragma HLS STREAM variable=layer6_out depth=4096
    hls::stream<layer7_t> layer7_out("layer7_out");
    #pragma HLS STREAM variable=layer7_out depth=4356
    hls::stream<conv1_result_t> layer8_out("layer8_out");
    #pragma HLS STREAM variable=layer8_out depth=4096
    hls::stream<layer10_t> layer10_out("layer10_out");
    #pragma HLS STREAM variable=layer10_out depth=4096
    hls::stream<layer11_t> layer11_out("layer11_out");
    #pragma HLS STREAM variable=layer11_out depth=1024
    hls::stream<layer12_t> layer12_out("layer12_out");
    #pragma HLS STREAM variable=layer12_out depth=1156
    hls::stream<conv2_result_t> layer13_out("layer13_out");
    #pragma HLS STREAM variable=layer13_out depth=1024
    hls::stream<layer15_t> layer15_out("layer15_out");
    #pragma HLS STREAM variable=layer15_out depth=1024
    hls::stream<layer16_t> layer16_out("layer16_out");
    #pragma HLS STREAM variable=layer16_out depth=256
    hls::stream<layer17_t> layer17_out("layer17_out");
    #pragma HLS STREAM variable=layer17_out depth=324
    hls::stream<conv3_result_t> layer18_out("layer18_out");
    #pragma HLS STREAM variable=layer18_out depth=256
    hls::stream<layer20_t> layer20_out("layer20_out");
    #pragma HLS STREAM variable=layer20_out depth=256
    hls::stream<layer21_t> layer21_out("layer21_out");
    #pragma HLS STREAM variable=layer21_out depth=64
    hls::stream<layer22_t> layer22_out("layer22_out");
    #pragma HLS STREAM variable=layer22_out depth=100
    hls::stream<conv4_result_t> layer23_raw("layer23_raw");
    hls::stream<conv4_result_t> layer23_out("layer23_out");
    #pragma HLS STREAM variable=layer23_raw depth=64
    #pragma HLS STREAM variable=layer23_out depth=64
    hls::stream<layer25_t> layer25_out("layer25_out");
    #pragma HLS STREAM variable=layer25_out depth=64
    hls::stream<layer26_t> layer26_out("layer26_out");
    #pragma HLS STREAM variable=layer26_out depth=16
    hls::stream<layer27_t> layer27_raw("layer27_raw");
    hls::stream<layer27_t> layer27_for_dense("layer27_for_dense");
    #pragma HLS STREAM variable=layer27_raw depth=1
    #pragma HLS STREAM variable=layer27_for_dense depth=1

    nnet::zeropad2d_cl<input_t, layer2_t, config2>(bitstream_input, layer2_out);
    nnet::conv_2d_cl<layer2_t, conv0_result_t, config3>(layer2_out, layer3_raw, w3, b3);
    checksum_stream<conv0_result_t>(layer3_raw, layer3_out, 128 * 128, conv0_checksum);
    nnet::relu<conv0_result_t, layer5_t, relu_config5>(layer3_out, layer5_out);
    nnet::pooling2d_cl<layer5_t, layer6_t, config6>(layer5_out, layer6_raw);
    checksum_stream<layer6_t>(layer6_raw, layer6_out, 64 * 64, pool0_checksum);
    nnet::zeropad2d_cl<layer6_t, layer7_t, config7>(layer6_out, layer7_out);
    nnet::conv_2d_cl<layer7_t, conv1_result_t, config8>(layer7_out, layer8_out, w8, b8);
    nnet::relu<conv1_result_t, layer10_t, relu_config10>(layer8_out, layer10_out);
    nnet::pooling2d_cl<layer10_t, layer11_t, config11>(layer10_out, layer11_out);
    nnet::zeropad2d_cl<layer11_t, layer12_t, config12>(layer11_out, layer12_out);
    nnet::conv_2d_cl<layer12_t, conv2_result_t, config13>(layer12_out, layer13_out, w13, b13);
    nnet::relu<conv2_result_t, layer15_t, relu_config15>(layer13_out, layer15_out);
    nnet::pooling2d_cl<layer15_t, layer16_t, config16>(layer15_out, layer16_out);
    nnet::zeropad2d_cl<layer16_t, layer17_t, config17>(layer16_out, layer17_out);
    nnet::conv_2d_cl<layer17_t, conv3_result_t, config18>(layer17_out, layer18_out, w18, b18);
    nnet::relu<conv3_result_t, layer20_t, relu_config20>(layer18_out, layer20_out);
    nnet::pooling2d_cl<layer20_t, layer21_t, config21>(layer20_out, layer21_out);
    nnet::zeropad2d_cl<layer21_t, layer22_t, config22>(layer21_out, layer22_out);
    nnet::conv_2d_cl<layer22_t, conv4_result_t, config23>(layer22_out, layer23_raw, w23, b23);
    checksum_stream<conv4_result_t>(layer23_raw, layer23_out, 8 * 8, conv4_checksum);
    nnet::relu<conv4_result_t, layer25_t, relu_config25>(layer23_out, layer25_out);
    nnet::pooling2d_cl<layer25_t, layer26_t, config26>(layer25_out, layer26_out);
    nnet::pooling2d_cl<layer26_t, layer27_t, config27>(layer26_out, layer27_raw);

    layer27_t gap_item = layer27_raw.read();
    ap_fixed<48, 24> gap_sum = 0;
    for (unsigned lane = 0; lane < layer27_t::size; ++lane) {{
        #pragma HLS UNROLL
        gap_sum += gap_item[lane];
        if (lane < 4) {{
            ap_int<32> scaled_lane = gap_item[lane] * ap_int<16>(1024);
            gap_first.write(ap_uint<16>(scaled_lane.range(15, 0)));
        }}
    }}
    ap_int<48> scaled_gap = gap_sum * ap_int<16>(1024);
    gap_checksum.write(ap_uint<16>(scaled_gap.range(15, 0)));
    layer27_for_dense.write(gap_item);

    nnet::dense<layer27_t, result_t, config29>(layer27_for_dense, layer29_out, w29, b29);
}}

void coyote_qkeras_infer(hls::stream<axi_s> &s_axi_in, hls::stream<axi_s> &m_axi_out) {{
    #pragma HLS INTERFACE ap_ctrl_none port=return
    #pragma HLS INTERFACE axis register port=s_axi_in name=s_axi_in
    #pragma HLS INTERFACE axis register port=m_axi_out name=m_axi_out
    #pragma HLS DATAFLOW

    static ap_uint<16> frame_counter = 0;

    for (int beat = 0; beat < INPUT_BEATS; ++beat) {{
        axi_s word = s_axi_in.read();
    }}

    hls::stream<input_t> bitstream_input("bitstream_input");
    hls::stream<result_t> layer29_out("layer29_out");
    hls::stream<ap_uint<16> > input_debug("input_debug");
    hls::stream<ap_uint<16> > conv0_checksum("conv0_checksum");
    hls::stream<ap_uint<16> > pool0_checksum("pool0_checksum");
    hls::stream<ap_uint<16> > conv4_checksum("conv4_checksum");
    hls::stream<ap_uint<16> > gap_checksum("gap_checksum");
    hls::stream<ap_uint<16> > gap_first("gap_first");
    #pragma HLS STREAM variable=bitstream_input depth=1024
    #pragma HLS STREAM variable=layer29_out depth=2
    #pragma HLS STREAM variable=input_debug depth=16
    #pragma HLS STREAM variable=conv0_checksum depth=2
    #pragma HLS STREAM variable=pool0_checksum depth=2
    #pragma HLS STREAM variable=conv4_checksum depth=2
    #pragma HLS STREAM variable=gap_checksum depth=2
    #pragma HLS STREAM variable=gap_first depth=8

    feed_rom_input(bitstream_input, input_debug);
    probed_network(bitstream_input, layer29_out, conv0_checksum, pool0_checksum, conv4_checksum, gap_checksum, gap_first);

    result_t y = layer29_out.read();
    packed_output_t out_value = y[0];

    axi_s out_word;
    out_word.data = 0;
    out_word.keep = -1;
    out_word.last = 1;
    out_word.data.range(15, 0) = out_value.range(15, 0);
    out_word.data.range(31, 16) = ap_uint<16>(0x4c50);
    out_word.data.range(47, 32) = frame_counter;
    for (int i = 0; i < 8; ++i) {{
        #pragma HLS PIPELINE II=1
        ap_uint<16> raw = input_debug.read();
        out_word.data.range((i + 4) * 16 - 1, (i + 3) * 16) = raw;
    }}
    out_word.data.range(191, 176) = input_debug.read();
    out_word.data.range(207, 192) = conv0_checksum.read();
    out_word.data.range(223, 208) = pool0_checksum.read();
    out_word.data.range(239, 224) = conv4_checksum.read();
    out_word.data.range(255, 240) = gap_checksum.read();
    for (int i = 0; i < 4; ++i) {{
        #pragma HLS PIPELINE II=1
        ap_uint<16> raw = gap_first.read();
        out_word.data.range((i + 17) * 16 - 1, (i + 16) * 16) = raw;
    }}
    m_axi_out.write(out_word);
    frame_counter = frame_counter + 1;
}}
""".strip()


def write_rom_input_header(ctx: FlowContext, kernel_dir: Path) -> dict[str, Any]:
    diag_cfg = ctx.config.get("u55c", {}).get("diagnostic", {}) or {}
    source = str(diag_cfg.get("rom_input", "sample0")).strip().lower()
    sample_index = int(diag_cfg.get("rom_sample_index", 0))
    n_values = int(ctx.abi["pixels_per_sample"])

    if source in {"zero", "zeros", "all_zero", "all-zero"}:
        values = np.zeros(n_values, dtype=np.int16)
        source_kind = 0
        sample_index = 0
        source_path = ""
    elif source in {"sample0", "sample", "prepared"}:
        source_path_obj = ctx.prepared_inputs_dir / f"sample_{sample_index:04d}.bin"
        if not source_path_obj.exists():
            raise FileNotFoundError(source_path_obj)
        values = np.fromfile(source_path_obj, dtype="<i2")
        if values.size != n_values:
            raise ValueError(f"expected {n_values} ROM input values, got {values.size}: {source_path_obj}")
        source_kind = 1
        source_path = str(source_path_obj)
    else:
        raise ValueError("u55c.diagnostic.rom_input must be 'sample0'/'sample' or 'zero'")

    lines = [
        "#pragma once",
        "",
        f"constexpr int ROM_INPUT_KIND = {source_kind};",
        f"constexpr int ROM_INPUT_SAMPLE_INDEX = {sample_index};",
        "static const ap_int<FIXED_WIDTH> ROM_INPUT_VALUES[INPUT_PIXELS] = {",
    ]
    chunk = 16
    for start in range(0, values.size, chunk):
        part = ", ".join(str(int(v)) for v in values[start : start + chunk])
        comma = "," if start + chunk < values.size else ""
        lines.append(f"    {part}{comma}")
    lines.append("};")
    header_path = kernel_dir / "rom_input_values.hpp"
    header_path.write_text("\n".join(lines) + "\n")
    return {
        "rom_input": source,
        "rom_input_kind": source_kind,
        "rom_sample_index": sample_index,
        "rom_source_path": source_path,
        "rom_values": int(values.size),
        "rom_header": str(header_path),
    }


def stage_kernel_sources(ctx: FlowContext, staged_hw_dir: Path) -> dict[str, Any]:
    conv = read_json(ctx.hls_project_dir / "conversion_manifest.json")
    project_name = conv["project_name"]
    firmware = ctx.hls_project_dir / "firmware"
    top_header = find_top_header(ctx.hls_project_dir, project_name)
    top_cpp = firmware / f"{top_header.stem}.cpp"
    if not top_cpp.exists():
        raise FileNotFoundError(top_cpp)
    kernel_dir = staged_hw_dir / "src" / "hls" / "coyote_qkeras_infer"
    if kernel_dir.exists():
        shutil.rmtree(kernel_dir)
    kernel_dir.mkdir(parents=True, exist_ok=True)
    srcs = list(firmware.glob("*.h")) + list(firmware.glob("*.hpp")) + list(firmware.glob("*.cpp"))
    srcs += list((firmware / "nnet_utils").glob("*.h")) + list((firmware / "nnet_utils").glob("*.hpp"))
    srcs += list((firmware / "weights").glob("*.h"))
    for src in srcs:
        (kernel_dir / src.name).write_text(rewrite_includes(src.read_text(errors="ignore")))
    abi = ctx.abi
    header = f"""
#pragma once

#include "ap_axi_sdata.h"
#include "ap_fixed.h"
#include "ap_int.h"
#include "hls_stream.h"

constexpr int AXI_DATA_BITS = {int(abi['axi_data_bits'])};
constexpr int INPUT_PIXELS = {int(abi['pixels_per_sample'])};
constexpr int FIXED_WIDTH = {int(abi['fixed_width'])};
constexpr int PIXELS_PER_BEAT = AXI_DATA_BITS / FIXED_WIDTH;
constexpr int INPUT_BEATS = INPUT_PIXELS / PIXELS_PER_BEAT;

typedef ap_axiu<AXI_DATA_BITS, 0, 0, 0> axi_s;
typedef ap_fixed<{int(abi['fixed_width'])},{int(abi['fixed_integer'])}> packed_input_t;
typedef ap_fixed<{int(abi['fixed_width'])},{int(abi['fixed_integer'])}> packed_output_t;

void coyote_qkeras_infer(hls::stream<axi_s> &s_axi_in, hls::stream<axi_s> &m_axi_out);
""".strip()
    (kernel_dir / "coyote_qkeras_infer.hpp").write_text(header + "\n")
    mode = diagnostic_mode(ctx)
    extra_info: dict[str, Any] = {}
    if mode == "lane_probe":
        wrapper = lane_probe_wrapper_source()
    elif mode == "h1_framing_probe":
        wrapper = h1_probe_wrapper_source(delayed=False)
    elif mode == "h1_delayed_probe":
        wrapper = h1_probe_wrapper_source(delayed=True)
    elif mode == "framed_buffered_cnn":
        wrapper = framed_buffered_cnn_wrapper_source(top_header.name, top_header.stem)
    elif mode == "replicated_logit_2beat_cnn":
        wrapper = replicated_logit_2beat_cnn_wrapper_source(top_header.name, top_header.stem)
    elif mode == "rom_cnn":
        extra_info.update(write_rom_input_header(ctx, kernel_dir))
        wrapper = rom_cnn_wrapper_source(top_header.name, top_header.stem)
    elif mode == "rom_control_probe":
        extra_info.update(write_rom_input_header(ctx, kernel_dir))
        diag_cfg = ctx.config.get("u55c", {}).get("diagnostic", {}) or {}
        delay_cycles = int(diag_cfg.get("delay_cycles", 65536))
        extra_info["delay_cycles"] = delay_cycles
        wrapper = rom_control_probe_wrapper_source(top_header.name, top_header.stem, delay_cycles)
    elif mode == "rom_layer_probe":
        extra_info.update(write_rom_input_header(ctx, kernel_dir))
        wrapper = rom_layer_probe_wrapper_source(top_header.name, top_header.stem)
    elif mode == "full_streaming":
        wrapper = full_streaming_wrapper_source(top_header.name, top_header.stem)
    else:
        wrapper = baseline_wrapper_source(top_header.name, top_header.stem)
    (kernel_dir / "coyote_qkeras_infer.cpp").write_text(wrapper + "\n")
    return {
        "kernel_dir": str(kernel_dir),
        "top_function": top_header.stem,
        "diagnostic_mode": mode,
        "flattened_files": len(list(kernel_dir.iterdir())),
        **extra_info,
    }


def vfpga_top_source(*, mark_axis_debug: bool) -> str:
    if not mark_axis_debug:
        return """
coyote_qkeras_infer_hls_ip inst_coyote_qkeras_infer(
    .s_axi_in_TDATA         (axis_host_recv[0].tdata),
    .s_axi_in_TKEEP         (axis_host_recv[0].tkeep),
    .s_axi_in_TLAST         (axis_host_recv[0].tlast),
    .s_axi_in_TSTRB         (0),
    .s_axi_in_TVALID        (axis_host_recv[0].tvalid),
    .s_axi_in_TREADY        (axis_host_recv[0].tready),
    .m_axi_out_TDATA        (axis_host_send[0].tdata),
    .m_axi_out_TKEEP        (axis_host_send[0].tkeep),
    .m_axi_out_TLAST        (axis_host_send[0].tlast),
    .m_axi_out_TSTRB        (),
    .m_axi_out_TVALID       (axis_host_send[0].tvalid),
    .m_axi_out_TREADY       (axis_host_send[0].tready),
    .ap_clk                 (aclk),
    .ap_rst_n               (aresetn)
);

always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb notify.tie_off_m();
always_comb axi_ctrl.tie_off_s();
""".strip()

    return """
(* MARK_DEBUG = "true" *) logic [511:0] dbg_hls_s_axis_tdata;
(* MARK_DEBUG = "true" *) logic [63:0]  dbg_hls_s_axis_tkeep;
(* MARK_DEBUG = "true" *) logic         dbg_hls_s_axis_tlast;
(* MARK_DEBUG = "true" *) logic         dbg_hls_s_axis_tvalid;
(* MARK_DEBUG = "true" *) logic         dbg_hls_s_axis_tready;
(* MARK_DEBUG = "true" *) logic [511:0] dbg_hls_m_axis_tdata;
(* MARK_DEBUG = "true" *) logic [63:0]  dbg_hls_m_axis_tkeep;
(* MARK_DEBUG = "true" *) logic         dbg_hls_m_axis_tlast;
(* MARK_DEBUG = "true" *) logic         dbg_hls_m_axis_tvalid;
(* MARK_DEBUG = "true" *) logic         dbg_hls_m_axis_tready;

assign dbg_hls_s_axis_tdata = axis_host_recv[0].tdata;
assign dbg_hls_s_axis_tkeep = axis_host_recv[0].tkeep;
assign dbg_hls_s_axis_tlast = axis_host_recv[0].tlast;
assign dbg_hls_s_axis_tvalid = axis_host_recv[0].tvalid;
assign axis_host_recv[0].tready = dbg_hls_s_axis_tready;

assign axis_host_send[0].tdata = dbg_hls_m_axis_tdata;
assign axis_host_send[0].tkeep = dbg_hls_m_axis_tkeep;
assign axis_host_send[0].tlast = dbg_hls_m_axis_tlast;
assign axis_host_send[0].tvalid = dbg_hls_m_axis_tvalid;
assign dbg_hls_m_axis_tready = axis_host_send[0].tready;

coyote_qkeras_infer_hls_ip inst_coyote_qkeras_infer(
    .s_axi_in_TDATA         (dbg_hls_s_axis_tdata),
    .s_axi_in_TKEEP         (dbg_hls_s_axis_tkeep),
    .s_axi_in_TLAST         (dbg_hls_s_axis_tlast),
    .s_axi_in_TSTRB         (0),
    .s_axi_in_TVALID        (dbg_hls_s_axis_tvalid),
    .s_axi_in_TREADY        (dbg_hls_s_axis_tready),
    .m_axi_out_TDATA        (dbg_hls_m_axis_tdata),
    .m_axi_out_TKEEP        (dbg_hls_m_axis_tkeep),
    .m_axi_out_TLAST        (dbg_hls_m_axis_tlast),
    .m_axi_out_TSTRB        (),
    .m_axi_out_TVALID       (dbg_hls_m_axis_tvalid),
    .m_axi_out_TREADY       (dbg_hls_m_axis_tready),
    .ap_clk                 (aclk),
    .ap_rst_n               (aresetn)
);

always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb notify.tie_off_m();
always_comb axi_ctrl.tie_off_s();
""".strip()


def stage_coyote_hw_sw(ctx: FlowContext, force: bool = False) -> dict[str, Any]:
    staged_hw_dir = ctx.u55c_root / "coyote_hw"
    staged_sw_dir = ctx.u55c_root / "coyote_sw"
    staged_hw_dir.mkdir(parents=True, exist_ok=True)
    staged_sw_dir.mkdir(parents=True, exist_ok=True)
    src_dir = staged_hw_dir / "src"
    src_dir.mkdir(parents=True, exist_ok=True)
    kernel_info = stage_kernel_sources(ctx, staged_hw_dir)
    (staged_hw_dir / "CMakeLists.txt").write_text(
        f"""
cmake_minimum_required(VERSION 3.5)
set(CYT_DIR {ctx.coyote_root})
set(CMAKE_MODULE_PATH ${{CMAKE_MODULE_PATH}} ${{CYT_DIR}}/cmake)
find_package(CoyoteHW REQUIRED)

project(u55c_qkeras_hls4ml_infer)
message("*** Coyote U55C QKeras hls4ml inference [Hardware] ***")

set(EN_STRM 1)
set(N_STRM_AXI 1)
set(EN_MEM 0)
set(N_REGIONS 1)

validation_checks_hw()
load_apps(VFPGA_C0_0 "src")
create_hw()
""".strip()
        + "\n"
    )
    debug_cfg = ctx.config.get("u55c", {}).get("debug", {}) or {}
    mark_axis_debug = bool(
        debug_cfg.get(
            "mark_axis",
            diagnostic_mode(ctx) in {"replicated_logit_2beat_cnn", "rom_cnn", "rom_control_probe", "rom_layer_probe"},
        )
    )
    (src_dir / "vfpga_top.svh").write_text(vfpga_top_source(mark_axis_debug=mark_axis_debug) + "\n")
    sw_src = staged_sw_dir / "src"
    sw_src.mkdir(parents=True, exist_ok=True)
    (staged_sw_dir / "CMakeLists.txt").write_text(
        f"""
cmake_minimum_required(VERSION 3.5)
project(u55c_qkeras_hls4ml_infer_host)
set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
set(CMAKE_CXX_STANDARD 17)
add_subdirectory({ctx.coyote_root}/sw ${{CMAKE_BINARY_DIR}}/coyote)
add_executable(coyote_qkeras_host src/main.cpp)
target_link_libraries(coyote_qkeras_host PUBLIC Coyote)
find_package(Boost REQUIRED COMPONENTS program_options)
target_link_libraries(coyote_qkeras_host PUBLIC Boost::program_options)
""".strip()
        + "\n"
    )
    abi = ctx.abi
    mode = diagnostic_mode(ctx)
    lane_probe_output = "true" if mode == "lane_probe" else "false"
    h1_probe_output = "true" if mode in {"h1_framing_probe", "h1_delayed_probe"} else "false"
    framed_buffered_output = "true" if mode in {"framed_buffered_cnn", "rom_cnn"} else "false"
    replicated_logit_2beat_output = "true" if mode == "replicated_logit_2beat_cnn" else "false"
    rom_control_probe_output = "true" if mode == "rom_control_probe" else "false"
    rom_layer_probe_output = "true" if mode == "rom_layer_probe" else "false"
    vfpga_id = int(ctx.config["u55c"].get("vfpga_id", 0))
    (sw_src / "main.cpp").write_text(
        f"""
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
	#include <sstream>
	#include <stdexcept>
	#include <string>
	#include <thread>
	#include <vector>
#include <unistd.h>

#include <boost/program_options.hpp>
#include <coyote/cRcnfg.hpp>
#include <coyote/cThread.hpp>

namespace {{
constexpr uint INPUT_BYTES = {int(abi['input_bytes_per_sample'])};
constexpr uint RESULT_BYTES = {int(abi['output_bytes_per_sample'])};
constexpr uint RESULT_LANES = RESULT_BYTES / sizeof(uint16_t);
constexpr int DEFAULT_VFPGA_ID = {vfpga_id};
constexpr bool LANE_PROBE_OUTPUT = {lane_probe_output};
constexpr bool H1_PROBE_OUTPUT = {h1_probe_output};
constexpr bool FRAMED_BUFFERED_OUTPUT = {framed_buffered_output};
constexpr bool REPLICATED_LOGIT_2BEAT_OUTPUT = {replicated_logit_2beat_output};
constexpr bool ROM_CONTROL_PROBE_OUTPUT = {rom_control_probe_output};
constexpr bool ROM_LAYER_PROBE_OUTPUT = {rom_layer_probe_output};

std::vector<std::string> split_csv_line(const std::string &line) {{
    std::vector<std::string> out;
    std::stringstream ss(line);
    std::string item;
    while (std::getline(ss, item, ',')) out.push_back(item);
    return out;
}}

struct Sample {{
    int sample_index;
    std::string input_path;
}};

std::vector<Sample> read_manifest(const std::string &path) {{
    std::ifstream f(path);
    if (!f) throw std::runtime_error("Could not open manifest: " + path);
    std::string header;
    std::getline(f, header);
    auto fields = split_csv_line(header);
    int idx_col = -1, path_col = -1;
    for (int i = 0; i < static_cast<int>(fields.size()); ++i) {{
        if (fields[i] == "sample_index") idx_col = i;
        if (fields[i] == "input_path") path_col = i;
    }}
    if (idx_col < 0 || path_col < 0) throw std::runtime_error("Manifest requires sample_index,input_path columns");
    std::vector<Sample> samples;
    std::string line;
    while (std::getline(f, line)) {{
        if (line.empty()) continue;
        auto cols = split_csv_line(line);
        if (static_cast<int>(cols.size()) <= std::max(idx_col, path_col)) continue;
        samples.push_back({{std::stoi(cols[idx_col]), cols[path_col]}});
    }}
    return samples;
}}
}}

int main(int argc, char *argv[]) {{
	    std::string manifest_path;
	    std::string output_csv;
	    std::string repetitions_output_csv;
	    std::string shell_bitstream_path;
	    int vfpga_id = DEFAULT_VFPGA_ID;
	    int max_samples = -1;
	    int skip_samples = 0;
	    int warmup_zero_frames = 0;
	    int repetitions_per_sample = 1;
	    int capture_repetition = 1;
	    double timeout_s = 30.0;
	    boost::program_options::options_description opts("U55C hls4ml inference options");
	    opts.add_options()
	        ("manifest,m", boost::program_options::value<std::string>(&manifest_path)->required(), "prepared_inputs/manifest.csv")
	        ("output,o", boost::program_options::value<std::string>(&output_csv)->required(), "hardware_per_sample.csv")
	        ("repetitions-output", boost::program_options::value<std::string>(&repetitions_output_csv), "raw per-transfer capture CSV")
	        ("reconfigure-shell", boost::program_options::value<std::string>(&shell_bitstream_path), "optional shell_top.bin to load before running")
	        ("vfpga", boost::program_options::value<int>(&vfpga_id)->default_value(DEFAULT_VFPGA_ID), "vFPGA id")
	        ("max-samples", boost::program_options::value<int>(&max_samples)->default_value(-1), "limit samples for debug runs")
	        ("skip-samples", boost::program_options::value<int>(&skip_samples)->default_value(0), "skip this many manifest rows before processing")
	        ("warmup-zero-frames", boost::program_options::value<int>(&warmup_zero_frames)->default_value(0), "send this many all-zero frames before processing samples")
	        ("repetitions-per-sample", boost::program_options::value<int>(&repetitions_per_sample)->default_value(1), "run each input this many times")
	        ("capture-repetition", boost::program_options::value<int>(&capture_repetition)->default_value(1), "1-based repetition to write to the summary CSV")
	        ("timeout-s", boost::program_options::value<double>(&timeout_s)->default_value(30.0), "per-sample timeout in seconds");
    boost::program_options::variables_map args;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, opts), args);
    boost::program_options::notify(args);
    if (warmup_zero_frames < 0) throw std::runtime_error("--warmup-zero-frames must be non-negative");
    if (repetitions_per_sample < 1) throw std::runtime_error("--repetitions-per-sample must be >= 1");
    if (capture_repetition < 1 || capture_repetition > repetitions_per_sample) {{
        throw std::runtime_error("--capture-repetition must be in [1, repetitions-per-sample]");
    }}
    if (repetitions_output_csv.empty()) repetitions_output_csv = output_csv + ".repetitions.csv";

	    if (!shell_bitstream_path.empty()) {{
	        std::cout << "reconfiguring shell=" << shell_bitstream_path << std::endl;
	        coyote::cRcnfg rcnfg(0);
	        auto t0 = std::chrono::high_resolution_clock::now();
	        rcnfg.reconfigureShell(shell_bitstream_path);
	        auto t1 = std::chrono::high_resolution_clock::now();
	        double reconfig_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
	        std::cout << "shell_reconfigured_ms=" << reconfig_ms << std::endl;
	    }}

	    auto samples = read_manifest(manifest_path);
	    std::ofstream out(output_csv);
	    if (LANE_PROBE_OUTPUT) {{
	        out << "sample_index,full_sum_raw,full_sum,lane_weighted_raw,lane_weighted";
	        for (int lane = 0; lane < 32; ++lane) {{
	            out << ",lane_" << std::setw(2) << std::setfill('0') << lane << "_raw";
	            out << ",lane_" << std::setw(2) << std::setfill('0') << lane << "_sum";
	        }}
	        out << std::setfill(' ') << ",latency_us\\n";
	    }} else if (H1_PROBE_OUTPUT) {{
	        out << "sample_index,magic,frame_counter,input_beats,tlast_count,first_tlast_beat,last_tlast_beat,"
	            << "early_tlast,missing_tlast,keep_error_count,full_sum_raw,weighted_sum_raw,"
	            << "first_lane0_raw,last_lane0_raw,delay_acc_raw,latency_us\\n";
	    }} else if (FRAMED_BUFFERED_OUTPUT) {{
	        out << "sample_index,logit_fixed_raw,logit,magic,frame_counter,input_beats,tlast_count,"
	            << "first_tlast_beat,last_tlast_beat,early_tlast,missing_tlast,keep_error_count,"
	            << "full_sum_raw,weighted_sum_raw,first_lane0_raw,last_lane0_raw,latency_us\\n";
	    }} else if (REPLICATED_LOGIT_2BEAT_OUTPUT) {{
	        out << "sample_index,logit_fixed_raw,logit,lane_mismatch_count,magic,frame_counter,input_beats,tlast_count,"
	            << "first_tlast_beat,last_tlast_beat,early_tlast,missing_tlast,keep_error_count,"
	            << "full_sum_raw,weighted_sum_raw,first_lane0_raw,last_lane0_raw,debug_output_raw,debug_version,latency_us\\n";
	    }} else if (ROM_CONTROL_PROBE_OUTPUT) {{
	        out << "sample_index,logit_a_raw,logit_a,logit_b_raw,logit_b,logit_zero_raw,logit_zero,"
	            << "logit_d_raw,logit_d,magic,frame_counter,delay_cycles_low,delay_acc_high,"
	            << "input_beats,tlast_count,first_tlast_beat,last_tlast_beat,early_tlast,"
	            << "missing_tlast,keep_error_count,rom_sample_index,latency_us\\n";
	    }} else if (ROM_LAYER_PROBE_OUTPUT) {{
	        out << "sample_index,logit_raw,logit,magic,frame_counter,"
	            << "input0_raw,input1_raw,input2_raw,input3_raw,input4_raw,input5_raw,input6_raw,input7_raw,"
	            << "input_checksum_raw,conv0_checksum_raw,pool0_checksum_raw,conv4_checksum_raw,gap_checksum_raw,"
	            << "gap0_raw,gap1_raw,gap2_raw,gap3_raw,latency_us\\n";
	    }} else {{
	        out << "sample_index,logit_fixed_raw,logit,latency_us\\n";
	    }}
	    out.flush();
	    std::ofstream reps_out(repetitions_output_csv);
	    if (!reps_out) throw std::runtime_error("Could not open repetitions output CSV: " + repetitions_output_csv);
	    reps_out << "phase,sample_index,repetition,latency_us";
	    for (uint lane = 0; lane < RESULT_LANES; ++lane) {{
	        reps_out << ",lane_" << std::setw(2) << std::setfill('0') << lane << "_raw";
	    }}
	    reps_out << std::setfill(' ') << "\\n";
	    reps_out.flush();

    coyote::cThread coyote_thread(vfpga_id, getpid());
    auto *input_mem = reinterpret_cast<unsigned char *>(coyote_thread.getMem({{coyote::CoyoteAllocType::HPF, INPUT_BYTES}}));
    auto *output_mem = reinterpret_cast<unsigned char *>(coyote_thread.getMem({{coyote::CoyoteAllocType::HPF, RESULT_BYTES}}));
    if (!input_mem || !output_mem) throw std::runtime_error("Could not allocate Coyote buffers");

	    auto run_transfer = [&]() -> double {{
	        coyote::localSg sg_in = {{.addr = input_mem, .len = INPUT_BYTES, .dest = 0}};
	        coyote::localSg sg_out = {{.addr = output_mem, .len = RESULT_BYTES, .dest = 0}};
	        coyote_thread.clearCompleted();
	        auto t0 = std::chrono::high_resolution_clock::now();
	        coyote_thread.invoke(coyote::CoyoteOper::LOCAL_TRANSFER, sg_in, sg_out);
	        uint32_t done = 0;
	        while ((done = coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_TRANSFER)) != 1) {{
	            auto now = std::chrono::high_resolution_clock::now();
	            double elapsed_s = std::chrono::duration<double>(now - t0).count();
	            if (elapsed_s > timeout_s) {{
	                throw std::runtime_error("Timed out waiting for LOCAL_TRANSFER completion; completed=" + std::to_string(done));
	            }}
	            std::this_thread::sleep_for(std::chrono::milliseconds(1));
	        }}
	        auto t1 = std::chrono::high_resolution_clock::now();
	        return std::chrono::duration<double, std::micro>(t1 - t0).count();
	    }};

	    auto write_repetition_row = [&](const char *phase, int sample_index, int repetition, double latency_us) {{
	        reps_out << phase << "," << sample_index << "," << repetition << "," << std::setprecision(12) << latency_us;
	        for (uint lane = 0; lane < RESULT_LANES; ++lane) {{
	            uint16_t raw = 0;
	            std::memcpy(&raw, output_mem + lane * sizeof(uint16_t), sizeof(raw));
	            reps_out << "," << raw;
	        }}
	        reps_out << "\\n";
	        reps_out.flush();
	    }};

	    for (int warmup = 1; warmup <= warmup_zero_frames; ++warmup) {{
	        std::fill(input_mem, input_mem + INPUT_BYTES, 0);
	        std::fill(output_mem, output_mem + RESULT_BYTES, 0);
	        double latency_us = run_transfer();
	        write_repetition_row("warmup_zero", -1, warmup, latency_us);
	        std::cout << "warmup_zero repetition=" << warmup << " latency_us=" << latency_us << std::endl;
	    }}

	    int processed = 0;
	    int skipped = 0;
	    for (const auto &sample : samples) {{
	        if (skipped < skip_samples) {{
	            skipped++;
	            continue;
	        }}
	        if (max_samples >= 0 && processed >= max_samples) break;
	        std::cout << "starting sample=" << sample.sample_index << std::endl;
	        std::fill(input_mem, input_mem + INPUT_BYTES, 0);
        std::fill(output_mem, output_mem + RESULT_BYTES, 0);
        std::ifstream input_file(sample.input_path, std::ios::binary);
        if (!input_file) throw std::runtime_error("Could not open input blob: " + sample.input_path);
        input_file.read(reinterpret_cast<char *>(input_mem), INPUT_BYTES);
        if (input_file.gcount() != INPUT_BYTES) throw std::runtime_error("Short input blob: " + sample.input_path);

	        std::vector<unsigned char> captured_output(RESULT_BYTES);
	        double latency_us = 0.0;
	        for (int repetition = 1; repetition <= repetitions_per_sample; ++repetition) {{
	            std::fill(output_mem, output_mem + RESULT_BYTES, 0);
	            double this_latency_us = run_transfer();
	            write_repetition_row("sample", sample.sample_index, repetition, this_latency_us);
	            if (repetition == capture_repetition) {{
	                latency_us = this_latency_us;
	                std::copy(output_mem, output_mem + RESULT_BYTES, captured_output.begin());
	            }}
	        }}
	        std::copy(captured_output.begin(), captured_output.end(), output_mem);
	        if (LANE_PROBE_OUTPUT) {{
	            uint16_t full_sum = 0;
	            uint16_t weighted_sum = 0;
	            std::memcpy(&full_sum, output_mem + 64, sizeof(full_sum));
	            std::memcpy(&weighted_sum, output_mem + 66, sizeof(weighted_sum));
	            out << sample.sample_index
	                << "," << full_sum
	                << "," << std::setprecision(12) << (static_cast<double>(full_sum) / {float(1 << int(abi['fixed_fraction']))})
	                << "," << weighted_sum
	                << "," << std::setprecision(12) << (static_cast<double>(weighted_sum) / {float(1 << int(abi['fixed_fraction']))});
	            for (int lane = 0; lane < 32; ++lane) {{
	                uint16_t raw = 0;
	                std::memcpy(&raw, output_mem + lane * sizeof(uint16_t), sizeof(raw));
	                out << "," << raw
	                    << "," << std::setprecision(12) << (static_cast<double>(raw) / {float(1 << int(abi['fixed_fraction']))});
	            }}
	            out << "," << latency_us << "\\n";
	            std::cout << "sample=" << sample.sample_index
	                      << " full_sum_raw=" << full_sum
	                      << " weighted_raw=" << weighted_sum
	                      << " latency_us=" << latency_us << std::endl;
	        }} else if (H1_PROBE_OUTPUT) {{
	            uint16_t fields[16] = {{}};
	            for (int field = 0; field < 16; ++field) {{
	                std::memcpy(&fields[field], output_mem + field * sizeof(uint16_t), sizeof(uint16_t));
	            }}
	            out << sample.sample_index;
	            for (int field = 0; field < 14; ++field) {{
	                out << "," << fields[field];
	            }}
	            out << "," << latency_us << "\\n";
	            std::cout << "sample=" << sample.sample_index
	                      << " magic=0x" << std::hex << fields[0] << std::dec
	                      << " frame_counter=" << fields[1]
	                      << " tlast_count=" << fields[3]
	                      << " last_tlast_beat=" << fields[5]
	                      << " early_tlast=" << fields[6]
	                      << " missing_tlast=" << fields[7]
	                      << " keep_error_count=" << fields[8]
	                      << " full_sum_raw=" << fields[9]
	                      << " weighted_sum_raw=" << fields[10]
	                      << " latency_us=" << latency_us << std::endl;
	        }} else if (FRAMED_BUFFERED_OUTPUT) {{
	            uint16_t fields[16] = {{}};
	            for (int field = 0; field < 16; ++field) {{
	                std::memcpy(&fields[field], output_mem + field * sizeof(uint16_t), sizeof(uint16_t));
	            }}
	            int16_t raw = 0;
	            std::memcpy(&raw, output_mem, sizeof(raw));
	            double logit = static_cast<double>(raw) / {float(1 << int(abi['fixed_fraction']))};
	            out << sample.sample_index
	                << "," << raw
	                << "," << std::setprecision(12) << logit;
	            for (int field = 1; field < 14; ++field) {{
	                out << "," << fields[field];
	            }}
	            out << "," << latency_us << "\\n";
	            std::cout << "sample=" << sample.sample_index
	                      << " logit=" << logit
	                      << " magic=0x" << std::hex << fields[1] << std::dec
	                      << " frame_counter=" << fields[2]
	                      << " tlast_count=" << fields[4]
	                      << " last_tlast_beat=" << fields[6]
	                      << " early_tlast=" << fields[7]
	                      << " missing_tlast=" << fields[8]
	                      << " keep_error_count=" << fields[9]
	                      << " latency_us=" << latency_us << std::endl;
	        }} else if (REPLICATED_LOGIT_2BEAT_OUTPUT) {{
	            uint16_t fields[16] = {{}};
	            for (int field = 0; field < 16; ++field) {{
	                std::memcpy(&fields[field], output_mem + field * sizeof(uint16_t), sizeof(uint16_t));
	            }}
	            std::vector<int16_t> replicated;
	            replicated.reserve(32);
	            for (int lane = 0; lane < 32; ++lane) {{
	                int16_t lane_raw = 0;
	                std::memcpy(&lane_raw, output_mem + 64 + lane * sizeof(int16_t), sizeof(lane_raw));
	                replicated.push_back(lane_raw);
	            }}
	            int16_t lane0_raw = replicated.empty() ? 0 : replicated.front();
	            int lane_mismatch_count = 0;
	            for (int16_t lane_raw : replicated) {{
	                if (lane_raw != lane0_raw) lane_mismatch_count++;
	            }}
	            std::sort(replicated.begin(), replicated.end());
	            int16_t raw = replicated[replicated.size() / 2];
	            double logit = static_cast<double>(raw) / {float(1 << int(abi['fixed_fraction']))};
	            out << sample.sample_index
	                << "," << raw
	                << "," << std::setprecision(12) << logit
	                << "," << lane_mismatch_count;
	            for (int field = 0; field < 15; ++field) {{
	                out << "," << fields[field];
	            }}
	            out << "," << latency_us << "\\n";
	            std::cout << "sample=" << sample.sample_index
	                      << " logit=" << logit
	                      << " lane_mismatch_count=" << lane_mismatch_count
	                      << " magic=0x" << std::hex << fields[0] << std::dec
	                      << " frame_counter=" << fields[1]
	                      << " tlast_count=" << fields[3]
	                      << " last_tlast_beat=" << fields[5]
	                      << " early_tlast=" << fields[6]
	                      << " missing_tlast=" << fields[7]
	                      << " keep_error_count=" << fields[8]
	                      << " latency_us=" << latency_us << std::endl;
	        }} else if (ROM_CONTROL_PROBE_OUTPUT) {{
	            uint16_t fields[16] = {{}};
	            for (int field = 0; field < 16; ++field) {{
	                std::memcpy(&fields[field], output_mem + field * sizeof(uint16_t), sizeof(uint16_t));
	            }}
	            int16_t logit_a_raw = static_cast<int16_t>(fields[0]);
	            int16_t logit_b_raw = static_cast<int16_t>(fields[1]);
	            int16_t logit_zero_raw = static_cast<int16_t>(fields[2]);
	            int16_t logit_d_raw = static_cast<int16_t>(fields[3]);
	            double logit_a = static_cast<double>(logit_a_raw) / {float(1 << int(abi['fixed_fraction']))};
	            double logit_b = static_cast<double>(logit_b_raw) / {float(1 << int(abi['fixed_fraction']))};
	            double logit_zero = static_cast<double>(logit_zero_raw) / {float(1 << int(abi['fixed_fraction']))};
	            double logit_d = static_cast<double>(logit_d_raw) / {float(1 << int(abi['fixed_fraction']))};
	            out << sample.sample_index
	                << "," << logit_a_raw
	                << "," << std::setprecision(12) << logit_a
	                << "," << logit_b_raw
	                << "," << std::setprecision(12) << logit_b
	                << "," << logit_zero_raw
	                << "," << std::setprecision(12) << logit_zero
	                << "," << logit_d_raw
	                << "," << std::setprecision(12) << logit_d;
	            for (int field = 4; field < 16; ++field) {{
	                out << "," << fields[field];
	            }}
	            out << "," << latency_us << "\\n";
	            std::cout << "sample=" << sample.sample_index
	                      << " logit_a=" << logit_a
	                      << " logit_b=" << logit_b
	                      << " logit_zero=" << logit_zero
	                      << " logit_d=" << logit_d
	                      << " magic=0x" << std::hex << fields[4] << std::dec
	                      << " frame_counter=" << fields[5]
	                      << " tlast_count=" << fields[9]
	                      << " latency_us=" << latency_us << std::endl;
	        }} else if (ROM_LAYER_PROBE_OUTPUT) {{
	            uint16_t fields[32] = {{}};
	            for (int field = 0; field < 32; ++field) {{
	                std::memcpy(&fields[field], output_mem + field * sizeof(uint16_t), sizeof(uint16_t));
	            }}
	            int16_t raw = static_cast<int16_t>(fields[0]);
	            double logit = static_cast<double>(raw) / {float(1 << int(abi['fixed_fraction']))};
	            out << sample.sample_index
	                << "," << raw
	                << "," << std::setprecision(12) << logit
	                << "," << fields[1]
	                << "," << fields[2];
	            for (int field = 3; field <= 19; ++field) {{
	                out << "," << fields[field];
	            }}
	            out << "," << latency_us << "\\n";
	            std::cout << "sample=" << sample.sample_index
	                      << " logit=" << logit
	                      << " magic=0x" << std::hex << fields[1] << std::dec
	                      << " input_checksum_raw=" << fields[11]
	                      << " conv0_checksum_raw=" << fields[12]
	                      << " pool0_checksum_raw=" << fields[13]
	                      << " conv4_checksum_raw=" << fields[14]
	                      << " gap_checksum_raw=" << fields[15]
	                      << " latency_us=" << latency_us << std::endl;
	        }} else {{
	            int16_t raw = 0;
	            std::memcpy(&raw, output_mem, sizeof(raw));
	            double logit = static_cast<double>(raw) / {float(1 << int(abi['fixed_fraction']))};
	            out << sample.sample_index << "," << raw << "," << std::setprecision(12) << logit << "," << latency_us << "\\n";
	            std::cout << "sample=" << sample.sample_index << " logit=" << logit << " latency_us=" << latency_us << std::endl;
	        }}
	        out.flush();
	        processed++;
	    }}
    return 0;
}}
""".strip()
        + "\n"
    )
    return {**kernel_info, "hw_dir": str(staged_hw_dir), "sw_dir": str(staged_sw_dir), "mark_axis_debug": mark_axis_debug}


COYOTE_HW_BUILD_DIRS = ("build_u55c",)
COYOTE_CMAKE_DEFINE_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def staged_coyote_hw_source_hash(hw_dir: Path) -> str:
    return sha256_tree(hw_dir, exclude_dir_names=COYOTE_HW_BUILD_DIRS)


def clean_coyote_hw_build_dir(build_dir: Path) -> None:
    if build_dir.exists():
        print(f"[info] removing stale Coyote hardware build directory: {build_dir}")
        shutil.rmtree(build_dir)
    build_dir.mkdir(parents=True, exist_ok=True)


def coyote_cmake_defines(ctx: FlowContext) -> dict[str, str]:
    raw = ctx.config.get("u55c", {}).get("cmake_defines", {}) or {}
    if not isinstance(raw, dict):
        raise TypeError("u55c.cmake_defines must be a mapping of CMake cache names to scalar values")
    defines: dict[str, str] = {}
    for key, value in sorted(raw.items()):
        key_s = str(key)
        if not COYOTE_CMAKE_DEFINE_RE.match(key_s):
            raise ValueError(f"invalid CMake define name in u55c.cmake_defines: {key_s!r}")
        if isinstance(value, bool):
            value_s = "1" if value else "0"
        elif value is None:
            value_s = ""
        elif isinstance(value, (int, float, str)):
            value_s = str(value)
        else:
            raise TypeError(f"u55c.cmake_defines.{key_s} must be a scalar value, got {type(value).__name__}")
        defines[key_s] = value_s
    return defines


def coyote_cmake_args(defines: dict[str, str]) -> list[str]:
    return [f"-D{key}={value}" for key, value in sorted(defines.items())]


def file_hash_record(path: Path) -> dict[str, Any]:
    path = Path(path)
    record: dict[str, Any] = {"path": str(path), "exists": path.exists()}
    if path.exists():
        record.update({"sha256": file_sha256(path), "bytes": path.stat().st_size})
    return record


def bitstream_artifact_hashes(ctx: FlowContext, build_dir: Path) -> dict[str, Any]:
    ip_dir = build_dir / "iprepo" / "coyote_qkeras_infer_hls_ip"
    return {
        "wrapper_source": file_hash_record(
            ctx.u55c_root / "coyote_hw" / "src" / "hls" / "coyote_qkeras_infer" / "coyote_qkeras_infer.cpp"
        ),
        "generated_hls_rtl": file_hash_record(ip_dir / "hdl" / "verilog" / "coyote_qkeras_infer.v"),
        "component_xml": file_hash_record(ip_dir / "component.xml"),
        "vfpga_top_svh": file_hash_record(ctx.u55c_root / "coyote_hw" / "src" / "vfpga_top.svh"),
        "cyt_top_bitstream": file_hash_record(build_dir / "bitstreams" / "cyt_top.bit"),
        "shell_top_bin": file_hash_record(build_dir / "bitstreams" / "shell_top.bin"),
        "hls_config": file_hash_record(ctx.hls_project_dir / "hls4ml_config.yml"),
        "hls_firmware_tree_hash": sha256_tree(ctx.hls_project_dir / "firmware"),
        "prepared_inputs_manifest_csv": file_hash_record(ctx.prepared_inputs_dir / "manifest.csv"),
        "prepared_input_sample_0000": file_hash_record(ctx.prepared_inputs_dir / "sample_0000.bin"),
    }


def parse_shell_timing_summary(report_path: Path) -> dict[str, Any]:
    summary: dict[str, Any] = {
        "report": str(report_path),
        "exists": report_path.exists(),
    }
    if not report_path.exists():
        return summary
    text = report_path.read_text(errors="ignore")
    summary["constraints_met"] = "Timing constraints are met." in text
    summary["constraints_failed"] = "Timing constraints are not met." in text

    design_match = re.search(
        r"WNS\(ns\)\s+TNS\(ns\)\s+TNS Failing Endpoints.*?\n\s*-+\s+-+\s+-+.*?\n\s*"
        r"(?P<wns>-?\d+(?:\.\d+)?)\s+(?P<tns>-?\d+(?:\.\d+)?)\s+(?P<fail>\d+)\s+(?P<total>\d+)",
        text,
        re.S,
    )
    if design_match:
        summary.update(
            {
                "wns": float(design_match.group("wns")),
                "tns": float(design_match.group("tns")),
                "failing_endpoints": int(design_match.group("fail")),
                "total_endpoints": int(design_match.group("total")),
            }
        )

    clock_match = re.search(
        r"clk_out1_design_ctrl_clk_wiz_0_0\s+\{[^}]+\}\s+"
        r"(?P<period>\d+(?:\.\d+)?)\s+(?P<freq>\d+(?:\.\d+)?)",
        text,
    )
    if clock_match:
        summary["ctrl_clock_period_ns"] = float(clock_match.group("period"))
        summary["ctrl_clock_frequency_mhz"] = float(clock_match.group("freq"))

    if "wns" in summary:
        summary["timing_clean"] = (
            float(summary["wns"]) >= 0.0
            and float(summary.get("tns", 0.0)) >= 0.0
            and int(summary.get("failing_endpoints", 0)) == 0
        )
    return summary


def bitstream_build_outputs(ctx: FlowContext, build_dir: Path) -> dict[str, Any]:
    timing = parse_shell_timing_summary(build_dir / "reports" / "shell_timing_summary.rpt")
    return {
        "bitstream_candidates": sorted(str(path) for path in build_dir.rglob("*.bit")),
        "report_candidates": sorted(str(path) for path in build_dir.rglob("*.rpt")),
        "dcp_candidates": sorted(str(path) for path in build_dir.rglob("*.dcp")),
        "timing_summary": timing,
        "artifact_hashes": bitstream_artifact_hashes(ctx, build_dir),
    }


def stage_bitstream(ctx: FlowContext, force: bool = False) -> None:
    if not (ctx.hls_project_dir / "conversion_manifest.json").exists():
        raise FileNotFoundError(f"Missing HLS project; run hls first: {ctx.hls_project_dir}")
    splits = get_splits(ctx)
    prepare_u55c_inputs(ctx, splits, force=force)
    manifest_path = ctx.u55c_root / "bitstream_manifest.json"
    cmake_defines = coyote_cmake_defines(ctx)
    stage_fingerprint = {
        "u55c_stage_version": "2026-05-05-replicated-logit-debug-axis",
        "project_name": read_json(ctx.hls_project_dir / "conversion_manifest.json")["project_name"],
        "hls_project": str(ctx.hls_project_dir),
        "hls_firmware_hash": sha256_tree(ctx.hls_project_dir / "firmware"),
        "prepared_inputs_manifest": read_json(ctx.prepared_inputs_dir / "manifest.json"),
        "coyote_root": str(ctx.coyote_root),
        "coyote_cmake_defines": cmake_defines,
        "abi": ctx.abi,
        "diagnostic": ctx.config.get("u55c", {}).get("diagnostic", {"mode": "baseline"}),
        "debug": ctx.config.get("u55c", {}).get("debug", {}),
    }
    if not force and manifest_path.exists() and read_json(manifest_path).get("stage_fingerprint") == stage_fingerprint:
        print("staged source cache hit")
    else:
        info = stage_coyote_hw_sw(ctx, force=force)
        write_json(
            manifest_path,
            {
                "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                "stage_fingerprint": stage_fingerprint,
                "stage_info": info,
                "hw_build_dir": str(ctx.u55c_root / "coyote_hw" / "build_u55c"),
                "bitstream_candidates": [],
            },
        )
    manifest = read_json(manifest_path)
    build_dir = Path(manifest["hw_build_dir"])
    build_fingerprint = {
        **manifest["stage_fingerprint"],
        "staged_source_hash": staged_coyote_hw_source_hash(ctx.u55c_root / "coyote_hw"),
        "build_clean_policy": "remove_build_u55c_before_rebuild",
        "coyote_cmake_defines": cmake_defines,
    }
    needs_build = force or manifest.get("build_fingerprint") != build_fingerprint or not manifest.get("bitstream_candidates")
    if needs_build:
        clean_coyote_hw_build_dir(build_dir)
        jobs = ctx.config["u55c"].get("build_jobs") or os.cpu_count() or 4
        try:
            run_command(
                ["cmake", "-DFDEV_NAME=u55c", *coyote_cmake_args(cmake_defines), ".."],
                cwd=build_dir,
                log_path=ctx.u55c_root / "logs" / "cmake_hw.log",
            )
            run_command(["make", "project", "-j", str(jobs)], cwd=build_dir, log_path=ctx.u55c_root / "logs" / "make_project.log")
            run_command(["make", "bitgen", "-j", str(jobs)], cwd=build_dir, log_path=ctx.u55c_root / "logs" / "make_bitgen.log")
        except Exception as exc:
            manifest.update(
                {
                    "build_fingerprint": build_fingerprint,
                    "built_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                    "build_failed": True,
                    "build_error": repr(exc),
                    **bitstream_build_outputs(ctx, build_dir),
                }
            )
            write_json(manifest_path, manifest)
            raise
        manifest.update(
            {
                "build_fingerprint": build_fingerprint,
                "built_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                "build_failed": False,
                **bitstream_build_outputs(ctx, build_dir),
            }
        )
        write_json(manifest_path, manifest)
    else:
        print("bitstream build cache hit")
        output_updates = bitstream_build_outputs(ctx, build_dir)
        changed = False
        for key, value in output_updates.items():
            if manifest.get(key) != value:
                manifest[key] = value
                changed = True
        if changed:
            write_json(manifest_path, manifest)
    write_run_index(ctx)
