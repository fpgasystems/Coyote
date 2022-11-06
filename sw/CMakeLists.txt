cmake_minimum_required(VERSION 3.0)
project(base)

# Includes
include_directories(${CMAKE_SOURCE_DIR}/include ${TARGET_DIR}/include)

# Sources
file(GLOB SOURCES ${TARGET_DIR}/*.cpp ${CMAKE_SOURCE_DIR}/src/*.cpp)

# AVX support (Disable on Enzian)
set(EN_AVX 1 CACHE STRING "AVX environment.")

# Exec
set(EXEC main)

# Compilation
set (CMAKE_CXX_STANDARD 17)
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
