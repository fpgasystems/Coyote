#!/usr/bin/env python3
"""Build, deploy, validate, and pool hardware k-fold CV for trained runs."""

from __future__ import annotations

import argparse
import contextlib
import csv
import json
import os
import shutil
import subprocess
import sys
import time
import traceback
from concurrent.futures import ProcessPoolExecutor, as_completed
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))


def configure_coyote_hls4ml_source() -> None:
    """Prefer the patched hls4ml tree that contains CoyoteAccelerator."""
    raw = os.environ.get("HLS4ML_COYOTE_SOURCE_ROOT", "/pub/scratch/sdeheredia/hls4ml")
    root = Path(raw).expanduser()
    if not (root / "hls4ml" / "backends" / "coyote_accelerator").exists():
        return
    root_str = str(root)
    if root_str not in sys.path:
        sys.path.insert(0, root_str)
    parts = [part for part in os.environ.get("PYTHONPATH", "").split(os.pathsep) if part]
    if root_str not in parts:
        os.environ["PYTHONPATH"] = os.pathsep.join([root_str, *parts])


configure_coyote_hls4ml_source()


def _toolchain_version_sort_key(value: str) -> list[int | str]:
    import re

    return [int(part) if part.isdigit() else part for part in re.split(r"([0-9]+)", value)]


def discover_xilinx_toolchain_version(requested: str = "latest") -> str | None:
    roots = [Path("/tools/Xilinx/Vivado"), Path("/tools/Xilinx/Vitis"), Path("/tools/Xilinx/Vitis_HLS")]
    version_sets: list[set[str]] = []
    for root in roots:
        if root.exists():
            version_sets.append({path.name for path in root.iterdir() if path.is_dir()})
    if not version_sets:
        return None
    common = set.intersection(*version_sets)
    if requested != "latest":
        return requested if requested in common else None
    return sorted(common, key=_toolchain_version_sort_key)[-1] if common else None


def reexec_with_xilinx_settings_if_needed(argv: list[str]) -> None:
    if os.environ.get("XILINX_VIVADO") and shutil.which("vivado") and shutil.which("vitis_hls"):
        return
    version = os.environ.get("HLS4ML_XILINX_VERSION") or discover_xilinx_toolchain_version()
    if not version:
        return
    settings = [
        Path(f"/tools/Xilinx/Vivado/{version}/settings64.sh"),
        Path(f"/tools/Xilinx/Vitis/{version}/settings64.sh"),
        Path(f"/tools/Xilinx/Vitis_HLS/{version}/settings64.sh"),
    ]
    if not all(path.exists() for path in settings):
        return
    import shlex

    python = shlex.quote(sys.executable)
    quoted_argv = " ".join(shlex.quote(arg) for arg in argv)
    prologue = "\n".join(
        [
            "set -euo pipefail",
            "export TERM=${TERM:-xterm}",
            "export HLS4ML_RUN_TOOLCHAIN_ENABLED=1",
            *(f"source {shlex.quote(str(path))}" for path in settings),
            f"exec {python} {quoted_argv}",
        ]
    )
    print(f"[toolchain] re-execing with Xilinx settings64.sh {version}", flush=True)
    os.execv("/bin/bash", ["bash", "-lc", prologue])


def reexec_local_python_if_needed() -> None:
    if os.environ.get("HLS4ML_RUN_NO_VENV") == "1" or os.environ.get("HLS4ML_HARDWARE_CV_REEXEC") == "1":
        return
    candidates = [
        EXAMPLE_ROOT.parent / ".venv_hls4ml" / "bin" / "python",
        EXAMPLE_ROOT.parent / ".venv" / "bin" / "python",
        EXAMPLE_ROOT / ".venv_hls4ml" / "bin" / "python",
        EXAMPLE_ROOT / ".venv" / "bin" / "python",
    ]
    current = Path(sys.executable)
    for candidate in candidates:
        if candidate.exists() and os.access(candidate, os.X_OK) and candidate != current:
            os.environ["HLS4ML_HARDWARE_CV_REEXEC"] = "1"
            os.execv(str(candidate), [str(candidate), *sys.argv])


reexec_local_python_if_needed()

import numpy as np

from pipeline.coyote_accelerator.project import (  # noqa: E402
    convert_coyote_model,
    patch_generated_project,
    template_hashes,
    write_compile_smoke,
)
from pipeline.coyote_accelerator.raw_data import (  # noqa: E402
    load_raw_arrays,
    raw_reference_nhwc,
    write_coyote_prepared_inputs,
)
from pipeline.part1_common import (  # noqa: E402
    FlowContext,
    build_context,
    clean_rows,
    deep_merge,
    metrics_from_stage_rows,
    parity_dir_for_fold,
    read_json,
    rows_from_logits,
    sha256_payload,
    write_csv,
    write_json,
    write_metrics_summary,
)
from pipeline.part2_train import current_validation_samples, get_splits, load_current_model  # noqa: E402
from pipeline.part4_bitstream import coyote_accelerator_config, coyote_build_outputs, coyote_output_dir  # noqa: E402
from pipeline.part5_deploy import _existing_paths, _load_overlay, _predict_raw_batches, _timing_guard  # noqa: E402
from pipeline.qkeras_plots import write_per_sample_diagnostic_plots  # noqa: E402
from pipeline.notebook_flow import load_config, maybe_reexec_with_toolchain  # noqa: E402
from train import save_checkpoint_plots  # noqa: E402


NTFY_TOPIC = "coyote-build-sdeheredia"
STAGE_VERSION = "2026-05-27-hardware-kfold-cv"


@dataclass(frozen=True)
class RunSpec:
    run_root: str
    config_path: str
    hls_sweep_root: str
    output_root: str
    log_root: str
    original_training_fingerprint: str
    original_hls_fingerprint: str
    hls_override_config_path: str
    hls_override_fingerprint: str


@dataclass(frozen=True)
class FoldJob:
    run: RunSpec
    fold: int
    force_build: bool = False
    force_deploy: bool = False
    program_fpga: bool = True
    allow_timing_violating_deploy: bool = False


def now() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")


def notify(message: str) -> None:
    subprocess.run(["curl", "-s", "-d", message, f"ntfy.sh/{NTFY_TOPIC}"], check=False)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def write_status(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames: list[str] = []
    for row in rows:
        for key in row:
            if key not in fieldnames:
                fieldnames.append(key)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def find_single_hls_sweep(run_root: Path) -> Path:
    sweeps = sorted((run_root / "hls_sweeps").glob("*/hls_sweep_manifest.json"))
    if not sweeps:
        raise FileNotFoundError(f"no hls_sweeps/*/hls_sweep_manifest.json under {run_root}")
    if len(sweeps) > 1:
        names = ", ".join(str(path.parent) for path in sweeps)
        raise RuntimeError(f"expected one HLS sweep under {run_root}, found {len(sweeps)}: {names}")
    return sweeps[0].parent


def load_hls_override_metadata(path: Path | None) -> tuple[str, str]:
    if path is None:
        return "", ""
    path = path.resolve()
    config = load_config(path)
    payload = {
        "path": str(path),
        "hls": config.get("hls", {}),
        "synthesis": config.get("synthesis", {}),
    }
    return str(path), sha256_payload(payload)


def apply_hls_override(config: dict[str, Any], override_config_path: str) -> dict[str, Any]:
    if not override_config_path:
        return config
    override = load_config(Path(override_config_path))
    config["hls"] = deep_merge(config.get("hls", {}), override.get("hls", {}))
    config["synthesis"] = deep_merge(config.get("synthesis", {}), override.get("synthesis", {}))
    return config


def load_run_spec(run_root: Path, output_name: str, hls_override_config: Path | None = None) -> RunSpec:
    run_root = run_root.resolve()
    iteration = read_json(run_root / "iteration_manifest.json")
    config_path = Path(iteration["config_path"]).resolve()
    hls_sweep_root = find_single_hls_sweep(run_root)
    hls_manifest = read_json(hls_sweep_root / "hls_sweep_manifest.json")
    output_root = run_root / "hardware_kfold_cv" / output_name
    hls_override_config_path, hls_override_fingerprint = load_hls_override_metadata(hls_override_config)
    return RunSpec(
        run_root=str(run_root),
        config_path=str(config_path),
        hls_sweep_root=str(hls_sweep_root),
        output_root=str(output_root),
        log_root=str(output_root / "logs"),
        original_training_fingerprint=str(iteration.get("training_fingerprint", "")),
        original_hls_fingerprint=str(hls_manifest.get("hls_fingerprint", "")),
        hls_override_config_path=hls_override_config_path,
        hls_override_fingerprint=hls_override_fingerprint,
    )


def load_fold_config(
    spec: RunSpec,
    fold: int,
    program_fpga: bool = True,
    allow_timing_violating_deploy: bool = False,
) -> dict[str, Any]:
    config = load_config(Path(spec.config_path))
    hls_manifest = read_json(Path(spec.hls_sweep_root) / "hls_sweep_manifest.json")
    config["hls"] = deep_merge(config.get("hls", {}), hls_manifest.get("hls_config", {}))
    config["synthesis"] = deep_merge(config.get("synthesis", {}), hls_manifest.get("synthesis_config", {}))
    config = apply_hls_override(config, spec.hls_override_config_path)
    config.setdefault("candidate", {})["primary_fold"] = int(fold)
    config.setdefault("run", {})["mode"] = "standard"
    config.setdefault("u55c", {}).setdefault("coyote_accelerator", {})["program_fpga"] = bool(program_fpga)
    if allow_timing_violating_deploy:
        config.setdefault("u55c", {})["allow_timing_violating_deploy"] = True
    return config


def build_fold_context(
    spec: RunSpec,
    fold: int,
    program_fpga: bool = True,
    allow_timing_violating_deploy: bool = False,
) -> FlowContext:
    config = load_fold_config(
        spec,
        fold,
        program_fpga=program_fpga,
        allow_timing_violating_deploy=allow_timing_violating_deploy,
    )
    return build_context(
        config,
        config_path=Path(spec.config_path),
        run_root_arg=Path(spec.run_root),
        hls_sweep_root_arg=Path(spec.output_root),
    )


def fold_label(fold: int) -> str:
    return f"fold_{int(fold)}"


def log_path_for(job: FoldJob, stage: str) -> Path:
    return Path(job.run.log_root) / Path(job.run.run_root).name / f"{fold_label(job.fold)}.{stage}.log"


def build_bitstream_for_fold(job: FoldJob) -> dict[str, Any]:
    log_path = log_path_for(job, "build")
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("w") as log, contextlib.redirect_stdout(log), contextlib.redirect_stderr(log):
        print(f"[hardware-cv] build start run={job.run.run_root} fold={job.fold} at {now()}", flush=True)
        ctx = build_fold_context(job.run, job.fold, program_fpga=job.program_fpga)
        splits = get_splits(ctx)
        val_samples, _n_train, eval_split = current_validation_samples(ctx, splits)
        prepared_manifest = write_coyote_prepared_inputs(ctx, val_samples, force=job.force_build)

        cfg = coyote_accelerator_config(ctx)
        project_name = str(cfg["project_name"])
        output_dir = coyote_output_dir(ctx)
        project_dir = output_dir / "project"
        manifest_path = ctx.u55c_root / "bitstream_manifest.json"
        stage_fingerprint = {
            "stage_version": STAGE_VERSION,
            "original_training_fingerprint": job.run.original_training_fingerprint,
            "original_hls_fingerprint": job.run.original_hls_fingerprint,
            "training_fingerprint": ctx.training_fingerprint,
            "hls_fingerprint": ctx.hls_fingerprint,
            "fold": int(job.fold),
            "coyote_accelerator_config": cfg,
            "prepared_manifest": prepared_manifest,
            "eval_split": eval_split,
            "template_hashes": template_hashes(),
            "source_hashes": ctx.source_hashes,
        }
        if not job.force_build and manifest_path.exists():
            old = read_json(manifest_path)
            outputs = coyote_build_outputs(Path(old.get("project_dir", project_dir)), str(old.get("project_name", project_name)))
            host_lib = Path(outputs["host_library"])
            bitstreams = [Path(path) for path in outputs["bitstream_candidates"] if Path(path).exists()]
            if old.get("stage_fingerprint") == stage_fingerprint and host_lib.exists() and (bitstreams or not bool(cfg["bitfile"])):
                print(f"[hardware-cv] bitstream cache hit fold={job.fold}", flush=True)
                old.update(outputs)
                write_json(manifest_path, old)
                return {
                    "run_root": job.run.run_root,
                    "fold": job.fold,
                    "stage": "build",
                    "status": "cached",
                    "log": str(log_path),
                    "manifest": str(manifest_path),
                    "finished_at": now(),
                }

        if output_dir.exists():
            if not job.force_build:
                raise FileExistsError(f"{output_dir} exists but cache is stale; rerun with --force-build or choose a new --output-name")
            shutil.rmtree(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        model = load_current_model(ctx)
        x = np.load(ctx.prepared_inputs_dir / "x_norm.npy").astype(np.float32)
        labels = np.load(ctx.prepared_inputs_dir / "labels.npy").astype(np.int32)
        keras_logits = np.asarray(model.predict(x, verbose=0)).reshape(-1)
        hls_model, _hls_config = convert_coyote_model(ctx, model, x, keras_logits, output_dir, project_name)
        hls_model.compile()

        raw_rows = read_json(ctx.prepared_inputs_dir / "manifest.json")
        raw_samples = read_csv(ctx.prepared_inputs_dir / "manifest.csv")
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
            print(f"[warn] CoyoteAccelerator compile smoke did not pass; continuing: {smoke}", flush=True)

        parity_dir = parity_dir_for_fold(ctx, job.fold)
        write_csv(parity_dir / "qkeras_per_sample.csv", rows_from_logits(val_samples, labels, keras_logits))
        write_csv(parity_dir / "hls_per_sample.csv", rows_from_logits(val_samples, labels, hls_logits))
        write_json(
            parity_dir / "summary.json",
            {
                "created_at": now(),
                "fold": int(job.fold),
                "eval_split": eval_split,
                "n": int(len(labels)),
                "compile_smoke": smoke,
            },
        )

        build_manifest = {
            "stage": "converted",
            "backend": "CoyoteAccelerator",
            "io_type": "io_stream",
            "project_name": project_name,
            "output_dir": str(output_dir),
            "project_dir": str(project_dir),
            "run_root": str(ctx.run_root),
            "hardware_cv_root": str(ctx.hls_sweep_root),
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
            "created_at": now(),
            "stage_fingerprint": stage_fingerprint,
            "stage": "built",
            "backend": "CoyoteAccelerator",
            "io_type": "io_stream",
            "raw_input_mode": True,
            "raw_input_abi": "64-byte header beat with little-endian uint64 raw_len, followed by raw bytes",
            "fold": int(job.fold),
            "eval_split": eval_split,
            "project_name": project_name,
            "output_dir": str(output_dir),
            "project_dir": str(project_dir),
            "build_manifest": str(output_dir / "build_manifest.json"),
            "compile_smoke": smoke,
            **outputs,
        }
        build_manifest.update({"stage": "built", **outputs})
        write_json(output_dir / "build_manifest.json", build_manifest)
        write_json(manifest_path, manifest)
        print(f"[hardware-cv] build complete fold={job.fold} at {now()}", flush=True)
        return {
            "run_root": job.run.run_root,
            "fold": job.fold,
            "stage": "build",
            "status": "ok",
            "log": str(log_path),
            "manifest": str(manifest_path),
            "finished_at": now(),
        }


def run_build_job(job: FoldJob) -> dict[str, Any]:
    try:
        return build_bitstream_for_fold(job)
    except Exception as exc:
        log_path = log_path_for(job, "build")
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("a") as log:
            log.write("\n[hardware-cv] build failed\n")
            log.write(traceback.format_exc())
        return {
            "run_root": job.run.run_root,
            "fold": job.fold,
            "stage": "build",
            "status": "failed",
            "error": str(exc),
            "log": str(log_path),
            "finished_at": now(),
        }


def deploy_fold(job: FoldJob) -> dict[str, Any]:
    log_path = log_path_for(job, "deploy")
    log_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with log_path.open("w") as log, contextlib.redirect_stdout(log), contextlib.redirect_stderr(log):
            print(f"[hardware-cv] deploy start run={job.run.run_root} fold={job.fold} at {now()}", flush=True)
            ctx = build_fold_context(
                job.run,
                job.fold,
                program_fpga=job.program_fpga,
                allow_timing_violating_deploy=job.allow_timing_violating_deploy,
            )
            bit_manifest_path = ctx.u55c_root / "bitstream_manifest.json"
            if not bit_manifest_path.exists():
                raise FileNotFoundError(f"Run build first: {bit_manifest_path}")
            if not job.force_deploy and (ctx.u55c_root / "deployment_manifest.json").exists():
                print(f"[hardware-cv] deployment cache hit fold={job.fold}", flush=True)
                return {
                    "run_root": job.run.run_root,
                    "fold": job.fold,
                    "stage": "deploy",
                    "status": "cached",
                    "log": str(log_path),
                    "manifest": str(ctx.u55c_root / "deployment_manifest.json"),
                    "finished_at": now(),
                }
            bit_manifest = read_json(bit_manifest_path)
            if bit_manifest.get("backend") != "CoyoteAccelerator" or not bit_manifest.get("raw_input_mode"):
                raise RuntimeError(f"Expected a raw-input CoyoteAccelerator bitstream manifest, got {bit_manifest_path}")
            _timing_guard(ctx, bit_manifest)

            cfg = coyote_accelerator_config(ctx)
            project_name = str(bit_manifest.get("project_name") or cfg["project_name"])
            project_dir = Path(bit_manifest["project_dir"]).resolve()
            host_library = Path(bit_manifest.get("host_library") or project_dir / "build" / f"{project_name}_cyt_sw" / "lib/libCoyoteInference.so")
            bitstreams = _existing_paths(list(bit_manifest.get("bitstream_candidates", [])))
            if not bitstreams:
                raise FileNotFoundError("No bitstream available from bitstream stage")
            if not host_library.exists():
                raise FileNotFoundError(f"Generated CoyoteAccelerator host library is missing: {host_library}")

            prep_rows = clean_rows(ctx.prepared_inputs_dir / "manifest.csv")
            if not prep_rows:
                raise FileNotFoundError(f"Missing prepared raw input manifest: {ctx.prepared_inputs_dir / 'manifest.csv'}")
            raw_arrays = load_raw_arrays(prep_rows)
            labels = np.load(ctx.prepared_inputs_dir / "labels.npy").astype(np.int32).reshape(-1)
            if len(labels) != len(prep_rows):
                raise RuntimeError(f"labels.npy has {len(labels)} labels but manifest has {len(prep_rows)} rows")

            overlay = _load_overlay(project_dir, project_name)
            if bool(cfg.get("program_fpga", True)):
                print("[deploy] programming Coyote FPGA", flush=True)
                overlay.program_hacc_fpga()
            logits, batch_rows = _predict_raw_batches(overlay, raw_arrays, int(cfg["batch_size"]))
            if len(logits) != len(prep_rows):
                raise RuntimeError(f"FPGA returned {len(logits)} logits for {len(prep_rows)} prepared samples")

            batch_latency_by_index = {int(row["batch_index"]): float(row["wall_latency_us"]) for row in batch_rows}
            batch_real_size_by_index = {int(row["batch_index"]): int(row.get("real_batch_size", row["batch_size"])) for row in batch_rows}
            hardware_rows: list[dict[str, Any]] = []
            for idx, (sample, label, logit) in enumerate(zip(prep_rows, labels, logits)):
                batch_index = idx // int(cfg["batch_size"])
                batch_latency = batch_latency_by_index.get(batch_index, 0.0)
                real_batch_size = max(1, batch_real_size_by_index.get(batch_index, int(cfg["batch_size"])))
                hardware_rows.append(
                    {
                        "sample_index": int(sample["sample_index"]),
                        "sample_id": sample.get("sample_id", ""),
                        "app_name": sample.get("app_name", ""),
                        "class_label": int(label),
                        "class_name": sample.get("class_name", "standalone" if int(label) else "benign"),
                        "ro_count": sample.get("ro_count", ""),
                        "bitstream_path": sample.get("bitstream_path", ""),
                        "raw_input_path": sample.get("raw_input_path", ""),
                        "raw_input_bytes": sample.get("raw_input_bytes", ""),
                        "logit": f"{float(logit):.9f}",
                        "batch_index": batch_index,
                        "batch_wall_latency_us": f"{batch_latency:.3f}",
                        "sample_share_wall_latency_us": f"{batch_latency / real_batch_size:.3f}",
                    }
                )

            hardware_csv = ctx.u55c_root / "hardware_per_sample.csv"
            write_csv(hardware_csv, hardware_rows)
            write_csv(ctx.u55c_root / "hardware_batches.csv", batch_rows)
            np.save(ctx.u55c_root / "y_hw.npy", logits.astype(np.float32))

            batch_lat = np.asarray([float(row["wall_latency_us"]) for row in batch_rows], dtype=np.float64)
            total_batch_wall_us = float(batch_lat.sum()) if batch_lat.size else 0.0
            latency_summary = {
                "n_samples": int(len(logits)),
                "batch_size": int(cfg["batch_size"]),
                "n_batches": int(len(batch_rows)),
                "batch_wall_latency_us_mean": float(np.mean(batch_lat)) if batch_lat.size else None,
                "batch_wall_latency_us_median": float(np.median(batch_lat)) if batch_lat.size else None,
                "batch_wall_latency_us_min": float(np.min(batch_lat)) if batch_lat.size else None,
                "batch_wall_latency_us_max": float(np.max(batch_lat)) if batch_lat.size else None,
                "sample_share_wall_latency_us_mean": float(total_batch_wall_us / len(logits)) if len(logits) else None,
                "throughput_samples_per_s": float(len(logits) / (total_batch_wall_us * 1e-6)) if total_batch_wall_us else None,
                "padded_samples": int(sum(int(row.get("padding_samples", 0)) for row in batch_rows)),
                "measurement_scope": "Python RawCoyoteOverlay.predict_raw call wall time per batch.",
            }
            write_json(ctx.u55c_root / "latency_summary.json", latency_summary)
            deployment_manifest = {
                "deployed_at": now(),
                "backend": "CoyoteAccelerator",
                "raw_input_mode": True,
                "programmed_fpga": bool(cfg.get("program_fpga", True)),
                "fold": int(job.fold),
                "project_name": project_name,
                "project_dir": str(project_dir),
                "host_library": str(host_library),
                "bitstream": str(bitstreams[-1]),
                "hardware_per_sample_csv": str(hardware_csv),
                "hardware_batches_csv": str(ctx.u55c_root / "hardware_batches.csv"),
                "y_hw": str(ctx.u55c_root / "y_hw.npy"),
                "latency_summary": latency_summary,
                "bitstream_manifest": str(bit_manifest_path),
            }
            write_json(ctx.u55c_root / "deployment_manifest.json", deployment_manifest)
            print(f"[hardware-cv] deploy complete fold={job.fold} at {now()}", flush=True)
            return {
                "run_root": job.run.run_root,
                "fold": job.fold,
                "stage": "deploy",
                "status": "ok",
                "log": str(log_path),
                "manifest": str(ctx.u55c_root / "deployment_manifest.json"),
                "finished_at": now(),
            }
    except Exception as exc:
        with log_path.open("a") as log:
            log.write("\n[hardware-cv] deploy failed\n")
            log.write(traceback.format_exc())
        return {
            "run_root": job.run.run_root,
            "fold": job.fold,
            "stage": "deploy",
            "status": "failed",
            "error": str(exc),
            "log": str(log_path),
            "finished_at": now(),
        }


def validate_fold(job: FoldJob) -> dict[str, Any]:
    log_path = log_path_for(job, "validate")
    log_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with log_path.open("w") as log, contextlib.redirect_stdout(log), contextlib.redirect_stderr(log):
            print(f"[hardware-cv] validate start run={job.run.run_root} fold={job.fold} at {now()}", flush=True)
            ctx = build_fold_context(job.run, job.fold, program_fpga=job.program_fpga)
            parity_dir = parity_dir_for_fold(ctx, job.fold)
            qkeras_rows = clean_rows(parity_dir / "qkeras_per_sample.csv")
            hls_rows = clean_rows(parity_dir / "hls_per_sample.csv")
            prep_rows = clean_rows(ctx.prepared_inputs_dir / "manifest.csv")
            hw_raw_rows = clean_rows(ctx.u55c_root / "hardware_per_sample.csv")
            if not qkeras_rows or not hls_rows:
                raise FileNotFoundError(f"Missing parity rows in {parity_dir}")
            if not hw_raw_rows:
                raise FileNotFoundError(f"Missing hardware rows: {ctx.u55c_root / 'hardware_per_sample.csv'}")

            x_prepared = np.load(ctx.prepared_inputs_dir / "x_norm.npy").astype(np.float32)
            raw_reference = raw_reference_nhwc(ctx, load_raw_arrays(prep_rows))
            if raw_reference.shape != x_prepared.shape:
                raise RuntimeError(f"raw reference shape {raw_reference.shape} != prepared input shape {x_prepared.shape}")
            raw_reference_max_abs = float(np.max(np.abs(raw_reference - x_prepared))) if x_prepared.size else 0.0
            if raw_reference_max_abs > 1e-7:
                raise RuntimeError(f"raw downsampling reference does not match prepared inputs: max_abs={raw_reference_max_abs}")

            hw_logits_by_idx = {int(row["sample_index"]): float(row["logit"]) for row in hw_raw_rows}
            hw_logits = np.asarray([hw_logits_by_idx[int(row["sample_index"])] for row in prep_rows], dtype=np.float32)
            hw_rows = rows_from_logits(prep_rows, [int(row["class_label"]) for row in prep_rows], hw_logits)
            for row in hw_rows:
                row["fold"] = int(job.fold)
                row["hardware_cv_run"] = Path(job.run.output_root).name
            write_csv(ctx.u55c_root / "hardware_per_sample_enriched.csv", hw_rows)
            np.save(ctx.u55c_root / "y_hw.npy", hw_logits)

            stages = {f"{ctx.training_stage} Keras CPU": qkeras_rows, "Coyote HLS CPU": hls_rows, "U55C hardware": hw_rows}
            summary_keys = [
                "accuracy",
                "balanced_accuracy",
                "precision",
                "recall",
                "f1",
                "roc_auc",
                "pr_auc",
                "bce_loss",
                "log_loss",
                "mcc",
            ]
            summary: dict[str, Any] = {}
            for name, rows in stages.items():
                metrics = metrics_from_stage_rows(rows)
                summary[name] = {key: float(metrics[key]) for key in summary_keys if key in metrics}
                if "confusion_matrix" in metrics:
                    summary[name]["confusion_matrix"] = np.asarray(metrics["confusion_matrix"]).astype(int).tolist()
            ctx.validation_dir.mkdir(parents=True, exist_ok=True)
            write_json(ctx.validation_dir / "comparison_summary.json", summary)

            hw_metrics = metrics_from_stage_rows(hw_rows)
            save_checkpoint_plots(
                str(ctx.validation_dir),
                "final",
                canonical_metrics=hw_metrics,
                split_info=f"Candidate: {ctx.candidate_name} | Fold: {job.fold} | Stage: U55C hardware",
                run_params={
                    "hardware_cv": Path(job.run.output_root).name,
                    "board": "u55c",
                    "abi": "raw bitstream bytes -> FPGA downsampler -> ap_fixed<16,6> hls4ml stream",
                },
            )
            write_json(
                ctx.validation_dir / "validation_manifest.json",
                {
                    "created_at": now(),
                    "fold": int(job.fold),
                    "model_slot": fold_label(job.fold),
                    "hardware_cv_root": job.run.output_root,
                    "comparison_summary": str(ctx.validation_dir / "comparison_summary.json"),
                    "final_evaluation_plots": str(ctx.validation_dir / "final_evaluation_plots.png"),
                    "hardware_per_sample_enriched": str(ctx.u55c_root / "hardware_per_sample_enriched.csv"),
                    "raw_reference_max_abs": raw_reference_max_abs,
                    "raw_reference_shape": list(raw_reference.shape),
                },
            )
            print(f"[hardware-cv] validate complete fold={job.fold} at {now()}", flush=True)
            return {
                "run_root": job.run.run_root,
                "fold": job.fold,
                "stage": "validate",
                "status": "ok",
                "log": str(log_path),
                "manifest": str(ctx.validation_dir / "validation_manifest.json"),
                "finished_at": now(),
            }
    except Exception as exc:
        with log_path.open("a") as log:
            log.write("\n[hardware-cv] validate failed\n")
            log.write(traceback.format_exc())
        return {
            "run_root": job.run.run_root,
            "fold": job.fold,
            "stage": "validate",
            "status": "failed",
            "error": str(exc),
            "log": str(log_path),
            "finished_at": now(),
        }


def pool_run(spec: RunSpec, folds: Iterable[int]) -> dict[str, Any]:
    out_root = Path(spec.output_root)
    pooled_dir = out_root / "pooled"
    rows: list[dict[str, Any]] = []
    fold_summary: list[dict[str, Any]] = []
    for fold in folds:
        ctx = build_fold_context(spec, fold)
        path = ctx.u55c_root / "hardware_per_sample_enriched.csv"
        if not path.exists():
            raise FileNotFoundError(path)
        fold_rows = clean_rows(path)
        for row in fold_rows:
            row["fold"] = int(fold)
            row["source_run_root"] = spec.run_root
            rows.append(row)
        metrics = metrics_from_stage_rows(fold_rows)
        fold_summary.append(
            {
                "fold": int(fold),
                "n": len(fold_rows),
                "accuracy": float(metrics["accuracy"]),
                "balanced_accuracy": float(metrics["balanced_accuracy"]),
                "precision": float(metrics["precision"]),
                "recall": float(metrics["recall"]),
                "f1": float(metrics["f1"]),
                "roc_auc": float(metrics["roc_auc"]),
                "pr_auc": float(metrics["pr_auc"]),
            }
        )
    write_csv(pooled_dir / "hardware_per_sample.csv", rows)
    write_csv(pooled_dir / "fold_summary.csv", fold_summary)
    pooled_metrics = metrics_from_stage_rows(rows)
    write_metrics_summary(
        pooled_dir / "metrics_summary.json",
        pooled_metrics,
        extra={
            "stage": "U55C hardware",
            "source_run_root": spec.run_root,
            "hardware_cv_root": spec.output_root,
            "folds": list(folds),
            "n": len(rows),
        },
    )
    write_per_sample_diagnostic_plots(pooled_dir, rows, title_prefix="Pooled hardware folds")
    write_json(
        pooled_dir / "hardware_cv_manifest.json",
        {
            "created_at": now(),
            "source_run_root": spec.run_root,
            "hardware_cv_root": spec.output_root,
            "folds": list(folds),
            "n": len(rows),
            "hardware_per_sample": str(pooled_dir / "hardware_per_sample.csv"),
            "fold_summary": str(pooled_dir / "fold_summary.csv"),
            "metrics_summary": str(pooled_dir / "metrics_summary.json"),
        },
    )
    return {
        "run_root": spec.run_root,
        "stage": "pool",
        "status": "ok",
        "n": len(rows),
        "manifest": str(pooled_dir / "hardware_cv_manifest.json"),
        "finished_at": now(),
    }


def parse_folds(raw: str | None, k_folds: int) -> list[int]:
    if not raw:
        return list(range(k_folds))
    folds = [int(item) for item in raw.split(",") if item.strip()]
    for fold in folds:
        if fold < 0 or fold >= k_folds:
            raise ValueError(f"fold {fold} outside range [0,{k_folds})")
    return folds


def load_existing_status_rows(spec: RunSpec, rerun_stages: set[str], rerun_folds: list[int]) -> list[dict[str, Any]]:
    status_path = Path(spec.output_root) / "job_status.csv"
    if not status_path.exists():
        return []
    fold_set = {str(fold) for fold in rerun_folds}
    kept: list[dict[str, Any]] = []
    for row in read_csv(status_path):
        stage = str(row.get("stage", ""))
        fold = str(row.get("fold", ""))
        if stage not in rerun_stages:
            kept.append(row)
            continue
        if not fold or fold in fold_set:
            continue
        kept.append(row)
    return kept


def preflight(spec: RunSpec, folds: list[int]) -> dict[str, Any]:
    run_root = Path(spec.run_root)
    missing = []
    for fold in folds:
        for path in (
            run_root / fold_label(fold) / "final_weights.weights.h5",
            run_root / fold_label(fold) / "training_manifest.json",
            run_root / "splits" / f"fold_{fold}_val.csv",
            run_root / "splits" / f"fold_{fold}_train.csv",
        ):
            if not path.exists():
                missing.append(str(path))
    if missing:
        raise FileNotFoundError("missing required inputs:\n" + "\n".join(missing))
    import hls4ml
    from hls4ml.backends import get_available_backends

    backends = {name.lower() for name in get_available_backends()}
    if "coyoteaccelerator" not in backends:
        raise RuntimeError(
            "CoyoteAccelerator backend is not registered. "
            "Set HLS4ML_COYOTE_SOURCE_ROOT to the patched hls4ml tree; "
            f"currently imported hls4ml from {Path(hls4ml.__file__).resolve()}"
        )
    config = load_config(Path(spec.config_path))
    k_folds = int(config["candidate"]["k_folds"])
    return {
        "run_root": spec.run_root,
        "stage": "preflight",
        "status": "ok",
        "k_folds": k_folds,
        "folds": ",".join(str(fold) for fold in folds),
        "output_root": spec.output_root,
        "hls_override_config_path": spec.hls_override_config_path,
        "hls_override_fingerprint": spec.hls_override_fingerprint,
        "hls4ml": str(Path(hls4ml.__file__).resolve()),
        "finished_at": now(),
    }


def run_builds(specs: list[RunSpec], folds_by_run: dict[str, list[int]], workers: int, force_build: bool, program_fpga: bool) -> list[dict[str, Any]]:
    jobs = [
        FoldJob(spec, fold, force_build=force_build, program_fpga=program_fpga)
        for spec in specs
        for fold in folds_by_run[spec.run_root]
    ]
    if not jobs:
        return []
    results: list[dict[str, Any]] = []
    with ProcessPoolExecutor(max_workers=min(workers, len(jobs))) as pool:
        futures = [pool.submit(run_build_job, job) for job in jobs]
        for future in as_completed(futures):
            result = future.result()
            print(f"[hardware-cv] build {result['status']} run={Path(result['run_root']).name} fold={result['fold']} log={result.get('log', '')}", flush=True)
            results.append(result)
    return results


def run_deploy_validate(
    specs: list[RunSpec],
    folds_by_run: dict[str, list[int]],
    force_deploy: bool,
    program_fpga: bool,
    allow_timing_violating_deploy: bool,
) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for spec in specs:
        for fold in folds_by_run[spec.run_root]:
            job = FoldJob(
                spec,
                fold,
                force_deploy=force_deploy,
                program_fpga=program_fpga,
                allow_timing_violating_deploy=allow_timing_violating_deploy,
            )
            deploy_result = deploy_fold(job)
            print(f"[hardware-cv] deploy {deploy_result['status']} run={Path(spec.run_root).name} fold={fold} log={deploy_result.get('log', '')}", flush=True)
            results.append(deploy_result)
            if deploy_result["status"] == "failed":
                continue
            validate_result = validate_fold(job)
            print(f"[hardware-cv] validate {validate_result['status']} run={Path(spec.run_root).name} fold={fold} log={validate_result.get('log', '')}", flush=True)
            results.append(validate_result)
    return results


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-root", type=Path, action="append", required=True, help="Trained run root. Pass once per model.")
    parser.add_argument(
        "--hls-override-config",
        type=Path,
        action="append",
        default=None,
        help=(
            "Config whose hls/synthesis sections override the trained run's original HLS sweep. "
            "Pass once for all run roots, or once per --run-root."
        ),
    )
    parser.add_argument("--folds", default=None, help="Comma-separated folds. Default: all folds from config.")
    parser.add_argument("--output-name", default=None, help="Name under hardware_kfold_cv/. Default: timestamped.")
    parser.add_argument("--build-workers", type=int, default=10, help="Parallel bitstream build workers. Cap this at available licenses/RAM.")
    parser.add_argument(
        "--stages",
        default="preflight,build,deploy,validate,pool",
        help="Comma-separated stages from: preflight,build,deploy,validate,pool",
    )
    parser.add_argument("--force-build", action="store_true", help="Rebuild and replace existing generated hardware-CV build outputs.")
    parser.add_argument("--force-deploy", action="store_true", help="Rerun deployment even when deployment_manifest.json exists.")
    parser.add_argument("--no-program-fpga", action="store_true", help="Run deployment without programming the FPGA.")
    parser.add_argument(
        "--allow-timing-violating-deploy",
        action="store_true",
        help="Allow deployment of timing-violating bitstreams for explicit diagnostics.",
    )
    parser.add_argument("--notify", action="store_true", help=f"Send ntfy notifications to {NTFY_TOPIC}.")
    return parser.parse_args()


def resolve_hls_override_configs(run_roots: list[Path], overrides: list[Path] | None) -> list[Path | None]:
    if not overrides:
        return [None] * len(run_roots)
    if len(overrides) == 1:
        return [overrides[0]] * len(run_roots)
    if len(overrides) != len(run_roots):
        raise ValueError("--hls-override-config must be passed once, or once per --run-root")
    return list(overrides)


def main() -> None:
    args = parse_args()
    output_name = args.output_name or time.strftime("%Y%m%d_%H%M%S")
    stages = [stage.strip() for stage in args.stages.split(",") if stage.strip()]
    allowed = {"preflight", "build", "deploy", "validate", "pool"}
    unknown = set(stages) - allowed
    if unknown:
        raise ValueError(f"unknown stages: {sorted(unknown)}")
    if args.build_workers < 1:
        raise ValueError("--build-workers must be >= 1")

    hls_override_configs = resolve_hls_override_configs(args.run_root, args.hls_override_config)
    specs = [
        load_run_spec(root, output_name, hls_override_config=override_config)
        for root, override_config in zip(args.run_root, hls_override_configs)
    ]
    folds_by_run: dict[str, list[int]] = {}
    status_rows: list[dict[str, Any]] = []
    started = time.time()
    try:
        for spec in specs:
            config = load_config(Path(spec.config_path))
            folds_by_run[spec.run_root] = parse_folds(args.folds, int(config["candidate"]["k_folds"]))
            Path(spec.output_root).mkdir(parents=True, exist_ok=True)
            write_json(Path(spec.output_root) / "run_spec.json", asdict(spec))

        for spec in specs:
            status_rows.extend(load_existing_status_rows(spec, set(stages), folds_by_run[spec.run_root]))

        if "build" in stages and specs:
            first_spec = specs[0]
            first_fold = folds_by_run[first_spec.run_root][0]
            ctx = build_fold_context(first_spec, first_fold, program_fpga=not bool(args.no_program_fpga))
            maybe_reexec_with_toolchain(ctx, {"bitstream"}, sys.argv)
            reexec_with_xilinx_settings_if_needed(sys.argv)

        if args.notify:
            notify(f"hardware k-fold CV started: output={output_name} runs={len(specs)}")

        if "preflight" in stages:
            for spec in specs:
                result = preflight(spec, folds_by_run[spec.run_root])
                status_rows.append(result)
                print(f"[hardware-cv] preflight ok run={Path(spec.run_root).name}", flush=True)

        if "build" in stages:
            status_rows.extend(
                run_builds(
                    specs,
                    folds_by_run,
                    workers=args.build_workers,
                    force_build=bool(args.force_build),
                    program_fpga=not bool(args.no_program_fpga),
                )
            )

        build_failures = [row for row in status_rows if row.get("stage") == "build" and row.get("status") == "failed"]
        if build_failures and "build" in stages:
            raise RuntimeError(f"{len(build_failures)} build jobs failed")

        if "deploy" in stages or "validate" in stages:
            status_rows.extend(
                run_deploy_validate(
                    specs,
                    folds_by_run,
                    force_deploy=bool(args.force_deploy),
                    program_fpga=not bool(args.no_program_fpga),
                    allow_timing_violating_deploy=bool(args.allow_timing_violating_deploy),
                )
            )

        deploy_or_validate_failures = [
            row for row in status_rows if row.get("stage") in {"deploy", "validate"} and row.get("status") == "failed"
        ]
        if deploy_or_validate_failures and "pool" in stages:
            raise RuntimeError(f"{len(deploy_or_validate_failures)} deploy/validate jobs failed; not pooling incomplete hardware CV")

        if "pool" in stages:
            for spec in specs:
                result = pool_run(spec, folds_by_run[spec.run_root])
                status_rows.append(result)
                print(f"[hardware-cv] pool ok run={Path(spec.run_root).name} n={result['n']}", flush=True)

        elapsed_s = time.time() - started
        for spec in specs:
            write_status(Path(spec.output_root) / "job_status.csv", [row for row in status_rows if row.get("run_root") == spec.run_root])
        if args.notify:
            notify(f"hardware k-fold CV finished ok: output={output_name} elapsed_h={elapsed_s/3600:.2f}")
    except Exception as exc:
        for spec in specs:
            write_status(Path(spec.output_root) / "job_status.csv", [row for row in status_rows if row.get("run_root") == spec.run_root])
        if args.notify:
            notify(f"hardware k-fold CV failed: output={output_name} error={exc}")
        raise


if __name__ == "__main__":
    main()
