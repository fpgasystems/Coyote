###
### QSFP 0
###

# Clock (161.1328125 MHz)
set_property	PACKAGE_PIN	N37		[get_ports 	gt0_refclk_n	] ; 
set_property	PACKAGE_PIN	N36		[get_ports 	gt0_refclk_p	] ; 

# Clock (322.265625 MHz)
#set_property	PACKAGE_PIN	M39		[get_ports 	gt0_refclk_n	] ; 
#set_property	PACKAGE_PIN	M38		[get_ports 	gt0_refclk_p	] ; 

# Transceiver
set_property	PACKAGE_PIN	J46		[get_ports 	{gt0_rxn_in[0]}	] ; 
set_property	PACKAGE_PIN	G46		[get_ports 	{gt0_rxn_in[1]}	] ; 
set_property	PACKAGE_PIN	F44		[get_ports 	{gt0_rxn_in[2]}	] ; 
set_property	PACKAGE_PIN	E46		[get_ports 	{gt0_rxn_in[3]}	] ; 
set_property	PACKAGE_PIN	J45		[get_ports 	{gt0_rxp_in[0]}	] ; 
set_property	PACKAGE_PIN	G45		[get_ports 	{gt0_rxp_in[1]}	] ; 
set_property	PACKAGE_PIN	F43		[get_ports 	{gt0_rxp_in[2]}	] ; 
set_property	PACKAGE_PIN	E45		[get_ports 	{gt0_rxp_in[3]}	] ; 
set_property	PACKAGE_PIN	D43		[get_ports 	{gt0_txn_out[0]}	] ; 
set_property	PACKAGE_PIN	C41		[get_ports 	{gt0_txn_out[1]}	] ; 
set_property	PACKAGE_PIN	B43		[get_ports 	{gt0_txn_out[2]}	] ; 
set_property	PACKAGE_PIN	A41		[get_ports 	{gt0_txn_out[3]}	] ; 
set_property	PACKAGE_PIN	D42		[get_ports 	{gt0_txp_out[0]}	] ; 
set_property	PACKAGE_PIN	C40		[get_ports 	{gt0_txp_out[1]}	] ; 
set_property	PACKAGE_PIN	B42		[get_ports 	{gt0_txp_out[2]}	] ; 
set_property	PACKAGE_PIN	A40		[get_ports 	{gt0_txp_out[3]}	] ; 
