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
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
######################################################################################

# CMake configuration
cmake_minimum_required(VERSION 3.5)
set(CYT_DIR ${CMAKE_SOURCE_DIR}/../../../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteHW REQUIRED)

project(test)
message("*** 9.4. Multi-tenant AES ECB Encryption [Hardware] ***")

# Number of vFPGAs (parallel user applications)
set(N_REGIONS 4)

# Enables host memory streams
set(EN_STRM 1)

# Build with optimizations for easier timing closure
set(BUILD_OPT 1)

# In the paper, this example was shown on an Alveo u55c; change as required to other devices (e.g., u250, u280)
set(FDEV_NAME "u55c")

# Confirm that the selected options are allowed
validation_checks_hw()

# Loads the four user applications
# src corresponds to the folder which includes the vfpga_top.svh file and the RTL/HLS kernel
load_apps (
    VFPGA_C0_0 "src"
    VFPGA_C0_1 "src"
    VFPGA_C0_2 "src"
    VFPGA_C0_3 "src"
)

# Create the hardware project
create_hw()
