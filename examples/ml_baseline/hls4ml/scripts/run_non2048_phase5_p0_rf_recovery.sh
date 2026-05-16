#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml}"
SESSION="${SESSION:-hls4ml_non2048_phase5_p0_rf_recovery}"
LOG_ROOT="${LOG_ROOT:-$ROOT/logs/non2048_phase5_p0_rf_recovery/$(date +%Y%m%d_%H%M%S)}"
TOPIC="${TOPIC:-coyote-build-sdeheredia}"
PY="$ROOT/../.venv_hls4ml/bin/python"
XILINX_VERSION="${XILINX_VERSION:-2024.2}"
JOBS="${JOBS:-6}"
CONFIG_DIR="configs/hls4ml_non2048_phase5_p0_rf_recovery"
RESULTS_DIR="results/non2048_phase5_p0_rf_recovery"

cd "$ROOT"
mkdir -p "$LOG_ROOT" "$RESULTS_DIR"
exec > >(tee -a "$LOG_ROOT/supervisor.log") 2>&1

notify() {
  curl -s -d "$*" "ntfy.sh/$TOPIC" >/dev/null || true
}

status_summary() {
  "$PY" - <<'PY'
from pathlib import Path
import csv
from collections import Counter

p = Path("results/non2048_phase5_p0_rf_recovery/suite_status.csv")
rows = list(csv.DictReader(p.open())) if p.exists() else []
counts = Counter(row.get("status", "") for row in rows)
print("rows=" + str(len(rows)) + " " + " ".join(f"{k}={v}" for k, v in sorted(counts.items())))
PY
}

prepare_configs() {
  "$PY" - <<'PY'
from pathlib import Path
import csv
import sys

sys.path.insert(0, str(Path(".").resolve()))

from pipeline.experiment_suite import load_yaml, write_yaml
from pipeline.notebook_flow import build_context, load_config

names = [f"res1024_layers5_W6A6_P0_RF{rf}" for rf in [1, 2, 4, 8, 16, 32]]
config_dir = Path("configs/hls4ml_non2048_phase5_p0_rf_recovery")
results_dir = Path("results/non2048_phase5_p0_rf_recovery")
config_dir.mkdir(parents=True, exist_ok=True)
results_dir.mkdir(parents=True, exist_ok=True)

manifest_rows = []
prepared = []
skipped = []

for name in names:
    src = Path("configs/hls4ml_experiment_global") / f"{name}.yaml"
    if not src.exists():
        src = Path("configs/hls4ml_experiment") / f"{name}.yaml"
    if not src.exists():
        raise FileNotFoundError(f"missing source config for {name}")

    cfg = load_yaml(src)
    selected_run_root = Path(cfg["experiment"]["selected_run_root"])
    if not selected_run_root.exists():
        raise FileNotFoundError(f"{name}: selected_run_root missing: {selected_run_root}")

    sweep_name = str(cfg.get("hls", {}).get("sweep_name", ""))
    complete = [
        path for path in sorted((selected_run_root / "hls_sweeps").glob(f"{sweep_name}_hls_*"))
        if (path / "synthesis_summary.csv").exists() and (path / "hls_metrics_summary.json").exists()
    ]
    if complete:
        skipped.append(name)
        manifest_rows.append(
            {
                "experiment_name": name,
                "source_config": str(src),
                "recovery_config": "",
                "selected_run_root": str(selected_run_root),
                "status": "skipped_existing_complete",
                "existing_hls_sweep_root": str(complete[-1]),
            }
        )
        continue

    cfg.setdefault("training", {})
    cfg["training"]["allow_stale_fold_cache"] = True
    cfg.setdefault("experiment", {})
    cfg["experiment"]["recovery_allow_stale_fold_cache"] = True
    cfg["experiment"]["recovery_note"] = "non-2048 phase5 P0 RF HLS recovery with force-fingerprint"

    dst = config_dir / src.name
    write_yaml(dst, cfg)

    check_cfg = load_config(dst)
    ctx = build_context(check_cfg, config_path=dst.resolve(), run_root_arg=selected_run_root)
    manifest_rows.append(
        {
            "experiment_name": name,
            "source_config": str(src),
            "recovery_config": str(dst),
            "selected_run_root": str(ctx.run_root),
            "status": "prepared",
            "existing_hls_sweep_root": "",
        }
    )
    prepared.append(name)

with (results_dir / "recovery_manifest.csv").open("w", newline="") as handle:
    fieldnames = [
        "experiment_name",
        "source_config",
        "recovery_config",
        "selected_run_root",
        "status",
        "existing_hls_sweep_root",
    ]
    writer = csv.DictWriter(handle, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(manifest_rows)

print(f"[non2048-p0-rf] prepared={len(prepared)} skipped_existing={len(skipped)} config_dir={config_dir}")
for name in prepared:
    print(f"[non2048-p0-rf] prepared {name}")
for name in skipped:
    print(f"[non2048-p0-rf] skipped existing complete {name}")
PY
}

pending_count() {
  find "$CONFIG_DIR" -maxdepth 1 -type f -name 'res1024_layers5_W6A6_P0_RF*.yaml' | wc -l | tr -d ' '
}

collect_recovery() {
  "$PY" scripts/collect_experiment_results.py \
    --configs "$CONFIG_DIR" \
    --artifacts artifacts \
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
    --extra "$CONFIG_DIR" "$RESULTS_DIR" \
    --snapshot
}

verify_outputs() {
  "$PY" - <<'PY'
from pathlib import Path
import csv
import sys

manifest = Path("results/non2048_phase5_p0_rf_recovery/recovery_manifest.csv")
rows = list(csv.DictReader(manifest.open()))
failures = []
for row in rows:
    if row["status"] == "skipped_existing_complete":
        continue
    root = Path(row["selected_run_root"])
    name = row["experiment_name"]
    rf = name.rsplit("_", 1)[-1]
    complete = [
        hls for hls in sorted((root / "hls_sweeps").glob(f"{rf}_hls_*"))
        if (hls / "synthesis_summary.csv").exists() and (hls / "hls_metrics_summary.json").exists()
    ]
    if not complete:
        failures.append(f"{name}: missing complete HLS summaries under {root / 'hls_sweeps'}")
if failures:
    raise SystemExit("\n".join(failures))
print("[non2048-p0-rf] verified all prepared RF sweeps have HLS summaries")
PY
}

trap 'status=$?; notify "non2048 phase5 P0 RF recovery FAILED status=$status session=$SESSION log=$LOG_ROOT/supervisor.log"; exit $status' ERR

echo "[non2048-p0-rf] launched session=$SESSION logs=$LOG_ROOT jobs=$JOBS"
notify "non2048 phase5 P0 RF recovery launched: session=$SESSION jobs=$JOBS logs=$LOG_ROOT"
prepare_configs

if [[ "$(pending_count)" == "0" ]]; then
  echo "[non2048-p0-rf] no pending configs; collecting and aggregating existing outputs"
  collect_recovery
  aggregate_global
  notify "non2048 phase5 P0 RF recovery complete: no pending configs session=$SESSION"
  exit 0
fi

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

collect_recovery
verify_outputs
aggregate_global

summary="$(status_summary)"
echo "[non2048-p0-rf] complete $summary logs=$LOG_ROOT"
notify "non2048 phase5 P0 RF recovery complete: $summary session=$SESSION"
