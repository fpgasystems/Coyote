######################################################################################
# This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
#
# MIT Licence
# Copyright (c) 2026, Systems Group, ETH Zurich
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

cmake_minimum_required(VERSION 3.5)
project(example_13_denim_sw CXX)

set(TARGET_DIR "${CMAKE_SOURCE_DIR}/src")

message("*** Coyote Example 13: DENIM [Software] ***")
message("    Build this on the FPGA node itself, not on a build server.")

add_subdirectory(../../../sw ${CMAKE_BINARY_DIR}/coyote)

add_executable(denim_ctl ${TARGET_DIR}/main.cpp ${TARGET_DIR}/denim_rules.cpp)
target_include_directories(denim_ctl PRIVATE ${TARGET_DIR})
target_compile_features(denim_ctl PRIVATE cxx_std_17)
target_link_libraries(denim_ctl PUBLIC Coyote)

find_package(Boost REQUIRED COMPONENTS program_options)
target_link_libraries(denim_ctl PUBLIC Boost::program_options)
