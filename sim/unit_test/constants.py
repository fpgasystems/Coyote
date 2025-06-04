import os.path

# IT IS VERY IMPORTANT THAT WE USE LITTLE-ENDIAN
BYTE_ORDER = "little"

# Note, all of the following variables are set via CMAKE
# using the script in scripts/unit_test/__init__.in.py

HW_BUILD_FOLDER = None
SIM_FOLDER = None
UNIT_TEST_FOLDER = None
MAX_NUMBER_STREAMS = None
SOURCE_FOLDER = None
TEST_BENCH_FOLDER = None
COMPILE_CHECK_FILE = None
N_REGIONS = None
SIM_OUT_FILE = None
IO_INPUT_FILE_NAME = None
IO_OUTPUT_FILE_NAME = None
DIFF_FOLDER = None
SIM_TARGET_V_FPGA_TOP_FILE = None
SRC_V_FPGA_TOP_FILE = None
# TODO: Define CMAKE constant and replace also in lynx template
CLOCK_PERIOD = None