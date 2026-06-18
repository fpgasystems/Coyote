#!/usr/bin/env bash
# Launch one split job batch in a detached tmux session.

set -euo pipefail

PART="${1:?Usage: $0 <part1|part2> [session_name]}"
SESSION="${2:-it4_big_ro_${PART}}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
JOB_ROOT="${JOB_ROOT:-jobs}"
SKIP_EXISTING_BINS="${SKIP_EXISTING_BINS:-0}"
MAX_PARALLEL="${MAX_PARALLEL:-6}"
TOPIC="${NTFY_TOPIC:-coyote-build-sdeheredia}"
MONITOR_INTERVAL="${MONITOR_INTERVAL:-60}"

if [ "$PART" != "part1" ] && [ "$PART" != "part2" ]; then
    echo "ERROR: part must be part1 or part2"
    exit 2
fi

unique_session() {
    local requested="$1"
    if tmux has-session -t "$requested" 2>/dev/null; then
        echo "${requested}_$(date +%Y%m%d_%H%M%S)"
    else
        echo "$requested"
    fi
}

SESSION="$(unique_session "$SESSION")"
MONITOR_SESSION="$(unique_session "${SESSION}_monitor")"

tmux new-session -d -s "$SESSION" \
    "cd '$BASE_DIR' && JOB_ROOT='$JOB_ROOT' SKIP_EXISTING_BINS='$SKIP_EXISTING_BINS' MAX_PARALLEL='$MAX_PARALLEL' NTFY_TOPIC='$TOPIC' scripts/run_job_batch.sh '$PART'"

tmux new-session -d -s "$MONITOR_SESSION" \
    "cd '$BASE_DIR' && NTFY_TOPIC='$TOPIC' MONITOR_INTERVAL='$MONITOR_INTERVAL' scripts/monitor_tmux_session_ntfy.sh '$SESSION' '$PART'"

echo "Launched tmux session: $SESSION"
echo "Launched monitor session: $MONITOR_SESSION"
echo "Attach with: tmux attach -t $SESSION"
