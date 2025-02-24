# CMake configuration
cmake_minimum_required(VERSION 3.5)
project(example_06_gpu_p2p)

set(CYT_DIR ${CMAKE_SOURCE_DIR}/../../../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteSW REQUIRED)

message("*** Coyote Example 6: FPGA-GPU Peer-to-Peer Data Movement [Software Build] ***")

# Directory containing the executable(s) to be compiled
set(TARGET_DIR "${CMAKE_SOURCE_DIR}/src/")

# Create build targets and link against required libraries
set(EXEC test)
add_executable(${EXEC} ${TARGET_DIR}/main.cpp)
target_link_libraries(${EXEC} PUBLIC Coyote)
target_link_directories(${EXEC} PUBLIC /usr/local/lib)

# Target GPU architecture - gfx90 corresponds to MI210 - change as needed
set(AMD_GPU "gfx90a" CACHE STRING "Target GPU platform")
set_property(TARGET ${EXEC} PROPERTY HIP_ARCHITECTURES ${AMD_GPU})
