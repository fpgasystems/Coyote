cmake_minimum_required(VERSION 3.0)
project(test)

set(CYT_DIR ${CMAKE_SOURCE_DIR}/../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)

find_package(CoyoteHW REQUIRED)

#
# TEST
#

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
    set(BUILD_OPT 1)
    set(N_REGIONS 4)
    set(EN_STRM 1)
    set(EN_MEM 1)
    set(HBM_SPLIT 1)

    validation_checks_hw()

    load_apps (
        VFPGA_C0_0 "apps/perf_local"
        VFPGA_C0_1 "apps/perf_local"
        VFPGA_C0_2 "apps/perf_local"
        VFPGA_C0_3 "apps/perf_local"
    )

    create_hw()
endif()

#
# Shells with examples
#

# Application examples, streaming examples
# @brief: Streaming interface example
# The first application is gradient boosting decision trees inference - RTL integration example
# The second one is HyperLogLog cardinality estimation - HLS integration example
#
# @note: Floorplan provided for u55c only -> add manual app floorplans for other devices
#
if(EXAMPLE STREQUAL "streaming")
    message("** Streaming examples: HyperLogLog (cardinality estimation), GBM decision trees (inference) and AES CBC mode")
    set(SHELL_PROBE 1)
    set(FDEV_NAME "u55c")
    set(N_REGIONS 1)
    set(EN_STRM 1)
    set(EN_MEM 0)
    set(EN_PR 1)
    set(N_CONFIG 2)
    set(FPLAN_PATH "${CMAKE_SOURCE_DIR}/floorplans/streaming_fplan_u55c.xdc")

    validation_checks_hw()

    load_apps (
        VFPGA_C0_0 "apps/hyperloglog"    
        VFPGA_C1_0 "apps/gbm_dtrees"    
    )

    create_hw()
endif()

# @brief Shell add app
# This is an example how a previous shell can be extended with additional application on the fly
# This means you don't have to recompile the whole shell, just this new apps will additionally compiled
#
# @note: Need to provide a path to the existing shell build dir ($SHELL_PATH)
#
if(EXAMPLE STREQUAL "streaming_add_aes")
    message("** Streaming examples: Add AES to the previous two apps (app build flow)")
    set(BUILD_APP 1)
    set(BUILD_SHELL 0)
    set(N_CONFIG 1)

    validation_checks_hw()

    load_apps (
        VFPGA_C0_0 "apps/aes_ecb"    
    )

    create_hw()
endif()

# @brief: AES encryption multithreading
# Running multiple threads within one vFPGA
#
#
if(EXAMPLE STREQUAL "multithreading")
    message("** Streaming examples: Multithreading AES CBC")
    set(SHELL_PROBE 2)
    set(FDEV_NAME "u55c")
    set(N_REGIONS 1)
    set(EN_STRM 1)
    set(N_STRM_AXI 8)
    set(EN_MEM 0)
    set(EN_PR 0)

    validation_checks_hw()

    load_apps (
        VFPGA_C0_0 "apps/aes_cbc"
    )

    create_hw()
endif()

# Application example, KMeans algorithm
# @brief: On-board memory example
#
# @note: Add a target device (FDEV_NAME) -> depending on the device HBM or MIG DRAM will be used (interface is the same)
#
if(EXAMPLE STREQUAL "kmeans")
    message("** K-Means application example")
    set(SHELL_PROBE 3)
    set(N_REGIONS 2)
    set(EN_MEM 1)
    set(N_CARD_AXI 2)

    validation_checks_hw()

    load_apps (
        VFPGA_C0_0 "apps/kmeans"
        VFPGA_C0_1 "apps/kmeans"
    )

    create_hw()
endif()

# GPU example
# @brief: GPU perf test
#
# @note: Add a target device (FDEV_NAME)
#
if(EXAMPLE STREQUAL "perf_gpu")
    message("** GPU perf example")
    set(SHELL_PROBE 4)
    set(N_REGIONS 1)
    set(EN_MEM 1)
    set(N_CARD_AXI 2)

    validation_checks_hw()

    load_apps (
        VFPGA_C0_0 "apps/kmeans"
        VFPGA_C0_1 "apps/kmeans"
    )

    create_hw()
endif()

# Network example, RDMA
# @brief: RDMA with AES encryption example
#
# @note: Add a target device (FDEV_NAME)
#
if(EXAMPLE STREQUAL "rdma_aes")
    message("** RDMA AES-en(de)cryption test")
    set(SHELL_PROBE 5)
    set(N_REGIONS 2)
    set(EN_STRM 1)
    set(EN_MEM 1)
    set(EN_RDMA 1)

    validation_checks_hw()

    load_apps (
        VFPGA_C0_0 "apps/rdma_base"
        VFPGA_C0_1 "apps/rdma_aes"
    )

    create_hw()
endif()

if(EXAMPLE STREQUAL "rdma_perf")
    message("** RDMA perf test")
    set(SHELL_PROBE 6)
    set(N_REGIONS 1)
    set(EN_STRM 1)
    set(EN_RDMA 1)
    set(N_STRM_AXI 2)

    validation_checks_hw()

    load_apps (
        VFPGA_C0_0 "apps/rdma_perf"
    )

    create_hw()
endif()

# Network example, TCP iperf
# @brief: TCP iperf
#
# @note: Add a target device (FDEV_NAME)
#
if(EXAMPLE STREQUAL "tcp_iperf")
    message("** TCP iperf")
    set(SHELL_PROBE 7)
    set(N_REGIONS 1)
    set(EN_STRM 1)
    set(EN_TCP 1)

    validation_checks_hw()

    load_apps (
        VFPGA_C0_0 "apps/tcp_iperf"
    )

    create_hw()
endif()

#
# Perf FPGA
# @brief: Link benchmarks, FPGA initiated
#
# @note: Add a target device (FDEV_NAME)
#

if(EXAMPLE STREQUAL "perf_fpga")
    set(N_REGIONS 1)
    set(EN_STRM 1)
    set(N_STRM_AXI 2)
    set(EN_MEM 0) # Should work with MEM as well
    set(N_CARD_AXI 2)

    validation_checks_hw()

    load_apps (
        VFPGA_C0_0 "apps/perf_fpga"
    )

    create_hw()
endif()
