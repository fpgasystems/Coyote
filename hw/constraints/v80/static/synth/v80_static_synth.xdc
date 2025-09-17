# PCIe
create_clock -period 10.000 [get_ports pcie_clk_clk_p];

# Placeholder: CMAC clocks --- TODO: Modify accordingly for V80 when adding network support
create_clock -period 6.206 [get_ports gt0_refclk_p];
create_clock -period 6.206 [get_ports gt1_refclk_p];
