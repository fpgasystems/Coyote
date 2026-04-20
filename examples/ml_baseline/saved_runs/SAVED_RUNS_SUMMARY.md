# Saved Runs Summary

Generated on `2026-04-19`.

This summary ranks every run preserved under `saved_runs/`. All entries are 5-fold kfold runs on the same dataset vaults (`min_ro=8000`, flip-only augmentation, class balancing, final-epoch evaluation). The pooled validation set size is `n=238` for every run.

Method: for each run, fold-level `final_canonical_val_per_sample.csv` predictions were concatenated and metrics were recomputed once on the pooled out-of-fold set. All metrics use the default threshold `0.5` unless labeled `Opt` (threshold chosen to maximize that metric).

Per-run sources:

| Batch | Summary |
| --- | --- |
| April 15 (`img=1024` / 1D baselines) | [20260415_run_summary.md](./20260415_run_summary.md) |
| April 19 (smaller-model / smaller-input sweep) | [20260419_run_summary.md](./20260419_run_summary.md) |
| April 20 (cnn_small_hls_opt sweep) | [20260420_run_summary.md](./20260420_run_summary.md) |

## Ranked Runs (Final-Epoch Pooled Validation, n=238)

Sorted by pooled F1 at threshold `0.5`.

| Rank | Model | Run | `img_size` / `seq_len` | `epochs` | `lr` | F1 | Opt F1 | MCC | ROC-AUC | PR-AUC | Acc | Opt Acc | BCE | FN | FP |
| ---: | --- | --- | :---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | `cnn_b` (2D) | [`20260415_021131_cnn_b_...`](./20260415_021131_cnn_b_ro8000_ep300_kfold5_fliponly_kfold5/) | 1024 | 300 | 1e-4 | **0.9667** | 0.9744 | **0.9329** | **0.9935** | **0.9948** | **0.9664** | 0.9748 | **0.1054** | 3 | 5 |
| 2 | `cnn_medium` (2D) | [`20260415_040251_cnn_medium_...`](./20260415_040251_cnn_medium_ro8000_ep500_kfold5_fliponly_kfold5/) | 1024 | 500 | 1e-4 | 0.9474 | **0.9787** | 0.9024 | 0.9915 | 0.9938 | 0.9496 | **0.9790** | 0.1213 | 11 | 1 |
| 3 | `cnn_b` (2D) | [`20260419_191653_cnn_b_...`](./20260419_191653_cnn_b_ro8000_ep300_fliponly_img512_img512_kfold5/) | 512 | 300 | 1e-4 | 0.9381 | 0.9432 | 0.8869 | 0.9838 | 0.9864 | 0.9412 | 0.9454 | 0.1844 | 13 | 1 |
| 4 | `cnn_medium` (2D) | [`20260419_191657_cnn_medium_...`](./20260419_191657_cnn_medium_ro8000_ep300_fliponly_img512_lr3e4_img512_kfold5/) | 512 | 300 | **3e-4** | 0.9356 | 0.9391 | 0.8747 | 0.9775 | 0.9825 | 0.9370 | 0.9412 | 0.1765 | 10 | 5 |
| 5 | `cnn_b_1d` (1D) | [`20260415_045411_cnn_b_1d_...`](./20260415_045411_cnn_b_1d_ro8000_ep800_kfold5_fliponly_kfold5/) | 1,048,576 bytes | 800 | 1e-4 | 0.9177 | 0.9286 | 0.8418 | 0.9742 | 0.9790 | 0.9202 | 0.9328 | 0.2481 | 13 | 6 |
| 6 | `cnn_b` (2D) | [`20260419_191701_cnn_b_...`](./20260419_191701_cnn_b_ro8000_ep300_fliponly_img256_img256_kfold5/) | 256 | 300 | 1e-4 | 0.8945 | 0.8945 | 0.7899 | 0.9518 | 0.9524 | 0.8950 | 0.8950 | 0.2904 | 13 | 12 |

Bold = best value in the column.

## Per-Question Takeaways

### 1. Resolution matters (more than architecture within this pool)
The same `cnn_b` architecture evaluated at three input sizes gives the cleanest signal in the saved archive:

| `img_size` | F1 | MCC | FN | FP |
| ---: | ---: | ---: | ---: | ---: |
| 1024 | 0.9667 | 0.9329 | 3 | 5 |
| 512 | 0.9381 | 0.8869 | 13 | 1 |
| 256 | 0.8945 | 0.7899 | 13 | 12 |

Each halving of the side length costs roughly `~0.05` F1 and `~0.04–0.10` MCC. The effect is monotonic and consistent with the standalone-score-vs-RO-count plots from both summaries.

### 2. `cnn_b` is the most robust backbone in this archive
At every `img_size` tested, `cnn_b` is at least as good as `cnn_medium` on F1. `cnn_medium` needs more epochs (500 vs 300) to approach `cnn_b`, and a higher learning rate at `img=512` does not change the ranking.

### 3. The 1D representation underperforms the 2D representation
`cnn_b_1d` (800 epochs, 1,048,576-byte sequences) lands at F1 `0.9177` / MCC `0.8418`. Every 2D run at `img=1024` or `img=512` (including the `lr=3e-4` variant) beats it on both F1 and MCC. Useful for ablation, but not a replacement for the 2D pipeline.

### 4. `cnn_medium` extracts value from tuning `Opt Thr` (not default `0.5`)
`cnn_medium @ img=1024` has the best `Opt F1` (`0.9787`) and `Opt Acc` (`0.9790`) in this archive. Its default-threshold metrics are lower because its predictions are well-calibrated below `0.5` rather than far from it. If threshold tuning is part of the deployment pipeline, `cnn_medium @ img=1024` is the strongest post-calibration choice.

## Recommendation For Primary Pick

- **Primary pick: `cnn_b @ img=1024, ep=300`.** Best F1, best MCC, best ROC-AUC, best PR-AUC, best BCE at the default threshold. 3 FN / 5 FP across 238 pooled samples.
- **Secondary pick: `cnn_medium @ img=1024, ep=500`** when post-hoc threshold tuning is available — best `Opt F1` and best `Opt Acc` in the archive.
- **If inference cost at `img=1024` is prohibitive**, `cnn_b @ img=512, ep=300` is the best drop-in at half the input area (F1 loss ≈ 0.029, MCC loss ≈ 0.046).
- **Do not pick `img=256` or `cnn_b_1d`** as primary models based on these runs.

## Files In This Directory

- `20260415_run_summary.md` — details of the `img=1024` / 1D baseline runs with their own Grad-CAM and RO-count analysis.
- `20260419_run_summary.md` — details of the April 19 smaller-model / smaller-input sweep with Grad-CAM panels for the top 3 finishers.
- `20260420_run_summary.md` — details of the April 20 `cnn_small_hls_opt` sweep with RO/name diagnostics and `img=256` Grad-CAM deep dives.
- `20260415_run_summary_assets/` — auxiliary plots for the April 15 summary.
- `20260419_run_summary_assets/` — auxiliary plots for the April 19 summary.
- `20260420_run_summary_assets/` — auxiliary plots for the April 20 `cnn_small_hls_opt` summary.
- `<timestamp>_*` — individual run directories (fold-level artifacts, evaluation plots, reports). The heavy artifacts (`final_model.pt`, `augmented_val_cache.pt`) are intentionally excluded from the saved copies.
