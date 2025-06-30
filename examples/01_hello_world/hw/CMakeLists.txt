# CMake configuration
# Coyote has its own internal build system, which must be sourced when synthesizing bitstreams
# This can be done using find_package(CoyoteHW REQUIRED)
cmake_minimum_required(VERSION 3.5)
set(CYT_DIR ${CMAKE_SOURCE_DIR}/../../../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteHW REQUIRED)

project(example_01_hello_world)
message("*** Coyote Example 1: Hello World! [Hardware] ***")

# Enables streams from host memory (CPU DDR) and card memory (FPGA HBM or DDR)
set(EN_STRM 1)
set(EN_MEM 1)
set(HBM_SPLIT 1)

# Number of vFPGAs (user applications)
set(N_REGIONS 1)

# Confirm that the selected options are allowed
validation_checks_hw()

# Load a user application in Configuration #0, Region #0 
# Configurations become important in partial reconfiguration (PR) flows, covered in example Example 10
# Region is equal to zero, since we only have one vFPGA
# The macro load_apps(...) will look for a file vfgpa_top.svh in the specified folder (in this case src/)
load_apps (
    VFPGA_C0_0 "src"
)

# Create the hardware project
create_hw()
