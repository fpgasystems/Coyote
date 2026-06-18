#!/usr/bin/env bash
set -euo pipefail

ML_BASELINE_ROOT="${ML_BASELINE_ROOT:-/pub/scratch/sdeheredia/Coyote/examples/ml_baseline}"
SCRIPT_DIR="${ML_BASELINE_ROOT}/hls4ml/scripts/coyote_accelerator"
OUT_PARENT="${ML_BASELINE_ROOT}/hls4ml/artifacts/coyote_original_example"
RUN_ID="${RUN_ID:-$(date +%Y%m%d_%H%M%S)}"
NTFY_TOPIC="${NTFY_TOPIC:-coyote-build-sdeheredia}"
COYOTE_VENV="${COYOTE_VENV:-${ML_BASELINE_ROOT}/.venv_hls4ml_coyote}"
PY="${COYOTE_VENV}/bin/python"
XILINX_VERSION="${XILINX_VERSION:-2024.2}"
MODES="${MODES:-io_parallel io_stream}"
IO_PARALLEL_ARGS="${IO_PARALLEL_ARGS:---cosim --validation --bitfile}"
IO_STREAM_ARGS="${IO_STREAM_ARGS:-}"

mkdir -p "${OUT_PARENT}/${RUN_ID}"

launch_one() {
  local mode="$1"
  local extra_args="$2"
  local session="coyote_original_${mode}_${RUN_ID}"
  local out_dir="${OUT_PARENT}/${RUN_ID}/${mode}"
  local log_dir="${out_dir}/logs"
  local log="${log_dir}/build.log"
  mkdir -p "${log_dir}"

  if tmux has-session -t "${session}" 2>/dev/null; then
    echo "tmux session already exists: ${session}" >&2
    exit 1
  fi

  tmux new-session -d -s "${session}" bash -lc "
    set +e
    curl -s -d \"Coyote original example ${mode} started: session=${session} out=${out_dir}\" ntfy.sh/${NTFY_TOPIC} >/dev/null || true
    (
      set -euo pipefail
      echo \"[start] \$(date -Is)\"
      echo \"[session] ${session}\"
      echo \"[run_id] ${RUN_ID}\"
      echo \"[mode] ${mode}\"
      echo \"[out] ${out_dir}\"
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
      '${PY}' '${SCRIPT_DIR}/original_example_probe.py' --mode '${mode}' --output-dir '${out_dir}' ${extra_args}
      echo \"[finish] \$(date -Is)\"
    ) > '${log}' 2>&1
    status=\$?
    if [[ \$status -eq 0 ]]; then
      curl -s -d \"Coyote original example ${mode} PASSED: out=${out_dir} log=${log}\" ntfy.sh/${NTFY_TOPIC} >/dev/null || true
    else
      curl -s -d \"Coyote original example ${mode} FAILED status=\$status: out=${out_dir} log=${log}\" ntfy.sh/${NTFY_TOPIC} >/dev/null || true
    fi
    exit \$status
  "

  echo "session=${session}"
  echo "out=${out_dir}"
  echo "log=${log}"
  echo "attach: tmux attach -t ${session}"
  echo "tail: tail -f ${log}"
}

for mode in ${MODES}; do
  case "${mode}" in
    io_parallel)
      launch_one "io_parallel" "${IO_PARALLEL_ARGS}"
      ;;
    io_stream)
      launch_one "io_stream" "${IO_STREAM_ARGS}"
      ;;
    *)
      echo "unknown mode: ${mode}" >&2
      exit 1
      ;;
  esac
done

echo "run_id=${RUN_ID}"
echo "parent=${OUT_PARENT}/${RUN_ID}"
