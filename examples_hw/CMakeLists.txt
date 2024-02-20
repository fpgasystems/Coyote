cmake_minimum_required(VERSION 3.0)
project(test)

set(CYT_DIR ${CMAKE_SOURCE_DIR}/../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)

find_package(CoyoteHW REQUIRED)

#
# Static
# @brief: Default shell, contains interconnect and memory link testing circuits (perf_local)
#
# @note: Add a target device (FDEV_NAME)
#
# This is what every other shell is built against
#
if(EXAMPLE STREQUAL "static")
    set(BUILD_STATIC 1)
    set(BUILD_SHELL 0)
    set(COMP_CORES 40)
    set(N_REGIONS 3)
    set(EN_STRM 1)
    set(EN_MEM 1)

    load_apps(
        VFPGA_C0_0 "perf_local"
        VFPGA_C0_1 "perf_local"
        VFPGA_C0_2 "perf_local"
    )
endif()

#
# Shells with examples
#

# Application example, two streaming examples
# @brief: Streaming interface example
# The first application is gradient boosting decision trees inference - RTL integration example
# The second one is HyperLogLog cardinality estimation - HLS integration example
#
# @note: Floorplan provided for u55c only -> add manual app floorplans for other devices
#
if(EXAMPLE STREQUAL "streaming")
    message("** Streaming examples: HyperLogLog (cardinality estimation) and GBM decision trees (inference)")
    set(SHELL_PROBE 184594741)
    set(FDEV_NAME "u55c")
    set(N_REGIONS 1)
    set(EN_STRM 1)
    set(EN_MEM 0)
    set(EN_PR 1)
    set(N_CONFIG 2)

    load_apps(
        VFPGA_C0_0 "hyperloglog"
        VFPGA_C1_0 "gbm_dtrees"
    )
endif()

if(EXAMPLE STREQUAL "hyperloglog")
    message("** Streaming examples: HyperLogLog (cardinality estimation) and GBM decision trees (inference)")
    set(SHELL_PROBE 184594741)
    set(FDEV_NAME "u55c")
    set(N_REGIONS 1)
    set(EN_STRM 1)
    set(EN_MEM 0)

    load_apps(
        VFPGA_C0_0 "hyperloglog"
    )
endif()

# Application example, KMeans algorithm
# @brief: On-board memory example
#
# @note: Add a target device (FDEV_NAME) -> depending on the device HBM or MIG DRAM will be used (interface is the same)
#
if(EXAMPLE STREQUAL "kmeans")
    message("** K-Means application example")
    set(SHELL_PROBE 2343432205)
    set(N_REGIONS 2)
    set(EN_MEM 1)
    set(N_CARD_AXI 2)

    load_apps(
        VFPGA_C0_0 "kmeans"
        VFPGA_C0_1 "kmeans"
    )
endif()

# Network example, TCP/IP
# @brief: TCP/IP iperf test
#
# @note: Add a target device (FDEV_NAME)
#
if(EXAMPLE STREQUAL "iperf_tcp")
    message("** TCP perf test")
    set(SHELL_PROBE 219540062)
    set(N_REGIONS 1)
    set(EN_TCP 1)

    load_apps(
        VFPGA_C0_0 "iperf_tcp"
    )
endif()

# Network example, RDMA
# @brief: RDMA with AES encryption example
#
# @note: Add a target device (FDEV_NAME)
#
if(EXAMPLE STREQUAL "rdma_aes")
    message("** RDMA AES-en(de)cryption test")
    set(SHELL_PROBE 3735928495)
    set(N_REGIONS 2)
    set(EN_RDMA 1)
    set(EN_MEM 1)

    load_apps(
        VFPGA_C0_0 "rdma_base"
        VFPGA_C0_1 "rdma_aes"
    )
endif()

if(EXAMPLE STREQUAL "rdma")
    message("** RDMA test")
    set(SHELL_PROBE 3735928495)
    set(N_REGIONS 1)
    set(EN_RDMA 1)

    load_apps(
        VFPGA_C0_0 "rdma"
    )
endif()

# Dynamic reconfiguration example
# @brief: Example of a Coyote service
# This shows how Coyote can effectively be used to create a library of accelerators 
# which can be loaded on demand through a background daemon
#
# @note: Add a target device (FDEV_NAME) -> depending on the device HBM or MIG DRAM will be used (interface is the same)
#
if(EXAMPLE STREQUAL "service_reconfiguration")
    message("** Service dynamic reconfiguration")
    set(SHELL_PROBE 2976579765)
    set(FDEV_NAME "u55c")
    set(N_REGIONS 2)
    set(EN_PR 1)
    set(N_CONFIG 3)
    set(EN_STRM 1)
    set(EN_MEM 0)

    load_apps(
        VFPGA_C0_0 "addmul"
        VFPGA_C0_1 "addmul"
        VFPGA_C1_0 "minmaxsum"
        VFPGA_C1_1 "minmaxsum"
        VFPGA_C2_0 "testcount"
        VFPGA_C2_1 "testcount"
    )
endif()

#
# Create build targets
#

create_hw() 
