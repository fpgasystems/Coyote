#!/usr/bin/env bash
set -euo pipefail

ROOT="/pub/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/hls4ml"
SESSION="${1:-hls4ml_selected_feasible_artifact_recovery}"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_ROOT="$ROOT/logs/selected_feasible_artifact_recovery/$TS"
RUNNER="$ROOT/scripts/run_selected_feasible_artifact_recovery.sh"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "tmux session already exists: $SESSION" >&2
  exit 1
fi

mkdir -p "$LOG_ROOT"

tmux new-session -d -s "$SESSION" "bash '$RUNNER' '$SESSION' '$LOG_ROOT'"

echo "session=$SESSION"
echo "attach=tmux attach -t $SESSION"
echo "log=$LOG_ROOT/supervisor.log"
