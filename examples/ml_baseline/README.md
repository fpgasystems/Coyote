# ML Baseline Research Artifact

This directory contains the frozen ML baseline used for benign-vs-standalone
FPGA partial-bitstream classification. The baseline trains grayscale PyTorch
models over raw `.bin` bitstreams and feeds the selected hls4ml production
pipeline in `hls4ml/`.

For PR review, treat this directory as the source and documentation entrypoint.
Generated training runs, exploratory result directories, Vitis logs, and local
agent notes are intentionally excluded from the PR surface.

## Layout

| Path | Purpose |
| --- | --- |
| `dataset.py` | Manifest discovery, bitstream loading, 1D/2D dataset views |
| `model.py` | Grayscale ResNet-18 factory and forward-pass check |
| `train.py` | Baseline PyTorch training, validation, plots, checkpoints |
| `visualize.py` | Optional debug image generation |
| `resnet18_baseline.ipynb` | Notebook version of the baseline flow |
| `hls4ml/` | YAML-driven hls4ml production pipeline and reproducibility packages |

## Dataset

By default, the loader searches the local scratch vault:

```bash
/mnt/scratch/sdeheredia/coyote_vault_work
```

Override this path when reproducing elsewhere:

```bash
export COYOTE_DATASET_VAULT=/path/to/coyote_vault_work
```

The expected vault layout is one or more directories named
`full_dataset_it*`, each containing a `manifest.csv` and a `bitstreams/`
directory. Standalone samples are filtered with `--min-ro`, defaulting to
`4000`; all benign samples are retained.

The in-repository dataset iteration directories under `../full_dataset_it*`
document how the frozen datasets were generated. They are source manifests and
build recipes, not a replacement for the external bitstream vault.

## Setup

```bash
set -euo pipefail
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline
bash setup_env.sh
source .venv/bin/activate
```

## Smoke Checks

Run cheap checks before launching expensive training or synthesis:

```bash
set -euo pipefail
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline
source .venv/bin/activate
python model.py
python -m py_compile dataset.py model.py train.py visualize.py
```

## Training

```bash
set -euo pipefail
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline
source .venv/bin/activate

python train.py --epochs 1 --run-name smoke
python train.py --epochs 50 --batch-size 8 --lr 1e-4 --min-ro 4000 --img-size 512 --run-name resnet18_baseline
```

Training outputs are written to `runs/<run_name>/` and ignored by Git:

- `final_model.pt`
- `training_curves.png`
- `final_evaluation_plots.png`
- `history.csv`

## hls4ml / Vitis

The hls4ml production flow is documented in `hls4ml/README.md`. Vitis tools
must be available in the shell before starting notebooks or synthesis jobs:

```bash
set -euo pipefail
source /tools/Xilinx/Vitis/2024.2/.settings64-Vitis.sh
source /tools/Xilinx/Vitis_HLS/2024.2/.settings64-Vitis_HLS.sh
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml
./scripts/hls4ml_run.py --config configs/hls4ml_production/res256_layers7_W8A8_P50_manualA_production.yaml --stages ''
./scripts/hls4ml_run.py --config configs/hls4ml_production/res512_layers7_W8A8_P50_manualA_production.yaml --stages ''
```

For notebook inspection, start Jupyter from the Vitis-enabled shell:

```bash
tmux new-session -d -s jupyter_ml_baseline_8890 \
  "bash -lc 'source /tools/Xilinx/Vitis/2024.2/.settings64-Vitis.sh && source /tools/Xilinx/Vitis_HLS/2024.2/.settings64-Vitis_HLS.sh && cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml && exec /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/.venv/bin/jupyter notebook --no-browser --ip=127.0.0.1 --port=8890 --port-retries=0'"
```

Then tunnel from your laptop:

```bash
ssh -N -L 8890:127.0.0.1:8890 <user>@<host>
```
