# CMake configuration
cmake_minimum_required(VERSION 3.5)
set(CYT_DIR ${CMAKE_SOURCE_DIR}/../../../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteHW REQUIRED)

project(example_03_multitenancy)
message("*** Coyote Example 3: Multiple, Parallel AES Encryption Blocks [Hardware] ***")

# Number of vFPGAs (parallel user applications)
set(N_REGIONS 4)

# Enables host memory streams
set(EN_STRM 1)

# Build with optimizations for easier timing closure
set(BUILD_OPT 1)

# Confirm that the selected options are allowed
validation_checks_hw()

# Loads the four user applications (more on the meaning of C0 in Example 10)
# src corresponds to the folder which includes the vfpga_top.svh file and the RTL/HLS kernel
# There is absolutely no requirement that the individual applications point to different source folders.
load_apps (
    VFPGA_C0_0 "src"
    VFPGA_C0_1 "src"
    VFPGA_C0_2 "src"
    VFPGA_C0_3 "src"
)

# Create the hardware project
create_hw()
