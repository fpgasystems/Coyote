# ECI
create_clock -period 10.000 [get_ports {prgc_clk_p[0]}]
create_clock -period 3.333 [get_ports {prgc_clk_p[1]}]


# CMAC clocks
create_clock -period 3.103 [get_ports gt0_refclk_p];
create_clock -period 3.103 [get_ports gt1_refclk_p];

# Debug
connect_debug_port inst_static/inst_debug_hub/inst/xsdbm/clk [get_nets inst_static/pclk]