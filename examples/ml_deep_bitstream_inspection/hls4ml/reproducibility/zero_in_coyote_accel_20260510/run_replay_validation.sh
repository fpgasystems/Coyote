#!/usr/bin/env bash
set -euo pipefail

PKG=${PKG:-/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/reproducibility/zero_in_coyote_accel_20260510}
ML_ROOT=${ML_ROOT:-/pub/scratch/sdeheredia/Coyote/examples/ml_baseline}
HLS4ML_PR=${HLS4ML_PR:-/pub/scratch/sdeheredia/hls4ml}
VENV=${VENV:-$ML_ROOT/.venv_hls4ml_coyote}
NTFY_TOPIC=${NTFY_TOPIC:-coyote-build-sdeheredia}

mkdir -p "$PKG/replay/logs"
LOG="$PKG/replay/logs/replay_validation_$(date +%Y%m%d_%H%M%S).log"

notify() {
  local msg=$1
  curl -s -d "$msg" "https://ntfy.sh/$NTFY_TOPIC" >/dev/null || true
}

on_exit() {
  local status=$?
  if [ "$status" -eq 0 ]; then
    notify "zero_in replay validation finished OK on $(hostname); log=$LOG"
  else
    notify "zero_in replay validation FAILED on $(hostname); status=$status; log=$LOG"
  fi
}
trap on_exit EXIT

{
  echo "[replay] host=$(hostname)"
  echo "[replay] start=$(date -Is)"
  source "$VENV/bin/activate"
  source /tools/Xilinx/Vitis/2024.2/settings64.sh

  cat > "$PKG/non_vcs_artifacts/runtime_manifest.json" <<EOF
{
  "project_dir": "$PKG/non_vcs_artifacts/runtime_project",
  "project_name": "zero_in_coyote_accel",
  "output_dir": "$PKG/replay",
  "stage": "runtime_replay"
}
EOF

  cd "$PKG/non_vcs_artifacts/runtime_project/Coyote/driver"
  make

  cd "$PKG/non_vcs_artifacts/runtime_project/Coyote/util"
  bash program_hacc_local.sh \
    "$PKG/non_vcs_artifacts/runtime_project/build/zero_in_coyote_accel_cyt_hw/bitstreams/cyt_top.bit" \
    "$PKG/non_vcs_artifacts/runtime_project/Coyote/driver/build/coyote_driver.ko"

  cd /tmp
  export LD_LIBRARY_PATH="$PKG/non_vcs_artifacts/runtime_project/build/zero_in_coyote_accel_cyt_sw:${LD_LIBRARY_PATH:-}"
  export PYTHONPATH="$HLS4ML_PR:$PKG/sources/ml_baseline/hls4ml/scripts/coyote_accelerator:$ML_ROOT"
  python - <<PY
import runpy, sys
sys.argv = [
    "zero_in_inference_validate.py",
    "--manifest", "$PKG/non_vcs_artifacts/runtime_manifest.json",
    "--config", "$PKG/sources/ml_baseline/hls4ml/configs/hls4ml_experiment/res256_layers5_W8A8_P50_RFbase.yaml",
    "--run-root", "$PKG/non_vcs_artifacts/model",
    "--input-root", "$PKG/non_vcs_artifacts/prepared_inputs",
    "--batch-size", "16",
    "--n-samples", "48",
    "--tolerance", "0.20",
]
runpy.run_path("$PKG/sources/ml_baseline/hls4ml/scripts/coyote_accelerator/zero_in_inference_validate.py", run_name="__main__")
PY

  echo "[replay] end=$(date -Is)"
} 2>&1 | tee "$LOG"
