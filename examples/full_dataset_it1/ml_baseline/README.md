# ML Baseline: Grayscale ResNet-18 (Benign vs Standalone)

Binary classifier on 1024x1024 grayscale images derived from FPGA partial bitstreams.
Uses torchvision ResNet-18 with conv1 changed to 1 input channel and fc to 1 output logit.

## Setup

```bash
bash setup_env.sh
source .venv/bin/activate
```

## Usage

### 1. Verify the model forward pass

```bash
python model.py
```

### 2. Debug visualization (optional)

Saves sample grids and individual images to `debug_viz/` so you can inspect what the model sees.

```bash
python visualize.py
```

### 3. Train

```bash
python train.py                    # default: 50 epochs, batch 8, lr 1e-4
python train.py --epochs 1         # quick smoke test
python train.py --batch-size 4     # reduce if OOM
python train.py --lr 1e-3          # override learning rate
python train.py --min-ro 4000      # RO threshold for standalone class (default 4000)
python train.py --run-name my_run  # custom run name
```

Outputs are saved to `runs/<run_name>/`:
- `best_model.pt` — best checkpoint by val ROC-AUC
- `final_model.pt` — model at last epoch
- `training_curves.png` — loss, accuracy, ROC-AUC plots
- `history.csv` — per-epoch metrics

### Notebook alternative

`resnet18_baseline.ipynb` contains the same pipeline in a single notebook with inline plots.

## File overview

| File | Purpose |
|------|---------|
| `setup_env.sh` | Create venv, install PyTorch + dependencies |
| `dataset.py` | Manifest loading, bitstream-to-image, PyTorch Dataset |
| `model.py` | Grayscale ResNet-18 factory + forward pass test |
| `train.py` | Training loop, validation, metrics, checkpointing |
| `visualize.py` | Debug visualization of training images |
| `resnet18_baseline.ipynb` | Self-contained notebook version |

## Dataset

- **Source:** `/home/sdeheredia/coyote_vault_work/full_dataset_it1_2026-04-01_production`
- **Samples:** 75 benign + 50 standalone (RO >= 4000) = 125 total
- **Split:** stratified 80/20 train/val
- **Input:** 35.9 MB raw `.bin` files downsampled to 1024x1024 via uniform subsampling
