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

# List of c files to compile and link for the testbench
set(DPI_FILES
    file_io.c
)

set(WORKING_DIR "${CMAKE_BINARY_DIR}/sim")

# First, make sure the directory exists!
add_custom_target(sim_dpi_dir
    COMMAND ${CMAKE_COMMAND} -E make_directory ${WORKING_DIR}
)

# Then do the compilation

# Prefix each file with current source directory
list(TRANSFORM DPI_FILES PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/")

# Convert to space-separated string
string(JOIN " " FILES_STRING ${DPI_FILES})

add_custom_target(sim_dpi_c   
    COMMAND ${XSC_BINARY} --compile ${FILES_STRING}
    COMMAND ${XSC_BINARY} --shared --output ${SIM_DPI_LIB_NAME}
    WORKING_DIRECTORY ${WORKING_DIR}
)
add_dependencies(sim_dpi_c sim_dpi_dir)