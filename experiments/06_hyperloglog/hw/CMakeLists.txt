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
message("*** 9.6. HyperLogLog cardinality estimation with on-demand reconfiguration [Hardware] ***")

# Enables stream from host memory (CPU DDR)
set(EN_STRM 1)

# Number of vFPGAs (user applications)
set(N_REGIONS 1)

# Enable partial reconfiguration to enable on-demand loading of user applications
set(EN_PR 1)

# For experiment, only one application --- more can of course be added
set(N_CONFIG 1)

# In the paper, this example was shown on an Alveo u55c; change as to other devices (e.g., u280)
# NOTE: The floorplan is typically device-specific
set(FDEV_NAME "u55c")

# An example floorplan which determined the location of the HLL application, so that it can be dynamically reconfigured
set(FPLAN_PATH "${CMAKE_SOURCE_DIR}/floorplan/fplan_u55c.xdc")

# Build with optimizations for easier timing closure
set(BUILD_OPT 1)

# This HLS kernel has good pipelining, no need to specify clock uncertainty
# A high clock uncertainty can help with timing closue but it could also increase latency and decrease throughput
set(HLS_CLOCK_UNCERTAINTY "0%")

# Confirm that the selected options are allowed
validation_checks_hw()

# Load a user application in Configuration #0, Region #0
load_apps (
    VFPGA_C0_0 "apps/hyperloglog"    
)

# Create the hardware project
create_hw()
