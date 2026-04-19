# CODEX_CONTINUE — hls4ml Workspace Status

## Stage 1 Progress

Stage 1 status summary:

- Tasks 1, 2, 3: environment + export pipeline are usable.
- Task 4: direct PyTorch hls4ml parity now uses the real `MediumCNNHLS` `AvgPool2d(64,64) -> Linear` head, not the collapsed-conv export view.
- Precision target: global `fixed<24,8>` plus `avgpool.accum=fixed<40,20>`.
- Fold parity over 4 calibration samples/fold passes the revised gate (`max_abs <= 0.25`): worst fold max_abs is `0.2039`; summary is `artifacts/cnn_medium/hls/parity_pytorch_avgpool_fixed24_8/all_folds_summary.csv`.
- Task 5: next step is running `csynth` on the direct PyTorch avgpool project under `artifacts/cnn_medium/hls/pytorch/fold_0/` after regenerating the canonical Stage 1 projects with `scripts/run_stage1_all_folds.sh`.
- Fold_0 csynth status: Vitis 2024.2 direct-float `fixed<24,8>` RF=4/5 run is still in clang csynth after >4h with no final `csynth.rpt`; only design-size reports exist. Treat this as a practical synthesis blocker for the uncompressed float configuration unless it eventually terminates with a usable report. ntfy monitor is active for `coyote-build-sdeheredia`.

Tracks progress against `CODEX_PLAN.md` for `examples/ml_baseline/hls4ml`.

## Done

- **Workspace scaffold**: `configs/`, `pipeline/`, `scripts/`, `hw/`, `sw/`, `artifacts/` in place; candidate registry at `configs/candidates.yaml` (initial entry `cnn_medium`, 2d, `(1,1024,1024)`, target `xcu55c-fsvh2892-2L-e`, fallback `xcu250-figd2104-2L-e`).
- **Stage 0 — software baseline**: all 5 `cnn_medium` folds + pooled metrics regenerated under `artifacts/cnn_medium/pytorch_float/`. Pooled metrics reproduced: `accuracy=0.9496`, `roc_auc=0.9915`, `mcc=0.9024`. Stage ledger (`artifacts/cnn_medium/stage_ledger.csv`) and summary (`stage_summary.csv`) are written.
- **Stage 1 — direct avgpool parity**:
  - ONNX export: `artifacts/cnn_medium/onnx/fold_0/final.onnx`
  - QONNX cleanup: `artifacts/cnn_medium/qonnx/fold_0/final_clean.onnx`
  - hls4ml PyTorch direct avgpool projects tested under `artifacts/cnn_medium/hls/pytorch_avgpool_fixed24_8/fold_*`. Config: `Vitis`, `io_stream`, `Resource`, `ReuseFactor=4`, global `fixed<24,8>`, final `avgpool.accum=fixed<40,20>`, clock 5 ns, part `xcu55c-fsvh2892-2L-e`.
  - Parity summary: `artifacts/cnn_medium/hls/parity_pytorch_avgpool_fixed24_8/all_folds_summary.csv`.
- **Calibration export**: fixed-length sample blobs + NHWC/NCHW/uint8 tensors for all folds under `artifacts/cnn_medium/exports/fold_*`.
- **Coyote scaffolds**: `hw/CMakeLists.txt` + `hw/src/` and `sw/CMakeLists.txt` + `sw/src/` skeletons (no generated hls4ml core vendored yet).

## Remaining

- **Stage 1 — finish**
  - Run hls4ml `trace` and profiling for fold_0 through `scripts/check_parity.py`; parity on all folds has already been established in the direct avgpool experiment.
  - Let the current fold_0 direct-float csynth terminate or stop it explicitly; if no final report appears, move synthesis effort to higher reuse, pruning, or quantization rather than spending more time on this uncompressed float configuration.
- **Stage 2 — compression (not started)**
  - Structured channel pruning of `conv2`, `conv3`, `conv4` at 25% and 50% (keep `conv1` unchanged).
  - 50-epoch fine-tune on non-test data; physically compact each pruned variant before export.
  - Gate: keep only if dev MCC drop ≤ 0.01 absolute and ROC-AUC drop ≤ 0.003 relative to float `cnn_medium`.
  - Unstructured sparsity only as a secondary experiment.
- **Stage 3 — quantization (not started)**
  - Brevitas + QONNX as primary path. Train Q1 (`W8A8`), Q2 (inner `W6A6`, first/last `W8A8`), Q3 (best pruned + Q2).
  - Zero zero-point, power-of-2 scales. 40-epoch fine-tune per variant before export.
- **Stage 4 — HLS tuning (not started)**
  - For every promoted variant: profiling, `predict`, `trace` before synth.
  - Sweep `ReuseFactor` ∈ {4, 8, 16}; run FIFO-depth optimization after first successful stream build.
  - Select smallest-resource config that passes dev tolerance and completes `csynth`.
- **Coyote integration (scaffolded only)**
  - Vendor the winning hls4ml-generated source into the HLS kernel directory.
  - Implement `cnn_medium_infer` wrapper: one 512-bit AXI host input stream, tensor reconstruction, byte inversion + normalization identical to `ml_baseline`, feed into network core, return one packed score/logit word.
  - Full Coyote bitstream build for `u55c` (fallback `u250`).
- **Final acceptance**
  - Fold parity (PyTorch float vs HLS float) on all 5 folds; pooled OOF metrics match archived run within tolerance.
  - Compression/quantization metric tracking (before/after fine-tune, after HLS).
  - Bit-accuracy checks (predict/trace/profiling) for every promoted variant.
  - `csynth` latency/resource + Coyote post-route numbers recorded.
  - Locked test set evaluated exactly once after freeze; hardware output matches host HLS output within tolerance on the deployment set.
- **Stage 5 — escalation**
  - Only if `cnn_medium` misses the accuracy/resource tradeoff: add `cnn_b` candidate through the same pipeline. HGQ2 rebuild only if Brevitas cannot deliver. QKeras is not the main path.

## Suggested next steps (in order)

1. Archive fold_0 trace/profiling and optionally a larger-sample parity spot check for the canonical direct-avgpool path.
2. Generate higher-reuse fold_0 projects (`ReuseFactor=8`, `16`) as fallback candidates; defer their csynth until the current Vitis run is stopped or complete.
3. Start Stage 2 planning/implementation for structured pruning, because uncompressed float synthesis is likely too heavy.
4. Proceed to Stage 3 (Brevitas Q1/Q2/Q3) and Stage 4 (RF sweep + FIFO opt) on the surviving variants.
5. Vendor the winning core into `hw/src/hls/cnn_medium_infer/` and close the Coyote integration for `u55c`.

## Pointers

- Plan: `CODEX_PLAN.md`
- Candidate registry: `configs/candidates.yaml`
- Stage ledger: `artifacts/cnn_medium/stage_ledger.csv`
- Latest hls4ml project: `artifacts/cnn_medium/hls/pytorch/fold_0/` after rerunning `scripts/run_stage1_all_folds.sh`; tested direct-avgpool projects are under `artifacts/cnn_medium/hls/pytorch_avgpool_fixed24_8/fold_*`.
- Environment check: `scripts/check_environment.py`
