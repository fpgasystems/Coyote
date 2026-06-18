#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/pub/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/hls4ml}"
SESSION="${1:-hls4ml_expand_phase5_p50_recovery}"
LOG_ROOT="${2:-$ROOT/logs/expand_phase5_p50_recovery/$(date +%Y%m%d_%H%M%S)}"
TOPIC="${TOPIC:-coyote-build-sdeheredia}"
PY="$ROOT/../.venv_hls4ml/bin/python"
XILINX_VERSION="${XILINX_VERSION:-2024.2}"
JOBS="${JOBS:-3}"
CONFIG_SRC="configs/hls4ml_expand_sweep_pending/phase5"
CONFIG_DIR="configs/hls4ml_expand_phase5_p50_recovery"
RESULTS_DIR="results/expand_sweep"

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
p = Path("results/expand_sweep/suite_status.csv")
rows = list(csv.DictReader(p.open())) if p.exists() else []
counts = collections.Counter(row.get("status", "") for row in rows)
print("rows=" + str(len(rows)) + " " + " ".join(f"{k}={v}" for k, v in sorted(counts.items())))
PY
}

prepare_configs() {
  "$PY" - <<'PY'
from pathlib import Path
from pipeline.experiment_suite import load_yaml, write_yaml

src = Path("configs/hls4ml_expand_sweep_pending/phase5")
dst = Path("configs/hls4ml_expand_phase5_p50_recovery")
dst.mkdir(parents=True, exist_ok=True)
for old in dst.glob("*.yaml"):
    old.unlink()
names = [
    "res1024_layers5_W6A6_P50_RF1",
    "res1024_layers5_W6A6_P50_RF2",
    "res1024_layers5_W6A6_P50_RF4",
    "res1024_layers5_W6A6_P50_RF8",
    "res1024_layers5_W6A6_P50_RF16",
    "res1024_layers5_W6A6_P50_RF32",
]
for name in names:
    source = src / f"{name}.yaml"
    if not source.exists():
        raise FileNotFoundError(source)
    cfg = load_yaml(source)
    cfg.setdefault("training", {})
    cfg["training"]["allow_stale_fold_cache"] = True
    cfg.setdefault("experiment", {})
    cfg["experiment"]["recovery_allow_stale_fold_cache"] = True
    write_yaml(dst / source.name, cfg)
print(f"[expand-p50] prepared configs={len(names)} dir={dst}")
PY
}

verify_outputs() {
  "$PY" - <<'PY'
from pathlib import Path
import sys

root = Path("artifacts/cnn_small_hls_opt_img1024/notebook_pruned_qat/res1024_layers5_W6A6_P50_RFbase_99018e551242")
failures = []
for rf in [1, 2, 4, 8, 16, 32]:
    complete = [
        hls for hls in sorted((root / "hls_sweeps").glob(f"RF{rf}_hls_*"))
        if (hls / "synthesis_summary.csv").exists() and (hls / "hls_metrics_summary.json").exists()
    ]
    if not complete:
        failures.append(f"RF{rf}: missing complete hls summary under {root / 'hls_sweeps'}")
if failures:
    raise SystemExit("\n".join(failures))
print("[expand-p50] verified RF1,RF2,RF4,RF8,RF16,RF32")
PY
}

trap 'status=$?; notify "expand phase5 P50 recovery FAILED status=$status session=$SESSION log=$LOG_ROOT/supervisor.log"; exit $status' ERR

echo "[expand-p50] launched session=$SESSION logs=$LOG_ROOT jobs=$JOBS"
notify "expand phase5 P50 recovery launched: session=$SESSION jobs=$JOBS logs=$LOG_ROOT"
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
  --log-dir "$LOG_ROOT/hls" \
  --jobs "$JOBS" \
  --hls-timeout 10h \
  --force-fingerprint

"$PY" scripts/collect_experiment_results.py \
  --configs configs/hls4ml_expand_sweep \
  --artifacts artifacts_expand_sweep \
  --results-dir "$RESULTS_DIR"

verify_outputs
echo "[expand-p50] complete $(status_summary) logs=$LOG_ROOT"
notify "expand phase5 P50 recovery complete: $(status_summary) session=$SESSION"
