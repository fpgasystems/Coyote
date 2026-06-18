#!/usr/bin/env python3
"""Run zero-in sample0 through Python Coyote sim and C++ host sim.

This script is intentionally narrow: it targets the current ZERO_IN baseline
artifact, copies the staged Coyote hardware/software into a diagnostics work
directory, and compares sample 0 against the HLS parity CSV with a small raw
fixed-point tolerance.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import shutil
import struct
import subprocess
import sys
import textwrap
import time
from pathlib import Path


DEFAULT_U55C_ROOT = Path(
    "/mnt/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/hls4ml/artifacts/"
    "cnn_small_hls_opt_img256/notebook_pruned_qat/"
    "ZERO_IN_res256_layers5_W8A8_P50_RFbase_07faeca37cb7/"
    "hls_sweeps/RFbase_hls_a121fc48614f/fold_0/u55c_deployment"
)
DEFAULT_INPUT_BYTES = 131072
DEFAULT_RESULT_BYTES = 64
DEFAULT_FRACTION_BITS = 10
COYOTE_ROOT = Path("/pub/scratch/sdeheredia/Coyote")


def run(cmd: list[str], *, cwd: Path, log: Path, env: dict[str, str] | None = None) -> int:
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w") as f:
        f.write(f"$ {' '.join(cmd)}\n")
        f.flush()
        proc = subprocess.run(cmd, cwd=cwd, env=env, stdout=f, stderr=subprocess.STDOUT)
        f.write(f"\nexit_code={proc.returncode}\n")
        return proc.returncode


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as f:
        return list(csv.DictReader(f))


def resolve_u55c_root(path: Path) -> Path:
    root = path.resolve()
    if (root / "coyote_hw" / "src" / "vfpga_top.svh").exists() and (root / "coyote_sw").is_dir():
        return root
    candidate = root / "fold_0" / "u55c_deployment"
    if (candidate / "coyote_hw" / "src" / "vfpga_top.svh").exists() and (candidate / "coyote_sw").is_dir():
        return candidate.resolve()
    raise FileNotFoundError(f"not a staged zero-in u55c_deployment root: {path}")


def reference_csv(u55c_root: Path) -> Path:
    candidate = u55c_root.parent / "parity" / "hls_per_sample.csv"
    if candidate.exists():
        return candidate
    raise FileNotFoundError(candidate)


def expected_raw(reference: Path, sample_index: int) -> tuple[int, float]:
    for row in read_csv(reference):
        if int(row["sample_index"]) == sample_index:
            logit = float(row["logit"])
            return int(round(logit * (1 << DEFAULT_FRACTION_BITS))), logit
    raise KeyError(f"sample_index {sample_index} not found in {reference}")


def sample_input_path(u55c_root: Path, sample_index: int) -> Path:
    manifest = u55c_root / "prepared_inputs" / "manifest.csv"
    for row in read_csv(manifest):
        if int(row["sample_index"]) == sample_index:
            path = Path(row["input_path"])
            return path if path.is_absolute() else (manifest.parent / path).resolve()
    raise KeyError(f"sample_index {sample_index} not found in {manifest}")


def copytree_filtered(src: Path, dst: Path) -> None:
    def ignore(_dir: str, names: list[str]) -> set[str]:
        ignored = {
            "build",
            "build_u55c",
            "build_sim",
            ".Xil",
            ".ipcache",
            "__pycache__",
        }
        return {name for name in names if name in ignored or name.endswith(".jou") or name.endswith(".log")}

    shutil.copytree(src, dst, ignore=ignore)


def patch_host_copy(host_dir: Path) -> None:
    cmake = host_dir / "CMakeLists.txt"
    text = cmake.read_text()
    text = text.replace(
        "add_subdirectory(/pub/scratch/sdeheredia/Coyote/sw ${CMAKE_BINARY_DIR}/coyote)",
        "add_subdirectory(/pub/scratch/sdeheredia/Coyote/sim/sw ${CMAKE_BINARY_DIR}/coyote)",
    )
    text = text.replace(
        "add_subdirectory(/mnt/scratch/sdeheredia/Coyote/sw ${CMAKE_BINARY_DIR}/coyote)",
        "add_subdirectory(/pub/scratch/sdeheredia/Coyote/sim/sw ${CMAKE_BINARY_DIR}/coyote)",
    )
    cmake.write_text(text)

    main_cpp = host_dir / "src" / "main.cpp"
    text = main_cpp.read_text()
    text = text.replace("CoyoteAllocType::HPF", "CoyoteAllocType::REG")
    main_cpp.write_text(text)


def signed16(raw: int) -> int:
    raw &= 0xFFFF
    return raw - 0x10000 if raw & 0x8000 else raw


def output_words(data: bytes) -> list[int]:
    if len(data) != DEFAULT_RESULT_BYTES:
        raise ValueError(f"expected {DEFAULT_RESULT_BYTES} output bytes, got {len(data)}")
    return list(struct.unpack("<" + "H" * (DEFAULT_RESULT_BYTES // 2), data))


def compare_words(words: list[int], expected: int, tolerance: int) -> dict[str, object]:
    actual = signed16(words[0])
    nonzero_padding = [idx for idx, value in enumerate(words[1:], start=1) if value != 0]
    diff = actual - expected
    passed = abs(diff) <= tolerance and not nonzero_padding
    return {
        "actual_raw": actual,
        "expected_raw": expected,
        "diff_raw": diff,
        "tolerance_raw": tolerance,
        "actual_logit": actual / float(1 << DEFAULT_FRACTION_BITS),
        "expected_logit": expected / float(1 << DEFAULT_FRACTION_BITS),
        "nonzero_padding_lanes": nonzero_padding,
        "passed": passed,
    }


def generated_unittest_source() -> str:
    return textwrap.dedent(
        r'''
        import json
        import os
        from pathlib import Path

        from coyote_test import fpga_test_case
        from unit_test.io_writer import CoyoteOperator, CoyoteStreamType
        from unit_test.simulation_time import SimulationTime


        def env_bool(name):
            return os.environ.get(name, "0") in ("1", "true", "True", "yes", "on")


        class ZeroInSampleCase(fpga_test_case.FPGATestCase):
            disable_input_timing_randomization = env_bool("ZERO_IN_DISABLE_RANDOMIZATION")
            debug_mode = True
            verbose_logging = True
            test_sim_dump_module = os.environ.get("ZERO_IN_SIM_DUMP_MODULE", "")

            def test_sample_output_bytes(self):
                case = json.loads(Path(os.environ["ZERO_IN_CASE_JSON"]).read_text())
                log_dir = Path(os.environ["ZERO_IN_SIM_LOG_DIR"])
                log_dir.mkdir(parents=True, exist_ok=True)

                input_bytes = bytearray(bytes.fromhex(case["input_hex"]))
                io = self.get_io_writer()
                self.overwrite_simulation_time(SimulationTime.till_finished())

                in_vaddr = io.allocate_and_write_to_next_free_sim_memory(input_bytes)
                out_vaddr = io.allocate_next_free_sim_memory(case["result_bytes"])
                io.invoke_transfer(
                    CoyoteOperator.LOCAL_READ,
                    CoyoteStreamType.STREAM_HOST,
                    0,
                    in_vaddr,
                    len(input_bytes),
                    True,
                )
                io.invoke_transfer(
                    CoyoteOperator.LOCAL_WRITE,
                    CoyoteStreamType.STREAM_HOST,
                    0,
                    out_vaddr,
                    case["result_bytes"],
                    True,
                )

                end_event = self.simulate_fpga_non_blocking()
                io.block_till_completed(CoyoteOperator.LOCAL_WRITE, 1, end_event)
                io.all_input_done()
                self.finish_fpga_simulation()

                actual = bytes(io.read_from_sim_memory(out_vaddr, case["result_bytes"]))
                (log_dir / "actual_output.hex").write_text(actual.hex() + "\n")
                self.write_simulation_output_to_file()
        '''
    )


def build_python_sim(
    *,
    coyote_hw: Path,
    logs_dir: Path,
) -> tuple[int, Path]:
    build_dir = coyote_hw / "build_u55c"
    rc = run(["cmake", "-S", str(coyote_hw), "-B", str(build_dir), "-DFDEV_NAME=u55c"], cwd=coyote_hw, log=logs_dir / "cmake_hw_sim.log")
    if rc != 0:
        return rc, build_dir
    rc = run(["cmake", "--build", str(build_dir), "--target", "sim"], cwd=coyote_hw, log=logs_dir / "build_hw_sim.log")
    return rc, build_dir


def run_python_variant(
    *,
    coyote_hw: Path,
    build_dir: Path,
    input_bytes: bytes,
    expected: int,
    tolerance: int,
    disable_randomization: bool,
    work_dir: Path,
) -> dict[str, object]:
    label = "no_randomization" if disable_randomization else "randomization"
    variant_dir = work_dir / "python" / label
    logs_dir = variant_dir / "logs"
    unit_tests = coyote_hw / "unit-tests"
    unit_tests.mkdir(parents=True, exist_ok=True)
    test_file = unit_tests / "test_zero_in_sample.py"
    test_file.write_text(generated_unittest_source())
    case_json = variant_dir / "case.json"
    case_json.parent.mkdir(parents=True, exist_ok=True)
    case_json.write_text(
        json.dumps(
            {
                "input_hex": input_bytes.hex(),
                "result_bytes": DEFAULT_RESULT_BYTES,
                "expected_raw": expected,
                "tolerance_raw": tolerance,
                "disable_randomization": disable_randomization,
            },
            indent=2,
        )
        + "\n"
    )

    env = os.environ.copy()
    env["PYTHONPATH"] = str(build_dir) + os.pathsep + env.get("PYTHONPATH", "")
    env["ZERO_IN_CASE_JSON"] = str(case_json)
    env["ZERO_IN_SIM_LOG_DIR"] = str(logs_dir)
    env["ZERO_IN_DISABLE_RANDOMIZATION"] = "1" if disable_randomization else "0"
    env["ZERO_IN_SIM_DUMP_MODULE"] = "inst_coyote_qkeras_infer"
    rc = run([sys.executable, "-m", "unittest", str(test_file)], cwd=coyote_hw, log=logs_dir / "unittest.log", env=env)

    actual_hex = logs_dir / "actual_output.hex"
    result: dict[str, object] = {
        "stage": "python",
        "variant": label,
        "returncode": rc,
        "log": str(logs_dir / "unittest.log"),
        "case_json": str(case_json),
    }
    if actual_hex.exists():
        data = bytes.fromhex(actual_hex.read_text().strip())
        result.update(compare_words(output_words(data), expected, tolerance))
        (variant_dir / "actual_output.hex").write_text(data.hex() + "\n")
    else:
        result.update({"passed": False, "error": "actual_output.hex missing"})

    for name in ["sim.out", "sim_dump.vcd"]:
        src = unit_tests / name
        if src.exists():
            dst = logs_dir / name
            shutil.copy2(src, dst)
            result[name.replace(".", "_")] = str(dst)
    if rc != 0:
        result["passed"] = False
    return result


def run_cpp_host_sim(
    *,
    u55c_root: Path,
    host_src: Path,
    build_dir: Path,
    expected: int,
    tolerance: int,
    max_samples: int,
    timeout_s: float,
    work_dir: Path,
) -> dict[str, object]:
    cpp_dir = work_dir / "cpp"
    logs_dir = cpp_dir / "logs"
    host_copy = cpp_dir / "coyote_sw_sim"
    copytree_filtered(host_src, host_copy)
    patch_host_copy(host_copy)

    result: dict[str, object] = {"stage": "cpp", "host_copy": str(host_copy), "steps": []}
    rc = run(["cmake", "-S", str(host_copy), "-B", str(host_copy / "build_sim")], cwd=cpp_dir, log=logs_dir / "cmake_host_sim.log")
    result["steps"].append({"step": "cmake_host_sim", "returncode": rc})
    if rc != 0:
        result.update({"passed": False, "log": str(logs_dir / "cmake_host_sim.log")})
        return result
    rc = run(["cmake", "--build", str(host_copy / "build_sim")], cwd=cpp_dir, log=logs_dir / "build_host_sim.log")
    result["steps"].append({"step": "build_host_sim", "returncode": rc})
    if rc != 0:
        result.update({"passed": False, "log": str(logs_dir / "build_host_sim.log")})
        return result

    output_csv = cpp_dir / "host_sim_hardware_per_sample.csv"
    repetitions_csv = cpp_dir / "host_sim_hardware_per_sample.repetitions.csv"
    env = os.environ.copy()
    env["COYOTE_SIM_DIR"] = str(build_dir)
    binary = host_copy / "build_sim" / "coyote_qkeras_host"
    rc = run(
        [
            str(binary),
            "--manifest",
            str(u55c_root / "prepared_inputs" / "manifest.csv"),
            "--output",
            str(output_csv),
            "--repetitions-output",
            str(repetitions_csv),
            "--max-samples",
            str(max_samples),
            "--timeout-s",
            str(timeout_s),
        ],
        cwd=cpp_dir,
        log=logs_dir / "run_host_sim.log",
        env=env,
    )
    result["steps"].append({"step": "run_host_sim", "returncode": rc})
    result["output_csv"] = str(output_csv)
    result["repetitions_csv"] = str(repetitions_csv)
    result["log"] = str(logs_dir / "run_host_sim.log")
    if rc != 0:
        result["passed"] = False
        return result

    rows = read_csv(output_csv)
    if not rows:
        result.update({"passed": False, "error": "host output CSV is empty"})
        return result
    raw = int(rows[0]["logit_fixed_raw"])
    words = [raw & 0xFFFF] + [0] * ((DEFAULT_RESULT_BYTES // 2) - 1)
    cmp_result = compare_words(words, expected, tolerance)
    result.update(cmp_result)

    rep_rows = read_csv(repetitions_csv)
    if rep_rows:
        lane_errors: list[dict[str, object]] = []
        for row in rep_rows:
            lane0 = signed16(int(row["lane_00_raw"]))
            diff = lane0 - expected
            nonzero = [idx for idx in range(1, DEFAULT_RESULT_BYTES // 2) if int(row[f"lane_{idx:02d}_raw"]) != 0]
            if abs(diff) > tolerance or nonzero:
                lane_errors.append({"row": row.get("phase", ""), "lane0": lane0, "diff_raw": diff, "nonzero_padding_lanes": nonzero})
        result["repetition_errors"] = lane_errors
        result["passed"] = bool(result["passed"]) and not lane_errors
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--u55c-root", type=Path, default=DEFAULT_U55C_ROOT)
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--sample-index", type=int, default=0)
    parser.add_argument("--tolerance-raw", type=int, default=2)
    parser.add_argument("--timeout-s", type=float, default=300.0)
    parser.add_argument("--skip-cpp", action="store_true")
    args = parser.parse_args()

    started = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    u55c_root = resolve_u55c_root(args.u55c_root)
    work_dir = args.work_dir.resolve()
    logs_dir = work_dir / "logs"
    work_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    ref = reference_csv(u55c_root)
    exp_raw, exp_logit = expected_raw(ref, args.sample_index)
    input_path = sample_input_path(u55c_root, args.sample_index)
    input_bytes = input_path.read_bytes()
    if len(input_bytes) != DEFAULT_INPUT_BYTES:
        raise ValueError(f"expected {DEFAULT_INPUT_BYTES} input bytes in {input_path}, got {len(input_bytes)}")

    isolated = work_dir / "isolated"
    coyote_hw = isolated / "coyote_hw"
    host_src = u55c_root / "coyote_sw"
    copytree_filtered(u55c_root / "coyote_hw", coyote_hw)
    rc, build_dir = build_python_sim(coyote_hw=coyote_hw, logs_dir=logs_dir)
    results: list[dict[str, object]] = []
    if rc != 0:
        results.append({"stage": "python_build", "passed": False, "returncode": rc, "log": str(logs_dir / "build_hw_sim.log")})
    else:
        for disable_randomization in [False, True]:
            results.append(
                run_python_variant(
                    coyote_hw=coyote_hw,
                    build_dir=build_dir,
                    input_bytes=input_bytes,
                    expected=exp_raw,
                    tolerance=args.tolerance_raw,
                    disable_randomization=disable_randomization,
                    work_dir=work_dir,
                )
            )
        if all(bool(row.get("passed")) for row in results) and not args.skip_cpp:
            results.append(
                run_cpp_host_sim(
                    u55c_root=u55c_root,
                    host_src=host_src,
                    build_dir=build_dir,
                    expected=exp_raw,
                    tolerance=args.tolerance_raw,
                    max_samples=1,
                    timeout_s=args.timeout_s,
                    work_dir=work_dir,
                )
            )

    passed = all(bool(row.get("passed")) for row in results)
    summary = {
        "status": "passed" if passed else "failed",
        "started_at": started,
        "finished_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "u55c_root": str(u55c_root),
        "work_dir": str(work_dir),
        "sample_index": args.sample_index,
        "input_path": str(input_path),
        "reference_csv": str(ref),
        "expected_raw": exp_raw,
        "expected_logit": exp_logit,
        "tolerance_raw": args.tolerance_raw,
        "isolated_coyote_hw": str(coyote_hw),
        "isolated_build_dir": str(build_dir),
        "results": results,
    }
    (work_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    with (work_dir / "summary.csv").open("w", newline="") as f:
        fieldnames = sorted({key for row in results for key in row.keys() if not isinstance(row.get(key), (list, dict))})
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in results:
            writer.writerow({key: value for key, value in row.items() if key in fieldnames})
    print(json.dumps(summary, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
