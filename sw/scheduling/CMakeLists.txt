cmake_minimum_required(VERSION 3.0)
project(scheduling)

# Includes
include_directories(include)

# Sources
file(GLOB SOURCES src/*.cpp)

# Exec
set(EXEC main)

# Compilation
set (CMAKE_CXX_STANDARD 14)
set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -pthread -mavx -march=native -O3")

# Boost lib
#find_package(Boost COMPONENTS program_options REQUIRED)

# Targets
add_executable(${EXEC} ${SOURCES})
#target_link_libraries(${EXEC} ${Boost_LIBRARIES})