############################################
##         COYOTE HARDWARE PACKAGE        ##
############################################
# @brief Set-up the necessary config, dependencies and software to build the Coyote hardware

cmake_minimum_required(VERSION 3.5)

set(IPREPO_DIR ${CMAKE_BINARY_DIR}/iprepo)
file(MAKE_DIRECTORY ${IPREPO_DIR})

############################################
##            USER CONFIGURATION          ##
############################################
# Target FPGA device; supported Alveo U55C, Alveo U280, Alveo U250
set(FDEV_NAME "0" CACHE STRING "Target FPGA device")

##
## BUILD CONFIGURATION
##

# Number of vFPGAs
set(N_REGIONS 1 CACHE STRING "Number of vFPGAs")

# Re-builds the static layer of Coyote, alongside the standard shell and app build
# Not recommended for most users, as the static layer is not configurable and will very rarey require code changes
set(BUILD_STATIC 0 CACHE STRING "Static build flow: static + shell")

# Builds the Coyote shell (dynamic + app layer) and links against an existing static layer checkpoint
# Recommended for most users, since it's much faster than BUILD_STATIC and the shell is the configurable part of Coyote
set(BUILD_SHELL 1 CACHE STRING "Build shell, linking against existing design check-point")

# Build the user logic (vFPGA) and link it against an existing shell 
set(BUILD_APP 0 CACHE STRING "Build app portion of the design (on top of existing shell config)")

# Custom simulation callback script, executed during simulation, executed at the end of scripts/cr_sim.tcl 
set(SIM_SCR_PATH 0 CACHE STRING "Custom simulation script path")

##
## MEMORY & STREAMS
##

# Enable streams from host
set(EN_STRM 1 CACHE STRING "Enable host streams")

# Number of parallel streams from host (per vFPGA)
set(N_STRM_AXI 1 CACHE STRING "Number of host streams")

# Enable streams from card memory (HBM/DDR)
set(EN_MEM 0 CACHE STRING "Enable memory streams")

# Number of parallel streams from card memory (per vFPGA)
set(N_CARD_AXI 1 CACHE STRING "Number of memory streams")

# Target memory type (only applicable if EN_MEM = 1)
set(MEM_TYPE 1 CACHE STRING "Memory type (DDR/HBM)")

# Number of DDR channels
set(N_DDR_CHAN 0 CACHE STRING "Number of DDR channels")

# Enable automatic placement of DDRs
set(DDR_AUTO 1 CACHE STRING "Automatic placement of DDRs")

# Striping fragmentation size
set(DDR_FRAG 1024 CACHE STRING "Stripe fragment size")

# Concatenate HBM bank ports to achieve higher throughput
set(HBM_SPLIT 0 CACHE STRING "HBM bank splitting")

##
## TLB
##
# Regular-pages TLB size; TLB size is 2 ** 10; increase if facing page faults but keep in mind BRAM usage
set(TLBS_S 10 CACHE STRING "TLB (small) size")

# Regular-pages TLB associativity
set(TLBS_A 4 CACHE STRING "TLB (small) associativity")

# Regular-pages TLB page order: 2 ^ TLBS_BITS should corresponds to your regular page size (2 ^ 12 = 4KB, indeed regular page in Linux)
# Modify only if page size is not 4KB
set(TLBS_BITS 12 CACHE STRING "TLB (small) page order")

# Huge-pages TLB size; TLB size is 2 ** 9; increase if facing page faults but keep in mind BRAM usage
set(TLBL_S 9 CACHE STRING "TLB (huge) size")

# Huge-pages TLB associativity
set(TLBL_A 2 CACHE STRING "TLB (huge) associativity")

# Huge-pages TLB page order: 2 ^ TLBL_BITS should corresponds to your huge page size (2 ^ 21 = 2MB, indeed huge page in Linux)
# Modify only if page size is not 2MB; e.g. if you use 1GB huge pages
set(TLBL_BITS 21 CACHE STRING "TLB (huge) page order")

# Use NRU eviction policy
set(EN_NRU 0 CACHE STRING "Enable NRU eviction policy")

# Number of outstanding requests in MMU
set(N_TLB_ACTV 16 CACHE STRING "Number of outstanding PMTUs in MMU")

##
## NETWORKING
##
# Enable RDMA stack
set(EN_RDMA 0 CACHE STRING "Enable RDMA stack")

# Number of RDMA streams, per vFPGA
set(N_RDMA_AXI 1 CACHE STRING "Number of RDMA streams")

# Enable TCP/IP stack
set(EN_TCP 0 CACHE STRING "Enable TCP/IP stack.")

# Number of TCP/IP streams, per vFPGA
set(N_TCP_AXI 1 CACHE STRING "Number of TCP/IP streams")

# Use QSFP port 0
set(EN_NET_0 1 CACHE STRING "QSFP port 0")

# Use QSFP port 1
set(EN_NET_1 0 CACHE STRING "QSFP port 1")

# Network MTU size --- best NOT to change for optimal performance
set(PMTU_BYTES 4096 CACHE STRING "PMTU size")

##
## RECONFIGURATION
##
# Enable partial reconfiguration
set(EN_PR 0 CACHE STRING "Enable PR flow")

# Number of PR configurations; in total N_CONFIG x N_REGION apps must be provided; for more details see Example 9: Partial Reconfiguration
set(N_CONFIG 1 CACHE STRING "Number of PR configurations (for each region)")

# Floorplan for PR; for more details on floorplans, Example 9: Partial Reconfiguration 
set(FPLAN_PATH 0 CACHE STRING "External floorplan for PR")

# Number of clock cycles after which the loaded app is considered valid (due to the ICAP done signal being lost if crossing SLR regions on the U55C)
set(EOS_TIME 1000000 CACHE STRING "End of startup time.")

##
## CLOCKS
##
# Default system clock
set(ACLK_F 250 CACHE STRING "System clock frequency")

# Enable clock domain crossing for the network stack
set(EN_NCLK 1 CACHE STRING "Network clock crossing (250 MHz by default)")

# Target network clock crossing, if EN_NCLK=1
set(NCLK_F 250 CACHE STRING "Network clock frequency")

# Enable clock domain crossing for the user logic
set(EN_UCLK 0 CACHE STRING "User clock crossing (300 MHz by default)")

# Target user logic clock crossing, if EN_UCLK=1
set(UCLK_F 250 CACHE STRING "User clock frequency")

# HBM clock frequency 
set(HCLK_F 450 CACHE STRING "HBM clock frequency")

##
## DEBUG & SYSTEM
##
# Enable sysfs statistics in the driver
set(EN_STATS 1 CACHE STRING "Enable driver sysfs statistics")

# Enable AVX (for host CPUs which include AVX), enabling faste data transfer
set(EN_AVX 1 CACHE STRING "AVX environment")

# Enable writeback, for polling completions from the host CPU --- best NOT to change
set(EN_WB 1 CACHE STRING "Enable writeback")

set(STATIC_PROBE 1044942 CACHE STRING "Static probe ID")
set(SHELL_PROBE 1044942 CACHE STRING "Shell probe ID")

##
## VIVADO
##
# Number of cores to use for synthesis and implementation
set(COMP_CORES 8 CACHE STRING "Number of compilation cores")

# Run implementation with optimization, can help close timing but significantly longer compilation time
set(BUILD_OPT 0 CACHE STRING "Build optimizations (significantly longer compilation times)")

##
## DESIGN CHECKPOINTS
##

# Path to static layer checkpoint, routed and locked
# Coyote provides static layer checkpoints for Alveo U55C, U280, U250 clocked at 250MHz
# Since the static layer never changes, a checkpoint is used for faster Place-and-Route
# Users are free to provide their own via this variable, or, rebuild the static part using BUILD_STATIC = 1
set(STATIC_PATH "${CYT_DIR}/hw/checkpoints" CACHE STRING "Static layer checkpoint")

# Path to a routed and locked shell checkpoint, used for linking an app against it (BUILD_APP = 1)
set(SHELL_PATH "0" CACHE STRING "External shell checkpoint")


##
## ADVANCED
##
# Number of XDMA stages
set(N_XCHAN 3 CACHE STRING "Number of XDMA channels")

# Number of outstanding transactions
set(N_OUTSTANDING 8 CACHE STRING "Number of supported outstanding transactions")

# Varios variables related to pipeline stages
# Each of the following controls the number of register stages in more congested areas of design
# Usually, the default values work just fine; only tweak if facing timing closure issues
set(NR_ST_S0 2 CACHE STRING "Static host stage 0")
set(NR_ST_S1 2 CACHE STRING "Static host stage 1")
set(NR_SH_S0 3 CACHE STRING "Shell host stage 0")
set(NR_SH_S1 2 CACHE STRING "Shell host stage 1")
set(NR_DH_S0 3 CACHE STRING "Dynamic host stage 0")
set(NR_DH_S1 3 CACHE STRING "Dynamic host stage 1")
set(NR_DC_S0 3 CACHE STRING "Dynamic card stage 0")
set(NR_DC_S1 3 CACHE STRING "Dynamic card stage 1")
set(NR_DN_S0 3 CACHE STRING "Dynamic net stage 0")
set(NR_DN_S1 3 CACHE STRING "Dynamic net stage 1")
set(NR_N_S0 6 CACHE STRING "Network stage 0")
set(NR_N_S1 4 CACHE STRING "Network stage 1")
set(NR_N_S2 5 CACHE STRING "Network stage 2")
set(NR_CC 4 CACHE STRING "Static dynamic cc")
set(NR_SD 3 CACHE STRING "Static decouple reg")
set(NR_DD 3 CACHE STRING "Dynamic decouple reg")
set(NR_PR 4 CACHE STRING "PR reg")
set(NR_NST 4 CACHE STRING "Net stats")
set(NR_XST 4 CACHE STRING "XDMA stats")

##
## LEGACY VARIABLES
##
set(NR_E_S0 3 CACHE STRING "Enzian stage 0")
set(NR_E_S1 2 CACHE STRING "Enzian stage 1")
set(NET_DROP 0 CACHE STRING "Network dropper")
set(EN_XTERM 1 CACHE STRING "Terminal prints")

##
## DON'T TOUCH; COYOTE INTERNAL
##
set(LOAD_APPS 0 CACHE STRING "Load external apps")

############################################
##        SOFTWARE DEPENDENCIES           ##
############################################
find_package(Vivado REQUIRED)
if (NOT VIVADO_FOUND)
   message(FATAL_ERROR "Vivado not found.")
endif()

find_package(VitisHLS REQUIRED)
if (NOT VITIS_HLS_FOUND)
  message(FATAL_ERROR "Vitis HLS not found.")
endif()

############################################
##               MACROS                   ##
############################################

function(period_calc expr out)
    execute_process(COMMAND awk "BEGIN {printf ${expr}}" OUTPUT_VARIABLE __out)
    set(${out} ${__out} PARENT_SCOPE)
endfunction()

# Performs base validation checks of configured parmeters and sets the other params
macro(validation_checks_hw)
    if(NOT DEFINED CYT_DIR)
        message(FATAL_ERROR "Coyote directory not set.")
    endif()

    set(NN 0)
    if(BUILD_STATIC)
        message("** Static design flow")
        MATH(EXPR NN "${NN}+1")
    endif()
    if(BUILD_SHELL)
        message("** Shell design flow")
        MATH(EXPR NN "${NN}+1")
    endif()
    if(BUILD_APP)
        message("** App design flow")
        MATH(EXPR NN "${NN}+1")
    endif()
    if(NOT NN EQUAL 1)
        message(FATAL_ERROR "Choose one build flow.")
    endif()

    if(BUILD_SHELL OR BUILD_STATIC)
        if((SHELL_PROBE EQUAL STATIC_PROBE) AND BUILD_SHELL)
            message("** Maybe not a bad choice to set a unique probe ID for the shell.")
        endif()

        # Set device details (memory size is in hex)
        if(FDEV_NAME STREQUAL "u55c") 
            set(FPGA_PART xcu55c-fsvh2892-2L-e CACHE STRING "FPGA device.")
            set(DDR_SIZE 0)
            set(HBM_SIZE 34)
        elseif(FDEV_NAME STREQUAL "u250")
            set(FPGA_PART xcu250-figd2104-2L-e CACHE STRING "FPGA device.")
            set(DDR_SIZE 34)
            set(HBM_SIZE 0)
            set(N_DDR_CHAN 1)
        elseif(FDEV_NAME STREQUAL "u280")
            set(FPGA_PART xcu280-fsvh2892-2L-e CACHE STRING "FPGA device.")
            set(DDR_SIZE 34)
            set(HBM_SIZE 33)
        else()
            message(FATAL_ERROR "Target device not supported.")
        endif()
        message("** Target platform ${FDEV_NAME}")

        ##
        ## DDR and HBM support
        ## ! u280 has both DDR and HBM, HBM enabled by def, if DDR is required add u280 in DDR_DEV and remove it from HBM_DEV
        ##
        set(DDR_DEV "vcu118" "u200" "u250" "enzian")
        set(HBM_DEV "u280" "u50" "u55c")

        list(FIND DDR_DEV ${FDEV_NAME} TMP_DEV)
        if(NOT TMP_DEV EQUAL -1)
            set(AV_DDR 1)
        else()
            set(AV_DDR 0)
        endif()

        list(FIND HBM_DEV ${FDEV_NAME} TMP_DEV)
        if(NOT TMP_DEV EQUAL -1)
            set(AV_HBM 1)
        else()
            set(AV_HBM 0)
        endif()

        ##
        ## User logic
        ##
        # Max regions
        set(MULT_REGIONS 0)
        if(N_REGIONS GREATER 1)
            set(MULT_REGIONS 1)
        endif()
        if(N_REGIONS GREATER 15)
            message(FATAL_ERROR "Max 15 vFPGAs supported.")
        endif()

        # Number of configurations needs to be 1 without PR
        if(N_CONFIG GREATER 1 AND NOT EN_PR)
            message(FATAL_ERROR "When PR is not enabled only one configuration of the shell should exist.")
        endif()

        # User credits (enabled by default)
        set(EN_CRED_LOCAL 1)
        set(EN_CRED_REMOTE 1)

        # User regs
        set(EN_USER_REG 0)

        # Static synthesis does not have PR
        if(BUILD_STATIC AND EN_PR) 
            message(FATAL_ERROR "Static builds do not support PR.")
        endif()

        # Period
        period_calc("1000.0 / ${ACLK_F}" ACLK_P)
        period_calc("1000.0 / ${NCLK_F}" NCLK_P)
        period_calc("1000.0 / ${UCLK_F}" UCLK_P)
        period_calc("1000.0 / ${HCLK_F}" HCLK_P)

        ##
        ## Network
        ##
        set(EN_DCARD 0)
        set(EN_HCARD 0)

        if(EN_TCP)
            set(N_TCP_CHAN 1)
            set(TCP_STACK_EN 1 CACHE BOOL "Enable TCP/IP stack")
        else()
            set(N_TCP_CHAN 0)
            set(TCP_STACK_EN 0 CACHE BOOL "Enable TCP/IP stack")
        endif()
        if(EN_RDMA)
            set(N_RDMA_CHAN 1)
            set(ROCE_STACK_EN 1 CACHE BOOL "RDMA stack disabled.")
        else()
            set(N_RDMA_CHAN 0)
            set(ROCE_STACK_EN 0 CACHE BOOL "RDMA stack disabled.")
        endif() 

        if(EN_TCP OR EN_RDMA)
            if(AV_DDR)  
                set(EN_DCARD 1)
                set(EN_HCARD 0)
                if(N_DDR_CHAN EQUAL 0)
                    set(N_DDR_CHAN 1)
                endif()
            elseif(AV_HBM)
                set(EN_DCARD 0)
                set(EN_HCARD 1)
            endif()
        else()
            if(EN_MEM)
                if(AV_DDR)
                    set(EN_DCARD 1)
                    set(EN_HCARD 0)
                elseif(AV_HBM)
                    set(EN_DCARD 0)
                    set(EN_HCARD 1)
                endif()
            endif()
        endif()

        # Top net enabled
        if(EN_RDMA OR EN_TCP)
            set(EN_NET 1)
        else()
            set(EN_NET 0)
        endif()

        # Mult user channels
        set(MULT_RDMA_AXI 0)
        if(N_RDMA_AXI GREATER 1)
            set(MULT_RDMA_AXI 1)
        endif()

        set(MULT_TCP_AXI 0)
        if(N_TCP_AXI GREATER 1)
            set(MULT_TCP_AXI 1)
        endif()

        # WBs
        set(N_WBS 2)
        if(EN_RDMA)
            set(N_WBS 4)
        endif()

        # Ports, only one
        if(EN_NET_0 AND EN_NET_1)
            message(FATAL_ERROR "Both network ports enabled.")
        else()
            set(QSFP 0)
            if(EN_NET_1)
                set(QSFP 1)
            endif()
        endif()

        ##
        ## Memory
        ##

        # Total AXI memory channels
        if(EN_HCARD OR EN_DCARD)
            set(EN_CARD 1)
        else()
            set(EN_CARD 0)
        endif()

        # Total memory AXI channels
        set(N_MEM_CHAN 0)
        set(N_NET_CHAN 0)
        MATH(EXPR N_NET_CHAN "${N_TCP_CHAN} + ${N_RDMA_CHAN}")
        if(EN_MEM)
            MATH(EXPR N_MEM_CHAN "${N_REGIONS} * ${N_CARD_AXI} + 1 + ${N_MEM_CHAN}")
        endif()
        if(EN_TCP OR EN_RDMA)
            MATH(EXPR N_MEM_CHAN "${N_NET_CHAN} + ${N_MEM_CHAN}")
        endif()

        # Most boards only up to 4
        if(EN_DCARD)
            if((N_DDR_CHAN GREATER 4) OR (N_DDR_CHAN LESS 1))
                message(FATAL_ERROR "Number of DDR channels misconfigured.")
            endif()
        endif()

        set(DDR_0 0) # Bottom SLR (TODO: Check this stuff, might be completely different)
        set(DDR_1 0) # Mid SLRs
        set(DDR_2 0) # Mid SLRs
        set(DDR_3 0) # Top SLR

        if(DDR_AUTO)
            if(EN_DCARD)
                if(N_DDR_CHAN GREATER 0)
                    set(DDR_0 1)
                endif()
                if(N_DDR_CHAN GREATER 1)
                    set(DDR_1 1)
                endif()
                if(N_DDR_CHAN GREATER 2)
                    set(DDR_2 1)
                    set(DDR_3 1)
                endif()
            endif()
        endif()

        set(MULT_DDR_CHAN 0)
        if(N_DDR_CHAN GREATER 1)
            set(MULT_DDR_CHAN 1)
        endif()

        # Compare for mismatch
        if(EN_DCARD)
            MATH(EXPR N_DDRS "${DDR_0}+${DDR_1}+${DDR_2}+${DDR_3}")
            if(NOT N_DDRS EQUAL ${N_DDR_CHAN})
                message(FATAL_ERROR "DDRs have not been configured properly.")
            endif()
        endif()

        ##
        ## Enzian
        ##

        # Enzian currently doesn't support any form of AVX
        set(POL_INV 0)
        if(FDEV_NAME STREQUAL "enzian")
        if(EN_AVX)
            message("AVX instructions not supported on the Enzian platform currently. Force disable.")
            set(EN_AVX 0)
        endif()
        if(EN_NET)
            set(POL_INV 1)
        endif()
        endif()

        ##
        ## Control regs
        ##

        set(EN_GP_CTRL 0)
        if(N_GP_CTRL GREATER 0)
            set(EN_GP_CTRL 1)
        endif()
        set(EN_GP_STAT 0)
        if(N_GP_STAT GREATER 0)
            set(EN_GP_STAT 1)
        endif()
        set(EN_GP_RW 0)
        if(N_GP_RW GREATER 0)
            set(EN_GP_RW 1)
        endif()


        ##
        ## Rest of parameters
        ##

        set(N_SCHAN 0 CACHE STRING "Total number of shell crossing channels.")
        MATH(EXPR N_SCHAN "${N_XCHAN}-1")

        set(N_CHAN 0)
        if(EN_STRM)
            MATH(EXPR N_CHAN "${N_CHAN}+1")
        endif()
        if(EN_MEM)
            MATH(EXPR N_CHAN "${N_CHAN}+1")
        endif()

        set(NN 0)
        set(STRM_CHAN -1 CACHE STRING "Stream channel.")
        set(CARD_CHAN -1 CACHE STRING "Memory channel.")
        set(MULT_STRM_AXI 0)
        set(MULT_CARD_AXI 0)
        if(EN_STRM)
            set(STRM_CHAN ${NN})
            MATH(EXPR NN "${NN}+1")
            if(N_STRM_AXI GREATER 1)
                set(MULT_STRM_AXI 1)
            endif()
        endif()
        if(EN_MEM)
            set(CARD_CHAN ${NN})
            MATH(EXPR NN "${NN}+1")
            if(N_CARD_AXI GREATER 1)
                set(MULT_CARD_AXI 1)
            endif()
        endif()

        set(EN_XCH_0 0 CACHE STRING "Status counter channel 0.")
        set(EN_XCH_1 0 CACHE STRING "Status counter channel 1.")
        if(N_CHAN GREATER 0)
            set(EN_XCH_0 1)
        endif()
        if(N_CHAN GREATER 1)
            set(EN_XCH_1 1)
        endif()

    else()
        if(SHELL_PATH EQUAL "0")
            message(FATAL_ERROR "External shell path not provided.")
        endif()

        include("${CMAKE_BINARY_DIR}/${SHELL_PATH}/export.cmake")

        if(EN_PR EQUAL 0)
            message(FATAL_ERROR "PR not enabled in the shell.")
        endif()

    endif()

endmacro()

# Load applications
macro(load_apps)

    if(N_REGIONS EQUAL 0)
        message(FATAL_ERROR "N_REGIONS not set.")
    endif()

    # Load shell
    MATH(EXPR NN "2 * ${N_REGIONS} * ${N_CONFIG}")
    if(NOT ${ARGC} EQUAL ${NN}) 
        message(FATAL_ERROR "Provide N_REGIONS * N_CONFIG apps.")
    endif()

    set(APP_VARS "")
    set(c_idx 0)
    set(v_idx 0)
    while(c_idx LESS N_CONFIG)
        while(v_idx LESS N_REGIONS)
            set(APP_VARS "${APP_VARS}VFPGA_C${c_idx}_${v_idx};")
            MATH(EXPR v_idx "${v_idx}+1")    
        endwhile()
        MATH(EXPR c_idx "${c_idx}+1")
        set(v_idx 0)
    endwhile()

    cmake_parse_arguments(
        "APPS" # prefix of output variables
        ""
        ""
        "${APP_VARS}"
        ${ARGN}
    )

    set(c_idx 0)
    set(v_idx 0)
    MATH(EXPR NN "${N_REGIONS}-1")
    set(APPS_ALL "")
    message("**")
    message("** ─── Applications")
    
    while(c_idx LESS N_CONFIG)
        message("**   └── Config ${c_idx}")

        while(v_idx LESS N_REGIONS)
            if(NOT DEFINED "APPS_VFPGA_C${c_idx}_${v_idx}")
                message(FATAL_ERROR "Missing arguments.")
            endif()

            list(LENGTH "APPS_VFPGA_C${c_idx}_${v_idx}" l_tmp)
            if(NOT l_tmp EQUAL 1)
                message(FATAL_ERROR "Wrong number of arguments provided, ${l_tmp}.")
            endif()

            if(v_idx LESS NN)            
                set(TMP_P "**     ├── vFPGA ${v_idx}:")
            else()
                set(TMP_P "**     └── vFPGA ${v_idx}:")  
            endif()
            set(TMP_P "${TMP_P} path:")
            set(t_idx 0)
            foreach(vf_app IN LISTS "APPS_VFPGA_C${c_idx}_${v_idx}")
                set(TMP_P "${TMP_P} ${vf_app}")
                set(APPS_ALL "${APPS_ALL}set vfpga_c${c_idx}_${v_idx} ${vf_app}\n")
                MATH(EXPR t_idx "${t_idx}+1")
            endforeach()
            message("${TMP_P}")

            MATH(EXPR v_idx "${v_idx}+1")
        endwhile()
        MATH(EXPR c_idx "${c_idx}+1")
        set(v_idx 0)
    endwhile()
    message("**")

    set(LOAD_APPS 1)

endmacro()

# Generate templated scripts, from the parameters configured here
macro(gen_scripts)
    # Python
    configure_file(${CYT_DIR}/scripts/wr_hdl/write_hdl.py.in ${CMAKE_BINARY_DIR}/write_hdl.py)
    configure_file(${CYT_DIR}/scripts/wr_hdl/replace.py.in ${CMAKE_BINARY_DIR}/replace.py)

    # TCL
    configure_file(${CYT_DIR}/scripts/config.tcl.in ${CMAKE_BINARY_DIR}/config.tcl)
    configure_file(${CYT_DIR}/scripts/base.tcl.in ${CMAKE_BINARY_DIR}/base.tcl)
    configure_file(${CYT_DIR}/scripts/package.tcl.in ${CMAKE_BINARY_DIR}/package.tcl)
    configure_file(${CYT_DIR}/scripts/comp_hls.tcl.in ${CMAKE_BINARY_DIR}/comp_hls.tcl)

    # Simulation
    configure_file(${CYT_DIR}/scripts/cr_sim.tcl.in ${CMAKE_BINARY_DIR}/cr_sim.tcl)

    # Project
    configure_file(${CYT_DIR}/scripts/cr_static.tcl.in ${CMAKE_BINARY_DIR}/cr_static.tcl)
    configure_file(${CYT_DIR}/scripts/cr_shell.tcl.in ${CMAKE_BINARY_DIR}/cr_shell.tcl)
    configure_file(${CYT_DIR}/scripts/cr_user.tcl.in ${CMAKE_BINARY_DIR}/cr_user.tcl)
    configure_file(${CYT_DIR}/scripts/flow_static_prjct.tcl.in ${CMAKE_BINARY_DIR}/flow_static_prjct.tcl)
    configure_file(${CYT_DIR}/scripts/flow_shell_prjct.tcl.in ${CMAKE_BINARY_DIR}/flow_shell_prjct.tcl)
    configure_file(${CYT_DIR}/scripts/flow_app_prjct.tcl.in ${CMAKE_BINARY_DIR}/flow_app_prjct.tcl)

    # Synth
    configure_file(${CYT_DIR}/scripts/synth_static.tcl.in ${CMAKE_BINARY_DIR}/synth_static.tcl)
    configure_file(${CYT_DIR}/scripts/synth_shell.tcl.in ${CMAKE_BINARY_DIR}/synth_shell.tcl)
    configure_file(${CYT_DIR}/scripts/synth_user.tcl.in ${CMAKE_BINARY_DIR}/synth_user.tcl)
    configure_file(${CYT_DIR}/scripts/flow_synth_static.tcl.in ${CMAKE_BINARY_DIR}/flow_synth_static.tcl)
    configure_file(${CYT_DIR}/scripts/flow_synth_shell.tcl.in ${CMAKE_BINARY_DIR}/flow_synth_shell.tcl)
    configure_file(${CYT_DIR}/scripts/flow_synth_user.tcl.in ${CMAKE_BINARY_DIR}/flow_synth_user.tcl)

    # Link
    configure_file(${CYT_DIR}/scripts/flow_link.tcl.in ${CMAKE_BINARY_DIR}/flow_link.tcl)

    # Compile
    configure_file(${CYT_DIR}/scripts/flow_comp.tcl.in ${CMAKE_BINARY_DIR}/flow_comp.tcl)

    # Dynamic and app
    configure_file(${CYT_DIR}/scripts/flow_dyn.tcl.in ${CMAKE_BINARY_DIR}/flow_dyn.tcl)
    configure_file(${CYT_DIR}/scripts/flow_app.tcl.in ${CMAKE_BINARY_DIR}/flow_app.tcl)

    # Bitgen
    configure_file(${CYT_DIR}/scripts/flow_bitgen.tcl.in ${CMAKE_BINARY_DIR}/flow_bitgen.tcl)

    # Export
    configure_file(${CYT_DIR}/scripts/export.cmake.in ${CMAKE_BINARY_DIR}/export.cmake)
endmacro()

# Generate dependency lists
macro(gen_dep_lists)
    MATH(EXPR NN_CONFIG "${N_CONFIG} - 1")
    MATH(EXPR NN_REGIONS "${N_REGIONS} - 1")

    # Synthesis
    set(DEP_DCP_LIST_SYNTH_STATIC ${CMAKE_BINARY_DIR}/checkpoints/static/static_synthed.dcp)
    set(DEP_DCP_LIST_SYNTH_SHELL ${CMAKE_BINARY_DIR}/checkpoints/shell/shell_synthed.dcp)
    set(DEP_DCP_LIST_SYNTH_USER  "")
    foreach(i RANGE ${NN_CONFIG})
        foreach(j RANGE ${NN_REGIONS})
            list(APPEND DEP_DCP_LIST_SYNTH_USER ${CMAKE_BINARY_DIR}/checkpoints/config_${i}/user_synthed_c${i}_${j}.dcp)
        endforeach() 
    endforeach()

    # Link
    set(DEP_DCP_LIST_LINK  ${CMAKE_BINARY_DIR}/checkpoints/shell_linked.dcp)

    # Compile
    if(EN_PR)
        if(BUILD_SHELL)
            set(DEP_DCP_LIST_COMP  ${CMAKE_BINARY_DIR}/checkpoints/shell_subdivided.dcp)
        else()
            set(DEP_DCP_LIST_COMP  ${CMAKE_BINARY_DIR}/${SHELL_PATH}/checkpoints/shell_routed_locked.dcp)
        endif()
    else()
        set(DEP_DCP_LIST_COMP  ${CMAKE_BINARY_DIR}/checkpoints/shell_routed.dcp)
    endif()

    # Dynamic
    if(BUILD_SHELL)
        set(DEP_DCP_LIST_DYN   ${CMAKE_BINARY_DIR}/checkpoints/shell_recombined.dcp)
    else()
        set(DEP_DCP_LIST_DYN   "")
    endif()
    foreach(i RANGE ${NN_CONFIG})
        list(APPEND DEP_DCP_LIST_DYN ${CMAKE_BINARY_DIR}/checkpoints/config_${i}/shell_routed_c${i}.dcp)
    endforeach()

    # Bitgen
    if(BUILD_STATIC)
        set(DEP_DCP_LIST_BGEN  ${CMAKE_BINARY_DIR}/checkpoints/cyt_top.bit)
    else()
        if(BUILD_SHELL)
            set(DEP_DCP_LIST_BGEN  ${CMAKE_BINARY_DIR}/checkpoints/shell_top.bit)
        else()
            set(DEP_DCP_LIST_BGEN  "")
        endif()
        if(EN_PR)
            foreach(i RANGE ${NN_CONFIG})
                foreach(j RANGE ${NN_REGIONS})
                    list(APPEND DEP_DCP_LIST_BGEN ${CMAKE_BINARY_DIR}/bitstreams/config_${i}/vfpga_c${i}_${j}.bit)
                endforeach()    
            endforeach()
        endif()
    endif()

endmacro()

# Generate build targets
macro(gen_targets)
    if(EN_NET)
        add_subdirectory(${CYT_DIR}/hw/services/network ${CMAKE_BINARY_DIR}/network)
        set(NET_SYNTH_CMD COMMAND make services)
    endif()

    if(LOAD_APPS)
        set(HLS_SYNTH_CMD COMMAND ${VITIS_HLS_BINARY} -f comp_hls.tcl -tclargs ${target})
    endif()

    # Shell flow
    set(STATIC_PRJCT_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/flow_static_prjct.tcl -notrace)
    set(SHELL_PRJCT_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/flow_shell_prjct.tcl -notrace)
    set(APP_PRJCT_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/flow_app_prjct.tcl -notrace)

    set(SYNTH_CMD_STATIC  COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/flow_synth_static.tcl -notrace)
    set(SYNTH_CMD_SHELL   COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/flow_synth_shell.tcl -notrace)
    set(SYNTH_CMD_USER    COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/flow_synth_user.tcl -notrace)

    set(LINK_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/flow_link.tcl -notrace)

    set(COMP_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/flow_comp.tcl -notrace)

    set(DYN_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/flow_dyn.tcl -notrace)
    set(APP_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/flow_app.tcl -notrace)
    
    set(BGEN_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/flow_bitgen.tcl -notrace)

    # Dependencies
    gen_dep_lists()

    # Sim
    # -----------------------------------
    add_custom_target(sim COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/cr_sim.tcl -notrace)

    # Project
    # -----------------------------------
    if(BUILD_STATIC)
        add_custom_target(project
            ${NET_SYNTH_CMD}
            ${HLS_SYNTH_CMD}
            ${STATIC_PRJCT_CMD}
        )
    elseif(BUILD_SHELL)
        add_custom_target(project 
            ${NET_SYNTH_CMD}
            ${HLS_SYNTH_CMD}
            ${SHELL_PRJCT_CMD}
        )
    elseif(BUILD_APP)
        add_custom_target(project 
            ${HLS_SYNTH_CMD}
            ${APP_PRJCT_CMD}
        )
    endif()

    # Synth
    # -----------------------------------
    add_custom_target(synth 
        DEPENDS ${DEP_DCP_LIST_SYNTH_USER}
    )

    if(BUILD_APP)
        add_custom_command(
            OUTPUT ${DEP_DCP_LIST_SYNTH_USER}
            ${SYNTH_CMD_USER}
        )
    else()
        add_custom_command(
            OUTPUT ${DEP_DCP_LIST_SYNTH_USER}
            ${SYNTH_CMD_USER}
            DEPENDS ${DEP_DCP_LIST_SYNTH_SHELL}
        )

        if(BUILD_SHELL)
            add_custom_command(
                OUTPUT ${DEP_DCP_LIST_SYNTH_SHELL}
                ${SYNTH_CMD_SHELL}
            )
        
        elseif(BUILD_STATIC)
            add_custom_command(
                OUTPUT ${DEP_DCP_LIST_SYNTH_SHELL}
                ${SYNTH_CMD_SHELL}
                DEPENDS ${DEP_DCP_LIST_SYNTH_STATIC}
            )

            add_custom_command(
                OUTPUT ${DEP_DCP_LIST_SYNTH_STATIC}
                ${SYNTH_CMD_STATIC}
            )
        endif()
    endif()


    if(BUILD_SHELL OR BUILD_STATIC) 
        # Linking
        # -----------------------------------
        add_custom_target(link 
            DEPENDS ${DEP_DCP_LIST_LINK}
        )

        add_custom_command(
            OUTPUT ${DEP_DCP_LIST_LINK}
            ${LINK_CMD}
            DEPENDS ${DEP_DCP_LIST_SYNTH_USER}
        )

        # Shell compile
        # -----------------------------------
        add_custom_target(shell 
            DEPENDS ${DEP_DCP_LIST_COMP}
        )

        add_custom_command(
            OUTPUT ${DEP_DCP_LIST_COMP}
            ${COMP_CMD}
            DEPENDS ${DEP_DCP_LIST_LINK}
        )
    endif()

    # Bitgen
    # -----------------------------------
    add_custom_target(bitgen 
        DEPENDS ${DEP_DCP_LIST_BGEN}
    )

    if(EN_PR)
        add_custom_command(
            OUTPUT ${DEP_DCP_LIST_BGEN}
            ${BGEN_CMD}
            DEPENDS ${DEP_DCP_LIST_DYN}
        )

        add_custom_target(app
            DEPENDS ${DEP_DCP_LIST_DYN}
        )

        if(BUILD_APP)
            add_custom_command(
                OUTPUT ${DEP_DCP_LIST_DYN}
                ${APP_CMD}
                DEPENDS ${DEP_DCP_LIST_COMP}
            )
        else()
            add_custom_command(
                OUTPUT ${DEP_DCP_LIST_DYN}
                ${DYN_CMD}
                DEPENDS ${DEP_DCP_LIST_COMP}
            )
        endif()
    else()
        add_custom_command(
            OUTPUT ${DEP_DCP_LIST_BGEN}
            ${BGEN_CMD}
            DEPENDS ${DEP_DCP_LIST_COMP}
        )
    endif()

endmacro()

# Create build
macro(create_hw)
    gen_scripts()
    gen_targets()

endmacro()