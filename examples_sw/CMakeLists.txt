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
    set(TARGET_DIR "${CYT_DIR}/examples_sw/perf_local")
endif()

# Application examples
if(EXAMPLE STREQUAL "hloglog")
    set(TARGET_DIR "${CYT_DIR}/sw/examples/hloglog")
endif()

if(EXAMPLE STREQUAL "dtrees")
    set(TARGET_DIR "${CYT_DIR}/sw/examples/dtrees")
endif()

if(EXAMPLE STREQUAL "kmeans")
    set(TARGET_DIR "${CYT_DIR}/sw/examples/kmeans")
endif()

# Network examples
if(EXAMPLE STREQUAL "tcp_perf")
    set(TARGET_DIR "${CYT_DIR}/sw/examples/tcp_perf")
endif()

if(EXAMPLE STREQUAL "rdma_perf")
    set(TARGET_DIR "${CYT_DIR}/sw/examples/rdma_perf")
endif()

# Dynamic reconfiguration example
if(EXAMPLE STREQUAL "service_reconfiguration")
    set(TARGET_DIR "${CYT_DIR}/sw/examples/service_reconfiguration")
endif()

#
# Create build targets
#

create_sw()
