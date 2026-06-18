# Full Dataset Iteration 4 Big RO

Frozen standalone-only extension used to probe larger ring-oscillator resource
levels. This iteration is not class-balanced by itself; it extends the
standalone coverage used by later ML/hls4ml experiments.

## Scope

- Samples: 78 standalone-only samples.
- Floorplans: `FP06`, `FP08`, `FP09`, `FP10`, `FP04`, and `FP14`.
- Floorplan note: `FP04` salvages the original `FP11` slot because of routing
  congestion in the frozen campaign.
- Standalone RO counts:
  `26080, 32600, 39120, 45640, 52160, 58680, 65200, 71720, 78240, 84760, 91280, 97800, 108666`.
- Target range: approximately 6% to 25% modeled LUT occupancy.

## PR Surface

- `hw/`: dataset hardware source templates.
- `scripts/`: generation, build, and manifest scripts for this iteration.
- `artifacts/manifest.csv`: frozen planned manifest.
- `artifacts/manifest_available.csv`: canonical available-sample manifest.
- `artifacts/reports_raw.csv`: raw build/resource report summary.

Local build outputs, scheduler logs, and exported bitstream vault contents are
generated artifacts and are not part of the source review.

