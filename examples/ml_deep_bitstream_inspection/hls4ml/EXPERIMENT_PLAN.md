# Automated Experiment Plan: Phase 1–Phase 5

## Goal

Systematically evaluate CNN-based bitstream-inspection models across:

```text
input resolution
architecture depth
quantization precision
pruning
hls4ml reuse factor / hardware parallelism
```

The main outputs should be:

```text
accuracy / AUC / FNR / F1
hls4ml parity
synthesis feasibility
FPGA resources
latency
```

The plan should be automated and reproducible. The agent should treat the repository as the source of truth for exact training, conversion, and synthesis commands.

---

# Experimental assumptions

The completed run under:

```text
artifacts/cnn_small_hls_opt_img512/notebook_pruned_qat/BASELINE_pruned_qat_w6_a6_s50_pruneend200_kfold5_db9a98479fa8
```

is treated as a **known-working reference run**, not as the unpruned baseline for Phases 1–3.

For Phases 1–3, pruning and QAT should be disabled where supported. These phases study only the coupled resolution-depth feasibility space.

For Phase 4, quantization is introduced and swept over explicit W/A bit widths.

For Phase 4.5, pruning is introduced and swept over explicit sparsity targets.

For Phase 5, the selected trained model is fixed; only hls4ml reuse factor changes.

---

# Fixed model architecture anchor

Use this model shape as the architectural anchor:

```yaml
model:
  input_shape: [512, 512, 1]
  conv_specs:
    - {filters: 8,  kernel: [5, 5], strides: [2, 2], pad: 2, name: conv0}
    - {filters: 16, kernel: [3, 3], strides: [1, 1], pad: 1, name: conv1}
    - {filters: 24, kernel: [3, 3], strides: [1, 1], pad: 1, name: conv2}
    - {filters: 24, kernel: [3, 3], strides: [1, 1], pad: 1, name: conv3}
    - {filters: 32, kernel: [3, 3], strides: [1, 1], pad: 1, name: conv4}
  final_avg_pool: [8, 8]
  output_units: 1
```

We already have a completed quantized + pruned reference run, end-to-end minus Coyote deployment, under:

```text
artifacts/cnn_small_hls_opt_img512/notebook_pruned_qat/BASELINE_pruned_qat_w6_a6_s50_pruneend200_kfold5_db9a98479fa8
```

No need to re-run this reference unless explicitly needed.

The Phase 1 unpruned/non-QAT baseline experiment name should be:

```text
res512_layers5_WfloatAfloat_P0_RFbase
```

The existing reference run can be named separately as:

```text
res512_layers5_W6A6_P50_RFbase_reference
```

For the 512×512, 5-layer architecture, the spatial shape progression is approximately:

```text
512×512
  → conv0 stride 2
256×256
  → pool0
128×128
  → pool1
64×64
  → pool2
32×32
  → pool3
16×16
  → pool4
8×8
  → final AveragePooling2D(8×8)
```

So the final pooling window is only `8×8`, which is known to be easily synthesizable.

---

# Important design constraint

Input resolution and architecture depth are **not independent**.

A shallower model leaves a larger feature map before the final average pooling layer:

```text
fewer layers / fewer pools
        ↓
larger final feature map
        ↓
larger AveragePooling2D window
        ↓
more generated HLS code
        ↓
possible hls4ml / HLS frontend failure
```

Therefore, Phases 1–3 should use a **coupled resolution-depth sweep**, not independent resolution and architecture sweeps.

---

# Shared experiment metadata

Every experiment should log:

```text
experiment_name
input_resolution
num_layers
conv_filters
final_feature_map_shape
final_avg_pool
final_pool_area
weight_bits
activation_bits
pruning_target
actual_global_sparsity
actual_sparsity_per_layer
reuse_factor
software_accuracy
software_auc
precision
recall
f1
false_positive_rate
false_negative_rate
confusion_matrix
keras_hls4ml_prediction_agreement
max_output_difference
mean_output_difference
hls4ml_conversion_status
hls4ml_csim_status
synthesis_status
LUT
FF
BRAM
DSP
latency
clock_period
failure_reason
```

Most of these things should already be available from the current framework. If not, implement them.

Use a single machine-readable result table, for example:

```text
results/experiment_summary.csv
```

---

# Naming convention

Use names of the form:

```text
res{resolution}_layers{num_layers}_W{weight_bits}A{activation_bits}_P{pruning_target}_RF{reuse_factor}
```

Examples:

```text
res512_layers5_WfloatAfloat_P0_RFbase
res512_layers5_W6A6_P50_RFbase_reference
res256_layers3_W4A4_P0_RF16
res1024_layers4_WfloatAfloat_P0_RFbase_boundary
res512_layers4_W4A4_P50_RF8
```

For Phases 1–3, use:

```text
WfloatAfloat_P0
```

For Phase 4 onward, use explicit quantization labels:

```text
W8A8
W6A6
W4A4
W3A3
W2A2
```

For unpruned models, always use:

```text
P0
```

---

# Phase 1 — Baseline and shape-feasibility calibration

## Purpose

Establish the unpruned/non-QAT baseline and implement an automatic pre-check that classifies resolution-depth pairs based on final average-pooling size.

This phase should answer:

> Which resolution-depth pairs are expected to be feasible, boundary cases, or skipped before wasting time on full training/synthesis?

---

## Step 1.1 — Implement shape analysis

For every candidate model, automatically compute the spatial shape after each layer.

The agent should not rely only on the formula. It should instantiate or simulate the model shape directly from the repository config.

Still, for intuition, because the model uses:

```text
conv0 stride 2
MaxPooling2D(2, 2) after every conv layer
```

the approximate final spatial size after `L` conv/pool blocks is:

```text
final_size ≈ input_resolution / 2^(L + 1)
```

Record:

```text
final_feature_map_height
final_feature_map_width
final_channels
final_pool_area = H_final × W_final
final_pool_work = H_final × W_final × C_final
```

---

## Step 1.2 — Define feasibility tiers

Classify every candidate into one of three tiers:

| Tier       | Final average pool size | Expected behavior             | Action                                           |
| ---------- | ----------------------: | ----------------------------- | ------------------------------------------------ |
| **Green**  |               `≤ 16×16` | expected feasible             | train, convert, csim, synthesize                 |
| **Yellow** |                 `32×32` | boundary / likely problematic | attempt and document frontend/synthesis behavior |
| **Red**    |               `> 32×32` | expected infeasible           | skip by default                                  |

The `32×32` cases are intentionally included because they are useful for the paper. They help demonstrate that large final average-pooling windows create hls4ml/HLS frontend pressure.

---

## Step 1.3 — Run or consult the Phase 1 baseline

For the Phase 1 baseline:

```text
res512_layers5_WfloatAfloat_P0_RFbase
```

we want:

```text
train
software evaluation
hls4ml conversion
hls4ml C simulation
Keras-vs-hls4ml parity check
synthesis
resource/latency extraction
```

This is the reference point for the unpruned/non-QAT Phase 1–3 comparisons.

The existing completed run:

```text
artifacts/cnn_small_hls_opt_img512/notebook_pruned_qat/BASELINE_pruned_qat_w6_a6_s50_pruneend200_kfold5_db9a98479fa8
```

should be consulted as a known-working reference, but not treated as the Phase 1–3 baseline because it is already quantized and pruned.

---

# Phase 2 — Coupled resolution-depth sweep

## Purpose

Map the feasible design space over:

```text
input resolution × number of layers
```

The key question is:

> For each input resolution, how many layers are needed to reduce the final average pooling enough for synthesis?

---

## Candidate resolutions

Use:

```text
1024×1024
512×512
256×256
128×128
64×64
```

Do not include `2048×2048` in the main sweep. The current upper bound is:

```text
maximum resolution = 1024×1024
maximum depth = 5 layers
```

---

## Candidate depths

Use:

```text
5 layers
4 layers
3 layers
2 layers
```

Architecture variants should be generated as prefixes of the baseline `conv_specs`.

For example:

```text
5 layers: conv0 → conv1 → conv2 → conv3 → conv4
4 layers: conv0 → conv1 → conv2 → conv3
3 layers: conv0 → conv1 → conv2
2 layers: conv0 → conv1
```

For each variant, update `final_avg_pool` to match the final spatial shape.

---

## Expected feasibility matrix

Using the approximate shape rule, the candidate matrix is:

| Layers ↓ / Resolution → |      64 |       128 |        256 |        512 |        1024 |
| ----------------------: | ------: | --------: | ---------: | ---------: | ----------: |
|                   **5** | ✅ `1×1` |   ✅ `2×2` |    ✅ `4×4` |    ✅ `8×8` |   ✅ `16×16` |
|                   **4** | ✅ `2×2` |   ✅ `4×4` |    ✅ `8×8` |  ✅ `16×16` |  ⚠️ `32×32` |
|                   **3** | ✅ `4×4` |   ✅ `8×8` |  ✅ `16×16` | ⚠️ `32×32` |   ❌ `64×64` |
|                   **2** | ✅ `8×8` | ✅ `16×16` | ⚠️ `32×32` |  ❌ `64×64` | ❌ `128×128` |

Legend:

```text
✅ green  = expected feasible
⚠️ yellow = boundary stress-test
❌ red    = skip by default
```

---

## Phase 2 experiment list

### Green candidates

Run these normally:

```text
res1024_layers5_WfloatAfloat_P0_RFbase

res512_layers5_WfloatAfloat_P0_RFbase
res512_layers4_WfloatAfloat_P0_RFbase

res256_layers5_WfloatAfloat_P0_RFbase
res256_layers4_WfloatAfloat_P0_RFbase
res256_layers3_WfloatAfloat_P0_RFbase

res128_layers5_WfloatAfloat_P0_RFbase
res128_layers4_WfloatAfloat_P0_RFbase
res128_layers3_WfloatAfloat_P0_RFbase
res128_layers2_WfloatAfloat_P0_RFbase

res64_layers5_WfloatAfloat_P0_RFbase
res64_layers4_WfloatAfloat_P0_RFbase
res64_layers3_WfloatAfloat_P0_RFbase
res64_layers2_WfloatAfloat_P0_RFbase
```

### Yellow boundary candidates

Run these as boundary/stress-test cases:

```text
res1024_layers4_WfloatAfloat_P0_RFbase_boundary
res512_layers3_WfloatAfloat_P0_RFbase_boundary
res256_layers2_WfloatAfloat_P0_RFbase_boundary
```

For yellow candidates, the goal is not necessarily to obtain a usable final model. The goal is to record whether hls4ml conversion, C simulation, and synthesis succeed or fail, and why.

### Red candidates

Skip by default:

```text
res1024_layers3_WfloatAfloat_P0_RFbase
res1024_layers2_WfloatAfloat_P0_RFbase
res512_layers2_WfloatAfloat_P0_RFbase
```

Only run them if specifically needed as extra evidence of infeasibility.

---

## Phase 2 workflow for each candidate

For green and yellow candidates: run the pipeline from training → hls4ml conversion → C simulation → synthesis/implementation as supported by the pipeline.

Importantly, the training should not include quantization or pruning. Please check if the framework supports this.

For red candidates:

```text
1. Generate shape metadata.
2. Mark as skipped due to final_avg_pool > 32×32.
```

---

## Phase 2 outputs

Produce:

```text
feasibility_matrix.csv
resolution_depth_results.csv
```

Recommended plots:

```text
1. Feasibility heatmap
2. AUC heatmap over resolution × layers
3. Accuracy heatmap over resolution × layers
3.5. F1 heatmap over resolution × layers
4. Latency heatmap over resolution × layers
5. LUT heatmap over resolution × layers
6. BRAM heatmap over resolution × layers
7. DSP heatmap over resolution × layers
```

The most important plot is the feasibility heatmap, because it explains why resolution and architecture depth must be considered together.

---

# Phase 3 — Architecture comparison within feasible resolution bands

## Purpose

Analyze the model-depth tradeoff, but only in contexts where the candidates are meaningful.

Importantly, do not stop to write any non-reproducible report or analysis yourself: just focus on writing the code for these plots.

Do **not** ask:

```text
What happens if we vary layers at one arbitrary resolution?
```

Instead ask:

```text
At each resolution, what is the shallowest architecture that remains accurate and feasible?
```

---

## Phase 3A — Fixed-resolution architecture comparisons

Compare depth within each resolution band.

### At 512×512

Compare:

```text
res512_layers5_WfloatAfloat_P0_RFbase
res512_layers4_WfloatAfloat_P0_RFbase
res512_layers3_WfloatAfloat_P0_RFbase_boundary
```

Interpretation:

```text
5 layers: known feasible baseline-style design
4 layers: still feasible with 16×16 final pooling
3 layers: 32×32 boundary case
```

This shows what happens when reducing depth at the baseline resolution.

---

### At 256×256

Compare:

```text
res256_layers5_WfloatAfloat_P0_RFbase
res256_layers4_WfloatAfloat_P0_RFbase
res256_layers3_WfloatAfloat_P0_RFbase
res256_layers2_WfloatAfloat_P0_RFbase_boundary
```

This shows whether lower resolution allows shallower models without hitting the final-pooling wall.

---

### At 128×128

Compare:

```text
res128_layers5_WfloatAfloat_P0_RFbase
res128_layers4_WfloatAfloat_P0_RFbase
res128_layers3_WfloatAfloat_P0_RFbase
res128_layers2_WfloatAfloat_P0_RFbase
```

This shows whether deeper models still help when the input resolution is small, or whether they over-compress spatial information.

---

### At 64×64

Compare:

```text
res64_layers5_WfloatAfloat_P0_RFbase
res64_layers4_WfloatAfloat_P0_RFbase
res64_layers3_WfloatAfloat_P0_RFbase
res64_layers2_WfloatAfloat_P0_RFbase
```

This provides the low-resolution end of the design space.

---

## Phase 3B — Constant-final-pool diagonal comparisons

These are especially useful because they control the final average-pooling burden.

### Green diagonal: final pool `16×16`

Compare:

```text
res1024_layers5_WfloatAfloat_P0_RFbase
res512_layers4_WfloatAfloat_P0_RFbase
res256_layers3_WfloatAfloat_P0_RFbase
res128_layers2_WfloatAfloat_P0_RFbase
```

These all have approximately the same final spatial pooling size:

| Model                                    | Final pool |
| ---------------------------------------- | ---------: |
| `res1024_layers5_WfloatAfloat_P0_RFbase` |    `16×16` |
| `res512_layers4_WfloatAfloat_P0_RFbase`  |    `16×16` |
| `res256_layers3_WfloatAfloat_P0_RFbase`  |    `16×16` |
| `res128_layers2_WfloatAfloat_P0_RFbase`  |    `16×16` |

This answers:

> If final pooling complexity is held constant, what is the value of higher input resolution and deeper processing?

---

### Yellow diagonal: final pool `32×32`

Compare:

```text
res1024_layers4_WfloatAfloat_P0_RFbase_boundary
res512_layers3_WfloatAfloat_P0_RFbase_boundary
res256_layers2_WfloatAfloat_P0_RFbase_boundary
```

These are boundary candidates.

This answers:

> What happens when final average pooling grows to 32×32, and where does hls4ml/HLS become impractical?

For these models, report:

```text
conversion success/failure
C simulation success/failure
synthesis success/failure
generated code size or instruction count
compile time
failure reason
```

---

## Phase 3 outputs

Recommended plots:

```text
1. AUC vs layers at fixed resolution
1.5 F1 vs layers at fixed resolution
2. Latency vs layers at fixed resolution
3. LUT/BRAM/DSP vs layers at fixed resolution
4. AUC vs resolution along the 16×16 final-pool diagonal
5. Latency/resources vs resolution along the 16×16 final-pool diagonal
6. hls4ml failure/compile-cost plot for the 32×32 final-pool diagonal
```

After Phase 3, select one or more promising candidates for quantization.

Selection criteria:

```text
high AUC / accuracy
F1
low false negative rate
green-tier feasibility
successful hls4ml parity
successful synthesis
reasonable latency/resources
```

A likely output of Phase 3 is a shortlist such as:

```text
res512_layers4_WfloatAfloat_P0_RFbase
res512_layers5_WfloatAfloat_P0_RFbase
res256_layers3_WfloatAfloat_P0_RFbase
res1024_layers5_WfloatAfloat_P0_RFbase
```

The exact shortlist should be determined by results.

---

# Phase 4 — Quantization sweep

## Purpose

Find the lowest weight/activation precision that preserves accuracy while reducing FPGA cost.

This phase should use a small/medium-sized shortlist from Phase 3: we will see how many models pass and decide then.

---

## Candidate quantization settings

Run:

```text
W8A8
W6A6
W4A4
W3A3
W2A2
```

where:

```text
W = weight bit width
A = activation bit width
```

The exact QKeras quantizer strings should be generated from the repository’s quantizer utilities.

---

## Controlled variables

Keep fixed:

```text
input resolution
number of layers
architecture filters
training split
reuse factor
pruning target = P0
```

Only change:

```text
weight quantizer
activation quantizer
possibly accumulator/result precision if required by hls4ml
```

---

## Phase 4 experiment list

For each selected architecture from Phase 3, generate:

```text
resX_layersY_W8A8_P0_RFbase
resX_layersY_W6A6_P0_RFbase
resX_layersY_W4A4_P0_RFbase
resX_layersY_W3A3_P0_RFbase
resX_layersY_W2A2_P0_RFbase
```

If synthesis time is expensive, run the full quantization sweep on the single best Phase 3 candidate first, then repeat for only one backup candidate.

---

## Phase 4 workflow

For each quantization setting, using our pipeline stages:

```text
1. Generate QKeras config.
2. Train or fine-tune quantized model.
3. Evaluate software metrics.
4. Convert to hls4ml.
5. Run hls4ml C simulation.
6. Check Keras-vs-hls4ml parity.
7. Synthesize if parity is acceptable.
8. Extract resources and latency.
```

---

## Phase 4 parity requirements

Record:

```text
Keras accuracy
hls4ml C-sim accuracy
Keras-vs-hls4ml prediction agreement
maximum output difference
mean output difference
number of changed predictions
```

This phase must be strict about parity because low-bit quantization can expose fixed-point mismatch problems.

---

## Phase 4 outputs

Recommended plots:

```text
1. AUC vs bit width
2. Accuracy vs bit width
1.5 F1 vs bit width
3. FNR vs bit width
4. LUT vs bit width
5. DSP vs bit width
6. BRAM vs bit width
7. Latency vs bit width
8. Keras-hls4ml agreement vs bit width
```

After Phase 4, choose a final quantization setting based on:

```text
acceptable AUC / FNR
good F1
good hls4ml parity
successful synthesis
lower resources
acceptable latency
```

---

# Phase 4.5 — Pruning sparsity sweep

## Purpose

After selecting a promising resolution-depth candidate and quantization setting, evaluate whether pruning improves the final hardware/accuracy tradeoff.

Like the earlier phases, assume the Phase 1–4 models are **unpruned**.

The main question is:

```text
Can pruning reduce model size / hardware cost while preserving AUC and false-negative rate?
```

---

## Fixed inputs

Use the selected model from earlier phases:

```text
selected resolution
selected number of layers
selected quantization setting
baseline/default reuse factor
```

Example:

```text
res512_layers4_W4A4_P0_RFbase
```

---

## Pruning schedule

Use the known-working pruning schedule:

```text
total training epochs: 300
pruning active until epoch: 250
fine-tuning without further pruning: epochs 251–300
```

So the model is pruned during the first 250 epochs, then allowed to stabilize for the final 50 epochs.

Note: the existing known-working reference run used `pruneend200`, while this Phase 4.5 sweep uses the newer intended schedule, `pruneend250`. Do not directly compare the existing reference run to Phase 4.5 without noting this schedule difference.

---

## Sweep values

Run a small sparsity sweep, for example:

```text
P0
P25
P50
P75
```

where:

```text
P0  = 0% target sparsity / unpruned control
P25 = 25% target sparsity
P50 = 50% target sparsity
P75 = 75% target sparsity
```

If time is limited, run only:

```text
P0
P50
P75
```

For `P0`, reuse the selected Phase 4 model if it has the same training schedule and configuration. Only retrain `P0` if needed to make the training budget comparable to the pruned models.

---

## Experiment names

Use names like:

```text
resX_layersY_WZAZ_P0_RFbase
resX_layersY_WZAZ_P25_RFbase
resX_layersY_WZAZ_P50_RFbase
resX_layersY_WZAZ_P75_RFbase
```

Example:

```text
res512_layers4_W4A4_P50_RFbase
```

---

## Workflow

For each pruning setting:

```text
1. Train the selected QKeras model with the pruning schedule.
2. Stop pruning at epoch 250.
3. Continue fine-tuning until epoch 300.
4. Strip pruning wrappers / export the final pruned model.
5. Evaluate software accuracy, AUC, FNR, precision, and recall.
6. Record actual sparsity globally and per layer.
7. Convert to hls4ml.
8. Run hls4ml C simulation.
9. Check Keras-vs-hls4ml parity.
10. Synthesize if parity is acceptable.
11. Record LUT, FF, BRAM, DSP, latency, and synthesis status.
```

---

## Metrics to log

In addition to the normal metrics, log:

```text
target_sparsity
actual_global_sparsity
actual_sparsity_per_layer
nonzero_parameter_count
software_auc
software_f1
software_false_negative_rate
keras_hls4ml_prediction_agreement
LUT
FF
BRAM
DSP
latency
```

---

## Outputs

Recommended plots:

```text
AUC vs pruning sparsity
FNR vs pruning sparsity
F1 vs pruning sparsity
nonzero parameters vs pruning sparsity
LUT / DSP / BRAM vs pruning sparsity
latency vs pruning sparsity
```

Recommended table:

| Model | Target sparsity | Actual sparsity | F1 | AUC | FNR | LUT | BRAM | DSP | Latency |
| ----- | --------------: | --------------: | -: | --: | --: | --: | ---: | --: | ------: |

---

## Selection rule

Choose the pruned model only if it provides a clear benefit:

```text
similar AUC / FNR to the unpruned model
successful hls4ml parity
successful synthesis
lower resource usage and/or latency
```

If pruning preserves accuracy but does not reduce hardware cost, report that honestly and keep the unpruned model for Phase 5.

---

# Phase 5 — Reuse factor / hardware parallelism sweep

## Purpose

Explore the hardware tradeoff between latency and resource usage for the selected trained model.

Unlike Phases 2–4, this phase should **not retrain the model**. It changes only hls4ml implementation settings.

---

## Candidate reuse factors

Run:

```text
RF1
RF2
RF4
RF8
RF16
RF32
```

If some reuse factors are invalid for particular layers, the automation should skip them and record the reason.

---

## Controlled variables

Keep fixed:

```text
input resolution
number of layers
trained weights
quantization setting
pruning target / actual sparsity
dataset split
hls4ml backend
clock period
```

Only change:

```text
ReuseFactor
possibly Strategy: Latency vs Resource, if the repo supports this cleanly
```

---

## Phase 5 experiment list

For the selected model:

```text
resX_layersY_WZAZ_Pselected_RF1
resX_layersY_WZAZ_Pselected_RF2
resX_layersY_WZAZ_Pselected_RF4
resX_layersY_WZAZ_Pselected_RF8
resX_layersY_WZAZ_Pselected_RF16
resX_layersY_WZAZ_Pselected_RF32
```

Example:

```text
res512_layers4_W4A4_P0_RF1
res512_layers4_W4A4_P0_RF2
res512_layers4_W4A4_P0_RF4
res512_layers4_W4A4_P0_RF8
res512_layers4_W4A4_P0_RF16
res512_layers4_W4A4_P0_RF32
```

or, if pruning is selected:

```text
res512_layers4_W4A4_P50_RF1
res512_layers4_W4A4_P50_RF2
res512_layers4_W4A4_P50_RF4
res512_layers4_W4A4_P50_RF8
res512_layers4_W4A4_P50_RF16
res512_layers4_W4A4_P50_RF32
```

---

## Expected behavior

Usually:

```text
lower ReuseFactor
    → more parallelism
    → lower latency
    → higher resource usage

higher ReuseFactor
    → more reuse of hardware units
    → higher latency
    → lower resource usage
```

Accuracy should remain unchanged because the learned model and numerical precision are unchanged.

---

## Phase 5 workflow

Using our pipeline stages:

```text
1. Generate hls4ml config.
2. Do not retrain.
3. Run hls4ml C simulation.
4. Confirm parity. No need to block progress; just make sure the pipeline outputs that the accuracy is still what we expect. If we already have appropriate plots for this step, no need to do anything extra.
5. Synthesize.
6. Extract resources and latency.
7. Record success/failure.
```

---

## Phase 5 outputs

Recommended plots:

```text
1. Latency vs ReuseFactor
2. LUT vs ReuseFactor
3. FF vs ReuseFactor
4. BRAM vs ReuseFactor
5. DSP vs ReuseFactor
6. Accuracy/AUC vs ReuseFactor
7. Pareto plot: latency vs LUT
8. Pareto plot: latency vs DSP
```

The accuracy/AUC plot should ideally be flat. That demonstrates that `ReuseFactor` is a hardware scheduling/resource tradeoff, not a model-quality tradeoff.

---

# Final outputs after Phase 5

The agent should produce the following artifacts.

## 1. Master result table

One row per experiment:

| Experiment | Resolution | Layers | Final Pool | Tier | W bits | A bits | P target | Actual sparsity | RF | AUC | Acc | F1 | FNR | LUT | FF | BRAM | DSP | Latency | Status |
| ---------- | ---------: | -----: | ---------: | ---- | -----: | -----: | -------: | --------------: | -: | --: | --: | -: | --: | --: | -: | ---: | --: | ------: | ------ |

---

## 2. Feasibility matrix

A table/heatmap over:

```text
resolution × layers
```

with cells showing:

```text
green feasible
yellow boundary
red skipped/infeasible
actual hls4ml/synthesis status
```

---

## 3. Accuracy/resource/latency heatmaps

For Phase 2–3:

```text
AUC heatmap
F1 heatmap
FNR heatmap
latency heatmap
LUT heatmap
BRAM heatmap
DSP heatmap
```

---

## 4. Quantization plots

For Phase 4:

```text
AUC vs bit width
F1 vs bit width
FNR vs bit width
latency vs bit width
resources vs bit width
hls4ml parity vs bit width
```

---

## 5. Pruning plots

For Phase 4.5:

```text
AUC vs pruning sparsity
F1 vs pruning sparsity
FNR vs pruning sparsity
nonzero parameters vs pruning sparsity
resources vs pruning sparsity
latency vs pruning sparsity
```

---

## 6. Reuse factor plots

For Phase 5:

```text
latency vs ReuseFactor
resources vs ReuseFactor
latency-resource Pareto plot
```

---

## 7. Final selected model(s)

The final model(s) should be justified by:

```text
good AUC / accuracy / F1
low false negative rate
successful hls4ml parity
successful synthesis
fits FPGA resources
acceptable latency
reasonable integration complexity
```

The final model name should encode the chosen design point, for example:

```text
res512_layers4_W4A4_P0_RF8
```

or, if pruning is selected:

```text
res512_layers4_W4A4_P50_RF8
```

---

# One-sentence summary for the agent

Run a reproducible staged search where Phases 1–3 jointly sweep input resolution and architecture depth using final average-pooling size as a feasibility constraint, Phase 4 sweeps quantization on the best feasible candidates, Phase 4.5 sweeps pruning, and Phase 5 sweeps hls4ml reuse factor on the selected trained model to obtain the final latency-resource Pareto point.

---

# Important specific notes

* Please make sure that pruning and quantization are explicitly disabled until their relevant sweeps.
* The existing `BASELINE_pruned_qat_w6_a6_s50_pruneend200_kfold5` run is a known-working reference, not the unpruned Phase 1–3 baseline.
* Most of the things mentioned should already be available from the current framework. If not, stop, inform me, and we will implement them.
* We want this to be as automated and reproducible as possible. Ideally, we should be able to start from a directory where all model configs are already defined, and we just need to actually run the pipelines for the different variants to verify results.
* Do as little manual analysis as possible. The goal is to produce plots/tables that let a researcher inspect the results, deduce next steps, and verify conclusions themselves.
* Try to use the existing pipeline stages code as much as possible. If it is not possible, inform me and we will decide.
