# PCIe
create_clock -period 10.000 [get_ports pcie_clk_clk_p];

# HBM
create_clock -period 10.000 [get_ports  hbm_clk_clk_p];

# CMAC clocks
create_clock -period 6.206 [get_ports gt0_refclk_p];
create_clock -period 6.206 [get_ports gt1_refclk_p];

# Debug
connect_debug_port inst_static/inst_debug_hub/inst/xsdbm/clk [get_nets inst_static/dclk]