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

cmake_minimum_required(VERSION 3.5)
set(CYT_DIR ${CMAKE_SOURCE_DIR}/../../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteHW REQUIRED)
project(test)

# 1 region (vFPGA)
set(N_REGIONS 1)

# If the device changes, the following variable should also reflect the change
set(FPLAN_PATH "${CMAKE_SOURCE_DIR}/floorplans/fplan_u250.xdc")

if(EXAMPLE STREQUAL "perf_local")
    message("*** Pass-through shell ***")
    set(EN_STRM 1)

    set(SHELL_PATH "${CMAKE_SOURCE_DIR}/shells/perf_local")

    validation_checks_hw()
    load_apps (
        VFPGA_C0_0 "apps/perf_local"
    )
    create_hw()
endif()

if(EXAMPLE STREQUAL "mem_vadd")
    message("*** Vector addition from memory shell ***")
    set(EN_MEM 1)
    set(EN_STRM 0)
    set(N_CARD_AXI 2)

    set(SHELL_PATH "${CMAKE_SOURCE_DIR}/shells/mem_vadd")

    validation_checks_hw()
    load_apps (
        VFPGA_C0_0 "apps/mem_vadd"
    )
    create_hw()
endif()

if(EXAMPLE STREQUAL "rdma_aes")
    message("*** RDMA w/ AES encryption shell ***")
    set(EN_STRM 1)
    set(EN_RDMA 1)

    set(SHELL_PATH "${CMAKE_SOURCE_DIR}/shells/rdma_aes")

    validation_checks_hw()
    load_apps (
        VFPGA_C0_0 "apps/rdma_aes"
    )
    create_hw()
endif()
