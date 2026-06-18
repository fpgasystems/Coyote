#!/usr/bin/env bash
# Run one independent split batch with bounded parallelism.
#
# Usage:
#   scripts/run_job_batch.sh part1
#   scripts/run_job_batch.sh part2

set -euo pipefail

PART="${1:?Usage: $0 <part1|part2>}"
MAX_PARALLEL="${MAX_PARALLEL:-6}"
JOB_ROOT="${JOB_ROOT:-jobs}"
SKIP_EXISTING_BINS="${SKIP_EXISTING_BINS:-0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
TOPIC="${NTFY_TOPIC:-coyote-build-sdeheredia}"
LOG_DIR="$BASE_DIR/logs/$JOB_ROOT/$PART"
STATUS_DIR="$BASE_DIR/logs/status/$JOB_ROOT/$PART"
RUN_LOG="$BASE_DIR/logs/run_${PART}_${JOB_ROOT}_$(date +%Y%m%d_%H%M%S).log"
SUMMARY_FILE="${RUN_LOG%.log}.summary"

if [ "$PART" != "part1" ] && [ "$PART" != "part2" ]; then
    echo "ERROR: part must be part1 or part2"
    exit 2
fi

mkdir -p "$LOG_DIR" "$STATUS_DIR" "$(dirname "$RUN_LOG")"

notify() {
    local message="$1"
    curl -s -d "$message" "ntfy.sh/$TOPIC" >/dev/null || true
}

existing_bin_for_job() {
    local batch_id="$1"
    local config_local="$2"
    PYTHONPATH="$SCRIPT_DIR" JOB_ROOT="$JOB_ROOT" python3 - "$batch_id" "$config_local" <<'PY'
import os
import sys
from job_paths import bitstream_path_for

path = bitstream_path_for(sys.argv[1], int(sys.argv[2]))
print(path if os.path.exists(path) else "")
PY
}

write_status() {
    local job_id="$1"
    local status="$2"
    local detail="${3:-}"
    printf "job_id\t%s\nstatus\t%s\ndetail\t%s\nend_time\t%s\n" \
        "$job_id" "$status" "$detail" "$(date)" > "$STATUS_DIR/${job_id}.status"
}

run_queue() {
    local running=0
    local started=0
    local completed=0
    local skipped=0

    echo "=== full_dataset_it4_big_ro $PART ==="
    echo "Base: $BASE_DIR"
    echo "Job root: $JOB_ROOT"
    echo "Max parallel jobs: $MAX_PARALLEL"
    echo "Skip existing bins: $SKIP_EXISTING_BINS"
    echo "Start: $(date)"

    cd "$BASE_DIR"

    source scripts/source_xilinx_2024_2.sh

    expected_apps="$(PYTHONPATH="$SCRIPT_DIR" python3 -c 'from dataset_config import CONFIG_COUNT; print(CONFIG_COUNT)')"
    actual_apps="$(find hw/apps/standalone -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
    if [ "$actual_apps" -ne "$expected_apps" ]; then
        echo "ERROR: expected $expected_apps standalone apps, found $actual_apps"
        echo "Run: python3 scripts/gen_standalone_apps.py"
        return 1
    fi

    while IFS=$'\t' read -r job_id global_config batch_id fp_id fplan_file config_local ro_count target_pct; do
        if [ "$SKIP_EXISTING_BINS" = "1" ]; then
            existing_bin="$(existing_bin_for_job "$batch_id" "$config_local")"
            if [ -n "$existing_bin" ]; then
                echo "[$(date +%H:%M:%S)] skip $job_id existing_bin=$existing_bin"
                write_status "$job_id" "SKIP" "$existing_bin"
                skipped=$((skipped + 1))
                continue
            fi
        fi

        while [ "$running" -ge "$MAX_PARALLEL" ]; do
            wait -n || true
            completed=$((completed + 1))
            running=$((running - 1))
        done

        echo "[$(date +%H:%M:%S)] queue $job_id"
        (
            if JOB_ROOT="$JOB_ROOT" scripts/run_sample_job.sh \
                "$job_id" "$global_config" "$batch_id" "$fp_id" "$fplan_file" \
                "$config_local" "$ro_count" "$target_pct" \
                > "$LOG_DIR/${job_id}.log" 2>&1; then
                write_status "$job_id" "PASS" "$LOG_DIR/${job_id}.log"
            else
                rc=$?
                write_status "$job_id" "FAIL" "exit_code=$rc log=$LOG_DIR/${job_id}.log"
            fi
        ) &
        running=$((running + 1))
        started=$((started + 1))
    done < <(python3 scripts/list_job_batch.py "$PART")

    while [ "$running" -gt 0 ]; do
        wait -n || true
        completed=$((completed + 1))
        running=$((running - 1))
    done

    passed="$(find "$STATUS_DIR" -maxdepth 1 -type f -name 'S*.status' -exec awk -F '\t' '$1=="status" && $2=="PASS" {print FILENAME}' {} + | sort -u | wc -l)"
    failed="$(find "$STATUS_DIR" -maxdepth 1 -type f -name 'S*.status' -exec awk -F '\t' '$1=="status" && $2=="FAIL" {print FILENAME}' {} + | sort -u | wc -l)"
    skipped_total="$(find "$STATUS_DIR" -maxdepth 1 -type f -name 'S*.status' -exec awk -F '\t' '$1=="status" && $2=="SKIP" {print FILENAME}' {} + | sort -u | wc -l)"
    expected="$(python3 scripts/list_job_batch.py "$PART" | wc -l)"
    observed=$((passed + failed + skipped_total))
    missing=$((expected - observed))

    echo "End: $(date)"
    echo "Started jobs: $started"
    echo "Completed jobs observed: $completed"
    echo "Skipped jobs this run: $skipped"
    echo "Sample status: passed=$passed failed=$failed skipped=$skipped_total missing=$missing expected=$expected"
    {
        echo "part=$PART"
        echo "job_root=$JOB_ROOT"
        echo "passed=$passed"
        echo "failed=$failed"
        echo "skipped=$skipped_total"
        echo "missing=$missing"
        echo "expected=$expected"
        echo "log_dir=$LOG_DIR"
    } > "$SUMMARY_FILE"

    python3 scripts/collect_reports.py --all
    echo "Batch $PART completed; sample failures, if any, are recorded in $STATUS_DIR"
}

if run_queue 2>&1 | tee "$RUN_LOG"; then
    summary="$(tr '\n' ' ' < "$SUMMARY_FILE" 2>/dev/null || true)"
    notify "full_dataset_it4_big_ro $PART finished; $summary"
else
    rc=$?
    notify "full_dataset_it4_big_ro $PART failed with exit code $rc; see $RUN_LOG"
    exit "$rc"
fi
