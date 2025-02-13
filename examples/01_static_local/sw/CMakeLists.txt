# CMake configuration
# Coyote has its own internal build system, which must be sourced when compiling software
# This can be done using find_package(CoyoteSW REQUIRED)
cmake_minimum_required(VERSION 3.5)
set(CYT_DIR ${CMAKE_SOURCE_DIR}/../../../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteSW REQUIRED)

project(example_01_static_local)
message("*** Coyote Example 1: Static HW Design & Data Movement Initiated by the CPU [Software Build] ***")

# Directory containing the executable(s) to be compiled
set(TARGET_DIR "${CMAKE_SOURCE_DIR}/src/")

# Create build targets and link against required libraries
set(EXEC test)
add_executable(${EXEC} ${TARGET_DIR}/main.cpp)
target_link_libraries(${EXEC} PUBLIC Coyote)
target_link_directories(${EXEC} PUBLIC /usr/local/lib)
