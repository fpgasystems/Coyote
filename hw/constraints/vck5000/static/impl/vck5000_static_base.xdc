# Power constraint (VCK5000 is a 225 W card; budget for the power DRC estimate)
set_operating_conditions -design_power_budget 180

# Compress bitstream
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design];

# =====================================================================================
# PCIe reference clock (VCK5000) --- matched to the known-good VCK5000 CPM QDMA design.
#
# The board delivers the 100 MHz host PCIe ref on pcie_refclk_2 (R36/R37); the CPM4
# otherwise defaults it to pcie_refclk_0 (AB34/AB35) which is unconnected -> CPM PLL never
# locks -> link never trains. So the refclk pin MUST be pinned explicitly.
#
# GT lanes: NOT pinned here. The CPM PCIe (X16, CPM_PCIE0) auto-places its 16 GT lanes onto
# the board's PCIe pins via the silicon-fixed CPM->GTY mapping (verified: the x8 build placed
# lanes on the exact board pins with no lane XDC). Explicit lane LOCs are avoided because the
# VCK5000 board file lists lane 15 rx AND tx both on B40/B39 (a board-file duplication) which
# would collide if pinned; the silicon mapping resolves lane 15 correctly.
#
# No PCIE40_X0Y1 site LOC: on Vivado 2023.2 / versal_cips 3.4 the CPM is a monolithic hardened
# block (no user-placeable pcie_4_0_e5_inst cell); the CIPS auto-places the PCIe GTs correctly.
# =====================================================================================

# PCIe reference clock (100 MHz) --- pcie_refclk_2
set_property PACKAGE_PIN R37 [get_ports {pcie_clk_clk_n[0]}]
set_property PACKAGE_PIN R36 [get_ports {pcie_clk_clk_p[0]}]
create_clock -period 10.000 -name pcie_ref_clk [get_ports {pcie_clk_clk_p[0]}];
