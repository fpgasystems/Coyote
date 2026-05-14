#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml}"
SESSION="${1:-hls4ml_2048x6_recovery_after_current}"
LOG_ROOT="${2:-$ROOT/logs/2048x6_recovery_after_current/$(date +%Y%m%d_%H%M%S)}"
TOPIC="${TOPIC:-coyote-build-sdeheredia}"
PY="$ROOT/../.venv_hls4ml/bin/python"
XILINX_VERSION="${XILINX_VERSION:-2024.2}"
JOBS="${JOBS:-6}"
WAIT_SESSIONS="${WAIT_SESSIONS:-hls4ml_selected_feasible_artifact_recovery_retry_20260514_173253 hls4ml_expand_phase5_p50_recovery_20260514_175657}"
PHASE4_CONFIG_DIR="configs/hls4ml_2048x6_recovery_phase4"
PHASE5_CONFIG_DIR="configs/hls4ml_2048x6_recovery_phase5"
RESULTS_DIR="results_2048x6"

cd "$ROOT"
mkdir -p "$LOG_ROOT"
exec > >(tee -a "$LOG_ROOT/supervisor.log") 2>&1

notify() {
  curl -s -d "$*" "ntfy.sh/$TOPIC" >/dev/null || true
}

status_summary() {
  "$PY" - <<'PY'
from pathlib import Path
import csv, collections
p = Path("results_2048x6/suite_status.csv")
rows = list(csv.DictReader(p.open())) if p.exists() else []
counts = collections.Counter(row.get("status", "") for row in rows)
print("rows=" + str(len(rows)) + " " + " ".join(f"{k}={v}" for k, v in sorted(counts.items())))
PY
}

wait_for_sessions() {
  while true; do
    local alive=()
    for session in $WAIT_SESSIONS; do
      if tmux has-session -t "$session" 2>/dev/null; then
        alive+=("$session")
      fi
    done
    if [ "${#alive[@]}" -eq 0 ]; then
      break
    fi
    echo "[2048x6-recovery] waiting for active sessions: ${alive[*]}"
    sleep 300
  done
}

prepare_configs() {
  "$PY" - <<'PY'
from pathlib import Path
import shutil

src = Path("configs/hls4ml_experiment_2048x6")
phase4 = Path("configs/hls4ml_2048x6_recovery_phase4")
phase5 = Path("configs/hls4ml_2048x6_recovery_phase5")
for dst in [phase4, phase5]:
    dst.mkdir(parents=True, exist_ok=True)
    for old in dst.glob("*.yaml"):
        old.unlink()
phase4_names = [
    "res2048_layers6_W3A3_P0_RFbase",
    "res2048_layers6_W4A4_P0_RFbase",
    "res2048_layers6_W6A6_P0_RFbase",
]
phase5_names = [
    "res2048_layers6_W8A8_P50_RF1",
    "res2048_layers6_W8A8_P50_RF2",
    "res2048_layers6_W8A8_P50_RF4",
    "res2048_layers6_W8A8_P50_RF8",
    "res2048_layers6_W8A8_P50_RF16",
    "res2048_layers6_W8A8_P50_RF32",
]
for name in phase4_names:
    shutil.copy2(src / f"{name}.yaml", phase4 / f"{name}.yaml")
for name in phase5_names:
    shutil.copy2(src / f"{name}.yaml", phase5 / f"{name}.yaml")
print(f"[2048x6-recovery] prepared phase4={len(phase4_names)} phase5={len(phase5_names)}")
PY
}

collect_2048() {
  "$PY" scripts/collect_experiment_results.py \
    --configs configs/hls4ml_experiment_2048x6 \
    --artifacts artifacts_2048x6 \
    --results-dir "$RESULTS_DIR"
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

verify_outputs() {
  "$PY" - <<'PY'
from pathlib import Path

failures = []
for name in [
    "res2048_layers6_W3A3_P0_RFbase_87dd0ffcd5fc",
    "res2048_layers6_W4A4_P0_RFbase_57e4efedd19b",
    "res2048_layers6_W6A6_P0_RFbase_0294fcff25de",
]:
    root = Path("artifacts_2048x6/cnn_small_hls_opt_img2048/notebook_qat") / name
    complete = [
        hls for hls in sorted((root / "hls_sweeps").glob("RFbase_hls_*"))
        if (hls / "synthesis_summary.csv").exists() and (hls / "hls_metrics_summary.json").exists()
    ]
    if not complete:
        failures.append(f"{name}: missing complete RFbase_hls_*")

root = Path("artifacts_2048x6/cnn_small_hls_opt_img2048/notebook_pruned_qat/res2048_layers6_W8A8_P50_RFbase_20acfc65367c")
for rf in [1, 2, 4, 8, 16, 32]:
    complete = [
        hls for hls in sorted((root / "hls_sweeps").glob(f"RF{rf}_hls_*"))
        if (hls / "synthesis_summary.csv").exists() and (hls / "hls_metrics_summary.json").exists()
    ]
    if not complete:
        failures.append(f"res2048_layers6_W8A8_P50_RF{rf}: missing complete hls summary")
if failures:
    raise SystemExit("\n".join(failures))
print("[2048x6-recovery] verified phase4 RFbase and phase5 RF sweeps")
PY
}

trap 'status=$?; notify "2048x6 recovery FAILED status=$status session=$SESSION log=$LOG_ROOT/supervisor.log"; exit $status' ERR

echo "[2048x6-recovery] queued session=$SESSION logs=$LOG_ROOT jobs=$JOBS"
notify "2048x6 recovery queued after current sessions: session=$SESSION jobs=$JOBS logs=$LOG_ROOT"
wait_for_sessions
echo "[2048x6-recovery] dependencies clear; starting recovery"
notify "2048x6 recovery starting: session=$SESSION jobs=$JOBS logs=$LOG_ROOT"
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

echo "[2048x6-recovery] phase4 train,hls jobs=$JOBS"
"$PY" scripts/run_experiment_configs_parallel.py \
  --configs "$PHASE4_CONFIG_DIR" \
  --phases 4 \
  --stages train,hls \
  --results-dir "$RESULTS_DIR" \
  --log-dir "$LOG_ROOT/phase4" \
  --jobs "$JOBS" \
  --hls-timeout 10h \
  --force-fingerprint

collect_2048

echo "[2048x6-recovery] phase5 hls jobs=$JOBS"
"$PY" scripts/run_experiment_configs_parallel.py \
  --configs "$PHASE5_CONFIG_DIR" \
  --phases 5 \
  --stages hls \
  --results-dir "$RESULTS_DIR" \
  --log-dir "$LOG_ROOT/phase5" \
  --jobs "$JOBS" \
  --hls-timeout 10h \
  --force-fingerprint

collect_2048
verify_outputs
aggregate_global

echo "[2048x6-recovery] complete $(status_summary) logs=$LOG_ROOT"
notify "2048x6 recovery complete: $(status_summary) session=$SESSION"
