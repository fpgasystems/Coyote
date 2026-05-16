#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml}"
SESSION="${1:-hls4ml_2048x6_phase5_topup_$(date +%Y%m%d_%H%M%S)}"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_ROOT="$ROOT/logs/2048x6_phase5_topup/$TS"
RUNNER="$ROOT/scripts/run_2048x6_phase5_topup.sh"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "tmux session already exists: $SESSION" >&2
  exit 1
fi

mkdir -p "$LOG_ROOT"
tmux new-session -d -s "$SESSION" "JOBS='${JOBS:-5}' bash '$RUNNER' '$SESSION' '$LOG_ROOT'"

echo "session=$SESSION"
echo "attach=tmux attach -t $SESSION"
echo "log=$LOG_ROOT/supervisor.log"
