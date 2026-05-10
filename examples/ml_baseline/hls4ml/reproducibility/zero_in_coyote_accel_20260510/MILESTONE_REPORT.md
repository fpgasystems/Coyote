# Zero-In CoyoteAccelerator Milestone

This package records the first validated end-to-end `zero_in` deployment through the hls4ml `CoyoteAccelerator` backend.

## Outcome

- Built the `zero_in` hls4ml model with `backend="CoyoteAccelerator"` and `io_type="io_stream"`.
- Patched the generated AXI-stream input adapter to avoid the pathological Vitis HLS instruction explosion.
- Exported HLS IP, generated a Coyote bitstream, programmed the FPGA, and validated CPU Keras logits against FPGA logits.
- Device used: Alveo U55C on `alveo-u55c-07.inf.ethz.ch`.

Validation summary:

| Check | Result |
| --- | --- |
| Samples | 48 |
| Batch size | 16 |
| Tolerance | 0.20 logit absolute difference |
| Passed | true |
| Logit MAE | 0.049686431884765625 |
| Max absolute logit diff | 0.1455078125 |
| Prediction agreement | 0.9791666666666666 |
| Sign mismatches | 1 |
| CPU accuracy | 0.8541666666666666 |
| FPGA accuracy | 0.875 |

## Source Baseline

| Source | Path | Revision |
| --- | --- | --- |
| Coyote / ml baseline repo | `/pub/scratch/sdeheredia/Coyote` | `d3b507d29c33136294878ab67ab77763b17962c0` on `full-dataset-ml-baseline-1d` |
| hls4ml CoyoteAccelerator checkout | `/pub/scratch/sdeheredia/hls4ml` | `d4a6a2f5bee752e5d3738f136726fea722cc65e4` on `coyote-accelerator` |
| Original CoyoteAccelerator example docs | `/pub/scratch/sdeheredia/main_Coyote/experiments/07_hls4ml` | copied snapshots in this package |

Relevant hls4ml submodules:

| Submodule | Revision |
| --- | --- |
| `example-models` | `e7a9dee394b6c1f6e0eb23178d34e55f077297fe` |
| `hls4ml/contrib/Coyote` | `292ec1521c4a9a1cc9b1335dee6b99deabb38542` |
| `hls4ml/contrib/Coyote/hw/services/network` | `9eda6ce9a55c0761ee9e66d1eba38ad5c9474aa9` |

## Pipeline

```mermaid
flowchart LR
    A["trained zero_in QKeras model<br/>model_config.json + weights"] --> B["zero_in_synth.py<br/>load model and arrays"]
    B --> C["hls4ml convert_from_keras_model<br/>CoyoteAccelerator + io_stream"]
    C --> D["generated HLS project<br/>wrapper + firmware"]
    D --> E["source patch<br/>AXI adapter loop pragmas"]
    E --> F["hls4ml compile smoke<br/>Keras CPU vs hls4ml C sim"]
    F --> G["Vitis HLS synth/export"]
    G --> H["Coyote bitstream generation"]
    H --> I["program U55C"]
    I --> J["zero_in_inference_validate.py"]
    J --> K["CPU Keras logits vs FPGA logits"]
```

## Important Files

```mermaid
flowchart TD
    R["zero_in_coyote_accel_20260510/"]
    R --> S["sources/"]
    R --> N["non_vcs_artifacts/"]
    R --> O["results/"]
    R --> M["manifest.json"]
    R --> V["verify_manifest.py"]
    S --> S1["ml_baseline/hls4ml/scripts/coyote_accelerator/<br/>build + validation scripts"]
    S --> S2["hls4ml_pr/hls4ml/backends/coyote_accelerator/<br/>backend + overlay snapshots"]
    S --> S3["generated_project/src/hls/model_wrapper/<br/>generated wrapper snapshots"]
    S --> S4["generated_project/src/hls/firmware/<br/>generated CNN + patched stream adapter"]
    S --> S5["main_Coyote/experiments/07_hls4ml/<br/>original example snapshots"]
    N --> N1["runtime_project/build/.../bitstreams/<br/>cyt_top.bit and related files"]
    N --> N2["runtime_project/build/.../cyt_sw/<br/>libCoyoteInference.so and host runtime"]
    N --> N3["model/fold_0/<br/>model JSON and weights"]
    N --> N4["prepared_inputs/<br/>x_norm.npy and labels.npy"]
    O --> O1["compile_smoke/<br/>CPU vs hls4ml compile check"]
    O --> O2["fpga_validation/<br/>CPU vs FPGA validation"]
    O --> O3["logs/<br/>build, export, bitgen, validation logs"]
```

## Artifact Paths

| Artifact | Original path | Packaged path |
| --- | --- | --- |
| Build run root | `/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/artifacts/coyote_accelerator_zero_in_e2e/20260509_173826` | this directory |
| Bitstream | `.../20260509_173826/project/build/zero_in_coyote_accel_cyt_hw/bitstreams/cyt_top.bit` | `non_vcs_artifacts/runtime_project/build/zero_in_coyote_accel_cyt_hw/bitstreams/cyt_top.bit` |
| Host inference library | `.../20260509_173826/project/build/zero_in_coyote_accel_cyt_sw/lib/libCoyoteInference.so` | `non_vcs_artifacts/runtime_project/build/zero_in_coyote_accel_cyt_sw/lib/libCoyoteInference.so` |
| Validation summary | `.../20260509_173826/fpga_validation/validation_summary.json` | `results/fpga_validation/validation_summary.json` |
| FPGA predictions | `.../20260509_173826/fpga_validation/predictions.csv` | `results/fpga_validation/predictions.csv` |
| Prepared input array | `.../ZERO_IN_res256_layers5_W8A8_P50_RFbase_07faeca37cb7/hls_sweeps/RFbase_hls_a121fc48614f/fold_0/u55c_deployment/prepared_inputs/x_norm.npy` | `non_vcs_artifacts/prepared_inputs/x_norm.npy` |
| Labels | same prepared input directory, `labels.npy` | `non_vcs_artifacts/prepared_inputs/labels.npy` |
| Model weights | `.../ZERO_IN_res256_layers5_W8A8_P50_RFbase_07faeca37cb7/fold_0/final_weights.weights.h5` | `non_vcs_artifacts/model/fold_0/final_weights.weights.h5` |

All copied files, including ignored heavy artifacts, are listed with size and SHA-256 in `manifest.json`.

## Adapter Issue And Patch

The `zero_in` input tensor has `256 * 256 * 1 = 65536` scalar `float32` values. Coyote uses a 512-bit AXI stream, so each AXI beat carries 16 `float32` values:

```text
65536 floats / 16 floats per beat = 4096 AXI beats
```

The generated `axi_stream_to_data` adapter originally had a function-level `#pragma HLS PIPELINE` while also unrolling the inner 16-lane extraction loop. For this input size, Vitis HLS effectively expanded the adapter into a very large instruction body. The report was dominated by the adapter, with roughly 3.1M instructions.

We patched the generated `nnet_axi_utils_stream.h` to:

- remove the function-level pipeline pragma;
- add `#pragma HLS PIPELINE II=1` on the outer AXI-beat loop;
- keep the inner 16-lane loop unrolled.

The intended hardware behavior is still one 512-bit input beat per cycle after pipeline fill, while preventing full expansion of the 4096-beat loop.

Patched shape:

```cpp
for (int i = 0; i < NUM_BEATS; i++) {
    #pragma HLS PIPELINE II=1
    ap_axiu<...> axi_packet = axi_in.read();
    for (int j = 0; j < ELEMENTS_PER_AXI; j++) {
        #pragma HLS UNROLL
        ...
    }
}
```

The patched generated file snapshot is:

`sources/generated_project/src/hls/firmware/nnet_utils/nnet_axi_utils_stream.h`

The build script source that applies the patch is:

`sources/ml_baseline/hls4ml/scripts/coyote_accelerator/zero_in_synth.py`

## Runtime Data Path

```mermaid
flowchart LR
    A["prepared_inputs/x_norm.npy<br/>N x 256 x 256 x 1 float32"] --> B["Python validation script"]
    B --> C["CoyoteOverlay.predict"]
    C --> D["libCoyoteInference.so<br/>host runtime"]
    D --> E["Coyote driver + DMA"]
    E --> F["512-bit AXI stream<br/>16 float32 values per beat"]
    F --> G["model_wrapper<br/>axi_stream_to_data"]
    G --> H["hls::stream<input_t><br/>one scalar pixel token"]
    H --> I["zero_in_coyote_accel CNN"]
    I --> J["output adapter"]
    J --> K["host result buffer"]
    K --> L["CPU-vs-FPGA validation"]
```

The stream entering the hls4ml CNN still uses the hls4ml token type:

```cpp
typedef nnet::array<ap_fixed<16,6>, 1*1> input_t;
```

So the Coyote wrapper receives wide 512-bit AXI beats, then writes one `input_t` token per scalar pixel into the hls4ml model stream.

## Manifest Policy

Track in git:

- this report;
- `manifest.json`;
- `verify_manifest.py`;
- source snapshots under `sources/`;
- result summaries and logs under `results/`.

Do not track in git:

- `non_vcs_artifacts/runtime_project/build/.../bitstreams/`;
- `non_vcs_artifacts/runtime_project/build/.../cyt_sw/`;
- `non_vcs_artifacts/model/`;
- `non_vcs_artifacts/prepared_inputs/`.

Those ignored files are still hashed in `manifest.json` so they can be copied to a backed-up filesystem and verified later.

## Reproduce From Source

These commands assume the same machine family, Xilinx 2024.2 tools, the copied hls4ml PR checkout, and the ml_baseline repo layout used above.

```bash
set -euo pipefail

export COYOTE_ROOT=/pub/scratch/sdeheredia/Coyote
export ML_ROOT=$COYOTE_ROOT/examples/ml_baseline
export HLS4ML_PR=/pub/scratch/sdeheredia/hls4ml
export VENV=$ML_ROOT/.venv_hls4ml_coyote
export RUN_ROOT=$ML_ROOT/hls4ml/artifacts/coyote_accelerator_zero_in_e2e/$(date +%Y%m%d_%H%M%S)

cd "$HLS4ML_PR"
git submodule update --init --recursive

source "$VENV/bin/activate"
python -m pip install -e "$HLS4ML_PR"

cd /tmp
export PYTHONPATH="$HLS4ML_PR:$ML_ROOT/hls4ml/scripts/coyote_accelerator:$ML_ROOT"
python - <<PY
import runpy, sys
sys.argv = [
    "zero_in_synth.py",
    "--output-parent", "$ML_ROOT/hls4ml/artifacts/coyote_accelerator_zero_in_e2e",
    "--timestamp", "$(basename "$RUN_ROOT")",
]
runpy.run_path("$ML_ROOT/hls4ml/scripts/coyote_accelerator/zero_in_synth.py", run_name="__main__")
PY
```

The successful milestone needed a resumed export and bitstream generation after the Python build reached the generated project. The captured logs and command files are under `results/logs/`.

## Replay Validation From This Package

This uses the packaged bitstream, host library, model weights, and prepared inputs. It reprograms the local U55C and runs the same CPU-vs-FPGA comparison.

```bash
set -euo pipefail

export PKG=/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/reproducibility/zero_in_coyote_accel_20260510
export ML_ROOT=/pub/scratch/sdeheredia/Coyote/examples/ml_baseline
export HLS4ML_PR=/pub/scratch/sdeheredia/hls4ml
export VENV=$ML_ROOT/.venv_hls4ml_coyote

source "$VENV/bin/activate"
source /tools/Xilinx/Vitis/2024.2/settings64.sh

cat > "$PKG/non_vcs_artifacts/runtime_manifest.json" <<EOF
{
  "project_dir": "$PKG/non_vcs_artifacts/runtime_project",
  "project_name": "zero_in_coyote_accel",
  "output_dir": "$PKG/replay",
  "stage": "runtime_replay"
}
EOF

cd "$PKG/non_vcs_artifacts/runtime_project/Coyote/driver"
make

cd "$PKG/non_vcs_artifacts/runtime_project/Coyote/util"
bash program_hacc_local.sh \
  "$PKG/non_vcs_artifacts/runtime_project/build/zero_in_coyote_accel_cyt_hw/bitstreams/cyt_top.bit" \
  "$PKG/non_vcs_artifacts/runtime_project/Coyote/driver/build/coyote_driver.ko"

cd /tmp
export LD_LIBRARY_PATH="$PKG/non_vcs_artifacts/runtime_project/build/zero_in_coyote_accel_cyt_sw:${LD_LIBRARY_PATH:-}"
export PYTHONPATH="$HLS4ML_PR:$PKG/sources/ml_baseline/hls4ml/scripts/coyote_accelerator:$ML_ROOT"
python - <<PY
import runpy, sys
sys.argv = [
    "zero_in_inference_validate.py",
    "--manifest", "$PKG/non_vcs_artifacts/runtime_manifest.json",
    "--config", "$PKG/sources/ml_baseline/hls4ml/configs/hls4ml_experiment/res256_layers5_W8A8_P50_RFbase.yaml",
    "--run-root", "$PKG/non_vcs_artifacts/model",
    "--input-root", "$PKG/non_vcs_artifacts/prepared_inputs",
    "--batch-size", "16",
    "--n-samples", "48",
    "--tolerance", "0.20",
]
runpy.run_path("$PKG/sources/ml_baseline/hls4ml/scripts/coyote_accelerator/zero_in_inference_validate.py", run_name="__main__")
PY
```

Verify the package hashes:

```bash
set -euo pipefail
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/reproducibility/zero_in_coyote_accel_20260510
python3 verify_manifest.py
python3 verify_manifest.py --include-non-vcs
```

The same replay flow is also captured as:

```bash
set -euo pipefail
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/reproducibility/zero_in_coyote_accel_20260510
./run_replay_validation.sh
```

## Reproducibility Checks Performed

Package manifest verification passed on `alveo-u55c-07.inf.ethz.ch`:

```text
python3 verify_manifest.py
checked=45 skipped=66 failures=0

python3 verify_manifest.py --include-non-vcs
checked=111 skipped=0 failures=0
```

I also launched `run_replay_validation.sh` from tmux on 2026-05-10. It rebuilt the packaged Coyote driver and successfully programmed the copied `cyt_top.bit`; then `hdev program driver` hit an interactive sudo password prompt while deleting the already-staged driver file under `/tmp/devices_acap_fpga_drivers/`. Because this was a non-interactive run, the replay was stopped before inference. The original milestone validation results above remain the successful CPU-vs-FPGA result for this bitstream.

If rerunning interactively, expect the driver insertion step to require sudo credentials when an existing `coyote_driver` is present.
