#!/usr/bin/env bash
set -euo pipefail

PKG=${PKG:-/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/reproducibility/zero_in_coyote_accel_downsampler_hls4ml_e2e_20260517}
ML_ROOT=${ML_ROOT:-/pub/scratch/sdeheredia/Coyote/examples/ml_baseline}
HLS4ML_PR=${HLS4ML_PR:-/pub/scratch/sdeheredia/hls4ml}
VENV=${VENV:-$ML_ROOT/.venv_hls4ml_coyote}
NTFY_TOPIC=${NTFY_TOPIC:-coyote-build-sdeheredia}
PROGRAM=${PROGRAM:-1}

mkdir -p "$PKG/replay/logs" "$PKG/replay/fpga_validation"
LOG="$PKG/replay/logs/replay_raw_validation_$(date +%Y%m%d_%H%M%S).log"
MANIFEST="$PKG/non_vcs_artifacts/runtime_manifest.json"

notify() {
  local msg=$1
  curl -s -d "$msg" "https://ntfy.sh/$NTFY_TOPIC" >/dev/null || true
}

on_exit() {
  local status=$?
  if [ "$status" -eq 0 ]; then
    notify "zero_in raw replay validation finished OK on $(hostname); log=$LOG"
  else
    notify "zero_in raw replay validation FAILED on $(hostname); status=$status; log=$LOG"
  fi
}
trap on_exit EXIT

{
  echo "[replay] host=$(hostname)"
  echo "[replay] start=$(date -Is)"
  set +u
  source "$VENV/bin/activate"
  source /tools/Xilinx/Vitis/2024.2/settings64.sh
  set -u

  python - <<PY
import json
from pathlib import Path
manifest = {
    "project_dir": "$PKG/non_vcs_artifacts/runtime_project",
    "project_name": "zero_in_coyote_accel",
    "output_dir": "$PKG/replay",
    "stage": "runtime_replay_raw",
    "raw_input_mode": True,
}
Path("$MANIFEST").write_text(json.dumps(manifest, indent=2, sort_keys=True))
PY

  cd /tmp
  export LD_LIBRARY_PATH="$PKG/non_vcs_artifacts/runtime_project/build/zero_in_coyote_accel_cyt_sw/lib:${LD_LIBRARY_PATH:-}"
  export PYTHONPATH="$HLS4ML_PR:$PKG/sources/ml_baseline/hls4ml/scripts/coyote_accelerator:$ML_ROOT"

  args=(
    "$PKG/sources/ml_baseline/hls4ml/scripts/coyote_accelerator/zero_in_inference_validate.py"
    --manifest "$MANIFEST"
    --config "$PKG/sources/ml_baseline/hls4ml/configs/hls4ml_experiment/res256_layers5_W8A8_P50_RFbase.yaml"
    --run-root "$PKG/non_vcs_artifacts/model"
    --input-root "$PKG/non_vcs_artifacts/prepared_inputs"
    --split-csv "$PKG/non_vcs_artifacts/raw_bitstreams_by_vault/fold_0_val.csv"
    --batch-size 16
    --n-samples 48
    --tolerance 0.20
  )
  if [ "$PROGRAM" = "1" ]; then
    args+=(--program)
  fi
  python "${args[@]}"
  echo "[replay] end=$(date -Is)"
} 2>&1 | tee "$LOG"
