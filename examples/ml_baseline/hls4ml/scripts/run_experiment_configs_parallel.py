#!/usr/bin/env python3
"""Run generated hls4ml configs in parallel and write suite status rows."""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline.experiment_cli import reexec_local_python_if_needed


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
    parser.add_argument("--configs", type=Path, required=True, help="Generated config directory")
    parser.add_argument("--phases", default="1,2,3")
    parser.add_argument("--stages", default="train,hls")
    parser.add_argument("--results-dir", type=Path, required=True)
    parser.add_argument("--log-dir", type=Path, default=Path("logs/experiment_parallel"))
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument(
        "--hls-timeout",
        default=None,
        help="Kill and mark a run failed if HLS compile exceeds this duration, e.g. 10h, 90m, 3600s.",
    )
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--force-fingerprint", action="store_true")
    return parser.parse_args()


def now() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")


def parse_duration_seconds(value: str | None) -> float | None:
    if value is None or str(value).strip() == "":
        return None
    text = str(value).strip().lower()
    multiplier = 1.0
    if text.endswith("h"):
        multiplier = 3600.0
        text = text[:-1]
    elif text.endswith("m"):
        multiplier = 60.0
        text = text[:-1]
    elif text.endswith("s"):
        text = text[:-1]
    return float(text) * multiplier


def status_key(row: dict[str, Any]) -> tuple[str, str]:
    return (str(row.get("experiment_name", "")), str(row.get("requested_stages", "")))


def load_prior(path: Path) -> list[dict[str, str]]:
    from pipeline.experiment_suite import read_csv

    return read_csv(path)


def write_status(path: Path, rows: list[dict[str, Any]]) -> None:
    from pipeline.experiment_suite import write_csv

    write_csv(path, rows, fieldnames=STATUS_FIELDS)


def current_status_row(path: Path, key: tuple[str, str]) -> dict[str, str] | None:
    for row in load_prior(path):
        if status_key(row) == key:
            return row
    return None


def context_roots(config_path: Path) -> tuple[str, str]:
    from pipeline.notebook_flow import build_context, load_config

    config = load_config(config_path)
    selected_run_root = config.get("experiment", {}).get("selected_run_root")
    ctx = build_context(
        config,
        config_path=config_path.resolve(),
        run_root_arg=Path(selected_run_root) if selected_run_root else None,
    )
    return str(ctx.run_root), str(ctx.hls_sweep_root)


def base_row(config_path: Path, config: dict[str, Any], stages: list[str]) -> dict[str, Any]:
    from pipeline.experiment_suite import metadata_for_config

    meta = metadata_for_config(config, config_path)
    run_root, hls_sweep_root = "", ""
    try:
        run_root, hls_sweep_root = context_roots(config_path)
    except Exception:
        pass
    return {
        "experiment_name": meta["experiment_name"],
        "phase": meta["phase"],
        "tier": meta["tier"],
        "status": "",
        "requested_stages": ",".join(stages),
        "completed_stages": "",
        "failure_stage": "",
        "failure_reason": "",
        "run_root": run_root,
        "hls_sweep_root": hls_sweep_root,
        "config_path": str(config_path),
        "started_at": "",
        "finished_at": "",
    }


def launch(config_path: Path, row: dict[str, Any], stages: list[str], args: argparse.Namespace, log_path: Path):
    cmd = [
        sys.executable,
        str(SCRIPT_DIR / "hls4ml_run.py"),
        "--config",
        str(config_path),
        "--stages",
        ",".join(stages),
    ]
    if args.force:
        cmd.append("--force")
    if args.force_fingerprint:
        cmd.append("--force-fingerprint")
    log_path.parent.mkdir(parents=True, exist_ok=True)
    handle = log_path.open("w")
    handle.write("$ " + " ".join(cmd) + "\n")
    handle.flush()
    proc = subprocess.Popen(
        cmd,
        cwd=str(EXAMPLE_ROOT),
        stdout=handle,
        stderr=subprocess.STDOUT,
        text=True,
        preexec_fn=os.setsid,
    )
    row["started_at"] = now()
    row["status"] = "running"
    return {"proc": proc, "handle": handle, "row": row, "log_path": log_path, "hls_started_at": None}


def log_has_hls_compile(log_path: Path) -> bool:
    try:
        with log_path.open(errors="ignore") as handle:
            return any("$ vitis_hls -f build_prj.tcl" in line for line in handle)
    except FileNotFoundError:
        return False


def terminate_process_group(proc: subprocess.Popen, grace_seconds: float = 20.0) -> None:
    try:
        pgid = os.getpgid(proc.pid)
    except ProcessLookupError:
        return
    try:
        os.killpg(pgid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + grace_seconds
    while time.time() < deadline:
        if proc.poll() is not None:
            return
        time.sleep(0.5)
    try:
        os.killpg(pgid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def mark_timeout(row: dict[str, Any], stages: list[str], timeout_label: str, log_path: Path) -> None:
    row["status"] = "failed"
    row["completed_stages"] = "train" if "train" in stages else ""
    row["failure_stage"] = "hls"
    row["failure_reason"] = f"timeout after {timeout_label} HLS compile; log={log_path}"
    row["finished_at"] = now()


def is_external_timeout(row: dict[str, str] | None) -> bool:
    if not row:
        return False
    return (
        row.get("status") == "failed"
        and row.get("failure_stage") == "hls"
        and "timeout" in row.get("failure_reason", "").lower()
    )


def main() -> None:
    args = parse_args()
    reexec_local_python_if_needed(EXAMPLE_ROOT)

    from pipeline.experiment_suite import load_generated_configs

    stages = [stage.strip() for stage in args.stages.split(",") if stage.strip()]
    phases = [phase.strip() for phase in args.phases.split(",") if phase.strip()]
    hls_timeout_seconds = parse_duration_seconds(args.hls_timeout)
    hls_timeout_label = args.hls_timeout or ""
    status_path = args.results_dir / "suite_status.csv"
    args.results_dir.mkdir(parents=True, exist_ok=True)
    prior_rows = load_prior(status_path)
    prior_by_key = {status_key(row): row for row in prior_rows}
    rows: list[dict[str, Any]] = list(prior_rows)
    configs = load_generated_configs(args.configs, phases)
    pending: list[tuple[Path, dict[str, Any], dict[str, Any]]] = []
    for config_path, config in configs:
        row = base_row(config_path, config, stages)
        key = status_key(row)
        prior = prior_by_key.get(key)
        if prior and prior.get("status") in {"success", "skipped_red"} and not args.force:
            print(f"[parallel] cached {row['experiment_name']} ({prior['status']})")
            continue
        rows = [existing for existing in rows if status_key(existing) != key]
        if row["tier"] == "red":
            row.update(
                {
                    "status": "skipped_red",
                    "failure_stage": "precheck",
                    "failure_reason": "final_avg_pool > 32x32",
                    "started_at": now(),
                    "finished_at": now(),
                }
            )
            rows.append(row)
            write_status(status_path, rows)
            print(f"[parallel] skipped red {row['experiment_name']}")
            continue
        pending.append((config_path, config, row))

    active: list[dict[str, Any]] = []
    while pending or active:
        while pending and len(active) < max(1, int(args.jobs)):
            config_path, _, row = pending.pop(0)
            log_path = args.log_dir / f"{row['experiment_name']}.log"
            print(f"[parallel] start {row['experiment_name']} log={log_path}")
            active.append(launch(config_path, row, stages, args, log_path))
            rows.append(row)
            write_status(status_path, rows)
        time.sleep(15)
        still_active = []
        for item in active:
            if hls_timeout_seconds is not None and item["hls_started_at"] is None and log_has_hls_compile(item["log_path"]):
                item["hls_started_at"] = time.time()
                print(f"[parallel] hls compile started {item['row']['experiment_name']}")
            if (
                hls_timeout_seconds is not None
                and item["hls_started_at"] is not None
                and item["proc"].poll() is None
                and time.time() - float(item["hls_started_at"]) > hls_timeout_seconds
            ):
                row = item["row"]
                print(f"[parallel] hls timeout {row['experiment_name']} after {hls_timeout_label}")
                terminate_process_group(item["proc"])
                item["handle"].close()
                mark_timeout(row, stages, hls_timeout_label, item["log_path"])
                rows = [existing for existing in rows if status_key(existing) != status_key(row)]
                rows.append(row)
                write_status(status_path, rows)
                continue
            rc = item["proc"].poll()
            if rc is None:
                still_active.append(item)
                continue
            item["handle"].close()
            row = item["row"]
            row["finished_at"] = now()
            if rc == 0:
                row["status"] = "success"
                row["completed_stages"] = ",".join(stages)
                print(f"[parallel] success {row['experiment_name']}")
            else:
                external = current_status_row(status_path, status_key(row))
                if is_external_timeout(external):
                    row.update(external)
                    print(f"[parallel] timeout recorded externally {row['experiment_name']}")
                else:
                    row["status"] = "failed"
                    row["failure_stage"] = stages[0] if stages else "suite"
                    row["failure_reason"] = f"exit_code={rc}; log={item['log_path']}"
                    print(f"[parallel] failed {row['experiment_name']} rc={rc} log={item['log_path']}")
            rows = [existing for existing in rows if status_key(existing) != status_key(row)]
            rows.append(row)
            write_status(status_path, rows)
        active = still_active
    print(f"[parallel] status={status_path}")


if __name__ == "__main__":
    main()
