# ML Deep Bitstream Inspection

This directory is the frozen research artifact for deep-learning inspection of
Coyote FPGA partial bitstreams. It groups dataset-generation sources, the
PyTorch ML baseline, and the hls4ml/U55C production flow under one PR surface.

## Layout

| Path | Purpose |
| --- | --- |
| `datasets/` | Frozen dataset-generation iterations and manifests |
| `ml_baseline/` | PyTorch bitstream classifiers, dataset loader, notebooks, and training scripts |
| `hls4ml/` | YAML-driven hls4ml production pipeline, final results, and reproducibility packages |

The external bitstream vault is not stored here. By default the loader searches
`/mnt/scratch/sdeheredia/coyote_vault_work`; set `COYOTE_DATASET_VAULT` to
reproduce from another vault location.

## Reproducibility

```bash
set -euo pipefail
cd /pub/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/ml_baseline
source .venv/bin/activate

cd /pub/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/hls4ml
../ml_baseline/.venv/bin/python scripts/hls4ml_run.py --config configs/hls4ml_production/res256_layers7_W8A8_P50_manualA_production.yaml --stages ''
../ml_baseline/.venv/bin/python scripts/hls4ml_run.py --config configs/hls4ml_production/res512_layers7_W8A8_P50_manualA_production.yaml --stages ''
```

Final production summaries live under `hls4ml/artifacts_production/`; packaged
replay manifests live under `hls4ml/reproducibility/`.
