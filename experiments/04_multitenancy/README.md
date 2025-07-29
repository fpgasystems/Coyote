# 9.4. Multi-tenant AES ECB Encryption

This directory contains the software and hardware source code for the results of Section 9.4. of the SOSP paper: *Coyote v2: Raising the Level of Abstraction for Data Center FPGAs*.
The following is a brief guide on compiling and running this specific experiment presented in the paper. 
Getting-started examples on Coyote, with more comments and in-depth tutorials can be found in the `examples/` folder.

The number of active vFPGAs (as shown on the y-axis of Fig. 8 in the paper), can be varied using the `-n` parameter when running the software.

## Synthesis & compilation 
Most experiments consists of two folders: `hw` (hardware) and `sw` (software), both of which are built using `make`. Hardware builds can take hours, depending on the example complexity and synthesis flags. Therefore, if synthesizing on a remote node, it's recommended to ensure the process doesn't get terminated when the connection is lost, by using Linux utilities such as `screen` or `tmux`. To build the hardware, the following commands should be used:
```bash
cd hw
mkdir build_hw && cd build_hw                
cmake ../ -DFDEV_NAME=u55c      # In the paper, we demonstrate results on the Alveo u55c; the device can also be changed to an Alveo u280 or Alveo u250
make project && make bitgen
```

Once complete, a bitstream can be found in: `hw/build_hw/bitstreams/cyt_top.bit`

The software follows a largely similar process, but, is typically much faster (compilation typically within a minute).
```bash
cd sw
mkdir build_sw && cd build_sw                
cmake ../
make
```
Once complete, a binary can be found in: `sw/build_sw/bin/test`


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

If the driver insertion and bitstream programming went correctly through, the last printed message should be `probe returning 0`. If you see this, your system is all ready to run the accompanying software, by simply executing:

```bash
cd sw/build_sw
bin/test -n <number-of-vfpgas>
```

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

If the driver insertion and bitstream programming went correctly through, the last printed message should be `probe returning 0`. If you see this, your system is all ready to run the accompanying software, by simply executing:

```bash
cd sw/build_sw
bin/test -n <number-of-vfpgas>
```
