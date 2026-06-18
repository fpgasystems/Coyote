#!/usr/bin/env bash
set -euo pipefail

PKG=${PKG:-/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/reproducibility/prod_res256_coyote_accel_downsampler_hls4ml_e2e_20260524}
ML_ROOT=${ML_ROOT:-/pub/scratch/sdeheredia/Coyote/examples/ml_baseline}
VENV=${VENV:-$ML_ROOT/.venv_hls4ml}
PROGRAM=${PROGRAM:-1}
NTFY_TOPIC=${NTFY_TOPIC:-coyote-build-sdeheredia}
LOG_DIR="$PKG/replay/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/replay_$(date +%Y%m%d_%H%M%S).log"

notify() {
  curl -s -d "$1" "https://ntfy.sh/$NTFY_TOPIC" >/dev/null || true
}

trap 'status=$?; if [ "$status" -eq 0 ]; then notify "prod_res256_manualA_coyote_accel replay OK on $(hostname); log=$LOG"; else notify "prod_res256_manualA_coyote_accel replay FAILED status=$status on $(hostname); log=$LOG"; fi' EXIT

{
  echo "[replay] host=$(hostname)"
  echo "[replay] start=$(date -Is)"
  set +u
  source "$VENV/bin/activate"
  source /tools/Xilinx/Vitis/2024.2/settings64.sh
  set -u
  export PYTHONPATH="$ML_ROOT/hls4ml:$ML_ROOT:${PYTHONPATH:-}"
  cd "$ML_ROOT"
  if [ "$PROGRAM" = "1" ]; then
    echo "[replay] programming FPGA is handled by the packaged validation helper"
  fi
  python "$PKG/replay_validate.py" --package "$PKG" --project-name "prod_res256_manualA_coyote_accel" --program "$PROGRAM"
  echo "[replay] end=$(date -Is)"
} 2>&1 | tee "$LOG"
