#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CURRENT_SESSION="${1:-hls4ml_big_ro_training}"
LOG_ROOT="${2:-$ROOT/logs/big_ro_training_512_serial/$(date +%Y%m%d_%H%M%S)}"
TOPIC="${NTFY_TOPIC:-coyote-build-sdeheredia}"

CONFIG_DIR="$ROOT/configs/hls4ml_big_ro_training"
SERIAL_CONFIG_DIR="$ROOT/configs/hls4ml_big_ro_training_512_serial/$(basename "$LOG_ROOT")"
RESULTS_DIR="$ROOT/results/big_ro_training_512_serial"
STATUS="$RESULTS_DIR/suite_status.csv"
FLOAT_CONFIG="res512_layers7_WfloatAfloat_P0_RFbase.yaml"
QAT_CONFIG="res512_layers7_W8A8_P50_RFbase.yaml"

if [[ -x "$ROOT/../.venv_hls4ml/bin/python" ]]; then
  PY="$ROOT/../.venv_hls4ml/bin/python"
elif [[ -x "$ROOT/../.venv/bin/python" ]]; then
  PY="$ROOT/../.venv/bin/python"
else
  PY="python3"
fi

notify() {
  local message="$1"
  curl -s -d "$message" "https://ntfy.sh/$TOPIC" >/dev/null || true
}

csv_has_failed() {
  "$PY" - "$STATUS" <<'PY'
import csv
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    sys.exit(0)
with path.open(newline="") as handle:
    for row in csv.DictReader(handle):
        if row.get("status") == "failed":
            print(f"{row.get('experiment_name')} failed: {row.get('failure_reason')}")
            sys.exit(1)
sys.exit(0)
PY
}

mkdir -p "$LOG_ROOT" "$RESULTS_DIR"
exec > >(tee -a "$LOG_ROOT/supervisor.log") 2>&1

echo "[big-ro-512] waiting for current session=$CURRENT_SESSION"
notify "[big-ro-512] queued serial 512x7 rerun; waiting for $CURRENT_SESSION to finish"

while tmux has-session -t "$CURRENT_SESSION" 2>/dev/null; do
  sleep 60
done

echo "[big-ro-512] current session finished; preparing serial configs"

if [[ -f "$CONFIG_DIR/$QAT_CONFIG.deferred" ]]; then
  mv "$CONFIG_DIR/$QAT_CONFIG.deferred" "$CONFIG_DIR/$QAT_CONFIG"
fi

if [[ ! -f "$CONFIG_DIR/$FLOAT_CONFIG" ]]; then
  echo "[big-ro-512] missing $CONFIG_DIR/$FLOAT_CONFIG"
  notify "[big-ro-512] failed before start: missing float config"
  exit 1
fi
if [[ ! -f "$CONFIG_DIR/$QAT_CONFIG" ]]; then
  echo "[big-ro-512] missing $CONFIG_DIR/$QAT_CONFIG"
  notify "[big-ro-512] failed before start: missing QAT config"
  exit 1
fi

mkdir -p "$SERIAL_CONFIG_DIR"
cp "$CONFIG_DIR/$FLOAT_CONFIG" "$SERIAL_CONFIG_DIR/$FLOAT_CONFIG"
cp "$CONFIG_DIR/$QAT_CONFIG" "$SERIAL_CONFIG_DIR/$QAT_CONFIG"

notify "[big-ro-512] starting serial 512x7 float rerun"
echo "[big-ro-512] start float jobs=1"
"$PY" scripts/run_experiment_configs_parallel.py \
  --configs "$SERIAL_CONFIG_DIR" \
  --phases float \
  --stages train \
  --results-dir "$RESULTS_DIR" \
  --log-dir "$LOG_ROOT/float" \
  --jobs 1 \
  --force

if ! csv_has_failed; then
  notify "[big-ro-512] float rerun failed; see $LOG_ROOT/float/res512_layers7_WfloatAfloat_P0_RFbase.log"
  exit 1
fi

notify "[big-ro-512] starting serial 512x7 QAT P50 rerun"
echo "[big-ro-512] start QAT P50 jobs=1"
"$PY" scripts/run_experiment_configs_parallel.py \
  --configs "$SERIAL_CONFIG_DIR" \
  --phases qat_p50 \
  --stages train \
  --results-dir "$RESULTS_DIR" \
  --log-dir "$LOG_ROOT/qat_p50" \
  --jobs 1 \
  --force

if ! csv_has_failed; then
  notify "[big-ro-512] QAT rerun failed; see $LOG_ROOT/qat_p50/res512_layers7_W8A8_P50_RFbase.log"
  exit 1
fi

notify "[big-ro-512] serial 512x7 float + QAT reruns completed"
echo "[big-ro-512] done status=$STATUS logs=$LOG_ROOT"
