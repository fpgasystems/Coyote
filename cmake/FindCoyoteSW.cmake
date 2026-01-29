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

message(WARNING "FindCoyoteSW is deprecated. Instead, you can choose one of two options:\n"
  "1. If you're including Coyote as a git submodule, you can use the add_subdirectory(...)"
  " directive in CMake. As an example, the following snippet of FindCoyoteSW:\n"
  "     set(CYT_DIR \$\{CMAKE_SOURCE_DIR\}/../coyote)\n"
  "     set(CMAKE_MODULE_PATH \$\{CMAKE_MODULE_PATH\} \$\{CYT_DIR\}/cmake)\n"
  "     find_package(CoyoteSW REQUIRED)\n"
  "can be replaced with:\n"
  "     add_subdirectory(../coyote/sw coyote)\n"
  "Please refer to the add_subdirectory documentation for more details.\n"
  "2. If you're integrating Coyote into third-party software, it's likely that dependencies"
  " are managed out-of-tree, and thus submodules are not used. In that case, you can install"
  " coyote as a system library (by building the CMake project in sw/ and running `make install`)"
  " and use CMake's find_package functionality as follows:"
  "\n"
  "       find_package(Coyote REQUIRED)\n"
  "In both cases, you can then link Coyote into your project using:"
  "\n"
  "       target_link_libraries(<project> PRIVATE Coyote)\n"
  "       target_include_directories(<project> PRIVATE \$\{COYOTE_INCLUDE_DIRS\})\n"
)

add_subdirectory(${CYT_DIR}/sw)
