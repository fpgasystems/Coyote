<picture>
  <source media="(prefers-color-scheme: dark)" srcset="img/cyt_logo_dark.png" width = 220>
  <source media="(prefers-color-scheme: light)" srcset="img/cyt_logo_light.png" width = 220>
  <img src="img/cyt_logo_light.png" width = 220>
</picture>

[![Build benchmarks](https://github.com/fpgasystems/Coyote/actions/workflows/build_static.yml/badge.svg?branch=master)](https://github.com/fpgasystems/Coyote/actions/workflows/build_static.yml)
[![Documentation Status](https://github.com/fpgasystems/Coyote/actions/workflows/build_docs.yml/badge.svg?branch=master)](https://fpgasystems.github.io/Coyote/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

# _OS for FPGAs_

**Coyote** is a framework that offers operating system abstractions and a variety of shared networking (*RDMA*, *TCP/IP*), memory (*DRAM*, *HBM*)
and accelerator (*GPU*) services for modern heterogeneous platforms with FPGAs, targeting data centers and cloud environments.

Some of **Coyote's** features:
 * Multiple isolated virtualized vFPGA regions (with individual VMs)
 * Nested dynamic reconfiguration (independently reconfigurable layers: *Static*, *Service* and *Application*)
 * RTL and HLS user logic support
 * Unified host and FPGA memory with striping across virtualized DRAM/HBM channels
 * TCP/IP service
 * RDMA RoCEv2 service (compliant with Mellanox NICs)
 * GPU service
 * Runtime scheduler for different host user processes
 * Multithreading support

 <picture>
  <source media="(prefers-color-scheme: dark)" srcset="img/cyt_ov_dark.png" width = 620>
  <source media="(prefers-color-scheme: light)" srcset="img/cyt_ov_light.png" width = 620>
  <img src="img/cyt_ov_light.png" width = 620>
</picture>

## [For more detailed information, check out the documentation](https://fpgasystems.github.io/Coyote/)

## Prerequisites

Full `Vivado/Vitis` suite is needed to build the hardware side of things. Hardware server will be enough for deployment only scenarios. Coyote runs with `Vivado 2022.1`. Previous versions can be used at one's own peril.  

We are currently only actively supporting the AMD `Alveo u55c` accelerator card. Our codebase offers some legacy-support for the following platforms: `vcu118`, `Alveo u50`, `Alveo u200`, `Alveo u250` and `Alveo u280`, but we are not actively working with these cards anymore. Coyote is currently being developed on the HACC cluster at ETH Zurich. For more information and possible external access check out the following link: https://systems.ethz.ch/research/data-processing-on-modern-hardware/hacc.html


`CMake` is used for project creation. Additionally `Jinja2` template engine for Python is used for some of the code generation. The API is writen in `C++`, 17 should suffice (for now).

If networking services are used, to generate the design you will need a valid [UltraScale+ Integrated 100G Ethernet Subsystem](https://www.xilinx.com/products/intellectual-property/cmac_usplus.html) license set up in `Vivado`/`Vitis`.

To run the virtual machines on top of individual *vFPGAs* the following packages are needed: `qemu-kvm`, `build-essential` and `kmod`.

## Quick Start

Initialize the repo and all submodules:

~~~~
$ git clone --recurse-submodules https://github.com/fpgasystems/Coyote
~~~~

### Build `HW`

To build an example hardware project (generate a *shell* image):

~~~~
$ mkdir build_hw && cd build_hw
$ cmake <path_to_cmake_config> -DFDEV_NAME=<target_device>  -DEXAMPLE=<target_example>
~~~~

It's a good practice to generate the hardware-build in a subfolder of the `examples_hw`, since this already contains the cmake that needs to be referenced. In this case, the procedure would look like this: 

~~~~
$ mkdir examples_hw/build_hw && cd examples_hw/build_hw 
$ cmake ../ -DFDEV_NAME=<target_device>  -DEXAMPLE=<target_example>
~~~~

Already implemented target-examples are specified in `examples_hw/CMakeLists.txt` and allow to build a variety of interesting design constellations, i.e. `rdma_perf` will create a RDMA-capable Coyote-NIC. 

Generate all projects and compile all bitstreams:

~~~~
$ make project 
$ make bitgen
~~~~

Since at least the initial building process takes quite some time and will normally be executed on a remote server, it makes sense to use the `nohup`-command in Linux to avoid termination of the building process if the connection to the server might be lost at some point. In this case, the build would be triggered with: 

~~~~
$ nohup make bitgen &> bitgen.log &
~~~~

With this, the building process will run in the background, and the terminal output will be streamed to the `bitgen.log` file. Therefore, the command 

~~~~
$ tail -f bitgen.log
~~~~

allows to check the current progress of the build-process. 

The bitstreams will be generated under `bitstreams` directory. 
This initial bitstream can be loaded via JTAG.
Further custom shell bitstreams can all be loaded dynamically. 

Netlist with the *official* static layer image is already provided under `hw/checkpoints`. We suggest you build your shells on top of this image.
This default image is built with `-DEXAMPLE=static`.

### Build `SW`

Provided software applications (as well as any other) can be built with the following commands:

~~~~
$ mkdir build_sw && cd build_sw
$ cmake <path_to_cmake_config>
$ make
~~~~

Similar to building the HW, it makes sense to build within the `examples_sw` directory for direct access to the provided `CMakeLists.txt`: 

~~~~
$ mkdir examples_sw/build_sw && cd examples_sw/build_sw 
$ cmake ../ -DEXAMPLE=<target_example> -DVERBOSITY=<ON or OFF>
$ make
~~~~

The software-stack can be built in verbosity-mode, which will generate extensive printouts during execution. This is controlled via the `VERBOSITY` toggle in the cmake-call. Per default, verbosity is turned off.  

### Build `Driver`

After the bitstream is loaded, the driver can be inserted once for the initial static image.

~~~~
$ cd driver && make
$ insmod coyote_drv.ko <any_additional_args>
~~~~

### Provided examples
Coyote already comes with a number of pre-configured example applications that can be used to test the shell-capabilities and systems performance or start own developments around networking or memory offloading. 
These existing example apps are currently available (documentation can be found in the respective ./examples_sw/\<example> directories): kmeans, multithreading, perf_fpga, perf_local, rdma_service, reconfigure_shell, streaming_service, tcp_iperf.
There is always a pair of directories in ./examples_hw and ./examples_sw that belong together.
The hardware side contains vFPGA code which the software side interacts with through the Coyote-provided functions.

## Coyote v2 Hardware-Debugging
Coyote can be debugged on the hardware-level using the AMD ILA / ChipScope-cores. This requires interaction with the Vivado GUI, so that it's important to know how to access the different project files, include ILA-cores and trigger a rebuild of the bitstream: 

#### Opening the project file
Open the Vivado GUI and click `Open Project`. The required file is located within the previously generated hardware-build directory, at `.../<Name of HW-build folder>/test_shell/test.xpr` and should now be selected for opening the shell-project. 

###### Creating a new ILA
The `Sources` tab in the GUI can now be used to navigate to any file that is part of the shell - i.e. the networking stacks. There, a new ILA can be placed by including the module-template in the source code: 
~~~~
ila_<name> inst_ila_<name> (
  .clk(nclk); 
  .probe0(<Signal #1>), 
  .probe1(<Signal #2>), 
  ...
); 
~~~~
It makes sense to annotate (in comments) the bidwidth of each signal, since this information is required for the instantiation of the ILA-IP. 
In the next step, select the tab `IP Catalog` from the section `PROJECT MANAGER` on the left side of the GUI, search for `ILA` and select the first found item ("ILA (Integrated Logic Analyzer)"). Then, you enter the "Component Name" that was previously used for the instantiation of the module in hardware ("ila_<name>"), select the right number of probes and the desired sample data depth. Afterwards, assign the right bitwidth to all probes in the different tabs of the interface. Finally, you can start a `Out of context per IP`-run by clicking `Generate` in the next interface. Once this run is done, you have to restart the bitstream generation, which involves synthesis and implementation. To make sure that the changes with the new IP-cores for the added ILAs are incorporated into this bitstream, one first needs to delete all design-checkpoints (`*.dcp`) from the folders `.../<Name of the HW-build folder>/checkpoints/shell` and `.../<Name of the HW-build folder>/checkpoints/config_0`. After that, the generation can be restarted with 
~~~~
$ make bitgen
~~~~
in the original build-directory as described before. Once it's finished, the new ILA should be accessible for testing: 

###### Using an ILA for debugging
In the project-interface of the GUI click on `Open Hardware Manager` and select "Open target" in the top-dialogue. If you're logged into a machine with a locally attached FPGA, select `Auto Connect`, otherwise chose `Open New Target` to connect to a remote machine with FPGA via the network. Once the connection is established, you'll be able to select the specific ILA from the `Hardware` tab on the left side of the hardware manager. This opens a waveform-display, where the capturing-settings and the trigger-setup can be selected. This allows to create a data capturing customized to the desired experiment or debugging purpose. 

#### Recompilations after changes to the hardware
Since the Coyote-buildflow heavily relies on the usage of design-checkpoints, every change of the hardware design should be followed by deleting the key checkpoints in `.../<Name of the HW-build folder>/checkpoints/shell` and `.../<Name of the HW-build folder>/checkpoints/config_0` before triggering a rebuild with 
~~~~
$ make bitgen
~~~~
in the original build-directory as described before.

## Deploying on the ETHZ HACC-cluster 
The ETHZ HACC is a premiere cluster for research in systems, architecture and applications (https://github.com/fpgasystems/hacc/tree/main). Its hardware equipment provides the ideal environment to run Coyote-based experiments, since users can book up to 10 servers with U55C-accelerator cards connected via a fully switched 100G-network. User accounts for this platform can be obtained following the explanation on the previously cited homepage. 

The interaction with the HACC-cluster can be simplified by using the sgutil-run time commands. They also allow to easily program the accelerator with a Coyote-bitstreamd and insert the driver. For this purpose, the script `program_coyote.sh` has been generated. Under the assumption that the hardware-project has been created in `examples_hw/build` and the driver is already compiled in `driver`, the workflow should look like this: 

~~~
$ bash program_coyote.sh examples_hw/build/bitstreams/cyt_top.bit driver/coyote_drv.ko
~~~

Obviously, the paths to `cyt_top.bit` and `coyote_drv.ko` need to be adapted if a different build-structure has been chosen before. 
A successful completion of this process can be checked via a call to 

~~~
$ dmesg
~~~

If the driver insertion went through, the last printed message should be `probe returning 0`. Furthermore, the dmesg-printout should contain a line `set network ip XXXXXXXX, mac YYYYYYYYYYYY`, which displays IP and MAC of the Coyote-NIC if networking has been enabled in the system configuration. 

## Publication

#### If you use Coyote, cite us :

```bibtex
@inproceedings{coyote,
    author = {Dario Korolija and Timothy Roscoe and Gustavo Alonso},
    title = {Do {OS} abstractions make sense on FPGAs?},
    booktitle = {14th {USENIX} Symposium on Operating Systems Design and Implementation ({OSDI} 20)},
    year = {2020},
    pages = {991--1010},
    url = {https://www.usenix.org/conference/osdi20/presentation/roscoe},
    publisher = {{USENIX} Association}
}
```

## License

Copyright (c) 2023 FPGA @ Systems Group, ETH Zurich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

