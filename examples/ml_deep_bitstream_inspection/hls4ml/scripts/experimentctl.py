#!/usr/bin/env python3
"""Operate on running hls4ml experiment-suite jobs."""

from __future__ import annotations

import argparse
import csv
import os
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline.experiment_cli import reexec_local_python_if_needed
from pipeline.experiment_suite import write_csv


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


def parse_duration_seconds(value: str | None) -> float | None:
    if value is None:
        return None
    text = value.strip().lower()
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


def parse_time(value: str) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None


def read_status(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def now() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")


def process_rows() -> list[tuple[int, str]]:
    proc = subprocess.run(["pgrep", "-af", "hls4ml_run.py --config configs/hls4ml_experiment"], text=True, capture_output=True)
    rows = []
    for line in proc.stdout.splitlines():
        parts = line.split(maxsplit=1)
        if len(parts) == 2 and parts[0].isdigit():
            rows.append((int(parts[0]), parts[1]))
    return rows


def child_pids(pid: int) -> list[int]:
    proc = subprocess.run(["pgrep", "-P", str(pid)], text=True, capture_output=True)
    children = [int(line) for line in proc.stdout.splitlines() if line.strip().isdigit()]
    out: list[int] = []
    for child in children:
        out.extend(child_pids(child))
        out.append(child)
    return out


def pid_exists(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def kill_process_tree(pid: int, grace_seconds: float = 20.0) -> None:
    targets = [*child_pids(pid), pid]
    for target in targets:
        try:
            os.kill(target, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + grace_seconds
    while time.time() < deadline:
        if not any(pid_exists(target) for target in targets):
            return
        time.sleep(0.5)
    for target in targets:
        try:
            os.kill(target, signal.SIGKILL)
        except ProcessLookupError:
            pass


def matching_pids(experiment_name: str) -> list[int]:
    needles = [f"{experiment_name}.yaml", experiment_name]
    pids = []
    for pid, cmd in process_rows():
        if any(needle in cmd for needle in needles):
            pids.append(pid)
    return pids


def select_timeout_rows(args: argparse.Namespace, rows: list[dict[str, str]]) -> list[dict[str, str]]:
    names = set(args.name or [])
    older_than = parse_duration_seconds(args.older_than)
    current = datetime.now()
    selected = []
    for row in rows:
        if row.get("status") != "running":
            continue
        if names and row.get("experiment_name") not in names:
            continue
        if args.tier and row.get("tier") != args.tier:
            continue
        if older_than is not None:
            started = parse_time(row.get("started_at", ""))
            if started is None or (current - started).total_seconds() < older_than:
                continue
        selected.append(row)
    return selected


def command_timeout(args: argparse.Namespace) -> int:
    status_path = args.results_dir / "suite_status.csv"
    rows = read_status(status_path)
    selected = select_timeout_rows(args, rows)
    if not selected:
        print("[experimentctl] no matching running experiments")
        return 0
    print("[experimentctl] timeout candidates:")
    for row in selected:
        pids = matching_pids(row["experiment_name"])
        print(f"  {row['experiment_name']} tier={row.get('tier')} started={row.get('started_at')} pids={pids or 'none'}")
    if not args.yes:
        print("[experimentctl] dry run only; rerun with --yes to kill and mark timeouts")
        return 0
    selected_names = {row["experiment_name"] for row in selected}
    for row in selected:
        for pid in matching_pids(row["experiment_name"]):
            print(f"[experimentctl] killing {row['experiment_name']} pid={pid}")
            kill_process_tree(pid)
    for row in rows:
        if row.get("experiment_name") not in selected_names or row.get("status") != "running":
            continue
        row["status"] = "failed"
        row["completed_stages"] = "train" if "train" in row.get("requested_stages", "").split(",") else row.get("completed_stages", "")
        row["failure_stage"] = "hls"
        row["failure_reason"] = args.reason
        row["finished_at"] = now()
    write_csv(status_path, rows, fieldnames=STATUS_FIELDS)
    print(f"[experimentctl] updated {status_path}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    timeout = sub.add_parser("timeout", help="Kill running experiments and mark them as HLS timeout failures")
    timeout.add_argument("--results-dir", type=Path, required=True)
    timeout.add_argument("--name", action="append", default=[], help="Experiment name to time out. May be repeated.")
    timeout.add_argument("--tier", default=None, help="Filter running rows by tier, e.g. yellow")
    timeout.add_argument("--older-than", default=None, help="Only select rows older than this duration, e.g. 10h")
    timeout.add_argument(
        "--reason",
        default="manual HLS timeout",
        help="Failure reason written to suite_status.csv",
    )
    timeout.add_argument("--yes", action="store_true", help="Actually kill and update status; without this, only preview")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    reexec_local_python_if_needed(EXAMPLE_ROOT)
    if args.command == "timeout":
        raise SystemExit(command_timeout(args))
    raise SystemExit(f"unknown command {args.command}")


if __name__ == "__main__":
    main()
