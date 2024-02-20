###
### QSFP 0
###

# Clock (161.1328125 MHz)
set_property	PACKAGE_PIN	AD43	[get_ports 	gt0_refclk_n	] ; 
set_property	PACKAGE_PIN	AD42	[get_ports 	gt0_refclk_p	] ; 

# Clock (322.265625 MHz)
#set_property	PACKAGE_PIN	M39		[get_ports 	gt0_refclk_n	] ; 
#set_property	PACKAGE_PIN	M38		[get_ports 	gt0_refclk_p	] ; 

# Transceiver
set_property	PACKAGE_PIN	AD52	[get_ports 	{gt0_rxn_in[0]}	] ; 
set_property	PACKAGE_PIN	AC54	[get_ports 	{gt0_rxn_in[1]}	] ; 
set_property	PACKAGE_PIN	AC50	[get_ports 	{gt0_rxn_in[2]}	] ; 
set_property	PACKAGE_PIN	AB52	[get_ports 	{gt0_rxn_in[3]}	] ; 
set_property	PACKAGE_PIN	AD51	[get_ports 	{gt0_rxp_in[0]}	] ; 
set_property	PACKAGE_PIN	AC53	[get_ports 	{gt0_rxp_in[1]}	] ; 
set_property	PACKAGE_PIN	AC49	[get_ports 	{gt0_rxp_in[2]}	] ; 
set_property	PACKAGE_PIN	AB51	[get_ports 	{gt0_rxp_in[3]}	] ; 
set_property	PACKAGE_PIN	AD47	[get_ports 	{gt0_txn_out[0]} ] ; 
set_property	PACKAGE_PIN	AC45	[get_ports 	{gt0_txn_out[1]} ] ; 
set_property	PACKAGE_PIN	AB47	[get_ports 	{gt0_txn_out[2]} ] ; 
set_property	PACKAGE_PIN	AA49	[get_ports 	{gt0_txn_out[3]} ] ; 
set_property	PACKAGE_PIN	AD46	[get_ports 	{gt0_txp_out[0]} ] ; 
set_property	PACKAGE_PIN	AC44	[get_ports 	{gt0_txp_out[1]} ] ; 
set_property	PACKAGE_PIN	AB46	[get_ports 	{gt0_txp_out[2]} ] ; 
set_property	PACKAGE_PIN	AA48	[get_ports 	{gt0_txp_out[3]} ] ; 