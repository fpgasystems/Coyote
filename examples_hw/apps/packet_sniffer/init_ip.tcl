# Debug ILA
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_packet_sniffer_vfpga
set_property -dict [list CONFIG.C_PROBE38_WIDTH {1} CONFIG.C_PROBE37_WIDTH {64} CONFIG.C_PROBE36_WIDTH {1} CONFIG.C_PROBE35_WIDTH {1} CONFIG.C_PROBE34_WIDTH {512} CONFIG.C_PROBE33_WIDTH {1} CONFIG.C_PROBE32_WIDTH {64} CONFIG.C_PROBE31_WIDTH {1} CONFIG.C_PROBE30_WIDTH {1} CONFIG.C_PROBE29_WIDTH {512} CONFIG.C_PROBE28_WIDTH {1} CONFIG.C_PROBE27_WIDTH {1} CONFIG.C_PROBE26_WIDTH {64} CONFIG.C_PROBE25_WIDTH {1} CONFIG.C_PROBE24_WIDTH {1} CONFIG.C_PROBE23_WIDTH {512} CONFIG.C_PROBE22_WIDTH {4} CONFIG.C_PROBE21_WIDTH {1} CONFIG.C_PROBE20_WIDTH {32} CONFIG.C_PROBE9_WIDTH {28} CONFIG.C_PROBE8_WIDTH {48} CONFIG.C_PROBE7_WIDTH {4} CONFIG.C_PROBE6_WIDTH {6} CONFIG.C_PROBE5_WIDTH {64} CONFIG.C_PROBE4_WIDTH {32} CONFIG.C_PROBE3_WIDTH {2} CONFIG.C_PROBE2_WIDTH {64} CONFIG.C_PROBE1_WIDTH {1} CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_NUM_OF_PROBES {39} CONFIG.C_EN_STRG_QUAL {1} CONFIG.ALL_PROBE_SAME_MU_CNT {2}] [get_ips ila_packet_sniffer_vfpga]

# FIFO
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_rx_sniffer_vfpga
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.IS_ACLK_ASYNC {0} CONFIG.FIFO_DEPTH {64} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_data_fifo_rx_sniffer_vfpga]
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_tx_sniffer_vfpga
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.IS_ACLK_ASYNC {0} CONFIG.FIFO_DEPTH {64} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_data_fifo_tx_sniffer_vfpga]
