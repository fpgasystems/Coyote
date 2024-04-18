##
## CMAC wrapper
## 

# ILA link
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_link
set_property -dict [list CONFIG.C_PROBE1_WIDTH {4} CONFIG.C_NUM_OF_PROBES {2}  CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_ADV_TRIGGER {true} CONFIG.C_PROBE1_MU_CNT {2} CONFIG.C_PROBE0_MU_CNT {2} CONFIG.ALL_PROBE_SAME_MU_CNT {2}] [get_ips ila_link]

# VIO link
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_link
set_property -dict [list CONFIG.C_PROBE_IN1_WIDTH {4} CONFIG.C_NUM_PROBE_OUT {0} CONFIG.C_PROBE_IN2_WIDTH {3} CONFIG.C_NUM_PROBE_IN {3} ] [get_ips vio_link]

# VIO IP
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_ip
set_property -dict [list CONFIG.C_PROBE_IN1_WIDTH {48} CONFIG.C_PROBE_IN0_WIDTH {32} CONFIG.C_NUM_PROBE_OUT {0} CONFIG.C_NUM_PROBE_IN {2} ] [get_ips vio_ip]

# VIO nstats
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_shell_nstats
set_property -dict [list CONFIG.C_PROBE_IN14_WIDTH {16} CONFIG.C_PROBE_IN13_WIDTH {32} CONFIG.C_PROBE_IN12_WIDTH {32} CONFIG.C_PROBE_IN11_WIDTH {32} CONFIG.C_PROBE_IN10_WIDTH {32} CONFIG.C_PROBE_IN9_WIDTH {32} CONFIG.C_PROBE_IN8_WIDTH {32} CONFIG.C_PROBE_IN7_WIDTH {32} CONFIG.C_PROBE_IN6_WIDTH {32} CONFIG.C_PROBE_IN5_WIDTH {32} CONFIG.C_PROBE_IN4_WIDTH {32} CONFIG.C_PROBE_IN3_WIDTH {32} CONFIG.C_PROBE_IN2_WIDTH {32} CONFIG.C_PROBE_IN1_WIDTH {32} CONFIG.C_PROBE_IN0_WIDTH {32} CONFIG.C_NUM_PROBE_OUT {0} CONFIG.C_NUM_PROBE_IN {16} CONFIG.Component_Name {vio_shell_nstats}] [get_ips vio_shell_nstats]

# CMACs
if {$cfg(fdev) eq "vcu118"} {
    if {$cfg(en_net_0) eq 1} {
        create_ip -name cmac_usplus -vendor xilinx.com -library ip -module_name cmac_usplus_axis_0 
        set_property -dict [list CONFIG.CMAC_CAUI4_MODE {1} CONFIG.ENABLE_PIPELINE_REG {1} CONFIG.NUM_LANES {4x25} CONFIG.GT_REF_CLK_FREQ {156.25} CONFIG.USER_INTERFACE {AXIS} CONFIG.GT_DRP_CLK {100} CONFIG.TX_FLOW_CONTROL {0} CONFIG.RX_FLOW_CONTROL {0} CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y7} CONFIG.GT_GROUP_SELECT {X1Y48~X1Y51} CONFIG.LANE1_GT_LOC {X1Y48} CONFIG.LANE2_GT_LOC {X1Y49} CONFIG.LANE3_GT_LOC {X1Y50} CONFIG.LANE4_GT_LOC {X1Y51} CONFIG.LANE5_GT_LOC {NA} CONFIG.LANE6_GT_LOC {NA} CONFIG.LANE7_GT_LOC {NA} CONFIG.LANE8_GT_LOC {NA} CONFIG.LANE9_GT_LOC {NA} CONFIG.LANE10_GT_LOC {NA} CONFIG.ADD_GT_CNRL_STS_PORTS {1} ] [get_ips cmac_usplus_axis_0]
    }

    if {$cfg(en_net_1) eq 1} {
        create_ip -name cmac_usplus -vendor xilinx.com -library ip -module_name cmac_usplus_axis_0 
        set_property -dict [list CONFIG.CMAC_CAUI4_MODE {1} CONFIG.ENABLE_PIPELINE_REG {1} CONFIG.NUM_LANES {4x25} CONFIG.GT_REF_CLK_FREQ {156.25} CONFIG.USER_INTERFACE {AXIS} CONFIG.GT_DRP_CLK {100} CONFIG.TX_FLOW_CONTROL {0} CONFIG.RX_FLOW_CONTROL {0} CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y7} CONFIG.GT_GROUP_SELECT {X1Y52~X1Y55} CONFIG.LANE1_GT_LOC {X1Y52} CONFIG.LANE2_GT_LOC {X1Y53} CONFIG.LANE3_GT_LOC {X1Y54} CONFIG.LANE4_GT_LOC {X1Y55} CONFIG.LANE5_GT_LOC {NA} CONFIG.LANE6_GT_LOC {NA} CONFIG.LANE7_GT_LOC {NA} CONFIG.LANE8_GT_LOC {NA} CONFIG.LANE9_GT_LOC {NA} CONFIG.LANE10_GT_LOC {NA} CONFIG.ADD_GT_CNRL_STS_PORTS {1} ] [get_ips cmac_usplus_axis_0]
    }
}

if {$cfg(fdev) eq "u50"} {
    if {$cfg(en_net_0) eq 1} {
        create_ip -name cmac_usplus -vendor xilinx.com -library ip -module_name cmac_usplus_axis_0 
        set_property -dict [list CONFIG.CMAC_CAUI4_MODE {1} CONFIG.ENABLE_PIPELINE_REG {1} CONFIG.NUM_LANES {4x25} CONFIG.GT_REF_CLK_FREQ {161.1328125} CONFIG.USER_INTERFACE {AXIS} CONFIG.GT_DRP_CLK {100} CONFIG.TX_FLOW_CONTROL {0} CONFIG.RX_FLOW_CONTROL {0} CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y4} CONFIG.GT_GROUP_SELECT {X0Y28~X0Y31} CONFIG.LANE1_GT_LOC {X0Y28} CONFIG.LANE2_GT_LOC {X0Y29} CONFIG.LANE3_GT_LOC {X0Y30} CONFIG.LANE4_GT_LOC {X0Y31} CONFIG.ADD_GT_CNRL_STS_PORTS {1} ] [get_ips cmac_usplus_axis_0]
    }
    # create_ip -name cmac_usplus -vendor xilinx.com -library ip -module_name cmac_usplus_axis_0 
    # set_property -dict [list CONFIG.CMAC_CAUI4_MODE {1} CONFIG.ENABLE_PIPELINE_REG {1} CONFIG.NUM_LANES {4x25} CONFIG.GT_REF_CLK_FREQ {161.1328125} CONFIG.USER_INTERFACE {AXIS} CONFIG.GT_DRP_CLK {100} CONFIG.TX_FLOW_CONTROL {0} CONFIG.RX_FLOW_CONTROL {0} CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y7} CONFIG.GT_GROUP_SELECT {X1Y40~X1Y43} CONFIG.LANE1_GT_LOC {X1Y40} CONFIG.LANE2_GT_LOC {X1Y41} CONFIG.LANE3_GT_LOC {X1Y42} CONFIG.LANE4_GT_LOC {X1Y43} CONFIG.ADD_GT_CNRL_STS_PORTS {1} ] [get_ips cmac_usplus_axis_0]
}

if {$cfg(fdev) eq "u55c"} {
    if {$cfg(en_net_0) eq 1} {
        create_ip -name cmac_usplus -vendor xilinx.com -library ip -module_name cmac_usplus_axis_0 
        set_property -dict [list CONFIG.CMAC_CAUI4_MODE {1} CONFIG.ENABLE_PIPELINE_REG {1} CONFIG.NUM_LANES {4x25} CONFIG.GT_REF_CLK_FREQ {161.1328125} CONFIG.USER_INTERFACE {AXIS} CONFIG.GT_DRP_CLK {100} CONFIG.TX_FLOW_CONTROL {0} CONFIG.RX_FLOW_CONTROL {0} CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y5} CONFIG.GT_GROUP_SELECT {X0Y24~X0Y27} CONFIG.LANE1_GT_LOC {X0Y24} CONFIG.LANE2_GT_LOC {X0Y25} CONFIG.LANE3_GT_LOC {X0Y26} CONFIG.LANE4_GT_LOC {X0Y27} CONFIG.ADD_GT_CNRL_STS_PORTS {1}  ] [get_ips cmac_usplus_axis_0]
    }

    if {$cfg(en_net_1) eq 1} {
        create_ip -name cmac_usplus -vendor xilinx.com -library ip -module_name cmac_usplus_axis_0 
        set_property -dict [list CONFIG.CMAC_CAUI4_MODE {1} CONFIG.ENABLE_PIPELINE_REG {1} CONFIG.NUM_LANES {4x25} CONFIG.GT_REF_CLK_FREQ {161.1328125} CONFIG.USER_INTERFACE {AXIS} CONFIG.GT_DRP_CLK {100} CONFIG.TX_FLOW_CONTROL {0} CONFIG.RX_FLOW_CONTROL {0} CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y5} CONFIG.GT_GROUP_SELECT {X0Y28~X0Y31} CONFIG.LANE1_GT_LOC {X0Y28} CONFIG.LANE2_GT_LOC {X0Y29} CONFIG.LANE3_GT_LOC {X0Y30} CONFIG.LANE4_GT_LOC {X0Y31} CONFIG.ADD_GT_CNRL_STS_PORTS {1}  ] [get_ips cmac_usplus_axis_0]
    }
}



if {$cfg(fdev) eq "u200"} {
    if {$cfg(en_net_0) eq 1} {
        create_ip -name cmac_usplus -vendor xilinx.com -library ip -module_name cmac_usplus_axis_0 
        set_property -dict [list CONFIG.CMAC_CAUI4_MODE {1} CONFIG.ENABLE_PIPELINE_REG {1} CONFIG.NUM_LANES {4x25} CONFIG.GT_REF_CLK_FREQ {161.1328125} CONFIG.USER_INTERFACE {AXIS} CONFIG.GT_DRP_CLK {100} CONFIG.TX_FLOW_CONTROL {0} CONFIG.RX_FLOW_CONTROL {0} CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y7} CONFIG.GT_GROUP_SELECT {X1Y44~X1Y47} CONFIG.LANE1_GT_LOC {X1Y44} CONFIG.LANE2_GT_LOC {X1Y45} CONFIG.LANE3_GT_LOC {X1Y46} CONFIG.LANE4_GT_LOC {X1Y47} CONFIG.ADD_GT_CNRL_STS_PORTS {1} ] [get_ips cmac_usplus_axis_0]
    }

    if {$cfg(en_net_1) eq 1} {
        create_ip -name cmac_usplus -vendor xilinx.com -library ip -module_name cmac_usplus_axis_0
        set_property -dict [list CONFIG.CMAC_CAUI4_MODE {1} CONFIG.ENABLE_PIPELINE_REG {1} CONFIG.NUM_LANES {4x25} CONFIG.GT_REF_CLK_FREQ {161.1328125} CONFIG.USER_INTERFACE {AXIS} CONFIG.GT_DRP_CLK {100} CONFIG.TX_FLOW_CONTROL {0} CONFIG.RX_FLOW_CONTROL {0} CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y7} CONFIG.GT_GROUP_SELECT {X1Y40~X1Y43} CONFIG.LANE1_GT_LOC {X1Y40} CONFIG.LANE2_GT_LOC {X1Y41} CONFIG.LANE3_GT_LOC {X1Y42} CONFIG.LANE4_GT_LOC {X1Y43} CONFIG.ADD_GT_CNRL_STS_PORTS {1} ] [get_ips cmac_usplus_axis_0]
    }
}

if {$cfg(fdev) eq "u250"} {
    if {$cfg(en_net_0) eq 1} {
        create_ip -name cmac_usplus -vendor xilinx.com -library ip -module_name cmac_usplus_axis_0 
        set_property -dict [list CONFIG.CMAC_CAUI4_MODE {1} CONFIG.ENABLE_PIPELINE_REG {1} CONFIG.NUM_LANES {4x25} CONFIG.GT_REF_CLK_FREQ {156.25} CONFIG.USER_INTERFACE {AXIS} CONFIG.GT_DRP_CLK {100} CONFIG.TX_FLOW_CONTROL {0} CONFIG.RX_FLOW_CONTROL {0} CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y7} CONFIG.GT_GROUP_SELECT {X1Y44~X1Y47} CONFIG.LANE1_GT_LOC {X1Y44} CONFIG.LANE2_GT_LOC {X1Y45} CONFIG.LANE3_GT_LOC {X1Y46} CONFIG.LANE4_GT_LOC {X1Y47} CONFIG.ADD_GT_CNRL_STS_PORTS {1} ] [get_ips cmac_usplus_axis_0]
    }

    if {$cfg(en_net_1) eq 1} {
        create_ip -name cmac_usplus -vendor xilinx.com -library ip -module_name cmac_usplus_axis_0 
        set_property -dict [list CONFIG.CMAC_CAUI4_MODE {1} CONFIG.ENABLE_PIPELINE_REG {1} CONFIG.NUM_LANES {4x25} CONFIG.GT_REF_CLK_FREQ {156.25} CONFIG.USER_INTERFACE {AXIS} CONFIG.GT_DRP_CLK {100} CONFIG.TX_FLOW_CONTROL {0} CONFIG.RX_FLOW_CONTROL {0} CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y7} CONFIG.GT_GROUP_SELECT {X1Y40~X1Y43} CONFIG.LANE1_GT_LOC {X1Y40} CONFIG.LANE2_GT_LOC {X1Y41} CONFIG.LANE3_GT_LOC {X1Y42} CONFIG.LANE4_GT_LOC {X1Y43} CONFIG.ADD_GT_CNRL_STS_PORTS {1} ] [get_ips cmac_usplus_axis_0]
    }
}

if {$cfg(fdev) eq "u280"} {
    if {$cfg(en_net_0) eq 1} {
        create_ip -name cmac_usplus -vendor xilinx.com -library ip -module_name cmac_usplus_axis_0 
        set_property -dict [list CONFIG.CMAC_CAUI4_MODE {1} CONFIG.ENABLE_PIPELINE_REG {1} CONFIG.NUM_LANES {4x25} CONFIG.GT_REF_CLK_FREQ {156.25} CONFIG.USER_INTERFACE {AXIS} CONFIG.GT_DRP_CLK {100} CONFIG.TX_FLOW_CONTROL {0} CONFIG.RX_FLOW_CONTROL {0} CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y6} CONFIG.GT_GROUP_SELECT {X0Y40~X0Y43} CONFIG.LANE1_GT_LOC {X0Y40} CONFIG.LANE2_GT_LOC {X0Y41} CONFIG.LANE3_GT_LOC {X0Y42} CONFIG.LANE4_GT_LOC {X0Y43} CONFIG.ADD_GT_CNRL_STS_PORTS {1}  ] [get_ips cmac_usplus_axis_0]
    }

    if {$cfg(en_net_1) eq 1} {
        create_ip -name cmac_usplus -vendor xilinx.com -library ip -module_name cmac_usplus_axis_0 
        set_property -dict [list CONFIG.CMAC_CAUI4_MODE {1} CONFIG.ENABLE_PIPELINE_REG {1} CONFIG.NUM_LANES {4x25} CONFIG.GT_REF_CLK_FREQ {156.25} CONFIG.USER_INTERFACE {AXIS} CONFIG.GT_DRP_CLK {100} CONFIG.TX_FLOW_CONTROL {0} CONFIG.RX_FLOW_CONTROL {0} CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y6} CONFIG.GT_GROUP_SELECT {X0Y44~X0Y47} CONFIG.LANE1_GT_LOC {X0Y44} CONFIG.LANE2_GT_LOC {X0Y45} CONFIG.LANE3_GT_LOC {X0Y46} CONFIG.LANE4_GT_LOC {X0Y47} CONFIG.ADD_GT_CNRL_STS_PORTS {1}  ] [get_ips cmac_usplus_axis_0]
    }
}

if {$cfg(fdev) eq "enzian"} {
    if {$cfg(en_net_0) eq 1} {
        create_ip -name cmac_usplus -vendor xilinx.com -library ip -module_name cmac_usplus_axis_0 
        set_property -dict [list CONFIG.CMAC_CAUI4_MODE {1} CONFIG.ENABLE_PIPELINE_REG {1} CONFIG.NUM_LANES {4x25} CONFIG.GT_REF_CLK_FREQ {322.265625} CONFIG.USER_INTERFACE {AXIS} CONFIG.GT_DRP_CLK {100} CONFIG.TX_FLOW_CONTROL {0} CONFIG.RX_FLOW_CONTROL {0} CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y2} CONFIG.GT_GROUP_SELECT {X0Y8~X0Y11} CONFIG.LANE1_GT_LOC {X0Y8} CONFIG.LANE2_GT_LOC {X0Y9} CONFIG.LANE3_GT_LOC {X0Y10} CONFIG.LANE4_GT_LOC {X0Y11} CONFIG.ADD_GT_CNRL_STS_PORTS {1} ] [get_ips cmac_usplus_axis_0]
    }

    if {$cfg(en_net_1) eq 1} {
        create_ip -name cmac_usplus -vendor xilinx.com -library ip -module_name cmac_usplus_axis_0 
        set_property -dict [list CONFIG.CMAC_CAUI4_MODE {1} CONFIG.ENABLE_PIPELINE_REG {1} CONFIG.NUM_LANES {4x25} CONFIG.GT_REF_CLK_FREQ {322.265625} CONFIG.USER_INTERFACE {AXIS} CONFIG.GT_DRP_CLK {100} CONFIG.TX_FLOW_CONTROL {0} CONFIG.RX_FLOW_CONTROL {0} CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y3} CONFIG.GT_GROUP_SELECT {X0Y20~X0Y23} CONFIG.LANE1_GT_LOC {X0Y20} CONFIG.LANE2_GT_LOC {X0Y21} CONFIG.LANE3_GT_LOC {X0Y22} CONFIG.LANE4_GT_LOC {X0Y23} CONFIG.ADD_GT_CNRL_STS_PORTS {1} ] [get_ips cmac_usplus_axis_0]
    }
}

##
## Network module
##

## FIFOs
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_512_cc_rx
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.IS_ACLK_ASYNC {0} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.HAS_WR_DATA_COUNT {1} CONFIG.HAS_PROG_FULL {1} CONFIG.PROG_FULL_THRESH {416}] [get_ips axis_data_fifo_512_cc_rx]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_512_cc_tx
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.IS_ACLK_ASYNC {0} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1}] [get_ips axis_data_fifo_512_cc_tx]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_pkg_fifo_512 
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_MODE {2} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_pkg_fifo_512]

## Frame padding
create_ip -name ethernet_frame_padding_512 -vendor ethz.systems.fpga -library hls -version 0.1 -module_name ethernet_frame_padding_512_ip 

## Fifos
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_512_used
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.HAS_WR_DATA_COUNT {1} CONFIG.Component_Name {axis_data_fifo_512_used}] [get_ips axis_data_fifo_512_used]

##
## RDMA
##

if {$cfg(en_rdma) eq 1} {
    create_ip -name rocev2 -vendor ethz.systems.fpga -library hls -version 0.82 -module_name rocev2_ip 
}

# Cmd
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_req_512_used
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {32} CONFIG.HAS_WR_DATA_COUNT {1} ] [get_ips axis_data_fifo_req_512_used]

#create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_req_256_used
#set_property -dict [list CONFIG.TDATA_NUM_BYTES {32} CONFIG.FIFO_DEPTH {32} CONFIG.HAS_WR_DATA_COUNT {1} ] [get_ips axis_data_fifo_req_256_used]

## Crossings
create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_rdma_16
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_rdma_16]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_rdma_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_rdma_32]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_rdma_128
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_rdma_128]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_rdma_184
set_property -dict [list CONFIG.TDATA_NUM_BYTES {23} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_rdma_184]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_rdma_256
set_property -dict [list CONFIG.TDATA_NUM_BYTES {32} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_rdma_256]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_rdma_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_rdma_512]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_rdma_data_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.SYNCHRONIZATION_STAGES {4}] [get_ips axis_clock_converter_rdma_data_512]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axisr_clock_converter_rdma_data_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.SYNCHRONIZATION_STAGES {4} CONFIG.TID_WIDTH {6}] [get_ips axisr_clock_converter_rdma_data_512]

## Crossings FIFO
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rdma_ccross_8
set_property -dict [list CONFIG.TDATA_NUM_BYTES {1} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_rdma_ccross_8]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rdma_ccross_16
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_rdma_ccross_16]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rdma_ccross_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_rdma_ccross_32]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rdma_ccross_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_rdma_ccross_96]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rdma_ccross_128
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_rdma_ccross_128]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rdma_ccross_184
set_property -dict [list CONFIG.TDATA_NUM_BYTES {23} CONFIG.FIFO_DEPTH {32} CONFIG.IS_ACLK_ASYNC {1} ] [get_ips axis_data_fifo_rdma_ccross_184]


create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rdma_ccross_256
set_property -dict [list CONFIG.TDATA_NUM_BYTES {32} CONFIG.FIFO_DEPTH {32} CONFIG.IS_ACLK_ASYNC {1} ] [get_ips axis_data_fifo_rdma_ccross_256]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rdma_ccross_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {32} CONFIG.IS_ACLK_ASYNC {1} ] [get_ips axis_data_fifo_rdma_ccross_512]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rdma_ccross_data_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {512} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_data_fifo_rdma_ccross_data_512]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axisr_data_fifo_rdma_ccross_data_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {512} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.TID_WIDTH {6}] [get_ips axisr_data_fifo_rdma_ccross_data_512]


## Slicing
create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_rdma_16
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_rdma_16]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_rdma_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_rdma_32]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_rdma_128
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_rdma_128]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_rdma_184
set_property -dict [list CONFIG.TDATA_NUM_BYTES {23} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_rdma_184]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_rdma_256
set_property -dict [list CONFIG.TDATA_NUM_BYTES {32} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_rdma_256]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_rdma_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_rdma_512]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_rdma_data_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.REG_CONFIG {8} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_register_slice_rdma_data_512]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axisr_register_slice_rdma_data_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.REG_CONFIG {8} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.TID_WIDTH {6}] [get_ips axisr_register_slice_rdma_data_512]

## Buffering
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rdma_8
set_property -dict [list CONFIG.TDATA_NUM_BYTES {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_rdma_8]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rdma_16
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_rdma_16]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rdma_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_rdma_32]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rdma_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_rdma_96]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rdma_128
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_rdma_128]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rdma_184
set_property -dict [list CONFIG.TDATA_NUM_BYTES {23} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_rdma_184]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rdma_256
set_property -dict [list CONFIG.TDATA_NUM_BYTES {32} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_rdma_256]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rdma_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_rdma_512]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rdma_544
set_property -dict [list CONFIG.TDATA_NUM_BYTES {68} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_rdma_544]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rdma_data_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {512} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1}] [get_ips axis_data_fifo_rdma_data_512]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axisr_data_fifo_rdma_data_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {512} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.TID_WIDTH {6}] [get_ips axisr_data_fifo_rdma_data_512]

## Rem
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_cnfg_rdma_16
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.HAS_WR_DATA_COUNT {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_cnfg_rdma_16]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_cnfg_rdma_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.HAS_WR_DATA_COUNT {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_cnfg_rdma_32]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_cnfg_rdma_128
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.HAS_WR_DATA_COUNT {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_cnfg_rdma_128]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_cnfg_rdma_256
set_property -dict [list CONFIG.TDATA_NUM_BYTES {32} CONFIG.HAS_WR_DATA_COUNT {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_cnfg_rdma_256]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_cnfg_rdma_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.HAS_WR_DATA_COUNT {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_cnfg_rdma_512]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_cnfg_rdma_rec_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.HAS_WR_DATA_COUNT {1} CONFIG.FIFO_DEPTH {32} CONFIG.TID_WIDTH {6}] [get_ips axis_data_fifo_cnfg_rdma_rec_512]

##
## TCP/IP
##

## Stack
if {$cfg(en_tcp) eq 1} {
    create_ip -name toe -vendor ethz.systems -library hls -version 1.6 -module_name toe_ip 

    create_ip -name hash_table -vendor ethz.systems.fpga -library hls -version 1.0 -module_name hash_table_ip 
}

## Crossings
create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_tcp_8
set_property -dict [list CONFIG.TDATA_NUM_BYTES {1} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_tcp_8]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_tcp_16
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_tcp_16]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_tcp_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_tcp_32]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_tcp_40
set_property -dict [list CONFIG.TDATA_NUM_BYTES {5} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_tcp_40]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_tcp_48
set_property -dict [list CONFIG.TDATA_NUM_BYTES {6} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_tcp_48]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_tcp_64
set_property -dict [list CONFIG.TDATA_NUM_BYTES {8} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_tcp_64]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_tcp_72
set_property -dict [list CONFIG.TDATA_NUM_BYTES {9} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_tcp_72]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_tcp_88
set_property -dict [list CONFIG.TDATA_NUM_BYTES {11} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_tcp_88]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_tcp_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_tcp_96]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_tcp_104
set_property -dict [list CONFIG.TDATA_NUM_BYTES {13} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_tcp_104]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_tcp_128
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_tcp_128]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_tcp_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_tcp_512]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axisr_clock_converter_tcp_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.SYNCHRONIZATION_STAGES {4} CONFIG.TID_WIDTH {6}] [get_ips axisr_clock_converter_tcp_512]

## Crossings FIFO
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_ccross_8
set_property -dict [list CONFIG.TDATA_NUM_BYTES {1} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_ccross_8]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_ccross_16
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_ccross_16]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_ccross_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_ccross_32]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_ccross_40
set_property -dict [list CONFIG.TDATA_NUM_BYTES {5} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_ccross_40]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_ccross_48
set_property -dict [list CONFIG.TDATA_NUM_BYTES {6} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_ccross_48]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_ccross_64
set_property -dict [list CONFIG.TDATA_NUM_BYTES {8} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_ccross_64]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_ccross_72
set_property -dict [list CONFIG.TDATA_NUM_BYTES {9} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_ccross_72]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_ccross_88
set_property -dict [list CONFIG.TDATA_NUM_BYTES {11} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_ccross_88]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_ccross_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_ccross_96]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_ccross_104
set_property -dict [list CONFIG.TDATA_NUM_BYTES {13} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_ccross_104]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_ccross_128
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_ccross_128]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_ccross_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {512} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_data_fifo_tcp_ccross_512]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axisr_data_fifo_tcp_ccross_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {512} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.TID_WIDTH {6}] [get_ips axisr_data_fifo_tcp_ccross_512]

## Slicing
create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_tcp_8 
set_property -dict [list CONFIG.TDATA_NUM_BYTES {1} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_tcp_8]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_tcp_16 
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_tcp_16]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_tcp_32 
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_tcp_32]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_tcp_40
set_property -dict [list CONFIG.TDATA_NUM_BYTES {5} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_tcp_40]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_tcp_48 
set_property -dict [list CONFIG.TDATA_NUM_BYTES {6} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_tcp_48]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_tcp_64
set_property -dict [list CONFIG.TDATA_NUM_BYTES {8} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_tcp_64]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_tcp_72 
set_property -dict [list CONFIG.TDATA_NUM_BYTES {9} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_tcp_72]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_tcp_88 
set_property -dict [list CONFIG.TDATA_NUM_BYTES {11} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_tcp_88]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_tcp_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_tcp_96]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_tcp_104
set_property -dict [list CONFIG.TDATA_NUM_BYTES {13} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_tcp_104]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_tcp_128
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_tcp_128]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_tcp_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.REG_CONFIG {8} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_register_slice_tcp_512]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axisr_register_slice_tcp_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.REG_CONFIG {8} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.TID_WIDTH {6}] [get_ips axisr_register_slice_tcp_512]

## Buffering
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_8
set_property -dict [list CONFIG.TDATA_NUM_BYTES {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_8]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_16
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_16]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_32]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_40
set_property -dict [list CONFIG.TDATA_NUM_BYTES {5} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_40]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_48
set_property -dict [list CONFIG.TDATA_NUM_BYTES {6} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_48]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_64
set_property -dict [list CONFIG.TDATA_NUM_BYTES {8} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_64]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_72
set_property -dict [list CONFIG.TDATA_NUM_BYTES {9} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_72]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_88
set_property -dict [list CONFIG.TDATA_NUM_BYTES {11} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_88]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_96]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_104
set_property -dict [list CONFIG.TDATA_NUM_BYTES {13} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_104]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_128
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_tcp_128]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tcp_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {512} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_data_fifo_tcp_512]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axisr_data_fifo_tcp_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {512} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.TID_WIDTH {6}] [get_ips axisr_data_fifo_tcp_512]

## Rem 
create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_tcp_mem_104 
set_property -dict [list CONFIG.TDATA_NUM_BYTES {13} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_register_slice_tcp_mem_104]

create_ip -name axi_datamover -vendor xilinx.com -library ip -version 5.1 -module_name axi_datamover_mem 
set_property -dict [list  CONFIG.c_mm2s_stscmd_is_async {true} CONFIG.c_m_axi_mm2s_data_width {512} CONFIG.c_mm2s_include_sf {false} CONFIG.c_m_axi_mm2s_id_width {6} CONFIG.c_m_axis_mm2s_tdata_width {512} CONFIG.c_mm2s_burst_size {64} CONFIG.c_mm2s_btt_used {23} CONFIG.c_s2mm_stscmd_is_async {true} CONFIG.c_m_axi_s2mm_data_width {512} CONFIG.c_s_axis_s2mm_tdata_width {512} CONFIG.c_s2mm_burst_size {64} CONFIG.c_s2mm_btt_used {23} CONFIG.c_s2mm_include_sf {false} CONFIG.c_m_axi_s2mm_id_width {6} CONFIG.c_addr_width {64}] [get_ips axi_datamover_mem]

create_ip -name axi_datamover -vendor xilinx.com -library ip -version 5.1 -module_name axi_datamover_mem_unaligned 
set_property -dict [list  CONFIG.c_mm2s_stscmd_is_async {true} CONFIG.c_mm2s_include_sf {false} CONFIG.c_m_axi_mm2s_id_width {6} CONFIG.c_m_axi_s2mm_id_width {6} CONFIG.c_m_axi_mm2s_data_width {512} CONFIG.c_m_axis_mm2s_tdata_width {512} CONFIG.c_include_mm2s_dre {true} CONFIG.c_mm2s_burst_size {64} CONFIG.c_mm2s_btt_used {23} CONFIG.c_s2mm_stscmd_is_async {true} CONFIG.c_m_axi_s2mm_data_width {512} CONFIG.c_s_axis_s2mm_tdata_width {512} CONFIG.c_include_s2mm_dre {true} CONFIG.c_s2mm_burst_size {64} CONFIG.c_s2mm_btt_used {23} CONFIG.c_s2mm_include_sf {false} CONFIG.c_addr_width {64}] [get_ips axi_datamover_mem_unaligned]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_512_d1024 
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {1024} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.HAS_WR_DATA_COUNT {1} CONFIG.HAS_RD_DATA_COUNT {1} ] [get_ips axis_data_fifo_512_d1024]

create_ip -name axi_interconnect -vendor xilinx.com -library ip -version 1.7 -module_name axi_merge_2to1
set_property -dict [list CONFIG.AXI_ADDR_WIDTH {64} CONFIG.INTERCONNECT_DATA_WIDTH {512} CONFIG.S00_AXI_DATA_WIDTH {512} CONFIG.S01_AXI_DATA_WIDTH {512} CONFIG.M00_AXI_DATA_WIDTH {512} CONFIG.S00_AXI_REGISTER {1} CONFIG.S01_AXI_REGISTER {1} CONFIG.M00_AXI_REGISTER {1} ] [get_ips axi_merge_2to1]

##
## Network top
##

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_net_ccross_early_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {512} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_data_fifo_net_ccross_early_512]

## Crossings
create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_net_8
set_property -dict [list CONFIG.TDATA_NUM_BYTES {1} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_net_8]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_net_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_net_32]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_net_48
set_property -dict [list CONFIG.TDATA_NUM_BYTES {6} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_net_48]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_net_56
set_property -dict [list CONFIG.TDATA_NUM_BYTES {7} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_net_56]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_net_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.SYNCHRONIZATION_STAGES {4} ] [get_ips axis_clock_converter_net_512]

## Crossings FIFO
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_net_ccross_8
set_property -dict [list CONFIG.TDATA_NUM_BYTES {1} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_net_ccross_8]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_net_ccross_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_net_ccross_32]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_net_ccross_48
set_property -dict [list CONFIG.TDATA_NUM_BYTES {6} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_net_ccross_48]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_net_ccross_56
set_property -dict [list CONFIG.TDATA_NUM_BYTES {7} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_net_ccross_56]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_net_ccross_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.IS_ACLK_ASYNC {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_net_ccross_512]

## Slicing
create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_net_8
set_property -dict [list CONFIG.TDATA_NUM_BYTES {1} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_net_8]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_net_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_net_32]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_net_48
set_property -dict [list CONFIG.TDATA_NUM_BYTES {6} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_net_48]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_net_56
set_property -dict [list CONFIG.TDATA_NUM_BYTES {7} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_net_56]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_net_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_net_512]

## Buffering
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_net_8
set_property -dict [list CONFIG.TDATA_NUM_BYTES {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_net_8]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_net_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_net_32]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_net_48
set_property -dict [list CONFIG.TDATA_NUM_BYTES {6} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_net_48]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_net_56
set_property -dict [list CONFIG.TDATA_NUM_BYTES {7} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_net_56]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_net_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_net_512]

##
## Network stack
##

create_ip -name ip_handler -vendor ethz.systems.fpga -library hls -version 2.0 -module_name ip_handler_ip 

create_ip -name mac_ip_encode -vendor ethz.systems.fpga -library hls -version 2.0 -module_name mac_ip_encode_ip 

create_ip -name icmp_server -vendor xilinx.labs -library hls -version 1.67 -module_name icmp_server_ip 

create_ip -name arp_server_subnet -vendor ethz.systems.fpga -library hls -version 1.1 -module_name arp_server_subnet_ip 

create_ip -name axis_dwidth_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_512_to_64_converter 
set_property -dict [list CONFIG.S_TDATA_NUM_BYTES {64} CONFIG.M_TDATA_NUM_BYTES {8} CONFIG.HAS_TLAST {1} CONFIG.HAS_TKEEP {1} CONFIG.HAS_MI_TKEEP {1} ] [get_ips axis_512_to_64_converter]

create_ip -name axis_dwidth_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_64_to_512_converter 
set_property -dict [list CONFIG.S_TDATA_NUM_BYTES {8} CONFIG.M_TDATA_NUM_BYTES {64} CONFIG.HAS_TLAST {1} CONFIG.HAS_TKEEP {1} CONFIG.HAS_MI_TKEEP {1} CONFIG.TDEST_WIDTH {1} ] [get_ips axis_64_to_512_converter]

create_ip -name axis_interconnect -vendor xilinx.com -library ip -version 1.1 -module_name axis_interconnect_512_4to1 
set_property -dict [list CONFIG.C_NUM_SI_SLOTS {4} CONFIG.SWITCH_TDATA_NUM_BYTES {64} CONFIG.HAS_TSTRB {false} CONFIG.HAS_TID {false} CONFIG.HAS_TDEST {false} CONFIG.SWITCH_PACKET_MODE {true} CONFIG.C_SWITCH_MAX_XFERS_PER_ARB {0} CONFIG.C_M00_AXIS_REG_CONFIG {1} CONFIG.C_S00_AXIS_REG_CONFIG {1} CONFIG.C_S01_AXIS_REG_CONFIG {1} CONFIG.C_S02_AXIS_REG_CONFIG {1} CONFIG.C_S03_AXIS_REG_CONFIG {1} CONFIG.C_SWITCH_NUM_CYCLES_TIMEOUT {0} CONFIG.M00_AXIS_TDATA_NUM_BYTES {64} CONFIG.S00_AXIS_TDATA_NUM_BYTES {64} CONFIG.S01_AXIS_TDATA_NUM_BYTES {64} CONFIG.S02_AXIS_TDATA_NUM_BYTES {64} CONFIG.S03_AXIS_TDATA_NUM_BYTES {64} CONFIG.M00_S01_CONNECTIVITY {true} CONFIG.M00_S02_CONNECTIVITY {true} CONFIG.M00_S03_CONNECTIVITY {true}] [get_ips axis_interconnect_512_4to1]

create_ip -name axis_interconnect -vendor xilinx.com -library ip -version 1.1 -module_name axis_interconnect_512_2to1 
set_property -dict [list CONFIG.C_NUM_SI_SLOTS {2} CONFIG.SWITCH_TDATA_NUM_BYTES {64} CONFIG.HAS_TSTRB {false} CONFIG.HAS_TID {false} CONFIG.HAS_TDEST {false} CONFIG.SWITCH_PACKET_MODE {true} CONFIG.C_SWITCH_MAX_XFERS_PER_ARB {0} CONFIG.C_M00_AXIS_REG_CONFIG {1} CONFIG.C_S00_AXIS_REG_CONFIG {1} CONFIG.C_S01_AXIS_REG_CONFIG {1} CONFIG.C_SWITCH_NUM_CYCLES_TIMEOUT {0} CONFIG.M00_AXIS_TDATA_NUM_BYTES {64} CONFIG.S00_AXIS_TDATA_NUM_BYTES {64} CONFIG.S01_AXIS_TDATA_NUM_BYTES {64} CONFIG.M00_S01_CONNECTIVITY {true}] [get_ips axis_interconnect_512_2to1]

create_ip -name axis_interconnect -vendor xilinx.com -library ip -version 1.1 -module_name axis_interconnect_merger_512
set_property -dict [list  CONFIG.C_NUM_SI_SLOTS {2} CONFIG.SWITCH_TDATA_NUM_BYTES {64} CONFIG.HAS_TSTRB {false} CONFIG.HAS_TKEEP {false} CONFIG.HAS_TLAST {false} CONFIG.HAS_TID {false} CONFIG.HAS_TDEST {false} CONFIG.SWITCH_PACKET_MODE {false} CONFIG.C_SWITCH_MAX_XFERS_PER_ARB {1} CONFIG.C_SWITCH_NUM_CYCLES_TIMEOUT {0} CONFIG.M00_AXIS_TDATA_NUM_BYTES {68} CONFIG.S00_AXIS_TDATA_NUM_BYTES {68} CONFIG.S01_AXIS_TDATA_NUM_BYTES {68} CONFIG.M00_S01_CONNECTIVITY {true}] [get_ips axis_interconnect_merger_512]

##
## Reserve
##

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_drop_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.FIFO_DEPTH {128} ] [get_ips axis_data_fifo_drop_32]

#create_ip -name iperf_client -vendor ethz.systems.fpga -library hls -version 1.0 -module_name iperf_client_ip 

#create_ip -name ipv4 -vendor ethz.systems.fpga -library hls -version 0.1 -module_name ipv4_ip 

#create_ip -name udp -vendor ethz.systems.fpga -library hls -version 0.4 -module_name udp_ip 

#create_ip -name iperf_udp -vendor ethz.systems.fpga -library hls -version 0.9 -module_name iperf_udp_ip 

#create_ip -name udpAppMux -vendor xilinx.labs -library hls -version 1.05 -module_name udpAppMux_0 

#create_ip -name dhcp_client -vendor xilinx.labs -library hls -version 1.05 -module_name dhcp_client_ip 

#update_compile_order -fileset sources_1