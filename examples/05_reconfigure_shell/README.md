# Coyote Example 5: Shell reconfiguration
Welcome to the fifth Coyote example! In this example we will cover how to reconfigure the Coyote shell at run-time. As with all Coyote examples, a brief description of the core Coyote concepts covered in this example are included below. How to synthesize hardware, compile the examples and load the bitstream/driver is explained in the top-level example README in Coyote/examples/README.md. Please refer to that file for general Coyote guidance.

**IMPORTANT:** This example relies on bitstreams from previous examples. First, to get started with the example, you should program the shell with the full bitstream (`cyt_top.bit`) from *Example 4: User Interrupts*. Since this example is about shell reconfiguration, you should also have the *partial shell bitstream* (`shell_top.bin`) from *Example 2: HLS Vector Addition*.

## Table of contents
[Example Overview](#example-overview)

[Hardware Concepts](#hardware-concepts)

[Software Concepts](#software-concepts)

[Expected Results](#expected-results)

## Example overview
In this example, we cover how to reconfigure the whole Coyote shell. Note, this is different from partial reconfiguration, which is covered in *Example 10: Application Reconfiguration*. Recall, the Coyote hardware consists of the shell and the static layer. The static layer consists of an XDMA core for communication with the host CPU as well as a few other IP blocks related to partial reconfiguration. For the same chip, the static layer always remains the same; that is, it cannot be reconfigured. However, the shell can be reconfigured at run-time. The shell consists of the so-called *hardware services* (dynamic layer) and *vFPGAs* (application layer). The *hardware services*, which are analogous to Linux software libraries, provide some ready-to-use interfaces and abstractions for common components such as networking (RDMA and TCP/IP), memory (HBM/DDR etc.). An example of shell reconfiguration is shown below, where we went from a shell with one vFPGA (e.g. vector addition) and an HBM controller to a shell with two vFPGAs (encryption and compression) and networking (RDMA) enabled. Shell reconfiguration at run-time has several advantages over full FPGA re-programming:
- Since the static part remains in-place, i.e. it's not reprogrammed, there is no need to do PCIe rescanning, which is often slow
- The Coyote driver doesn't need to be re-loaded, making the process, again, faster compared to standard FPGA programming
- The shell can be reconfigured dynamically; e.g. depending on incoming user requests etc.

<div align="center">
  <img src="img/shell_reconfigure.png">
</div>

**VERY IMPORTANT:** When reconfiguring the shell, the current and the new shell must have been linked against the same static layer checkpoint. As explained before, Coyote consists of a static layer and a shell layer, which are linked together before the final Place-and-Route. To enable a faster building process, we provide a pre-routed and locked static layer checkpoint which is used in the *shell* build flow (`BUILD_SHELL = 1`, `BUILD_STATIC = 0`, `BUILD_APP = 0`) for linking. Now, recall that Place-and-Route is not deterministic; therefore, even if we used the same static layer module, its routed checkpoint can differ from one Vivado run to another. This can cause issues in shell reconfiguration as there is no guarantee that the connections from the two shells (which are linked against different static layers) are in the same place. Therefore, if both the shells where built using the *shell* build flow, they can be reconfigured at run-time. 

## Hardware concepts
This example uses bitstreams from previous examples; therefore there are no new hardware concepts.

## Software concepts

### Shell reconfiguration
Reconfiguring the shell from Coyote is straight-forward. First, you should create an instance of the class `cRcnfg` and assign it to the correct (physical) FPGA (0 for systems with one accelerator card). Then, reconfiguration can be triggered using the `reconfigureShell` function. Importantly, the function takes one string argument - path to the partial shell bitstream. This **MUST** be a `.bin` file (and **NOT** `.bit`). If you followed the standard Coyote build flow, the partial shell bitstream is named `shell_top.bin` (and **NOT** `cyt_top.bin` or `cyt_top.bit` which also include the static layer of Coyote).
```C++
coyote::cRcnfg rcnfg(0);
rcnfg.reconfigureShell(bitstream_path);
```

## Expected results
To run this example, you need to provide a path to the vector addition partial bitstream. An example of this would be (adjust paths as needed):
```bash
cd sw/build
./test -b ../../../02_hls_vadd/hw/build/bitstreams/shell_top.bin
```
The shell reconfiguration should take around ~850ms, as reported from the example code. Further inspecting the output from `dmesg`, you should also find a line:
```bash
reconfig_dev_ioctl():shell reconfiguration time 49 ms
```

The actual hardware reconfiguration run-time is typically much faster (~50ms compared to ~850ms); however, in order to reconfigure, Coyote must load the bitstream from disk and allocate memory in the kernel-space to hold it, before writing it to the FPGA reconfiguration module. Additionally, there are a few reset and initialization functions that need to be completed.
