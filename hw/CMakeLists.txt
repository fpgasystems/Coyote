cmake_minimum_required(VERSION 3.0)
project(lynx)

#
# Vivado
#

set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CMAKE_SOURCE_DIR}/../cmake)

set(IPREPO_DIR ${CMAKE_BINARY_DIR}/iprepo)
file(MAKE_DIRECTORY ${IPREPO_DIR})

#
# Target options
#

if(FDEV_NAME STREQUAL "vcu118")
    set(FPGA_PART xcvu9p-flga2104-2L-e CACHE STRING "FPGA device.")
elseif(FDEV_NAME STREQUAL "u250")
    set(FPGA_PART xcu250-figd2104-2L-e CACHE STRING "FPGA device.")
elseif(FDEV_NAME STREQUAL "u280")
    set(FPGA_PART xcu280-fsvh2892-2L-e CACHE STRING "FPGA device.")
else()
    message(FATAL_ERROR "Target device not supported.")
endif()

#
# Domain options
#

# Number of user regions
set(N_REGIONS 1 CACHE STRING "Number of regions per channel.")

# User logic descriptors
set(EN_BPSS 0 CACHE STRING "User logic bypass descriptors.")
# AVX support
set(EN_AVX 1 CACHE STRING "AVX environment.")

# Host streams
set(EN_STRM 1 CACHE STRING "Enable streams.")

# DDR streams
set(EN_DDR 0 CACHE STRING "Enable local DDR.")
# DDR channels
set(N_DDR_CHAN 1 CACHE STRING "Channel 0.")

# Partial reconfiguration
set(EN_PR 0 CACHE STRING "Enable PR flow.")

# Enable Network stack
set(EN_TCP 0 CACHE STRING "Enable TCP.")
set(EN_RDMA 0 CACHE STRING "Enable RDMA.")
set(EN_FVV 0 CACHE STRING "Enable Farview.")

# QSFP port
set(QSFP_PORT 1 CACHE STRING "Network traffic route.")

#
# Validation checks
#

if(N_REGIONS GREATER 16)
    message(FATAL_ERROR "Max 16 regions supported.")
endif()

if(NOT EN_STRM AND NOT EN_DDR)
    message(FATAL_ERROR "Neither of the transfer options selected.")
endif()

if(FDEV_NAME STREQUAL "vcu118" OR FDEV_NAME STREQUAL "u280")
    if(N_DDR_CHAN GREATER 2)
        message(FATAL_ERROR "Maximum of 2 channels supported.")
    endif()
endif()

if(FDEV_NAME STREQUAL "u250")
    if(N_DDR_CHAN GREATER 4)
        message(FATAL_ERROR "Maximum of 4 channels supported.")
    endif()
endif()

if(EN_RDMA)
    set(EN_FV 1 CACHE BOOL "Enable Farview")
else()
    set(EN_FV 0 CACHE BOOL "Enable Farview")
endif()

if(EN_FV AND NOT EN_BPSS)
    set(EN_BPSS 1)
    if(QSFP_PORT GREATER 1)
        message(FATAL_ERROR "QSFP port doesn't exist.")
    endif()
endif()

# FPGA-network-stack
if(EN_FV EQUAL 1)
    set(ROCE_STACK_EN 1 CACHE BOOL "Enable RDMA stack.")
else()
    set(ROCE_STACK_EN 0 CACHE BOOL "Enable RDMA stack.")
endif()

if(EN_TCP EQUAL 1)
    set(TCP_STACK_EN 1 CACHE BOOL "Enable TCP stack.")
else()
    set(TCP_STACK_EN 0 CACHE BOOL "Enable TCP stack.")
endif()

set(UDP_STACK_EN 0 CACHE BOOL "Enable UDP/IP stack")

#
# Network stack
#

add_subdirectory(ext/network)

#
# Find Vivado
#

find_package(Vivado REQUIRED)
if (NOT VIVADO_FOUND)
   message(FATAL_ERROR "Vivado not found.")
endif()

#
# Configure files
#

configure_file(${CMAKE_SOURCE_DIR}/scripts/shell.tcl.in ${CMAKE_BINARY_DIR}/shell.tcl)
configure_file(${CMAKE_SOURCE_DIR}/scripts/post.tcl.in ${CMAKE_BINARY_DIR}/post.tcl)
configure_file(${CMAKE_SOURCE_DIR}/scripts/dynamic.tcl.in ${CMAKE_BINARY_DIR}/dynamic.tcl)
configure_file(${CMAKE_SOURCE_DIR}/scripts/compile.tcl.in ${CMAKE_BINARY_DIR}/compile.tcl)

add_custom_target(shell COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/shell.tcl)
add_custom_target(compile COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/compile.tcl)
add_custom_target(dynamic COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/dynamic.tcl)
