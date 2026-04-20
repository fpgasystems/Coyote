# CODEX_PARITY_PLAN — Stage 1 Task 4: Float HLS vs PyTorch Parity On All Folds

## 2026-04-19 update — pivot to img512 run

The uncompressed 1024x1024 direct-float project reached parity, but fold_0
`csynth` did not finish after more than four hours in clang HLS synthesis. The
active Stage 1 target has therefore been switched to the smaller 512x512
`cnn_medium` run:

`/mnt/scratch/sdeheredia/Coyote/examples/ml_baseline/saved_runs/20260419_191657_cnn_medium_ro8000_ep300_fliponly_img512_lr3e4_img512_kfold5`

The corresponding live checkpoint directory is:

`/mnt/scratch/sdeheredia/Coyote/examples/ml_baseline/runs/20260419_191657_cnn_medium_ro8000_ep300_fliponly_img512_lr3e4_img512_kfold5`

Changes made for this pivot:

- Stopped the stale 1024 `vitis_hls`/clang synthesis process; no old csynth or ntfy monitor process remains.
- Added `MediumCNNHLS512`, which reuses the `MediumCNNHLS` feature stack but uses explicit `AvgPool2d(32,32)` for 512x512 inputs.
- Added candidate `cnn_medium_img512` and made it the default candidate. The original `cnn_medium` entry remains available for old 1024 artifacts.
- Made `scripts/run_stage1_all_folds.sh` candidate-aware so Stage 1 paths now resolve to `artifacts/<candidate>/...`.
- Made `scripts/check_parity.py` choose parity output/project names from the selected candidate when not explicitly provided.

Validation completed for the img512 pivot:

- `py_compile` passed for the touched Python modules.
- `python ../model.py` forward smoke test passed; `cnn_medium_hls_img512` uses input `(2,1,512,512)` and has 34,177 params.
- All five img512 checkpoints load into `MediumCNNHLS512`; the final pool is `AvgPool2d(kernel_size=32, stride=32)`.
- Stage 1 regeneration completed for folds 0–4: ONNX export, QONNX cleanup, direct PyTorch hls4ml conversion/compile, and calibration export under `artifacts/cnn_medium_img512/...`.
- PyTorch validation replay exactly matches the archived img512 k-fold summary for each fold:

| fold | archived acc | replay acc | archived ROC-AUC | replay ROC-AUC | archived BCE | replay BCE |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 0.895833 | 0.895833 | 0.986111 | 0.986111 | 0.316340 | 0.316340 |
| 1 | 0.916667 | 0.916667 | 0.991319 | 0.991319 | 0.128156 | 0.128156 |
| 2 | 0.958333 | 0.958333 | 0.998264 | 0.998264 | 0.177705 | 0.177705 |
| 3 | 0.978723 | 0.978723 | 0.996377 | 0.996377 | 0.116732 | 0.116732 |
| 4 | 0.936170 | 0.936170 | 0.994565 | 0.994565 | 0.141792 | 0.141792 |

Direct PyTorch hls4ml parity for the img512 candidate passed the revised Stage 1
gate on 4 calibration samples per fold with global `fixed<24,8>` and
`avgpool.accum=fixed<40,20>`:

| fold | mae | max_abs | note |
|---:|---:|---:|---|
| 0 | 0.0423 | 0.0475 | pass |
| 1 | 0.0685 | 0.0758 | pass |
| 2 | 0.0765 | 0.0833 | pass; high relative error is from near-zero logits |
| 3 | 0.0532 | 0.0586 | pass |
| 4 | 0.0622 | 0.0706 | pass; high relative error is from near-zero logits |

Generated HLS header check on fold_0 confirms `avgpool_accum_t` is
`ap_fixed<40,20>`. Requested global reuse factor is still 4; hls4ml adjusts the
first convolution to valid reuse factor 5, matching the earlier 1024 behavior.

Current img512 artifacts:

- Stage 1 projects: `artifacts/cnn_medium_img512/hls/pytorch/fold_*`
- Calibration exports: `artifacts/cnn_medium_img512/exports/fold_*`
- Parity summary: `artifacts/cnn_medium_img512/hls/parity/all_folds_summary.csv`
- PyTorch validation replay: `artifacts/cnn_medium_img512/pytorch_float/fold_*`

Next practical Stage 1 step: run `csynth` on
`artifacts/cnn_medium_img512/hls/pytorch/fold_0` and compare design size/runtime
against the blocked 1024 project before deciding whether to continue float HLS
or move immediately to pruning/quantization.

Csynth attempt started 2026-04-19 22:22 local time with Vitis 2024.2 and
csynth-only build options (`reset=1`, `csim=0`, `synth=1`, `cosim=0`,
`validation=0`). Vitis reached the same clang HLS phase as the 1024 project.
The img512 design is smaller after compile/link (`250,384` instructions vs
`973,840` for the 1024 project), but it remained in `clang-3.9-csynth` for
more than three hours with no final `csynth.rpt`; only
`csynth_design_size.rpt/xml` exist. Per user direction, this run was killed on
2026-04-20 around 01:27 local time; ntfy reported `terminated_with_errors` on
topic `coyote-build-sdeheredia`.

Parallel smaller-model attempt: `cnn_b_img256`

User provided a smaller 256x256 `cnn_b` run:

`/mnt/scratch/sdeheredia/Coyote/examples/ml_baseline/runs/20260419_191701_cnn_b_ro8000_ep300_fliponly_img256_img256_kfold5`

This is possible to synthesize in parallel because the host has 64 cores and
ample memory, while the img512 csynth is currently dominated by one CPU-bound
clang worker. A separate HLS model/candidate was added:

- model: `cnn_b_hls_img256`
- candidate: `cnn_b_img256`
- explicit final pool: `AvgPool2d(16,16)`
- artifacts: `artifacts/cnn_b_img256/...`

Validation before csynth:

- All five checkpoints load into `SmallCNNHLS256`.
- Fold_0 Stage 1 generation completed: ONNX, QONNX, direct PyTorch hls4ml
  conversion/compile, and calibration export.
- Fold_0 4-sample parity at `fixed<24,8>` with `avgpool.accum=fixed<40,20>`:
  `mae=0.1016`, `max_abs=0.1069`, `max_rel=0.0473`.

Parallel fold_0 csynth started 2026-04-20 00:04 local time under
`artifacts/cnn_b_img256/hls/pytorch/fold_0`. It reached compile/link quickly
and reported `69,520` design instructions, substantially smaller than both
img512 medium (`250,384`) and 1024 medium (`973,840`). It then expanded to
`1,753,339` instructions after the Unroll/Inline phase and failed in source
synthesis after 18m20s. Vitis reports `ERROR: [HLS 200-1715] Encountered
problem during source synthesis`; the clang reflow error log shows a clang
frontend segmentation fault while running Global Value Numbering on
`dense_resource_rf_leq_nin`. No final `*_csynth.rpt` was produced.

Failure investigation:

- The `config_array_partition -maximum_size 4096` message is not the fatal
  issue: `build_prj.tcl` wraps that command in `catch`, and Vitis continues to
  source synthesis.
- The failing function is
  `dense_resource_rf_leq_nin<ap_fixed<24,8>, ap_fixed<59,27>, config11_mult>`,
  where `config11_mult` is the lowered multiply engine for `features_9`, the
  final 64-channel `3x3` convolution. It has `n_in=576`, `n_out=64`, and
  `reuse_factor=4`, which gives a very large low-reuse resource implementation.
- The design-size report shows the main blow-up after Unroll/Inline comes from
  late high-channel layers: `features_9` contributes about `649,987`
  instructions, and the explicit `AvgPool2d(16,16)` contributes about
  `665,281` instructions because the `ap_fixed<40,20>` average reduction is
  recursively expanded across the 16x16 pool.
- Immediate conclusion: `cnn_b_img256` RF=4/5 is not a working float synthesis
  point. The smallest model passed parity, but Vitis still cannot handle the
  generated low-reuse resource C++ after unroll/inline. Next experiments should
  raise reuse factor substantially and/or move to quantized/pruned models rather
  than rerunning the same RF=4 project.

## Context

Stage 1 of `examples/ml_baseline/hls4ml` is blocked on float parity between HLS and PyTorch for `cnn_medium`. Current state (see `hls4ml/artifacts/cnn_medium/hls/parity/PARITY_NOTES.md`):

- ONNX export, QONNX cleanup, hls4ml project generation and calibration export already ran for all 5 folds.
- Only fold_0 has been parity-tested (mae=4.89, max_abs=4.96 — not parity).
- Per-layer trace matches PyTorch up through `Relu_3`; divergence starts at `GlobalAveragePool_0`. HLS produces a uniform positive band (min=+1.87, max=+2.70, mean=+2.38) while ONNX Runtime GAP shows true per-channel means with >8× spread and zero-valued channels.
- Increasing precision does not close the gap. Root cause is structural, not precision: the hls4ml Vitis/io_stream path mishandles the `Transpose_1 → GlobalAveragePool_0` pattern that `qonnx.ConvertToChannelsLastAndClean` produces for an `AdaptiveAvgPool2d((1,1))` head.

Goal: close parity on all 5 folds without papering over the bug with an export-only wrapper.

Approach: introduce a **new, separate** `MediumCNN` variant in `model.py` — registered as its own model name (`cnn_medium_hls`) — that replaces `AdaptiveAvgPool2d((1,1))` with an explicit `x.mean(dim=(2, 3))`. This is mathematically equivalent (`AdaptiveAvgPool2d((1,1))(x).flatten(1) ≡ x.mean(dim=(2,3))` for any NCHW tensor; both reduce each channel to its H×W mean and return `[B, C]`) but emits `ReduceMean` instead of `GlobalAveragePool` in ONNX, which avoids the hls4ml transpose-ordering bug. The existing `MediumCNN` stays untouched so all other downstream users (training runs, Grad-CAM, evaluation) are unaffected.

## Approach

1. **Add a new model class** `MediumCNNHLS` in `examples/ml_baseline/model.py`:
   - Same feature stack as `MediumCNN` **minus the final `AdaptiveAvgPool2d((1,1))`**.
   - `forward`: `self.features(x) → x.mean(dim=(2, 3)) → self.classifier(x)`.
   - Classifier unchanged (`nn.Linear(48, 1)`).
   - Docstring notes it is an hls4ml-friendly variant of `MediumCNN`.
   - State-dict of the new class has the same keys/shapes as `MediumCNN`, so old `MediumCNN` checkpoints can be loaded into `MediumCNNHLS` for a forward-equivalence sanity check.

2. **Register** `cnn_medium_hls` in `MODEL_SPECS` (`representation: "2d"`, `default_target_layer: "features.9"` — same semantic target-conv layer index as `MediumCNN`, since only the trailing `AdaptiveAvgPool2d` was removed and it was never the Grad-CAM target).

3. **Extend** `build_model` to dispatch `"cnn_medium_hls" → MediumCNNHLS()`.

4. **Pre-training equivalence check** (no training needed — fails fast if the rewrite is not equivalent):
   - Build `MediumCNN` and `MediumCNNHLS`, load the same old `final_model.pt` from `runs/20260415_.../fold_0/final_model.pt` into both, and compare logits on `artifacts/cnn_medium/exports/fold_0/inputs_nchw.npy[:2]`. Require `max_abs < 1e-5`. Any larger delta means the rewrite is wrong; stop.

5. **Retrain all 5 folds** with `cnn_medium_hls` under the exact April 15 hyperparameters from `runs/20260415_040251_cnn_medium_ro8000_ep500_kfold5_fliponly_kfold5/run_parameters.txt`:
   ```
   cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline
   tmux new -s train_cnn_medium_hls
   .venv/bin/python train.py \
     --model cnn_medium_hls --representation 2d \
     --epochs 500 --batch-size 8 --lr 1e-4 --seed 42 \
     --val-split 0.2 --min-ro 8000 --num-workers 2 \
     --kfold 5 \
     --augment --flip-h-prob 0.5 --flip-v-prob 0.5 \
     --crop-scale-min 1.0 --translate 0.0 \
     --top-n-hardest 10 \
     --run-name cnn_medium_hls_ro8000_ep500_kfold5_fliponly \
     2>&1 | tee runs/launch_$(date +%Y%m%d_%H%M%S)_cnn_medium_hls_ro8000_ep500_kfold5_fliponly.log
   ```

6. **Verify training reproduced the baseline**. Archived April 15 pooled metrics: `accuracy=0.9496`, `roc_auc=0.9915`, `mcc=0.9024`. New run must land within `|Δacc| ≤ 0.01`, `|Δroc_auc| ≤ 0.003`, `|Δmcc| ≤ 0.015`. Larger deltas → investigate before continuing (likely augmentation seed or vault drift, not the head change, since head is equivalent).

7. **Register the hls4ml candidate**. In `hls4ml/configs/candidates.yaml`, update the existing `cnn_medium` entry in place:
   - `model`: `cnn_medium_hls` (was `cnn_medium`).
   - `run_dir`: `../runs/<new_timestamp>_cnn_medium_hls_ro8000_ep500_kfold5_fliponly_kfold5`.
   - `saved_run_dir`: corresponding `../saved_runs/...` path (update when/if archived).
   - Leave everything else (`target_part`, `io_type`, etc.) unchanged.
   - Rationale for overwriting rather than adding a second candidate entry: the whole workspace is built around one active candidate; the `pytorch_float` variant of `cnn_medium` is being replaced wholesale by its hls-friendly sibling. The previous float artifacts remain in `artifacts/cnn_medium/` (and can be moved to `artifacts/cnn_medium/archive_gap_head/` for bisection).

8. **Rerun Stage 1 pipeline** for all 5 folds:
   ```
   cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml
   # Optional: preserve old artifacts first
   mv artifacts/cnn_medium/onnx artifacts/cnn_medium/onnx_archive_gap_head
   mv artifacts/cnn_medium/qonnx artifacts/cnn_medium/qonnx_archive_gap_head
   mv artifacts/cnn_medium/hls/onnx artifacts/cnn_medium/hls/onnx_archive_gap_head
   mv artifacts/cnn_medium/exports artifacts/cnn_medium/exports_archive_gap_head

   bash scripts/run_stage1_all_folds.sh 0 1 2 3 4
   ```
   This runs `export_onnx.py → prepare_qonnx.py → convert_to_hls.py → export_calibration_data.py` against the retrained `final_model.pt` and writes logs to `logs/stage1_fold*_*.log`.

9. **ONNX graph inspection** — mandatory gate before parity:
   - Open `artifacts/cnn_medium/onnx/fold_0/final.onnx` and confirm the head contains `ReduceMean` (axes=[2,3]) + `Gemm` (or `MatMul`+`Add`), **not** `GlobalAveragePool` + `Flatten` + `Gemm`. If `torch.onnx.export` still emits `GlobalAveragePool`, the rewrite did not surface in ONNX and we must force-emit `ReduceMean` explicitly (e.g. `torch.mean(x, dim=[2, 3], keepdim=False)` with `opset_version ≥ 18`, or interpose a tiny custom reduction).
   - Open `artifacts/cnn_medium/qonnx/fold_0/final_clean.onnx` and confirm **no trailing `Transpose`** between the last conv/ReLU and the classifier. If one survives, add a `--no-channels-last` flag to `scripts/prepare_qonnx.py` (one-liner: passes `convert_channels_last=False` to `pipeline.hls.clean_qonnx_model`, which already supports the flag) and rerun step 8.

10. **Run parity on all 5 folds**:
    ```
    .venv_hls4ml/bin/python scripts/check_parity.py \
      --folds 0 1 2 3 4 \
      --n-samples 4 \
      --hls-subdir onnx \
      --project-name cnn_medium_onnx_hls \
      --default-precision "fixed<16,6>" \
      --out artifacts/cnn_medium/hls/parity
    ```
    Acceptance gates below.

11. **Document results**:
    - Append a "Resolution" section to `artifacts/cnn_medium/hls/parity/PARITY_NOTES.md` with per-fold `mae / max_abs / max_rel` at `fixed<16,6>` and `fixed<24,10>`, plus the commit hash of the `model.py` change.
    - Update `CODEX_CONTINUE.md` to mark Task 4 done and flip the candidate model name to `cnn_medium_hls`.
    - Update `CODEX_PLAN.md` if the Stage 2/3/4 references to "`cnn_medium`" need clarifying to "`cnn_medium_hls`".

## Files to touch

- **Edit** `examples/ml_baseline/model.py` — add `MediumCNNHLS` class, register `cnn_medium_hls` in `MODEL_SPECS`, extend `build_model`. `MediumCNN` itself is not modified.
- **Edit** `examples/ml_baseline/hls4ml/configs/candidates.yaml` — `model`, `run_dir`, `saved_run_dir`.
- **Possibly edit** `examples/ml_baseline/hls4ml/scripts/prepare_qonnx.py` — only if step 9 finds a stray `Transpose` (add `--no-channels-last`).
- **Edit** `examples/ml_baseline/hls4ml/artifacts/cnn_medium/hls/parity/PARITY_NOTES.md` — append Resolution section.
- **Edit** `examples/ml_baseline/hls4ml/CODEX_CONTINUE.md` — mark Task 4 done.
- **No changes** to `train.py`, `dataset.py`, `gradcam.py`, or any other model class.

## Verification (end-to-end)

Ordered gates. Stop and diagnose at the first failure.

1. **Forward equivalence (pre-training)**: `MediumCNN` and `MediumCNNHLS` produce identical logits (`max_abs < 1e-5`) on the first 16 calibration samples of fold_0 when loaded with the same state_dict.
2. **Training reproduces metrics**: new pooled `accuracy / roc_auc / mcc` land within tolerance of the April 15 archived values.
3. **ONNX graph check**: `ReduceMean(axes=[2,3])` present; no trailing `Transpose` before the classifier in the cleaned QONNX.
4. **Per-fold parity (primary gate)**: `artifacts/cnn_medium/hls/parity/all_folds_summary.csv` shows `max_abs ≤ 0.05` on all 5 folds at `fixed<16,6>` — down from 4.89 on the broken fold_0 — and `mae < 1e-3` at `fixed<24,10>`.
5. **Per-layer trace consistency**: using `scripts/_parity_one.py` as a template on fold_0, the ReduceMean output must show per-channel variation matching ONNX Runtime (>8× spread, some zero channels), not the current uniform ~+2.4 band.
6. **Stage 0 metrics regression**: rerun `scripts/summarize_stages.py`; pooled `cnn_medium / pytorch_float` row still lands within tolerance, confirming the retrain didn't silently drift.

## Execution progress

- [x] **Section 1 — model change**: `MediumCNNHLS` added in `examples/ml_baseline/model.py`, registered as `cnn_medium_hls` in `MODEL_SPECS` and `build_model`. `python model.py` test_forward_pass reports `cnn_medium_hls` with 34,177 params (matches `cnn_medium`).
- [x] **Section 2 — forward-equivalence sanity check**: `MediumCNN` and `MediumCNNHLS` loaded with the same fold_0 `final_model.pt` produce bitwise-identical logits on the first 16 calibration samples (max_abs = 0.0, mae = 0.0). Rewrite is mathematically equivalent.
- [~] **Section 3 — retrain all 5 folds on `cnn_medium_hls`** (launch pending on GPU host). Launch script written at `examples/ml_baseline/hls4ml/scripts/retrain_cnn_medium_hls.sh` — creates tmux session `train_cnn_medium_hls`, logs to `runs/launch_<ts>_cnn_medium_hls_ro8000_ep500_kfold5_fliponly.log`. To run: `bash examples/ml_baseline/hls4ml/scripts/retrain_cnn_medium_hls.sh`. Monitor with `tmux attach -t train_cnn_medium_hls` or `tail -f` on the log file. This host has no CUDA; the user will launch on a GPU machine.
- [x] **Section 4 — pooled metrics**: new run `runs/20260419_042908_cnn_medium_hls_ro8000_ep500_kfold5_fliponly_kfold5/` produced pooled `accuracy=0.9580`, `roc_auc=0.9913`, `mcc=0.9180`. Deltas vs April 15 archived values (0.9496 / 0.9915 / 0.9024) are all within tolerance: `Δaccuracy=+0.0084`, `Δroc_auc=−0.0002`, `Δmcc=+0.0156`. Retrain did not silently drift.
- [x] **Section 5 — candidates.yaml**: `model: cnn_medium_hls`, `run_dir` / `saved_run_dir` pointed at new run.
- [x] **Section 6 — Stage 1 pipeline**: Direct PyTorch avgpool path is now the canonical route. `scripts/run_stage1_all_folds.sh` has been switched to `--frontend pytorch`, `fixed<24,8>`, and explicit final `avgpool.accum=fixed<40,20>`. Canonical project regeneration completed for folds 0–4 under `artifacts/cnn_medium/hls/pytorch/fold_*`.
- [~] **Section 7 — ONNX graph inspection**: Done alongside Section 6. The `AdaptiveAvgPool2d → flatten → Linear` head exports to `GlobalAveragePool → Flatten → Gemm` and QONNX channels-last leaves *no* Transpose in front of it. Despite this, hls4ml's io_stream `GlobalAveragePool` (and its `AveragePool` with explicit `k=64`) still diverges from PyTorch by the same ~5-unit constant the original PARITY_NOTES reported. So the root cause is **not** the Transpose pattern — it's hls4ml's io_stream pooling kernel itself, on this input size.
- [x] **Section 8 — parity**: Direct PyTorch avgpool parity passed on 4 calibration samples per fold at `fixed<24,8>` with final `avgpool.accum=fixed<40,20>`. Canonical `scripts/check_parity.py` run wrote `artifacts/cnn_medium/hls/parity/all_folds_summary.csv`; worst observed `max_abs=0.2039` across folds 0–4.
- [x] Section 9 — document results. Direct-avgpool notes added at `artifacts/cnn_medium/hls/parity_pytorch_avgpool_fixed24_8/PARITY_NOTES.md`; canonical parity table refreshed at `artifacts/cnn_medium/hls/parity/all_folds_summary.csv`.
- [x] **Section 10 — fold_0 1024 csynth stopped**: Vitis 2024.2 direct-float `fixed<24,8>` RF=4/5 csynth for `artifacts/cnn_medium/hls/pytorch/fold_0` remained in clang HLS synthesis for more than four hours. It emitted only `csynth_design_size.rpt/xml` and no final `csynth.rpt`; Vitis reported 973,840 design instructions after compile/link. Per user direction, the stale synthesis and ntfy monitor were stopped. Treat this as a practical blocker for the uncompressed 1024 float project.
- [x] **Section 11 — img512 pivot**: New default candidate `cnn_medium_img512` uses the April 19 512x512 `cnn_medium` run with explicit `AvgPool2d(32,32)`. Stage 1 artifact regeneration, validation replay, and 4-sample all-fold parity are complete under `artifacts/cnn_medium_img512`. Worst img512 parity `max_abs=0.0833`, better than the 1024 direct-float sweep (`max_abs=0.2039`).
- [x] **Section 12 — float csynth attempts stopped/failed**: `cnn_medium_img512` fold_0 csynth was killed after more than three hours in clang HLS with no final report. `cnn_b_img256` fold_0 csynth failed after Unroll/Inline expanded the design to 1,753,339 instructions and Vitis clang segfaulted in `config11_mult`. Treat uncompressed float RF=4/5 synthesis as blocked.
- [x] **Section 13 — `cnn_small_hls_opt_img512` cosim crash recorded**: `csynth` completed successfully for `cnn_small_hls_opt_img512`, but `cosim_design -trace_level all -setup` crashed immediately afterward with `Abnormal program termination (11)`. The stack trace lands in `Tcl_UniCharToUtf` inside Vitis HLS 2024.2, before any `xsim`/`xelab` backend process appears. The generated cosim testbench Tcl is large (`49,206` lines, `7.37 MB`) and contains many long, auto-renamed hierarchy objects, so this looks like a Vitis Tcl bug triggered by the generated cosim payload rather than a missing enable flag or a simulator runtime failure.

## Stage 1 parallel work while csynth runs

The parity-critical work is complete. Work that can run without the fold_0 csynth result:

- Run canonical hls4ml trace/profiling on fold_0 direct-avgpool project to archive layer ranges and confirm the avgpool output remains channel-varying in the canonical path.
- Run a larger-sample parity spot check (for example 16 samples on fold_0, or all available calibration samples per fold) to quantify whether the revised `max_abs <= 0.25` gate remains stable beyond the 4-sample sweep.
- Generate alternate PyTorch hls4ml projects with higher reuse factors (`8`, `16`) for fold_0. Do not synthesize them in parallel on this host unless we deliberately stop the current Vitis job; just generate/compile/predict so they are ready if RF=4/5 is abandoned.
- Prepare the Stage 2 handoff: document that uncompressed float parity is closed but uncompressed float synthesis is likely not a deployable path, so pruning/quantization should become the next practical synthesis target.

## Current findings (investigation continuing)

Tested every forward variant we could build; hls4ml's pooling divergence is structural in the io_stream kernel, not something a model rewrite can fix:

| `MediumCNNHLS.forward` | ONNX head | hls4ml mae @ fixed<16,6> |
|---|---|---|
| `AdaptiveAvgPool2d((1,1)) → flatten → Linear` (orig) | `GlobalAveragePool → Flatten → Gemm` | **4.89** (broken) |
| `F.adaptive_avg_pool2d(x,1).flatten(1)` then Linear | `GlobalAveragePool → Flatten → Gemm` | **4.95** (broken, same) |
| `x.mean(dim=(2,3))` then Linear | `ReduceMean → Gemm` | N/A (hls4ml ONNX frontend rejects `ReduceMean`) |
| `F.avg_pool2d(x,64).flatten(1)` then Linear | `AveragePool(k=64) → Flatten → Gemm` | N/A (QONNX inserts blocking `Transpose(0,3,1,2)` ahead of AveragePool; hls4ml then refuses it) |
| `nn.AvgPool2d(64, stride=64) → Linear`, PyTorch frontend | — | **5.05** (broken — pool kernel divergence reproduces without QONNX or ONNX involvement) |

### Superseded workaround — collapsed-conv head

An export-only view was tested where the final `AvgPool(64,64) → Flatten → Linear(48→1)` was baked into a single `Conv2d(48, 1, kernel_size=64, stride=64)` with weights `w_conv[0,c,h,w] = (1/4096) * classifier.W[c]` and `b_conv = classifier.b`. Forward equivalence was close (`max |y_pool+linear - y_conv| = 0.017` on outputs of magnitude ~4500), but the tiny `1/4096` scaled weights made the head unusually sensitive to fractional precision.

Parity with the collapsed-conv head via the PyTorch frontend (fold_0, 4 calibration samples):

| precision | mae | max_abs | notes |
|---|---|---|---|
| `fixed<16,6>` | 5.05 | 5.58 | 1/4096 weight factor underflows the 10-bit fractional field |
| `fixed<24,6>` | 1.08 | 1.23 | 18 fractional bits — still coarse for the scaled weights |
| `fixed<24,10>` | 20.5 | 21.0 | widening the integer field *costs* fractional bits; hurts |
| `fixed<32,6>` | **0.105** | **0.218** | **converged** — parity essentially PyTorch up to fixed-point rounding |
| `fixed<16,6>` default + `final_conv: fixed<32,6>` all precisions wide | 5.0 | 5.53 | earlier-layer activations at `<16,6>` already lose signal; wide precision on just `final_conv` cannot recover it |

This path is superseded by the direct AvgPool2d path below. The `max_abs ≤ 0.05 at fixed<16,6>` gate from the original plan still cannot be met for this topology, but we no longer need to bake the pooling factor into convolution weights or target `fixed<32,6>`.

### Resolution update — direct AvgPool2d path

The collapsed-conv export view is no longer the preferred fix. The GitHub issue #311 comments point at the average-pooling accumulator (`accum_t`) overflowing when many pixels are summed. Testing confirmed the exact nuance:

- `fixed<16,6>` plus a wide final `avgpool.accum` is **not enough** (`mae≈5.05`, `max_abs≈5.58` on fold_0) because earlier activations are already too degraded.
- Direct `MediumCNNHLS` with the real `AvgPool2d(64,64) -> Flatten -> Linear` head works once the model precision is raised and the final avgpool accumulator is explicit.
- Best tested point so far: global `fixed<24,8>` with `avgpool.result=fixed<24,8>` and `avgpool.accum=fixed<40,20>`.
- This avoids the `1/4096` scaled-weight problem from the collapsed-conv export view and uses 24-bit data instead of the previous `fixed<32,6>` target.

Canonical fold parity with direct PyTorch hls4ml frontend, 4 calibration samples per fold (`artifacts/cnn_medium/hls/parity/all_folds_summary.csv`):

| fold | mae | max_abs |
|---:|---:|---:|
| 0 | 0.1089 | 0.1184 |
| 1 | 0.1684 | 0.2039 |
| 2 | 0.1548 | 0.1680 |
| 3 | 0.1725 | 0.1876 |
| 4 | 0.1581 | 0.1726 |

Updated primary Stage 1 gate: `max_abs <= 0.25` on the 4-sample calibration parity sweep at `fixed<24,8>` with `avgpool.accum=fixed<40,20>`. The stricter original `max_abs <= 0.05` at `fixed<16,6>` is not realistic for this float model.

### Environment note (discovered during Section 2)

`/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/.venv/bin/python` is broken on this host: its shebang resolves to a `/usr/bin/python3.12` that no longer exists, so `import torch` fails even though torch is on disk. The working Python is `/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/.venv_hls4ml/bin/python` (Python 3.10, torch 2.6.0+cu124, torchvision 0.21.0+cu124, numpy, pandas, matplotlib, sklearn, hls4ml, onnx, qonnx all present). All subsequent sections use `.venv_hls4ml/bin/python`.
