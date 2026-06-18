#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/pub/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/hls4ml}"
SESSION="${1:-hls4ml_big_ro_balanced_training}"
LOG_ROOT="${2:-$ROOT/logs/big_ro_balanced_training/$(date +%Y%m%d_%H%M%S)}"
TOPIC="${TOPIC:-coyote-build-sdeheredia}"
CONFIG_DIR="configs/hls4ml_big_ro_balanced_training"
RESULTS_DIR="results/big_ro_balanced_training"
VAULT="/mnt/scratch/sdeheredia/coyote_vault_big_ro_balanced"

if [ -x "$ROOT/../.venv_hls4ml/bin/python" ]; then
  PY="$ROOT/../.venv_hls4ml/bin/python"
elif [ -x "$ROOT/../.venv/bin/python" ]; then
  PY="$ROOT/../.venv/bin/python"
else
  PY="python3"
fi

cd "$ROOT"
mkdir -p "$LOG_ROOT"
exec > >(tee -a "$LOG_ROOT/supervisor.log") 2>&1

notify() {
  curl -s -d "$*" "ntfy.sh/$TOPIC" >/dev/null || true
}

status_summary() {
  "$PY" - <<'PY'
import csv
import collections
from pathlib import Path

p = Path("results/big_ro_balanced_training/suite_status.csv")
rows = list(csv.DictReader(p.open())) if p.exists() else []
counts = collections.Counter(row.get("status", "") for row in rows)
print("rows=" + str(len(rows)) + " " + " ".join(f"{k}={v}" for k, v in sorted(counts.items())))
PY
}

trap 'status=$?; notify "big-RO balanced training FAILED status=$status session=$SESSION log=$LOG_ROOT/supervisor.log"; exit $status' ERR

echo "[big-ro] launched session=$SESSION logs=$LOG_ROOT"
notify "big-RO balanced training launched: session=$SESSION logs=$LOG_ROOT"

if [ -d "$VAULT" ]; then
  echo "[big-ro] validating existing vault=$VAULT"
  "$PY" scripts/prepare_big_ro_balanced_training.py --reuse-existing-vault --reuse-existing-configs
else
  echo "[big-ro] creating balanced vault=$VAULT"
  "$PY" scripts/prepare_big_ro_balanced_training.py
fi

echo "[big-ro] start float training jobs=2"
notify "big-RO balanced float training started: jobs=2 session=$SESSION logs=$LOG_ROOT/float"
"$PY" scripts/run_experiment_configs_parallel.py \
  --configs "$CONFIG_DIR" \
  --phases float \
  --stages train \
  --results-dir "$RESULTS_DIR" \
  --log-dir "$LOG_ROOT/float" \
  --jobs 2

echo "[big-ro] start QAT P50 training jobs=2"
notify "big-RO balanced QAT P50 training started: jobs=2 session=$SESSION logs=$LOG_ROOT/qat_p50"
"$PY" scripts/run_experiment_configs_parallel.py \
  --configs "$CONFIG_DIR" \
  --phases qat_p50 \
  --stages train \
  --results-dir "$RESULTS_DIR" \
  --log-dir "$LOG_ROOT/qat_p50" \
  --jobs 2

echo "[big-ro] complete $(status_summary) logs=$LOG_ROOT"
notify "big-RO balanced training complete: $(status_summary) session=$SESSION results=$ROOT/$RESULTS_DIR"
