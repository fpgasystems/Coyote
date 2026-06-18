#!/usr/bin/env python3
"""Retry hardware k-fold CV one fold per process with hard timeouts."""

from __future__ import annotations

import argparse
import csv
import json
import os
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
NTFY_TOPIC = "coyote-build-sdeheredia"


@dataclass(frozen=True)
class FoldAttempt:
    run_root: Path
    fold: int
    wns: float | None
    tns: float | None
    failing_endpoints: int | None


def now() -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S")


def notify(enabled: bool, message: str) -> None:
    if not enabled:
        return
    subprocess.run(["curl", "-s", "-d", message, f"ntfy.sh/{NTFY_TOPIC}"], check=False)


def read_json(path: Path) -> dict[str, Any]:
    with path.open() as handle:
        return json.load(handle)


def parse_folds(raw: str | None) -> set[int] | None:
    if raw is None:
        return None
    folds: set[int] = set()
    for part in raw.split(","):
        part = part.strip()
        if part:
            folds.add(int(part))
    return folds


def timing_for(run_root: Path, output_name: str, fold: int) -> tuple[float | None, float | None, int | None]:
    path = run_root / "hardware_kfold_cv" / output_name / f"fold_{fold}" / "u55c_deployment" / "bitstream_manifest.json"
    if not path.exists():
        return None, None, None
    summary = (read_json(path).get("timing_summary") or {})
    wns = summary.get("wns")
    tns = summary.get("tns")
    failing = summary.get("failing_endpoints")
    return (
        float(wns) if wns is not None else None,
        float(tns) if tns is not None else None,
        int(failing) if failing is not None else None,
    )


def discover_attempts(run_root: Path, output_name: str, folds: set[int] | None) -> list[FoldAttempt]:
    output_root = run_root / "hardware_kfold_cv" / output_name
    if folds is None:
        discovered = []
        for path in output_root.glob("fold_*"):
            if path.is_dir():
                try:
                    discovered.append(int(path.name.split("_", 1)[1]))
                except ValueError:
                    continue
        folds = set(discovered)
    attempts = []
    for fold in sorted(folds):
        wns, tns, failing = timing_for(run_root, output_name, fold)
        attempts.append(FoldAttempt(run_root=run_root, fold=fold, wns=wns, tns=tns, failing_endpoints=failing))
    return attempts


def timing_sort_key(attempt: FoldAttempt) -> tuple[float, float, int, int]:
    # Least-bad timing first: higher WNS/TNS, fewer failing endpoints.
    wns = attempt.wns if attempt.wns is not None else float("-inf")
    tns = attempt.tns if attempt.tns is not None else float("-inf")
    failing = attempt.failing_endpoints if attempt.failing_endpoints is not None else 10**12
    return (wns, tns, -failing, -attempt.fold)


def run_sort_key(attempts: list[FoldAttempt]) -> tuple[float, float, int]:
    if not attempts:
        return (float("-inf"), float("-inf"), -10**12)
    known_wns = [attempt.wns for attempt in attempts if attempt.wns is not None]
    known_tns = [attempt.tns for attempt in attempts if attempt.tns is not None]
    known_failing = [attempt.failing_endpoints for attempt in attempts if attempt.failing_endpoints is not None]
    avg_wns = sum(known_wns) / len(known_wns) if known_wns else float("-inf")
    avg_tns = sum(known_tns) / len(known_tns) if known_tns else float("-inf")
    avg_failing = int(sum(known_failing) / len(known_failing)) if known_failing else 10**12
    return (avg_wns, avg_tns, -avg_failing)


def latest_stage_rows(run_root: Path, output_name: str, fold: int) -> dict[str, str]:
    path = run_root / "hardware_kfold_cv" / output_name / "job_status.csv"
    if not path.exists():
        return {}
    rows_by_stage: dict[str, str] = {}
    with path.open(newline="") as handle:
        for row in csv.DictReader(handle):
            if row.get("fold") != str(fold):
                continue
            stage = row.get("stage", "")
            if stage in {"deploy", "validate"}:
                rows_by_stage[stage] = row.get("status", "")
    return rows_by_stage


def classify_result(run_root: Path, output_name: str, fold: int, returncode: int) -> tuple[str, str]:
    rows = latest_stage_rows(run_root, output_name, fold)
    if returncode != 0:
        return "failed", f"runner_returncode={returncode}"
    if any(status == "failed" for status in rows.values()):
        return "failed", f"stage_status={rows}"
    if rows.get("deploy") in {"ok", "cached"} and rows.get("validate") in {"ok", "cached"}:
        return "ok", f"stage_status={rows}"
    return "unknown", f"stage_status={rows}"


def append_status(status_csv: Path, row: dict[str, Any]) -> None:
    fields = [
        "started_at",
        "finished_at",
        "run_root",
        "run_name",
        "fold",
        "status",
        "detail",
        "returncode",
        "elapsed_s",
        "timeout_s",
        "wns",
        "tns",
        "failing_endpoints",
        "log",
    ]
    exists = status_csv.exists()
    with status_csv.open("a", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        if not exists:
            writer.writeheader()
        writer.writerow({field: row.get(field, "") for field in fields})


def log_line(top_log: Path, message: str) -> None:
    line = f"[{now()}] {message}"
    print(line, flush=True)
    with top_log.open("a") as handle:
        handle.write(line + "\n")


def child_pids(pid: int) -> list[int]:
    result = subprocess.run(["pgrep", "-P", str(pid)], text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False)
    children: list[int] = []
    for raw in result.stdout.splitlines():
        raw = raw.strip()
        if raw:
            try:
                children.append(int(raw))
            except ValueError:
                pass
    return children


def process_tree_pids(pid: int) -> list[int]:
    pids: list[int] = []
    for child in child_pids(pid):
        pids.extend(process_tree_pids(child))
    pids.append(pid)
    return pids


def signal_process_tree(pid: int, sig: int) -> None:
    for target in process_tree_pids(pid):
        try:
            os.kill(target, sig)
        except ProcessLookupError:
            pass
        except PermissionError:
            pass


def terminate_process_tree(proc: subprocess.Popen[Any], kill_after_s: int) -> None:
    signal_process_tree(proc.pid, signal.SIGTERM)
    try:
        proc.wait(timeout=kill_after_s)
        return
    except subprocess.TimeoutExpired:
        pass
    signal_process_tree(proc.pid, signal.SIGKILL)
    proc.wait()


def run_attempt(
    attempt: FoldAttempt,
    output_name: str,
    retry_dir: Path,
    timeout_s: int,
    kill_after_s: int,
    allow_timing_violating_deploy: bool,
    notify_enabled: bool,
    top_log: Path,
    status_csv: Path,
) -> str:
    run_name = attempt.run_root.name
    log_path = retry_dir / f"{run_name}_fold_{attempt.fold}.log"
    cmd = [
        sys.executable,
        str(SCRIPT_DIR / "run_hardware_kfold_cv.py"),
        "--run-root",
        str(attempt.run_root),
        "--output-name",
        output_name,
        "--stages",
        "preflight,deploy,validate",
        "--folds",
        str(attempt.fold),
        "--force-deploy",
    ]
    if allow_timing_violating_deploy:
        cmd.append("--allow-timing-violating-deploy")

    started_at = now()
    start = time.time()
    log_line(
        top_log,
        (
            f"start run={run_name} fold={attempt.fold} timeout_s={timeout_s} "
            f"WNS={attempt.wns} TNS={attempt.tns} endpoints={attempt.failing_endpoints}"
        ),
    )
    notify(notify_enabled, f"hardware CV retry started: run={run_name} fold={attempt.fold} timeout_min={timeout_s/60:.1f}")

    timed_out = False
    returncode: int | str = ""
    with log_path.open("w") as log:
        log.write(f"# started_at={started_at}\n")
        log.write("# command=" + " ".join(cmd) + "\n")
        log.flush()
        proc = subprocess.Popen(
            cmd,
            cwd=EXAMPLE_ROOT,
            stdout=log,
            stderr=subprocess.STDOUT,
        )
        try:
            returncode = proc.wait(timeout=timeout_s)
        except subprocess.TimeoutExpired:
            timed_out = True
            terminate_process_tree(proc, kill_after_s)
            returncode = "timeout"

    elapsed_s = time.time() - start
    if timed_out:
        status, detail = "timeout", f"exceeded_timeout_s={timeout_s}"
    else:
        status, detail = classify_result(attempt.run_root, output_name, attempt.fold, int(returncode))

    finished_at = now()
    row = {
        "started_at": started_at,
        "finished_at": finished_at,
        "run_root": str(attempt.run_root),
        "run_name": run_name,
        "fold": attempt.fold,
        "status": status,
        "detail": detail,
        "returncode": returncode,
        "elapsed_s": f"{elapsed_s:.1f}",
        "timeout_s": timeout_s,
        "wns": attempt.wns,
        "tns": attempt.tns,
        "failing_endpoints": attempt.failing_endpoints,
        "log": str(log_path),
    }
    append_status(status_csv, row)
    log_line(top_log, f"finish run={run_name} fold={attempt.fold} status={status} elapsed_s={elapsed_s:.1f} log={log_path}")
    notify(notify_enabled, f"hardware CV retry {status}: run={run_name} fold={attempt.fold} elapsed_min={elapsed_s/60:.1f}")
    return status


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-root", type=Path, action="append", required=True, help="Trained run root. Pass once per model.")
    parser.add_argument("--output-name", required=True, help="Existing hardware_kfold_cv output name to reuse.")
    parser.add_argument("--folds", default=None, help="Optional comma-separated folds to retry for every run.")
    parser.add_argument("--timeout-min", type=float, default=10.0, help="Hard timeout per fold attempt.")
    parser.add_argument("--kill-after-sec", type=int, default=60, help="Seconds between SIGTERM and SIGKILL after timeout.")
    parser.add_argument("--retry-dir", type=Path, default=None, help="Directory for retry logs/status. Default: timestamped under cwd.")
    parser.add_argument("--preserve-run-order", action="store_true", help="Use CLI run-root order instead of safer timing order.")
    parser.add_argument("--preserve-fold-order", action="store_true", help="Use numeric fold order instead of safer timing order.")
    parser.add_argument("--no-allow-timing-violating-deploy", action="store_true", help="Do not bypass timing guard on retry.")
    parser.add_argument("--dry-run", action="store_true", help="Print the retry order and exit without running any folds.")
    parser.add_argument("--notify", action="store_true", help=f"Send ntfy notifications to {NTFY_TOPIC}.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    folds = parse_folds(args.folds)
    timeout_s = max(1, int(args.timeout_min * 60))
    retry_dir = args.retry_dir or (EXAMPLE_ROOT / f"hardware_kfold_cv_retry_{args.output_name}_{time.strftime('%Y%m%d_%H%M%S')}")
    retry_dir.mkdir(parents=True, exist_ok=True)
    top_log = retry_dir / "retry.log"
    status_csv = retry_dir / "retry_status.csv"

    attempts_by_run: list[list[FoldAttempt]] = []
    for run_root in args.run_root:
        attempts = discover_attempts(run_root.resolve(), args.output_name, folds)
        if not args.preserve_fold_order:
            attempts = sorted(attempts, key=timing_sort_key, reverse=True)
        attempts_by_run.append(attempts)

    if not args.preserve_run_order:
        attempts_by_run = sorted(attempts_by_run, key=run_sort_key, reverse=True)

    flat_attempts = [attempt for attempts in attempts_by_run for attempt in attempts]
    if not flat_attempts:
        raise RuntimeError("No folds found to retry")

    if args.dry_run:
        for index, attempt in enumerate(flat_attempts, start=1):
            print(
                f"{index:02d} run={attempt.run_root.name} fold={attempt.fold} "
                f"WNS={attempt.wns} TNS={attempt.tns} endpoints={attempt.failing_endpoints}"
            )
        return

    log_line(top_log, f"retry campaign start output={args.output_name} attempts={len(flat_attempts)} retry_dir={retry_dir}")
    notify(args.notify, f"hardware CV retry campaign started: output={args.output_name} attempts={len(flat_attempts)}")

    counts = {"ok": 0, "failed": 0, "timeout": 0, "unknown": 0}
    for attempt in flat_attempts:
        status = run_attempt(
            attempt,
            output_name=args.output_name,
            retry_dir=retry_dir,
            timeout_s=timeout_s,
            kill_after_s=args.kill_after_sec,
            allow_timing_violating_deploy=not bool(args.no_allow_timing_violating_deploy),
            notify_enabled=bool(args.notify),
            top_log=top_log,
            status_csv=status_csv,
        )
        counts[status] = counts.get(status, 0) + 1

    summary = f"retry campaign done output={args.output_name} ok={counts.get('ok', 0)} failed={counts.get('failed', 0)} timeout={counts.get('timeout', 0)} unknown={counts.get('unknown', 0)} status_csv={status_csv}"
    log_line(top_log, summary)
    notify(args.notify, "hardware CV " + summary)
    if counts.get("failed", 0) or counts.get("timeout", 0) or counts.get("unknown", 0):
        sys.exit(1)


if __name__ == "__main__":
    main()
