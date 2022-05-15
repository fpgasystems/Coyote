###
### QSFP 0
###

# Clock (156.25 MHz)
set_property	PACKAGE_PIN	T43		[get_ports 	gt0_refclk_n	] ; 
set_property	PACKAGE_PIN	T42		[get_ports 	gt0_refclk_p	] ; 

# Clock (161 MHz)
#set_property	PACKAGE_PIN	R41		[get_ports 	gt0_refclk_n	] ; 
#set_property	PACKAGE_PIN	R40		[get_ports 	gt0_refclk_p	] ; 

# Transceiver
set_property	PACKAGE_PIN	L54	    [get_ports 	{gt0_rxn_in[0]}	] ; 
set_property	PACKAGE_PIN	K52	    [get_ports 	{gt0_rxn_in[1]}	] ; 
set_property	PACKAGE_PIN	J54	    [get_ports 	{gt0_rxn_in[2]}	] ; 
set_property	PACKAGE_PIN	H52	    [get_ports 	{gt0_rxn_in[3]}	] ; 
set_property	PACKAGE_PIN	L53	    [get_ports 	{gt0_rxp_in[0]}	] ; 
set_property	PACKAGE_PIN	K51	    [get_ports 	{gt0_rxp_in[1]}	] ; 
set_property	PACKAGE_PIN	J53	    [get_ports 	{gt0_rxp_in[2]}	] ; 
set_property	PACKAGE_PIN	H51	    [get_ports 	{gt0_rxp_in[3]}	] ; 
set_property	PACKAGE_PIN	L49	    [get_ports 	{gt0_txn_out[0]} ] ; 
set_property	PACKAGE_PIN	L45	    [get_ports 	{gt0_txn_out[1]} ] ; 
set_property	PACKAGE_PIN	K47	    [get_ports 	{gt0_txn_out[2]} ] ; 
set_property	PACKAGE_PIN	J49	    [get_ports 	{gt0_txn_out[3]} ] ; 
set_property	PACKAGE_PIN	L48	    [get_ports 	{gt0_txp_out[0]} ] ; 
set_property	PACKAGE_PIN	L44	    [get_ports 	{gt0_txp_out[1]} ] ; 
set_property	PACKAGE_PIN	K46	    [get_ports 	{gt0_txp_out[2]} ] ; 
set_property	PACKAGE_PIN	J48	    [get_ports 	{gt0_txp_out[3]} ] ; 