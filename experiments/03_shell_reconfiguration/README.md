# 9.3. Shell Reconfiguration

This directory contains the software and hardware source code for the results of Section 9.3. of the SOSP paper: *Coyote v2: Raising the Level of Abstraction for Data Center FPGAs*.

### Synthesizing the bitstreams
For his example, six hardware builds need to be started (3 cases/scenarios, as described in Table 3, and 2 configurations per case). The hardware configuration for these can be found in the `case_(1|2|3)` folders. To facilitate the hardware synthesis, there is a helper script, `run_synth.py` which will synthesize the the six bitstreams. Note, however, that hardware synthesis is a lengthy process and the script should be launched using Linux utilities such as `tmux` or `screen`.

In each of the six hardware builds, two bitstreams are generated: (1) a full one (found in `case_(1|2|3)/shell_*/build/bitstreams/cyt_top.bit`), which can be used for the Vivado flow, and a partial one (found in `case_(1|2|3)/shell_*/build/bitstreams/shell_top.bin`), which can be used for Coyote partial reconfiguration.

### Performing full reconfiguration [Vivado flow]
If performing full reconfiguration on the [ETHZ HACC cluster](https://github.com/fpgasystems/hacc/tree/main), a helper script, `reconfigure_vivado.py`, can be used, simply providing a path to the bistream. Under the hood, this script uses [hdev](https://github.com/fpgasystems/hdev), a development platform that facilitates the interaction with the HACC cluster. The script will compile the driver, load the bitstream using Vivado HW Manager, perform PCIe hot plug and insert the driver. On other clusters, the script should be modified to perform the equivalent steps.

### Performing partial reconfiguration [Coyote flow]
Partial reconfiguration can be performed on any cluster, using the software in `recofigure_coyote`, which can be compiled using:

```
cd recofigure_coyote
mkdir build && cd build
cmake ../
make
```

Then, the software can be launching using
```
bin/test -b <path-to-partial-bitstream>
````

It will print the total time taken for partial recofiguration.
Additionally, the "kernel" reconfiguration time can be seen from the command `sudo dmesg` and searching for the line:

```
reconfig_dev_ioctl():shell reconfiguration time x ms
```

**NOTE:** The program should be launched with an absolute path to the partial bitstream (`shell_top.bin`)

### Validating reconfiguration
To ensure reconfiguration went through, one can look for the above-mentioned line for time taken.

Additionally, the shell configuration can give some hints on what changed in the shell.

For example, in case 1, for the MMU with 2MB page size, one would observe:
```
read_shell_config():lTLB order 9, lTLB assoc 2, lTLB page size 2097152
```

while for 1GB page size it would be:
```
read_shell_config():lTLB order 9, lTLB assoc 2, lTLB page size 1073741824
```

For example, in case 2 with the RDMA shell, one would observe:
```
read_shell_config():enabled RDMA 1, port 0
...
setup_vfpga_devices():virtual FPGA device 0 created
```

and for the vector ops, we could see 2 vFPGAs and RDMA being disabled:

```
read_shell_config():enabled RDMA 0, port 0
...
irq_setup():using IRQ#185 with vFPGA 0
irq_setup():using IRQ#186 with vFPGA 1
```