cmake_minimum_required(VERSION 3.0)
project(test)

set(CYT_DIR ${CMAKE_SOURCE_DIR}/../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)

find_package(CoyoteSW REQUIRED)

#
# Shell reconfiguration
#
if(EXAMPLE STREQUAL "reconfigure_shell")
    set(TARGET_DIR "${CYT_DIR}/examples_sw/reconfigure_shell")
endif()

#
# Example builds
#

# Used in conjunction with the default shell
if(EXAMPLE STREQUAL "perf_local")
    set(TARGET_DIR "${CYT_DIR}/examples_sw/apps/perf_local")
    message("** Example: Validation tests - Link perf")
endif()

# Streaming services example - reconfiguration example
if(EXAMPLE STREQUAL "streaming_service_server")
    set(TARGET_DIR "${CYT_DIR}/examples_sw/apps/streaming_service/server")
    message("** Example: Streaming service - Server (Coyote daemon)")
endif()

if(EXAMPLE STREQUAL "streaming_service_client")
    set(TARGET_DIR "${CYT_DIR}/examples_sw/apps/streaming_service/client")
    message("** Example: Streaming service - Client")
endif()

# Kmeans example (unified memory)
if(EXAMPLE STREQUAL "kmeans")
    set(TARGET_DIR "${CYT_DIR}/sw/examples/kmeans")
    message("** Example: K-Means kernel - Unified memory")
endif()

# Network examples
if(EXAMPLE STREQUAL "tcp_perf")
    set(TARGET_DIR "${CYT_DIR}/sw/examples/tcp_perf")
    message("** Example: TCP iperf")
endif()

if(EXAMPLE STREQUAL "rdma_aes")
    set(TARGET_DIR "${CYT_DIR}/sw/examples/rdma_aes")
    message("** Example: RDMA network example with AES encryption - shows the negligible cost of additional pipelined operations on top of RDMA")
endif()

#
# Create build targets
#

create_sw()
