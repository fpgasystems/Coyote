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

############################################
#        COYOTE SOFTWARE PACKAGE           #
############################################
# @brief Set-up all the necessary libs, includes and source file compile the Coyote software

cmake_minimum_required(VERSION 3.5)

# Create a Coyote simulation lib
project(
    Coyote
    VERSION 2.0.0
    DESCRIPTION "Coyote simulation library"
)

# Specify C++ standard, compile time options
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED True)
add_compile_options("-march=native")

set(CYT_SW_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../sw")

# Source files, includes
file(GLOB CYT_SOURCES CONFIGURE_DEPENDS "${CYT_SW_DIR}/src/*.cpp")
file(GLOB CYT_SIM_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp")
list(FILTER CYT_SOURCES EXCLUDE REGEX ".*cThread\\.cpp$")
list(APPEND CYT_SOURCES ${CYT_SIM_SOURCES})

add_library(Coyote SHARED ${CYT_SOURCES})
target_include_directories(Coyote
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<BUILD_INTERFACE:${CYT_SW_DIR}/include>
        $<INSTALL_INTERFACE:include/coyotesim>
)
set_target_properties(Coyote PROPERTIES OUTPUT_NAME "coyotesim")

# Additional libraries
find_package(Threads)
target_link_libraries(Coyote PRIVATE Threads::Threads util)
find_package(Boost REQUIRED)
target_include_directories(Coyote PRIVATE ${BOOST_INCLUDE_DIRS})

##############################
#    INSTALATION OPTIONS    #
#############################
include(GNUInstallDirs)

# Install the library
install(TARGETS Coyote
    EXPORT CoyoteSimulationTargets
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

# Install headers
install(DIRECTORY "${CYT_SW_DIR}/include/coyote/"
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/coyotesim/coyote
    FILES_MATCHING PATTERN "*.hpp"
)
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/include/coyote/"
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/coyotesim/coyote
    FILES_MATCHING PATTERN "*.hpp"
)

# Export package configuration
install(EXPORT CoyoteSimulationTargets
    FILE CoyoteSimulationTargets.cmake
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/coyotesim
)

# Generate CMake package configuration files
include(CMakePackageConfigHelpers)
write_basic_package_version_file(
    ${CMAKE_CURRENT_BINARY_DIR}/CoyoteSimulationConfigVersion.cmake
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY AnyNewerVersion
)
