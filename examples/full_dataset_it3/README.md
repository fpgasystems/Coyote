# Full Dataset Iteration 3

Frozen dataset-generation source for the third production corpus. This
iteration targets another floorplan band and records the available subset after
build/export.

## Scope

- Samples: 150 planned samples in the manifest; 146 available samples recorded
  in `artifacts/manifest_available.csv`.
- Floorplans: `FP10` through `FP14`.
- Standalone RO counts:
  `8000, 8750, 9500, 10250, 11000, 11750, 12500, 13250, 14000, 14750, 15500, 16250, 17000, 17500, 18000`.
- Availability note: the available manifest is the canonical record for this
  iteration because four samples did not complete/export in the frozen run.

## PR Surface

- `hw/`: dataset hardware source templates.
- `scripts/`: generation, build, and manifest scripts for this iteration.
- `artifacts/manifest.csv`: frozen planned manifest.
- `artifacts/manifest_available.csv`: canonical available-sample manifest.
- `artifacts/reports_raw.csv`: raw build/resource report summary.

Local build outputs, scheduler logs, and exported bitstream vault contents are
generated artifacts and are not part of the source review.

