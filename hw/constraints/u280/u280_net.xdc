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
set_property	PACKAGE_PIN	L49	    [get_ports 	{gt0_txn_in[0]}	] ; 
set_property	PACKAGE_PIN	L45	    [get_ports 	{gt0_txn_in[1]}	] ; 
set_property	PACKAGE_PIN	K47	    [get_ports 	{gt0_txn_in[2]}	] ; 
set_property	PACKAGE_PIN	J49	    [get_ports 	{gt0_txn_in[3]}	] ; 
set_property	PACKAGE_PIN	L48	    [get_ports 	{gt0_txp_in[0]}	] ; 
set_property	PACKAGE_PIN	L44	    [get_ports 	{gt0_txp_in[1]}	] ; 
set_property	PACKAGE_PIN	K46	    [get_ports 	{gt0_txp_in[2]}	] ; 
set_property	PACKAGE_PIN	J48	    [get_ports 	{gt0_txp_in[3]}	] ; 

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
set_property	PACKAGE_PIN	G49	    [get_ports 	{gt1_txn_in[0]}	] ; 
set_property	PACKAGE_PIN	E49	    [get_ports 	{gt1_txn_in[1]}	] ; 
set_property	PACKAGE_PIN	C49	    [get_ports 	{gt1_txn_in[2]}	] ; 
set_property	PACKAGE_PIN	A50	    [get_ports 	{gt1_txn_in[3]}	] ; 
set_property	PACKAGE_PIN	G48	    [get_ports 	{gt1_txp_in[0]}	] ; 
set_property	PACKAGE_PIN	E48	    [get_ports 	{gt1_txp_in[1]}	] ; 
set_property	PACKAGE_PIN	C48	    [get_ports 	{gt1_txp_in[2]}	] ; 
set_property	PACKAGE_PIN	A49	    [get_ports 	{gt1_txp_in[3]}	] ; 