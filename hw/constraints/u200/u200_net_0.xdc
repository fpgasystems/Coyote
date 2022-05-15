###
### QSFP 0
###

# Control
set_property PACKAGE_PIN BE17 [get_ports qsfp0_resetn]
set_property PACKAGE_PIN BD18 [get_ports qsfp0_lpmode]
set_property PACKAGE_PIN BE16 [get_ports qsfp0_modseln]


# Clock (156.25 MHz)
set_property PACKAGE_PIN M10 [get_ports gt0_refclk_n]
set_property PACKAGE_PIN M11 [get_ports gt0_refclk_p]

# Clock (161 MHz)
#set_property	PACKAGE_PIN	K10		[get_ports 	gt0_refclk_n	] ;
#set_property	PACKAGE_PIN	K11		[get_ports 	gt0_refclk_p	] ;

# Transceiver
set_property PACKAGE_PIN N4 [get_ports {gt0_rxp_in[0]}]
set_property PACKAGE_PIN N3 [get_ports {gt0_rxn_in[0]}]
set_property PACKAGE_PIN N9 [get_ports {gt0_txp_out[0]}]
set_property PACKAGE_PIN N8 [get_ports {gt0_txn_out[0]}]
set_property PACKAGE_PIN M2 [get_ports {gt0_rxp_in[1]}]
set_property PACKAGE_PIN M1 [get_ports {gt0_rxn_in[1]}]
set_property PACKAGE_PIN M7 [get_ports {gt0_txp_out[1]}]
set_property PACKAGE_PIN M6 [get_ports {gt0_txn_out[1]}]
set_property PACKAGE_PIN L4 [get_ports {gt0_rxp_in[2]}]
set_property PACKAGE_PIN L3 [get_ports {gt0_rxn_in[2]}]
set_property PACKAGE_PIN L9 [get_ports {gt0_txp_out[2]}]
set_property PACKAGE_PIN L8 [get_ports {gt0_txn_out[2]}]
set_property PACKAGE_PIN K2 [get_ports {gt0_rxp_in[3]}]
set_property PACKAGE_PIN K1 [get_ports {gt0_rxn_in[3]}]
set_property PACKAGE_PIN K7 [get_ports {gt0_txp_out[3]}]
set_property PACKAGE_PIN K6 [get_ports {gt0_txn_out[3]}]

set_property IOSTANDARD LVCMOS12 [get_ports qsfp0_resetn]
set_property IOSTANDARD LVCMOS12 [get_ports qsfp0_lpmode]
set_property IOSTANDARD LVCMOS12 [get_ports qsfp0_modseln]
set_false_path -to [get_ports qsfp0_resetn]
set_false_path -to [get_ports qsfp0_lpmode]
set_false_path -to [get_ports qsfp0_modseln]

####################################################################################
# Constraints from file : 'design_static_xdma_0_0_pcie4_ip_late.xdc'
####################################################################################

