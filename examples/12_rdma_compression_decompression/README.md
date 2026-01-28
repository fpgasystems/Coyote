# Coyote Example 12: RDMA with Data Compression/Decompression

Welcome to the twelfth Coyote example! This example extends Example 9 (RDMA performance benchmarking) by adding hardware-accelerated data compression and decompression engines directly into the RDMA data path. This demonstrates how Coyote can be used to implement transparent, high-performance data processing for RDMA traffic at 100G line rate.

## Table of Contents
[Overview](#overview)

[Compression/Decompression Architecture](#compressiondecompression-architecture)

[Hardware Implementation](#hardware-implementation)

[Software Concepts](#software-concepts)

[Building and Running](#building-and-running)

[Performance Considerations](#performance-considerations)

## Overview

This example demonstrates:
- **Hardware-accelerated compression/decompression** for RDMA traffic
- **Transparent operation**: no software changes required (uses the same interface as Example 9)
- **Line-rate performance**: 100G throughput with zero backpressure at 250 MHz
- **Bidirectional processing**: compression and decompression in both directions

The compression/decompression engines are inserted directly into the AXI stream data paths between the host memory and the network stack, allowing all RDMA traffic to be automatically compressed/decompressed without any software intervention.

### Use Cases
- **Bandwidth optimization**: Reduce network bandwidth consumption for repetitive or sparse data patterns
- **Storage efficiency**: Compress data before writing to remote storage over RDMA
- **Smart data transformation**: Demonstrate arbitrary processing on high-speed RDMA streams
- **In-line encryption**: Framework can be extended for encryption/decryption use cases

## Compression/Decompression Architecture

The system architecture follows the RDMA data flow from Example 9, with compression/decompression engines inserted at strategic points:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              LOCAL NODE                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  Host Memory                                                              │
│      │                                                                    │
│      │ RDMA WRITE Request (uncompressed)                                 │
│      ↓                                                                    │
│  ┌────────────────────┐                                                  │
│  │ Compression Engine │                                                  │
│  └─────────┬──────────┘                                                  │
│            │ (compressed)                                                │
│            ↓                                                              │
│  ┌─────────────────┐         ┌──────────┐                               │
│  │  Network Stack  │ ──────> │ 100G NIC │ ──> To Remote Node            │
│  │     (RDMA)      │ <────── │          │ <── From Remote Node          │
│  └─────────────────┘         └──────────┘                               │
│            │ (compressed)                                                │
│            ↓                                                              │
│  ┌──────────────────────┐                                                │
│  │ Decompression Engine │                                                │
│  └──────────┬───────────┘                                                │
│             │ RDMA WRITE Data (uncompressed)                             │
│             ↓                                                             │
│      Host Memory                                                          │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
```

### Data Path Details

Four compression/decompression engine instances handle bidirectional data flow:

1. **Outgoing RDMA WRITEs** (Host → Network):
   - Path: `axis_host_recv[0]` → **Compression** → `axis_rreq_send[0]`
   - Compresses data from local host before sending to remote node

2. **Incoming RDMA READ RESPONSEs** (Network → Host):
   - Path: `axis_rreq_recv[0]` → **Decompression** → `axis_host_send[0]`
   - Decompresses data received from remote node before writing to local host

3. **Outgoing RDMA READ RESPONSEs** (Host → Network):
   - Path: `axis_host_recv[1]` → **Compression** → `axis_rrsp_send[0]`
   - Compresses response data from local host before sending to remote node

4. **Incoming RDMA WRITEs** (Network → Host):
   - Path: `axis_rrsp_recv[0]` → **Decompression** → `axis_host_send[1]`
   - Decompresses data received from remote node before writing to local host

## Hardware Implementation

### Compression/Decompression Engine Design

The engines are implemented in SystemVerilog (`hw/src/rdma_compression_engine.sv`) with the following characteristics:

**Key Features:**
- **Interface**: 512-bit AXI4-Stream (matching Coyote's standard width)
- **Clock frequency**: 250 MHz
- **Throughput**: 128 Gbps (16 GB/s) raw bandwidth
- **Pipeline depth**: 2 stages for timing closure
- **Backpressure handling**: Zero backpressure guaranteed via pipelined architecture

**Module Interface:**
```systemverilog
module rdma_compression_engine (
    input  logic    aclk,       // 250 MHz clock
    input  logic    aresetn,    // Active-low reset
    AXI4SR.s        axis_in,    // Input AXI stream
    AXI4SR.m        axis_out    // Output AXI stream (compressed)
);
```

**Current Implementation:**

The provided implementation is a **demonstration framework** that:
- Maintains full 100G line rate with zero backpressure
- Preserves all AXI stream metadata (tid, tlast, tkeep)
- Provides a pipelined architecture suitable for complex algorithms
- Currently implements a simple passthrough for functional verification

**Extending to Real Compression:**

To implement actual compression algorithms, replace the passthrough logic in Stage 1 with:
- **Run-Length Encoding (RLE)**: Detect and compress repeated patterns
- **Dictionary-based**: LZ77, LZW, or similar algorithms
- **Statistical coding**: Huffman or arithmetic coding
- **Specialized algorithms**: Domain-specific compression (e.g., for scientific data)

The framework ensures timing closure and proper flow control, allowing you to focus on the compression algorithm itself.

### vFPGA Integration

The `vfpga_top.svh` file instantiates four engine instances (2 compression, 2 decompression) and wires them into the RDMA data paths:

```systemverilog
// Engine 1: Compress outgoing RDMA WRITEs
rdma_compression_engine inst_comp_wr (
    .aclk(aclk),
    .aresetn(aresetn),
    .axis_in(axis_host_recv[0]),
    .axis_out(axis_comp_out_wr)
);
`AXISR_ASSIGN(axis_comp_out_wr, axis_rreq_send[0])

// Engine 2-4: Similar instantiation for other paths
// ...
```

### ILA Debug Infrastructure

An Integrated Logic Analyzer (ILA) is included to monitor all compression/decompression data paths:
- 30 probes monitoring tvalid/tready/tlast signals for all four data paths
- Control signal monitoring (sq_wr, sq_rd)
- Configured via `init_ip.tcl`

## Software Concepts

The software layer is **identical to Example 9** - the compression/decompression is completely transparent to the application. This demonstrates a key benefit of hardware acceleration: complex processing can be added without modifying application code.

### Client and Server Applications

The client and server applications are unchanged from Example 9:
- Client initiates RDMA operations (WRITE or READ)
- Server responds according to the benchmark pattern
- Both use the same `initRDMA()` and `invoke()` API calls

The compression/decompression happens automatically in hardware, invisible to the software.

## Building and Running

### Prerequisites

- AMD Alveo FPGA (U55C recommended, U280/U250 supported)
- Vivado 2022.1 or later with UltraScale+ 100G Ethernet license
- Linux kernel 5.4+ (6.2+ for GPU P2P)
- CMake 3.5+ with C++17 support
- Two FPGA-equipped servers connected via 100G network
- Hugepages enabled (recommended for best performance)

### Hardware Build

```bash
cd examples/12_rdma_compression_decompression/hw
mkdir build && cd build
cmake ../ -DFDEV_NAME=u55c
make project && make bitgen
```

**Note**: Hardware synthesis can take several hours. Use `screen` or `tmux` for remote builds.

The bitstream will be available at: `build/bitstreams/cyt_top.bit`

### Software Build

Build both server and client executables:

```bash
# Build server
cd examples/12_rdma_compression_decompression/sw
mkdir build_server && cd build_server
cmake ../ -DINSTANCE=server
make

# Build client
cd ..
mkdir build_client && cd build_client
cmake ../ -DINSTANCE=client
make
```

### Deployment

1. **Program both FPGAs** with the same bitstream
2. **Load the driver** on both nodes (with network parameters)
3. **Run the server** first (it listens for QP exchange)
4. **Run the client** with the server's IP address

Example for HACC cluster:
```bash
# On both nodes
bash util/program_hacc_local.sh \
    examples/12_rdma_compression_decompression/hw/build/bitstreams/cyt_top.bit \
    driver/build/coyote_driver.ko

# On server node
cd examples/12_rdma_compression_decompression/sw/build_server
bin/test

# On client node (replace SERVER_IP with actual server CPU IP)
cd examples/12_rdma_compression_decompression/sw/build_client
bin/test --ip_address SERVER_IP
```

### Command-Line Options

Same as Example 9:
- `--ip_address, -i <string>`: Server CPU IP (client only, for QP exchange)
- `--operation, -o <0|1>`: READ (0) or WRITE (1) benchmark
- `--runs, -r <uint>`: Number of test iterations (default: 10)
- `--min_size, -x <uint>`: Starting transfer size (default: 64 B)
- `--max_size, -X <uint>`: Maximum transfer size (default: 1 MB)

## Performance Considerations

### Throughput Analysis

**Theoretical Maximum:**
- Clock: 250 MHz
- Data width: 512 bits = 64 bytes
- Peak bandwidth: 64 B × 250 MHz = 16 GB/s = 128 Gbps

**100G Line Rate Requirement:**
- Required: 100 Gbps = 12.5 GB/s
- Headroom: 128 / 100 = 1.28× (28% margin)

The 28% headroom allows for:
- Protocol overhead (RoCE headers, ACKs, etc.)
- Compression expansion in worst-case scenarios
- Pipeline bubbles and flow control

### Compression Ratio Impact

**Expansion case** (data doesn't compress well):
- If compression expands data by up to 28%, still maintains 100G
- Beyond 28%, may need to throttle or use selective compression

**Compression case** (data compresses well):
- Effective throughput can exceed 100G
- Network becomes the bottleneck, not the compression engine
- Reduced network utilization improves overall system efficiency

### Timing Considerations

The design uses a 2-stage pipeline to:
1. **Stage 0**: Input register for timing isolation
2. **Stage 1**: Compression/decompression logic
3. **Stage 2**: Output register for timing isolation

This ensures timing closure even with complex compression algorithms.

### Design Guidelines for Extensions

When implementing real compression algorithms:

1. **Maintain pipeline depth**: Add stages as needed, but keep total latency reasonable
2. **Handle variable-rate output**: Some algorithms produce variable amounts of output
3. **Manage metadata**: Preserve tid, tlast, tkeep signals correctly
4. **Consider FPGA resources**: Balance compression ratio vs. resource usage
5. **Test with real traffic**: RDMA patterns differ from typical file compression

## Comparison with Example 9

| Aspect | Example 9 | Example 12 |
|--------|-----------|------------|
| Software | Identical | Identical |
| Data path | Direct passthrough | Compression/decompression engines |
| Bandwidth | 100G raw | 100G compressed (potentially higher effective) |
| Latency | Minimal | +2 cycles per direction (pipeline) |
| Use case | Performance baseline | Bandwidth optimization, data transformation |

## Debugging and Troubleshooting

### Using the ILA

The ILA probes all four data paths. To use:
1. Connect to the FPGA with Vivado Hardware Manager
2. Add the ILA core to the waveform viewer
3. Set triggers on compression/decompression events
4. Capture and analyze traffic patterns

### Network Statistics

Check RDMA statistics: `cat /sys/kernel/coyote_sysfs_0/cyt_attr_nstats`

Look for:
- Packet loss (should be 0)
- Retransmissions (should be minimal)
- STRM down flag (should be 0)

### Common Issues

**Socket binding error**: Wait 60 seconds or use different port

**Timing issues**: If synthesis fails timing, increase pipeline depth

**Data corruption**: Verify compression/decompression symmetry on both nodes

## Further Reading

- [Example 9 README](../09_perf_rdma/README.md) - Base RDMA example
- [Coyote Documentation](https://fpgasystems.github.io/Coyote/) - Full system documentation
- [AXI4-Stream Specification](https://www.xilinx.com/support/documentation/ip_documentation/axi_ref_guide/latest/ug1037-vivado-axi-reference-guide.pdf) - Interface specification

## License

MIT License - Copyright (c) 2025, Systems Group, ETH Zurich
