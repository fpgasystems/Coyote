set_property C_CLK_INPUT_FREQ_HZ 100000000 [get_debug_cores inst_static/inst_debug_hub/inst/xsdbm]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores inst_static/inst_debug_hub/inst/xsdbm]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores inst_static/inst_debug_hub/inst/xsdbm]
connect_debug_port inst_static/inst_debug_hub/inst/xsdbm [get_nets pclk]