#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/pub/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/hls4ml}"
SESSION="${1:-hls4ml_2048x6_phase5_topup}"
LOG_ROOT="${2:-$ROOT/logs/2048x6_phase5_topup/$(date +%Y%m%d_%H%M%S)}"
TOPIC="${TOPIC:-coyote-build-sdeheredia}"
PY="$ROOT/../.venv_hls4ml/bin/python"
XILINX_VERSION="${XILINX_VERSION:-2024.2}"
JOBS="${JOBS:-5}"
CONFIG_DIR="configs/hls4ml_2048x6_phase5_topup"
RESULTS_DIR="results_2048x6"

cd "$ROOT"
mkdir -p "$LOG_ROOT" "$CONFIG_DIR"
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

prepare_configs() {
  "$PY" - <<'PY'
from pathlib import Path
from pipeline.experiment_suite import load_yaml, write_yaml

src = Path("configs/hls4ml_experiment_2048x6")
dst = Path("configs/hls4ml_2048x6_phase5_topup")
dst.mkdir(parents=True, exist_ok=True)
for old in dst.glob("*.yaml"):
    old.unlink()

# Run high-RF jobs first; they are usually the cheaper HLS points and give
# quick resource-side coverage while the larger RF1/RF2 jobs remain queued.
ordered = [32, 16, 8, 4, 2, 1]
for index, rf in enumerate(ordered):
    name = f"res2048_layers6_W8A8_P50_RF{rf}"
    cfg = load_yaml(src / f"{name}.yaml")
    cfg.setdefault("training", {})
    cfg["training"]["allow_stale_fold_cache"] = True
    cfg.setdefault("experiment", {})
    cfg["experiment"]["recovery_allow_stale_fold_cache"] = True
    write_yaml(dst / f"{index:02d}_{name}.yaml", cfg)
print(f"[2048x6-topup] prepared phase5 configs={len(ordered)} dir={dst}")
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

root = Path("artifacts_2048x6/cnn_small_hls_opt_img2048/notebook_pruned_qat/res2048_layers6_W8A8_P50_RFbase_20acfc65367c")
failures = []
for rf in [1, 2, 4, 8, 16, 32]:
    complete = [
        hls for hls in sorted((root / "hls_sweeps").glob(f"RF{rf}_hls_*"))
        if (hls / "synthesis_summary.csv").exists() and (hls / "hls_metrics_summary.json").exists()
    ]
    if not complete:
        failures.append(f"res2048_layers6_W8A8_P50_RF{rf}: missing complete hls summary")
if failures:
    raise SystemExit("\n".join(failures))
print("[2048x6-topup] verified RF1,RF2,RF4,RF8,RF16,RF32")
PY
}

trap 'status=$?; notify "2048x6 phase5 top-up FAILED status=$status session=$SESSION log=$LOG_ROOT/supervisor.log"; exit $status' ERR

echo "[2048x6-topup] launched session=$SESSION logs=$LOG_ROOT jobs=$JOBS"
notify "2048x6 phase5 top-up launched: session=$SESSION jobs=$JOBS logs=$LOG_ROOT"
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

echo "[2048x6-topup] complete $(status_summary) logs=$LOG_ROOT"
notify "2048x6 phase5 top-up complete: $(status_summary) session=$SESSION"
