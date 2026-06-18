# Full Dataset Iteration 1

Frozen dataset-generation source for the first production corpus used by the
ML baseline. This iteration covers the initial benign and standalone samples
for five floorplans.

## Scope

- Samples: 150 planned samples, 75 benign and 75 standalone.
- Floorplans: `FP00` through `FP04`.
- Standalone RO counts:
  `4, 16, 64, 256, 1024, 4096, 8192, 10000, 12000, 14000, 16000, 18000, 19000, 20000, 22000`.
- Shell target: frozen U55C partial-reconfiguration setup.
- Dataset shape: one region, `N_CONFIG=15`, `EN_STRM=1`, `N_STRM_AXI=2`,
  `EN_MEM=0`.

## PR Surface

- `hw/`: dataset hardware source templates.
- `scripts/`: generation, build, and manifest scripts for this iteration.
- `artifacts/manifest.csv`: frozen manifest record.
- `artifacts/manifest_available.csv`: samples available after build/export.
- `artifacts/reports_raw.csv`: raw build/resource report summary.

Local build outputs, scheduler logs, and exported bitstream vault contents are
generated artifacts and are not part of the source review.
