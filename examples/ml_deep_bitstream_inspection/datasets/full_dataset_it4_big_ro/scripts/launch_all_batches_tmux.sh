#!/usr/bin/env bash
# Launch the full big-hammer RO build in a detached tmux session.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
SESSION="${1:-it4_big_ro_build}"

tmux new-session -d -s "$SESSION" "cd '$BASE_DIR' && NTFY_TOPIC='coyote-build-sdeheredia' scripts/run_all_batches.sh"

echo "Launched tmux session: $SESSION"
echo "Attach with: tmux attach -t $SESSION"
