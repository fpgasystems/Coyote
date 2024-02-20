###
### QSFP 1
###

# Clock (161.1328125 MHz)
set_property	PACKAGE_PIN	AB43	[get_ports 	gt1_refclk_n	] ; 
set_property	PACKAGE_PIN	AB42	[get_ports 	gt1_refclk_p	] ; 

# Clock (322.265625 MHz)
#set_property	PACKAGE_PIN	M39		[get_ports 	gt0_refclk_n	] ; 
#set_property	PACKAGE_PIN	M38		[get_ports 	gt0_refclk_p	] ; 

# Transceiver
set_property	PACKAGE_PIN	AA54	[get_ports 	{gt1_rxn_in[0]}	] ; 
set_property	PACKAGE_PIN	Y52	    [get_ports 	{gt1_rxn_in[1]}	] ; 
set_property	PACKAGE_PIN	W54	    [get_ports 	{gt1_rxn_in[2]}	] ; 
set_property	PACKAGE_PIN	V52	    [get_ports 	{gt1_rxn_in[3]}	] ; 
set_property	PACKAGE_PIN	AA53	[get_ports 	{gt1_rxp_in[0]}	] ; 
set_property	PACKAGE_PIN	Y51	    [get_ports 	{gt1_rxp_in[1]}	] ; 
set_property	PACKAGE_PIN	W53	    [get_ports 	{gt1_rxp_in[2]}	] ; 
set_property	PACKAGE_PIN	V51	    [get_ports 	{gt1_rxp_in[3]}	] ; 
set_property	PACKAGE_PIN	AA45	[get_ports 	{gt1_txn_out[0]} ] ; 
set_property	PACKAGE_PIN	Y47	    [get_ports 	{gt1_txn_out[1]} ] ; 
set_property	PACKAGE_PIN	W49	    [get_ports 	{gt1_txn_out[2]} ] ; 
set_property	PACKAGE_PIN	W45	    [get_ports 	{gt1_txn_out[3]} ] ; 
set_property	PACKAGE_PIN	AA44	[get_ports 	{gt1_txp_out[0]} ] ; 
set_property	PACKAGE_PIN	Y46	    [get_ports 	{gt1_txp_out[1]} ] ; 
set_property	PACKAGE_PIN	W48	    [get_ports 	{gt1_txp_out[2]} ] ; 
set_property	PACKAGE_PIN	W44	    [get_ports 	{gt1_txp_out[3]} ] ; 
