# April 15 Saved Run Summary

This summary covers only the archived selected runs preserved under `saved_runs/`:

- `cnn_medium`
- `cnn_b`
- `cnn_b_1d`

Method: ranking uses pooled **final-epoch canonical validation** metrics only. For each k-fold run, fold-level `final_canonical_val_per_sample.csv` predictions were pooled and metrics recomputed once on the combined out-of-fold set.

## Recommendations

- Best overall on pooled final metrics: **`cnn_b`** with MCC `0.9329`, ROC-AUC `0.9935`, and accuracy `0.9664`.
- Best conservative 2D alternative: **`cnn_medium`** with MCC `0.9024`, ROC-AUC `0.9915`, and accuracy `0.9496`.
- Best 1D model: **`cnn_b_1d`** with pooled final MCC `0.8418`, ROC-AUC `0.9742`, and accuracy `0.9202`.

## Key Plots

### `cnn_medium` final pooled evaluation

![cnn_medium final evaluation](./20260415_run_summary_assets/key_plots/cnn_medium_final_evaluation.png)

![cnn_medium evaluation dashboard](./20260415_run_summary_assets/key_plots/cnn_medium_evaluation_dashboard.png)

![cnn_medium kfold training curves](./20260415_run_summary_assets/key_plots/cnn_medium_kfold_training_curves.png)

### `cnn_b` final pooled evaluation

![cnn_b final evaluation](./20260415_run_summary_assets/key_plots/cnn_b_final_evaluation.png)

![cnn_b evaluation dashboard](./20260415_run_summary_assets/key_plots/cnn_b_evaluation_dashboard.png)

![cnn_b kfold training curves](./20260415_run_summary_assets/key_plots/cnn_b_kfold_training_curves.png)

### `cnn_b_1d` final pooled evaluation

![cnn_b_1d final evaluation](./20260415_run_summary_assets/key_plots/cnn_b_1d_final_evaluation.png)

![cnn_b_1d evaluation dashboard](./20260415_run_summary_assets/key_plots/cnn_b_1d_evaluation_dashboard.png)

![cnn_b_1d kfold training curves](./20260415_run_summary_assets/key_plots/cnn_b_1d_kfold_training_curves.png)

## Ranked Saved Runs

| Rank | Model | Repr | Epochs | Run | Final MCC | Final ROC-AUC | Final Acc | Final Opt Acc | Final BCE | Final FN | Final FP |
| --- | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | `cnn_b` | `2d` | 300 | [`20260415_021131_cnn_b_ro8000_ep300_kfold5_fliponly_kfold5`](./20260415_021131_cnn_b_ro8000_ep300_kfold5_fliponly_kfold5/) | 0.9329 | 0.9935 | 0.9664 | 0.9748 | 0.1054 | 3 | 5 |
| 2 | `cnn_medium` | `2d` | 500 | [`20260415_040251_cnn_medium_ro8000_ep500_kfold5_fliponly_kfold5`](./20260415_040251_cnn_medium_ro8000_ep500_kfold5_fliponly_kfold5/) | 0.9024 | 0.9915 | 0.9496 | 0.9790 | 0.1213 | 11 | 1 |
| 3 | `cnn_b_1d` | `1d` | 800 | [`20260415_045411_cnn_b_1d_ro8000_ep800_kfold5_fliponly_kfold5`](./20260415_045411_cnn_b_1d_ro8000_ep800_kfold5_fliponly_kfold5/) | 0.8418 | 0.9742 | 0.9202 | 0.9328 | 0.2481 | 13 | 6 |

## Standalone Score vs RO Count

These plots use only true standalone validation samples. The y-axis is the final predicted standalone probability, the x-axis is `ro_count`, blue points are correct standalone predictions, red `x` marks are missed standalone predictions, and the black line is a rolling mean after sorting by `ro_count`.

![saved runs standalone score vs ro count](./20260415_run_summary_assets/standalone_score_vs_ro_count_top_models.png)

## Standalone Grad-CAM Debugging

For each model below:

- `most correctly guessed` means the true standalone validation sample with the highest final standalone probability
- `least correctly guessed` means the true standalone validation sample with the lowest final standalone probability
- only the standalone-target Grad-CAM panel is shown

### `cnn_medium` (`2d`)

Most correctly guessed standalone: `it2_S058`, `p=0.999999`, `fold_3`

![cnn_medium most-correct standalone gradcam](./20260415_run_summary_assets/standalone_gradcam/cnn_medium_most_correct.png)

Least correctly guessed standalone: `it2_S030`, `p=0.010753`, `fold_0`

![cnn_medium least-correct standalone gradcam](./20260415_run_summary_assets/standalone_gradcam/cnn_medium_least_correct.png)

### `cnn_b` (`2d`)

Most correctly guessed standalone: `it1_S058`, `p=1.000000`, `fold_4`

![cnn_b most-correct standalone gradcam](./20260415_run_summary_assets/standalone_gradcam/cnn_b_most_correct.png)

Least correctly guessed standalone: `it1_S021`, `p=0.058874`, `fold_2`

![cnn_b least-correct standalone gradcam](./20260415_run_summary_assets/standalone_gradcam/cnn_b_least_correct.png)

### `cnn_b_1d` (`1d`)

Most correctly guessed standalone: `it1_S027`, `p=0.999572`, `fold_0`

![cnn_b_1d most-correct standalone gradcam](./20260415_run_summary_assets/standalone_gradcam/cnn_b_1d_most_correct.png)

Least correctly guessed standalone: `it2_S030`, `p=0.119623`, `fold_0`

![cnn_b_1d least-correct standalone gradcam](./20260415_run_summary_assets/standalone_gradcam/cnn_b_1d_least_correct.png)

## Recommendation For Model Selection

- Primary pick: **`cnn_b`**
- Secondary / more conservative 2D alternative: **`cnn_medium`**
- Best 1D baseline if you want a no-2D-mapping model: **`cnn_b_1d`**
