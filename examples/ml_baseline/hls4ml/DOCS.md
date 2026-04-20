# hls4ml Workspace — DOCS

Quick reference for the PyTorch-only hls4ml flow in
`examples/ml_baseline/hls4ml`. Everything is candidate-driven via
`configs/candidates.yaml` (default: `cnn_medium_img512`; also `cnn_medium`,
`cnn_b_img256`).

Python entry point: `../../ml_baseline/.venv_hls4ml/bin/python` (referred to as
`$PY` below). All commands assume `cwd = examples/ml_baseline/hls4ml`.

---

## Pipeline modules (`pipeline/`)

Shared library imported by every `scripts/*.py` entry point.

| File | Role |
|------|------|
| `paths.py` | Workspace roots (`EXAMPLE_ROOT`, `ARTIFACTS_ROOT`, `CONFIGS_ROOT`) and `ensure_ml_baseline_on_path()` so parent `model.py`/`dataset.py`/`train.py` import cleanly. |
| `candidates.py` | `CandidateConfig` dataclass, `load_candidates()`, `get_candidate(name=None)` — reads `configs/candidates.yaml` and returns the default candidate if no name is given. |
| `evaluation.py` | `evaluate_candidate_fold()`, `aggregate_candidate_metrics()`, `export_calibration_bundle()` — replays PyTorch inference on archived fold splits and writes per-sample CSVs / pooled metrics. |
| `hls.py` | `build_pytorch_hls_project()` — builds the hls4ml project directly from the PyTorch model. Applies `DEFAULT_STAGE1_PRECISION=fixed<24,8>`, can override dense-layer precision, and forces average-pooling accumulators such as `avgpool`/`gap` to `fixed<40,20>` by default. Writes `conversion_manifest.json` next to the generated project. |
| `stages.py` | `write_stage_ledger()` and `compare_stage_predictions()` — discover and align `per_sample.csv` outputs across stages. |

Stage directory layout under `artifacts/<candidate>/`:
```
pytorch_float/fold_{N}/per_sample.csv
hls/pytorch/fold_{N}/              # generated hls4ml project (build_prj.tcl, firmware/, ...)
hls/parity/fold_{N}/               # parity.csv + summary.json
exports/fold_{N}/inputs_nchw.npy   # calibration tensors + fixed-length blobs
```

---

## Scripts (`scripts/`)

### Python entry points

| Script | Purpose |
|--------|---------|
| `check_environment.py` | Reports which Python modules (torch, hls4ml) and toolchain binaries (`vivado`, `vitis_hls`, `vitis-run`) are present. |
| `evaluate_candidate.py` | PyTorch replay over archived fold validation splits. Writes per-sample CSV + `metrics_summary.json`; prints pooled metrics when run across all folds. |
| `convert_to_hls.py` | Builds the hls4ml project (PyTorch frontend, `Vitis` backend, `io_stream`, `Resource` strategy). Global knobs: `--reuse-factor`, `--default-precision`, `--accum-precision`, `--dense-precision`, `--pool-accum-precision`, `--strategy`, `--clock-period`, `--backend`, `--part`. |
| `export_calibration_data.py` | Deterministic NCHW calibration tensors + fixed-length `1048576`-byte sample blobs for the `sw/` harness. |
| `check_parity.py` | Float HLS vs PyTorch parity for a subset of calibration samples. Writes `parity.csv`, `summary.json`, `all_folds_summary.csv`, and optionally profiling PNGs. |
| `build_stage_ledger.py` | Consolidates `per_sample.csv` files across candidates/stages into one ledger CSV. |
| `compare_stages.py` | Per-sample diff between two named stages; emits JSON summary. |
| `summarize_stages.py` | Gathers all `metrics_summary.json` files under `artifacts/` into one CSV. |

### Shell scripts

| Script | Purpose |
|--------|---------|
| `run_stage1_all_folds.sh [folds...]` | Runs Stage 1 per fold: `convert_to_hls` → `export_calibration_data`. Env vars: `CANDIDATE`, `DEFAULT_PRECISION`, `PROJECT_NAME`. Default folds: 0–4. |
| `monitor_csynth_ntfy.sh <pid> [project_rel]` | Blocks on the `vitis_hls` PID, then POSTs a completion/error summary to ntfy topic `coyote-build-sdeheredia`. |
| `retrain_cnn_medium_hls.sh` | Launches a new tmux session `train_cnn_medium_hls` and retrains `cnn_medium_hls` (5-fold, 500 ep). GPU host only. |

---

## Common commands

All run from `examples/ml_baseline/hls4ml`. Set `PY=../../ml_baseline/.venv_hls4ml/bin/python`.

### Environment check
```bash
$PY scripts/check_environment.py
```

### PyTorch baseline replay
```bash
# all folds + pooled metrics
$PY scripts/evaluate_candidate.py --candidate cnn_medium_img512
# single fold
$PY scripts/evaluate_candidate.py --candidate cnn_medium_img512 --fold 0
```

### Stage 1 (hls4ml project + calibration) for one candidate
```bash
CANDIDATE=cnn_medium_img512 bash scripts/run_stage1_all_folds.sh 0
# or all folds:
CANDIDATE=cnn_medium_img512 bash scripts/run_stage1_all_folds.sh
# override precision:
CANDIDATE=cnn_b_img256 DEFAULT_PRECISION="fixed<20,8>" bash scripts/run_stage1_all_folds.sh 0
```

### Regenerate the hls4ml project with different RF / precision
```bash
$PY scripts/convert_to_hls.py \
  --candidate cnn_b_img256 --fold 0 \
  --output-dir artifacts/cnn_b_img256/hls/pytorch/fold_0 \
  --project-name cnn_b_img256_pytorch_hls \
  --reuse-factor 32 \
  --default-precision "fixed<24,8>"
```
Reduced-precision bring-up for the current `cnn_small_hls_opt_img512` target:
```bash
$PY scripts/convert_to_hls.py \
  --candidate cnn_small_hls_opt_img512 --fold 0 \
  --output-dir artifacts/cnn_small_hls_opt_img512/hls/pytorch/fold_0 \
  --project-name cnn_small_hls_opt_img512_pytorch_hls \
  --reuse-factor 8 \
  --default-precision "fixed<8,3>" \
  --accum-precision "fixed<24,10>" \
  --dense-precision "fixed<16,6>"
```
Sanity-check the generated config:
```bash
grep -c "ReuseFactor: 32" artifacts/cnn_b_img256/hls/pytorch/fold_0/hls4ml_config.yml
grep -A3 "^    avgpool:" artifacts/cnn_b_img256/hls/pytorch/fold_0/hls4ml_config.yml
```

### Run Vitis csynth on a generated project
```bash
source /opt/hdev/cli/enable/vitis          # pick 2024.2 at prompt
cd artifacts/cnn_b_img256/hls/pytorch/fold_0
TS=$(date +%Y%m%d_%H%M%S)
LOG=$PWD/../../../../../logs/csynth_cnn_b_img256_fold0_${TS}.log
nohup vitis_hls -f build_prj.tcl > "$LOG" 2>&1 &
MAIN_PID=$!
# ntfy notification on exit:
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml
nohup bash scripts/monitor_csynth_ntfy.sh "$MAIN_PID" \
  artifacts/cnn_b_img256/hls/pytorch/fold_0 \
  > logs/csynth_cnn_b_img256_fold0_ntfy_monitor.log 2>&1 &
```

### Parity check (HLS vs PyTorch on calibration samples)
```bash
$PY scripts/check_parity.py --candidate cnn_medium_img512 --folds 0 --n-samples 4
```

### Cross-stage inspection
```bash
$PY scripts/build_stage_ledger.py --candidate cnn_medium_img512 \
  --output artifacts/cnn_medium_img512/stage_ledger.csv
$PY scripts/compare_stages.py --candidate cnn_medium_img512 \
  --left-stage pytorch_float --right-stage pytorch_float \
  --output artifacts/cnn_medium_img512/pytorch_float/self_compare.csv
$PY scripts/summarize_stages.py --output artifacts/stage_summary.csv
```

---

## Notes

- Average-pooling accumulator precision defaults to `fixed<40,20>` in
  `build_pytorch_hls_project`; changing `--default-precision` does not disable it.
- `convert_to_hls.py` exposes dense and accumulator precision but not per-layer
  reuse factors. For per-layer reuse tuning, edit
  `config["LayerName"][layer]["ReuseFactor"]` inside
  `pipeline/hls.py:build_pytorch_hls_project` before `convert_from_pytorch_model`.
- `check_environment.py` will report `MISS vitis_hls` until `source
  /opt/hdev/cli/enable/vitis` has been run in the current shell.
