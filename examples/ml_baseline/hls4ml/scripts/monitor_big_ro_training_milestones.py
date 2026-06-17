#!/usr/bin/env python3
"""Notify when big-RO balanced training reaches completion milestones."""

from __future__ import annotations

import argparse
import csv
import subprocess
import time
from pathlib import Path


TERMINAL_STATUSES = {"success", "failed", "skipped_red"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--status", type=Path, required=True, help="suite_status.csv to monitor")
    parser.add_argument("--topic", default="coyote-build-sdeheredia", help="ntfy.sh topic")
    parser.add_argument("--interval", type=float, default=60.0, help="Polling interval in seconds")
    parser.add_argument("--milestones", type=int, nargs="+", default=[1, 3], help="Finished-run milestones")
    return parser.parse_args()


def terminal_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    return [row for row in rows if row.get("status") in TERMINAL_STATUSES]


def notify(topic: str, message: str) -> None:
    subprocess.run(["curl", "-s", "-d", message, f"ntfy.sh/{topic}"], check=False, stdout=subprocess.DEVNULL)


def summary(rows: list[dict[str, str]]) -> str:
    return ", ".join(f"{row.get('experiment_name', '')}={row.get('status', '')}" for row in rows)


def main() -> None:
    args = parse_args()
    pending = sorted(set(args.milestones))
    while pending:
        rows = terminal_rows(args.status)
        count = len(rows)
        while pending and count >= pending[0]:
            milestone = pending.pop(0)
            label = "first run" if milestone == 1 else f"first {milestone} runs"
            message = f"big-RO balanced training: {label} finished ({summary(rows)})"
            notify(args.topic, message)
            print(message, flush=True)
        if pending:
            time.sleep(max(1.0, float(args.interval)))


if __name__ == "__main__":
    main()
