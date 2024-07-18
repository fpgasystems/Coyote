#
# Coyote SW package
#
cmake_minimum_required(VERSION 3.0)

# Config
set(EN_AVX "1" CACHE STRING "AVX enabled.")
set(EN_GPU "0" CACHE STRING "GPU enabled.")
set(CYT_LANG CXX)

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
    Coyote
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
file(GLOB CYT_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_LIST_DIR}/../sw/src/*.cpp")
set(CYT_INCLUDE_PATH ${CMAKE_CURRENT_LIST_DIR}/../sw/include)

# Add shared
add_library(Coyote SHARED ${CYT_SOURCES})

set_target_properties(Coyote PROPERTIES
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
target_include_directories(Coyote PUBLIC ${CYT_INCLUDE_PATH})
target_link_directories(Coyote PUBLIC /usr/local/lib)

# Libs
find_package(Boost COMPONENTS program_options REQUIRED)
target_link_libraries(Coyote PUBLIC ${Boost_LIBRARIES})

# Comp
if(EN_AVX)
    target_compile_definitions(Coyote PUBLIC EN_AVX)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mavx")
endif()
if(EN_GPU)
    target_compile_definitions(Coyote PUBLIC EN_GPU)

    # Include GPU directories
    target_include_directories(Coyote
            PUBLIC
                $<BUILD_INTERFACE:${ROCM_PATH}/include>
                $<BUILD_INTERFACE:${ROCM_PATH}/include/hsa>)

    # Add GPU libs
    #set_target_properties(Coyote PROPERTIES LINKER_LANGUAGE HIP)
    target_link_libraries(Coyote PUBLIC hip::device numa pthread drm drm_amdgpu rt dl hsa-runtime64 hsakmt)

endif()


