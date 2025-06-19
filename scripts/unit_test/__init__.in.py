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
constants.SOURCE_FOLDER = '${APPS_VFPGA_C0_0}'
constants.N_REGIONS = int('${N_REGIONS}')
constants.CLOCK_PERIOD = "${SIM_CLOCK_PERIOD}"
constants.STREAM_ID_BITS = int("${DATA_DEST_BITS}")
constants.VADDR_BITS = int("${VADDR_BITS}")


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
constants.SRC_V_FPGA_TOP_FILE = os.path.join(constants.SOURCE_FOLDER, "vfpga_top.svh")

# Re-export all definitions from the actual unit-test module
from unit_test import *
from unit_test import __all__ as sim_all
__all__ = sim_all
