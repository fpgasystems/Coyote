"""Part 4 of the notebook flow: U55C input preparation and Coyote bitstream build."""

from __future__ import annotations

import os
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
    wrapper = f"""
#include "coyote_qkeras_infer.hpp"
#include "{top_header.name}"
#include "{top_cpp.name}"

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
    {top_header.stem}(nn_in, nn_out);
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
    (kernel_dir / "coyote_qkeras_infer.cpp").write_text(wrapper + "\n")
    return {"kernel_dir": str(kernel_dir), "top_function": top_header.stem, "flattened_files": len(list(kernel_dir.iterdir()))}


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
    (src_dir / "vfpga_top.svh").write_text(
        """
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
        + "\n"
    )
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
constexpr int DEFAULT_VFPGA_ID = {vfpga_id};

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
	    std::string shell_bitstream_path;
	    int vfpga_id = DEFAULT_VFPGA_ID;
	    int max_samples = -1;
	    int skip_samples = 0;
	    double timeout_s = 30.0;
	    boost::program_options::options_description opts("U55C hls4ml inference options");
	    opts.add_options()
	        ("manifest,m", boost::program_options::value<std::string>(&manifest_path)->required(), "prepared_inputs/manifest.csv")
	        ("output,o", boost::program_options::value<std::string>(&output_csv)->required(), "hardware_per_sample.csv")
	        ("reconfigure-shell", boost::program_options::value<std::string>(&shell_bitstream_path), "optional shell_top.bin to load before running")
	        ("vfpga", boost::program_options::value<int>(&vfpga_id)->default_value(DEFAULT_VFPGA_ID), "vFPGA id")
	        ("max-samples", boost::program_options::value<int>(&max_samples)->default_value(-1), "limit samples for debug runs")
	        ("skip-samples", boost::program_options::value<int>(&skip_samples)->default_value(0), "skip this many manifest rows before processing")
	        ("timeout-s", boost::program_options::value<double>(&timeout_s)->default_value(30.0), "per-sample timeout in seconds");
    boost::program_options::variables_map args;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, opts), args);
    boost::program_options::notify(args);

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
	    out << "sample_index,logit_fixed_raw,logit,latency_us\\n";
	    out.flush();

    coyote::cThread coyote_thread(vfpga_id, getpid());
    auto *input_mem = reinterpret_cast<unsigned char *>(coyote_thread.getMem({{coyote::CoyoteAllocType::HPF, INPUT_BYTES}}));
    auto *output_mem = reinterpret_cast<unsigned char *>(coyote_thread.getMem({{coyote::CoyoteAllocType::HPF, RESULT_BYTES}}));
    if (!input_mem || !output_mem) throw std::runtime_error("Could not allocate Coyote buffers");

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

        int16_t raw = 0;
        std::memcpy(&raw, output_mem, sizeof(raw));
	        double logit = static_cast<double>(raw) / {float(1 << int(abi['fixed_fraction']))};
	        double latency_us = std::chrono::duration<double, std::micro>(t1 - t0).count();
	        out << sample.sample_index << "," << raw << "," << std::setprecision(12) << logit << "," << latency_us << "\\n";
	        out.flush();
	        std::cout << "sample=" << sample.sample_index << " logit=" << logit << " latency_us=" << latency_us << std::endl;
	        processed++;
	    }}
    return 0;
}}
""".strip()
        + "\n"
    )
    return {**kernel_info, "hw_dir": str(staged_hw_dir), "sw_dir": str(staged_sw_dir)}


COYOTE_HW_BUILD_DIRS = ("build_u55c",)
FORBIDDEN_AP_CTRL_PORTS = ("ap_start", "ap_done", "ap_idle", "ap_ready")


def staged_coyote_hw_source_hash(hw_dir: Path) -> str:
    return sha256_tree(hw_dir, exclude_dir_names=COYOTE_HW_BUILD_DIRS)


def clean_coyote_hw_build_dir(build_dir: Path) -> None:
    if build_dir.exists():
        print(f"[info] removing stale Coyote hardware build directory: {build_dir}")
        shutil.rmtree(build_dir)
    build_dir.mkdir(parents=True, exist_ok=True)


def verify_coyote_hls_ip_has_no_ctrl_ports(build_dir: Path) -> dict[str, Any]:
    ip_dir = build_dir / "iprepo" / "coyote_qkeras_infer_hls_ip"
    if not ip_dir.exists():
        raise FileNotFoundError(f"Missing packaged HLS IP directory: {ip_dir}")
    check_files = [ip_dir / "component.xml"]
    check_files.extend(sorted((ip_dir / "hdl" / "verilog").glob("*.v")))
    matches: list[str] = []
    for path in check_files:
        if not path.exists():
            continue
        text = path.read_text(errors="ignore")
        for token in FORBIDDEN_AP_CTRL_PORTS:
            if token in text:
                matches.append(f"{path}: contains {token}")
    if matches:
        preview = "\n".join(matches[:20])
        if len(matches) > 20:
            preview += f"\n... {len(matches) - 20} more matches"
        raise RuntimeError(
            "Packaged HLS IP still exposes ap_ctrl_hs control ports after rebuild; "
            f"refusing to record bitstream manifest.\n{preview}"
        )
    return {
        "ip_dir": str(ip_dir),
        "checked_files": [str(path) for path in check_files if path.exists()],
        "forbidden_ports_absent": list(FORBIDDEN_AP_CTRL_PORTS),
    }


def stage_bitstream(ctx: FlowContext, force: bool = False) -> None:
    if not (ctx.hls_project_dir / "conversion_manifest.json").exists():
        raise FileNotFoundError(f"Missing HLS project; run hls first: {ctx.hls_project_dir}")
    splits = get_splits(ctx)
    prepare_u55c_inputs(ctx, splits, force=force)
    manifest_path = ctx.u55c_root / "bitstream_manifest.json"
    stage_fingerprint = {
        "u55c_stage_version": "2026-04-30-ap-ctrl-none-trunc-inputs",
        "project_name": read_json(ctx.hls_project_dir / "conversion_manifest.json")["project_name"],
        "hls_project": str(ctx.hls_project_dir),
        "hls_firmware_hash": sha256_tree(ctx.hls_project_dir / "firmware"),
        "prepared_inputs_manifest": read_json(ctx.prepared_inputs_dir / "manifest.json"),
        "coyote_root": str(ctx.coyote_root),
        "abi": ctx.abi,
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
        "packaged_ip_control_check": {
            "ip_name": "coyote_qkeras_infer_hls_ip",
            "forbidden_ports": list(FORBIDDEN_AP_CTRL_PORTS),
        },
    }
    needs_build = force or manifest.get("build_fingerprint") != build_fingerprint or not manifest.get("bitstream_candidates")
    if needs_build:
        clean_coyote_hw_build_dir(build_dir)
        jobs = ctx.config["u55c"].get("build_jobs") or os.cpu_count() or 4
        run_command(["cmake", "-DFDEV_NAME=u55c", ".."], cwd=build_dir, log_path=ctx.u55c_root / "logs" / "cmake_hw.log")
        run_command(["make", "project", "-j", str(jobs)], cwd=build_dir, log_path=ctx.u55c_root / "logs" / "make_project.log")
        run_command(["make", "bitgen", "-j", str(jobs)], cwd=build_dir, log_path=ctx.u55c_root / "logs" / "make_bitgen.log")
        packaged_ip_check = verify_coyote_hls_ip_has_no_ctrl_ports(build_dir)
        manifest.update(
            {
                "build_fingerprint": build_fingerprint,
                "built_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                "bitstream_candidates": sorted(str(path) for path in build_dir.rglob("*.bit")),
                "report_candidates": sorted(str(path) for path in build_dir.rglob("*.rpt")),
                "dcp_candidates": sorted(str(path) for path in build_dir.rglob("*.dcp")),
                "packaged_ip_check": packaged_ip_check,
            }
        )
        write_json(manifest_path, manifest)
    else:
        print("bitstream build cache hit")
    write_run_index(ctx)
