# Clocks
create_clock -period 4.000 [get_ports xclk];
create_clock -period 10.000 [get_ports dclk];

# HBM
create_clock -period 10.000 [get_ports  hbm_clk_clk_p];

# CMAC clocks
create_clock -period 6.206 [get_ports gt0_refclk_p];
create_clock -period 6.206 [get_ports gt1_refclk_p];

# Debug
set_property C_CLK_INPUT_FREQ_HZ 100000000 [get_debug_cores inst_debug_bridge_dynamic/inst/xsdbm]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores inst_debug_bridge_dynamic/inst/xsdbm]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores inst_debug_bridge_dynamic/inst/xsdbm]
connect_debug_port inst_debug_bridge_dynamic/inst/xsdbm/clk [get_nets dclk]
