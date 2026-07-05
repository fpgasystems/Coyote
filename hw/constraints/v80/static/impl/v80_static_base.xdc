# Power constraint
set_operating_conditions -design_power_budget 160

# Compress bitstream
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design];

# PCIe clock
# No need to assign pins, since the QDMA is hardened; see: 
# https://adaptivesupport.amd.com/s/question/0D54U00008ey67vSAA/questions-about-alveo-v80-implementation-pin-assignment?language=en_US
create_clock -period 10.000 -name pcie_ref_clk [get_ports pcie_clk_clk_p];

# Placeholder: DCMAC clocks --- TODO: Modify accordingly for V80 when adding network support
# create_clock -period 6.206 -name gt0_refclk_p [get_ports gt0_refclk_p];
# create_clock -period 6.206 -name gt1_refclk_p [get_ports gt1_refclk_p];
