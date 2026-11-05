######################################################################################
# This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
# 
# MIT Licence
# Copyright (c) 2026, Systems Group, ETH Zurich
# All rights reserved.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
######################################################################################

# CMake configuration
# Coyote has its own internal build system, which must be sourced when synthesizing bitstreams
# This can be done using find_package(CoyoteHW REQUIRED)
cmake_minimum_required(VERSION 3.5)
set(CYT_DIR ${CMAKE_SOURCE_DIR}/../../../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteHW REQUIRED)

project(ga-cvrp-heterogeneous-hardware)
message("*** GA for CVRP on FPGA ***")

# Enables streams from host memory (CPU DDR): streams 0 and 1 for population
set(EN_STRM 1)
set(N_STRM_AXI 2)

set(EN_MEM 0)

# Number of vFPGAs (user applications)
set(N_REGIONS 2)

# Since timing closure with HBM can be difficult, run place and route with optimizations 
set(BUILD_OPT 1)

# Confirm that the selected options are allowed
validation_checks_hw()

# Load user applications in Configuration #0 for both regions
# The macro load_apps(...) will look for a file vfpga_top.svh in the specified folder (in this case src/)
load_apps (
    VFPGA_C0_0 "src"
    VFPGA_C0_1 "src"
)

# Copy the common header files from the software project to the hardware project
set(HLS_SW_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../sw/src")
file(COPY
    "${HLS_SW_INCLUDE_DIR}/ga_encoding_constants.hpp"
    "${HLS_SW_INCLUDE_DIR}/static_block.hpp"
    DESTINATION "${CMAKE_CURRENT_SOURCE_DIR}/src/hls/processing_node"
)

# Create the hardware project
create_hw()
