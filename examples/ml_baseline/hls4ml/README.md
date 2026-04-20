# hls4ml Workspace

This directory is the dedicated `hls4ml` bring-up workspace for the bitstream
classifier models trained in the parent [`ml_baseline`](..).

The active candidate is `cnn_medium_img512`, selected after the 1024x1024
direct-float project reached parity but stalled in Vitis csynth. It uses the
April 19 512x512 `cnn_medium` run with an HLS-specific explicit final average
pool.
The workspace is intentionally candidate-driven so that `cnn_b` can be added
later without restructuring the flow.

## Layout

- `configs/candidates.yaml`
  Candidate registry, run roots, and target hardware defaults.
- `pipeline/`
  Shared Python modules for candidate resolution, evaluation, and exports.
- `scripts/`
  User-facing entry points for evaluation, exports, and environment checks.
- `artifacts/`
  Generated evaluation outputs, stage summaries, and calibration exports.
- `hw/`
  Coyote hardware example skeleton for inference.
- `sw/`
  Coyote software harness for sending fixed-length sample blobs to the FPGA.

## Current State

- The Python evaluation/export path is usable immediately against the existing
  `ml_baseline` checkpoints and fold CSVs.
- The active `cnn_medium_img512` PyTorch validation replay has been regenerated
  under `artifacts/cnn_medium_img512/pytorch_float` and matches the archived
  fold metrics exactly; pooled replay metrics are `accuracy=0.9370`,
  `roc_auc=0.9775`, and `mcc=0.8747`.
- The visibility tooling is live:
  `artifacts/cnn_medium/stage_ledger.csv` consolidates per-sample outputs and
  `scripts/compare_stages.py` writes aligned stage-to-stage deltas by sample.
- Stage 1 float parity now uses direct PyTorch hls4ml conversion of
  `cnn_medium_hls_img512` with its real `AvgPool2d(32,32)` head. The tested
  precision point is global `fixed<24,8>` with
  `avgpool.accum=fixed<40,20>`; the all-fold 4-sample parity summary is under
  `artifacts/cnn_medium_img512/hls/parity/`.
- The hardware side is scaffolded as a standard Coyote example, but the actual
  generated `hls4ml` network source still needs to be dropped into the HLS
  kernel directory once the external toolchain is available.

## Typical Commands

Run a fold-level baseline evaluation:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml
../../ml_baseline/.venv_hls4ml/bin/python scripts/evaluate_candidate.py --candidate cnn_medium_img512
```

Export a deterministic calibration bundle and fixed-length sample blobs:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml
../../ml_baseline/.venv_hls4ml/bin/python scripts/export_calibration_data.py --candidate cnn_medium_img512 --fold 0 --max-samples 16
```

Check the local HLS environment:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml
../../ml_baseline/.venv_hls4ml/bin/python scripts/check_environment.py
```

Write a consolidated per-sample stage ledger:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml
../../ml_baseline/.venv_hls4ml/bin/python scripts/build_stage_ledger.py --candidate cnn_medium_img512 --output artifacts/cnn_medium_img512/stage_ledger.csv
```

Compare two stages on aligned samples:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml
../../ml_baseline/.venv_hls4ml/bin/python scripts/compare_stages.py --candidate cnn_medium_img512 --left-stage pytorch_float --right-stage pytorch_float --output artifacts/cnn_medium_img512/pytorch_float/self_compare.csv
```

Convert to `hls4ml` (PyTorch → Vitis, no ONNX):

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml
../../ml_baseline/.venv_hls4ml/bin/python scripts/convert_to_hls.py --candidate cnn_medium_img512 --fold 0 --reuse-factor 4 --default-precision "fixed<24,8>"
```

## Notes

- The evaluation scripts reconstruct the saved k-fold validation splits from the
  archived per-sample CSVs, so they do not need separate split manifests for
  the existing April 15 runs.
- The `hls4ml` entrypoint uses the direct PyTorch frontend; `onnx`/`qonnx`
  are not required. The AMD HLS toolchain (Vitis) must be enabled in the
  shell before running csynth.
- The `sw` harness currently expects a fixed-length `1048576`-byte sample blob.
  The export script writes these blobs directly so the first hardware loop can
  operate on deterministic inputs without re-implementing the full host-side
  dataset pipeline in C++.
