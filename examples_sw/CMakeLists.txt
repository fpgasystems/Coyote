cmake_minimum_required(VERSION 3.0)
project(test)

set(CYT_DIR ${CMAKE_SOURCE_DIR}/../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)

find_package(CoyoteSW REQUIRED)

#
# Shell reconfiguration
#
if(EXAMPLE STREQUAL "reconfigure_shell")
    set(TARGET_DIR "${CYT_DIR}/examples_sw/apps/reconfigure_shell")
    message("** Shell load")
endif()

#
# Example builds
#

# Used in conjunction with the default shell
if(EXAMPLE STREQUAL "perf_local")
    set(TARGET_DIR "${CYT_DIR}/examples_sw/apps/perf_local")
    message("** Example: Validation tests - Link perf")
endif()

# Streaming services example
if(EXAMPLE STREQUAL "streaming_server")
    set(TARGET_DIR "${CYT_DIR}/examples_sw/apps/streaming_service/server")
    message("** Example: Streaming service - Server (Coyote daemon)")
endif()

if(EXAMPLE STREQUAL "streaming_client")
    set(TARGET_DIR "${CYT_DIR}/examples_sw/apps/streaming_service/client")
    message("** Example: Streaming service - Client")
endif()

if(EXAMPLE STREQUAL "multithreading")
    set(TARGET_DIR "${CYT_DIR}/examples_sw/apps/multithreading")
    message("** Example: Multithreading")
endif()

# Kmeans example (unified memory)
if(EXAMPLE STREQUAL "kmeans")
    set(TARGET_DIR "${CYT_DIR}/examples_sw/apps/kmeans")
    message("** Example: K-Means kernel - Unified memory")
endif()

# Network - RDMA
if(EXAMPLE STREQUAL "rdma_server")
    set(TARGET_DIR "${CYT_DIR}/examples_sw/apps/rdma_service/server")
    message("** Example: RDMA service - Server (Coyote daemon)")
endif()

if(EXAMPLE STREQUAL "rdma_client")
    set(TARGET_DIR "${CYT_DIR}/examples_sw/apps/rdma_service/client")
    message("** Example: RDMA service - Client")
endif()

# Network - TCP
if(EXAMPLE STREQUAL "tcp_iperf")
    set(TARGET_DIR "${CYT_DIR}/examples_sw/apps/tcp_iperf")
    message("**  Example: TCP - iperf")
endif()

#
# Create build targets
#

create_sw()
