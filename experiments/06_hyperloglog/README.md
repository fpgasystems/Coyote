# 9.6. HyperLogLog cardinality estimation with on-demand reconfiguration

This directory contains the software and hardware source code for the results of Section 9.6. of the SOSP paper: *Coyote v2: Raising the Level of Abstraction for Data Center FPGAs*.
The following is a brief guide on compiling and running this specific experiment presented in the paper. 
Getting-started examples on Coyote, with more comments and in-depth tutorials can be found in the `examples/` folder.

**NOTE:** The exact throughput for this experiment may be different from the one obtained in the paper, depending on the Vitis HLS version and its scheduling algorithm.
In the paper, the results were obtained using Vitis HLS 2022.1, which was able to schedule the HLS kernel with a initiation interval of 1. However, some versions of Vitis HLS
may fail to achieve II = 1, and therefore have lower throughput.

## Hardware synthesis
Most experiments consists of two folders: `hw` (hardware) and `sw` (software), both of which are built using `make`. Hardware builds can take hours, depending on the example complexity and synthesis flags. Therefore, if synthesizing on a remote node, it's recommended to ensure the process doesn't get terminated when the connection is lost, by using Linux utilities such as `screen` or `tmux`. To build the hardware, the following commands should be used:
```bash
cd hw
mkdir build_hw && cd build_hw                
cmake ../
make project && make bitgen
```

Once complete, a full bitstream can be found in: `hw/build_hw/bitstreams/cyt_top.bit`. The full bitstream can be used to obtain the throughput of the HyperLogLog kernel, as shown in Figure 11a of the paper.

The partial bitstream can be found in `hw/build_hw/bitstreams/config_0/vfpga_c0_0.bit`, which can be used for measuring the time taken to load the bitstream on demand.

## Software compilation: Throughput measurement

The software follows a largely similar process to hardware synthesis, but, is typically much faster (compilation typically within a minute). In this example, there are two instances of the software. For measuring throughput, we use the code from `sw/throughput_scaling`, which can be compiled as follows:
```bash
cd sw/throughput_scaling
mkdir build_sw && cd build_sw                
cmake ../
make
```
Once complete, a binary can be found in: `sw/throughput_scaling/build_sw/bin/test`

## Software compilation: On-demand reconfiguration

To measure latency of on-demand reconfiguration, we need to compile two programs: (1) a "server" program which runs in the background and processes client requests, dynamically loading bitstreams and executing the kernel and (2) a client which submits requests. More details and detailed guides about Coyote's background service and on-demand reconfiguration can be found in Example 10 under `examples`.

Two CMake builds have to be triggered to obtain the correct executables. In order to build the server code, one needs to specify `-DINSTANCE=server`, while a build of the client software is specified with `-DINSTANCE=client`:
```bash
cd sw/partial_reconfiguration

mkdir build_server && cd build_server
cmake ../ -DINSTANCE=server && make

cd ../
mkdir build_client && cd build_client
cmake ../ -DINSTANCE=client && make
```
Once complete, binaries can be found in the folders: `sw/partial_reconfiguration/build_server/bin/test` and `sw/partial_reconfiguration/build_client/bin/test`


## Deploying the examples
We cover how to deploy the examples in two set-ups: The Heterogeneous Accelerated Compute Cluster (HACC) at ETH Zurich and on an independent set-up. In both cases, it's necessary to compile the driver:
```bash
cd Coyote/driver/
make
```

Once complete, a driver module can be foind in `Coyote/driver/build/coyote_driver.ko`

#### ETHZ HACC
The [ETHZ HACC](https://github.com/fpgasystems/hacc/tree/main) is a premiere cluster for research in systems, architecture, and applications. Its hardware equipment provides the ideal environment to run Coyote examples, since users can book various compute nodes (Alveo U55C, V80, U250, U280, Instinct GPU etc.) which are connected via a high-speed (100G) network.

The interaction and deployment on the HACC cluster can be simplified by using the `hdev` tool. It also allows to easily program the FPGA with a Coyote bitstream and insert the driver. For this purpose, the script `util/program_hacc_local.sh` has been created:
```bash
bash util/program_hacc_local.sh <path-to-bitstream> <path-to-driver-ko>
```

A successful completion of the FPGA programming and driver insertion can be checked via a call to
```bash
sudo dmesg
```

If the driver insertion and bitstream programming went correctly through, the last printed message should be `probe returning 0`. If you see this, your system is all ready to run the accompanying software, as explained below

#### Independent set-up
Before deploying Coyote on an independent set-up, ensure the following system requirements are met:
- AMD Alveo card. Most experiments in the paper were done using an Alveo u55c.
- Linux >= 5
- CMake >= 3.5, supporting C++17 standard
- Vivado suite, including Vitis HLS >= 2022.1. 
- Hugepages enabled

The steps to follow when deploying Coyote on an independent set-up are:
1. Program the FPGA using the synthesized bitstream using Vivado Hardware Manager via the GUI or a custom script

2. Rescan the PCIe devices and run PCI hot-plug.

3. Insert the driver using `sudo insmod <path-to-driver-ko> ip_addr=$qsfp_ip mac_addr=$qsfp_mac` (the parameters IP and MAC must only be specified when using networking on the FPGA)

If the driver insertion and bitstream programming went correctly through, the last printed message should be `probe returning 0`. If you see this, your system is all ready to run the accompanying software, as explained below.

## Running the throughput scaling experiment
After the full bitstream (`cyt_top.bit`) has been loaded and the driver has been inserted, the throughput scaling (Fig 11a) can be simply obtained using:
```bash
cd sw/throughput_scaling
bin/test
```

## Running the on-demand reconfiguration experiment
First, the server needs to be started, specifying the absolute path to the partial bitstream (typically in `hw/build_hw/bitstreams/config_0/vfpga_c0_0.bit`); as shown in below:
```bash
cd sw/partial_reconfiguration/build_server
bin/test -b <path-to-partial-bitstream>
```

This will launch a background thread, that can be accept client requests and will load the correct application.

Then, the client can submit a request, specifying the size of the HyperLogLog input. In this case, the inputs are random, but the code can easily be extended to allow reading inputs from some file or similar.
```bash
cd sw/partial_reconfiguration/build_client
bin/test -s <hll-size>
```

Once complete, the server returns the result and kernel execution latency to the client. We can now inspect the output from `dmesg`, to see how long the bitstream loading took:
```bash
reconfig_dev_ioctl():app reconfiguration time x ms
```

**NOTE:** When running partial reconfiguration, the FPGA must be loaded with some initial Coyote bitstream that is floorplanned in the same manner as this example. This could be a dedicated bitstream where the vFPGA is a placeholder, or, one can simply use the full bitstream (`hw/build_hw/bitstreams/cyt_top.bit`). While this bitstream already holds the HLL kernel, reconfiguration, partial reconfiguration will still occur on the first client request, since the server has no information about the underlying kernel when first loaded. However, after one partial reconfiguration, the server keeps track of the active kernel and will only reconfigure if the incoming request is requesting a kernel that is not already loaded on the FPGA (only matters when using more apps than one, which is not the case for this experiment.)