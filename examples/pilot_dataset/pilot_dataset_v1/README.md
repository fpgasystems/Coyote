# Pilot Dataset v1 — Coyote PR Partial Bitstreams

Pilot dataset for ML-based detection of suspicious FPGA partial bitstreams.

## Overview

| Property | Value |
|----------|-------|
| Samples | 24 partial bitstream files (.bin) |
| Classes | 3 (benign, paired-suspicious, standalone-suspicious) |
| Samples per class | 8 |
| FPGA platform | Xilinx Alveo U55C (xcu55c-fsvh2892-2L-e) |
| Framework | Coyote (partial reconfiguration flow, Example 10) |
| Build tool | Vivado v2024.2 |
| Build date | 2026-03-19 |
| Validation | GO (all gates passed) |

## Dataset Schema

Each sample is one partial bitstream (.bin) produced by Vivado `write_bitstream` for a specific PR pblock (wrapper) in a specific configuration.

### Classes

| Label | Name | Description | Samples |
|-------|------|-------------|---------|
| 0 | Benign | Unmodified Coyote applications | 8 |
| 1 | Paired-suspicious | Same base app + 16 ring oscillators injected (+48 LUTs) | 8 |
| 2 | Standalone-suspicious | Minimal passthrough + N ring oscillators (5/50/500/5000) | 8 |

### Base Applications (Classes 0 and 1)

| App ID | Source | Description |
|--------|--------|-------------|
| app1_euclidean | Example 10 | HLS streaming: sum of squared differences |
| app2_cosine | Example 10 | HLS streaming: cosine similarity |
| app3_vadd | Example 02 | HLS streaming: vector add |
| app4_aes | Example 03 | RTL: AES-256 encryption (NPAR=2) |

### Standalone Families (Class 2)

| Family ID | Attack class | RO count | LUTs from ROs |
|-----------|-------------|----------|----------------|
| standalone_1 | Stealth leakage Trojan | 5 | 15 |
| standalone_2 | RO sensor / probe | 50 | 150 |
| standalone_3 | Covert-channel transmitter | 500 | 1,500 |
| standalone_4 | DoS aggressor | 5,000 | 15,000 |

## Manifest CSV

`pilot_manifest.csv` contains one row per sample with these columns:

| Column | Description |
|--------|-------------|
| sample_id | S00-S23 |
| class_label | 0, 1, or 2 |
| base_app_id | Application identifier |
| variant_id | benign / suspicious / standalone |
| region_id | 0 or 1 (physical PR pblock index) |
| config_id | 0-11 (Vivado configuration index) |
| shell_id | First 8 chars of shell_routed.dcp SHA-256 |
| build_seed | Vivado implementation strategy |
| tool_version | Vivado version |
| bitstream_path | Relative path to .bin file |
| timing_status | PASS / MARGINAL / FAIL |
| lut_count | Post-synthesis LUT count for this wrapper |
| ff_count | Post-synthesis flip-flop count |
| bram_count | Block RAM tile count |
| dsp_count | DSP48E2 count |
| utilization_pct | LUT utilization vs full device (%) |
| validation_status | VALID / INVALID / PENDING |
| file_hash | SHA-256 of the .bin file |
| notes | Additional context |

## Shell Parameters (frozen)

| Parameter | Value |
|-----------|-------|
| FDEV_NAME | u55c |
| N_REGIONS | 2 |
| EN_PR | 1 |
| N_CONFIG | 12 |
| EN_STRM | 1 |
| EN_MEM | 0 |
| Shell DCP hash | 5d1d615f... |

## Structural Validation Summary

### Paired-suspicious delta (Class 1 vs Class 0)

Every paired-suspicious variant shows exactly **+48 LUTs** (16 ROs x 3 LUTs) compared to its benign counterpart. FF, BRAM, and DSP counts are identical between pairs.

| App | Benign LUTs | Suspicious LUTs | Delta |
|-----|-------------|-----------------|-------|
| euclidean | 20,799 | 20,847 | +48 |
| cosine | 20,833 | 20,881 | +48 |
| vadd | 20,307 | 20,355 | +48 |
| aes | 31,149 | 31,197 | +48 |

### Standalone RO scaling (Class 2)

RO LUT counts scale exactly as expected relative to standalone_1 baseline (8,387 LUTs).

### Timing

All 24 samples pass timing (WNS > 0). Tightest: config 7 (AES suspicious) at WNS = 0.002 ns.

## Directory Structure

```
pilot_dataset_v1/
├── README.md              ← this file
├── pilot_manifest.csv     ← labels + metadata for all 24 samples
├── bitstreams/            ← 24 partial bitstream .bin files (~200 MB)
│   └── config_{0..11}/
├── reports/               ← Vivado timing, utilization, DRC, route reports
│   └── config_{0..11}/
├── sources/               ← app sources, CMakeLists.txt, floorplan (reproducibility)
│   ├── CMakeLists.txt
│   ├── floorplans/
│   └── apps/
└── logs/                  ← build logs (app.log, synth.log, bitgen.log)
```

## How to Reproduce

1. Clone Coyote and copy `sources/` contents into a new example directory
2. Set up the Vivado 2024.2 environment
3. Build:
   ```bash
   mkdir build_hw && cd build_hw
   cmake ../hw -DFPLAN_PATH=../hw/floorplans/pilot_fplan_u55c.xdc
   make project && make synth && make link && make shell && make app && make bitgen
   ```
4. Note: `make shell` exits with Error 1 when EN_PR=1 — this is expected
5. Ring oscillator designs require `ALLOW_COMBINATORIAL_LOOPS TRUE` on `*inst_ro/w*` nets (see build logs for details)

## Build Timing (observed, sequential, 8 CPUs)

| Step | Duration |
|------|----------|
| make project | ~1.5h |
| make synth | ~3-4h |
| make app | ~15-18h |
| make bitgen | ~2.5h |
| **Total** | **~22-27h** |
