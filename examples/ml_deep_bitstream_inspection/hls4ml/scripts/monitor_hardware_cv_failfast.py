#!/usr/bin/env python3
"""Fail-fast ntfy monitor for hardware k-fold CV logs."""

from __future__ import annotations

import argparse
import os
import subprocess
import time
import urllib.request
from pathlib import Path


FAIL_PATTERNS = (
    "hardware k-fold CV failed",
    "build failed",
    "deploy failed",
    "validate failed",
    "Traceback",
    "RuntimeError",
    "CMake Error",
    "Vivado not found",
    "No rule to make target",
    "ERROR: [",
    "Segmentation fault",
    "Killed",
    "missing expected CoyoteAccelerator build artifacts",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", required=True, help="hardware_kfold_cv output name, e.g. paper_hwcv_...")
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="hls4ml example root")
    parser.add_argument("--poll-seconds", type=float, default=30.0)
    parser.add_argument("--topic", default="coyote-build-sdeheredia")
    parser.add_argument("--main-session", default=None, help="Optional tmux session to watch for normal exit")
    parser.add_argument("--extra-log", type=Path, action="append", default=[], help="Additional top-level log to scan")
    parser.add_argument("--no-default-log", action="store_true", help="Do not scan hardware_kfold_cv_<run>.log")
    parser.add_argument("--ignore-existing", action="store_true", help="Only scan bytes appended after monitor startup")
    return parser.parse_args()


def log_files(root: Path, run: str, extra_logs: list[Path], include_default_log: bool = True) -> list[Path]:
    files = [root / f"hardware_kfold_cv_{run}.log"] if include_default_log else []
    files.extend(extra_logs)
    artifacts = root / "artifacts_big_ro"
    if artifacts.exists():
        for dirpath, dirnames, filenames in os.walk(artifacts, onerror=lambda _err: None):
            path = Path(dirpath)
            if f"hardware_kfold_cv/{run}/logs" not in path.as_posix():
                continue
            for name in filenames:
                if name.endswith(".log"):
                    files.append(path / name)
    return [path for path in files if path.exists()]


def initial_offsets(files: list[Path]) -> dict[Path, int]:
    offsets: dict[Path, int] = {}
    for path in files:
        try:
            offsets[path.resolve()] = path.stat().st_size
        except OSError:
            continue
    return offsets


def find_failure(files: list[Path], offsets: dict[Path, int] | None = None) -> tuple[Path, int, str] | None:
    for path in files:
        try:
            resolved = path.resolve()
            start = offsets.get(resolved, 0) if offsets else 0
            text = path.read_text(errors="ignore")
            if start > len(text):
                start = 0
            if start:
                text = text[start:]
            lines = text.splitlines()
        except OSError:
            continue
        for lineno, line in enumerate(lines, start=1):
            if any(pattern in line for pattern in FAIL_PATTERNS):
                return path, lineno, line.strip()
    return None


def tmux_session_exists(name: str) -> bool:
    result = subprocess.run(["tmux", "has-session", "-t", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return result.returncode == 0


def notify(topic: str, message: str) -> None:
    data = message.encode("utf-8")
    req = urllib.request.Request(f"https://ntfy.sh/{topic}", data=data, method="POST")
    with urllib.request.urlopen(req, timeout=10) as response:
        response.read()


def main() -> None:
    args = parse_args()
    root = args.root.resolve()
    marker = Path("/tmp") / f"{args.run}_hardware_cv_failfast_notified"
    marker.unlink(missing_ok=True)
    include_default_log = not bool(args.no_default_log)
    offsets = initial_offsets(log_files(root, args.run, args.extra_log, include_default_log)) if args.ignore_existing else None
    print(f"[failfast] monitoring run={args.run} root={root}", flush=True)
    while True:
        failure = find_failure(log_files(root, args.run, args.extra_log, include_default_log), offsets=offsets)
        if failure is not None:
            path, lineno, line = failure
            rel = path.relative_to(root) if path.is_relative_to(root) else path
            message = f"hardware k-fold CV fail-fast alert: output={args.run}; first match {rel}:{lineno}: {line[:180]}"
            if not marker.exists():
                notify(args.topic, message)
                marker.write_text(message + "\n")
            print("[failfast] notified failure", flush=True)
            print(message, flush=True)
            return
        if args.main_session and not tmux_session_exists(args.main_session):
            print("[failfast] main session ended without failure signature", flush=True)
            return
        time.sleep(args.poll_seconds)


if __name__ == "__main__":
    main()
