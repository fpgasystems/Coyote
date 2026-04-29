#!/usr/bin/env python3
"""Run a Vitis HLS C-sim test for the staged U55C Coyote wrapper.

This test copies the staged hls4ml/Coyote HLS kernel into an isolated work
directory, generates a small C++ testbench, and checks that the wrapper emits
the same logit semantics as the saved hls4ml CPU reference.
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

static std::vector<int16_t> read_input_blob(const std::string &path) {{
    std::ifstream f(path, std::ios::binary);
    if (!f) throw std::runtime_error("could not open input blob: " + path);
    std::vector<int16_t> values(INPUT_PIXELS);
    f.read(reinterpret_cast<char *>(values.data()), values.size() * sizeof(int16_t));
    if (f.gcount() != static_cast<std::streamsize>(values.size() * sizeof(int16_t))) {{
        throw std::runtime_error("short input blob: " + path);
    }}
    return values;
}}

static void push_input_frame(const std::vector<int16_t> &values, hls::stream<axi_s> &input_stream) {{
    for (int beat = 0; beat < INPUT_BEATS; ++beat) {{
        axi_s word;
        word.data = 0;
        word.keep = -1;
        word.last = (beat == INPUT_BEATS - 1);
        for (int lane = 0; lane < PIXELS_PER_BEAT; ++lane) {{
            int pixel = beat * PIXELS_PER_BEAT + lane;
            ap_uint<FIXED_WIDTH> raw = static_cast<uint16_t>(values[pixel]);
            word.data.range((lane + 1) * FIXED_WIDTH - 1, lane * FIXED_WIDTH) = raw;
        }}
        input_stream.write(word);
    }}
}}

int main(int argc, char **argv) {{
    if (argc < 4) {{
        std::cerr << "usage: tb <cases.csv> <results.csv> <tolerance>\\n";
        return 2;
    }}
    const std::string cases_csv = argv[1];
    const std::string results_csv = argv[2];
    const double tolerance = std::stod(argv[3]);
    auto cases = read_cases(cases_csv);

    std::ofstream out(results_csv);
    if (!out) throw std::runtime_error("could not open results CSV: " + results_csv);
    out << "sample_index,expected_logit,wrapper_raw,wrapper_logit,abs_err,pass,last,keep\\n";

    int failures = 0;
    for (const auto &row : cases) {{
        hls::stream<axi_s> input_stream("input_stream");
        hls::stream<axi_s> output_stream("output_stream");
        auto values = read_input_blob(row.input_path);
        push_input_frame(values, input_stream);

        coyote_qkeras_infer(input_stream, output_stream);
        if (output_stream.empty()) {{
            throw std::runtime_error("wrapper produced no output for sample " + std::to_string(row.sample_index));
        }}
        axi_s output_word = output_stream.read();
        ap_int<FIXED_WIDTH> raw = output_word.data.range(FIXED_WIDTH - 1, 0);
        int raw_int = raw.to_int();
        double wrapper_logit = static_cast<double>(raw_int) / static_cast<double>(1 << OUTPUT_FRAC_BITS);
        double abs_err = std::abs(wrapper_logit - row.expected_logit);
        bool ok = abs_err <= tolerance;
        if (!ok) failures++;
        out << row.sample_index << ","
            << std::setprecision(12) << row.expected_logit << ","
            << raw_int << ","
            << std::setprecision(12) << wrapper_logit << ","
            << std::setprecision(12) << abs_err << ","
            << (ok ? "true" : "false") << ","
            << static_cast<int>(output_word.last) << ","
            << output_word.keep << "\\n";
        std::cout << "sample=" << row.sample_index
                  << " expected=" << row.expected_logit
                  << " wrapper=" << wrapper_logit
                  << " abs_err=" << abs_err
                  << " pass=" << ok << std::endl;
    }}
    return failures == 0 ? 0 : 1;
}}
""".strip()


def tcl_source(part: str, clock_ns: float, cases_csv: Path, results_csv: Path, tolerance: float) -> str:
    return f"""
open_project wrapper_csim
set_top coyote_qkeras_infer
add_files kernel/coyote_qkeras_infer.cpp -cflags "-Ikernel"
add_files -tb tb_coyote_qkeras_infer.cpp -cflags "-Ikernel"
add_files -tb weights
open_solution -reset solution1
set_part {{{part}}}
create_clock -period {clock_ns} -name default
csim_design -argv {{{cases_csv} {results_csv} {tolerance}}}
exit
""".strip()


def run(cmd: list[str], cwd: Path, log_path: Path) -> int:
    with log_path.open("w") as log:
        proc = subprocess.run(cmd, cwd=cwd, stdout=log, stderr=subprocess.STDOUT, text=True)
    return proc.returncode


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--u55c-root", type=Path, required=True, help="Path to fold_*/u55c_deployment")
    parser.add_argument("--reference-csv", type=Path, default=None, help="hls4ml CPU per-sample CSV")
    parser.add_argument("--work-dir", type=Path, default=None, help="Isolated work directory for C simulation")
    parser.add_argument("--sample-index", type=int, action="append", default=None, help="Specific sample index to test")
    parser.add_argument("--max-samples", type=int, default=1, help="Maximum number of samples to test; <=0 means all")
    parser.add_argument("--part", default=DEFAULT_PART)
    parser.add_argument("--clock-ns", type=float, default=DEFAULT_CLOCK_NS)
    parser.add_argument("--tolerance", type=float, default=1e-6)
    parser.add_argument("--no-run", action="store_true", help="Write the isolated C-sim project but do not run Vitis HLS")
    args = parser.parse_args()

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

    staged_kernel = copy_kernel(kernel_dir, work_dir)
    copied_weights = copy_weight_files(u55c_root, work_dir)
    output_fraction_bits = parse_output_fraction_bits(staged_kernel / "coyote_qkeras_infer.hpp")
    cases = build_cases(
        prepared_manifest,
        reference_csv,
        sample_indices=set(args.sample_index) if args.sample_index else None,
        max_samples=args.max_samples,
    )
    cases_csv = work_dir / "cases.csv"
    results_csv = work_dir / "wrapper_csim_results.csv"
    log_path = work_dir / "vitis_hls_csim.log"
    write_csv(cases_csv, cases)
    (work_dir / "tb_coyote_qkeras_infer.cpp").write_text(testbench_source(output_fraction_bits) + "\n")
    (work_dir / "run_csim.tcl").write_text(tcl_source(args.part, args.clock_ns, cases_csv, results_csv, args.tolerance) + "\n")

    print(f"u55c_root: {u55c_root}")
    print(f"work_dir: {work_dir}")
    print(f"cases: {cases_csv}")
    print(f"results: {results_csv}")
    print(f"log: {log_path}")
    print(f"weights: {copied_weights if copied_weights else 'not found'}")
    if args.no_run:
        return 0

    vitis_hls = shutil.which("vitis_hls")
    if not vitis_hls:
        raise FileNotFoundError("vitis_hls not found on PATH; source the Vitis/HACC enable script first")
    rc = run([vitis_hls, "-f", "run_csim.tcl"], cwd=work_dir, log_path=log_path)
    if not results_csv.exists():
        print(f"C-sim did not produce results; see {log_path}", file=sys.stderr)
        return rc or 1

    results = read_csv(results_csv)
    failures = [row for row in results if row.get("pass") != "true"]
    print(f"tested={len(results)} failures={len(failures)}")
    if failures:
        print(f"first failure: {failures[0]}", file=sys.stderr)
    return rc or (1 if failures else 0)


if __name__ == "__main__":
    raise SystemExit(main())
