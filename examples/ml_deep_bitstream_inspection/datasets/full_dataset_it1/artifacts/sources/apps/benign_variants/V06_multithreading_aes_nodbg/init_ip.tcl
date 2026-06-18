# Data width converters (ILA removed for nodbg variant)
create_ip -name axis_dwidth_converter -vendor xilinx.com -library ip -version 1.1 -module_name dwidth_input_512_128
set_property -dict [list CONFIG.S_TDATA_NUM_BYTES {64} CONFIG.M_TDATA_NUM_BYTES {16} CONFIG.TID_WIDTH {6} CONFIG.HAS_TLAST {1} CONFIG.HAS_TKEEP {1} CONFIG.Component_Name {dwidth_input_512_128}] [get_ips dwidth_input_512_128]

create_ip -name axis_dwidth_converter -vendor xilinx.com -library ip -version 1.1 -module_name dwidth_output_128_512
set_property -dict [list CONFIG.S_TDATA_NUM_BYTES {16} CONFIG.M_TDATA_NUM_BYTES {64} CONFIG.TID_WIDTH {6} CONFIG.HAS_TLAST {1} CONFIG.HAS_TKEEP {1} CONFIG.Component_Name {dwidth_output_128_512}] [get_ips dwidth_output_128_512]

# FIFO
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_cbc
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.TID_WIDTH {6} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.Component_Name {axis_data_fifo_cbc}] [get_ips axis_data_fifo_cbc]
