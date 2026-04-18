######################################################################################
# This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
# 
# MIT Licence
# Copyright (c) 2025, Systems Group, ETH Zurich
# All rights reserved.
######################################################################################

cmake_minimum_required(VERSION 3.5)
set(CYT_DIR ${CMAKE_SOURCE_DIR}/../../../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteHW REQUIRED)

project(example_hls4ml_infer)
message("*** Coyote Example: hls4ml Inference [Hardware] ***")

set(EN_STRM 1)
set(N_STRM_AXI 1)
set(EN_MEM 0)
set(N_REGIONS 1)

validation_checks_hw()

load_apps (
    VFPGA_C0_0 "src"
)

create_hw()
