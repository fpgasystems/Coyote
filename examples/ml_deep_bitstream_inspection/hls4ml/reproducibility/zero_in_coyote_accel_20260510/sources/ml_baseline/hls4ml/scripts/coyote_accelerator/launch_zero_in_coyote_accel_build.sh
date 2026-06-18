#!/usr/bin/env bash
set -euo pipefail

ML_BASELINE_ROOT="${ML_BASELINE_ROOT:-/pub/scratch/sdeheredia/Coyote/examples/ml_baseline}"
SCRIPT_DIR="${ML_BASELINE_ROOT}/hls4ml/scripts/coyote_accelerator"
OUT_PARENT="${OUT_PARENT:-${ML_BASELINE_ROOT}/hls4ml/artifacts/coyote_accelerator_zero_in_e2e}"
STAMP="$(date +%Y%m%d_%H%M%S)"
SESSION="${SESSION:-zero_in_coyote_accel_e2e_${STAMP}}"
OUT_DIR="${OUT_DIR:-${OUT_PARENT}/${STAMP}}"
LOG_DIR="${OUT_DIR}/logs"
LOG="${LOG_DIR}/build.log"
NTFY_TOPIC="${NTFY_TOPIC:-coyote-build-sdeheredia}"
COYOTE_VENV="${COYOTE_VENV:-${ML_BASELINE_ROOT}/.venv_hls4ml_coyote}"
PY="${COYOTE_VENV}/bin/python"
XILINX_VERSION="${XILINX_VERSION:-2024.2}"
PROJECT_NAME="${PROJECT_NAME:-zero_in_coyote_accel}"
N_SAMPLES="${N_SAMPLES:-48}"
TOLERANCE="${TOLERANCE:-0.20}"
VALIDATION_BATCH_SIZE="${VALIDATION_BATCH_SIZE:-16}"

mkdir -p "${LOG_DIR}"

if tmux has-session -t "${SESSION}" 2>/dev/null; then
  echo "tmux session already exists: ${SESSION}" >&2
  exit 1
fi

tmux new-session -d -s "${SESSION}" bash -lc "
  set +e
  curl -s -d \"zero-in CoyoteAccelerator E2E started: session=${SESSION} out=${OUT_DIR}\" ntfy.sh/${NTFY_TOPIC} >/dev/null || true
  (
    set -euo pipefail
    echo \"[start] \$(date -Is)\"
    echo \"[session] ${SESSION}\"
    echo \"[out] ${OUT_DIR}\"
    echo \"[project] ${PROJECT_NAME}\"
    echo \"[samples] ${N_SAMPLES}\"
    echo \"[validation_batch_size] ${VALIDATION_BATCH_SIZE}\"
    source \"/tools/Xilinx/Vivado/${XILINX_VERSION}/settings64.sh\"
    source \"/tools/Xilinx/Vitis/${XILINX_VERSION}/settings64.sh\"
    source \"/tools/Xilinx/Vitis_HLS/${XILINX_VERSION}/settings64.sh\"
    which vivado
    which vitis_hls
    cd '${ML_BASELINE_ROOT}'
    if [[ ! -x '${PY}' ]]; then
      '${SCRIPT_DIR}/setup_coyote_venv.sh'
    else
      echo '[venv] reusing existing ${COYOTE_VENV}'
    fi
    echo \"[build] \$(date -Is)\"
    '${PY}' '${SCRIPT_DIR}/zero_in_synth.py' \
      --output-dir '${OUT_DIR}' \
      --project-name '${PROJECT_NAME}' \
      --n-samples '${N_SAMPLES}' \
      --tolerance '${TOLERANCE}'
    curl -s -d \"zero-in CoyoteAccelerator bitstream build PASSED: out=${OUT_DIR} log=${LOG}\" ntfy.sh/${NTFY_TOPIC} >/dev/null || true
    echo \"[validate] \$(date -Is)\"
    '${PY}' '${SCRIPT_DIR}/zero_in_inference_validate.py' \
      --manifest '${OUT_DIR}/build_manifest.json' \
      --batch-size '${VALIDATION_BATCH_SIZE}' \
      --n-samples '${N_SAMPLES}' \
      --tolerance '${TOLERANCE}' \
      --program
    curl -s -d \"zero-in CoyoteAccelerator FPGA validation PASSED: out=${OUT_DIR} log=${LOG}\" ntfy.sh/${NTFY_TOPIC} >/dev/null || true
    echo \"[finish] \$(date -Is)\"
  ) > '${LOG}' 2>&1
  status=\$?
  if [[ \$status -eq 0 ]]; then
    curl -s -d \"zero-in CoyoteAccelerator E2E PASSED: out=${OUT_DIR} log=${LOG}\" ntfy.sh/${NTFY_TOPIC} >/dev/null || true
  else
    curl -s -d \"zero-in CoyoteAccelerator E2E FAILED status=\$status: out=${OUT_DIR} log=${LOG}\" ntfy.sh/${NTFY_TOPIC} >/dev/null || true
  fi
  exit \$status
"

echo "session=${SESSION}"
echo "out=${OUT_DIR}"
echo "log=${LOG}"
echo "attach: tmux attach -t ${SESSION}"
echo "tail: tail -f ${LOG}"
