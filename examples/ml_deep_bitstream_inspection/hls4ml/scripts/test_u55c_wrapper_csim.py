#!/usr/bin/env python3
"""Run a Vitis HLS C-sim or RTL cosim test for the staged U55C wrapper.

This test copies the staged hls4ml/Coyote HLS kernel into an isolated work
directory, generates a C++ testbench, and checks that the wrapper emits the
same logit semantics as the saved hls4ml reference. The testbench reads the
prepared input blobs as raw host bytes, packs them into 512-bit AXI stream
beats, and decodes the output as the deployed host does. By default it runs C
simulation only; pass --run-cosim to also synthesize and RTL-cosimulate the
wrapper with the same testbench inputs.
"""

from __future__ import annotations

import argparse
import csv
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


DEFAULT_PART = "xcu55c-fsvh2892-2L-e"
DEFAULT_CLOCK_NS = 4.0


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    if not rows:
        raise ValueError("no rows to write")
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def parse_output_fraction_bits(header: Path) -> int:
    text = header.read_text(errors="ignore")
    match = re.search(r"typedef\s+ap_fixed<\s*(\d+)\s*,\s*(\d+)\s*>\s+packed_output_t\s*;", text)
    if not match:
        raise ValueError(f"could not parse packed_output_t from {header}")
    width = int(match.group(1))
    integer = int(match.group(2))
    return width - integer


def resolve_u55c_root(path: Path) -> Path:
    root = path.resolve()
    if (root / "coyote_hw" / "src" / "hls" / "coyote_qkeras_infer").exists():
        return root
    candidate = root / "fold_0" / "u55c_deployment"
    if (candidate / "coyote_hw" / "src" / "hls" / "coyote_qkeras_infer").exists():
        return candidate
    raise FileNotFoundError(
        "expected either a u55c_deployment directory or a fold root containing fold_0/u55c_deployment"
    )


def build_cases(
    prepared_manifest: Path,
    reference_csv: Path,
    *,
    sample_indices: set[int] | None,
    max_samples: int,
) -> list[dict[str, object]]:
    prepared_rows = read_csv(prepared_manifest)
    reference_rows = read_csv(reference_csv)
    reference_by_index = {int(row["sample_index"]): row for row in reference_rows}
    cases: list[dict[str, object]] = []
    for row in prepared_rows:
        idx = int(row["sample_index"])
        if sample_indices is not None and idx not in sample_indices:
            continue
        if idx not in reference_by_index:
            raise KeyError(f"sample_index {idx} missing from {reference_csv}")
        input_path = Path(row["input_path"]).resolve()
        if not input_path.exists():
            raise FileNotFoundError(input_path)
        cases.append(
            {
                "sample_index": idx,
                "input_path": str(input_path),
                "expected_logit": reference_by_index[idx]["logit"],
            }
        )
        if max_samples > 0 and len(cases) >= max_samples:
            break
    if not cases:
        raise ValueError("no matching samples selected")
    return cases


def copy_kernel(kernel_dir: Path, work_dir: Path) -> Path:
    dst = work_dir / "kernel"
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(kernel_dir, dst)
    return dst


def copy_weight_files(u55c_root: Path, work_dir: Path) -> Path | None:
    weights_src = u55c_root.parent / "project" / "firmware" / "weights"
    if not weights_src.exists():
        return None
    weights_dst = work_dir / "weights"
    if weights_dst.exists():
        shutil.rmtree(weights_dst)
    shutil.copytree(weights_src, weights_dst)
    return weights_dst


def testbench_source(output_fraction_bits: int) -> str:
    return f"""
#include "coyote_qkeras_infer.hpp"

#include <array>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

constexpr int OUTPUT_FRAC_BITS = {output_fraction_bits};
constexpr int INPUT_BYTES = INPUT_PIXELS * sizeof(int16_t);
constexpr int RESULT_BYTES = 64;
constexpr int BYTES_PER_BEAT = AXI_DATA_BITS / 8;

namespace nnet {{
bool trace_enabled = false;
std::map<std::string, void *> *trace_outputs = nullptr;
size_t trace_type_size = 0;
}} // namespace nnet

struct CaseRow {{
    int sample_index;
    std::string input_path;
    double expected_logit;
}};

static std::vector<std::string> split_csv_line(const std::string &line) {{
    std::vector<std::string> fields;
    std::stringstream ss(line);
    std::string item;
    while (std::getline(ss, item, ',')) fields.push_back(item);
    return fields;
}}

static std::vector<CaseRow> read_cases(const std::string &path) {{
    std::ifstream f(path);
    if (!f) throw std::runtime_error("could not open cases CSV: " + path);
    std::string line;
    std::getline(f, line);
    std::vector<CaseRow> rows;
    while (std::getline(f, line)) {{
        if (line.empty()) continue;
        auto fields = split_csv_line(line);
        if (fields.size() < 3) throw std::runtime_error("bad cases CSV row: " + line);
        rows.push_back({{std::stoi(fields[0]), fields[1], std::stod(fields[2])}});
    }}
    return rows;
}}

static std::vector<uint8_t> read_input_blob(const std::string &path) {{
    std::ifstream f(path, std::ios::binary);
    if (!f) throw std::runtime_error("could not open input blob: " + path);
    std::vector<uint8_t> bytes(INPUT_BYTES);
    f.read(reinterpret_cast<char *>(bytes.data()), bytes.size());
    if (f.gcount() != static_cast<std::streamsize>(bytes.size())) {{
        throw std::runtime_error("short input blob: " + path);
    }}
    char extra = 0;
    if (f.read(&extra, 1)) {{
        throw std::runtime_error("input blob has trailing bytes: " + path);
    }}
    return bytes;
}}

static std::vector<uint8_t> zero_input_blob() {{
    return std::vector<uint8_t>(INPUT_BYTES, 0);
}}

static void push_input_frame(const std::vector<uint8_t> &bytes, hls::stream<axi_s> &input_stream) {{
    if (bytes.size() != INPUT_BYTES) {{
        throw std::runtime_error("input byte vector has wrong size");
    }}
    for (int beat = 0; beat < INPUT_BEATS; ++beat) {{
        axi_s word;
        word.data = 0;
        word.keep = -1;
        word.last = (beat == INPUT_BEATS - 1);
        for (int byte = 0; byte < BYTES_PER_BEAT; ++byte) {{
            int offset = beat * BYTES_PER_BEAT + byte;
            ap_uint<8> raw = bytes[offset];
            word.data.range((byte + 1) * 8 - 1, byte * 8) = raw;
        }}
        input_stream.write(word);
    }}
}}

static axi_s read_output_frame(hls::stream<axi_s> &output_stream, const std::string &context) {{
    if (output_stream.empty()) {{
        throw std::runtime_error("wrapper produced no output for " + context);
    }}
    axi_s output_word;
    bool saw_last = false;
    for (int beat = 0; beat < 8; ++beat) {{
        if (output_stream.empty()) {{
            if (!saw_last) throw std::runtime_error("wrapper output ended without TLAST for " + context);
            break;
        }}
        output_word = output_stream.read();
        saw_last = bool(output_word.last);
        if (saw_last) break;
    }}
    if (!saw_last) {{
        throw std::runtime_error("wrapper produced too many output beats or no TLAST for " + context);
    }}
    return output_word;
}}

static std::array<uint8_t, RESULT_BYTES> output_word_to_host_bytes(const axi_s &output_word) {{
    std::array<uint8_t, RESULT_BYTES> bytes{{}};
    for (int byte = 0; byte < RESULT_BYTES; ++byte) {{
        ap_uint<8> raw = output_word.data.range((byte + 1) * 8 - 1, byte * 8);
        bytes[byte] = static_cast<uint8_t>(raw.to_uint());
    }}
    return bytes;
}}

static int16_t host_decode_logit_raw(const std::array<uint8_t, RESULT_BYTES> &bytes) {{
    uint16_t raw = static_cast<uint16_t>(bytes[0]) |
                   (static_cast<uint16_t>(bytes[1]) << 8);
    return static_cast<int16_t>(raw);
}}

static axi_s run_one_transfer(
    const std::vector<uint8_t> &input_bytes,
    hls::stream<axi_s> &input_stream,
    hls::stream<axi_s> &output_stream,
    const std::string &context
) {{
    push_input_frame(input_bytes, input_stream);
    coyote_qkeras_infer(input_stream, output_stream);
    return read_output_frame(output_stream, context);
}}

int main(int argc, char **argv) {{
    if (argc < 7) {{
        std::cerr << "usage: tb <cases.csv> <results.csv> <tolerance> <warmup_zero_frames> <repetitions_per_sample> <capture_repetition>\\n";
        return 2;
    }}
    const std::string cases_csv = argv[1];
    const std::string results_csv = argv[2];
    const double tolerance = std::stod(argv[3]);
    const int warmup_zero_frames = std::stoi(argv[4]);
    const int repetitions_per_sample = std::stoi(argv[5]);
    const int capture_repetition = std::stoi(argv[6]);
    if (warmup_zero_frames < 0) throw std::runtime_error("warmup_zero_frames must be non-negative");
    if (repetitions_per_sample < 1) throw std::runtime_error("repetitions_per_sample must be >= 1");
    if (capture_repetition < 1 || capture_repetition > repetitions_per_sample) {{
        throw std::runtime_error("capture_repetition must be in [1, repetitions_per_sample]");
    }}
    auto cases = read_cases(cases_csv);

    std::ofstream out(results_csv);
    if (!out) throw std::runtime_error("could not open results CSV: " + results_csv);
    out << "call_ordinal,sample_index,repetition,expected_logit,wrapper_raw,wrapper_logit,abs_err,pass,last,keep";
    for (int lane = 0; lane < RESULT_BYTES / 2; ++lane) {
        out << ",lane_" << std::setw(2) << std::setfill('0') << lane << "_raw";
    }
    out << std::setfill(' ') << "\\n";

    hls::stream<axi_s> input_stream("input_stream");
    hls::stream<axi_s> output_stream("output_stream");
    int failures = 0;
    int call_ordinal = 0;

    for (int warmup = 1; warmup <= warmup_zero_frames; ++warmup) {{
        auto output_word = run_one_transfer(
            zero_input_blob(),
            input_stream,
            output_stream,
            "warmup_zero " + std::to_string(warmup)
        );
        auto output_bytes = output_word_to_host_bytes(output_word);
        int16_t raw_int = host_decode_logit_raw(output_bytes);
        double wrapper_logit = static_cast<double>(raw_int) / static_cast<double>(1 << OUTPUT_FRAC_BITS);
        std::cout << "warmup_zero=" << warmup
                  << " wrapper=" << wrapper_logit
                  << " raw=" << raw_int
                  << " last=" << static_cast<int>(output_word.last)
                  << " keep=" << output_word.keep << std::endl;
    }}

    for (const auto &row : cases) {{
        auto input_bytes = read_input_blob(row.input_path);
        for (int repetition = 1; repetition <= repetitions_per_sample; ++repetition) {{
            auto output_word = run_one_transfer(
                input_bytes,
                input_stream,
                output_stream,
                "sample " + std::to_string(row.sample_index) + " repetition " + std::to_string(repetition)
            );
            auto output_bytes = output_word_to_host_bytes(output_word);
            int16_t raw_int = host_decode_logit_raw(output_bytes);
            double wrapper_logit = static_cast<double>(raw_int) / static_cast<double>(1 << OUTPUT_FRAC_BITS);
            double abs_err = std::abs(wrapper_logit - row.expected_logit);
            bool ok = abs_err <= tolerance;
            if (!ok) failures++;
            int printed_call_ordinal = call_ordinal;
            if (repetition == capture_repetition) {{
                out << call_ordinal << ","
                    << row.sample_index << ","
                    << repetition << ","
                    << std::setprecision(12) << row.expected_logit << ","
                    << raw_int << ","
                    << std::setprecision(12) << wrapper_logit << ","
                    << std::setprecision(12) << abs_err << ","
                    << (ok ? "true" : "false") << ","
                    << static_cast<int>(output_word.last) << ","
                    << output_word.keep;
                for (int lane = 0; lane < RESULT_BYTES / 2; ++lane) {{
                    uint16_t lane_raw = static_cast<uint16_t>(output_bytes[lane * 2]) |
                                        (static_cast<uint16_t>(output_bytes[lane * 2 + 1]) << 8);
                    out << "," << lane_raw;
                }}
                out << "\\n";
                call_ordinal++;
            }}
            std::cout << "call=" << printed_call_ordinal
                      << " sample=" << row.sample_index
                      << " repetition=" << repetition
                      << " expected=" << row.expected_logit
                      << " wrapper=" << wrapper_logit
                      << " raw=" << raw_int
                      << " abs_err=" << abs_err
                      << " last=" << static_cast<int>(output_word.last)
                      << " keep=" << output_word.keep
                      << " pass=" << ok << std::endl;
        }}
    }}
    return failures == 0 ? 0 : 1;
}}
""".strip()


CSYNTH_SENTINEL = Path("wrapper_cosim") / "solution1" / "syn" / "verilog" / "coyote_qkeras_infer.v"


def csynth_complete(work_dir: Path) -> bool:
    return (work_dir / CSYNTH_SENTINEL).exists()


def tcl_source(
    *,
    part: str,
    clock_ns: float,
    cases_csv: Path,
    results_csv: Path,
    tolerance: float,
    warmup_zero_frames: int,
    repetitions_per_sample: int,
    capture_repetition: int,
    run_cosim: bool,
    resume_cosim: bool = False,
) -> str:
    argv = (
        f"{cases_csv} {results_csv} {tolerance} "
        f"{warmup_zero_frames} {repetitions_per_sample} {capture_repetition}"
    )
    if resume_cosim:
        # Reopen existing project+solution without reset; skip csim+csynth.
        return f"""
open_project wrapper_cosim
open_solution solution1
cosim_design -rtl verilog -tool xsim -argv {{{argv}}}
exit
""".strip()

    flow_steps = [
        f"csim_design -argv {{{argv}}}",
    ]
    if run_cosim:
        flow_steps.extend(
            [
                "csynth_design",
                f"cosim_design -rtl verilog -tool xsim -argv {{{argv}}}",
            ]
        )
    return f"""
open_project wrapper_{"cosim" if run_cosim else "csim"}
set_top coyote_qkeras_infer
add_files kernel/coyote_qkeras_infer.cpp -cflags "-Ikernel"
add_files -tb tb_coyote_qkeras_infer.cpp -cflags "-Ikernel"
add_files -tb weights
open_solution -reset solution1
set_part {{{part}}}
create_clock -period {clock_ns} -name default
{chr(10).join(flow_steps)}
exit
""".strip()


def run(cmd: list[str], cwd: Path, log_path: Path) -> int:
    with log_path.open("w") as log:
        proc = subprocess.run(cmd, cwd=cwd, stdout=log, stderr=subprocess.STDOUT, text=True)
    return proc.returncode


def prepare_hls_work_dir(
    *,
    work_dir: Path,
    kernel_dir: Path,
    u55c_root: Path,
    cases: list[dict[str, object]],
    part: str,
    clock_ns: float,
    tolerance: float,
    warmup_zero_frames: int,
    repetitions_per_sample: int,
    capture_repetition: int,
    run_cosim: bool,
    resume_cosim: bool,
) -> tuple[Path, Path, Path, Path, Path | None]:
    if resume_cosim:
        if not csynth_complete(work_dir):
            raise FileNotFoundError(f"--resume-cosim requires completed csynth output at {work_dir / CSYNTH_SENTINEL}")
        print(f"Resuming cosim: existing csynth found in {work_dir / 'wrapper_cosim'}")
        kernel_hdr = work_dir / "kernel" / "coyote_qkeras_infer.hpp"
        output_fraction_bits = parse_output_fraction_bits(kernel_hdr)
        copied_weights = work_dir / "weights" if (work_dir / "weights").exists() else None
    else:
        staged_kernel = copy_kernel(kernel_dir, work_dir)
        copied_weights = copy_weight_files(u55c_root, work_dir)
        output_fraction_bits = parse_output_fraction_bits(staged_kernel / "coyote_qkeras_infer.hpp")

    cases_csv = work_dir / "cases.csv"
    results_csv = work_dir / ("wrapper_cosim_results.csv" if run_cosim else "wrapper_csim_results.csv")
    log_path = work_dir / ("vitis_hls_cosim.log" if run_cosim else "vitis_hls_csim.log")
    tcl_path = work_dir / ("run_cosim.tcl" if run_cosim else "run_csim.tcl")
    write_csv(cases_csv, cases)
    if not resume_cosim:
        (work_dir / "tb_coyote_qkeras_infer.cpp").write_text(testbench_source(output_fraction_bits) + "\n")
    tcl_path.write_text(
        tcl_source(
            part=part,
            clock_ns=clock_ns,
            cases_csv=cases_csv,
            results_csv=results_csv,
            tolerance=tolerance,
            warmup_zero_frames=warmup_zero_frames,
            repetitions_per_sample=repetitions_per_sample,
            capture_repetition=capture_repetition,
            run_cosim=run_cosim,
            resume_cosim=resume_cosim,
        )
        + "\n"
    )
    return cases_csv, results_csv, log_path, tcl_path, copied_weights


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--u55c-root", type=Path, required=True, help="Path to fold_*/u55c_deployment")
    parser.add_argument("--reference-csv", type=Path, default=None, help="hls4ml per-sample reference CSV")
    parser.add_argument("--work-dir", type=Path, default=None, help="Isolated work directory for the HLS test")
    parser.add_argument("--sample-index", type=int, action="append", default=None, help="Specific sample index to test")
    parser.add_argument("--max-samples", type=int, default=0, help="Maximum number of samples to test; <=0 means all")
    parser.add_argument("--part", default=DEFAULT_PART)
    parser.add_argument("--clock-ns", type=float, default=DEFAULT_CLOCK_NS)
    parser.add_argument("--tolerance", type=float, default=1e-6)
    parser.add_argument("--warmup-zero-frames", type=int, default=0)
    parser.add_argument("--repetitions-per-sample", type=int, default=1)
    parser.add_argument("--capture-repetition", type=int, default=1)
    parser.add_argument(
        "--run-cosim",
        action="store_true",
        help="Run csim_design, csynth_design, and cosim_design instead of C simulation only",
    )
    parser.add_argument(
        "--resume-cosim",
        action="store_true",
        help=(
            "Resume an existing cosim run: skip csim+csynth and run only cosim_design "
            "against the already-synthesised project in --work-dir. "
            "Requires --run-cosim and an existing csynth output (wrapper_cosim/solution1/syn/verilog/)."
        ),
    )
    parser.add_argument("--no-run", action="store_true", help="Write the isolated HLS project but do not run Vitis HLS")
    args = parser.parse_args()

    if args.resume_cosim and not args.run_cosim:
        print("ERROR: --resume-cosim requires --run-cosim", file=sys.stderr)
        return 1
    if args.warmup_zero_frames < 0:
        print("ERROR: --warmup-zero-frames must be non-negative", file=sys.stderr)
        return 1
    if args.repetitions_per_sample < 1:
        print("ERROR: --repetitions-per-sample must be >= 1", file=sys.stderr)
        return 1
    if args.capture_repetition < 1 or args.capture_repetition > args.repetitions_per_sample:
        print("ERROR: --capture-repetition must be in [1, repetitions-per-sample]", file=sys.stderr)
        return 1

    u55c_root = resolve_u55c_root(args.u55c_root)
    kernel_dir = u55c_root / "coyote_hw" / "src" / "hls" / "coyote_qkeras_infer"
    prepared_manifest = u55c_root / "prepared_inputs" / "manifest.csv"
    reference_csv = args.reference_csv or (u55c_root.parent / "parity" / "hls_per_sample.csv")
    if not prepared_manifest.exists():
        raise FileNotFoundError(prepared_manifest)
    if not reference_csv.exists():
        raise FileNotFoundError(reference_csv)

    if args.work_dir is None:
        work_dir = Path(tempfile.mkdtemp(prefix="u55c_wrapper_csim_"))
    else:
        work_dir = args.work_dir.resolve()
        work_dir.mkdir(parents=True, exist_ok=True)

    cases = build_cases(
        prepared_manifest,
        reference_csv,
        sample_indices=set(args.sample_index) if args.sample_index else None,
        max_samples=args.max_samples,
    )

    try:
        cases_csv, results_csv, log_path, tcl_path, copied_weights = prepare_hls_work_dir(
            work_dir=work_dir,
            kernel_dir=kernel_dir,
            u55c_root=u55c_root,
            cases=cases,
            part=args.part,
            clock_ns=args.clock_ns,
            tolerance=args.tolerance,
            warmup_zero_frames=args.warmup_zero_frames,
            repetitions_per_sample=args.repetitions_per_sample,
            capture_repetition=args.capture_repetition,
            run_cosim=args.run_cosim,
            resume_cosim=args.resume_cosim,
        )
    except FileNotFoundError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"u55c_root: {u55c_root}")
    print(f"work_dir: {work_dir}")
    print(f"cases: {cases_csv}")
    print(f"results: {results_csv}")
    print(f"log: {log_path}")
    print(f"tcl: {tcl_path}")
    print(f"weights: {copied_weights if copied_weights else 'not found'}")
    if args.no_run:
        return 0

    vitis_hls = shutil.which("vitis_hls")
    if not vitis_hls:
        raise FileNotFoundError("vitis_hls not found on PATH; source the Vitis/HACC enable script first")
    rc = run([vitis_hls, "-f", tcl_path.name], cwd=work_dir, log_path=log_path)
    if not results_csv.exists():
        flow_name = "RTL cosim" if args.run_cosim else "C-sim"
        print(f"{flow_name} did not produce results; see {log_path}", file=sys.stderr)
        return rc or 1

    results = read_csv(results_csv)
    failures = [row for row in results if row.get("pass") != "true"]
    print(f"tested={len(results)} failures={len(failures)}")
    if failures:
        print(f"first failure: {failures[0]}", file=sys.stderr)
    return rc or (1 if failures else 0)


if __name__ == "__main__":
    raise SystemExit(main())
