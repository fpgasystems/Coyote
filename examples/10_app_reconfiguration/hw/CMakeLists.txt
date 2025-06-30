cmake_minimum_required(VERSION 3.5)
set(CYT_DIR ${CMAKE_SOURCE_DIR}/../../../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteHW REQUIRED)

project(example_10_partial_reconfiguration)
message("*** Coyote Example 10: Partial (application) reconfiguration [Hardware] ***")

# Two input streams, one for each input vector, which are used to calculate the similarity
set(EN_STRM 1)
set(N_STRM_AXI 2)

# Enable partial (application) reconfiguration and specify that there are two possible configurations for the (single) vFPGA
set(EN_PR 1)
set(N_CONFIG 2)
set(N_REGIONS 1)

# Specify the floorplan for partial reconfiguration
set(FDEV_NAME "u55c")
set(FPLAN_PATH "${CMAKE_SOURCE_DIR}/example_fplan_u55c.xdc")

# Load the vector similarity kernels; note the C0_0, corresponding to Config 0, Region 0 and C1_0, corresponding to Config 1, Region 0
validation_checks_hw()
load_apps (
    VFPGA_C0_0 "euclidean_distance"
    VFPGA_C1_0 "cosine_similarity"
)
create_hw()
