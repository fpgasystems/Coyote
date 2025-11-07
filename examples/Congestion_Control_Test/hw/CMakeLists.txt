# CMake configuration
cmake_minimum_required(VERSION 3.5)
set(CYT_DIR ${CMAKE_SOURCE_DIR}/../../../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteHW REQUIRED)

project(example_08_perf_rdma)
message("*** Coyote Example 8: Remote Direct Memory Access (RDMA) [Hardware Build] ***")

# Enables two streams from host memory (1 for requests, 1 for response)
set(EN_STRM 1)
set(N_STRM_AXI 2)

# Incldue Coyote's RDMA stack during synthesis
set(EN_RDMA 1)

# Number of vFPGAs (user applications)
set(N_REGIONS 1)

# Build with optimization, since timing closure with RDMA can be difficult
set(BUILD_OPT 1)

# Confirm that the selected options are allowed
validation_checks_hw()

# Load a user application in Configuration #0, Region #0
load_apps (
    VFPGA_C0_0 "src"
)

# Create the hardware project
create_hw()
