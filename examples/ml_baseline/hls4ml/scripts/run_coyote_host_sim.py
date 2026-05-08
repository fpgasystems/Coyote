#!/usr/bin/env python3
"""Run a generated Coyote host program against the Coyote simulation library.

This is the C++ host-simulation path: it keeps the staged hardware design under
`coyote_hw`, copies the generated `coyote_sw` host program into a diagnostic
work directory, links that copy against `/Coyote/sim/sw`, and runs it with
`COYOTE_SIM_DIR=<u55c_root>/coyote_hw/build_u55c`.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import time
from pathlib import Path


COYOTE_DIR = Path("/pub/scratch/sdeheredia/Coyote")


def resolve_u55c_root(path: Path) -> Path:
    root = path.resolve()
    if (root / "coyote_hw").is_dir() and (root / "coyote_sw").is_dir():
        return root
    candidate = root / "fold_0" / "u55c_deployment"
    if (candidate / "coyote_hw").is_dir() and (candidate / "coyote_sw").is_dir():
        return candidate.resolve()
    raise FileNotFoundError(f"not a staged u55c_deployment root: {path}")


def run(cmd: list[str], *, cwd: Path, log: Path, env: dict[str, str] | None = None) -> int:
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w") as f:
        f.write(f"$ {' '.join(cmd)}\n")
        f.flush()
        proc = subprocess.run(cmd, cwd=cwd, env=env, stdout=f, stderr=subprocess.STDOUT)
        f.write(f"\nexit_code={proc.returncode}\n")
        return proc.returncode


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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--u55c-root", required=True, type=Path)
    parser.add_argument("--work-dir", required=True, type=Path)
    parser.add_argument("--max-samples", type=int, default=1)
    parser.add_argument("--timeout-s", type=float, default=300.0)
    parser.add_argument("--skip-sim-build", action="store_true")
    args = parser.parse_args()

    u55c_root = resolve_u55c_root(args.u55c_root)
    work_dir = args.work_dir.resolve()
    logs_dir = work_dir / "logs"
    work_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    manifest = u55c_root / "prepared_inputs" / "manifest.csv"
    if not manifest.exists():
        raise FileNotFoundError(manifest)

    host_copy = work_dir / "coyote_sw_sim"
    if host_copy.exists():
        raise FileExistsError(f"work host copy already exists: {host_copy}")
    shutil.copytree(u55c_root / "coyote_sw", host_copy)
    patch_host_copy(host_copy)

    status = {
        "started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "u55c_root": str(u55c_root),
        "work_dir": str(work_dir),
        "host_copy": str(host_copy),
        "max_samples": args.max_samples,
        "steps": [],
    }

    build_hw = u55c_root / "coyote_hw" / "build_u55c"
    if not args.skip_sim_build:
        rc = run(
            ["cmake", "--build", str(build_hw), "--target", "sim"],
            cwd=u55c_root / "coyote_hw",
            log=logs_dir / "build_hw_sim.log",
        )
        status["steps"].append({"step": "build_hw_sim", "returncode": rc})
        if rc != 0:
            (work_dir / "summary.json").write_text(json.dumps(status, indent=2) + "\n")
            return rc

    rc = run(
        ["cmake", "-S", str(host_copy), "-B", str(host_copy / "build_sim")],
        cwd=work_dir,
        log=logs_dir / "cmake_host_sim.log",
    )
    status["steps"].append({"step": "cmake_host_sim", "returncode": rc})
    if rc != 0:
        (work_dir / "summary.json").write_text(json.dumps(status, indent=2) + "\n")
        return rc

    rc = run(
        ["cmake", "--build", str(host_copy / "build_sim")],
        cwd=work_dir,
        log=logs_dir / "build_host_sim.log",
    )
    status["steps"].append({"step": "build_host_sim", "returncode": rc})
    if rc != 0:
        (work_dir / "summary.json").write_text(json.dumps(status, indent=2) + "\n")
        return rc

    output_csv = work_dir / "host_sim_hardware_per_sample.csv"
    repetitions_csv = work_dir / "host_sim_hardware_per_sample.repetitions.csv"
    env = os.environ.copy()
    env["COYOTE_SIM_DIR"] = str(build_hw)
    binary = host_copy / "build_sim" / "coyote_qkeras_host"
    rc = run(
        [
            str(binary),
            "--manifest",
            str(manifest),
            "--output",
            str(output_csv),
            "--repetitions-output",
            str(repetitions_csv),
            "--max-samples",
            str(args.max_samples),
            "--timeout-s",
            str(args.timeout_s),
        ],
        cwd=work_dir,
        log=logs_dir / "run_host_sim.log",
        env=env,
    )
    status["steps"].append({"step": "run_host_sim", "returncode": rc})
    status["output_csv"] = str(output_csv)
    status["repetitions_csv"] = str(repetitions_csv)
    status["finished_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    status["status"] = "passed" if rc == 0 else "failed"
    (work_dir / "summary.json").write_text(json.dumps(status, indent=2) + "\n")
    print(json.dumps(status, indent=2))
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
