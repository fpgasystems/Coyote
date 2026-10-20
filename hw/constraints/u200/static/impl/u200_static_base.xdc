# Power constraint
set_operating_conditions -design_power_budget 160

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design];

# CMAC clocks
create_clock -period 6.4 -name gt0_refclk_p [get_ports gt0_refclk_p];
create_clock -period 6.4 -name gt1_refclk_p [get_ports gt1_refclk_p];
