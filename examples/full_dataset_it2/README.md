# Full Dataset Iteration 2

Frozen dataset-generation source for the second production corpus. This
iteration extends the floorplan coverage while keeping the same benign versus
standalone classification target.

## Scope

- Samples: 150 samples in the frozen manifest.
- Floorplans: `FP05` through `FP09`.
- Standalone RO counts:
  `8000, 9000, 10000, 11000, 12000, 13000, 14000, 15000, 16000, 17000, 18000, 19000, 20000, 21000, 22000`.
- Dataset config: `scripts/dataset_config.py`.
- Benign catalog: same benign class design as iteration 1, extended across the
  iteration 2 floorplans.

## PR Surface

- `hw/`: dataset hardware source templates.
- `scripts/`: generation, build, and manifest scripts for this iteration.
- `artifacts/manifest.csv`: frozen manifest record.
- `artifacts/manifest_available.csv`: samples available after build/export.
- `artifacts/reports_raw.csv`: raw build/resource report summary.

`AGENT_HANDOFF.md` is a historical development note, not part of the polished
research artifact. Local build outputs, scheduler logs, and exported bitstream
vault contents are generated artifacts and are not part of the source review.

