# PR-Ready Plan

This plan turns the frozen Coyote ML/hls4ml work into a polished research
artifact inside this fork. The goal is PR hygiene and reproducibility, not
continued development. Cleanup must be recoverable: generated files can be
removed from the Git index, archived, or documented as local-only, but they
must not be destructively deleted.

## Canonical Scope

- Project directories:
  - `examples/ml_deep_bitstream_inspection/datasets/full_dataset_it*`
  - `examples/ml_deep_bitstream_inspection/ml_baseline`
  - `examples/ml_deep_bitstream_inspection/hls4ml`
- Canonical final hls4ml runs:
  - `examples/ml_deep_bitstream_inspection/hls4ml/artifacts_production`
  - `examples/ml_deep_bitstream_inspection/hls4ml/reproducibility`
- PR surface:
  - source code needed to load data, train, run hls4ml, package
    reproducibility, and inspect final results
  - dataset iteration READMEs and central baseline/hls4ml documentation
  - final production summaries and reproducibility packages

## Milestone 1: Documentation Spine

Status: completed

- Add this central PR plan at repository root.
- Rewrite `examples/ml_deep_bitstream_inspection/ml_baseline/README.md` as the top-level research artifact
  entrypoint for the ML baseline.
- Update `examples/ml_deep_bitstream_inspection/hls4ml/README.md` with the PR artifact boundary,
  canonical production configs, and reproducibility instructions.
- Add short README files for each dataset iteration directory describing
  intent, sample counts, floorplans, RO ranges, and generated/local-only files.

## Milestone 2: Portable Reproducibility

Status: completed

- Make dataset discovery configurable through `COYOTE_DATASET_VAULT` while
  preserving the current scratch path as the local default.
- Document exact smoke checks that avoid expensive training/builds.
- Keep Vitis and U55C commands explicit, with `set -euo pipefail` examples and
  log files for long-running runs.

## Milestone 3: Artifact Curation

Status: completed

- Keep the production configs and reproducibility packages tracked.
- Keep selected final production summaries/plots from `artifacts_production`
  only when they are part of the paper/result record.
- Remove generated exploratory artifact directories, auxiliary `results_*`
  directories, and old baseline `saved_runs` from the Git index only. Keep the
  original hls4ml `results/` directory tracked. Do not delete local files.
- Update ignore rules so future generated outputs do not re-enter the PR by
  accident.

## Milestone 4: Script Surface Cleanup

Status: completed

- Keep reusable source scripts tracked:
  - the YAML runner
  - experiment config generation and collection helpers
  - production reproducibility packaging
  - focused smoke tests and validators
- Remove one-off tmux launchers, recovery scripts, top-up scripts, and
  campaign-specific monitors from the Git index only.
- Document that historical agent handoff files are local development notes and
  not part of the polished artifact.

## Milestone 5: Verification

Status: completed

- Run a cheap Python syntax/import check over the edited Python modules.
- Run hls4ml config-load smoke checks with empty stages for the production
  configs.
- Run the manifest verification scripts in the production reproducibility
  packages.
- Review `git status --short` to confirm the PR surface contains only intended
  documentation, source, selected production artifacts, and index removals.
