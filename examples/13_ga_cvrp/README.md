# Coyote Example 13: Multi-vFPGA Dual-Stream Processing Pipeline

Welcome to the thirteenth Coyote example! In this example, we cover how to deploy an asynchronous, multi-accelerator processing pipeline across multiple vFPGAs using dual host AXI streams. The application workload is a Genetic Algorithm for the Capacitated Vehicle Routing Problem (for more see [here](https://github.com/schreadr/ga-cvrp-heterogeneous-hardware])). How to synthesize hardware, compile software, and load the bitstream/driver is explained in the top-level [Coyote Examples README](../README.md).

## Table of contents
[Example Overview](#example-overview)

[Hardware Concepts](#hardware-concepts)

[Software Concepts](#software-concepts)

[Additional Information](#additional-information)

## Example overview
This example demonstrates a high-throughput heterogeneous processing pipeline on Coyote. Rather than executing as a single-transfer accelerator, the design distributes micro-batches across multiple independent vFPGAs while streaming pairs of data buffers in parallel.

The operational flow consists of:
1. **Cache Initialization**: Static problem data is loaded beforehand into on-chip vFPGA cache memory via host stream 0, commanded via control registers and synchronized through completion counters.
2. **Dual-Stream Bidirectional Streaming**: Input data is streamed concurrently into the vFPGA across two independent host streams, processed in hardware, and written back to host memory.
3. **Multi-vFPGA Asynchronous Pipelining**: Micro-batches are dispatched across multiple vFPGA regions, overlapping host-side preparation and decoding with concurrent FPGA DMA execution.

## Hardware concepts
- **Multi-vFPGA Regions**: The dynamic logic area is partitioned into two independent vFPGA regions (`N_REGIONS = 2`). Both regions load the same top-level wrapper (`vfpga_top.svh`) to enable symmetric parallel processing.
- **Dual Host AXI Streams**: Two 512-bit AXI stream pairs per vFPGA (`N_STRM_AXI = 2`) stream paired data directly between host memory and the kernel over PCIe DMA.
- **AXI4-Lite CSR Width Conversion (64-bit to 32-bit)**: Coyote exposes a 64-bit user CSR bus (`axi_ctrl`), whereas HLS kernel configuration registers use a 32-bit AXI4-Lite interface. An AXI-Lite width adapter bridges the two buses, allowing 64-bit host CSR writes to configure 32-bit kernel registers directly.

## Software concepts
- **Multi-Region Coyote Threads**: Software instantiates a dedicated `cThread` for each vFPGA region (`vfid = 0, 1`).
- **Hugepage Memory Allocation**: Host buffers are allocated as hugepages (`CoyoteAllocType::HPF`), which pre-maps entries into the vFPGA's internal TLB to prevent page faults during streaming DMA.
- **Control Register Management**: Scalar configuration registers and the execution trigger (`ap_start`) are set and validated via `setCSR` / `getCSR`.
- **Dual-Stream and Polling**: Bidirectional DMA transfers are launched concurrently on both streams. The host thread polls `checkCompleted(coyote::CoyoteOper::LOCAL_TRANSFER)` until both transfers finish.
- **Asynchronous Pipelining & Benchmarking**: Double-buffered micro-batching allows CPU worker threads to prepare and decode batches while the vFPGAs execute DMA transfers in the background.

## Additional information
### Command line parameters
- `[--help | -h]`: Print help message
- `[--smoke_test | -t]`: Run a single-generation smoke test on all vFPGAs and exit
- `[--vrp_file | -f] <string>`: Path to CVRP problem instance file (default: `../../problem_instances/P-n40-k5.vrp`)
- `[--pop_mult | -p] <uint>`: Population size multiplier (`population = dimension * multiplier`, default: `20`)
- `[--generations | -g] <uint>`: Number of generations (default: `100`)
- `[--elitism | -e] <double>`: Elitism percentage to retain across generations (default: `5.0`)
- `[--seed | -s] <uint>`: Random seed (default: `0xC0FFEE`)
- `[--two_opt_k | -k] <int>`: Number of 2-opt iterations per subtour in hardware (default: `20`)
- `[--precheck | -r] <bool>`: Enable geometric precheck for 2-opt moves (default: `false`)
- `[--crossover | -c] <int>`: Crossover probability percentage (default: `100`)
- `[--mutation | -m] <int>`: Mutation probability percentage (default: `10`)
- `[--output | -o] <string>`: Path to output JSON file (default: none)
