#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml}"
SESSION="${1:-hls4ml_big_ro_training}"
MONITOR_SESSION="${SESSION}_milestone_monitor"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_ROOT="$ROOT/logs/big_ro_training/$TS"
RUNNER="$ROOT/scripts/run_big_ro_training.sh"
STATUS="$ROOT/results/big_ro_training/suite_status.csv"

for old in hls4ml_big_ro_balanced_training hls4ml_big_ro_balanced_milestone_monitor; do
  if tmux has-session -t "$old" 2>/dev/null; then
    echo "old balanced session is still running: $old" >&2
    echo "stop it first with: tmux kill-session -t $old" >&2
    exit 1
  fi
done

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "tmux session already exists: $SESSION" >&2
  exit 1
fi
if tmux has-session -t "$MONITOR_SESSION" 2>/dev/null; then
  echo "tmux session already exists: $MONITOR_SESSION" >&2
  exit 1
fi

mkdir -p "$LOG_ROOT"
tmux new-session -d -s "$SESSION" "bash '$RUNNER' '$SESSION' '$LOG_ROOT'"
tmux new-session -d -s "$MONITOR_SESSION" \
  "cd '$ROOT' && python3 scripts/monitor_big_ro_training_milestones.py --status '$STATUS' --topic coyote-build-sdeheredia --milestones 1 3 --interval 60"

echo "session=$SESSION"
echo "attach=tmux attach -t $SESSION"
echo "monitor_session=$MONITOR_SESSION"
echo "monitor_attach=tmux attach -t $MONITOR_SESSION"
echo "log=$LOG_ROOT/supervisor.log"
