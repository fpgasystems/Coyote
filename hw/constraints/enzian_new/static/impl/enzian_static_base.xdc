# Power constraint
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design];

# CMAC clocks
create_clock -period 3.103 -name gt0_refclk_p [get_ports gt0_refclk_p];
create_clock -period 3.103 -name gt1_refclk_p [get_ports gt1_refclk_p];

# Fabric clocks
set_property PACKAGE_PIN AY26 [get_ports {prgc_clk_p[0]}]
set_property PACKAGE_PIN AY27 [get_ports {prgc_clk_n[0]}]
set_property PACKAGE_PIN AW28 [get_ports {prgc_clk_p[1]}]
set_property PACKAGE_PIN AY28 [get_ports {prgc_clk_n[1]}]