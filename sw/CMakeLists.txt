cmake_minimum_required(VERSION 3.0)
project(main)

# Includes
include_directories(${CMAKE_SOURCE_DIR}/include ${TARGET_DIR}/include)

# Sources
file(GLOB SOURCES ${TARGET_DIR}/*.cpp ${CMAKE_SOURCE_DIR}/src/*.cpp)

# AVX support (Disable on Enzian)
set(EN_AVX 1 CACHE STRING "AVX environment.")

# Exec
set(EXEC main)

# Using C++17 and Choose Correct Compiler
set (CMAKE_CXX_STANDARD 17)

execute_process(COMMAND lsb_release -rs
                OUTPUT_VARIABLE UBUNTU_VERSION
                OUTPUT_STRIP_TRAILING_WHITESPACE)
if(UBUNTU_VERSION STREQUAL "18.04")
    message("Detected Ubuntu 18.04. Using clang++-9.")
    set(CMAKE_CXX_COMPILER "clang++-9")
else()
    message("Using default CMAKE_CXX_COMPILER = ", ${CMAKE_CXX_COMPILER})
endif()

if(EN_AVX)
    set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -pthread -mavx -march=native -O3")
else()
    set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -pthread -march=native -O1")
endif()

# Boost lib
find_package(Boost COMPONENTS program_options REQUIRED)

# Targets
add_executable(${EXEC} ${SOURCES})
target_link_libraries(${EXEC} ${Boost_LIBRARIES})
