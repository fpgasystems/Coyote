##
## Quick validation checks
##

## General

# Max supported regions
set(MULT_REGIONS 0)
if(N_REGIONS GREATER 1)
    set(MULT_REGIONS 1)
endif()
if(N_REGIONS GREATER 15)
    message(FATAL_ERROR "Max 15 regions supported.")
endif()

# Number of configurations needs to be 1 without PR
if(N_CONFIG GREATER 1 AND NOT EN_PR)
    message(FATAL_ERROR "When PR is not enabled only one configuration of the system should exist.")
endif()

##
## Network
##

# RDMA Bypass
if(EN_RDMA_0 OR EN_RDMA_1)
    set(EN_BPSS 1)
endif()

# RDMA stack
if(EN_RDMA_0 OR EN_RDMA_1)
    set(ROCE_STACK_EN 1 CACHE BOOL "RDMA stack disabled.")
    set(EN_RDMA 1)
else()
    set(ROCE_STACK_EN 0 CACHE BOOL "RDMA stack disabled.")
    set(EN_RDMA 0)
endif()

# TCP stack (also set appropriate memory config)
set(N_TCP_CHAN 0)
set(EN_DCARD 0)
set(EN_HCARD 0)
if(EN_TCP_0 OR EN_TCP_1)
    if(AV_DDR)
        if(EN_TCP_0 AND EN_TCP_1)
            set(N_TCP_CHAN 2)
        else()
            set(N_TCP_CHAN 1)
        endif()

        # Mem
        set(EN_DCARD 1)
        set(EN_HCARD 0)

        if(N_DDR_CHAN EQUAL 0)
            set(N_DDR_CHAN 1)
        endif()
    elseif(AV_HBM)
        if(EN_TCP_0 AND EN_TCP_1)
            set(N_TCP_CHAN 2)
        else()
            set(N_TCP_CHAN 1)
        endif()

        # Mem
        set(EN_DCARD 0)
        set(EN_HCARD 1)
    endif()

    # Stack
    set(TCP_STACK_EN 1 CACHE BOOL "Enable TCP/IP stack")
    set(EN_TCP 1)
else()
    # Mem
    if(EN_MEM)
        if(AV_DDR)
            set(EN_DCARD 1)
            set(EN_HCARD 0)
        elseif(AV_HBM)
            set(EN_DCARD 0)
            set(EN_HCARD 1)
        endif()
    endif()

    # Stack
    set(TCP_STACK_EN 0 CACHE BOOL "Enable TCP/IP stack")
    set(EN_TCP 0)
endif()

# Simple UDP stack not supported
set(UDP_STACK_EN 0 CACHE BOOL "Enable UDP/IP stack")

# Rest of network flags
if(EN_RDMA_0 OR EN_RDMA_1)
    set(EN_RDMA 1)
else()
    set(EN_RDMA 0)
endif()

if(EN_TCP_0 OR EN_TCP_1)
    set(EN_TCP 1)
else()
    set(EN_TCP 0)
endif()

if(EN_RDMA_0 OR EN_TCP_0)
    set(EN_NET_0 1)
else()
    set(EN_NET_0 0)
endif()

if(EN_RDMA_1 OR EN_TCP_1)
    set(EN_NET_1 1)
else()
    set(EN_NET_1 0)
endif()

if(EN_NET_0 OR EN_NET_1)
    set(EN_NET 1)
else()
    set(EN_NET 0)
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

# Total mem AXI channels
set(N_MEM_CHAN 0)
if(EN_MEM)
    MATH(EXPR N_MEM_CHAN "${N_REGIONS} * ${N_CARD_AXI} + 1 + ${N_MEM_CHAN}")
endif()
if(EN_TCP)
    MATH(EXPR N_MEM_CHAN "${N_TCP_CHAN} + ${N_MEM_CHAN}")
endif()

# Most boards only up to 4
if(EN_DCARD)
    if((N_DDR_CHAN GREATER 4) OR (N_DDR_CHAN LESS 1))
        message(FATAL_ERROR "Number of DDR channels misconfigured.")
    endif()
endif()

# Setup channels
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
if(FDEV_NAME STREQUAL "enzian")
    if(EN_AVX)
        message("AVX instructions not supported on the Enzian platform currently. Force disable.")
        set(EN_AVX 0)
    endif()
    if(EN_NET)
        set(POLARITY_INV 1)
    endif()
endif()

# Polarity inversion on Enzian (TODO: is it really needed?)
if(FDEV_NAME STREQUAL "enzian")
    set(POL_INV 1)
else()
    set(POL_INV 0)
endif()

##
## Network stack subdirectory (services)
##

if(EN_RDMA OR EN_TCP)
	add_subdirectory(services/network)
endif()

##
## Rest of parameters
##

# Utility channel
if(EN_WB OR EN_TLBF)
    set(EN_UC 1)
else()
    set(EN_UC 0)
endif()

# Total XDMA channels
set(N_CHAN 0)
if(EN_STRM)
    MATH(EXPR N_CHAN "${N_CHAN}+1")
endif()
if(EN_MEM)
    MATH(EXPR N_CHAN "${N_CHAN}+1")
endif()
if(EN_PR)
    MATH(EXPR N_CHAN "${N_CHAN}+1")
endif()
if(EN_UC)
    MATH(EXPR N_CHAN "${N_CHAN}+1")
endif()

# Channel designators
set(NN 0)
set(MULT_STRM_AXI 0)
if(EN_STRM)
    set(STRM_CHAN ${NN})
    MATH(EXPR NN "${NN}+1")
    if(N_STRM_AXI GREATER 1)
        set(MULT_STRM_AXI 1)
    endif()
else()
    set(STRM_CHAN -1)
endif()
if(EN_MEM)
    set(DDR_CHAN ${NN})
    MATH(EXPR NN "${NN}+1")
else()
    set(DDR_CHAN -1)
endif()
if(EN_PR)
    set(PR_CHAN ${NN})
    MATH(EXPR NN "${NN}+1")
else()
    set(PR_CHAN -1)
endif()
if(EN_UC)
    set(UC_CHAN ${NN})
    MATH(EXPR NN "${NN}+1")
else()
    set(UC_CHAN -1)
endif()

set(EN_XCH_0 0)
set(EN_XCH_1 0)
set(EN_XCH_2 0)
set(EN_XCH_3 0)
if(N_CHAN GREATER 0)
    set(EN_XCH_0 1)
endif()
if(N_CHAN GREATER 1)
    set(EN_XCH_1 1)
endif()
if(N_CHAN GREATER 2)
    set(EN_XCH_2 1)
endif()
if(N_CHAN GREATER 3)
    set(EN_XCH_3 1)
endif()