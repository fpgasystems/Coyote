# CMake configuration
# Coyote has its own internal build system, which must be sourced when synthesizing bitstreams
# This can be done using find_package(CoyoteHW REQUIRED)
cmake_minimum_required(VERSION 3.5)
set(CYT_DIR ${CMAKE_SOURCE_DIR}/../../../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteHW REQUIRED)

project(example_01_static_local)
message("*** Coyote Example 1: Static HW Design & Data Movement Initiated by the CPU [Hardware Build] ***")

# As explained in the README.md, in this example the "static" build flow is used; esentially resynthesizing the static layer
set(BUILD_STATIC 1)
set(BUILD_SHELL 0)

# Enables Place-and-Route timing optimizations; Vivado implementation will take longer in order to meet the target clock frequency
# This option is rarely needed; but achieving timing closure with the XDMA core can be tricky so for static designs this is recommended
# For the other examples, this is not needed as the static part is provided as a pre-routed checkpoint
set(BUILD_OPT 1)

# Enables streams from host memory (CPU DDR) and card memory (FPGA HBM or DDR)
set(EN_STRM 1)
set(EN_MEM 1)

# Number of vFPGAs (user applications)
set(N_REGIONS 1)

# TODO: Add comment on what HBM_SPLIT does
set(HBM_SPLIT 1)

# Confirm that the selected options are allowed
validation_checks_hw()

# Load a user application in Configuration #0, Region #0 
# Configurations become important in partial reconfiguration (PR) covered in another example
# Region is equal to zero, since we only have one vFPGA
# The macro load_apps(...) will look for a file vfgpa_top.svh in the specified folder (in this case src/)
load_apps (
    VFPGA_C0_0 "src"
)

# Create the hardware project
create_hw()
