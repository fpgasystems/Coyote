# prod_res256_coyote_accel_downsampler_hls4ml_e2e_20260524

Production CoyoteAccelerator deployment package for raw-bitstream input, FPGA downsampling, and hls4ml CNN inference.

## Outcome

- Samples: `146`
- Batch size: `16`
- Timing status: `met`, WNS `0.0` ns, TNS `0.0` ns
- Raw downsampling parity max abs: `0.0`

## Final Classification Metrics

| Stage | Acc | Bal acc | F1 | Precision | TPR/Recall | FPR | FNR | TNR | ROC AUC | PR AUC | BCE loss | TN | FP | FN | TP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| U55C hardware | 0.876712 | 0.875493 | 0.884615 | 0.851852 | 0.92 | 0.169014 | 0.08 | 0.830986 | 0.950986 | 0.961408 | 0.393963 | 59 | 12 | 6 | 69 |
| hls4ml CPU | 0.876712 | 0.875493 | 0.884615 | 0.851852 | 0.92 | 0.169014 | 0.08 | 0.830986 | 0.950986 | 0.961408 | 0.393143 | 59 | 12 | 6 | 69 |
| pruned_qat Keras CPU | 0.883562 | 0.882535 | 0.890323 | 0.8625 | 0.92 | 0.15493 | 0.08 | 0.84507 | 0.950423 | 0.960716 | 0.393773 | 60 | 11 | 6 | 69 |

Parity against U55C hardware:

| Comparison | Agreement | Logit MAE | Max abs logit diff | Sign mismatches |
| --- | ---: | ---: | ---: | ---: |
| U55C vs Keras CPU | 0.993151 | 0.117622 | 0.509766 | 1 |
| U55C vs hls4ml CPU | 1 | 0.00365208 | 0.111328 | 0 |

## Latency

These are separate latency scopes. For "how much latency would this add to an FPGA critical path?", use the FPGA critical-path estimate.

### FPGA Critical-Path Estimate

| Metric | Value |
| --- | ---: |
| Estimated raw downsampler scan, mean | 2.26462 ms/sample |
| Estimated raw downsampler scan, min | 1.91652 ms/sample |
| Estimated raw downsampler scan, max | 2.51717 ms/sample |
| Estimated hls4ml CNN | 1.08166 ms/sample |
| Estimated FPGA critical-path total, mean | 3.34629 ms/sample |
| Estimated FPGA critical-path total, min | 2.99818 ms/sample |
| Estimated FPGA critical-path total, max | 3.59884 ms/sample |

This estimate covers raw bytes entering the HLS wrapper, FPGA downsampling, hls4ml CNN execution, and logit production. It excludes Python, host memory copies, Coyote driver setup, and output pointer conversion.

### Observed Coyote Inference-Only

| Metric | Value |
| --- | ---: |
| Observed inference-only mean | 63.2977 ms/batch |
| Observed inference-only min | 57.5422 ms/batch |
| Observed inference-only max | 66.4239 ms/batch |
| Inference-only full-batch share | 3.9561 ms/sample |
| Inference-only real-sample share | 4.33546 ms/sample |
| Inference-only throughput | 253.25 samples/s |

This is the timing printed by `RawCoyoteOverlay` around `CoyoteInference::predict()`. It includes Coyote `LOCAL_TRANSFER` behavior and waits until the output transfer completes.

### Observed Python Outer Wall

| Metric | Value |
| --- | ---: |
| Observed outer wall latency | 160.849 ms/batch |
| Observed outer wall sample-share latency | 11.0171 ms/sample |
| Observed outer wall throughput | 90.7683 samples/s |
| Host setup/copy/readback overhead | 97.5514 ms/batch |
| Estimated downsampler per batch | 33.0635 ms |
| Estimated model per batch | 15.7923 ms |
| HLS estimated downsampler + model per batch | 48.8558 ms |

Machine-readable latency scopes and per-batch values are in `results/performance_summary.json`.

## HLS Component Estimates

| Component | HLS module | Latency | BRAM_18K | DSP | FF | LUT | URAM |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Wrapper | `model_wrapper` | - | 234 | 668 | 132868 | 194042 | 0 |
| Downsampler | `raw_bitstream_downsample_to_input_stream` | - | 0 | 16 | 4043 | 5778 | 0 |
| hls4ml CNN | `prod_res256_manualA_coyote_accel` | 1.08166 ms | 233 | 652 | 127977 | 187655 | 0 |

## Resources

| Scope | LUT | Registers | BRAM tile | URAM | DSP |
| --- | ---: | ---: | ---: | ---: | ---: |
| Shell-only synth | 5649 / 0.43% | 10552 / 0.4% | 26 / 1.29% | 0 / 0% | 0 / 0% |
| Model wrapper IP synth | 59559 / 4.57% | 72044 / 2.76% | 360 / 17.86% | 11 / 1.15% | 1328 / 14.72% |
| Full routed cyt_top | 183239 / 14.06% | 251264 / 9.64% | 518.5 / 25.72% | 11 / 1.15% | 1328 / 14.72% |

Machine-readable resource and latency details are in `results/performance_summary.json`.

## Important Files

| Artifact | Path |
| --- | --- |
| Bitstream manifest | `results/build_manifest.json` |
| Deployment manifest | `results/fpga_validation/deployment_manifest.json` |
| Validation manifest | `results/fpga_validation/validation_manifest.json` |
| Comparison summary | `results/fpga_validation/comparison_summary.json` |
| Performance summary | `results/performance_summary.json` |
| HLS synthesis report | `results/reports/model_wrapper_csynth.rpt` |
| Full routed utilization | `results/reports/shell_utilization.rpt` |
| Full routed timing | `results/reports/shell_timing_summary.rpt` |

## Replay

From the FPGA host:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/reproducibility/prod_res256_coyote_accel_downsampler_hls4ml_e2e_20260524
./run_replay_raw_validation.sh
```

If the bitstream is already programmed:

```bash
PROGRAM=0 ./run_replay_raw_validation.sh
```

## Notes

- Heavy runtime artifacts and copied raw bitstreams live under `non_vcs_artifacts/`.
- `manifest.json` records SHA-256 and size for packaged files.
- Use the FPGA critical-path estimate for device-path impact, the inference-only timing for Coyote predict-call behavior, and the outer wall timing for application-level host runtime.
