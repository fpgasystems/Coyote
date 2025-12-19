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

# IT IS VERY IMPORTANT THAT WE USE LITTLE-ENDIAN
BYTE_ORDER = "little"

# Note, all of the following variables are set via CMAKE
# using the script in scripts/unit_test/__init__.in.py

HW_BUILD_FOLDER = None
SIM_FOLDER = None
UNIT_TEST_FOLDER = None
MAX_NUMBER_STREAMS = None
SOURCE_FOLDERS = None
VFPGA_SOURCE_FOLDER = None
TEST_BENCH_FOLDER = None
COMPILE_CHECK_FILE = None
N_REGIONS = None
SIM_OUT_FILE = None
IO_INPUT_FILE_NAME = None
IO_OUTPUT_FILE_NAME = None
DIFF_FOLDER = None
SIM_TARGET_V_FPGA_TOP_FILE = None
SRC_V_FPGA_TOP_FILE = None
CLOCK_PERIOD = None
STREAM_ID_BITS = None
VADDR_BITS = None
VIVADO_BINARY_PATH = None
PROJECT_NAME = None