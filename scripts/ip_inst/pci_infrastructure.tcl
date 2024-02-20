##
## STATIC WRAPPER
##

# Regs
create_ip -name axi_register_slice -vendor xilinx.com -library ip -version 2.1 -module_name axi_register_slice_static_512
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {512} CONFIG.REG_AW {1} CONFIG.REG_AR {1} CONFIG.REG_B {1} CONFIG.ID_WIDTH {4} CONFIG.MAX_BURST_LENGTH {14} CONFIG.NUM_READ_OUTSTANDING {32} CONFIG.NUM_WRITE_OUTSTANDING {32}] [get_ips axi_register_slice_static_512]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_static_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.REG_CONFIG {8} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1}] [get_ips axis_register_slice_static_512]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_static_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.REG_CONFIG {8} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1}] [get_ips axis_register_slice_static_32]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_req_static_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_req_static_96]

# PR
create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name pr_clock_converter
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} ] [get_ips pr_clock_converter]

create_ip -name axis_dwidth_converter -vendor xilinx.com -library ip -version 1.1 -module_name pr_dwidth_converter
set_property -dict [list CONFIG.S_TDATA_NUM_BYTES {64} CONFIG.M_TDATA_NUM_BYTES {4} CONFIG.HAS_TLAST {1} CONFIG.HAS_TKEEP {1} CONFIG.HAS_MI_TKEEP {0} ] [get_ips pr_dwidth_converter]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name pr_reg_slice
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.HAS_TLAST {1} ] [get_ips pr_reg_slice]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_static_slave
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.FIFO_DEPTH {32} CONFIG.HAS_WR_DATA_COUNT {1}] [get_ips axis_data_fifo_static_slave]

# WB
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_wb_dma_static
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.FIFO_DEPTH {64} CONFIG.Component_Name {axis_data_fifo_wb_dma_static}] [get_ips axis_data_fifo_wb_dma_static]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_wb_data_static
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.FIFO_DEPTH {64} CONFIG.Component_Name {axis_data_fifo_wb_data_static}] [get_ips axis_data_fifo_wb_data_static]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_meta_static_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_meta_static_32]

# Debug
create_ip -name debug_bridge -vendor xilinx.com -library ip -module_name debug_bridge_static 
set_property -dict [list CONFIG.C_DEBUG_MODE {7} CONFIG.C_DESIGN_TYPE {0} CONFIG.C_NUM_BS_MASTER {2} ] [get_ips debug_bridge_static]

create_ip -name debug_bridge -vendor xilinx.com -library ip -module_name debug_hub_static
set_property -dict [list CONFIG.C_DEBUG_MODE {1} CONFIG.C_DESIGN_TYPE {0} CONFIG.C_NUM_BS_MASTER {0} ] [get_ips debug_hub_static]

create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_static_xstats
set_property -dict [list CONFIG.C_PROBE_IN5_WIDTH {32} CONFIG.C_PROBE_IN4_WIDTH {32} CONFIG.C_PROBE_IN3_WIDTH {32} CONFIG.C_PROBE_IN2_WIDTH {32} CONFIG.C_PROBE_IN1_WIDTH {32} CONFIG.C_PROBE_IN0_WIDTH {32} CONFIG.C_NUM_PROBE_OUT {0} CONFIG.C_NUM_PROBE_IN {6}] [get_ips vio_static_xstats]

create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_static_decoupling
set_property -dict [list CONFIG.C_PROBE_IN0_WIDTH {1} CONFIG.C_PROBE_IN1_WIDTH {1} CONFIG.C_PROBE_OUT0_WIDTH {1} CONFIG.C_PROBE_OUT1_WIDTH {1} CONFIG.C_PROBE_OUT2_WIDTH {1} CONFIG.C_NUM_PROBE_OUT {3} CONFIG.C_NUM_PROBE_IN {2} CONFIG.C_PROBE_OUT2_INIT_VAL {0x1}] [get_ips vio_static_decoupling]