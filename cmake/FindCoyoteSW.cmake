#
# Coyote SW package
#
cmake_minimum_required(VERSION 3.0)
#project(CoyoteSW)

# AVX support (Disable on Enzian)
set(EN_AVX 1 CACHE STRING "AVX environment.")

# Coyote directory
macro(validation_checks_sw)

    # Coyote directory
    if(NOT DEFINED CYT_DIR)
        message(FATAL_ERROR "Coyote directory not set.")
    endif()

    # Libs
    find_package(Boost COMPONENTS program_options REQUIRED)

    # AVX check
    if(FDEV_NAME STREQUAL "enzian")
        set(EN_AVX 0)
    endif()

endmacro()

macro(create_sw)
    validation_checks_sw()

    # Includes
    include_directories(${CYT_DIR}/sw/include ${TARGET_DIR}/include ${TARGET_DIR}/../include)

    # Sources
    file(GLOB SOURCES ${CYT_DIR}sw/src/*.cpp ${TARGET_DIR}/*.cpp)

    # Set exec
    set(EXEC main)

    # Compilation
    set (CMAKE_CXX_STANDARD 17)
    if(EN_AVX)
        set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -pthread -mavx -march=native -O3")
    else()
        set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -pthread -march=native -O1")
    endif()

    # Targets
    add_executable(${EXEC} ${SOURCES})
    target_link_libraries(${EXEC} ${Boost_LIBRARIES})

endmacro()

