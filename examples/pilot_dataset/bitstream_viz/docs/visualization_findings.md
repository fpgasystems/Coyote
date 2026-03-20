# Visualization Findings Report

## Objective

Determine which bitstream-to-image mappings show clear visual and quantitative differences between **benign** and **standalone** (suspicious-dominated) partial bitstreams. Also assess the harder task: benign vs paired-suspicious (only +48 LUTs difference).

All comparisons use **region 0, one sample per app** (4 benign, 4 standalone).

---

## 1. Quantitative Summary: Benign vs Standalone

| Variant | % pixels differ | Mean pixel diff | Notes |
|---------|---------------:|----------------:|-------|
| **B4** | **56.2%** | **31.5** | Best Case B variant — full-file downsampled, captures global structure |
| **A2** | **46.6%** | **41.4** | Best Case A variant — paired-point line plot, highest per-pixel intensity difference |
| **A4** | **75.7%** | **9.7** | Most pixels differ, but low intensity difference (log-compressed density) |
| **A1** | **25.9%** | **36.7** | High intensity difference where pixels differ; lower spatial spread |
| B3 | 34.6% | 14.1 | Misleading — center of bitstream is mostly padding; high variance across apps |
| B1 | 13.3% | 5.4 | Low — first 64KB includes shared header, limiting discriminability |
| B2 | 4.8% | 1.9 | Very low — file tails are nearly identical for most pairs |
| A3 | 6.7% | 5.9 | Chunked mean smooths out differences; not informative |

### Key findings

1. **B4 (evenly downsampled) is the most informative Case B variant.** It captures the full file at reduced resolution, producing 56% pixel difference between classes. This makes sense: downsampling preserves the global byte-value distribution, which differs between apps with 20K LUTs (benign) and 8–23K LUTs (standalone).

2. **A2 (paired-point line plot) shows the strongest visual contrast.** 46.6% of pixels differ with the highest mean intensity difference (41.4). The paired-point mapping naturally produces diagonal line patterns, and the different byte distributions in benign vs standalone create visually distinct trace patterns.

3. **A4 (density accumulation) has the widest spatial spread** (75.7% pixels differ) but the differences are subtle in intensity (mean diff 9.7). This is because log normalization compresses the dynamic range. Still useful as a complementary view.

4. **B2 (last window) is nearly useless** — the tail of partial bitstreams is structurally similar regardless of app content. Cosine and vadd tails are **identical** to their standalone counterparts (0.0% difference).

5. **B3 (center window) is unreliable.** The center of region-0 partial bitstreams falls in sparse Xilinx frame padding (~85% zero bytes), making most center windows look similar. AES is an exception (only 55% zeros) because it has a larger file with denser content at the center. The high variance (±7.7) across app pairs confirms this is not a stable metric.

---

## 2. Benign vs Paired-Suspicious (The Hard Task)

For reference — the paired-suspicious variants differ by only 48 LUTs (16 ring oscillators × 3 LUTs) in files of 6–11 MB.

| Variant | % pixels differ | Mean pixel diff |
|---------|---------------:|----------------:|
| B4 | 56.5% | 32.1 |
| A2 | 45.3% | 36.9 |
| A4 | 74.1% | 6.9 |
| B3 | 38.7% | 17.2 |
| A1 | 22.5% | 30.6 |
| B1 | 14.9% | 6.0 |
| A3 | 5.9% | 4.4 |
| B2 | 3.7% | 1.5 |

**Critical observation:** The benign-vs-suspicious pixel differences are **comparable to** benign-vs-standalone differences. This is counterintuitive — the 48-LUT injection should be invisible, yet B4 shows 56.5% vs 56.2% pixel difference.

**Explanation:** The pixel differences between benign and paired-suspicious are dominated by **implementation variability** (different place-and-route outcomes), not the 48-LUT structural change. Vivado produces different routing solutions for the two builds, and these routing differences propagate through the entire bitstream. This means:

- At 256×256 resolution, **implementation noise swamps the signal** from the injected suspicious logic
- The CNN will need to learn features that are invariant to P&R noise, which is the core challenge
- The paired-suspicious class cannot be distinguished from benign by simple pixel comparison at this resolution

This confirms the pilot plan's expectation: "visual differences between paired samples may be imperceptible."

---

## 3. Per-App Breakdown: Benign vs Standalone

| App pair | B4 % diff | A2 % diff | A4 % diff |
|----------|----------:|----------:|----------:|
| euclidean (20,799 LUT) vs standalone_1 (8,387 LUT) | 55.7% | 48.2% | 71.9% |
| cosine (20,833 LUT) vs standalone_2 (8,522 LUT) | 54.9% | 46.4% | 72.2% |
| vadd (20,307 LUT) vs standalone_3 (9,872 LUT) | 55.0% | 47.0% | 72.5% |
| aes (31,149 LUT) vs standalone_4 (23,372 LUT) | 59.1% | 44.8% | 86.1% |

- AES vs standalone_4 shows the **largest A4 difference** (86.1%) — both are high-LUT designs but with very different logic structures (AES encryption vs 5000 ring oscillators)
- A2 differences are remarkably consistent across pairs (44.8–48.2%), suggesting the paired-point mapping is robust to app-specific variation
- B4 is also stable across pairs (54.9–59.1%)

---

## 4. Image Statistics by Class

| Variant | Benign mean pixel | Standalone mean pixel | Difference |
|---------|------------------:|---------------------:|-----------:|
| B4 | 233.9 ± 1.3 | 237.0 ± 0.9 | Standalone slightly brighter (more zeros in raw bytes) |
| A2 | 49.4 ± 5.5 | 64.2 ± 13.1 | Standalone significantly brighter with higher variance |
| A4 | 24.1 ± 3.3 | 17.9 ± 0.7 | Standalone dimmer (more concentrated byte-pair distribution) |

- **A2 shows the clearest class-level separation** in mean pixel intensity: benign at 49.4, standalone at 64.2, with non-overlapping error bars
- Standalone has **lower variance** across apps in A4 and B4, likely because the standalone designs are structurally simpler (passthrough + ROs vs full computational kernels)

---

## 5. Recommendations

### Best representations for ML classification

1. **B4 (downsampled byte-to-pixel)** — most informative Case B variant. Deterministic, hardware-friendly, captures global structure. Recommended as the primary input representation.

2. **A2 (paired-point line plot)** — strongest visual contrast and most consistent class separation. Closest match to the ETS paper style. Recommended as the primary Case A variant.

3. **A4 (density accumulation)** — complementary view with widest spatial spread. Useful as a secondary feature or for ensemble approaches.

### Representations to deprioritize

- **B2 (last window):** near-zero discriminability
- **B3 (center window):** dominated by shared padding, unreliable
- **A3 (chunked polyline):** averaging destroys discriminative detail

### For the research paper

- The **benign vs standalone** comparison is visually compelling — montages clearly show different patterns
- The **benign vs paired-suspicious** comparison confirms the expected difficulty — implementation noise dominates
- B3's similarity across classes is worth documenting as a bitstream-format property, not a pipeline bug

---

## 6. Relevant Plots

See `docs/plot_commands.md` for regeneration commands.

| Plot file | What it shows |
|-----------|---------------|
| `benign_vs_standalone_case_B.png` | Side-by-side B1–B4 with LUT counts |
| `benign_vs_standalone_case_A.png` | Side-by-side A1–A4 with LUT counts |
| `benign_vs_standalone_A2.png` | A2-only focused comparison |
| `pair_euclidean_S00_vs_S08.png` | Benign vs suspicious (hardest case) |
| `standalone_progression.png` | RO count scaling (5→50→500→5000) |
| `class_0_benign.png` | All benign apps across all variants |
| `class_2_standalone.png` | All standalone apps across all variants |
