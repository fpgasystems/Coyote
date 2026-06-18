#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/pub/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/hls4ml}"
SESSION="${1:-hls4ml_selected_feasible_artifact_recovery}"
LOG_ROOT="${2:-$ROOT/logs/selected_feasible_artifact_recovery/$(date +%Y%m%d_%H%M%S)}"
TOPIC="${TOPIC:-coyote-build-sdeheredia}"
PY="$ROOT/../.venv_hls4ml/bin/python"
XILINX_VERSION="${XILINX_VERSION:-2024.2}"
CONFIG_DIR="configs/hls4ml_selected_feasible_candidates_artifact_recovery"
RESULTS_DIR="results/selected_feasible_candidates"

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

p = Path("results/selected_feasible_candidates/suite_status.csv")
rows = list(csv.DictReader(p.open())) if p.exists() else []
counts = collections.Counter(row.get("status", "") for row in rows)
print("rows=" + str(len(rows)) + " " + " ".join(f"{k}={v}" for k, v in sorted(counts.items())))
PY
}

copy_root() {
  local src="$1"
  local dst="$2"

  if [ ! -d "$src" ]; then
    echo "[selected-recovery] missing source: $src" >&2
    return 1
  fi
  mkdir -p "$dst"
  echo "[selected-recovery] restore copy src=$src dst=$dst"
  rsync -a --ignore-existing "$src/" "$dst/"
}

prepare_configs() {
  "$PY" - <<'PY'
from __future__ import annotations

from pathlib import Path
import csv

from pipeline.experiment_suite import load_yaml, metadata_for_config, write_csv, write_yaml

CONFIG_DIR = Path("configs/hls4ml_selected_feasible_candidates_artifact_recovery")
BASE_CONFIG_DIR = Path("configs/hls4ml_selected_feasible_candidates")
CONFIG_DIR.mkdir(parents=True, exist_ok=True)
for old in CONFIG_DIR.glob("*.yaml"):
    old.unlink()

runs = {
    "res128_layers6_W8A8_P0_RFbase": Path("artifacts_selected_feasible_candidates/cnn_small_hls_opt_img128/notebook_qat/res128_layers6_W8A8_P0_RFbase_94343a3be5ee"),
    "res128_layers6_W8A8_P50_RFbase": Path("artifacts_selected_feasible_candidates/cnn_small_hls_opt_img128/notebook_pruned_qat/res128_layers6_W8A8_P50_RFbase_f91e4f03fa27"),
    "res256_layers6_W8A8_P0_RFbase": Path("artifacts_selected_feasible_candidates/cnn_small_hls_opt_img256/notebook_qat/res256_layers6_W8A8_P0_RFbase_113ad7c2b86d"),
    "res256_layers6_W8A8_P50_RFbase": Path("artifacts_selected_feasible_candidates/cnn_small_hls_opt_img256/notebook_pruned_qat/res256_layers6_W8A8_P50_RFbase_e7705f9077f8"),
    "res256_layers7_W8A8_P50_RFbase": Path("artifacts_selected_feasible_candidates/cnn_small_hls_opt_img256/notebook_pruned_qat/res256_layers7_W8A8_P50_RFbase_74abd8967440"),
    "res512_layers7_W8A8_P50_RFbase": Path("artifacts_selected_feasible_candidates/cnn_small_hls_opt_img512/notebook_pruned_qat/res512_layers7_W8A8_P50_RFbase_b3a09a3d898b"),
}

rows = []
for name, run_root in runs.items():
    source = BASE_CONFIG_DIR / f"{name}.yaml"
    if not source.exists():
        raise FileNotFoundError(source)
    if not run_root.exists():
        raise FileNotFoundError(run_root)
    if not (run_root / "fold_0" / "final_weights.weights.h5").exists():
        raise FileNotFoundError(run_root / "fold_0" / "final_weights.weights.h5")
    cfg = load_yaml(source)
    cfg.setdefault("training", {})
    cfg["training"]["allow_stale_fold_cache"] = True
    cfg.setdefault("experiment", {})
    cfg["experiment"]["selected_run_root"] = str(run_root.resolve())
    cfg["experiment"]["artifact_recovery"] = True
    cfg["experiment"]["artifact_recovery_source_config"] = str(source)
    out = CONFIG_DIR / source.name
    write_yaml(out, cfg)
    meta = metadata_for_config(cfg, out)
    rows.append(
        {
            "experiment_name": name,
            "phase": meta["phase"],
            "selected_run_root": str(run_root.resolve()),
            "config_path": str(out),
        }
    )

write_csv(
    Path("results/selected_feasible_candidates/artifact_recovery_manifest.csv"),
    rows,
    fieldnames=["experiment_name", "phase", "selected_run_root", "config_path"],
)
print(f"[selected-recovery] prepared configs={len(rows)} dir={CONFIG_DIR}")
PY
}

verify_outputs() {
  "$PY" - <<'PY'
from __future__ import annotations

from pathlib import Path
import csv

manifest = Path("results/selected_feasible_candidates/artifact_recovery_manifest.csv")
rows = list(csv.DictReader(manifest.open()))
failures = []
for row in rows:
    root = Path(row["selected_run_root"])
    if not (root / "fold_0" / "final_weights.weights.h5").exists():
        failures.append(f"{row['experiment_name']}: missing fold_0/final_weights.weights.h5")
    if not (root / "pooled" / "metrics_summary.json").exists():
        failures.append(f"{row['experiment_name']}: missing pooled/metrics_summary.json")
    hls_dirs = sorted((root / "hls_sweeps").glob("RFbase_hls_*"))
    complete = [
        hls
        for hls in hls_dirs
        if (hls / "synthesis_summary.csv").exists() and (hls / "hls_metrics_summary.json").exists()
    ]
    if not complete:
        failures.append(f"{row['experiment_name']}: missing complete RFbase_hls_* summary")

if failures:
    raise SystemExit("\n".join(failures))
print(f"[selected-recovery] verified recovered outputs={len(rows)}")
PY
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
    --extra configs/hls4ml_expand_sweep results/expand_sweep \
    --snapshot
}

trap 'status=$?; notify "selected feasible artifact recovery FAILED status=$status session=$SESSION log=$LOG_ROOT/supervisor.log"; exit $status' ERR

echo "[selected-recovery] launched session=$SESSION logs=$LOG_ROOT"
notify "selected feasible artifact recovery launched: session=$SESSION logs=$LOG_ROOT"

copy_root \
  "artifacts_hand_optimized/cnn_small_hls_opt_img128/notebook_qat/res128_layers6_W8A8_P0_RFbase_94343a3be5ee" \
  "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img128/notebook_qat/res128_layers6_W8A8_P0_RFbase_94343a3be5ee"
copy_root \
  "artifacts_hand_optimized/cnn_small_hls_opt_img128/notebook_pruned_qat/res128_layers6_W8A8_P50_RFbase_f91e4f03fa27" \
  "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img128/notebook_pruned_qat/res128_layers6_W8A8_P50_RFbase_f91e4f03fa27"
copy_root \
  "artifacts_layer6_ext/cnn_small_hls_opt_img256/notebook_qat/res256_layers6_W8A8_P0_RFbase_113ad7c2b86d" \
  "artifacts_selected_feasible_candidates/cnn_small_hls_opt_img256/notebook_qat/res256_layers6_W8A8_P0_RFbase_113ad7c2b86d"

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

echo "[selected-recovery] start hls jobs=3 config_dir=$CONFIG_DIR"
notify "selected feasible artifact recovery HLS started: configs=6 jobs=3 session=$SESSION logs=$LOG_ROOT/hls"
"$PY" scripts/run_experiment_configs_parallel.py \
  --configs "$CONFIG_DIR" \
  --phases 4,4.5 \
  --stages hls \
  --results-dir "$RESULTS_DIR" \
  --log-dir "$LOG_ROOT/hls" \
  --jobs 3 \
  --hls-timeout 10h \
  --force-fingerprint

"$PY" scripts/collect_experiment_results.py \
  --configs configs/hls4ml_selected_feasible_candidates \
  --artifacts artifacts_selected_feasible_candidates \
  --results-dir "$RESULTS_DIR"
verify_outputs
aggregate_global

echo "[selected-recovery] complete $(status_summary) logs=$LOG_ROOT"
notify "selected feasible artifact recovery complete: $(status_summary) session=$SESSION results=$ROOT/$RESULTS_DIR"
