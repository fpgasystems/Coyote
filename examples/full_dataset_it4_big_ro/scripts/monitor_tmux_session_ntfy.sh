#!/usr/bin/env bash
# Send an ntfy notification when a tmux session exits.
#
# Usage:
#   scripts/monitor_tmux_session_ntfy.sh <session> <label>

set -euo pipefail

SESSION="${1:?Usage: $0 <session> <label>}"
LABEL="${2:-$SESSION}"
TOPIC="${NTFY_TOPIC:-coyote-build-sdeheredia}"
INTERVAL="${MONITOR_INTERVAL:-60}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$BASE_DIR/logs/monitors"
LOG_FILE="$LOG_DIR/${SESSION}_monitor_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$LOG_DIR"

notify() {
    local message="$1"
    curl -s -d "$message" "ntfy.sh/$TOPIC" >/dev/null || true
    echo "[$(date)] $message" | tee -a "$LOG_FILE"
}

echo "Monitoring tmux session '$SESSION' ($LABEL)" | tee -a "$LOG_FILE"
echo "Start: $(date)" | tee -a "$LOG_FILE"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    notify "full_dataset_it4_big_ro monitor: $LABEL tmux session is not running at monitor start"
    exit 1
fi

while tmux has-session -t "$SESSION" 2>/dev/null; do
    sleep "$INTERVAL"
done

notify "full_dataset_it4_big_ro monitor: $LABEL tmux session ended"
