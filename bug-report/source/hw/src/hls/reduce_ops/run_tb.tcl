# Standalone TCL script for simulating reduce_ops HLS module with Vitis HLS

open_project reduce_ops_prj -reset
set_top reduce_ops
open_solution "solution1" -reset

# Target FPGA - Alveo U55C
set_part xcu55c-fsvh2892-2L-e

# 250 MHz clock with 27% uncertainty, matching the Coyote default
create_clock -period "4" -name default
set_clock_uncertainty 27% default

# Sources
add_files reduce_ops.cpp -cflags "-std=c++14"
add_files -tb reduce_ops_tb.cpp -cflags "-std=c++14"

# C simualation, synthesis and RTL simulation
csim_design
csynth_design
cosim_design

exit
