# hls4ml Workspace

This directory is the dedicated `hls4ml` bring-up workspace for the bitstream
classifier models trained under [`../ml_baseline`](../ml_baseline).

The initial candidate is `cnn_medium`, selected because it is materially
smaller than `cnn_b` while still being one of the strongest April 15 models.
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
- The baseline `cnn_medium` parity stage has been regenerated under
  `artifacts/cnn_medium/pytorch_float` and currently reproduces pooled metrics
  of `accuracy=0.9496`, `roc_auc=0.9915`, and `mcc=0.9024`.
- The visibility tooling is live:
  `artifacts/cnn_medium/stage_ledger.csv` consolidates per-sample outputs and
  `scripts/compare_stages.py` writes aligned stage-to-stage deltas by sample.
- The hardware side is scaffolded as a standard Coyote example, but the actual
  generated `hls4ml` network source still needs to be dropped into the HLS
  kernel directory once the external toolchain is available.

## Typical Commands

Run a fold-level baseline evaluation:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/hls4ml
../ml_baseline/.venv/bin/python scripts/evaluate_candidate.py --candidate cnn_medium
```

Export a deterministic calibration bundle and fixed-length sample blobs:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/hls4ml
../ml_baseline/.venv/bin/python scripts/export_calibration_data.py --candidate cnn_medium --fold 0 --max-samples 16
```

Check the local HLS environment:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/hls4ml
../ml_baseline/.venv/bin/python scripts/check_environment.py
```

Write a consolidated per-sample stage ledger:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/hls4ml
../ml_baseline/.venv/bin/python scripts/build_stage_ledger.py --candidate cnn_medium --output artifacts/cnn_medium/stage_ledger.csv
```

Compare two stages on aligned samples:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/hls4ml
../ml_baseline/.venv/bin/python scripts/compare_stages.py --candidate cnn_medium --left-stage pytorch_float --right-stage pytorch_float --output artifacts/cnn_medium/pytorch_float/self_compare.csv
```

Export ONNX once `onnx` is installed:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/hls4ml
../ml_baseline/.venv/bin/python scripts/export_onnx.py --candidate cnn_medium --fold 0
```

Convert to `hls4ml` once `hls4ml`, `onnx`, and `qonnx` are installed:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/hls4ml
../ml_baseline/.venv/bin/python scripts/convert_to_hls.py --candidate cnn_medium --frontend pytorch --fold 0 --reuse-factor 4
```

## Notes

- The evaluation scripts reconstruct the saved k-fold validation splits from the
  archived per-sample CSVs, so they do not need separate split manifests for
  the existing April 15 runs.
- The ONNX/QONNX and `hls4ml` entrypoints are implemented, but they currently
  stop early on this machine because `onnx`, `qonnx`, `hls4ml`, and the AMD HLS
  toolchain are not installed in the active environment.
- The `sw` harness currently expects a fixed-length `1048576`-byte sample blob.
  The export script writes these blobs directly so the first hardware loop can
  operate on deterministic inputs without re-implementing the full host-side
  dataset pipeline in C++.
