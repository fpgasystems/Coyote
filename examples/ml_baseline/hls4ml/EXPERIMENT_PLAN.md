# Automated Experiment Plan: Phase 1–Phase 5

## Goal

Systematically evaluate CNN-based bitstream-inspection models across:

```text
input resolution
architecture depth
quantization precision
hls4ml reuse factor / hardware parallelism
```

The main outputs should be:

```text
accuracy / AUC / FNR
hls4ml parity
synthesis feasibility
FPGA resources
latency
```

The plan should be automated and reproducible. The agent should treat the repository as the source of truth for exact training, conversion, and synthesis commands.

---

# Fixed baseline

Use this model as the anchor:

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

We already have a completed (quantized) run, end-to-end (minus Coyote deployment) for it under `artifacts/cnn_small_hls_opt_img512/notebook_pruned_qat/BASELINE_pruned_qat_w6_a6_s50_pruneend200_kfold5_db9a98479fa8`. No need to re-run it.

The baseline experiment name should be:

```text
res512_layers5_WbaseAbase_RFbase
```

For this baseline, the spatial shape progression is approximately:

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

Most of these things should already be available from our current framework. If not, implement them.

Use a single machine-readable result table, for example:

```text
results/experiment_summary.csv
```

or:

```text
results/experiment_summary.jsonl
```

---

# Naming convention

Use names of the form:

```text
res{resolution}_layers{num_layers}_W{weight_bits}A{activation_bits}_RF{reuse_factor}
```

Examples:

```text
res512_layers5_W6A6_RF8
res256_layers3_W4A4_RF16
res1024_layers4_WbaseAbase_RFbase_boundary
```

For baseline/default quantization and reuse factor, use:

```text
WbaseAbase
RFbase
```

until the exact values are known.

---

# Phase 1 — Baseline and shape-feasibility calibration

## Purpose

Establish the baseline and implement an automatic pre-check that classifies resolution-depth pairs based on final average-pooling size.

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

## Step 1.3 — Consult baseline fully

For the baseline:

```text
res512_layers5_WbaseAbase_RFbase
```

we want

```text
train
software evaluation
hls4ml conversion
hls4ml C simulation
Keras-vs-hls4ml parity check
synthesis
resource/latency extraction
```

This is the reference point for all later comparisons.

We already have a completed (quantized) run, end-to-end (minus Coyote deployment) for it under `artifacts/cnn_small_hls_opt_img512/notebook_pruned_qat/BASELINE_pruned_qat_w6_a6_s50_pruneend200_kfold5_db9a98479fa8`. Do not re-run it.

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
res1024_layers5

res512_layers5
res512_layers4

res256_layers5
res256_layers4
res256_layers3

res128_layers5
res128_layers4
res128_layers3
res128_layers2

res64_layers5
res64_layers4
res64_layers3
res64_layers2
```

### Yellow boundary candidates

Run these as boundary/stress-test cases:

```text
res1024_layers4
res512_layers3
res256_layers2
```

For yellow candidates, the goal is not necessarily to obtain a usable final model. The goal is to record whether hls4ml conversion, C simulation, and synthesis succeed or fail, and why.

### Red candidates

Skip by default:

```text
res1024_layers3
res1024_layers2
res512_layers2
```

Only run them if specifically needed as extra evidence of infeasibility.

---

## Phase 2 workflow for each candidate

For green and yellow candidates: run the pipeline from training -> hls -> bitstream. Importantly, the training should not include quantization: please check if the framework supports this.

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
res512_layers5
res512_layers4
res512_layers3_boundary
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
res256_layers5
res256_layers4
res256_layers3
res256_layers2_boundary
```

This shows whether lower resolution allows shallower models without hitting the final-pooling wall.

---

### At 128×128

Compare:

```text
res128_layers5
res128_layers4
res128_layers3
res128_layers2
```

This shows whether deeper models still help when the input resolution is small, or whether they over-compress spatial information.

---

### At 64×64

Compare:

```text
res64_layers5
res64_layers4
res64_layers3
res64_layers2
```

This provides the low-resolution end of the design space.

---

## Phase 3B — Constant-final-pool diagonal comparisons

These are especially useful because they control the final average-pooling burden.

### Green diagonal: final pool `16×16`

Compare:

```text
res1024_layers5
res512_layers4
res256_layers3
res128_layers2
```

These all have approximately the same final spatial pooling size:

| Model             | Final pool |
| ----------------- | ---------: |
| `res1024_layers5` |    `16×16` |
| `res512_layers4`  |    `16×16` |
| `res256_layers3`  |    `16×16` |
| `res128_layers2`  |    `16×16` |

This answers:

> If final pooling complexity is held constant, what is the value of higher input resolution and deeper processing?

---

### Yellow diagonal: final pool `32×32`

Compare:

```text
res1024_layers4
res512_layers3
res256_layers2
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
res512_layers4
res512_layers5
res256_layers3
res1024_layers5
```

The exact shortlist should be determined by results.

---

# Phase 4 — Quantization sweep

## Purpose

Find the lowest weight/activation precision that preserves accuracy while reducing FPGA cost.

This phase should use the best candidate or small shortlist from Phase 3.

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
resX_layersY_W8A8_RFbase
resX_layersY_W6A6_RFbase
resX_layersY_W4A4_RFbase
resX_layersY_W3A3_RFbase
resX_layersY_W2A2_RFbase
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
good f1
good hls4ml parity
successful synthesis
lower resources
acceptable latency
```

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
resX_layersY_WZAZ_RF1
resX_layersY_WZAZ_RF2
resX_layersY_WZAZ_RF4
resX_layersY_WZAZ_RF8
resX_layersY_WZAZ_RF16
resX_layersY_WZAZ_RF32
```

Example:

```text
res512_layers4_W4A4_RF1
res512_layers4_W4A4_RF2
res512_layers4_W4A4_RF4
res512_layers4_W4A4_RF8
res512_layers4_W4A4_RF16
res512_layers4_W4A4_RF32
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

```text
1. Generate hls4ml config.
2. Do not retrain.
3. Run hls4ml C simulation.
4. Confirm parity (no need to block the progress, just make sure that the pipeline outputs that the accuracy is still what we expect. If we already have appropriate plots for this step, no need to do anything)
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

| Experiment | Resolution | Layers | Final Pool | Tier | W bits | A bits | RF | AUC | Acc | FNR | LUT | FF | BRAM | DSP | Latency | Status |
| ---------- | ---------: | -----: | ---------: | ---- | -----: | -----: | -: | --: | --: | --: | --: | -: | ---: | --: | ------: | ------ |

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
FNR vs bit width
latency vs bit width
resources vs bit width
hls4ml parity vs bit width
```

---

## 5. Reuse factor plots

For Phase 5:

```text
latency vs ReuseFactor
resources vs ReuseFactor
latency-resource Pareto plot
```

---

## 6. Final selected model

The final model should be justified by:

```text
good AUC / accuracy
low false negative rate
successful hls4ml parity
successful synthesis
fits FPGA resources
acceptable latency
reasonable integration complexity
```

The final model name should encode the chosen design point, for example:

```text
res512_layers4_W4A4_RF8
```

---

# One-sentence summary for the agent

Run a reproducible staged search where Phases 1–3 jointly sweep input resolution and architecture depth using final average-pooling size as a feasibility constraint, Phase 4 sweeps quantization on the best feasible candidates, and Phase 5 sweeps hls4ml reuse factor on the selected trained model to obtain the final latency-resource Pareto point.
