# prod_res512_coyote_accel_downsampler_hls4ml_e2e_20260524

Production CoyoteAccelerator deployment package for raw-bitstream input, FPGA downsampling, and hls4ml CNN inference.

## Outcome

- Samples: `146`
- Batch size: `16`
- Timing status: `not_met`, WNS `-1.279` ns, TNS `-3237.176` ns
- Raw downsampling parity max abs: `0.0`

## Final Classification Metrics

| Stage | Acc | Bal acc | F1 | Precision | TPR/Recall | FPR | FNR | TNR | ROC AUC | PR AUC | BCE loss | TN | FP | FN | TP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| U55C hardware | 0.90411 | 0.904413 | 0.905405 | 0.917808 | 0.893333 | 0.084507 | 0.106667 | 0.915493 | 0.969202 | 0.97568 | 0.294045 | 65 | 6 | 8 | 67 |
| hls4ml CPU | 0.90411 | 0.904413 | 0.905405 | 0.917808 | 0.893333 | 0.084507 | 0.106667 | 0.915493 | 0.969202 | 0.97568 | 0.29406 | 65 | 6 | 8 | 67 |
| pruned_qat Keras CPU | 0.90411 | 0.904413 | 0.905405 | 0.917808 | 0.893333 | 0.084507 | 0.106667 | 0.915493 | 0.969014 | 0.975453 | 0.294489 | 65 | 6 | 8 | 67 |

Parity against U55C hardware:

| Comparison | Agreement | Logit MAE | Max abs logit diff | Sign mismatches |
| --- | ---: | ---: | ---: | ---: |
| U55C vs Keras CPU | 1 | 0.100146 | 0.333252 | 0 |
| U55C vs hls4ml CPU | 1 | 0.00240127 | 0.150391 | 0 |

## Latency

These are separate latency scopes. For "how much latency would this add to an FPGA critical path?", use the FPGA critical-path estimate.

### FPGA Critical-Path Estimate

| Metric | Value |
| --- | ---: |
| Estimated raw downsampler scan, mean | 2.26462 ms/sample |
| Estimated raw downsampler scan, min | 1.91652 ms/sample |
| Estimated raw downsampler scan, max | 2.51717 ms/sample |
| Estimated hls4ml CNN | 4.26174 ms/sample |
| Estimated FPGA critical-path total, mean | 6.52637 ms/sample |
| Estimated FPGA critical-path total, min | 6.17826 ms/sample |
| Estimated FPGA critical-path total, max | 6.77892 ms/sample |

This estimate covers raw bytes entering the HLS wrapper, FPGA downsampling, hls4ml CNN execution, and logit production. It excludes Python, host memory copies, Coyote driver setup, and output pointer conversion.

### Observed Coyote Inference-Only

| Metric | Value |
| --- | ---: |
| Observed inference-only mean | 114.399 ms/batch |
| Observed inference-only min | 108.589 ms/batch |
| Observed inference-only max | 117.604 ms/batch |
| Inference-only full-batch share | 7.14992 ms/sample |
| Inference-only real-sample share | 7.83553 ms/sample |
| Inference-only throughput | 139.95 samples/s |

This is the timing printed by `RawCoyoteOverlay` around `CoyoteInference::predict()`. It includes Coyote `LOCAL_TRANSFER` behavior and waits until the output transfer completes.

### Observed Python Outer Wall

| Metric | Value |
| --- | ---: |
| Observed outer wall latency | 213.593 ms/batch |
| Observed outer wall sample-share latency | 14.6297 ms/sample |
| Observed outer wall throughput | 68.3543 samples/s |
| Host setup/copy/readback overhead | 99.1942 ms/batch |
| Estimated downsampler per batch | 33.0635 ms |
| Estimated model per batch | 62.2215 ms |
| HLS estimated downsampler + model per batch | 95.2849 ms |

Machine-readable latency scopes and per-batch values are in `results/performance_summary.json`.

## HLS Component Estimates

| Component | HLS module | Latency | BRAM_18K | DSP | FF | LUT | URAM |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Wrapper | `model_wrapper` | - | 287 | 658 | 135299 | 199226 | 0 |
| Downsampler | `raw_bitstream_downsample_to_input_stream` | - | 0 | 16 | 4055 | 5782 | 0 |
| hls4ml CNN | `prod_res512_manualA_coyote_accel` | 4.26174 ms | 286 | 642 | 130396 | 192835 | 0 |

## Resources

| Scope | LUT | Registers | BRAM tile | URAM | DSP |
| --- | ---: | ---: | ---: | ---: | ---: |
| Shell-only synth | 5649 / 0.43% | 10552 / 0.4% | 26 / 1.29% | 0 / 0% | 0 / 0% |
| Model wrapper IP synth | 65053 / 4.99% | 72873 / 2.79% | 1245.5 / 61.78% | 17 / 1.77% | 1304 / 14.45% |
| Full routed cyt_top | 188897 / 14.49% | 252166 / 9.67% | 1404 / 69.64% | 17 / 1.77% | 1304 / 14.45% |

### Routed Hierarchy Resource Breakdown

This uses the routed `cyt_top` hierarchy report. It is the clearest attribution for the apparent BRAM overhead: the non-model BRAM comes from Coyote/XDMA static resources, Coyote control/MMU logic, and local credit FIFOs around the user wrapper.

| Category | Instance(s) | LUT | Registers | BRAM tile | URAM | DSP |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Static Coyote/XDMA platform | `inst_static` | 80372 / 6.165% | 87171 / 3.343% | 96 / 4.762% | 0 / 0% | 0 / 0% |
| Dynamic Coyote control/interconnect | `inst_shell_ctrl_cc` | 10044 / 0.7704% | 22073 / 0.8466% | 16 / 0.7937% | 0 / 0% | 0 / 0% |
| Dynamic Coyote MMU | `inst_mmu_top` | 5545 / 0.4253% | 11146 / 0.4275% | 30 / 1.488% | 0 / 0% | 0 / 0% |
| Coyote local credit FIFOs around user wrapper | `inst_local_credits_host_rd + inst_local_credits_host_wr` | 3455 / 0.265% | 6490 / 0.2489% | 16.5 / 0.8185% | 0 / 0% | 0 / 0% |
| HLS model wrapper/user logic | `inst_user_c0_0` | 63903 / 4.902% | 73566 / 2.821% | 1245.5 / 61.78% | 17 / 1.771% | 1304 / 14.45% |
| Other routed glue/debug/no-BRAM residual | `full - listed categories` | 25578 / 1.962% | 51720 / 1.984% | 0 / 0% | 0 / 0% | 0 / 0% |
| Full routed cyt_top | `cyt_top` | 188897 / 14.49% | 252166 / 9.671% | 1404 / 69.64% | 17 / 1.771% | 1304 / 14.45% |

Important: this is not a true incremental-over-Coyote-shell baseline. A true paper-grade "added over Coyote" number needs a matched routed no-op Coyote build and should subtract that full routed baseline from this full routed design.

### Added Resource Attribution Comparison

This table keeps the two useful attribution views side-by-side. The hierarchy column is the routed HLS user-wrapper instance itself. The no-op column is the full routed production design minus the routed no-op/hello-world Coyote design.

| Resource | Analytical hierarchy: `inst_user_c0_0` | Full routed: production minus no-op |
| --- | ---: | ---: |
| LUT | 63903 / 4.902% | 55319 / 4.243% |
| Registers | 73566 / 2.821% | 55796 / 2.14% |
| BRAM tile | 1245.5 / 61.78% | 1207 / 59.87% |
| URAM | 17 / 1.771% | 17 / 1.771% |
| DSP | 1304 / 14.45% | 1304 / 14.45% |

### No-op Coyote Reference

This compares against the no-op/hello-world Coyote routed build at `/mnt/scratch/sdeheredia/Coyote/examples/full_dataset_it1/builds/BENIGN_FP00/build_hw/reports/config_0`. Use `Production minus no-op` as the best available full-design overhead relative to a basic Coyote design.

| Resource | No-op Coyote full routed | Production full routed | Production minus no-op |
| --- | ---: | ---: | ---: |
| LUT | 133578 / 10.26% | 188897 / 14.49% | 55319 / 4.243% |
| Registers | 196370 / 7.54% | 252166 / 9.67% | 55796 / 2.14% |
| BRAM tile | 197 / 9.77% | 1404 / 69.64% | 1207 / 59.87% |
| URAM | 0 / 0% | 17 / 1.77% | 17 / 1.771% |
| DSP | 0 / 0% | 1304 / 14.45% | 1304 / 14.45% |

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
| Full routed hierarchical utilization | `results/reports/shell_routed_hierarchical_utilization.rpt` |
| No-op Coyote full routed utilization | `results/reports/noop_coyote_shell_utilization_c0.rpt` |
| No-op Coyote user synth utilization | `results/reports/noop_coyote_user_synthed_c0_0.rpt` |
| Full routed timing | `results/reports/shell_timing_summary.rpt` |

## Replay

From the FPGA host:

```bash
cd /pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/reproducibility/prod_res512_coyote_accel_downsampler_hls4ml_e2e_20260524
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
