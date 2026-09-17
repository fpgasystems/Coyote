# PCIe reference clock (100 MHz), synthesis-stage timing definition.
# NOTE: the physical refclk + GT-lane PACKAGE_PINs are set in static/impl/vck5000_static_base.xdc.
# The CPM4 auto-default put the refclk on the wrong board pin (pcie_refclk_0); the VCK5000 board
# actually routes the host PCIe refclk to pcie_refclk_2 (R36/R37), so it must be pinned explicitly.
create_clock -period 10.000 [get_ports pcie_clk_clk_p];
