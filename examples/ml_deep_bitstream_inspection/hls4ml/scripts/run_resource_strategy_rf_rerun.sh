#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/pub/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/hls4ml}"
SESSION="${1:-hls4ml_resource_strategy_rf}"
LOG_ROOT="${2:-$ROOT/logs/selected_feasible_candidates_resource_strategy/$(date +%Y%m%d_%H%M%S)}"
TOPIC="${TOPIC:-coyote-build-sdeheredia}"
PY="$ROOT/../.venv_hls4ml/bin/python"
XILINX_VERSION="${XILINX_VERSION:-2024.2}"

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

p = Path("results/selected_feasible_candidates_resource_strategy/suite_status.csv")
rows = list(csv.DictReader(p.open())) if p.exists() else []
counts = collections.Counter(row.get("status", "") for row in rows)
print("rows=" + str(len(rows)) + " " + " ".join(f"{k}={v}" for k, v in sorted(counts.items())))
PY
}

run_wave() {
  local wave="$1"
  local config_dir="configs/hls4ml_selected_feasible_candidates_resource_strategy_waves/$wave"
  local log_dir="$LOG_ROOT/$wave"
  local count

  mkdir -p "$log_dir"
  count=$(find "$config_dir" -maxdepth 1 -name '*.yaml' | wc -l)
  echo "[resource-rf] start $wave configs=$count log_dir=$log_dir"
  notify "resource RF $wave started: configs=$count session=$SESSION logs=$log_dir"

  "$PY" scripts/run_experiment_configs_parallel.py \
    --configs "$config_dir" \
    --phases 5 \
    --stages hls \
    --results-dir results/selected_feasible_candidates_resource_strategy \
    --log-dir "$log_dir" \
    --jobs 6 \
    --hls-timeout 10h \
    --force \
    --force-fingerprint

  echo "[resource-rf] finished $wave $(status_summary)"
  notify "resource RF $wave finished: $(status_summary) session=$SESSION logs=$log_dir"
}

trap 'status=$?; notify "resource RF FAILED status=$status session=$SESSION log=$LOG_ROOT/supervisor.log"; exit $status' ERR

echo "[resource-rf] launched session=$SESSION logs=$LOG_ROOT"
notify "resource RF launched: session=$SESSION logs=$LOG_ROOT"

export CLI_PATH=/opt/hdev/cli
export TERM="${TERM:-xterm}"
set +u
source "/tools/Xilinx/Vivado/${XILINX_VERSION}/settings64.sh"
source "/tools/Xilinx/Vitis/${XILINX_VERSION}/settings64.sh"
source "/tools/Xilinx/Vitis_HLS/${XILINX_VERSION}/settings64.sh"
set -u
export HLS4ML_RUN_TOOLCHAIN_ENABLED=1
which vitis_hls
which vivado

"$PY" scripts/prepare_resource_strategy_rf.py prepare
run_wave wave1_rf32_rf16
notify "resource RF first wave complete: $(status_summary) session=$SESSION logs=$LOG_ROOT/wave1_rf32_rf16"
run_wave wave2_rf8_rf4
run_wave wave3_rf2_rf1

"$PY" scripts/collect_experiment_results.py \
  --configs configs/hls4ml_selected_feasible_candidates_resource_strategy \
  --artifacts artifacts_selected_feasible_candidates \
  --results-dir results/selected_feasible_candidates_resource_strategy
"$PY" scripts/prepare_resource_strategy_rf.py verify-outputs
"$PY" scripts/plot_experiment_results.py \
  --summary results/selected_feasible_candidates_resource_strategy/experiment_summary.csv \
  --output-dir results/selected_feasible_candidates_resource_strategy/plots

echo "[resource-rf] complete $(status_summary) logs=$LOG_ROOT"
notify "resource RF complete: $(status_summary) session=$SESSION results=$ROOT/results/selected_feasible_candidates_resource_strategy"
