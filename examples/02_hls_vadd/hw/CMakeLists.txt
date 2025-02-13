# CMake configuration
cmake_minimum_required(VERSION 3.5)
set(CYT_DIR ${CMAKE_SOURCE_DIR}/../../../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteHW REQUIRED)

project(example_02_hls_vadd)
message("*** Coyote Example 2: HLS Vector Add [Hardware Build] ***")

# Enables two streams from host memory (CPU DDR)
set(EN_STRM 1)
set(N_STRM_AXI 2)

# Disable card memory for this example
set(EN_MEM 0)

# Number of vFPGAs (user applications)
set(N_REGIONS 1)

# Confirm that the selected options are allowed
validation_checks_hw()

# Load a user application in Configuration #0, Region #0
load_apps (
    VFPGA_C0_0 "src"
)

# Create the hardware project
create_hw()
