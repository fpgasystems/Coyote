# CODEX_CONTINUE — hls4ml Workspace Status

## Stage 1 Progress

Stage 1 status summary:

- Tasks 1, 2, 3: environment + export pipeline are usable.
- Task 4: direct PyTorch hls4ml parity now targets `cnn_medium_img512`, the smaller April 19 512x512 `cnn_medium` run. The HLS model is `MediumCNNHLS512`, using explicit `AvgPool2d(32,32) -> Linear`.
- Precision target: global `fixed<24,8>` plus `avgpool.accum=fixed<40,20>`.
- Fold parity over 4 calibration samples/fold passes the revised gate (`max_abs <= 0.25`): worst fold max_abs is `0.0833`; summary is `artifacts/cnn_medium_img512/hls/parity/all_folds_summary.csv`.
- PyTorch validation replay for `cnn_medium_img512` exactly matches the archived img512 fold metrics; pooled replay metrics are `accuracy=0.9370`, `roc_auc=0.9775`, `mcc=0.8747`.
- Task 5: `csynth` for the smaller direct PyTorch avgpool project under `artifacts/cnn_medium_img512/hls/pytorch/fold_0/` was killed after more than three hours in clang HLS synthesis with no final `csynth.rpt`. It emitted only `csynth_design_size.rpt/xml`; design size after compile/link was `250,384` instructions. ntfy reported `terminated_with_errors` on `coyote-build-sdeheredia`.
- Parallel fallback: `cnn_b_img256` was added as a smaller 256x256 HLS candidate (`cnn_b_hls_img256`, explicit `AvgPool2d(16,16)`). Fold_0 Stage 1 generation and 4-sample parity passed (`mae=0.1016`, `max_abs=0.1069`). Its fold_0 `csynth` failed during Vitis source synthesis after the design expanded from `69,520` instructions at compile/link to `1,753,339` instructions after unroll/inline; clang then segfaulted in Global Value Numbering on `dense_resource_rf_leq_nin<..., config11_mult>`, the lowered multiply engine for the final 64-channel `3x3` convolution. No final `*_csynth.rpt` was produced, and ntfy reported `terminated_with_errors` on `coyote-build-sdeheredia`.
- Old fold_0 1024 csynth status: Vitis 2024.2 direct-float `fixed<24,8>` RF=4/5 remained in clang csynth after >4h with no final `csynth.rpt`; only design-size reports exist. It was stopped by request and treated as a practical synthesis blocker for the uncompressed 1024 float configuration.

Tracks progress against `CODEX_PLAN.md` for `examples/ml_baseline/hls4ml`.

## Done

- **Workspace scaffold**: `configs/`, `pipeline/`, `scripts/`, `hw/`, `sw/`, `artifacts/` in place; candidate registry at `configs/candidates.yaml` (initial entry `cnn_medium`, 2d, `(1,1024,1024)`, target `xcu55c-fsvh2892-2L-e`, fallback `xcu250-figd2104-2L-e`).
- **Stage 0 — software baseline**: all 5 `cnn_medium` folds + pooled metrics regenerated under `artifacts/cnn_medium/pytorch_float/`. Pooled metrics reproduced: `accuracy=0.9496`, `roc_auc=0.9915`, `mcc=0.9024`. Stage ledger (`artifacts/cnn_medium/stage_ledger.csv`) and summary (`stage_summary.csv`) are written.
- **Stage 1 — img512 direct avgpool parity**:
  - ONNX export: `artifacts/cnn_medium_img512/onnx/fold_*/final.onnx`
  - QONNX cleanup: `artifacts/cnn_medium_img512/qonnx/fold_*/final_clean.onnx`
  - hls4ml PyTorch direct avgpool projects: `artifacts/cnn_medium_img512/hls/pytorch/fold_*`. Config: `Vitis`, `io_stream`, `Resource`, requested `ReuseFactor=4`, global `fixed<24,8>`, final `avgpool.accum=fixed<40,20>`, clock 5 ns, part `xcu55c-fsvh2892-2L-e`.
  - Parity summary: `artifacts/cnn_medium_img512/hls/parity/all_folds_summary.csv`.
- **Calibration export**: fixed-length sample blobs + NHWC/NCHW/uint8 tensors for all folds under `artifacts/cnn_medium_img512/exports/fold_*`.
- **Coyote scaffolds**: `hw/CMakeLists.txt` + `hw/src/` and `sw/CMakeLists.txt` + `sw/src/` skeletons (no generated hls4ml core vendored yet).

## Remaining

- **Stage 1 — finish**
  - Treat `cnn_medium_img512` RF=4/5 as blocked for float `csynth`; it was stopped after more than three hours in clang with no final report.
  - Treat `cnn_b_img256` RF=4/5 as failed for float `csynth`; next fallback should raise reuse factor or move to the quantized/pruned Stage 2/3 path rather than rerunning the same project.
  - Archive hls4ml `trace` and profiling for the img512 fold_0 project.
  - Optionally run a larger-sample parity spot check before promoting this as the float baseline for Stage 2/3.
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

1. Generate higher-reuse fold_0 projects (`ReuseFactor=16`, `32`, possibly `64`) as fallback candidates; RF=4/5 is too aggressive for Vitis 2024.2 on these float designs.
2. Archive fold_0 trace/profiling and optionally a larger-sample parity spot check for the canonical img512 direct-avgpool path.
3. Move Stage 2/3 pruning/quantization forward, because uncompressed float synthesis is blocked even on the 256x256 `cnn_b` fallback.
4. Proceed to Stage 3 (Brevitas Q1/Q2/Q3) and Stage 4 (RF sweep + FIFO opt) on the surviving variants.
5. Vendor the winning core into `hw/src/hls/cnn_medium_infer/` and close the Coyote integration for `u55c`.

## Pointers

- Plan: `CODEX_PLAN.md`
- Candidate registry: `configs/candidates.yaml`
- Current hls4ml project: `artifacts/cnn_medium_img512/hls/pytorch/fold_0/`
- Current parity notes: `artifacts/cnn_medium_img512/hls/parity/PARITY_NOTES.md`
- Environment check: `scripts/check_environment.py`
