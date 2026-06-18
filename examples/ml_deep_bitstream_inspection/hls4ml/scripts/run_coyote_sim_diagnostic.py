#!/usr/bin/env python3
"""Run Coyote behavioral sim for a staged U55C CNN deployment.

This drives exact prepared-input bytes through the Coyote simulation testbench
(`axis_host_recv`/`axis_host_send`) and checks the 64-byte host-visible output.
It is intentionally separate from the HLS C-sim/cosim script: this validates
the staged `vfpga_top.svh` and packaged HLS IP inside the Coyote sim wrapper.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import textwrap
import time
from pathlib import Path


DEFAULT_RESULT_BYTES = 64
DEFAULT_INPUT_BYTES = 131072
DEFAULT_FRACTION_BITS = 10


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
    if (root / "coyote_hw" / "src" / "vfpga_top.svh").exists():
        return root
    candidate = root / "fold_0" / "u55c_deployment"
    if (candidate / "coyote_hw" / "src" / "vfpga_top.svh").exists():
        return candidate.resolve()
    raise FileNotFoundError(f"not a staged u55c_deployment root: {path}")


def find_reference_csv(u55c_root: Path) -> Path | None:
    candidates = [
        u55c_root.parent / "parity" / "hls_per_sample.csv",
        u55c_root.parent.parent / "parity" / "hls_per_sample.csv",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return None


def expected_raw_from_reference(reference_csv: Path, sample_index: int) -> int:
    for row in read_csv(reference_csv):
        if int(row["sample_index"]) == sample_index:
            logit = float(row["logit"])
            return int(round(logit * (1 << DEFAULT_FRACTION_BITS)))
    raise KeyError(f"sample_index {sample_index} not found in {reference_csv}")


def expected_bytes_from_lanes_csv(path: Path, row_index: int = 0) -> bytes:
    rows = read_csv(path)
    if row_index < 0 or row_index >= len(rows):
        raise IndexError(f"row index {row_index} out of range for {path}")
    row = rows[row_index]
    fields: list[int] = []
    for lane in range(DEFAULT_RESULT_BYTES // 2):
        key = f"lane_{lane:02d}_raw"
        if key not in row:
            raise KeyError(f"{path} does not contain {key}")
        fields.append(int(row[key]) & 0xFFFF)
    return b"".join(struct.pack("<H", field) for field in fields)


def sample_input_path(u55c_root: Path, sample_index: int) -> Path:
    manifest = u55c_root / "prepared_inputs" / "manifest.csv"
    if manifest.exists():
        for row in read_csv(manifest):
            if int(row["sample_index"]) == sample_index:
                path = Path(row["input_path"])
                return path if path.is_absolute() else (manifest.parent / path).resolve()
    fallback = u55c_root / "prepared_inputs" / f"sample_{sample_index:04d}.bin"
    if fallback.exists():
        return fallback
    raise FileNotFoundError(f"could not find prepared input for sample {sample_index} under {u55c_root}")


def read_input_bytes(u55c_root: Path, sample_index: int, zero_stream_input: bool) -> bytes:
    if zero_stream_input:
        return bytes(DEFAULT_INPUT_BYTES)
    path = sample_input_path(u55c_root, sample_index)
    data = path.read_bytes()
    if len(data) != DEFAULT_INPUT_BYTES:
        raise ValueError(f"expected {DEFAULT_INPUT_BYTES} input bytes in {path}, got {len(data)}")
    return data


def parse_rom_metadata(u55c_root: Path) -> tuple[int, int] | None:
    header = u55c_root / "coyote_hw" / "src" / "hls" / "coyote_qkeras_infer" / "rom_input_values.hpp"
    if not header.exists():
        return None
    text = header.read_text(errors="ignore")
    kind = re.search(r"ROM_INPUT_KIND\s*=\s*(-?\d+)", text)
    sample = re.search(r"ROM_INPUT_SAMPLE_INDEX\s*=\s*(-?\d+)", text)
    if not kind or not sample:
        return None
    return int(kind.group(1)), int(sample.group(1))


def input_debug_fields(input_bytes: bytes) -> dict[str, int]:
    if len(input_bytes) % 2:
        raise ValueError("input byte length must be even")
    n = len(input_bytes) // 2
    vals = struct.unpack("<" + "h" * n, input_bytes)
    full_sum = sum(vals)
    weighted_sum = sum(v * (i + 1) for i, v in enumerate(vals))
    return {
        "input_beats": n // 32,
        "tlast_count": 1,
        "first_tlast_beat": n // 32 - 1,
        "last_tlast_beat": n // 32 - 1,
        "early_tlast": 0,
        "missing_tlast": 0,
        "keep_error_count": 0,
        "full_sum_raw": full_sum & 0xFFFF,
        "weighted_sum_raw": weighted_sum & 0xFFFF,
        "first_lane0_raw": vals[0] & 0xFFFF,
        "last_lane0_raw": vals[-32] & 0xFFFF,
    }


def build_expected_bytes(
    *,
    mode: str,
    expected_raw: int,
    input_bytes: bytes,
    rom_metadata: tuple[int, int] | None,
) -> bytes:
    fields = [0] * (DEFAULT_RESULT_BYTES // 2)
    dbg = input_debug_fields(input_bytes)
    fields[0] = expected_raw & 0xFFFF
    if mode == "rom":
        if rom_metadata is None:
            raise ValueError("--mode rom requires rom_input_values.hpp metadata")
        fields[1] = 0x524D
        fields[2] = 0
        fields[3] = dbg["input_beats"]
        fields[4] = dbg["tlast_count"]
        fields[5] = dbg["first_tlast_beat"]
        fields[6] = dbg["last_tlast_beat"]
        fields[7] = dbg["early_tlast"]
        fields[8] = dbg["missing_tlast"]
        fields[9] = dbg["keep_error_count"]
        fields[10] = dbg["full_sum_raw"]
        fields[11] = dbg["weighted_sum_raw"]
        fields[12] = dbg["first_lane0_raw"]
        fields[13] = dbg["last_lane0_raw"]
        fields[14] = rom_metadata[0] & 0xFFFF
        fields[15] = rom_metadata[1] & 0xFFFF
    elif mode == "framed":
        fields[1] = 0x4642
        fields[2] = 0
        fields[3] = dbg["input_beats"]
        fields[4] = dbg["tlast_count"]
        fields[5] = dbg["first_tlast_beat"]
        fields[6] = dbg["last_tlast_beat"]
        fields[7] = dbg["early_tlast"]
        fields[8] = dbg["missing_tlast"]
        fields[9] = dbg["keep_error_count"]
        fields[10] = dbg["full_sum_raw"]
        fields[11] = dbg["weighted_sum_raw"]
        fields[12] = dbg["first_lane0_raw"]
        fields[13] = dbg["last_lane0_raw"]
    elif mode == "raw":
        pass
    else:
        raise ValueError(f"unsupported mode: {mode}")
    return b"".join(struct.pack("<H", field & 0xFFFF) for field in fields)


def generated_unittest_source() -> str:
    return textwrap.dedent(
        r'''
        import json
        import os
        from pathlib import Path

        from coyote_test import fpga_test_case
        from unit_test.io_writer import CoyoteOperator, CoyoteStreamType
        from unit_test.simulation_time import SimulationTime


        def _env_bool(name):
            return os.environ.get(name, "0") in ("1", "true", "True", "yes", "on")


        class GeneratedCoyoteSimCase(fpga_test_case.FPGATestCase):
            disable_input_timing_randomization = _env_bool("COYOTE_SIM_DISABLE_RANDOMIZATION")
            debug_mode = True
            verbose_logging = True
            test_sim_dump_module = os.environ.get("COYOTE_SIM_DUMP_MODULE", "")

            def test_exact_output_bytes(self):
                case = json.loads(Path(os.environ["COYOTE_SIM_CASE_JSON"]).read_text())
                log_dir = Path(os.environ["COYOTE_SIM_LOG_DIR"])
                log_dir.mkdir(parents=True, exist_ok=True)

                input_bytes = bytearray(bytes.fromhex(case["input_hex"]))
                expected = bytearray(bytes.fromhex(case["expected_hex"]))
                io = self.get_io_writer()

                self.overwrite_simulation_time(SimulationTime.till_finished())

                in_vaddr = io.allocate_and_write_to_next_free_sim_memory(input_bytes)
                out_vaddr = io.allocate_next_free_sim_memory(len(expected))
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
                    len(expected),
                    True,
                )

                end_event = self.simulate_fpga_non_blocking()
                io.block_till_completed(CoyoteOperator.LOCAL_WRITE, 1, end_event)
                io.all_input_done()
                self.finish_fpga_simulation()

                actual = io.read_from_sim_memory(out_vaddr, len(expected))
                (log_dir / "actual_output.hex").write_text(bytes(actual).hex() + "\n")
                (log_dir / "expected_output.hex").write_text(bytes(expected).hex() + "\n")
                self.write_simulation_output_to_file()
                self.assertEqual(bytes(expected), bytes(actual))
        '''
    )


def write_case_json(path: Path, input_bytes: bytes, expected_bytes: bytes, meta: dict[str, object]) -> None:
    payload = {
        **meta,
        "input_hex": input_bytes.hex(),
        "expected_hex": expected_bytes.hex(),
    }
    path.write_text(json.dumps(payload, indent=2) + "\n")


def run_one_variant(
    *,
    u55c_root: Path,
    work_dir: Path,
    mode: str,
    sample_index: int,
    expected_raw: int,
    expected_bytes: bytes | None,
    zero_stream_input: bool,
    disable_randomization: bool,
    skip_sim_build: bool,
) -> dict[str, object]:
    label = "no_randomization" if disable_randomization else "randomization"
    variant_dir = work_dir / label
    logs_dir = variant_dir / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)

    coyote_hw = u55c_root / "coyote_hw"
    build_dir = coyote_hw / "build_u55c"
    unit_tests = coyote_hw / "unit-tests"
    unit_tests.mkdir(parents=True, exist_ok=True)
    test_file = unit_tests / "test_generated_coyote_sim.py"
    test_file.write_text(generated_unittest_source())

    sim_rc = 0
    if not skip_sim_build:
        sim_rc = run(
            ["cmake", "--build", str(build_dir), "--target", "sim"],
            cwd=coyote_hw,
            log=logs_dir / "build_sim.log",
        )
        if sim_rc != 0:
            return {
                "variant": label,
                "status": "build_sim_failed",
                "returncode": sim_rc,
                "log": str(logs_dir / "build_sim.log"),
            }

    input_bytes = read_input_bytes(u55c_root, sample_index, zero_stream_input)
    if expected_bytes is None:
        expected_bytes = build_expected_bytes(
            mode=mode,
            expected_raw=expected_raw,
            input_bytes=input_bytes,
            rom_metadata=parse_rom_metadata(u55c_root),
        )
    case_json = variant_dir / "case.json"
    write_case_json(
        case_json,
        input_bytes,
        expected_bytes,
        {
            "u55c_root": str(u55c_root),
            "mode": mode,
            "sample_index": sample_index,
            "expected_raw": expected_raw,
            "expected_logit": expected_raw / float(1 << DEFAULT_FRACTION_BITS),
            "zero_stream_input": zero_stream_input,
            "disable_randomization": disable_randomization,
        },
    )

    env = os.environ.copy()
    env["PYTHONPATH"] = str(build_dir) + os.pathsep + env.get("PYTHONPATH", "")
    env["COYOTE_SIM_CASE_JSON"] = str(case_json)
    env["COYOTE_SIM_LOG_DIR"] = str(logs_dir)
    env["COYOTE_SIM_DISABLE_RANDOMIZATION"] = "1" if disable_randomization else "0"
    env["COYOTE_SIM_DUMP_MODULE"] = "inst_coyote_qkeras_infer"

    rc = run(
        [sys.executable, "-m", "unittest", str(test_file)],
        cwd=coyote_hw,
        log=logs_dir / "unittest.log",
        env=env,
    )
    sim_out = unit_tests / "sim.out"
    if sim_out.exists():
        shutil.copy2(sim_out, logs_dir / "sim.out")
    vcd = unit_tests / "sim_dump.vcd"
    if vcd.exists():
        shutil.copy2(vcd, logs_dir / "sim_dump.vcd")
    return {
        "variant": label,
        "status": "passed" if rc == 0 else "failed",
        "returncode": rc,
        "log": str(logs_dir / "unittest.log"),
        "sim_out": str(logs_dir / "sim.out"),
        "vcd": str(logs_dir / "sim_dump.vcd"),
        "case_json": str(case_json),
        "expected_raw": expected_raw,
        "expected_logit": expected_raw / float(1 << DEFAULT_FRACTION_BITS),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--u55c-root", required=True, type=Path)
    ap.add_argument("--work-dir", required=True, type=Path)
    ap.add_argument("--mode", required=True, choices=["framed", "rom", "raw"])
    ap.add_argument("--sample-index", type=int, default=0)
    ap.add_argument("--expected-raw", type=int)
    ap.add_argument("--expected-hex", default=None, help="Exact expected 64-byte output as a hex string")
    ap.add_argument("--expected-lanes-csv", type=Path, help="CSV containing lane_00_raw..lane_31_raw columns")
    ap.add_argument("--expected-lanes-row", type=int, default=0)
    ap.add_argument("--reference-csv", type=Path)
    ap.add_argument("--zero-stream-input", action="store_true")
    ap.add_argument("--randomization", choices=["both", "on", "off"], default="both")
    ap.add_argument("--skip-sim-build", action="store_true")
    args = ap.parse_args()

    u55c_root = resolve_u55c_root(args.u55c_root)
    work_dir = args.work_dir.resolve()
    work_dir.mkdir(parents=True, exist_ok=True)

    reference_csv = args.reference_csv or find_reference_csv(u55c_root)
    expected_bytes: bytes | None = None
    if args.expected_hex is not None:
        expected_bytes = bytes.fromhex(args.expected_hex.strip())
        if len(expected_bytes) != DEFAULT_RESULT_BYTES:
            raise SystemExit(f"--expected-hex must decode to {DEFAULT_RESULT_BYTES} bytes")
    elif args.expected_lanes_csv is not None:
        expected_bytes = expected_bytes_from_lanes_csv(args.expected_lanes_csv, args.expected_lanes_row)

    if args.expected_raw is None and expected_bytes is None:
        if reference_csv is None:
            raise SystemExit("--expected-raw is required when no hls_per_sample.csv reference is available")
        expected_raw = expected_raw_from_reference(reference_csv, args.sample_index)
    elif args.expected_raw is None:
        expected_raw = 0
    else:
        expected_raw = args.expected_raw

    if args.randomization == "both":
        randomization_modes = [False, True]
    elif args.randomization == "on":
        randomization_modes = [False]
    else:
        randomization_modes = [True]

    started = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    rows: list[dict[str, object]] = []
    for i, disable_randomization in enumerate(randomization_modes):
        rows.append(
            run_one_variant(
                u55c_root=u55c_root,
                work_dir=work_dir,
                mode=args.mode,
                sample_index=args.sample_index,
                expected_raw=expected_raw,
                expected_bytes=expected_bytes,
                zero_stream_input=args.zero_stream_input,
                disable_randomization=disable_randomization,
                skip_sim_build=args.skip_sim_build or i > 0,
            )
        )

    summary = {
        "started_at": started,
        "finished_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "u55c_root": str(u55c_root),
        "work_dir": str(work_dir),
        "mode": args.mode,
        "sample_index": args.sample_index,
        "expected_raw": expected_raw,
        "expected_logit": expected_raw / float(1 << DEFAULT_FRACTION_BITS),
        "zero_stream_input": args.zero_stream_input,
        "reference_csv": str(reference_csv) if reference_csv else None,
        "results": rows,
    }
    (work_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    with (work_dir / "summary.csv").open("w", newline="") as f:
        fieldnames = sorted({key for row in rows for key in row.keys()})
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(json.dumps(summary, indent=2))
    return 0 if all(row["status"] == "passed" for row in rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
