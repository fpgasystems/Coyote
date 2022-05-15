###
### QSFP 1
###

# Clock (156 MHz)
set_property	PACKAGE_PIN	P43		[get_ports 	gt1_refclk_n	] ; 
set_property	PACKAGE_PIN	P42		[get_ports 	gt1_refclk_p	] ; 

# Clock (161 MHz)
#set_property	PACKAGE_PIN	M43		[get_ports 	gt1_refclk_n	] ; 
#set_property	PACKAGE_PIN	M42		[get_ports 	gt1_refclk_p	] ; 

# Transceiver
set_property	PACKAGE_PIN	G54	    [get_ports 	{gt1_rxn_in[0]}	] ; 
set_property	PACKAGE_PIN	F52	    [get_ports 	{gt1_rxn_in[1]}	] ; 
set_property	PACKAGE_PIN	E54	    [get_ports 	{gt1_rxn_in[2]}	] ; 
set_property	PACKAGE_PIN	D52	    [get_ports 	{gt1_rxn_in[3]}	] ; 
set_property	PACKAGE_PIN	G53	    [get_ports 	{gt1_rxp_in[0]}	] ; 
set_property	PACKAGE_PIN	F51	    [get_ports 	{gt1_rxp_in[1]}	] ; 
set_property	PACKAGE_PIN	E53	    [get_ports 	{gt1_rxp_in[2]}	] ; 
set_property	PACKAGE_PIN	D51	    [get_ports 	{gt1_rxp_in[3]}	] ; 
set_property	PACKAGE_PIN	G49	    [get_ports 	{gt1_txn_out[0]} ] ; 
set_property	PACKAGE_PIN	E49	    [get_ports 	{gt1_txn_out[1]} ] ; 
set_property	PACKAGE_PIN	C49	    [get_ports 	{gt1_txn_out[2]} ] ; 
set_property	PACKAGE_PIN	A50	    [get_ports 	{gt1_txn_out[3]} ] ; 
set_property	PACKAGE_PIN	G48	    [get_ports 	{gt1_txp_out[0]} ] ; 
set_property	PACKAGE_PIN	E48	    [get_ports 	{gt1_txp_out[1]} ] ; 
set_property	PACKAGE_PIN	C48	    [get_ports 	{gt1_txp_out[2]} ] ; 
set_property	PACKAGE_PIN	A49	    [get_ports 	{gt1_txp_out[3]} ] ; 