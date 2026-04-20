# `cnn_medium` hls4ml Plan For `examples/ml_baseline/hls4ml`

## Summary
- Start a new workspace at `examples/ml_baseline/hls4ml` and treat it as a new Coyote example with its own `hw`, `sw`, `configs`, `scripts`, and `artifacts`.
- Use `cnn_medium` as the initial model because it is smaller than `cnn_b` and therefore lower risk for first-pass `hls4ml` conversion and Coyote deployment.
- 2026-04-19 pivot: the active Stage 1 candidate is now `cnn_medium_img512`, a 512x512 `cnn_medium` run, because the 1024x1024 direct-float project reached parity but stalled in Vitis csynth after more than four hours.
- Keep the pipeline candidate-driven so `cnn_b` can be added later with the same flow if `cnn_medium` underperforms or leaves too much headroom.
- Keep the final test set locked until the `cnn_medium` variant, HLS config, and deployment path are frozen.

## Public Interfaces And Workspace
- Create `examples/ml_baseline/hls4ml` with:
  - `CODEX_PLAN.md`
  - `README.md`
  - `configs/candidates.yaml`
  - `scripts/`
  - `artifacts/`
  - `hw/`
  - `sw/`
- Use `configs/candidates.yaml` with one initial entry:
  - model name `cnn_medium`
  - representation `2d`
  - input shape `(1, 1024, 1024)`
  - checkpoint root `runs/20260415_040251_cnn_medium_ro8000_ep500_kfold5_fliponly_kfold5`
  - target part `xcu55c-fsvh2892-2L-e`
  - fallback part `xcu250-figd2104-2L-e`
- Current default candidate:
  - model name `cnn_medium_img512`
  - HLS model `cnn_medium_hls_img512`
  - representation `2d`
  - input shape `(1, 512, 512)`
  - checkpoint root `runs/20260419_191657_cnn_medium_ro8000_ep300_fliponly_img512_lr3e4_img512_kfold5`
- Reuse the parent `examples/ml_baseline/dataset.py` and `model.py` directly for preprocessing and checkpoint loading so the HLS flow matches training-time behavior exactly.
- Add a stage ledger format keyed by `sample_id`, `fold`, `model_variant`, and `stage` for all evaluation outputs.

## Implementation Changes
- Baseline resolution:
  - Resolve checkpoints from `ml_baseline/runs/.../final_model.pt`, not `saved_runs`, because `saved_runs` preserves plots/CSVs but not the `.pt` weights.
  - Reproduce the saved April 15 pooled validation metrics for `cnn_medium` before any HLS work.
- Environment:
  - Reuse the parent `ml_baseline/.venv` and install the HLS stack there.
  - Include `hls4ml[profiling,optimization]`, `onnx`, `qonnx`, `brevitas`, and the AMD HLS toolchain.
  - Add `tensorflow`, `qkeras`, and `HGQ/HGQ2` only for the fallback rewrite branch.
  - **Enable Vitis HLS in the shell before running any `hls4ml` build, `csynth`, or `convert_to_hls.py` step that invokes `vitis_hls`:** `source /opt/hdev/cli/enable/vitis` (related envs: `source /opt/hdev/cli/enable/vivado` for Vivado, `source /opt/hdev/cli/enable/xrt` for XRT). This must be sourced in every new shell before `scripts/check_environment.py` will report the toolchain as present; without it `hls4ml` falls back to project-only generation and no synthesis runs.
- Stage 0: software baseline.
  - Validate all five `cnn_medium` folds with the existing PyTorch model and emit pooled/per-fold artifacts in the same schema as `ml_baseline`.
- Stage 1: float HLS conversion.
  - Try direct PyTorch conversion first with `backend='Vitis'`, `io_type='io_stream'`, `granularity='name'`, `Strategy='Resource'`, and `ReuseFactor=4`.
  - For `cnn_medium_hls`, use direct `AvgPool2d(64,64)` with global `fixed<24,8>` and final `avgpool.accum=fixed<40,20>`; do not collapse the final avgpool/classifier into an export-only convolution.
  - For `cnn_medium_hls_img512`, use direct `AvgPool2d(32,32)` with the same `fixed<24,8>` and `avgpool.accum=fixed<40,20>` policy.
  - Export evaluation tensors in NHWC order explicitly, because PyTorch `io_stream` does not transpose inputs for us.
  - If direct PyTorch conversion fails on FX or layer support, switch the canonical path to float ONNX plus QONNX cleanup and channels-last conversion.
- Stage 2: compression.
  - Make structured channel pruning the default compression path.
  - Prune `conv2`, `conv3`, and `conv4`; keep `conv1` unchanged.
  - Start with two pruning levels: `25%` and `50%`.
  - Fine-tune each pruned variant for `50` epochs on non-test data and physically compact the model before export.
  - Keep a pruned variant only if dev MCC drop is at most `0.01` absolute and ROC-AUC drop is at most `0.003` relative to float `cnn_medium`.
  - Keep unstructured sparsity as a secondary experiment only.
- Stage 3: quantization.
  - Make Brevitas plus QONNX the primary quantization path.
  - Train three concrete variants:
    - `Q1`: `cnn_medium` with `W8A8`
    - `Q2`: `cnn_medium` with internal layers `W6A6`, first and last layers `W8A8`
    - `Q3`: best structured-pruned model plus `Q2`
  - Use zero zero-point and power-of-2 scales to stay on the supported QONNX path.
  - Fine-tune each quantized variant for `40` epochs on non-test data before export.
- Stage 4: HLS tuning.
  - For every promoted variant, run `hls4ml` profiling, `predict`, and `trace` before synthesis.
  - Sweep `ReuseFactor` over `4`, `8`, and `16`.
  - Run FIFO-depth optimization after the first successful streaming build.
  - Select the smallest-resource variant/config pair that stays within dev tolerance and completes `csynth`.
- Stage 5: escalation path.
  - If `cnn_medium` cannot meet the required accuracy-resource tradeoff, add `cnn_b` as the next candidate using the same pipeline and artifact format.
  - Only if PyTorch/ONNX plus Brevitas cannot deliver a deployable result, rebuild the chosen model as an HGQ2 branch and retrain it.
  - Do not make QKeras the main path.

## Coyote Integration
- Implement `examples/ml_baseline/hls4ml/hw` and `sw` as a normal full-bitstream Coyote example, modeled on `02_hls_vadd`.
- Generate the winning `hls4ml` core with the `Vitis` backend, then vendor the stable generated source into the example’s HLS source tree.
- Add a thin Coyote HLS wrapper `cnn_medium_infer` that:
  - accepts one 512-bit AXI host input stream
  - reconstructs the fixed input tensor
  - performs byte inversion and normalization exactly as in `ml_baseline`
  - feeds the generated `hls4ml` network core
  - returns one packed result word with the score/logit
- First deployment target is a full Coyote bitstream on `u55c`.
- If `u55c` blocks on tool or platform issues, rebuild the exact same example for `u250`.

## Test Plan
- Fold parity:
  - compare PyTorch float vs HLS float on each saved `cnn_medium` fold
  - recompute pooled out-of-fold metrics and confirm they match the archived run within tolerance
- Compression tracking:
  - record metrics before pruning, after pruning fine-tune, and after HLS conversion
- Quantization tracking:
  - record metrics for `W8A8`, `W6A6`, and `pruned+W6A6` before and after QONNX/HLS conversion
- Bit-accuracy checks:
  - use `predict`, `trace`, and profiling plots for every promoted variant before synthesis
- Synthesis checks:
  - collect `csynth` latency/resource numbers and then Coyote post-route timing/resource data
- Final acceptance:
  - best frozen `cnn_medium` variant stays within chosen dev tolerance relative to float baseline
  - Coyote build completes for `u55c` or fallback `u250`
  - final test is evaluated exactly once after freeze
  - hardware outputs match host HLS outputs within a fixed tolerance on the deployment sample set

## Assumptions And Defaults
- Intended plan file path is `examples/ml_baseline/hls4ml/CODEX_PLAN.md`.
- `cnn_medium` is the initial model only because it is smaller and lower risk; `cnn_b` remains the planned scale-up candidate if needed.
- The final deployed model does not have to be the original float checkpoint; a compressed and/or quantized `cnn_medium` derivative is allowed and expected.
- The existing single-logit design is retained; no softmax layer is introduced.
- `cnn_medium` still likely benefits from compression or quantization before deployment because its late conv layers remain sizable (`conv3=10,416`, `conv4=20,784` parameters), even though it is smaller than `cnn_b`.
- The final test manifest is external to the current repo layout and will be supplied explicitly.
- This plan applies the local tutorial guidance from:
  - `part3_compression.ipynb`
  - `part4_quantization.ipynb`
  - `part4.1_HG_quantization.ipynb`
  - `part6_cnns.ipynb`
- This plan also follows current official guidance that:
  - PyTorch CNNs are supported but less mature than Keras flows
  - Brevitas models should go through ONNX/QONNX
  - pruning and quantization are recommended for fit
  - profiling and bit-accurate checks should happen before synthesis
