# XCLK
create_clock -period 4.000 [get_ports xclk]

# HBM
create_clock -period 10.000 [get_ports  hbm_clk_clk_p];

# CMAC clocks
create_clock -period 3.103 [get_ports gt0_refclk_p]
create_clock -period 3.103 [get_ports gt1_refclk_p]