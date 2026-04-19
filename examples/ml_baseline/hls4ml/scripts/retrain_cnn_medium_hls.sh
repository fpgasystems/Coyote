#!/usr/bin/env bash
# Retrain cnn_medium_hls on all 5 folds using the exact April 15 hyperparameters.
#
# Run this on a GPU host. Launches inside a new tmux session so the job
# survives disconnects.
#
# Usage:
#   /bt
#
# Monitor:
#   tmux attach -t train_cnn_medium_hls
#   tail -f examples/ml_baseline/runs/launch_*_cnn_medium_hls_ro8000_ep500_kfold5_fliponly.log
set -euo pipefail

ML_BASELINE_DIR="/pub/scratch/sdeheredia/Coyote/examples/ml_baseline"
cd "$ML_BASELINE_DIR"

# Pick the first Python that can import torch. Prefer .venv (historical default);
# fall back to .venv_hls4ml (the one that works on this host right now).
PY=""
for candidate in "$ML_BASELINE_DIR/.venv/bin/python" "$ML_BASELINE_DIR/.venv_hls4ml/bin/python"; do
    if "$candidate" -c "import torch" >/dev/null 2>&1; then
        PY="$candidate"
        break
    fi
done
if [[ -z "$PY" ]]; then
    echo "No working Python with torch found under .venv or .venv_hls4ml" >&2
    exit 1
fi
echo "Using Python: $PY"

TS="$(date +%Y%m%d_%H%M%S)"
LOG="runs/launch_${TS}_cnn_medium_hls_ro8000_ep500_kfold5_fliponly.log"
SESSION="train_cnn_medium_hls"

if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "tmux session '$SESSION' already exists. Attach with: tmux attach -t $SESSION" >&2
    exit 1
fi

CMD="cd $ML_BASELINE_DIR && \
$PY train.py \
    --model cnn_medium_hls \
    --representation 2d \
    --epochs 500 \
    --batch-size 8 \
    --lr 1e-4 \
    --seed 42 \
    --val-split 0.2 \
    --min-ro 8000 \
    --num-workers 2 \
    --kfold 5 \
    --augment \
    --flip-h-prob 0.5 --flip-v-prob 0.5 \
    --crop-scale-min 1.0 --translate 0.0 \
    --top-n-hardest 10 \
    --run-name cnn_medium_hls_ro8000_ep500_kfold5_fliponly \
    2>&1 | tee $LOG"

echo "Launching tmux session: $SESSION"
echo "Log file: $LOG"
tmux new-session -d -s "$SESSION" "$CMD; echo; echo '[training finished — press enter to close]'; read -r"
echo
echo "Done. Attach with:    tmux attach -t $SESSION"
echo "Detach with:          Ctrl-b d"
echo "Tail the log:         tail -f $ML_BASELINE_DIR/$LOG"
