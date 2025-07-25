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

# Helper script, determines whether Vivado is available in the system
cmake_minimum_required(VERSION 3.5)

find_path(VIVADO_PATH
  NAMES vivado 
  PATHS ${VIVADO_ROOT_DIR} ENV XILINX_VIVADO
  PATH_SUFFIXES bin
)

if(NOT EXISTS ${VIVADO_PATH})
  message(WARNING "Vivado not found.")
else()
  get_filename_component(VIVADO_ROOT_DIR ${VIVADO_PATH} DIRECTORY)
  set(VIVADO_FOUND TRUE)
  set(VIVADO_BINARY ${VIVADO_ROOT_DIR}/bin/vivado)
  set(XSC_BINARY ${VIVADO_ROOT_DIR}/bin/xsc)
  message(STATUS "Found Vivado at ${VIVADO_ROOT_DIR}.")
endif()
