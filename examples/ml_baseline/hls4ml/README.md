# hls4ml Workspace

This workspace now contains the YAML-driven implementation of the
`cnn_small_hls_opt_img512` hls4ml notebook flow, including quantized,
float, pruned, and unpruned training variants.

The runner owns the full path from deterministic balanced k-fold training
through hls4ml emulation, Vitis synthesis, U55C bitstream staging/build,
deployment, and final hardware validation. Generated Coyote hardware/software
sources are staged inside each run directory.

## Layout

- `configs/hls4ml_runs/`
  YAML configs for full and smoke runs.
- `pipeline/part1_common.py` through `pipeline/part7_runner.py`
  Numbered implementation of the notebook behavior, split into shared helpers,
  training, hls4ml, U55C bitstream, deployment, validation, and dispatch parts.
- `pipeline/notebook_flow.py`
  Compatibility re-export module for existing imports.
- `pipeline/qkeras_plots.py`
  Plotting adapters for the parent `ml_baseline/train.py` plot utilities.
- `scripts/hls4ml_run.py`
  The only user-facing entrypoint.
- `artifacts/`
  Generated run directories, cache manifests, plots, bitstreams, deployment
  outputs, and validation artifacts.

## Commands

Run training, HLS conversion/synthesis, and U55C bitstream build for the
default pruned-QAT configuration:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml
./scripts/hls4ml_run.py --config configs/hls4ml_runs/cnn_small_hls_opt_img512_pruned_qat_u55c.yaml --stages train,hls,bitstream
```

Run the same flow without quantization-aware layers and without pruning:

```bash
./scripts/hls4ml_run.py --config configs/hls4ml_runs/cnn_small_hls_opt_img512_float_u55c.yaml --stages train,hls
```

Quantization and pruning are controlled independently in YAML:

```yaml
quantization:
  enabled: false  # false uses standard float Keras Conv2D/Dense/ReLU layers
  tag: float32

pruning:
  enabled: true   # can be true or false independently of quantization
```

With `quantization.enabled: true`, the trainer uses the existing QKeras QAT
layers. With `quantization.enabled: false`, it uses ordinary float Keras layers
with the same topology and layer names. `pruning.enabled` controls
`tensorflow_model_optimization` pruning for either model flavor.

Supported combinations:

| Quantization | Pruning | Stage label | Example config |
| --- | --- | --- | --- |
| enabled | enabled | `pruned_qat` | `configs/hls4ml_runs/cnn_small_hls_opt_img512_pruned_qat_u55c.yaml` |
| enabled | disabled | `qat` | `configs/hls4ml_runs/cnn_small_hls_opt_img512_qat_noprune_u55c.yaml` |
| disabled | enabled | `pruned_float` | `configs/hls4ml_runs/cnn_small_hls_opt_img512_pruned_float_u55c.yaml` |
| disabled | disabled | `float` | `configs/hls4ml_runs/cnn_small_hls_opt_img512_float_u55c.yaml` |

Run float training with pruning enabled:

```bash
./scripts/hls4ml_run.py --config configs/hls4ml_runs/cnn_small_hls_opt_img512_pruned_float_u55c.yaml --stages train,hls
```

Resume on the U55C host from the same shared run directory:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml
./scripts/hls4ml_run.py --config configs/hls4ml_runs/cnn_small_hls_opt_img512_pruned_qat_u55c.yaml --run-root <existing_run_root> --stages deploy,validate
```

Exercise config loading and manifest/index creation without expensive work:

```bash
./scripts/hls4ml_run.py --config configs/hls4ml_runs/cnn_small_hls_opt_img512_pruned_qat_u55c_fold0.yaml --stages ''
```

## Experiment Suite

Generate the automated experiment configs and feasibility table:

```bash
./scripts/generate_experiment_configs.py \
  --suite configs/hls4ml_experiment_suite.yaml \
  --output-dir configs/hls4ml_experiment \
  --results-dir results \
  --phases 1,2,3
```

Run generated configs in parallel and record suite-level status rows:

```bash
./scripts/run_experiment_configs_parallel.py \
  --configs configs/hls4ml_experiment \
  --phases 1,2 \
  --stages train,hls \
  --results-dir results \
  --log-dir logs/experiment_parallel \
  --jobs 8 \
  --hls-timeout 10h
```

`--hls-timeout` starts when a run reaches `vitis_hls -f build_prj.tcl`. If the
compile exceeds the limit, the run is killed and marked in `results/suite_status.csv`
as `status=failed`, `failure_stage=hls`.

Monitor status:

```bash
python - <<'PY'
import csv, collections
rows = list(csv.DictReader(open("results/suite_status.csv")))
print(collections.Counter(row["status"] for row in rows))
for row in rows:
    print(row["status"], row["experiment_name"])
PY
```

Manually time out long-running HLS jobs without waiting for the automatic limit:

```bash
./scripts/experimentctl.py timeout \
  --results-dir results \
  --older-than 10h \
  --tier yellow
```

The command previews matching runs by default. Add `--yes` to kill the matching
process trees and mark them as HLS timeout failures:

```bash
./scripts/experimentctl.py timeout \
  --results-dir results \
  --older-than 10h \
  --tier yellow \
  --reason "manual timeout after boundary HLS exceeded 10h" \
  --yes
```

After marking timeouts, collect tables and regenerate plots:

```bash
./scripts/collect_experiment_results.py \
  --configs configs/hls4ml_experiment \
  --artifacts artifacts \
  --results-dir results

./scripts/plot_experiment_results.py \
  --summary results/experiment_summary.csv \
  --output-dir results/plots
```

Run the U55C wrapper C-sim test for a staged deployment:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml
export CLI_PATH=/opt/hdev/cli
export TERM=${TERM:-xterm}
source /opt/hdev/cli/enable/vitis -v 2024.2
../.venv_hls4ml/bin/python scripts/test_u55c_wrapper_csim.py \
  --u55c-root <hls_sweep_root>/fold_0/u55c_deployment \
  --work-dir /tmp/u55c_wrapper_csim_run \
  --max-samples 1
```

This copies the staged `coyote_qkeras_infer` kernel into the work directory,
runs Vitis HLS C simulation, and compares the wrapper output against
`fold_0/parity/hls_per_sample.csv`. Results are written to
`wrapper_csim_results.csv`; the Vitis HLS log is `vitis_hls_csim.log`.

The test checks C-level AXI packing, wrapper input unpacking, hls4ml invocation,
and output fixed-point conversion. It does not validate RTL handshakes, Coyote
shell integration, or hardware timing.

To isolate per-invocation static state, run selected samples as separate C-sim
processes and aggregate the results:

```bash
../.venv_hls4ml/bin/python scripts/test_u55c_wrapper_csim.py \
  --u55c-root <hls_sweep_root>/fold_0/u55c_deployment \
  --work-dir /tmp/u55c_wrapper_csim_separate \
  --sample-index 3 \
  --sample-index 4 \
  --sample-index 5 \
  --max-samples 0 \
  --separate-process-per-sample
```

Run the same wrapper test through Vitis HLS RTL cosimulation:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml
export CLI_PATH=/opt/hdev/cli
export TERM=${TERM:-xterm}
source /opt/hdev/cli/enable/vitis -v 2024.2
../.venv_hls4ml/bin/python scripts/test_u55c_wrapper_csim.py \
  --u55c-root <hls_sweep_root>/fold_0/u55c_deployment \
  --work-dir /tmp/u55c_wrapper_cosim_run \
  --max-samples 1 \
  --run-cosim
```

With `--run-cosim`, the script runs `csim_design`, `csynth_design`, and
`cosim_design -rtl verilog -tool xsim` using the same generated testbench
inputs. Results are written to `wrapper_cosim_results.csv`; the Vitis HLS log
is `vitis_hls_cosim.log`. This checks the generated RTL control protocol and
AXI stream handshakes for `coyote_qkeras_infer`, but still does not include the
full Coyote shell or `vfpga_top.svh`.

**Csynth takes ~20 minutes.** The completed RTL output is cached under the
`--work-dir`. If cosim is killed or times out before xsim finishes, resume with
`--resume-cosim` to skip csim+csynth and retry only the cosim step:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml
export CLI_PATH=/opt/hdev/cli
export TERM=${TERM:-xterm}
source /opt/hdev/cli/enable/vitis -v 2024.2
../.venv_hls4ml/bin/python scripts/test_u55c_wrapper_csim.py \
  --u55c-root <hls_sweep_root>/fold_0/u55c_deployment \
  --work-dir /tmp/u55c_wrapper_cosim_run \
  --max-samples 1 \
  --run-cosim \
  --resume-cosim
```

`--resume-cosim` reopens the existing HLS project without `-reset`, preserving
all csynth artifacts, and calls `cosim_design` directly. The sentinel checked is
`wrapper_cosim/solution1/syn/verilog/coyote_qkeras_infer.v`. Note that xsim
elaboration of the ~130 generated Verilog files for this CNN design can itself
take 30–60+ minutes before any simulation output appears.

For hardware deployment debugging, the staged `coyote_qkeras_host` supports
`--max-samples` and `--skip-samples` so one manifest row can be run per process:

```bash
<u55c_deployment>/coyote_sw/build/coyote_qkeras_host \
  --manifest <u55c_deployment>/prepared_inputs/manifest.csv \
  --output <u55c_deployment>/hardware_isolated_sample_0003.csv \
  --skip-samples 3 \
  --max-samples 1
```

## Caching

Each stage writes a manifest under the run root or HLS sweep root and reuses
outputs when fingerprints and required artifacts match. Use `--force` to rerun
the requested stages.

For the U55C bitstream stage, `--force` removes the local Coyote hardware build
directory before rebuilding. This is intentional: generated packaged IP under
`coyote_hw/build_u55c/iprepo` can otherwise survive a source restage and feed
Vivado stale RTL. The bitstream stage also verifies that the packaged
`coyote_qkeras_infer_hls_ip` no longer exposes `ap_start`, `ap_done`,
`ap_idle`, or `ap_ready` before recording a successful manifest.

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
