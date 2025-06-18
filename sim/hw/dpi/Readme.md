# Simulation DPI-C functions

This directory contains files, which get compiled into a shared library. This library is linked to the simulation test-bench and can be called from the test bench. The goal is to enable functionality that
cannot be implemented in SystemVerilog directly. See the [Vivado DPI-C documentation](https://docs.amd.com/r/2021.2-English/ug900-vivado-logic-simulation/Direct-Programming-Interface-DPI-in-Vivado-Simulator).

The shared library will be automatically compiled when you run the ```make sim ``` target.

If you want to re-compile without running the whole sim target, execute the following:

First, enter your build-directory (e.g. ```build_hw```):

```bash
cd build_hw
```

Then run:

```bash
/usr/bin/cmake ..
make sim_dpi_c
```

This will call the ```CMakeLists.txt``` in this directory.
