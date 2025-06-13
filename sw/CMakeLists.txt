#
# Coyote SW package
#
cmake_minimum_required(VERSION 3.14)

# Config
set(EN_AVX "1" CACHE STRING "AVX enabled.")
set(EN_GPU "0" CACHE STRING "GPU enabled.")
set(CYT_LANG CXX)

option(COYOTE_VERBOSE "Print verbose debug statements." OFF)

if(COYOTE_VERBOSE) 
  add_compile_definitions(VERBOSE)
endif()

if(COYOTE_VERBOSE_DEBUG_3) 
  add_compile_definitions(VERBOSE_DEBUG_3)
endif()

if(COYOTE_VERBOSE_DEBUG_2) 
  add_compile_definitions(VERBOSE_DEBUG_2)
endif()

if(COYOTE_VERBOSE_DEBUG_1) 
  add_compile_definitions(VERBOSE_DEBUG_1)
endif()


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
        "${HIP_PATH}/../lib/cmake" # hopefully catches all extra HIP dependencies
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

# Create a lib
project(
    coyote
    VERSION 2.0.0
    DESCRIPTION
        "Coyote library"
    LANGUAGES ${CYT_LANG}
)
set(CMAKE_DEBUG_POSTFIX d)

# C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED True)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -pthread -march=native -O3")

# Sources and includes
file(GLOB CYT_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_LIST_DIR}/src/*.cpp")
set(CYT_INCLUDE_PATH ${CMAKE_CURRENT_LIST_DIR}/include)

# Add shared
add_library(coyote SHARED ${CYT_SOURCES})

set_target_properties(coyote PROPERTIES
    VERSION ${PROJECT_VERSION}
    SOVERSION ${PROJECT_VERSION_MAJOR}
)

if (NOT CMAKE_LIBRARY_OUTPUT_DIRECTORY)
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}/lib")
endif()

if (NOT CMAKE_RUNTIME_OUTPUT_DIRECTORY)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}/bin")
endif()

# Includes
target_include_directories(coyote
    PUBLIC
        $<BUILD_INTERFACE:${CYT_INCLUDE_PATH}>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/coyote>
)
target_link_directories(coyote PUBLIC /usr/local/lib)

# Libs
find_package(Boost COMPONENTS program_options REQUIRED)
target_link_libraries(coyote PUBLIC ${Boost_LIBRARIES})

# Comp
if(EN_AVX)
    target_compile_definitions(coyote PUBLIC EN_AVX)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mavx")
endif()
if(EN_GPU)
    target_compile_definitions(coyote PUBLIC EN_GPU)

    # Include GPU directories
    target_include_directories(coyote
            PUBLIC
                $<BUILD_INTERFACE:${ROCM_PATH}/include>
                $<BUILD_INTERFACE:${ROCM_PATH}/include/hsa>)

    # Add GPU libs
    #set_target_properties(coyote PROPERTIES LINKER_LANGUAGE HIP)
    target_link_libraries(coyote PUBLIC hip::device numa pthread drm drm_amdgpu rt dl hsa-runtime64 hsakmt)

endif()

# Add installation rules
include(GNUInstallDirs)

# Install the library
install(TARGETS coyote
    EXPORT CoyoteTargets
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}            # for shared libraries (.so)
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}            # for static libraries (.a)
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}            # for executables
    INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}       # for headers
)

# Install headers
install(DIRECTORY ${CYT_INCLUDE_PATH}/
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/coyote
    FILES_MATCHING PATTERN *.hpp
)

# Export package configuration
install(EXPORT CoyoteTargets
    FILE CoyoteTargets.cmake
    NAMESPACE fpga::
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/coyote
)

# Generate CMake package configuration files
include(CMakePackageConfigHelpers)
write_basic_package_version_file(
    ${CMAKE_CURRENT_BINARY_DIR}/CoyoteConfigVersion.cmake
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY AnyNewerVersion
)

configure_package_config_file(
    ${CMAKE_CURRENT_LIST_DIR}/cmake/CoyoteConfig.cmake.in
    ${CMAKE_CURRENT_BINARY_DIR}/CoyoteConfig.cmake
    INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/coyote
)

# Install CMake configuration files
install(FILES
    ${CMAKE_CURRENT_BINARY_DIR}/CoyoteConfig.cmake
    ${CMAKE_CURRENT_BINARY_DIR}/CoyoteConfigVersion.cmake
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/coyote
)