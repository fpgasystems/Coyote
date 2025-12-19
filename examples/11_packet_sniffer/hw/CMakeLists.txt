
######################################################################################
# This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
# 
# MIT Licence
# Copyright (c) 2025, Systems Group, ETH Zurich
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

project(example_11_packet_sniffer)
message("*** Coyote Example 11: Packet Sniffer [Hardware] ***")

# Enable optimizations for better timing closure
set(BUILD_OPT 1)

# Enables streams from card memory (FPGA HBM or DDR)
set(EN_STRM 0)
set(EN_MEM 1)
set(N_CARD_AXI 1)

# Number of vFPGAs (user applications)
set(N_REGIONS 1)

# Enables packet sniffer functionality
set(EN_SNIFFER 1)
set(SNIFFER_VFPGA_ID 0)
set(EN_RDMA 1)

# Confirm that the selected options are allowed
validation_checks_hw()

# Load a user application in Configuration #0, Region #0 
# Configurations become important in partial reconfiguration (PR) flows, covered in example Example 10
# Region is equal to zero, since we only have one vFPGA
# The macro load_apps(...) will look for a file vfgpa_top.svh in the specified folder (in this case src/)
load_apps (
    VFPGA_C0_0 "src"
)

# Create the hardware project
create_hw()
