#!/usr/bin/env python3
"""Run generated hls4ml experiment configs with resumable suite-level status."""

from __future__ import annotations

import argparse
import sys
import time
import traceback
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline.experiment_cli import reexec_local_python_if_needed
from pipeline.experiment_suite import load_generated_configs, metadata_for_config, read_csv, write_csv


STATUS_FIELDS = [
    "experiment_name",
    "phase",
    "tier",
    "status",
    "requested_stages",
    "completed_stages",
    "failure_stage",
    "failure_reason",
    "run_root",
    "hls_sweep_root",
    "config_path",
    "started_at",
    "finished_at",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", type=Path, required=True, help="Suite YAML, kept for CLI symmetry and provenance")
    parser.add_argument("--configs", type=Path, required=True, help="Generated config directory")
    parser.add_argument("--phases", default="1,2,3")
    parser.add_argument("--stages", default="train,hls")
    parser.add_argument("--results-dir", type=Path, required=True)
    parser.add_argument("--selected-candidates", type=Path, default=None, help="Reserved for compatibility with generation flow")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--force-fingerprint", action="store_true")
    return parser.parse_args()


def status_key(row: dict[str, Any]) -> tuple[str, str]:
    return (str(row.get("experiment_name", "")), str(row.get("requested_stages", "")))


def existing_statuses(path: Path) -> dict[tuple[str, str], dict[str, str]]:
    return {status_key(row): row for row in read_csv(path)}


def build_context_for_config(config_path: Path, config: dict[str, Any]):
    from pipeline.notebook_flow import build_context, load_config

    loaded = load_config(config_path)
    selected_run_root = loaded.get("experiment", {}).get("selected_run_root")
    run_root_arg = Path(selected_run_root) if selected_run_root else None
    return build_context(loaded, config_path=config_path.resolve(), run_root_arg=run_root_arg)


def run_candidate(
    config_path: Path,
    config: dict[str, Any],
    requested_stages: list[str],
    *,
    force: bool,
    force_fingerprint: bool,
) -> dict[str, Any]:
    from pipeline.notebook_flow import maybe_reexec_with_toolchain, run_stages

    meta = metadata_for_config(config, config_path)
    started_at = time.strftime("%Y-%m-%d %H:%M:%S")
    base = {
        "experiment_name": meta["experiment_name"],
        "phase": meta["phase"],
        "tier": meta["tier"],
        "requested_stages": ",".join(requested_stages),
        "completed_stages": "",
        "failure_stage": "",
        "failure_reason": "",
        "run_root": "",
        "hls_sweep_root": "",
        "config_path": str(config_path),
        "started_at": started_at,
        "finished_at": "",
    }
    if meta["tier"] == "red":
        return {
            **base,
            "status": "skipped_red",
            "failure_stage": "precheck",
            "failure_reason": "final_avg_pool > 32x32",
            "finished_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        }
    ctx = None
    completed: list[str] = []
    try:
        ctx = build_context_for_config(config_path, config)
        base["run_root"] = str(ctx.run_root)
        base["hls_sweep_root"] = str(ctx.hls_sweep_root)
        maybe_reexec_with_toolchain(ctx, set(requested_stages), sys.argv)
        for stage in requested_stages:
            run_stages(ctx, [stage], force=force, force_fingerprint=force_fingerprint)
            completed.append(stage)
        return {
            **base,
            "status": "success",
            "completed_stages": ",".join(completed),
            "finished_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        }
    except Exception as exc:  # noqa: BLE001 - failures are experiment data here.
        failure_stage = requested_stages[len(completed)] if len(completed) < len(requested_stages) else "suite"
        reason = f"{exc.__class__.__name__}: {exc}"
        if ctx is not None:
            base["run_root"] = str(ctx.run_root)
            base["hls_sweep_root"] = str(ctx.hls_sweep_root)
        log_path = Path(base["run_root"] or EXAMPLE_ROOT) / "suite_failure.log"
        try:
            log_path.parent.mkdir(parents=True, exist_ok=True)
            log_path.write_text(traceback.format_exc())
        except Exception:
            pass
        return {
            **base,
            "status": "failed",
            "completed_stages": ",".join(completed),
            "failure_stage": failure_stage,
            "failure_reason": reason,
            "finished_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        }


def main() -> None:
    args = parse_args()
    reexec_local_python_if_needed(EXAMPLE_ROOT)
    _ = args.suite.resolve()
    requested_stages = [stage.strip() for stage in args.stages.split(",") if stage.strip()]
    phases = [phase.strip() for phase in args.phases.split(",") if phase.strip()]
    status_path = args.results_dir / "suite_status.csv"
    prior = existing_statuses(status_path)
    rows = list(prior.values())
    configs = load_generated_configs(args.configs, phases)
    for config_path, config in configs:
        meta = metadata_for_config(config, config_path)
        key = (str(meta["experiment_name"]), ",".join(requested_stages))
        old = prior.get(key)
        if old and old.get("status") in {"success", "skipped_red"} and not args.force:
            print(f"[suite] skip cached {meta['experiment_name']} ({old['status']})")
            continue
        print(f"[suite] run {meta['experiment_name']} tier={meta['tier']} stages={','.join(requested_stages)}")
        row = run_candidate(
            config_path,
            config,
            requested_stages,
            force=args.force,
            force_fingerprint=args.force_fingerprint,
        )
        rows = [existing for existing in rows if status_key(existing) != key]
        rows.append(row)
        write_csv(status_path, rows, fieldnames=STATUS_FIELDS)
    write_csv(status_path, rows, fieldnames=STATUS_FIELDS)
    print(f"[suite] status={status_path}")


if __name__ == "__main__":
    main()
