# CMake configuration 
cmake_minimum_required(VERSION 3.5)
set(CYT_DIR ${CMAKE_SOURCE_DIR}/../../../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteHW REQUIRED)

project(example_10_host_networking_alternative)
message("*** Coyote Example 10: Host Networking Alternative [Hardware Build] ***")

# Enables one stream for host memory (no separation for requests and responses)
set(EN_STRM 1)
set(N_STRM_AXI 2)

# Include Coyote's RDMA-stack during synthesis (just to make sure that networking is included)
set(EN_RDMA 1)

# Enable host networking
set(EN_HOST_NETWORKING 1)   

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

