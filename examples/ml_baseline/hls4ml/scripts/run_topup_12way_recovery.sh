#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml}"
SESSION="${1:-hls4ml_topup_12way_recovery}"
LOG_ROOT="${2:-$ROOT/logs/topup_12way_recovery/$(date +%Y%m%d_%H%M%S)}"
TOPIC="${TOPIC:-coyote-build-sdeheredia}"
PY="$ROOT/../.venv_hls4ml/bin/python"
XILINX_VERSION="${XILINX_VERSION:-2024.2}"
JOBS="${JOBS:-4}"
TS="$(basename "$LOG_ROOT")"
CONFIG_DIR="configs/hls4ml_topup_12way_recovery/$TS"
TEMP_RESULTS_DIR="results/topup_12way_recovery/$TS"
WAIT_FOR_COLLECT_SESSIONS="${WAIT_FOR_COLLECT_SESSIONS:-hls4ml_expand_phase5_p50_recovery_retry_20260514_180027 hls4ml_2048x6_phase5_topup_20260514_192508 hls4ml_2048x6_recovery_after_current_20260514_175937}"

cd "$ROOT"
mkdir -p "$LOG_ROOT" "$CONFIG_DIR" "$TEMP_RESULTS_DIR"
exec > >(tee -a "$LOG_ROOT/supervisor.log") 2>&1

notify() {
  curl -s -d "$*" "ntfy.sh/$TOPIC" >/dev/null || true
}

status_summary() {
  "$PY" - "$TEMP_RESULTS_DIR/suite_status.csv" <<'PY'
from pathlib import Path
import csv, collections, sys
p = Path(sys.argv[1])
rows = list(csv.DictReader(p.open())) if p.exists() else []
counts = collections.Counter(row.get("status", "") for row in rows)
print("rows=" + str(len(rows)) + " " + " ".join(f"{k}={v}" for k, v in sorted(counts.items())))
PY
}

wait_for_collect_safety() {
  while true; do
    local alive=()
    for session in $WAIT_FOR_COLLECT_SESSIONS; do
      if [ "$session" = "$SESSION" ]; then
        continue
      fi
      if tmux has-session -t "$session" 2>/dev/null; then
        alive+=("$session")
      fi
    done
    if [ "${#alive[@]}" -eq 0 ]; then
      break
    fi
    echo "[topup-12way] waiting to recollect; active result writers: ${alive[*]}"
    sleep 300
  done
}

prepare_configs() {
  "$PY" - <<'PY'
from pathlib import Path
import shutil
import os

ts = Path(os.environ["CONFIG_DIR"])
ts.mkdir(parents=True, exist_ok=True)
for old in ts.glob("*.yaml"):
    old.unlink()

sources = [
    (Path("configs/hls4ml_experiment_2048x6"), "res2048_layers6_W3A3_P0_RFbase"),
    (Path("configs/hls4ml_experiment_2048x6"), "res2048_layers6_W4A4_P0_RFbase"),
    (Path("configs/hls4ml_experiment_2048x6"), "res2048_layers6_W6A6_P0_RFbase"),
    (Path("configs/hls4ml_expand_sweep_recovery/phase45_train_hls"), "res512_layers7_W8A8_P50_RFbase"),
    (Path("configs/hls4ml_expand_sweep_recovery/phase45_train_hls"), "res512_layers7_W8A8_P75_RFbase"),
]
for index, (src_dir, name) in enumerate(sources):
    src = src_dir / f"{name}.yaml"
    if not src.exists():
        raise FileNotFoundError(src)
    shutil.copy2(src, ts / f"{index:02d}_{name}.yaml")
print(f"[topup-12way] prepared configs={len(sources)} dir={ts}")
PY
}

verify_outputs() {
  "$PY" - "$CONFIG_DIR" <<'PY'
from pathlib import Path
import sys

from pipeline.notebook_flow import build_context, load_config

config_dir = Path(sys.argv[1])
failures = []
for config_path in sorted(config_dir.glob("*.yaml")):
    cfg = load_config(config_path)
    selected_run_root = cfg.get("experiment", {}).get("selected_run_root")
    ctx = build_context(
        cfg,
        config_path=config_path.resolve(),
        run_root_arg=Path(selected_run_root) if selected_run_root else None,
    )
    run_root = Path(ctx.run_root)
    hls_root = Path(ctx.hls_sweep_root)
    if not (run_root / "fold_0" / "final_weights.weights.h5").exists():
        failures.append(f"{config_path.name}: missing fold_0 final weights under {run_root}")
    if not (hls_root / "synthesis_summary.csv").exists():
        failures.append(f"{config_path.name}: missing synthesis_summary.csv under {hls_root}")
    if not (hls_root / "hls_metrics_summary.json").exists():
        failures.append(f"{config_path.name}: missing hls_metrics_summary.json under {hls_root}")
if failures:
    raise SystemExit("\n".join(failures))
print(f"[topup-12way] verified configs={len(list(config_dir.glob('*.yaml')))}")
PY
}

collect_results() {
  "$PY" scripts/collect_experiment_results.py \
    --configs configs/hls4ml_experiment_2048x6 \
    --artifacts artifacts_2048x6 \
    --results-dir results_2048x6

  "$PY" scripts/collect_experiment_results.py \
    --configs configs/hls4ml_expand_sweep \
    --artifacts artifacts_expand_sweep \
    --results-dir results/expand_sweep
}

aggregate_global() {
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
}

trap 'status=$?; notify "12-way top-up recovery FAILED status=$status session=$SESSION log=$LOG_ROOT/supervisor.log"; exit $status' ERR

export CONFIG_DIR
echo "[topup-12way] launched session=$SESSION logs=$LOG_ROOT jobs=$JOBS temp_results=$TEMP_RESULTS_DIR"
notify "12-way top-up recovery launched: session=$SESSION jobs=$JOBS logs=$LOG_ROOT"
prepare_configs

export TERM="${TERM:-xterm}"
set +u
source "/tools/Xilinx/Vivado/${XILINX_VERSION}/settings64.sh"
source "/tools/Xilinx/Vitis/${XILINX_VERSION}/settings64.sh"
source "/tools/Xilinx/Vitis_HLS/${XILINX_VERSION}/settings64.sh"
set -u
export HLS4ML_RUN_TOOLCHAIN_ENABLED=1
which vitis_hls
which vivado

"$PY" scripts/run_experiment_configs_parallel.py \
  --configs "$CONFIG_DIR" \
  --phases 4,4.5 \
  --stages train,hls \
  --results-dir "$TEMP_RESULTS_DIR" \
  --log-dir "$LOG_ROOT/train_hls" \
  --jobs "$JOBS" \
  --hls-timeout 10h \
  --force-fingerprint

verify_outputs
notify "12-way top-up recovery jobs complete: $(status_summary) session=$SESSION; waiting to recollect if needed"
wait_for_collect_safety
collect_results
aggregate_global

echo "[topup-12way] complete $(status_summary) logs=$LOG_ROOT"
notify "12-way top-up recovery complete: $(status_summary) session=$SESSION"
