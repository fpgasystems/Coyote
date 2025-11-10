# ILA
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_aes
set_property -dict [list CONFIG.C_NUM_OF_PROBES {8} CONFIG.C_PROBE7_WIDTH {512} CONFIG.C_PROBE3_WIDTH {512} CONFIG.C_EN_STRG_QUAL {1} CONFIG.ALL_PROBE_SAME_MU_CNT {2}] [get_ips ila_aes]
