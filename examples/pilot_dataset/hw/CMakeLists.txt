######################################################################################
# Pilot dataset — ML detection of suspicious FPGA partial bitstreams
# 24 samples: 3 balanced classes x 8 samples (4 apps x 2 regions)
#
# Build order:
#   Stage 2 (floorplan):  cmake . && make project synth link shell
#                         → open shell_subdivided.dcp in Vivado, define 2 pblocks,
#                           export XDC to floorplans/pilot_fplan_u55c.xdc
#   Stage 3 (full build): cmake . -DFPLAN_PATH=<abs-path>/floorplans/pilot_fplan_u55c.xdc
#                         make project synth link shell app bitgen
#
# Partial bitstream outputs:
#   build_hw/bitstreams/config_0/  … config_3/   — Class 0 (benign),      vfpga_c*_0.bin + vfpga_c*_1.bin
#   build_hw/bitstreams/config_4/  … config_7/   — Class 1 (paired-susp), vfpga_c*_0.bin + vfpga_c*_1.bin
#   build_hw/bitstreams/config_8/  … config_11/  — Class 2 (standalone),  vfpga_c*_0.bin + vfpga_c*_1.bin
######################################################################################

cmake_minimum_required(VERSION 3.5)
set(CYT_DIR ${CMAKE_SOURCE_DIR}/../../../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteHW REQUIRED)

project(pilot_dataset)
message("*** Pilot dataset: ML detection of suspicious FPGA PR bitstreams ***")

# Shell parameters — FROZEN once the shell is built
set(FDEV_NAME   "u55c")
set(N_REGIONS   2)
set(EN_PR       1)
set(N_CONFIG    12)
set(EN_STRM     1)
set(N_STRM_AXI  2)     # 2 AXI streams per vFPGA (needed by euclidean/cosine/vadd)
set(EN_MEM      0)

# Floorplan: comment out for Stage 2 (floorplan generation), uncomment for Stage 3+
# set(FPLAN_PATH "${CMAKE_SOURCE_DIR}/floorplans/pilot_fplan_u55c.xdc")

validation_checks_hw()

load_apps(
    # --- Class 0: Benign (configs 0–3) ---
    # Each config: same app in both regions for spatial diversity
    VFPGA_C0_0   "${CMAKE_SOURCE_DIR}/apps/benign/app1_euclidean"
    VFPGA_C0_1   "${CMAKE_SOURCE_DIR}/apps/benign/app1_euclidean"

    VFPGA_C1_0   "${CMAKE_SOURCE_DIR}/apps/benign/app2_cosine"
    VFPGA_C1_1   "${CMAKE_SOURCE_DIR}/apps/benign/app2_cosine"

    VFPGA_C2_0   "${CMAKE_SOURCE_DIR}/apps/benign/app3_vadd"
    VFPGA_C2_1   "${CMAKE_SOURCE_DIR}/apps/benign/app3_vadd"

    VFPGA_C3_0   "${CMAKE_SOURCE_DIR}/apps/benign/app4_aes"
    VFPGA_C3_1   "${CMAKE_SOURCE_DIR}/apps/benign/app4_aes"

    # --- Class 1: Paired-injected suspicious (configs 4–7) ---
    # Paired with Class 0: config (i+4) matches config i exactly, plus ring_osc_array (N_RO=16)
    VFPGA_C4_0   "${CMAKE_SOURCE_DIR}/apps/suspicious/app1_euclidean_susp"
    VFPGA_C4_1   "${CMAKE_SOURCE_DIR}/apps/suspicious/app1_euclidean_susp"

    VFPGA_C5_0   "${CMAKE_SOURCE_DIR}/apps/suspicious/app2_cosine_susp"
    VFPGA_C5_1   "${CMAKE_SOURCE_DIR}/apps/suspicious/app2_cosine_susp"

    VFPGA_C6_0   "${CMAKE_SOURCE_DIR}/apps/suspicious/app3_vadd_susp"
    VFPGA_C6_1   "${CMAKE_SOURCE_DIR}/apps/suspicious/app3_vadd_susp"

    VFPGA_C7_0   "${CMAKE_SOURCE_DIR}/apps/suspicious/app4_aes_susp"
    VFPGA_C7_1   "${CMAKE_SOURCE_DIR}/apps/suspicious/app4_aes_susp"

    # --- Class 2: Standalone suspicious-dominated (configs 8–11) ---
    # Passthrough + ring_osc_array at increasing scales: 5 / 200 / 3000 / 30000 ROs
    VFPGA_C8_0   "${CMAKE_SOURCE_DIR}/apps/standalone/standalone_1"
    VFPGA_C8_1   "${CMAKE_SOURCE_DIR}/apps/standalone/standalone_1"

    VFPGA_C9_0   "${CMAKE_SOURCE_DIR}/apps/standalone/standalone_2"
    VFPGA_C9_1   "${CMAKE_SOURCE_DIR}/apps/standalone/standalone_2"

    VFPGA_C10_0  "${CMAKE_SOURCE_DIR}/apps/standalone/standalone_3"
    VFPGA_C10_1  "${CMAKE_SOURCE_DIR}/apps/standalone/standalone_3"

    VFPGA_C11_0  "${CMAKE_SOURCE_DIR}/apps/standalone/standalone_4"
    VFPGA_C11_1  "${CMAKE_SOURCE_DIR}/apps/standalone/standalone_4"
)

create_hw()
