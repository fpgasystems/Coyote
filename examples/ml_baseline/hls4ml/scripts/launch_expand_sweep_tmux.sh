#!/usr/bin/env bash
set -euo pipefail

ROOT="/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml"
SESSION="${1:-hls4ml_expand_sweep}"
TOPIC="coyote-build-sdeheredia"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_ROOT="$ROOT/logs/expand_sweep/$TS"
PY="$ROOT/../.venv_hls4ml/bin/python"
XILINX_VERSION="${XILINX_VERSION:-2024.2}"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "tmux session already exists: $SESSION" >&2
  exit 1
fi

mkdir -p "$LOG_ROOT"

tmux new-session -d -s "$SESSION" bash -lc "
set -euo pipefail
cd '$ROOT'
mkdir -p '$LOG_ROOT'
notify() { curl -s -d \"\$*\" ntfy.sh/$TOPIC >/dev/null || true; }
run_phase() {
  local label=\"\$1\"
  local config_dir=\"\$2\"
  local phases=\"\$3\"
  local stages=\"\$4\"
  local log_dir=\"$LOG_ROOT/\$label\"
  mkdir -p \"\$log_dir\"
  local count
  count=\$(find \"\$config_dir\" -maxdepth 1 -name '*.yaml' 2>/dev/null | wc -l)
  echo \"[expand] \$label pending=\$count configs=\$config_dir stages=\$stages\"
  if [ \"\$count\" -eq 0 ]; then
    echo \"[expand] skip \$label: no pending configs\"
    return 0
  fi
  notify \"expand sweep \$label started: pending=\$count session=$SESSION logs=\$log_dir\"
  '$PY' scripts/run_experiment_configs_parallel.py \
    --configs \"\$config_dir\" \
    --phases \"\$phases\" \
    --stages \"\$stages\" \
    --results-dir results/expand_sweep \
    --log-dir \"\$log_dir\" \
    --jobs 8 \
    --hls-timeout 10h \
    --force-fingerprint
  notify \"expand sweep \$label finished: session=$SESSION logs=\$log_dir\"
}
collect_expand() {
  '$PY' scripts/collect_experiment_results.py \
    --configs configs/hls4ml_expand_sweep \
    --artifacts artifacts_expand_sweep \
    --results-dir results/expand_sweep
}
aggregate_global() {
  '$PY' scripts/stable_collect_global.py \
    --base-configs configs/hls4ml_experiment \
    --base-results results \
    --global-configs configs/hls4ml_experiment_global \
    --global-results results \
    --artifacts artifacts \
    --extra configs/hls4ml_experiment_layer6_ext results_layer6_ext \
    --extra configs/hls4ml_experiment_layer7_ext results_layer7_ext \
    --extra configs/hls4ml_experiment_2048x6 results_2048x6 \
    --extra configs/hls4ml_selected_feasible_candidates results/selected_feasible_candidates \
    --extra configs/hls4ml_expand_sweep results/expand_sweep \
    --snapshot
}
trap 'status=\$?; notify \"expand sweep FAILED status=\$status session=$SESSION log=$LOG_ROOT/supervisor.log\"; exit \$status' ERR
exec > >(tee -a '$LOG_ROOT/supervisor.log') 2>&1
notify \"expand sweep launched: session=$SESSION logs=$LOG_ROOT\"
export CLI_PATH=/opt/hdev/cli
export TERM=\${TERM:-xterm}
set +u
source \"/tools/Xilinx/Vivado/$XILINX_VERSION/settings64.sh\"
source \"/tools/Xilinx/Vitis/$XILINX_VERSION/settings64.sh\"
source \"/tools/Xilinx/Vitis_HLS/$XILINX_VERSION/settings64.sh\"
set -u
export HLS4ML_RUN_TOOLCHAIN_ENABLED=1
which vitis_hls
which vivado
'$PY' scripts/prepare_expand_sweep.py prepare
run_phase phase4 configs/hls4ml_expand_sweep_pending/phase4 4 train,hls
collect_expand
'$PY' scripts/prepare_expand_sweep.py prepare
run_phase phase45 configs/hls4ml_expand_sweep_pending/phase45 4.5 train,hls
collect_expand
'$PY' scripts/prepare_expand_sweep.py phase5
run_phase phase5 configs/hls4ml_expand_sweep_pending/phase5 5 hls
collect_expand
aggregate_global
'$PY' scripts/prepare_expand_sweep.py update-doc
notify \"expand sweep complete: session=$SESSION logs=$LOG_ROOT results=$ROOT/results/expand_sweep\"
echo \"[expand] complete logs=$LOG_ROOT\"
"

echo "session=$SESSION"
echo "attach=tmux attach -t $SESSION"
echo "log=$LOG_ROOT/supervisor.log"
