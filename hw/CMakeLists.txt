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
## Custom scripts
## 
set(SHL_SCR_PATH 0 CACHE STRING "Custom shell script path.")
set(SIM_SCR_PATH 0 CACHE STRING "Custom sim script path.")

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

# Number of host streams
set(N_STRM_AXI 1 CACHE STRING "Number of host streams.")

# Memory streams
set(EN_MEM 0 CACHE STRING "Enable memory streams.")

# Number of Memory streams
set(N_CARD_AXI 1 CACHE STRING "Number of memory streams.")

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
set(EN_NRU 0 CACHE STRING "Enable NRU eviction policy.")

# Enable statistics
set(EN_STATS 1 CACHE STRING "Enable sysfs statistics.")

# Net dropper
set(NET_DROP 0 CACHE STRING "Network dropper.")

# Reg stages
set(NR_DH_S0 4 CACHE STRING "Dynamic host stage 0.")
set(NR_DH_S1 3 CACHE STRING "Dynamic host stage 1.")
set(NR_DH_S2 3 CACHE STRING "Dynamic host stage 2.")
set(NR_DC_S0 4 CACHE STRING "Dynamic card stage 0.")
set(NR_DC_S1 3 CACHE STRING "Dynamic card stage 1.")
set(NR_DC_S2 3 CACHE STRING "Dynamic card stage 2.")
set(NR_DN_S0 4 CACHE STRING "Dynamic net stage 0.")
set(NR_DN_S1 3 CACHE STRING "Dynamic net stage 1.")
set(NR_DN_S2 4 CACHE STRING "Dynamic net stage 2.")
set(NR_N_S0 4 CACHE STRING "net stage 0.")
set(NR_N_S1 3 CACHE STRING "net stage 1.")
set(NR_N_S2 4 CACHE STRING "net stage 2.")
set(NR_CC 4 CACHE STRING "Static dynamic cc.")
set(NR_E_S0 3 CACHE STRING "eci stage 0.")
set(NR_E_S1 2 CACHE STRING "eci stage 1.")
set(NR_DD 4 CACHE STRING "Dynamic reg.")
set(NR_PR 4 CACHE STRING "PR reg.")
set(NR_NST 4 CACHE STRING "Net stats.")
set(NR_XST 4 CACHE STRING "XDMA stats.")

# EOS time
set(EOS_TIME 1000000 CACHE STRING "End of startup time.")

##
## Examples
##
include(${CMAKE_SOURCE_DIR}/examples.cmake)

##
## Config
##
include(${CMAKE_SOURCE_DIR}/config.cmake)

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