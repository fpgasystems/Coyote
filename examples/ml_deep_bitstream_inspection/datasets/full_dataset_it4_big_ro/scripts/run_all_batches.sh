#!/usr/bin/env bash
# Run all big-hammer RO batches sequentially.
#
# This script is intended to run inside tmux. It exits immediately on failure
# and sends an ntfy completion notification.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
TOPIC="${NTFY_TOPIC:-coyote-build-sdeheredia}"
LOG_DIR="$BASE_DIR/logs"
RUN_LOG="$LOG_DIR/run_all_batches_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$LOG_DIR"

notify() {
    local status="$1"
    local message="$2"
    curl -s -d "$message" "ntfy.sh/$TOPIC" >/dev/null || true
    echo "[$(date)] ntfy status=$status message=$message"
}

finish() {
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        notify "success" "full_dataset_it4_big_ro build finished successfully"
    else
        notify "failure" "full_dataset_it4_big_ro build failed with exit code $rc; see $RUN_LOG"
    fi
    exit "$rc"
}

trap finish EXIT

{
    echo "=== full_dataset_it4_big_ro build ==="
    echo "Base: $BASE_DIR"
    echo "Start: $(date)"

    cd "$BASE_DIR"

    source scripts/source_xilinx_2024_2.sh

    echo "[setup] Generate standalone apps"
    python3 scripts/gen_standalone_apps.py

    echo "[setup] Generate CMakeLists files"
    python3 scripts/gen_cmakelists.py --all

    for batch in STAND_FP06 STAND_FP08 STAND_FP09 STAND_FP10 STAND_FP04 STAND_FP14; do
        echo ""
        echo "=== Running $batch ==="
        scripts/run_batch.sh "$batch"
        python3 scripts/collect_reports.py --batch "$batch" \
            --output "$LOG_DIR/${batch}_reports_raw.csv"
    done

    echo ""
    echo "=== Collect/package/manifest/validate ==="
    python3 scripts/collect_reports.py --all
    python3 scripts/package_outputs.py
    python3 scripts/gen_manifest.py
    python3 scripts/validate_dataset.py

    echo "End: $(date)"
} 2>&1 | tee "$RUN_LOG"
