"""Part 4 of the notebook flow: CoyoteAccelerator raw-input bitstream build."""

from __future__ import annotations

import re
import shutil
import time
import os
from pathlib import Path
from typing import Any

import numpy as np

from .coyote_accelerator.project import (
    convert_coyote_model,
    patch_generated_project,
    template_hashes,
    write_compile_smoke,
)
from .coyote_accelerator.raw_data import write_coyote_prepared_inputs
from .part1_common import FlowContext, file_sha256, read_json, sha256_tree, write_json, write_run_index
from .part2_train import current_validation_samples, get_splits, load_current_model


def coyote_accelerator_config(ctx: FlowContext) -> dict[str, Any]:
    raw = dict(ctx.config.get("u55c", {}).get("coyote_accelerator", {}) or {})
    raw.setdefault("project_name", "zero_in_coyote_accel")
    raw.setdefault("batch_size", int(ctx.config.get("training", {}).get("batch_size", 16)))
    if os.environ.get("HLS4ML_COYOTE_BATCH_SIZE"):
        raw["batch_size"] = int(os.environ["HLS4ML_COYOTE_BATCH_SIZE"])
    raw.setdefault("raw_csim_samples", 1)
    raw.setdefault("tolerance", 0.20)
    raw.setdefault("device", "u55c")
    raw.setdefault("hls_clock_period", 4.0)
    raw.setdefault("hls_clock_uncertainty", 27.0)
    raw.setdefault("bitfile", True)
    raw.setdefault("program_fpga", True)
    return raw


def coyote_output_dir(ctx: FlowContext) -> Path:
    return ctx.u55c_root / "coyote_accelerator_project"


def file_hash_record(path: Path) -> dict[str, Any]:
    path = Path(path)
    record: dict[str, Any] = {"path": str(path), "exists": path.exists()}
    if path.exists():
        record.update({"sha256": file_sha256(path), "bytes": path.stat().st_size})
    return record


def parse_shell_timing_summary(report_path: Path) -> dict[str, Any]:
    summary: dict[str, Any] = {"report": str(report_path), "exists": report_path.exists()}
    if not report_path.exists():
        return summary
    text = report_path.read_text(errors="ignore")
    summary["constraints_met"] = "Timing constraints are met." in text
    summary["constraints_failed"] = "Timing constraints are not met." in text
    match = re.search(
        r"WNS\(ns\)\s+TNS\(ns\)\s+TNS Failing Endpoints.*?\n\s*-+\s+-+\s+-+.*?\n\s*"
        r"(?P<wns>-?\d+(?:\.\d+)?)\s+(?P<tns>-?\d+(?:\.\d+)?)\s+(?P<fail>\d+)\s+(?P<total>\d+)",
        text,
        re.S,
    )
    if match:
        summary.update(
            {
                "wns": float(match.group("wns")),
                "tns": float(match.group("tns")),
                "failing_endpoints": int(match.group("fail")),
                "total_endpoints": int(match.group("total")),
            }
        )
        summary["timing_clean"] = (
            float(summary["wns"]) >= 0.0
            and float(summary["tns"]) >= 0.0
            and int(summary["failing_endpoints"]) == 0
        )
    return summary


def coyote_build_outputs(project_dir: Path, project_name: str) -> dict[str, Any]:
    hw_build = project_dir / "build" / f"{project_name}_cyt_hw"
    sw_build = project_dir / "build" / f"{project_name}_cyt_sw"
    return {
        "bitstream_candidates": sorted(str(path) for path in hw_build.rglob("*.bit")),
        "report_candidates": sorted(str(path) for path in hw_build.rglob("*.rpt")),
        "dcp_candidates": sorted(str(path) for path in hw_build.rglob("*.dcp")),
        "host_library": str(sw_build / "lib" / "libCoyoteInference.so"),
        "timing_summary": parse_shell_timing_summary(hw_build / "reports" / "shell_timing_summary.rpt"),
        "artifact_hashes": {
            "model_wrapper_cpp": file_hash_record(project_dir / "src/hls/model_wrapper/model_wrapper.cpp"),
            "model_wrapper_hpp": file_hash_record(project_dir / "src/hls/model_wrapper/model_wrapper.hpp"),
            "raw_downsampler": file_hash_record(project_dir / "src/hls/model_wrapper/firmware/zero_in_raw_downsample.hpp"),
            "host_libs_cpp": file_hash_record(project_dir / "src/host_libs.cpp"),
            "host_libs_hpp": file_hash_record(project_dir / "src/host_libs.hpp"),
            "raw_testbench": file_hash_record(project_dir / f"src/{project_name}_test.cpp"),
            "cyt_top_bitstream": file_hash_record(hw_build / "bitstreams" / "cyt_top.bit"),
            "host_library": file_hash_record(sw_build / "lib" / "libCoyoteInference.so"),
        },
    }


def stage_bitstream(ctx: FlowContext, force: bool = False) -> None:
    splits = get_splits(ctx)
    val_samples, _n_train, eval_split = current_validation_samples(ctx, splits)
    prepared_manifest = write_coyote_prepared_inputs(ctx, val_samples, force=force)

    cfg = coyote_accelerator_config(ctx)
    project_name = str(cfg["project_name"])
    output_dir = coyote_output_dir(ctx)
    project_dir = output_dir / "project"
    manifest_path = ctx.u55c_root / "bitstream_manifest.json"
    stage_fingerprint = {
        "stage_version": "2026-05-17-coyote-accelerator-raw-downsampler",
        "training_fingerprint": ctx.training_fingerprint,
        "hls_fingerprint": ctx.hls_fingerprint,
        "coyote_accelerator_config": cfg,
        "prepared_manifest": prepared_manifest,
        "model_slot": ctx.model_slot,
        "eval_split": eval_split,
        "template_hashes": template_hashes(),
        "source_hashes": ctx.source_hashes,
    }
    if not force and manifest_path.exists():
        old = read_json(manifest_path)
        outputs = coyote_build_outputs(Path(old.get("project_dir", project_dir)), str(old.get("project_name", project_name)))
        host_lib = Path(outputs["host_library"])
        bitstreams = [Path(path) for path in outputs["bitstream_candidates"] if Path(path).exists()]
        if old.get("stage_fingerprint") == stage_fingerprint and host_lib.exists() and (bitstreams or not bool(cfg["bitfile"])):
            print("CoyoteAccelerator bitstream cache hit")
            old.update(outputs)
            write_json(manifest_path, old)
            write_run_index(ctx)
            return

    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    model = load_current_model(ctx)
    x = np.load(ctx.prepared_inputs_dir / "x_norm.npy").astype(np.float32)
    labels = np.load(ctx.prepared_inputs_dir / "labels.npy").astype(np.int32)
    keras_logits = np.asarray(model.predict(x, verbose=0)).reshape(-1)
    hls_model, _hls_config = convert_coyote_model(ctx, model, x, keras_logits, output_dir, project_name)
    hls_model.compile()

    raw_rows = read_json(ctx.prepared_inputs_dir / "manifest.json")
    raw_samples = []
    import csv

    with (ctx.prepared_inputs_dir / "manifest.csv").open(newline="") as handle:
        for row in csv.DictReader(handle):
            raw_samples.append(dict(row))
    patches = patch_generated_project(
        project_dir,
        project_name,
        pixels_per_sample=int(ctx.config["candidate"]["img_size"]) ** 2,
        raw_samples=raw_samples,
        raw_csim_samples=int(cfg["raw_csim_samples"]),
    )

    hls_logits = np.asarray(hls_model.predict(np.ascontiguousarray(x))).reshape(-1)
    smoke = write_compile_smoke(output_dir, keras_logits, hls_logits, labels, float(cfg["tolerance"]))
    if not smoke["passed"]:
        print(f"[warn] CoyoteAccelerator compile smoke did not pass; continuing with bitstream build: {smoke}")

    build_manifest = {
        "stage": "converted",
        "backend": "CoyoteAccelerator",
        "io_type": "io_stream",
        "project_name": project_name,
        "output_dir": str(output_dir),
        "project_dir": str(project_dir),
        "run_root": str(ctx.run_root),
        "hls_sweep_root": str(ctx.hls_sweep_root),
        "prepared_inputs": raw_rows,
        "raw_input_mode": True,
        "raw_input_abi": "64-byte header beat with little-endian uint64 raw_len, followed by raw bytes",
        "compile_smoke": smoke,
        "generated_patches": patches,
    }
    write_json(output_dir / "build_manifest.json", build_manifest)

    hls_model.build(
        device=str(cfg["device"]),
        csim=True,
        synth=True,
        cosim=False,
        validation=False,
        timing_opt=True,
        bitfile=bool(cfg["bitfile"]),
        hls_clock_period=float(cfg["hls_clock_period"]),
        hls_clock_uncertainty=float(cfg["hls_clock_uncertainty"]),
    )

    outputs = coyote_build_outputs(project_dir, project_name)
    host_lib = Path(outputs["host_library"])
    missing = []
    if not host_lib.exists():
        missing.append(str(host_lib))
    if bool(cfg["bitfile"]) and not any(Path(path).exists() for path in outputs["bitstream_candidates"]):
        missing.append(str(project_dir / "build" / f"{project_name}_cyt_hw" / "bitstreams" / "cyt_top.bit"))
    if missing:
        raise RuntimeError("missing expected CoyoteAccelerator build artifacts: " + ", ".join(missing))

    manifest = {
        "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "stage_fingerprint": stage_fingerprint,
        "stage": "built",
        "backend": "CoyoteAccelerator",
        "io_type": "io_stream",
        "raw_input_mode": True,
        "raw_input_abi": "64-byte header beat with little-endian uint64 raw_len, followed by raw bytes",
        "project_name": project_name,
        "output_dir": str(output_dir),
        "project_dir": str(project_dir),
        "build_manifest": str(output_dir / "build_manifest.json"),
        "compile_smoke": smoke,
        "source_tree_hash": sha256_tree(project_dir / "src"),
        **outputs,
    }
    build_manifest.update({"stage": "built", **outputs})
    write_json(output_dir / "build_manifest.json", build_manifest)
    write_json(manifest_path, manifest)
    write_run_index(ctx)
