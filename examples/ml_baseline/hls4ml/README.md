# hls4ml Workspace

This workspace now contains the YAML-driven implementation of the
`cnn_small_hls_opt_img512` pruned-QAT hls4ml notebook flow.

The runner owns the full path from deterministic balanced k-fold training
through hls4ml emulation, Vitis synthesis, U55C bitstream staging/build,
deployment, and final hardware validation. Generated Coyote hardware/software
sources are staged inside each run directory.

## Layout

- `configs/hls4ml_runs/`
  YAML configs for full and smoke runs.
- `pipeline/notebook_flow.py`
  Shared implementation of the notebook behavior.
- `pipeline/qkeras_plots.py`
  Plotting adapters for the parent `ml_baseline/train.py` plot utilities.
- `scripts/hls4ml_run.py`
  The only user-facing entrypoint.
- `artifacts/`
  Generated run directories, cache manifests, plots, bitstreams, deployment
  outputs, and validation artifacts.

## Commands

Run training, HLS conversion/synthesis, and U55C bitstream build:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml
./scripts/hls4ml_run.py --config configs/hls4ml_runs/cnn_small_hls_opt_img512_pruned_qat_u55c.yaml --stages train,hls,bitstream
```

Resume on the U55C host from the same shared run directory:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml
./scripts/hls4ml_run.py --config configs/hls4ml_runs/cnn_small_hls_opt_img512_pruned_qat_u55c.yaml --run-root <existing_run_root> --stages deploy,validate
```

Exercise config loading and manifest/index creation without expensive work:

```bash
./scripts/hls4ml_run.py --config configs/hls4ml_runs/smoke_cnn_small_hls_opt_img512_pruned_qat.yaml --stages ''
```

## Caching

Each stage writes a manifest under the run root or HLS sweep root and reuses
outputs when fingerprints and required artifacts match. Use `--force` to rerun
the requested stages.

The runner writes `run_index.md` at the run root with direct paths to manifests,
plots, reports, bitstreams/DCPs, deployment outputs, latency summaries, and
final validation artifacts.

Auto-created run roots are prefixed with `YYYYMMDD_HHMMSS`, so the run
directory sorts chronologically by name. Pass `--run-root <existing_run_root>`
to resume a specific run instead of creating a new timestamped directory.

## Toolchain

For toolchain-dependent stages, `toolchain.auto_enable: true` discovers the
latest common version under `/tools/Xilinx/{Vivado,Vitis,Vitis_HLS}` and
re-execs through:

```bash
export CLI_PATH=/opt/hdev/cli
export TERM=${TERM:-xterm}
source /opt/hdev/cli/enable/vivado -v "$VERSION"
source /opt/hdev/cli/enable/vitis -v "$VERSION"
```

The enable helpers are always called with `-v <version>` to avoid the
interactive selector.
