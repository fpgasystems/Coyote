"""Part 5 of the notebook flow: U55C deployment and hardware execution."""

from __future__ import annotations

import os
import time
from pathlib import Path

import numpy as np

from .part1_common import (
    FlowContext,
    clean_rows,
    file_sha256,
    read_json,
    run_command,
    sha256_tree,
    write_json,
    write_run_index,
)

def stage_deploy(ctx: FlowContext, force: bool = False) -> None:
    bit_manifest_path = ctx.u55c_root / "bitstream_manifest.json"
    if not bit_manifest_path.exists():
        raise FileNotFoundError(f"Run bitstream first: {bit_manifest_path}")
    bit_manifest = read_json(bit_manifest_path)
    bitstreams = [Path(path) for path in bit_manifest.get("bitstream_candidates", []) if Path(path).exists()]
    if not bitstreams:
        raise FileNotFoundError("No bitstream available from bitstream stage")
    staged_sw_dir = ctx.u55c_root / "coyote_sw"
    sw_build = staged_sw_dir / "build"
    sw_build.mkdir(parents=True, exist_ok=True)
    sw_fingerprint = {
        "sw_source_hash": sha256_tree(staged_sw_dir),
        "coyote_root": str(ctx.coyote_root),
        "prepared_manifest_hash": file_sha256(ctx.prepared_inputs_dir / "manifest.csv"),
    }
    deployment_manifest_path = ctx.u55c_root / "deployment_manifest.json"
    deployment_manifest = read_json(deployment_manifest_path) if deployment_manifest_path.exists() else {}
    host_exe = sw_build / "coyote_qkeras_host"
    jobs = ctx.config["u55c"].get("build_jobs") or os.cpu_count() or 4
    if force or deployment_manifest.get("sw_fingerprint") != sw_fingerprint or not host_exe.exists():
        run_command(["cmake", ".."], cwd=sw_build, log_path=ctx.u55c_root / "logs" / "cmake_sw.log")
        run_command(["make", "-j", str(jobs)], cwd=sw_build, log_path=ctx.u55c_root / "logs" / "make_sw.log")
        deployment_manifest["sw_fingerprint"] = sw_fingerprint
        deployment_manifest["host_executable"] = str(host_exe)
        write_json(deployment_manifest_path, deployment_manifest)
    bitstream = bitstreams[-1]
    driver_dir = ctx.coyote_root / "driver"
    driver = driver_dir / "build" / "coyote_driver.ko"
    if force or not driver.exists():
        driver_build = driver_dir / "build"
        driver_cflags = " ".join(
            [
                "-std=gnu11",
                "-Wno-declaration-after-statement",
                f"-I{driver_build / 'include'}",
                f"-I{driver_build / 'include' / 'reconfig'}",
                f"-I{driver_build / 'include' / 'vfpga'}",
                f"-I{driver_build / 'include' / 'platform'}",
                "-DPLATFORM_ULTRASCALE_PLUS",
            ]
        )
        run_command(["make", "clean"], cwd=driver_dir, log_path=ctx.u55c_root / "logs" / "make_driver_clean.log")
        run_command(["make", f"EXTRA_CFLAGS={driver_cflags}"], cwd=driver_dir, log_path=ctx.u55c_root / "logs" / "make_driver.log")
    if not driver.exists():
        raise FileNotFoundError(f"Could not build Coyote driver: {driver}")
    program_script = ctx.coyote_root / "util" / "program_hacc_local.sh"
    if not program_script.exists():
        raise FileNotFoundError(program_script)
    run_command(["bash", str(program_script), str(bitstream), str(driver)], cwd=ctx.coyote_root, log_path=ctx.u55c_root / "logs" / "program_u55c.log")
    hardware_csv = ctx.u55c_root / "hardware_per_sample.csv"
    run_command(
        [
            str(host_exe),
            "--manifest",
            str(ctx.prepared_inputs_dir / "manifest.csv"),
            "--output",
            str(hardware_csv),
        ],
        cwd=sw_build,
        log_path=ctx.u55c_root / "logs" / "host_run.log",
    )
    rows = clean_rows(hardware_csv)
    logits = np.asarray([float(row["logit"]) for row in rows], dtype=np.float32)
    lat = np.asarray([float(row["latency_us"]) for row in rows], dtype=np.float64)
    np.save(ctx.u55c_root / "y_hw.npy", logits)
    latency_summary = {
        "n_samples": int(len(rows)),
        "latency_us_mean": float(np.mean(lat)) if len(lat) else None,
        "latency_us_median": float(np.median(lat)) if len(lat) else None,
        "latency_us_min": float(np.min(lat)) if len(lat) else None,
        "latency_us_max": float(np.max(lat)) if len(lat) else None,
        "throughput_samples_per_s": float(1e6 / np.mean(lat)) if len(lat) else None,
    }
    write_json(ctx.u55c_root / "latency_summary.json", latency_summary)
    deployment_manifest.update(
        {
            "deployed_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "bitstream": str(bitstream),
            "driver": str(driver),
            "hardware_per_sample_csv": str(hardware_csv),
            "y_hw": str(ctx.u55c_root / "y_hw.npy"),
            "latency_summary": latency_summary,
        }
    )
    write_json(deployment_manifest_path, deployment_manifest)
    write_run_index(ctx)
