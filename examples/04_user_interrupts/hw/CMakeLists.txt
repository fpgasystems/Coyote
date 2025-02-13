# CMake configuration
cmake_minimum_required(VERSION 3.5)
set(CYT_DIR ${CMAKE_SOURCE_DIR}/../../../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteHW REQUIRED)

project(example_04_user_interrupts)
message("*** Coyote Example 4: User Interrupts [Hardware Build] ***")

# Enables host memory stream
set(EN_STRM 1)

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
