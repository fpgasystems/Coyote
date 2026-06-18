#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/pub/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/hls4ml}"
SESSION="${1:-hls4ml_recompute_results_pre_recovery}"
LOG_ROOT="${2:-$ROOT/logs/recompute_results_pre_recovery/$(date +%Y%m%d_%H%M%S)}"
TOPIC="${TOPIC:-coyote-build-sdeheredia}"
PY="$ROOT/../.venv_hls4ml/bin/python"

cd "$ROOT"
mkdir -p "$LOG_ROOT"
exec > >(tee -a "$LOG_ROOT/supervisor.log") 2>&1

notify() {
  curl -s -d "$*" "ntfy.sh/$TOPIC" >/dev/null || true
}

collect_suite() {
  local label="$1"
  local configs="$2"
  local artifacts="$3"
  local results="$4"
  echo "[recompute] collect $label configs=$configs artifacts=$artifacts results=$results"
  "$PY" scripts/collect_experiment_results.py \
    --configs "$configs" \
    --artifacts "$artifacts" \
    --results-dir "$results"
}

trap 'status=$?; notify "pre-recovery recompute FAILED status=$status session=$SESSION log=$LOG_ROOT/supervisor.log"; exit $status' ERR

echo "[recompute] launched session=$SESSION logs=$LOG_ROOT"
notify "pre-recovery recompute launched: session=$SESSION logs=$LOG_ROOT"

collect_suite "base" configs/hls4ml_experiment artifacts results
collect_suite "2048x6" configs/hls4ml_experiment_2048x6 artifacts_2048x6 results_2048x6
collect_suite "layer6_ext" configs/hls4ml_experiment_layer6_ext artifacts_layer6_ext results_layer6_ext
collect_suite "layer7_ext" configs/hls4ml_experiment_layer7_ext artifacts_layer7_ext results_layer7_ext
collect_suite "selected_feasible" configs/hls4ml_selected_feasible_candidates artifacts_selected_feasible_candidates results/selected_feasible_candidates
collect_suite "selected_feasible_resource_strategy" configs/hls4ml_selected_feasible_candidates_resource_strategy artifacts_selected_feasible_candidates results/selected_feasible_candidates_resource_strategy
collect_suite "selected_feasible_rf_p50_existing" configs/hls4ml_selected_feasible_candidates_rf_p50_existing/all artifacts_selected_feasible_candidates results/selected_feasible_candidates/rf_p50_existing
collect_suite "expand_sweep" configs/hls4ml_expand_sweep artifacts_expand_sweep results/expand_sweep

echo "[recompute] aggregate global"
"$PY" scripts/stable_collect_global.py \
  --base-configs configs/hls4ml_experiment \
  --base-results results \
  --global-configs configs/hls4ml_experiment_global \
  --global-results results \
  --artifacts artifacts \
  --extra configs/hls4ml_experiment_layer6_ext results_layer6_ext \
  --extra configs/hls4ml_experiment_layer7_ext results_layer7_ext \
  --extra configs/hls4ml_experiment_2048x6 results_2048x6 \
  --extra configs/hls4ml_selected_feasible_candidates results/selected_feasible_candidates \
  --extra configs/hls4ml_selected_feasible_candidates_resource_strategy results/selected_feasible_candidates_resource_strategy \
  --extra configs/hls4ml_selected_feasible_candidates_rf_p50_existing/all results/selected_feasible_candidates/rf_p50_existing \
  --extra configs/hls4ml_expand_sweep results/expand_sweep \
  --snapshot

plot_count="$(find results/plots -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
snapshot="$(find results/_snapshots -maxdepth 1 -type d -name '*_stable_collect_global' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)"
echo "[recompute] complete plots=$plot_count snapshot=$snapshot logs=$LOG_ROOT"
notify "pre-recovery recompute complete: plots=$plot_count snapshot=$snapshot session=$SESSION"
