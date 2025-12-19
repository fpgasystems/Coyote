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

import os

# Get the environment configuration we need
COYOTE_DIR = '${CYT_DIR}'

# Append module path to search
os.sys.path.append(os.path.join(COYOTE_DIR, 'sim'))

# Update the constants in the unit test module
from unit_test import constants

# Set constants to CMAKE values
constants.VIVADO_BINARY_PATH = '${VIVADO_BINARY}'
constants.MAX_NUMBER_STREAMS = int('${N_STRM_AXI}')
constants.HW_BUILD_FOLDER = '${CMAKE_BINARY_DIR}'
constants.UNIT_TEST_FOLDER = '${UNIT_TEST_DIR}'
constants.SOURCE_FOLDERS = '${APPS_VFPGA_C0_0}'.split()
constants.VFPGA_SOURCE_FOLDER = constants.SOURCE_FOLDERS[0]
constants.N_REGIONS = int('${N_REGIONS}')
constants.CLOCK_PERIOD = "${SIM_CLOCK_PERIOD}"
constants.STREAM_ID_BITS = int("${DATA_DEST_BITS}")
constants.VADDR_BITS = int("${VADDR_BITS}")
constants.PROJECT_NAME = '${PROJECT_NAME}'

# All of the following constants are derived from the above definitions!
constants.TEST_BENCH_FOLDER = os.path.join(COYOTE_DIR, "sim", "hw")
constants.SIM_FOLDER = os.path.join(constants.HW_BUILD_FOLDER, "sim")
constants.IO_INPUT_FILE_NAME = os.path.join(constants.SIM_FOLDER, "input.bin")
constants.IO_OUTPUT_FILE_NAME = os.path.join(constants.SIM_FOLDER, "output.bin")
constants.COMPILE_CHECK_FILE = os.path.join(constants.SIM_FOLDER, ".last_change_time")
constants.SIM_OUT_FILE = os.path.join(constants.UNIT_TEST_FOLDER, "sim.out")
constants.DIFF_FOLDER = os.path.join(constants.UNIT_TEST_FOLDER, "diff")
# Note: at the moment, we only support one vFPGA!
# Therefore, we hardcoded the path to the first vFPGA
constants.SIM_TARGET_V_FPGA_TOP_FILE = os.path.join(
    constants.SIM_FOLDER, "vfpga_top.svh"
)
constants.SRC_V_FPGA_TOP_FILE = os.path.join(constants.VFPGA_SOURCE_FOLDER, "vfpga_top.svh")

# Re-export all definitions from the actual unit-test module
from unit_test import *
from unit_test import __all__ as sim_all
__all__ = sim_all
