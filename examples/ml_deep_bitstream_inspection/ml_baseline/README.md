# ML Baseline

Frozen PyTorch baseline for benign-vs-standalone FPGA partial-bitstream
classification. The baseline trains grayscale models over raw `.bin`
bitstreams and feeds the sibling hls4ml production flow in `../hls4ml/`.

Generated training runs, Vitis logs, local virtualenvs, and agent notes are
excluded from the PR surface.

## Layout

| Path | Purpose |
| --- | --- |
| `dataset.py` | Manifest discovery, bitstream loading, 1D/2D dataset views |
| `model.py` | Grayscale ResNet-18 and hls4ml-friendly CNN factories |
| `train.py` | Training loop, validation, plots, and checkpoints |
| `visualize.py` | Optional debug image generation |
| `resnet18_baseline.ipynb` | Notebook version of the baseline flow |
| `../hls4ml/` | Production hls4ml pipeline and reproducibility packages |

## Dataset

By default, the loader searches:

```bash
/mnt/scratch/sdeheredia/coyote_vault_work
```

Override this path when reproducing elsewhere:

```bash
export COYOTE_DATASET_VAULT=/path/to/coyote_vault_work
```

The expected vault layout is one or more `full_dataset_it*` directories, each
with `manifest.csv` and `bitstreams/`. In-repository dataset generation sources
are documented under `../datasets/`.

## Setup and Checks

```bash
set -euo pipefail
cd /pub/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/ml_baseline
bash setup_env.sh
source .venv/bin/activate
python model.py
python -m py_compile dataset.py model.py train.py visualize.py
```

## Training

```bash
set -euo pipefail
cd /pub/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/ml_baseline
source .venv/bin/activate

python train.py --epochs 1 --run-name smoke
python train.py --epochs 50 --batch-size 8 --lr 1e-4 --min-ro 4000 --img-size 512 --run-name resnet18_baseline
```

Training outputs are written to `runs/<run_name>/` and ignored by Git.

## hls4ml / Vitis

The production hls4ml flow is documented in `../hls4ml/README.md`. Vitis tools
must be available in the shell before notebooks or synthesis jobs are started.

```bash
set -euo pipefail
source /tools/Xilinx/Vitis/2024.2/.settings64-Vitis.sh
source /tools/Xilinx/Vitis_HLS/2024.2/.settings64-Vitis_HLS.sh
cd /pub/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/hls4ml
../ml_baseline/.venv/bin/python scripts/hls4ml_run.py --config configs/hls4ml_production/res256_layers7_W8A8_P50_manualA_production.yaml --stages ''
../ml_baseline/.venv/bin/python scripts/hls4ml_run.py --config configs/hls4ml_production/res512_layers7_W8A8_P50_manualA_production.yaml --stages ''
```
