# Initialisation of the DATA FIFO for buffered incoming streams 
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_512
set_property -dict [list CONFIG.FIFO_DEPTH {2048} CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_MODE {2} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_data_fifo_512]

# Initialisation of the CTRL FIFO for buffered DMA lengths
create_ip -name axis_meta_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_meta_fifo_32 
set_property -dict [list CONFIG.FIFO_DEPTH {2048} CONFIG.TDATA_NUM_BYTES {4} CONFIG.FIFO_MODE {2} CONFIG.HAS_TKEEP {0} CONFIG.HAS_TLAST {0} ] [get_ips axis_meta_fifo_32]

# Initialisation of the ILA for debugging purposes 
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_host_networking
set_property -dict [list CONFIG.C_PROBE3_WIDTH {512} CONFIG.C_PROBE4_WIDTH {64} CONFIG.C_PROBE8_WIDTH {512} CONFIG.C_PROBE9_WIDTH {64} CONFIG.C_PROBE13_WIDTH {512} CONFIG.C_PROBE14_WIDTH {64} CONFIG.C_PROBE17_WIDTH {128}  CONFIG.C_PROBE18_WIDTH {4} CONFIG.C_PROBE19_WIDTH {4} CONFIG.C_PROBE20_WIDTH {32}  CONFIG.C_PROBE21_WIDTH {32} CONFIG.C_PROBE22_WIDTH {32} CONFIG.C_PROBE23_WIDTH {48} CONFIG.C_PROBE24_WIDTH {6} CONFIG.C_NUM_OF_PROBES {31} CONFIG.C_EN_STRG_QUAL {1} CONFIG.ALL_PROBE_SAME_MU_CNT {2}] [get_ips ila_host_networking]