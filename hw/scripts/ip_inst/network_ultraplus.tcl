#Network
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_64_cc -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {8} CONFIG.IS_ACLK_ASYNC {1} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.SYNCHRONIZATION_STAGES {3} CONFIG.Component_Name {axis_data_fifo_64_cc}] [get_ips axis_data_fifo_64_cc]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_data_fifo_64_cc/axis_data_fifo_64_cc.xci]

create_ip -name fifo_generator -vendor xilinx.com -library ip -version 13.2 -module_name axis_sync_fifo -dir $device_ip_dir
set_property -dict [list CONFIG.INTERFACE_TYPE {AXI_STREAM} CONFIG.FIFO_Implementation_axis {Common_Clock_Block_RAM} CONFIG.TDATA_NUM_BYTES {8} CONFIG.TUSER_WIDTH {0} CONFIG.Enable_TLAST {true} CONFIG.HAS_TKEEP {true} CONFIG.Enable_Data_Counts_axis {true} CONFIG.Reset_Type {Asynchronous_Reset} CONFIG.Full_Flags_Reset_Value {1} CONFIG.TSTRB_WIDTH {8} CONFIG.TKEEP_WIDTH {8} CONFIG.FIFO_Implementation_wach {Common_Clock_Distributed_RAM} CONFIG.Full_Threshold_Assert_Value_wach {15} CONFIG.Empty_Threshold_Assert_Value_wach {14} CONFIG.FIFO_Implementation_wrch {Common_Clock_Distributed_RAM} CONFIG.Full_Threshold_Assert_Value_wrch {15} CONFIG.Empty_Threshold_Assert_Value_wrch {14} CONFIG.FIFO_Implementation_rach {Common_Clock_Distributed_RAM} CONFIG.Full_Threshold_Assert_Value_rach {15} CONFIG.Empty_Threshold_Assert_Value_rach {14}] [get_ips axis_sync_fifo]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_sync_fifo/axis_sync_fifo.xci]
update_compile_order -fileset sources_1

create_ip -name fifo_generator -vendor xilinx.com -library ip -version 13.2 -module_name cmd_fifo_xgemac_rxif -dir $device_ip_dir
set_property -dict [list CONFIG.Fifo_Implementation {Common_Clock_Block_RAM} CONFIG.Input_Data_Width {16} CONFIG.Output_Data_Width {16} CONFIG.Reset_Type {Asynchronous_Reset} CONFIG.Full_Flags_Reset_Value {1} CONFIG.Use_Embedded_Registers {false} CONFIG.Full_Threshold_Assert_Value {1022} CONFIG.Full_Threshold_Negate_Value {1021} CONFIG.Enable_Safety_Circuit {false}] [get_ips cmd_fifo_xgemac_rxif]
generate_target {instantiation_template} [get_files $device_ip_dir/cmd_fifo_xgemac_rxif/cmd_fifo_xgemac_rxif.xci]
update_compile_order -fileset sources_1

create_ip -name fifo_generator -vendor xilinx.com -library ip -version 13.2 -module_name cmd_fifo_xgemac_txif -dir $device_ip_dir
set_property -dict [list CONFIG.Fifo_Implementation {Common_Clock_Block_RAM} CONFIG.Input_Data_Width {1} CONFIG.Output_Data_Width {1} CONFIG.Reset_Type {Asynchronous_Reset} CONFIG.Full_Flags_Reset_Value {1} CONFIG.Full_Threshold_Assert_Value {1022} CONFIG.Full_Threshold_Negate_Value {1021} CONFIG.Enable_Safety_Circuit {false}] [get_ips cmd_fifo_xgemac_txif]
generate_target {instantiation_template} [get_files $device_ip_dir/cmd_fifo_xgemac_txif/cmd_fifo_xgemac_txif.xci]
update_compile_order -fileset sources_1

#create_ip -name ethernet_frame_padding -vendor ethz.systems.fpga -library hls -version 0.1 -module_name ethernet_frame_padding_ip -dir $device_ip_dir
#generate_target {instantiation_template} [get_files $device_ip_dir/ethernet_frame_padding_ip/ethernet_frame_padding_ip.xci]
#update_compile_order -fileset sources_1


#100G
if {$cfg(fdev) eq "vcu118"} {
    create_ip -name cmac_usplus -vendor xilinx.com -library ip -version 3.0 -module_name cmac_usplus_axis -dir $device_ip_dir
    set_property -dict [list CONFIG.CMAC_CAUI4_MODE {1} CONFIG.NUM_LANES {4x25} CONFIG.GT_REF_CLK_FREQ {156.25} CONFIG.USER_INTERFACE {AXIS} CONFIG.GT_DRP_CLK {125} CONFIG.TX_FLOW_CONTROL {0} CONFIG.RX_FLOW_CONTROL {0} CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y8} CONFIG.GT_GROUP_SELECT {X1Y52~X1Y55} CONFIG.LANE1_GT_LOC {X1Y52} CONFIG.LANE2_GT_LOC {X1Y53} CONFIG.LANE3_GT_LOC {X1Y54} CONFIG.LANE4_GT_LOC {X1Y55} CONFIG.LANE5_GT_LOC {NA} CONFIG.LANE6_GT_LOC {NA} CONFIG.LANE7_GT_LOC {NA} CONFIG.LANE8_GT_LOC {NA} CONFIG.LANE9_GT_LOC {NA} CONFIG.LANE10_GT_LOC {NA} CONFIG.Component_Name {cmac_usplus_axis}] [get_ips cmac_usplus_axis]
    generate_target {instantiation_template} [get_files $device_ip_dir/cmac_usplus_axis/cmac_usplus_axis.xci]
    update_compile_order -fileset sources_1
}

if {$cfg(fdev) eq "u250"} {
    if {$cfg(qsfp) eq 0} {
        create_ip -name cmac_usplus -vendor xilinx.com -library ip -version 3.0 -module_name cmac_usplus_axis -dir $device_ip_dir
        set_property -dict [list CONFIG.CMAC_CAUI4_MODE {1} CONFIG.NUM_LANES {4x25} CONFIG.GT_REF_CLK_FREQ {156.25} CONFIG.USER_INTERFACE {AXIS} CONFIG.GT_DRP_CLK {250} CONFIG.TX_FLOW_CONTROL {0} CONFIG.RX_FLOW_CONTROL {0} CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y7} CONFIG.GT_GROUP_SELECT {X1Y44~X1Y47} CONFIG.LANE1_GT_LOC {X1Y44} CONFIG.LANE2_GT_LOC {X1Y45} CONFIG.LANE3_GT_LOC {X1Y46} CONFIG.LANE4_GT_LOC {X1Y47} CONFIG.Component_Name {cmac_usplus_axis}] [get_ips cmac_usplus_axis]
        generate_target {instantiation_template} [get_files $device_ip_dir/cmac_usplus_axis/cmac_usplus_axis.xci]
        update_compile_order -fileset sources_1
    } else {
        create_ip -name cmac_usplus -vendor xilinx.com -library ip -version 3.0 -module_name cmac_usplus_axis -dir $device_ip_dir
        set_property -dict [list CONFIG.CMAC_CAUI4_MODE {1} CONFIG.NUM_LANES {4x25} CONFIG.GT_REF_CLK_FREQ {156.25} CONFIG.USER_INTERFACE {AXIS} CONFIG.GT_DRP_CLK {250} CONFIG.TX_FLOW_CONTROL {0} CONFIG.RX_FLOW_CONTROL {0} CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y7} CONFIG.GT_GROUP_SELECT {X1Y40~X1Y43} CONFIG.LANE1_GT_LOC {X1Y40} CONFIG.LANE2_GT_LOC {X1Y41} CONFIG.LANE3_GT_LOC {X1Y42} CONFIG.LANE4_GT_LOC {X1Y43} CONFIG.Component_Name {cmac_usplus_axis}] [get_ips cmac_usplus_axis]
        generate_target {instantiation_template} [get_files $device_ip_dir/cmac_usplus_axis/cmac_usplus_axis.xci]
        update_compile_order -fileset sources_1
    }
}

if {$cfg(fdev) eq "u280"} {
    if {$cfg(qsfp) eq 0} {
        create_ip -name cmac_usplus -vendor xilinx.com -library ip -version 3.0 -module_name cmac_usplus_axis -dir $device_ip_dir
        set_property -dict [list CONFIG.CMAC_CAUI4_MODE {1} CONFIG.NUM_LANES {4x25} CONFIG.GT_REF_CLK_FREQ {156.25} CONFIG.USER_INTERFACE {AXIS} CONFIG.GT_DRP_CLK {250} CONFIG.TX_FLOW_CONTROL {0} CONFIG.RX_FLOW_CONTROL {0} CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y6} CONFIG.GT_GROUP_SELECT {X0Y40~X0Y43} CONFIG.LANE1_GT_LOC {X0Y40} CONFIG.LANE2_GT_LOC {X0Y41} CONFIG.LANE3_GT_LOC {X0Y42} CONFIG.LANE4_GT_LOC {X0Y43} CONFIG.Component_Name {cmac_usplus_axis} ] [get_ips cmac_usplus_axis]
        generate_target {instantiation_template} [get_files $device_ip_dir/cmac_usplus_axis/cmac_usplus_axis.xci]
        update_compile_order -fileset sources_1
    } else {
        create_ip -name cmac_usplus -vendor xilinx.com -library ip -version 3.0 -module_name cmac_usplus_axis -dir $device_ip_dir
        set_property -dict [list CONFIG.CMAC_CAUI4_MODE {1} CONFIG.NUM_LANES {4x25} CONFIG.GT_REF_CLK_FREQ {156.25} CONFIG.USER_INTERFACE {AXIS} CONFIG.GT_DRP_CLK {250} CONFIG.TX_FLOW_CONTROL {0} CONFIG.RX_FLOW_CONTROL {0} CONFIG.CMAC_CORE_SELECT {CMACE4_X0Y6} CONFIG.GT_GROUP_SELECT {X0Y44~X0Y47} CONFIG.LANE1_GT_LOC {X0Y44} CONFIG.LANE2_GT_LOC {X0Y45} CONFIG.LANE3_GT_LOC {X0Y46} CONFIG.LANE4_GT_LOC {X0Y47} CONFIG.Component_Name {cmac_usplus_axis} ] [get_ips cmac_usplus_axis]
        generate_target {instantiation_template} [get_files $device_ip_dir/cmac_usplus_axis/cmac_usplus_axis.xci]
        update_compile_order -fileset sources_1
    }
}

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_pkg_fifo_512 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_MODE {2} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.Component_Name {axis_pkg_fifo_512}] [get_ips axis_pkg_fifo_512]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_pkg_fifo_512/axis_pkg_fifo_512.xci]
update_compile_order -fileset sources_1


create_ip -name ethernet_frame_padding_512 -vendor ethz.systems.fpga -library hls -version 0.1 -module_name ethernet_frame_padding_512_ip -dir $device_ip_dir
generate_target {instantiation_template} [get_files $device_ip_dir/ethernet_frame_padding_512_ip/ethernet_frame_padding_512_ip.xci]
update_compile_order -fileset sources_1

