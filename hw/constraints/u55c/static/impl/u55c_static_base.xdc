# Power constraint
set_operating_conditions -design_power_budget 160

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design];

# CMAC clocks
create_clock -period 6.206 -name gt0_refclk_p [get_ports gt0_refclk_p];
create_clock -period 6.206 -name gt1_refclk_p [get_ports gt1_refclk_p];

# HBM (100 MHz)
create_clock -period 10.000 -name hbm_clk_clk_p [get_ports  hbm_clk_clk_p];
