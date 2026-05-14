#!/usr/bin/env bash
set -uo pipefail

SESSION_NAME="${1:?session name required}"
LOG_ROOT="${2:?log root required}"
RETRY_CONFIG_DIR="${3:?retry config dir required}"
XILINX_VERSION="${XILINX_VERSION:-2024.2}"

cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml

notify() {
  curl -s -d "$*" ntfy.sh/coyote-build-sdeheredia >/dev/null || true
}

mkdir -p "$LOG_ROOT"
exec >> "$LOG_ROOT/supervisor.log" 2>&1

rc=0
{
  set -e
  echo "[retry] started session=$SESSION_NAME log=$LOG_ROOT/supervisor.log"
  notify "resource RF retry launched: res512_layers7_W8A8_P50_RFResource1 session=$SESSION_NAME logs=$LOG_ROOT"

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

  ../.venv_hls4ml/bin/python scripts/run_experiment_configs_parallel.py \
    --configs "$RETRY_CONFIG_DIR" \
    --phases 5 \
    --stages hls \
    --results-dir results/selected_feasible_candidates_resource_strategy \
    --log-dir "$LOG_ROOT" \
    --jobs 1 \
    --hls-timeout 10h \
    --force-fingerprint

  ../.venv_hls4ml/bin/python scripts/collect_experiment_results.py \
    --configs configs/hls4ml_selected_feasible_candidates_resource_strategy \
    --artifacts artifacts_selected_feasible_candidates \
    --results-dir results/selected_feasible_candidates_resource_strategy

  ../.venv_hls4ml/bin/python scripts/prepare_resource_strategy_rf.py verify-outputs

  ../.venv_hls4ml/bin/python scripts/plot_experiment_results.py \
    --summary results/selected_feasible_candidates_resource_strategy/experiment_summary.csv \
    --output-dir results/selected_feasible_candidates_resource_strategy/plots
} || rc=$?

summary=$(
  ../.venv_hls4ml/bin/python - <<'PY'
import csv
import collections
from pathlib import Path

p = Path("results/selected_feasible_candidates_resource_strategy/suite_status.csv")
rows = list(csv.DictReader(p.open())) if p.exists() else []
counts = collections.Counter(r.get("status", "") for r in rows)
print("rows=" + str(len(rows)) + " " + " ".join(f"{k}={v}" for k, v in sorted(counts.items())))
PY
)

if [ "$rc" -eq 0 ]; then
  notify "resource RF retry complete: $summary session=$SESSION_NAME results=/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/results/selected_feasible_candidates_resource_strategy"
  echo "[retry] complete $summary"
else
  notify "resource RF retry FAILED status=$rc summary=$summary session=$SESSION_NAME log=$LOG_ROOT/supervisor.log"
  echo "[retry] FAILED status=$rc $summary"
fi

exit "$rc"
