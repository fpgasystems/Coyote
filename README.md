# Coyote
Reconfigurable Heterogeneous Architecture Framework aiming to provide operating system abstractions.

## Prerequisites
Framework was tested with `Vivado 2019.2` and `Vivado 2020.1`. Following Xilinx platforms are supported: `vcu118`, `Alveo u250`, `Alveo u280`. Minimum version of CMake required is 3.0.

## Dependencies
Initiate the network stack:

	$ git clone
	$ git submodule update --init --recursive

## Build `HW`

Create a build directory:

	$ cd hw
	$ mkdir build
	$ cd build

Enter a valid system configuration:

	$ cmake .. -DFDEV_NAME=u250 <params...>

Following configuration options are provided:

| Name                   | Values                   | Desription                                                                         |
|------------------------|--------------------------|------------------------------------------------------------------------------------|
| FDEV\_NAME             | <**u250**, u280, vcu118> | Supported devices                                                                  |
| N\_REGIONS             | <**1**:16>               | Number of independent regions                                                      |
| EN\_STRM               | <0, **1**>               | Enable direct host-fpga streaming                                                  |
| EN\_DDR                | <**0**, 1>               | Enable local FPGA memory stack                                                     |
| EN\_AVX                | <0,**1**>                | AVX support                                                                        |
| EN\_BPSS               | <0,**1**>                | Bypass descriptors in user logic                                                   |
| N\_DDR\_CHAN           | <0:4>                    | Number of DDR channels in striping mode                                            |
| EN\_PR                 | <**0**, 1>               | Enable dynamic reconfiguration of the regions                                      |
| EN\_TCP                | <**0**, 1>               | Enable TCP/IP stack                                                          		 |
| EN\_RDMA               | <**0**, 1>               | Enable RDMA stack   															     |
| EN\_FVV                | <**0**, 1>               | Enable Farview verbs                                                               |

If network stack is used, the IP dependencies can be installed with:

	make installip

Create the shell and the project:

	make shell

If PR is enabled, additional sets of configurations can be added by running the following command:

	make dynamic

At this point user logic can be inserted. User logic wrappers can be found under build project directory in the **hdl/config_X** where **X** represents the chosen PR configuration. If multiple PR configurations are present it is advisable to put the most complex configuration in the initial one (**config_0**). For best results explicit floorplanning should be done manually after synthesis. 

Once the user design is ready to be compiled, run the following command:
	
	make compile

Once the compilation finishes, the initial bitstream with the static region can be loaded to the FPGA via JTAG. At any point during the compilation, the status can be checked by opening the project in Vivado. This can be done by running `start_gui` in the same terminal shell. All compiled bitstreams, including partial ones, can be found in the build directory under **bitstreams**.

## Driver

After the bitstream has been loaded, the driver can be compiled on the target host machine:
	
	cd driver
	make

Insert the driver into the kernel:

	insmod fpga_drv.ko 

Run the script **util/hot_reset.sh** to rescan the PCIe. If this fails the restart of the machine might be necessary after this step.

## Build `SW`

Any of the `sw` projects can be built with the following commands:

	cd sw/<project>
	mkdir build
	cd build
	cmake ..
	make main

## Simulation

User logic can be simulated by creating the testbench project:

	cd hw/sim/scripts/sim
	vivado -mode tcl -source tb.tcl