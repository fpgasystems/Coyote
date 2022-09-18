cmake_minimum_required(VERSION 3.0)
project(lynx)

##
## Vivado
##

set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CMAKE_SOURCE_DIR}/../cmake)

set(IPREPO_DIR ${CMAKE_BINARY_DIR}/iprepo)
file(MAKE_DIRECTORY ${IPREPO_DIR})

##
## Target devices
##

if(FDEV_NAME STREQUAL "vcu118")
    set(FPGA_PART xcvu9p-flga2104-2L-e CACHE STRING "FPGA device.")
    set(DDR_SIZE 32)
    set(HBM_SIZE 0)
elseif(FDEV_NAME STREQUAL "u50")
    set(FPGA_PART xcu50-fsvh2104-2-e CACHE STRING "FPGA device.")
    set(DDR_SIZE 0)
    set(HBM_SIZE 33)
elseif(FDEV_NAME STREQUAL "u55c") # TODO: New Vivado version might be necessary
    set(FPGA_PART xcu55c-fsvh2892-2L-e CACHE STRING "FPGA device.")
    set(DDR_SIZE 0)
    set(HBM_SIZE 34)
elseif(FDEV_NAME STREQUAL "u200")
    set(FPGA_PART xcu200-fsgd2104-2-e CACHE STRING "FPGA device.")
    set(DDR_SIZE 34)
    set(HBM_SIZE 0)
elseif(FDEV_NAME STREQUAL "u250")
    set(FPGA_PART xcu250-figd2104-2L-e CACHE STRING "FPGA device.")
    set(DDR_SIZE 34)
    set(HBM_SIZE 0)
elseif(FDEV_NAME STREQUAL "u280")
    set(FPGA_PART xcu280-fsvh2892-2L-e CACHE STRING "FPGA device.")
    set(DDR_SIZE 34)
    set(HBM_SIZE 33)
elseif(FDEV_NAME STREQUAL "enzian")
    set(FPGA_PART xcvu9p-flgb2104-3-e CACHE STRING "FPGA device.")
    set(DDR_SIZE 37)
else()
    message(FATAL_ERROR "Target device not supported.")
endif()

message("** Target platform ${FDEV_NAME}")

set(FPGA_FAMILY ultraplus CACHE STRING "FPGA family.")
set(DATA_WIDTH 64 CACHE STRING "Data width")
set(CLOCK_PERIOD 3.2 CACHE STRING "Clock period.")

##
## DDR and HBM support
## ! u280 has both DDR and HBM, HBM enabled by def, if DDR is required add u280 in DDR_DEV and remove it from HBM_DEV
##
set(DDR_DEV "vcu118" "u200" "u250" "enzian")
set(HBM_DEV "u280" "u50" "u55c")

list(FIND DDR_DEV ${FDEV_NAME} TMP_DEV)
if(NOT TMP_DEV EQUAL -1)
    set(AV_DDR 1)
else()
    set(AV_DDR 0)
endif()

list(FIND HBM_DEV ${FDEV_NAME} TMP_DEV)
if(NOT TMP_DEV EQUAL -1)
    set(AV_HBM 1)
else()
    set(AV_HBM 0)
endif()

##
## Domain options
##

# HLS wrappers
set(EN_HLS 0 CACHE STRING "Enable HLS generation.")

# Number of user regions
set(N_REGIONS 1 CACHE STRING "Number of regions per channel.")

# User logic descriptors
set(EN_BPSS 0 CACHE STRING "User logic bypass descriptors.")

# AVX support
set(EN_AVX 1 CACHE STRING "AVX environment.")

# Fast DMA TLB mapping
set(EN_TLBF 0 CACHE STRING "Enable fast TLB DMA.")

# Writeback support
set(EN_WB 0 CACHE STRING "Enable writeback.")

# Host streams
set(EN_STRM 1 CACHE STRING "Enable host streams.")

# Memory streams
set(EN_MEM 0 CACHE STRING "Enable memory streams.")

# HBM split
set(HBM_SPLIT 0 CACHE STRING "HBM bank splitting.")

# Memory channels
set(N_DDR_CHAN 0 CACHE STRING "Number of DDR channels.")

# Stripe fragment
set(DDR_FRAG 1024 CACHE STRING "Stripe fragment size.")

# Manual DDR location
set(DDR_AUTO 1 CACHE STRING "Automatic placement of DDRs.")

# Partial reconfiguration
set(EN_PR 0 CACHE STRING "Enable PR flow.")

# Number of PR configurations to be supported for deployment
set(N_CONFIG 1 CACHE STRING "Number of PR configurations (for each region).")

# Number of supported outstanding transactions
set(N_OUTSTANDING 8 CACHE STRING "Number of supported outstanding transactions")

# Enable RDMA stack
set(EN_RDMA_0 0 CACHE STRING "Enable RDMA stack on QSFP 0.")
set(EN_RDMA_1 0 CACHE STRING "Enable RDMA stack on QSFP 1.")

# Enable RPC (IBV SEND)
set(EN_RPC 0 CACHE STRING "Enable RPC receive queueing.")

# Enable TCP/IP stack
set(EN_TCP_0 0 CACHE STRING "Enable TCP/IP stack on QSFP 0.")

set(EN_TCP_1 0 CACHE STRING "Enable TCP/IP stack on QSFP 1.")

set(TCP_RX_BPSS 1 CACHE BOOL "Enabling DDR bypass on the RX path")

# 1 credit packet size
set(PMTU_BYTES 4096 CACHE STRING "PMTU size.")

# Compilation number of cores
set(COMP_CORES 8 CACHE STRING "Number of compilation cores.")

# Probing ID
set(PROBE_ID 219540062 CACHE STRING "Probe ID.")

# Clock enable
set(EN_ACLK 1 CACHE STRING "System clock crossing (250 MHz by default).")
set(EN_NCLK 1 CACHE STRING "Network clock crossing (250 MHz by default).")
set(EN_UCLK 0 CACHE STRING "User clock crossing (300 MHz by default).")

# Clock frequencies
set(ACLK_F 300 CACHE STRING "System clock frequency.")
set(NCLK_F 250 CACHE STRING "Network clock frequency.")
set(UCLK_F 300 CACHE STRING "User clock frequency.")
set(HCLK_F 450 CACHE STRING "HBM clock frequency.")

# Examples
set(EXAMPLE 0 CACHE STRING "Chosen example.")

# TLB params
set(TLBS_S 10 CACHE STRING "TLB (small) size")
set(TLBS_A 4 CACHE STRING "TLB (small) associativity")
set(TLBL_S 9 CACHE STRING "TLB (huge) size")
set(TLBL_A 2 CACHE STRING "TLB (huge) associativity")
set(TLBS_BITS 12 CACHE STRING "TLB (small) page order")
set(TLBL_BITS 21 CACHE STRING "TLB (huge) page order")

# TLB eviction
set(EN_NRU 0 CACHE STRING "Enable NRU eviction policy")

##
## Examples
##
include(${CMAKE_SOURCE_DIR}/examples.cmake)

##
## Quick validation checks
##

## General

# Max supported regions (could be more if really needed with a bit of hacking)
if(N_REGIONS GREATER 15)
    message(FATAL_ERROR "Max 15 regions supported.")
endif()

# Number of configurations needs to be 1 without PR
if(N_CONFIG GREATER 1 AND NOT EN_PR)
    message(FATAL_ERROR "When PR is not enabled only one configuration of the system should exist.")
endif()

##
## Network
##

# RDMA Bypass
if(EN_RDMA_0 OR EN_RDMA_1)
    set(EN_BPSS 1)
endif()

# RDMA stack
if(EN_RDMA_0 OR EN_RDMA_1)
    set(ROCE_STACK_EN 1 CACHE BOOL "RDMA stack disabled.")
    set(EN_RDMA 1)
else()
    set(ROCE_STACK_EN 0 CACHE BOOL "RDMA stack disabled.")
    set(EN_RDMA 0)
endif()

# TCP stack (also set appropriate memory config)
set(N_TCP_CHAN 0)
set(EN_DCARD 0)
set(EN_HCARD 0)
if(EN_TCP_0 OR EN_TCP_1)
    if(AV_DDR)
        if(EN_TCP_0 AND EN_TCP_1)
            set(N_TCP_CHAN 2)
        else()
            set(N_TCP_CHAN 1)
        endif()

        # Mem
        set(EN_DCARD 1)
        set(EN_HCARD 0)

        if(N_DDR_CHAN EQUAL 0)
            set(N_DDR_CHAN 1)
        endif()
    elseif(AV_HBM)
        if(EN_TCP_0 AND EN_TCP_1)
            set(N_TCP_CHAN 2)
        else()
            set(N_TCP_CHAN 1)
        endif()

        # Mem
        set(EN_DCARD 0)
        set(EN_HCARD 1)
    endif()

    # Stack
    set(TCP_STACK_EN 1 CACHE BOOL "Enable TCP/IP stack")
    set(EN_TCP 1)
else()
    # Mem
    if(EN_MEM)
        if(AV_DDR)
            set(EN_DCARD 1)
            set(EN_HCARD 0)
        elseif(AV_HBM)
            set(EN_DCARD 0)
            set(EN_HCARD 1)
        endif()
    endif()

    # Stack
    set(TCP_STACK_EN 0 CACHE BOOL "Enable TCP/IP stack")
    set(EN_TCP 0)
endif()

# Simple UDP stack not supported
set(UDP_STACK_EN 0 CACHE BOOL "Enable UDP/IP stack")

# Rest of network flags
if(EN_RDMA_0 OR EN_RDMA_1)
    set(EN_RDMA 1)
else()
    set(EN_RDMA 0)
endif()

if(EN_TCP_0 OR EN_TCP_1)
    set(EN_TCP 1)
else()
    set(EN_TCP 0)
endif()

if(EN_RDMA_0 OR EN_TCP_0)
    set(EN_NET_0 1)
else()
    set(EN_NET_0 0)
endif()

if(EN_RDMA_1 OR EN_TCP_1)
    set(EN_NET_1 1)
else()
    set(EN_NET_1 0)
endif()

if(EN_NET_0 OR EN_NET_1)
    set(EN_NET 1)
else()
    set(EN_NET 0)
endif()

##
## Memory
##

# Total AXI memory channels
if(EN_HCARD OR EN_DCARD)
    set(EN_CARD 1)
else()
    set(EN_CARD 0)
endif()

# Total mem AXI channels
set(N_MEM_CHAN 0)
if(EN_MEM)
    MATH(EXPR N_MEM_CHAN "${N_REGIONS} + 1 + ${N_MEM_CHAN}")
endif()
if(EN_TCP)
    MATH(EXPR N_MEM_CHAN "${N_TCP_CHAN} + ${N_MEM_CHAN}")
endif()

# Most boards only up to 4
if(N_DDR_CHAN GREATER 4)
    message(FATAL_ERROR "Too many memory channels present.")
endif()

# Setup channels
set(DDR_0 0) # Bottom SLR (TODO: Check this stuff, might be completely different)
set(DDR_1 0) # Mid SLRs
set(DDR_2 0) # Mid SLRs
set(DDR_3 0) # Top SLR

if(DDR_AUTO)
    if(EN_DCARD)
        if(N_DDR_CHAN GREATER 0)
            set(DDR_0 1)
        endif()
        if(N_DDR_CHAN GREATER 1)
            set(DDR_1 1)
        endif()
        if(N_DDR_CHAN GREATER 2)
            set(DDR_2 1)
            set(DDR_3 1)
        endif()
    endif()
endif()

# Compare for mismatch
MATH(EXPR N_DDRS "${DDR_0}+${DDR_1}+${DDR_2}+${DDR_3}")
if(NOT N_DDRS EQUAL ${N_DDR_CHAN})
    message(FATAL_ERROR "DDRs have not been configured properly.")
endif()

##
## Enzian
##

# Enzian currently doesn't support any form of AVX
if(FDEV_NAME STREQUAL "enzian")
    if(EN_AVX)
        message("AVX instructions not supported on the Enzian platform currently. Force disable.")
        set(EN_AVX 0)
    endif()
    if(EN_NET)
        set(POLARITY_INV 1)
    endif()
endif()

# Polarity inversion on Enzian (TODO: is it really needed?)
if(FDEV_NAME STREQUAL "enzian")
    set(POL_INV 1)
else()
    set(POL_INV 0)
endif()

##
## Network stack subdirectory (services)
##

if(EN_RDMA OR EN_TCP)
	add_subdirectory(services/network)
endif()

##
## Rest of parameters
##

# Utility channel
if(EN_WB OR EN_TLBF)
    set(EN_UC 1)
else()
    set(EN_UC 0)
endif()

# Total XDMA channels
set(N_CHAN 0)
if(EN_STRM)
    MATH(EXPR N_CHAN "${N_CHAN}+1")
endif()
if(EN_MEM)
    MATH(EXPR N_CHAN "${N_CHAN}+1")
endif()
if(EN_PR)
    MATH(EXPR N_CHAN "${N_CHAN}+1")
endif()
if(EN_UC)
    MATH(EXPR N_CHAN "${N_CHAN}+1")
endif()

# Channel designators
set(NN 0)
if(EN_STRM)
    set(STRM_CHAN ${NN})
    MATH(EXPR NN "${NN}+1")
else()
    set(STRM_CHAN -1)
endif()
if(EN_MEM)
    set(DDR_CHAN ${NN})
    MATH(EXPR NN "${NN}+1")
else()
    set(DDR_CHAN -1)
endif()
if(EN_PR)
    set(PR_CHAN ${NN})
    MATH(EXPR NN "${NN}+1")
else()
    set(PR_CHAN -1)
endif()
if(EN_UC)
    set(UC_CHAN ${NN})
    MATH(EXPR NN "${NN}+1")
else()
    set(UC_CHAN -1)
endif()

#
# Find Vivado
#

find_package(Vivado REQUIRED)
if (NOT VIVADO_FOUND)
   message(FATAL_ERROR "Vivado not found.")
endif()

find_package(VivadoHLS REQUIRED)
if (NOT VIVADO_HLS_FOUND)
  message(FATAL_ERROR "Vivado HLS not found.")
endif()

if(VITIS_HLS) 
  message("** Vitis HLS flow")
else()
  message("** Vivado HLS flow")
endif()

#
# Configure files
#

configure_file(${CMAKE_SOURCE_DIR}/scripts/wr_hdl/write_hdl.py.in ${CMAKE_BINARY_DIR}/write_hdl.py)
configure_file(${CMAKE_SOURCE_DIR}/scripts/config.tcl.in ${CMAKE_BINARY_DIR}/config.tcl)
configure_file(${CMAKE_SOURCE_DIR}/scripts/base.tcl.in ${CMAKE_BINARY_DIR}/base.tcl)
configure_file(${CMAKE_SOURCE_DIR}/scripts/shell.tcl.in ${CMAKE_BINARY_DIR}/shell.tcl)
configure_file(${CMAKE_SOURCE_DIR}/scripts/post.tcl.in ${CMAKE_BINARY_DIR}/post.tcl)
configure_file(${CMAKE_SOURCE_DIR}/scripts/dynamic.tcl.in ${CMAKE_BINARY_DIR}/dynamic.tcl)
configure_file(${CMAKE_SOURCE_DIR}/scripts/compile.tcl.in ${CMAKE_BINARY_DIR}/compile.tcl)
configure_file(${CMAKE_SOURCE_DIR}/scripts/comphls.tcl.in ${CMAKE_BINARY_DIR}/comphls.tcl)
configure_file(${CMAKE_SOURCE_DIR}/scripts/importhls.tcl.in ${CMAKE_BINARY_DIR}/importhls.tcl)
configure_file(${CMAKE_SOURCE_DIR}/scripts/example.tcl.in ${CMAKE_BINARY_DIR}/example.tcl)
configure_file(${CMAKE_SOURCE_DIR}/scripts/sim.tcl.in ${CMAKE_BINARY_DIR}/sim.tcl)

#
# Base
#

if(EN_NET)
    set(NET_CMD COMMAND make services)
endif()
if(EN_HLS)
    set(HLS_CMD COMMAND ${VIVADO_HLS_BINARY} -f comphls.tcl -tclargs ${target} COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/importhls.tcl -notrace)
endif()

add_custom_target(dynamic COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/dynamic.tcl -notrace)
add_custom_target(sim COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/sim.tcl -notrace)
add_custom_target(hls_only ${HLS_CMD})
add_custom_target(net_only ${NET_CMD})
add_custom_target(shell_only COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/shell.tcl -notrace)

add_custom_target(shell ${NET_CMD} COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/shell.tcl -notrace)

add_custom_target(compile ${HLS_CMD} COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/compile.tcl -notrace)
