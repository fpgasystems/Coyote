cmake_minimum_required(VERSION 3.0)
project(test)

set(CYT_DIR ${CMAKE_SOURCE_DIR}/../)

set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteSW REQUIRED)
find_package(Boost REQUIRED)

#
# Shell reconfiguration
#
if(EXAMPLE STREQUAL "reconfigure_shell")
    set(TARGET_DIR "${CYT_DIR}/examples_sw/apps/reconfigure_shell")
    message("** Shell load")
endif()

#
# TEST
#
if(EXAMPLE STREQUAL "perf_gpu")
    set(TARGET_DIR "${CYT_DIR}/examples_sw/apps/perf_gpu")
    message("** Example: Validation tests - GPU perf")
endif()

#
# Example builds
#

# Used in conjunction with the default shell
if(EXAMPLE STREQUAL "perf_local")
    set(TARGET_DIR "${CYT_DIR}/examples_sw/apps/perf_local")
    message("** Example: Validation tests - Link perf")
endif()

# FPGA perf benchmark
if(EXAMPLE STREQUAL "perf_fpga")
    set(TARGET_DIR "${CYT_DIR}/examples_sw/apps/perf_fpga")
    message("** Example: FPGA perf benchmark")
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
    include_directories(${TARGET_DIR}/../include)
endif()

if(EXAMPLE STREQUAL "rdma_client")
    set(TARGET_DIR "${CYT_DIR}/examples_sw/apps/rdma_service/client")
    message("** Example: RDMA service - Client")
    include_directories(${TARGET_DIR}/../include)
endif()

# Network - TCP
if(EXAMPLE STREQUAL "tcp_iperf")
    set(TARGET_DIR "${CYT_DIR}/examples_sw/apps/tcp_iperf")
    message("**  Example: TCP - iperf")
endif()

# Arrow
if(EXAMPLE STREQUAL "arrow_test_1")
	set(TARGET_DIR "${CYT_DIR}/../sw/test_1")
    #set(COMMON_DIR "${CYT_DIR}/../sw/common")
    #set(USE_ARROW_OFFICIAL 1)
    #set(BUILD_NO_FPGA 1)
	message("**  Example: Arrow test_1")
endif()

# Minimal Two Transfer Test
if(EXAMPLE STREQUAL "mem_bw")
        set(TARGET_DIR "${CYT_DIR}/../sw/mem_bw")
        message("**  Example: Simple Memory Bandwidth Test")
endif()

# more complete test for arrow
if(EXAMPLE STREQUAL "arrow_test_2")
	set(TARGET_DIR "${CYT_DIR}/../sw/test_2")
    set(COMMON_DIR "${CYT_DIR}/../sw/common")
    set(USE_ARROW_OFFICIAL 1)
    set(BUILD_NO_FPGA 1)
	message("**  Example: Arrow test_2")
endif()

# server of RDMA enabled build
if (EXAMPLE STREQUAL "arrow_server")
    set(TARGET_DIR "${CYT_DIR}/../sw/test_3/server")
    set(COMMON_DIR "${CYT_DIR}/../sw/common")
    set(USE_ARROW_OFFICIAL 1)
    set(BUILD_NO_FPGA 1)
    message("**  Example: Arrow RDMA server")
endif()

# server of RDMA enabled build
if (EXAMPLE STREQUAL "arrow_client")
    set(TARGET_DIR "${CYT_DIR}/../sw/test_3/client")
    set(COMMON_DIR "${CYT_DIR}/../sw/common")
    set(USE_ARROW_OFFICIAL 1)
    set(BUILD_NO_FPGA 1)
    message("**  Example: Arrow RDMA client")
endif()

# Minimal Test
if(EXAMPLE STREQUAL "minimal")
	set(TARGET_DIR "${CYT_DIR}/../sw/test_minimal")
	message("**  Example: Minimal Test")
endif()

# Minimal Two Transfer Test
if(EXAMPLE STREQUAL "two")
        set(TARGET_DIR "${CYT_DIR}/../sw/test_two")
        message("**  Example: Minimal Two Transfer Test")
endif()

#
# Create build targets
#
set(CMAKE_EXPORT_COMPILE_COMMANDS 1)

file(GLOB TARGET_FILES "${TARGET_DIR}/*.cpp" "${TARGET_DIR}/*/*.cpp")
if (COMMON_DIR)
    file(GLOB COMMON_FILES "${COMMON_DIR}/*.cpp" "${COMMON_DIR}/*/*.cpp")
endif()
# always build full target

set(EXEC test)
add_executable(${EXEC} ${TARGET_FILES} ${COMMON_FILES})
include_directories(${EXEC} SYSTEM ${TARGET_DIR} ${COMMON_DIR} "${CYT_DIR}/../include" "${CYT_DIR}/sw/include" "${TARGET_DIR}/../include")
target_link_libraries(${EXEC} PUBLIC Coyote)
target_link_directories(${EXEC} PUBLIC /usr/local/lib)
target_link_directories(${EXEC} PUBLIC "${CYT_DIR}/../lib")
target_link_libraries(${EXEC} PUBLIC boost_program_options papi pfm sde)

if (USE_ARROW_OFFICIAL)
    target_link_libraries(${EXEC} PUBLIC arrow)
endif()

if (BUILD_NO_FPGA)
    # only build local test if the test actively supports this
    add_executable(no_fpga) # allow for multiple source files
    target_sources(no_fpga PUBLIC ${TARGET_FILES} PUBLIC ${COMMON_FILES})
    target_compile_definitions(no_fpga PRIVATE NO_FPGA)
    include_directories(no_fpga SYSTEM ${TARGET_DIR} ${COMMON_DIR} "${CYT_DIR}/../include" "${TARGET_DIR}/../include")
    # target_link_libraries(no_fpga PUBLIC Coyote) # don't link agains coyote here
    target_link_directories(no_fpga PUBLIC /usr/local/lib)
    target_link_directories(no_fpga PUBLIC "${CYT_DIR}/../lib")
    target_link_libraries(no_fpga PUBLIC boost_program_options papi pfm sde)
    
    if (USE_ARROW_OFFICIAL)
        target_link_libraries(no_fpga PUBLIC arrow)
    endif()
endif()

if(EN_GPU)
    set(AMD_GPU "gfx908" CACHE STRING "AMD GPU device to use")
    set_property(TARGET ${EXEC} PROPERTY HIP_ARCHITECTURES ${AMD_GPU})
    set_target_properties(${EXEC} PROPERTIES LINKER_LANGUAGE CXX)
    target_link_libraries(${EXEC} PUBLIC hip::device  numa pthread drm drm_amdgpu rt dl hsa-runtime64 hsakmt)
endif()
