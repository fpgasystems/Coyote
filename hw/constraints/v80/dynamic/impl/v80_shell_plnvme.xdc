##
## PL-connected NVMe over the V80 MCIO PCIe x4 link
##

# The source board constraint names this connector mcio1_a. Map its Root-Port
# receive and transmit directions onto Coyote's top-level PL-NVMe names.

# 100-MHz MCIO1 reference clock, GTY bank 213 (GTYP_REFCLKP0_213).
set_property -quiet PACKAGE_PIN AG55 [get_ports -quiet pl_nvme_refclk_p]

# MCIO1-A Root-Port receive lanes (GTYP_RXP[3:0]_213).
set_property -quiet PACKAGE_PIN D66 [get_ports -quiet {pl_nvme_rxp_in[0]}]
set_property -quiet PACKAGE_PIN B65 [get_ports -quiet {pl_nvme_rxp_in[1]}]
set_property -quiet PACKAGE_PIN D64 [get_ports -quiet {pl_nvme_rxp_in[2]}]
set_property -quiet PACKAGE_PIN B63 [get_ports -quiet {pl_nvme_rxp_in[3]}]

# MCIO1-A Root-Port transmit lanes (GTYP_TXP[3:0]_213).
set_property -quiet PACKAGE_PIN G69 [get_ports -quiet {pl_nvme_txp_out[0]}]
set_property -quiet PACKAGE_PIN E68 [get_ports -quiet {pl_nvme_txp_out[1]}]
set_property -quiet PACKAGE_PIN G67 [get_ports -quiet {pl_nvme_txp_out[2]}]
set_property -quiet PACKAGE_PIN G65 [get_ports -quiet {pl_nvme_txp_out[3]}]

# The complementary refclock, RXN, and TXN pins are inferred from the selected
# GT sites and do not need independent PACKAGE_PIN assignments.

# No PERST# top-level signal is required for this integration.
