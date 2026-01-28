# Welcome to Coyote!
Welcome to Coyote - the open-source FPGA shell! Coyote provides typical OS abstractions on reconfigurable hardware: networking, memory virtualization, data movement, multi-tenancy etc. These examples will give you an overview of Coyote and make you an expert in no time - and after, you can easily start deploying your accelerated applications on distributed FPGAs and in conjunction with other accelerators (GPUs, CPUs).

## Table of contents
[Examples overview](#examples-overview)

[Building the examples](#building-the-examples)

[Deploying the examples](#deploying-the-examples)

[Simulating the examples](#simulating-the-examples)

## Examples overview
Coyote currently includes ten examples, covering the following concepts:
- **Example 1: Hello World!:** How to synthesize the Coyote hardware, as well as the various configurations and flags. On the software side, concepts such as data movement and *Coyote threads* are covered, which enable easy integration from a high-level language (C++) with the FPGA.
- **Example 2: HLS vector addition:** How to deploy high-level synthesis (HLS) kernels with Coyote and enable multiple data streams at once.
- **Example 3: Multiple, parallel AES encryption blocks:** How to set control registers on the FPGA from C++ and deploy multiple, parallel and indendent applications (vFPGAs) on hardware.
- **Example 4: User interrupts:** How to issue interrupts from hardware and pick them up in host software.
- **Example 5: Shell reconfiguration:** How to perform run-time reconfiguration of the Coyote shell, enabling the swapping out of various services (networking stack, memory type, user application etc.)
- **Example 6: FPGA-GPU peer-to-peer (P2P) data movement:** How to enable interaction of the FPGA with a GPU, completely bypassing host memory when performing data movement. A particularly interesting example for building heterogeneous ML systems.
- **Example 7: Data movement initiated by the FPGA:** How to perform data movement using the FPGA, independently from the CPU, by using Coyote's internal *send* and *completion* queues.
- **Example 8: Multi-threaded AES encryption [ADVANCED]:** How to improve performance by re-using the same hardware with multiple software threads.
- **Example 9: Using the FPGA as a SmartNIC for Remote Direct Memory Access:** How to do networking with Coyote's internal, 100G, fully RoCEv2-compliant networking stack.
- **Example 10: Application reconfiguration and background services [ADVANCED]:** How to dynamically load Coyote applications to a system-wide service, which automatically schedules tasks and reconfigures the FPGA with the corrects bitstream, based on client requests. 

## Building the examples
Each example includes a detailed README, explaining the example as well as the various hardware and software concepts from Coyote. Before running an example, it would be worthwhile to read and understand the accompanying README. Additionally, the source code for each example is inside the folder `src/`, which includes commented code matching the concepts covered in the README.

Each example consists of two folders: `hw` (hardware) and `sw` (software), both of which are built using `make`. As you will see from the examples, it's only necessary to write the hardware logic for your target application, which can automatically be linked with the rest of Coyote's internal architecture. Hardware builds can take hours, depending on the example complexity and synthesis flags. Therefore, if synthesizing on a remote node, it's recommended to ensure the process doesn't get terminated when the connection is lost, by using Linux utilities such as `screen` or `tmux`. A typical hardware example flow would be:
```bash
cd Coyote/examples/01_hello_world/hw
mkdir build_hw && cd build_hw                
cmake ../ -DFDEV_NAME=<target_dev>     
make project && make bitgen
```

The default device for Coyote is the AMD Alveo U55C (passed as `-DFDEV_NAME=u55c`). We also support AMD Alveo U280 and U250, but with less recent testing. Before building, it's recommended to inspect the `CMakeLists.txt`, to understand the Coyote's configuration and synthesis parameters. For more details on the build flow and the various configuration parameters, please refer to the [documentation](https://fpgasystems.github.io/Coyote/intro/quick-start.html#building-the-hardware). Once complete, a bitstream can be found in: `Coyote/examples/01_hello_world/hw/build_hw/bitstreams/cyt_top.bit`

The software follows a largely similar process, but, is typically much faster (compilation typically within a minute). The software rarely has additional parameters to it: the only exceptions are Examples 6 and 9, which are covered in the individual README files.
```bash
cd Coyote/examples/01_hello_world/sw
mkdir build_sw && cd build_sw                
cmake ../
make
```

## Deploying the examples
We cover how to deploy the examples in two set-ups: The Heterogeneous Accelerated Compute Cluster (HACC) at ETH Zurich and on an independent set-up. In both cases, it's necessary to compile the driver:
```bash
cd Coyote/driver/
make
```

#### ETHZ HACC
The [ETHZ HACC](https://github.com/fpgasystems/hacc/tree/main) is a premiere cluster for research in systems, architecture, and applications. Its hardware equipment provides the ideal environment to run Coyote examples, since users can book various compute nodes (Alveo U55C, V80, U250, U280, Instinct GPU etc.) which are connected via a high-speed (100G) network.

The interaction and deployment on the HACC cluster can be simplified by using the `hdev` tool. It also allows to easily program the FPGA with a Coyote bitstream and insert the driver. For this purpose, the script `util/program_hacc_local.sh` has been created:
```bash
bash util/program_hacc_local.sh <path-to-bitstream> <path-to-driver-ko>
```
An example for programming the FPGA with Example 1 would look something like:
```bash
bash util/program_hacc_local.sh ../examples/01_hello_world/hw/build_hw/bitstreams/cyt_top.bit ../driver/build/coyote_driver.ko
```
A successful completion of the FPGA programming and driver insertion can be checked via a call to
```bash
sudo dmesg
```
If the driver insertion and bitstream programming went correctly through, the last printed message should be `probe returning 0`. If you see this, your system is all ready to run the accompanying software, by simply executing:
```bash
cd Coyote/examples/01_hello_world/sw/build_sw
./test
```

Congrats! You just completed your first Coyote example.

#### Independent set-up
Before deploying Coyote on an independent set-up, ensure the following system requirements are met:
- AMD Alveo card, recommended U55C. Some support for U280 and U250.
- Linux >= 5; for GPU P2P >= 6.2. We have extensively tested Coyote with Linux 5.4, 5.15 and 6.2.
- CMake >= 3.5 supporting C++17 standard
- Vivado suite, including Vitis HLS >= 2022.1. If running Example 8 (networking), to generate the design you will need a valid [UltraScale+ Integrated 100G Ethernet Subsystem license](https://www.xilinx.com/products/intellectual-property/cmac_usplus.html) set up in Vivado/Vitis.
- For Example 6, GPU P2P, AMD Instinct Accelerator cards are supported, with ROCm >= 6.0
- Hugepages enabled; while Coyote works just fine with regular pages, most of the examples assume available hugepages and, in general, hugepages significantly improve performance. Coyote works with standard Linux 2MB hugepages out of the box, and we are also working on adding support for 1GB hugepages.

The steps to follow when deploying Coyote on an independent set-up are:
1. Program the FPGA using the synthesized bitstream using Vivado Hardware Manager via the GUI or a custom script (an example structure is given in `util/program_alveo.tcl`). An example path for the bitstream for the first example would be: `Coyote/examples/01_hello_world/hw/build_hw/bitstreams/cyt_top.bit`.
2. Rescan the PCIe devices; an example script of this is given in `util/hot_reset.sh`. It may require some tuning for your system.
3. Insert the driver using `sudo insmod Coyote/driver/build/coyote_driver.ko ip_addr=$qsfp_ip mac_addr=$qsfp_mac` (the parameters IP and MAC must only be specified when using networking on the FPGA; i.e. Example 8)

If the driver insertion and bitstream programming went correctly through, the last printed message should be `probe returning 0`. If you see this, your system is all ready to run the accompanying software, by simply executing:
```bash
cd Coyote/examples/01_hello_world/sw/build_sw
./test
```

Congrats! You just completed your first Coyote example.

## Simulating the examples
Coyote also offers an extensive simulation environment, that allowes the use of the same software and vFPGA, without running on actual hardware. The code is compiled with a mock `cThread` that interacts with the simulation environment and writes a dump of the waveform to `<build_dir>/sim/sim_dump.vcd`. The dump may be opened in any waveform viewer afterwards.

*Hint: Using Vivado 2023.2 will throw an error about non-parameterized mailboxes that is a regression bug documented in this forum post (https://adaptivesupport.amd.com/s/question/0D54U00007wz0KeSAI/error-xsim-433980-generic-nonparameterized-mailbox?language=en_US). Use a different Vivado version for the simulation.*

To use the simulation environment, first create a simulation project by running `make sim`. For instance, Example 1 can be simulated using:
```bash
cd Coyote/examples/01_hello_world/hw
mkdir build_sim && cd build_sim          
cmake ../ -DFDEV_NAME=<target_dev>     
make sim
```
Then, the software is compiled. To do this, we need to enable the simulation for the example binary.
Normally, you should follow the guide in the [simulation documentation](../sim/README.md) to include
the simulation version of the coyote software library. For convenience, the examples provide an `EN_SIM`
CMake option to include the appropriate version of the Coyote library. Thus, you can compile the example
software in simulation mode via:

```bash
cmake </path/to/CMakeLists.txt> -DEN_SIM=ON
```

Then, when running the example you must set the `COYOTE_SIM_DIR` environment variable
such that it points to the `build_sim` folder.

For Example 1, this would look something like:
```bash
cd Coyote/examples/01_hello_world/sw
mkdir build_sw && cd build_sw                
cmake ../ -DEN_SIM=ON
make
COYOTE_SIM_DIR=../../hw/build_sim/ ./test 
```

If you need verbose output for debugging purposes, put a `#define VERBOSE` into `sim/sw/include/Common.hpp`. More details on simulation can be found in the corresponding README, `Coyote/sim/README.md`
