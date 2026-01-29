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

##############################
#       USER OPTIONS        #
#############################
# Build with AVX support
set(EN_AVX "1" CACHE STRING "AVX enabled.")

# Build with support for ROCm (AMD GPUs)
set(EN_GPU "0" CACHE STRING "AMD GPU enabled.")

##############################
#       BUILD CONFIG        #
#############################
set(CYT_LANG CXX)

# Find GPU libraries
if(EN_GPU)
    if(NOT DEFINED ROCM_PATH)
    if(DEFINED ENV{ROCM_PATH})
        set(ROCM_PATH $ENV{ROCM_PATH} CACHE PATH "Path to which ROCM has been installed")
    elseif(DEFINED ENV{HIP_PATH})
        set(ROCM_PATH "$ENV{HIP_PATH}/.." CACHE PATH "Path to which ROCM has been installed")
    else()
        set(ROCM_PATH "/opt/rocm" CACHE PATH "Path to which ROCM has been installed")
    endif()
    endif()

    file(STRINGS "${ROCM_PATH}/.info/version" ROCM_VERSION)
    message("-- Found ROCm: ${ROCM_VERSION}")

    if (NOT DEFINED CMAKE_CXX_COMPILER)
        set(CMAKE_CXX_COMPILER ${ROCM_PATH}/bin/hipcc)
    endif()

    if(NOT DEFINED HIP_PATH)
        if(NOT DEFINED ENV{HIP_PATH})
            set(HIP_PATH "/opt/rocm/hip" CACHE PATH "Path to which HIP has been installed")
        else()
            set(HIP_PATH $ENV{HIP_PATH} CACHE PATH "Path to which HIP has been installed")
        endif()
    endif()

    if(NOT DEFINED HCC_PATH)
        if(DEFINED ENV{HCC_PATH})
            set(HCC_PATH $ENV{HCC_PATH} CACHE PATH "Path to which HCC has been installed")
        else()
            set(HCC_PATH "${ROCM_PATH}/hcc" CACHE PATH "Path to which HCC has been installed")
        endif()
        set(HCC_HOME "${HCC_PATH}")
    endif()

    if(NOT DEFINED HIP_CLANG_PATH)
        if(NOT DEFINED ENV{HIP_CLANG_PATH})
            set(HIP_CLANG_PATH "${ROCM_PATH}/llvm/bin" CACHE PATH "Path to which HIP compatible clang binaries have been installed")
        else()
            set(HIP_CLANG_PATH $ENV{HIP_CLANG_PATH} CACHE PATH "Path to which HIP compatible clang binaries have been installed")
        endif()
    endif()

    set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${HIP_PATH}/cmake" )
    list(APPEND CMAKE_PREFIX_PATH
        "${HIP_PATH}/lib/cmake"
        "${HIP_PATH}/../lib/cmake"
    )

    find_package(HIP QUIET)
    if(HIP_FOUND)
        message(STATUS "Found HIP: " ${HIP_VERSION})
    else()
        message(FATAL_ERROR "Could not find HIP. Ensure that HIP is either installed in /opt/rocm/hip or the variable HIP_PATH is set to point to the right location.")
    endif()
    find_package(hip REQUIRED)

    set(CYT_LANG ${CYT_LANG} HIP)
endif()

# Create a Coyote lib
project(
    Coyote
    VERSION 2.0.0
    DESCRIPTION "Coyote library"
    LANGUAGES ${CYT_LANG}
)

# Specify C++ standard, compile time options
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED True)
add_compile_options("-march=native")

# Source files, includes
file(GLOB CYT_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp")
add_library(Coyote SHARED ${CYT_SOURCES})
target_include_directories(Coyote
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
)
set_target_properties(Coyote PROPERTIES OUTPUT_NAME "coyote")

# Additional libraries
find_package(Threads)
target_link_libraries(Coyote PRIVATE Threads::Threads)
find_package(Boost REQUIRED)
target_include_directories(Coyote PRIVATE ${Boost_INCLUDE_DIRS})

# Additional flags, depending on AVX or GPU support
if(EN_AVX)
    target_compile_definitions(Coyote PUBLIC EN_AVX)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mavx")
endif()

if(EN_GPU)
    target_compile_definitions(Coyote PUBLIC EN_GPU)

    # Include GPU directories
    target_include_directories(Coyote
            PUBLIC
                $<BUILD_INTERFACE:${ROCM_PATH}/include>
                $<BUILD_INTERFACE:${ROCM_PATH}/include/hsa>
    )

    # Add GPU libraries
    target_link_libraries(Coyote PUBLIC hip::device numa pthread drm drm_amdgpu rt dl hsa-runtime64 hsakmt)
endif()

##############################
#    INSTALATION OPTIONS    #
#############################
include(GNUInstallDirs)

# Install the library
install(TARGETS Coyote
    EXPORT CoyoteTargets
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

# Install headers
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/include/coyote/"
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/coyote
    FILES_MATCHING PATTERN "*.hpp"
)

# Export package configuration
install(EXPORT CoyoteTargets
    FILE CoyoteTargets.cmake
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/coyote
)

# Generate CMake package configuration files
include(CMakePackageConfigHelpers)
write_basic_package_version_file(
    ${CMAKE_CURRENT_BINARY_DIR}/CoyoteConfigVersion.cmake
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY AnyNewerVersion
)
