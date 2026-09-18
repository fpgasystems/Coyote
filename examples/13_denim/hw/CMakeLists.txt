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

cmake_minimum_required(VERSION 3.5)
set(CYT_DIR ${CMAKE_SOURCE_DIR}/../../../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteHW REQUIRED)

project(example_13_denim)
message("*** Coyote Example 13: DENIM (Network Impairment) [Hardware] ***")

set(BUILD_OPT 1)

# One vFPGA, holding the DENIM control registers and a full RDMA endpoint. The
# impairment datapath is in the shell, not here, the endpoint wiring exists so
# the evaluation node terminates RoCE v2 itself. 
set(N_REGIONS 1)
set(EN_STRM 1)
set(N_STRM_AXI 2)
set(EN_MEM 0)

set(EN_RDMA 1)

# DENIM itself
set(EN_DENIM 1)
set(DENIM_VFPGA_ID 0)

# DENIM is placed upstream of the  sniffer tap in the shell, so enabling both gives 
# captures of post-impairment traffic. However, using them also needs the capture and DMA pipeline from
# example 11 in this vFPGA. This example is the control plane on its own.
set(EN_SNIFFER 0)

# Confirm that the selected options are allowed
validation_checks_hw()

# Load a user application in Configuration #0, Region #0
load_apps (
    VFPGA_C0_0 "src"
)

# Create the hardware project
create_hw()
