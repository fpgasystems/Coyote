#AXI Infrastructure (device independent)


#Clock Converters

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_32 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.Component_Name {axis_clock_converter_32}] [get_ips axis_clock_converter_32]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_clock_converter_32/axis_clock_converter_32.xci]
update_compile_order -fileset sources_1

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_64 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {8} CONFIG.Component_Name {axis_clock_converter_64}] [get_ips axis_clock_converter_64]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_clock_converter_64/axis_clock_converter_64.xci]
update_compile_order -fileset sources_1

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_96 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.Component_Name {axis_clock_converter_96}] [get_ips axis_clock_converter_96]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_clock_converter_96/axis_clock_converter_96.xci]
update_compile_order -fileset sources_1

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_136 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {17} CONFIG.Component_Name {axis_clock_converter_136}] [get_ips axis_clock_converter_136]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_clock_converter_136/axis_clock_converter_136.xci]
update_compile_order -fileset sources_1

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_144 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {18} CONFIG.Component_Name {axis_clock_converter_144}] [get_ips axis_clock_converter_144]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_clock_converter_144/axis_clock_converter_144.xci]
update_compile_order -fileset sources_1

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_200 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {25} CONFIG.Component_Name {axis_clock_converter_200}] [get_ips axis_clock_converter_200]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_clock_converter_200/axis_clock_converter_200.xci]
update_compile_order -fileset sources_1

create_ip -name axi_clock_converter -vendor xilinx.com -library ip -version 2.1 -module_name axil_clock_converter -dir $device_ip_dir
set_property -dict [list CONFIG.Component_Name {axil_clock_converter} CONFIG.PROTOCOL {AXI4LITE} CONFIG.DATA_WIDTH {32} CONFIG.ID_WIDTH {0} CONFIG.AWUSER_WIDTH {0} CONFIG.ARUSER_WIDTH {0} CONFIG.RUSER_WIDTH {0} CONFIG.WUSER_WIDTH {0} CONFIG.BUSER_WIDTH {0}] [get_ips axil_clock_converter]
generate_target {instantiation_template} [get_files $device_ip_dir/axil_clock_converter/axil_clock_converter.xci]
update_compile_order -fileset sources_1

create_ip -name axi_clock_converter -vendor xilinx.com -library ip -version 2.1 -module_name axil_net_ctrl_clock_converter -dir $device_ip_dir
set_property -dict [list CONFIG.Component_Name {axil_net_ctrl_clock_converter} CONFIG.PROTOCOL {AXI4LITE} CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {64} CONFIG.ID_WIDTH {0} CONFIG.AWUSER_WIDTH {0} CONFIG.ARUSER_WIDTH {0} CONFIG.RUSER_WIDTH {0} CONFIG.WUSER_WIDTH {0} CONFIG.BUSER_WIDTH {0}] [get_ips axil_net_ctrl_clock_converter]
generate_target {instantiation_template} [get_files $device_ip_dir/axil_net_ctrl_clock_converter/axil_net_ctrl_clock_converter.xci]
update_compile_order -fileset sources_1

#Data Width Converters

#create_ip -name axis_dwidth_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_256_to_512_converter -dir $device_ip_dir
#set_property -dict [list CONFIG.S_TDATA_NUM_BYTES {32} CONFIG.M_TDATA_NUM_BYTES {64} CONFIG.HAS_TLAST {1} CONFIG.HAS_TKEEP {1} CONFIG.HAS_MI_TKEEP {1} CONFIG.Component_Name {axis_256_to_512_converter}] [get_ips axis_256_to_512_converter]
#generate_target {instantiation_template} [get_files $device_ip_dir/axis_256_to_512_converter/axis_256_to_512_converter.xci]
#update_compile_order -fileset sources_1


#create_ip -name axis_dwidth_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_512_to_256_converter -dir $device_ip_dir
#set_property -dict [list CONFIG.S_TDATA_NUM_BYTES {64} CONFIG.M_TDATA_NUM_BYTES {32} CONFIG.HAS_TLAST {1} CONFIG.HAS_TKEEP {1} CONFIG.HAS_MI_TKEEP {1} CONFIG.Component_Name {axis_512_to_256_converter}] [get_ips axis_512_to_256_converter]
#generate_target {instantiation_template} [get_files $device_ip_dir/axis_512_to_256_converter/axis_512_to_256_converter.xci]
#update_compile_order -fileset sources_1


create_ip -name axi_crossbar -vendor xilinx.com -library ip -version 2.1 -module_name axil_controller_crossbar -dir $device_ip_dir
set_property -dict [list CONFIG.PROTOCOL {AXI4LITE} CONFIG.CONNECTIVITY_MODE {SASD} CONFIG.R_REGISTER {1} CONFIG.NUM_MI {5} CONFIG.M01_A00_BASE_ADDR {0x0000000000001000} CONFIG.M02_A00_BASE_ADDR {0x0000000000002000} CONFIG.M03_A00_BASE_ADDR {0x0000000000003000} CONFIG.M04_A00_BASE_ADDR {0x0000000000004000} CONFIG.S00_WRITE_ACCEPTANCE {1} CONFIG.S01_WRITE_ACCEPTANCE {1} CONFIG.S02_WRITE_ACCEPTANCE {1} CONFIG.S03_WRITE_ACCEPTANCE {1} CONFIG.S04_WRITE_ACCEPTANCE {1} CONFIG.S05_WRITE_ACCEPTANCE {1} CONFIG.S06_WRITE_ACCEPTANCE {1} CONFIG.S07_WRITE_ACCEPTANCE {1} CONFIG.S08_WRITE_ACCEPTANCE {1} CONFIG.S09_WRITE_ACCEPTANCE {1} CONFIG.S10_WRITE_ACCEPTANCE {1} CONFIG.S11_WRITE_ACCEPTANCE {1} CONFIG.S12_WRITE_ACCEPTANCE {1} CONFIG.S13_WRITE_ACCEPTANCE {1} CONFIG.S14_WRITE_ACCEPTANCE {1} CONFIG.S15_WRITE_ACCEPTANCE {1} CONFIG.S00_READ_ACCEPTANCE {1} CONFIG.S01_READ_ACCEPTANCE {1} CONFIG.S02_READ_ACCEPTANCE {1} CONFIG.S03_READ_ACCEPTANCE {1} CONFIG.S04_READ_ACCEPTANCE {1} CONFIG.S05_READ_ACCEPTANCE {1} CONFIG.S06_READ_ACCEPTANCE {1} CONFIG.S07_READ_ACCEPTANCE {1} CONFIG.S08_READ_ACCEPTANCE {1} CONFIG.S09_READ_ACCEPTANCE {1} CONFIG.S10_READ_ACCEPTANCE {1} CONFIG.S11_READ_ACCEPTANCE {1} CONFIG.S12_READ_ACCEPTANCE {1} CONFIG.S13_READ_ACCEPTANCE {1} CONFIG.S14_READ_ACCEPTANCE {1} CONFIG.S15_READ_ACCEPTANCE {1} CONFIG.M00_WRITE_ISSUING {1} CONFIG.M01_WRITE_ISSUING {1} CONFIG.M02_WRITE_ISSUING {1} CONFIG.M03_WRITE_ISSUING {1} CONFIG.M04_WRITE_ISSUING {1} CONFIG.M05_WRITE_ISSUING {1} CONFIG.M06_WRITE_ISSUING {1} CONFIG.M07_WRITE_ISSUING {1} CONFIG.M08_WRITE_ISSUING {1} CONFIG.M09_WRITE_ISSUING {1} CONFIG.M10_WRITE_ISSUING {1} CONFIG.M11_WRITE_ISSUING {1} CONFIG.M12_WRITE_ISSUING {1} CONFIG.M13_WRITE_ISSUING {1} CONFIG.M14_WRITE_ISSUING {1} CONFIG.M15_WRITE_ISSUING {1} CONFIG.M00_READ_ISSUING {1} CONFIG.M01_READ_ISSUING {1} CONFIG.M02_READ_ISSUING {1} CONFIG.M03_READ_ISSUING {1} CONFIG.M04_READ_ISSUING {1} CONFIG.M05_READ_ISSUING {1} CONFIG.M06_READ_ISSUING {1} CONFIG.M07_READ_ISSUING {1} CONFIG.M08_READ_ISSUING {1} CONFIG.M09_READ_ISSUING {1} CONFIG.M10_READ_ISSUING {1} CONFIG.M11_READ_ISSUING {1} CONFIG.M12_READ_ISSUING {1} CONFIG.M13_READ_ISSUING {1} CONFIG.M14_READ_ISSUING {1} CONFIG.M15_READ_ISSUING {1} CONFIG.S00_SINGLE_THREAD {1} CONFIG.Component_Name {axil_controller_crossbar}] [get_ips axil_controller_crossbar]
generate_target {instantiation_template} [get_files $device_ip_dir/axil_controller_crossbar/axil_controller_crossbar.xci]
update_compile_order -fileset sources_1


#Register slices
create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_8 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {1} CONFIG.Component_Name {axis_register_slice_8}] [get_ips axis_register_slice_8]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_register_slice_8/axis_register_slice_8.xci]
update_compile_order -fileset sources_1

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_16 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.Component_Name {axis_register_slice_16}] [get_ips axis_register_slice_16]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_register_slice_16/axis_register_slice_16.xci]
update_compile_order -fileset sources_1

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_24 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {3} CONFIG.Component_Name {axis_register_slice_24}] [get_ips axis_register_slice_24]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_register_slice_24/axis_register_slice_24.xci]
update_compile_order -fileset sources_1

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_32 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.Component_Name {axis_register_slice_32}] [get_ips axis_register_slice_32]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_register_slice_32/axis_register_slice_32.xci]
update_compile_order -fileset sources_1

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_48 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {6} CONFIG.Component_Name {axis_register_slice_48}] [get_ips axis_register_slice_48]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_register_slice_48/axis_register_slice_48.xci]
update_compile_order -fileset sources_1

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_88 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {11} CONFIG.Component_Name {axis_register_slice_88}] [get_ips axis_register_slice_88]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_register_slice_88/axis_register_slice_88.xci]
update_compile_order -fileset sources_1

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_96 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.Component_Name {axis_register_slice_96}] [get_ips axis_register_slice_96]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_register_slice_96/axis_register_slice_96.xci]
update_compile_order -fileset sources_1

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_176 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {22} CONFIG.Component_Name {axis_register_slice_176}] [get_ips axis_register_slice_176]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_register_slice_176/axis_register_slice_176.xci]
update_compile_order -fileset sources_1

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_64 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {8} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.Component_Name {axis_register_slice_64}] [get_ips axis_register_slice_64]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_register_slice_64/axis_register_slice_64.xci]
update_compile_order -fileset sources_1

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_128 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.Component_Name {axis_register_slice_128}] [get_ips axis_register_slice_128]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_register_slice_128/axis_register_slice_128.xci]
update_compile_order -fileset sources_1

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_256 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {32} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.Component_Name {axis_register_slice_256}] [get_ips axis_register_slice_256]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_register_slice_256/axis_register_slice_256.xci]
update_compile_order -fileset sources_1

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_512 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.Component_Name {axis_register_slice_512}] [get_ips axis_register_slice_512]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_register_slice_512/axis_register_slice_512.xci]
update_compile_order -fileset sources_1


#FIFOs

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_96 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.Component_Name {axis_data_fifo_96}] [get_ips axis_data_fifo_96]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_data_fifo_96/axis_data_fifo_96.xci]
update_compile_order -fileset sources_1

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_160 -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {20} CONFIG.Component_Name {axis_data_fifo_160} CONFIG.HAS_WR_DATA_COUNT {1} CONFIG.HAS_RD_DATA_COUNT {1}] [get_ips axis_data_fifo_160]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_data_fifo_160/axis_data_fifo_160.xci]
update_compile_order -fileset sources_1

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_160_cc -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {20} CONFIG.IS_ACLK_ASYNC {1} CONFIG.Component_Name {axis_data_fifo_160_cc} CONFIG.HAS_WR_DATA_COUNT {1} CONFIG.HAS_RD_DATA_COUNT {1}] [get_ips axis_data_fifo_160_cc]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_data_fifo_160_cc/axis_data_fifo_160_cc.xci]
update_compile_order -fileset sources_1

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_512_cc -dir $device_ip_dir
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.IS_ACLK_ASYNC {1} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.Component_Name {axis_data_fifo_512_cc}] [get_ips axis_data_fifo_512_cc]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_data_fifo_512_cc/axis_data_fifo_512_cc.xci]
update_compile_order -fileset sources_1

create_ip -name fifo_generator -vendor xilinx.com -library ip -version 13.2 -module_name fifo_generator_rdma_cmd -dir $device_ip_dir
set_property -dict [list CONFIG.Component_Name {fifo_generator_rdma_cmd} CONFIG.INTERFACE_TYPE {AXI_STREAM} CONFIG.Reset_Type {Asynchronous_Reset} CONFIG.Clock_Type_AXI {Independent_Clock} CONFIG.TDATA_NUM_BYTES {16} CONFIG.TUSER_WIDTH {0} CONFIG.TSTRB_WIDTH {16} CONFIG.TKEEP_WIDTH {16} CONFIG.FIFO_Implementation_wach {Independent_Clocks_Distributed_RAM} CONFIG.Full_Threshold_Assert_Value_wach {15} CONFIG.Empty_Threshold_Assert_Value_wach {13} CONFIG.FIFO_Implementation_wdch {Independent_Clocks_Builtin_FIFO} CONFIG.Empty_Threshold_Assert_Value_wdch {1018} CONFIG.FIFO_Implementation_wrch {Independent_Clocks_Distributed_RAM} CONFIG.Full_Threshold_Assert_Value_wrch {15} CONFIG.Empty_Threshold_Assert_Value_wrch {13} CONFIG.FIFO_Implementation_rach {Independent_Clocks_Distributed_RAM} CONFIG.Full_Threshold_Assert_Value_rach {15} CONFIG.Empty_Threshold_Assert_Value_rach {13} CONFIG.FIFO_Implementation_rdch {Independent_Clocks_Builtin_FIFO} CONFIG.Empty_Threshold_Assert_Value_rdch {1018} CONFIG.FIFO_Implementation_axis {Independent_Clocks_Block_RAM} CONFIG.Input_Depth_axis {64} CONFIG.Full_Threshold_Assert_Value_axis {63} CONFIG.Empty_Threshold_Assert_Value_axis {61}] [get_ips fifo_generator_rdma_cmd]
generate_target {instantiation_template} [get_files $device_ip_dir/fifo_generator_rdma_cmd/fifo_generator_rdma_cmd.xci]
update_compile_order -fileset sources_1

create_ip -name fifo_generator -vendor xilinx.com -library ip -version 13.2 -module_name fifo_generator_rdma_data -dir $device_ip_dir
set_property -dict [list CONFIG.Component_Name {fifo_generator_rdma_data} CONFIG.INTERFACE_TYPE {AXI_STREAM} CONFIG.Reset_Type {Asynchronous_Reset} CONFIG.Clock_Type_AXI {Independent_Clock} CONFIG.TDATA_NUM_BYTES {64} CONFIG.TUSER_WIDTH {0} CONFIG.Enable_TLAST {true} CONFIG.TSTRB_WIDTH {64} CONFIG.HAS_TKEEP {true} CONFIG.TKEEP_WIDTH {64} CONFIG.FIFO_Implementation_wach {Independent_Clocks_Distributed_RAM} CONFIG.Full_Threshold_Assert_Value_wach {15} CONFIG.Empty_Threshold_Assert_Value_wach {13} CONFIG.FIFO_Implementation_wdch {Independent_Clocks_Builtin_FIFO} CONFIG.Empty_Threshold_Assert_Value_wdch {1018} CONFIG.FIFO_Implementation_wrch {Independent_Clocks_Distributed_RAM} CONFIG.Full_Threshold_Assert_Value_wrch {15} CONFIG.Empty_Threshold_Assert_Value_wrch {13} CONFIG.FIFO_Implementation_rach {Independent_Clocks_Distributed_RAM} CONFIG.Full_Threshold_Assert_Value_rach {15} CONFIG.Empty_Threshold_Assert_Value_rach {13} CONFIG.FIFO_Implementation_rdch {Independent_Clocks_Builtin_FIFO} CONFIG.Empty_Threshold_Assert_Value_rdch {1018} CONFIG.FIFO_Implementation_axis {Independent_Clocks_Block_RAM} CONFIG.Input_Depth_axis {128} CONFIG.Full_Threshold_Assert_Value_axis {127} CONFIG.Empty_Threshold_Assert_Value_axis {125}] [get_ips fifo_generator_rdma_data]
generate_target {instantiation_template} [get_files $device_ip_dir/fifo_generator_rdma_data/fifo_generator_rdma_data.xci]
update_compile_order -fileset sources_1

create_ip -name axi_register_slice -vendor xilinx.com -library ip -version 2.1 -module_name axi_register_slice -dir $device_ip_dir
set_property -dict [list CONFIG.PROTOCOL {AXI4LITE} CONFIG.REG_W {7} CONFIG.REG_R {7} CONFIG.Component_Name {axi_register_slice}] [get_ips axi_register_slice]
generate_target {instantiation_template} [get_files $device_ip_dir/axi_register_slice/axi_register_slice.xci]
update_compile_order -fileset sources_1

#Interconnects
create_ip -name axis_interconnect -vendor xilinx.com -library ip -version 1.1 -module_name axis_interconnect_96_1to2 -dir $device_ip_dir
set_property -dict [list CONFIG.Component_Name {axis_interconnect_96_1to2} CONFIG.C_NUM_MI_SLOTS {2} CONFIG.SWITCH_TDATA_NUM_BYTES {12} CONFIG.HAS_TSTRB {false} CONFIG.HAS_TKEEP {false} CONFIG.HAS_TLAST {false} CONFIG.HAS_TID {false} CONFIG.C_M00_AXIS_REG_CONFIG {1} CONFIG.C_S00_AXIS_REG_CONFIG {1} CONFIG.C_M01_AXIS_REG_CONFIG {1} CONFIG.HAS_TDEST {true} CONFIG.C_SWITCH_TDEST_WIDTH {1} CONFIG.SWITCH_PACKET_MODE {false} CONFIG.C_SWITCH_MAX_XFERS_PER_ARB {1} CONFIG.C_SWITCH_NUM_CYCLES_TIMEOUT {0} CONFIG.M00_AXIS_TDATA_NUM_BYTES {12} CONFIG.S00_AXIS_TDATA_NUM_BYTES {12} CONFIG.M01_AXIS_TDATA_NUM_BYTES {12} CONFIG.C_M00_AXIS_BASETDEST {0x00000000} CONFIG.C_M00_AXIS_HIGHTDEST {0x00000000} CONFIG.C_M01_AXIS_BASETDEST {0x00000001} CONFIG.C_M01_AXIS_HIGHTDEST {0x00000001} CONFIG.M01_S00_CONNECTIVITY {true}] [get_ips axis_interconnect_96_1to2]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_interconnect_96_1to2/axis_interconnect_96_1to2.xci]
update_compile_order -fileset sources_1

create_ip -name axis_interconnect -vendor xilinx.com -library ip -version 1.1 -module_name axis_interconnect_160_2to1 -dir $device_ip_dir
set_property -dict [list CONFIG.Component_Name {axis_interconnect_160_2to1} CONFIG.C_NUM_SI_SLOTS {2} CONFIG.SWITCH_TDATA_NUM_BYTES {20} CONFIG.HAS_TSTRB {false} CONFIG.HAS_TKEEP {false} CONFIG.HAS_TLAST {false} CONFIG.HAS_TID {false} CONFIG.HAS_TDEST {false} CONFIG.C_SWITCH_MAX_XFERS_PER_ARB {1} CONFIG.C_SWITCH_NUM_CYCLES_TIMEOUT {0} CONFIG.M00_AXIS_TDATA_NUM_BYTES {20} CONFIG.S00_AXIS_TDATA_NUM_BYTES {20} CONFIG.S01_AXIS_TDATA_NUM_BYTES {20} CONFIG.M00_S01_CONNECTIVITY {true}] [get_ips axis_interconnect_160_2to1]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_interconnect_160_2to1/axis_interconnect_160_2to1.xci]
update_compile_order -fileset sources_1

create_ip -name axis_interconnect -vendor xilinx.com -library ip -version 1.1 -module_name axis_interconnect_64_1to2 -dir $device_ip_dir
set_property -dict [list CONFIG.Component_Name {axis_interconnect_64_1to2} CONFIG.C_NUM_MI_SLOTS {2} CONFIG.SWITCH_TDATA_NUM_BYTES {8} CONFIG.HAS_TSTRB {false} CONFIG.HAS_TID {false} CONFIG.C_M00_AXIS_REG_CONFIG {1} CONFIG.C_S00_AXIS_REG_CONFIG {1} CONFIG.C_M01_AXIS_REG_CONFIG {1} CONFIG.HAS_TDEST {true} CONFIG.C_SWITCH_TDEST_WIDTH {1} CONFIG.C_SWITCH_NUM_CYCLES_TIMEOUT {0} CONFIG.M00_AXIS_TDATA_NUM_BYTES {8} CONFIG.S00_AXIS_TDATA_NUM_BYTES {8} CONFIG.M01_AXIS_TDATA_NUM_BYTES {8} CONFIG.C_M00_AXIS_BASETDEST {0x00000000} CONFIG.C_M00_AXIS_HIGHTDEST {0x00000000} CONFIG.C_M01_AXIS_BASETDEST {0x00000001} CONFIG.C_M01_AXIS_HIGHTDEST {0x00000001} CONFIG.M01_S00_CONNECTIVITY {true}] [get_ips axis_interconnect_64_1to2]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_interconnect_64_1to2/axis_interconnect_64_1to2.xci]
update_compile_order -fileset sources_1

create_ip -name axis_interconnect -vendor xilinx.com -library ip -version 1.1 -module_name axis_interconnect_512_1to2 -dir $device_ip_dir
set_property -dict [list CONFIG.Component_Name {axis_interconnect_512_1to2} CONFIG.C_NUM_MI_SLOTS {2} CONFIG.SWITCH_TDATA_NUM_BYTES {64} CONFIG.HAS_TSTRB {false} CONFIG.HAS_TID {false} CONFIG.C_M00_AXIS_REG_CONFIG {1} CONFIG.C_S00_AXIS_REG_CONFIG {1} CONFIG.C_M01_AXIS_REG_CONFIG {1} CONFIG.HAS_TDEST {true} CONFIG.C_SWITCH_TDEST_WIDTH {1} CONFIG.C_SWITCH_NUM_CYCLES_TIMEOUT {0} CONFIG.M00_AXIS_TDATA_NUM_BYTES {64} CONFIG.S00_AXIS_TDATA_NUM_BYTES {64} CONFIG.M01_AXIS_TDATA_NUM_BYTES {64} CONFIG.C_M00_AXIS_BASETDEST {0x00000000} CONFIG.C_M00_AXIS_HIGHTDEST {0x00000000} CONFIG.C_M01_AXIS_BASETDEST {0x00000001} CONFIG.C_M01_AXIS_HIGHTDEST {0x00000001} CONFIG.M01_S00_CONNECTIVITY {true}] [get_ips axis_interconnect_512_1to2]
generate_target {instantiation_template} [get_files $device_ip_dir/axis_interconnect_512_1to2/axis_interconnect_512_1to2.xci]
update_compile_order -fileset sources_1
