#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION="${1:-hls4ml_big_ro_512_serial}"
CURRENT_SESSION="${2:-hls4ml_big_ro_training}"
LOG_ROOT="$ROOT/logs/big_ro_training_512_serial/$(date +%Y%m%d_%H%M%S)"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "[big-ro-512] session already exists: $SESSION" >&2
  exit 1
fi

tmux new-session -d -s "$SESSION" "bash '$ROOT/scripts/run_big_ro_512_serial_after_current.sh' '$CURRENT_SESSION' '$LOG_ROOT'"
echo "[big-ro-512] launched session=$SESSION waiting_on=$CURRENT_SESSION logs=$LOG_ROOT"
