######################################################################################
# This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
#
# MIT Licence
# Copyright (c) 2025, Systems Group, ETH Zurich
# All rights reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
######################################################################################

# CMake configuration
cmake_minimum_required(VERSION 3.5)
project(example_06_gpu_p2p)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

option(EN_SIM "Enable simulation mode for Coyote" OFF)

# GPU backend selection: pass -DEN_ROCM=1 for AMD GPUs or -DEN_CUDA=1 for NVIDIA GPUs
if(EN_ROCM AND EN_CUDA)
    message(FATAL_ERROR "EN_ROCM and EN_CUDA cannot both be enabled at the same time. Please choose one.")
endif()

if(NOT EN_ROCM AND NOT EN_CUDA)
    message(FATAL_ERROR "This example requires GPU support. Configure with -DEN_ROCM=1 (AMD) or -DEN_CUDA=1 (NVIDIA).")
endif()

if(EN_SIM)
    add_subdirectory(../../../sim/sw ${CMAKE_BINARY_DIR}/coyote)
else()
    add_subdirectory(../../../sw ${CMAKE_BINARY_DIR}/coyote)
endif()

message("*** Coyote Example 6: FPGA-GPU Peer-to-Peer Data Movement [Software] ***")

set(EXEC test)

if(EN_ROCM)
    message(STATUS "Building with ROCm (AMD GPU) backend: src/rocm/main.cpp")
    add_executable(${EXEC} ${CMAKE_SOURCE_DIR}/src/rocm/main.cpp)
elseif(EN_CUDA)
    message(STATUS "Building with CUDA (NVIDIA GPU) backend: src/cuda/main.cpp")
    add_executable(${EXEC} ${CMAKE_SOURCE_DIR}/src/cuda/main.cpp)
endif()

target_link_libraries(${EXEC} PUBLIC Coyote)

find_package(Boost REQUIRED COMPONENTS program_options)
target_link_libraries(${EXEC} PUBLIC Boost::program_options)
