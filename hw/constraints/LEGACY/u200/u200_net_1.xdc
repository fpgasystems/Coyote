###
### QSFP 1
###

# Control
set_property    PACKAGE_PIN BC18            [get_ports 	qsfp1_resetn	] ; 
set_property	IOSTANDARD		LVCMOS12	[get_ports 	qsfp1_resetn	] ;
set_property    PACKAGE_PIN AV22            [get_ports 	qsfp1_lpmode	] ; 
set_property	IOSTANDARD		LVCMOS12	[get_ports 	qsfp1_lpmode    ] ;
set_property    PACKAGE_PIN AY20            [get_ports 	qsfp1_modseln	] ; 
set_property	IOSTANDARD		LVCMOS12	[get_ports 	qsfp1_modseln   ] ;

set_false_path -to [get_ports qsfp1_resetn]
set_false_path -to [get_ports qsfp1_lpmode]
set_false_path -to [get_ports qsfp1_modseln]

# Clock (156 MHz)
set_property	PACKAGE_PIN	T10		[get_ports 	gt1_refclk_n	] ; 
set_property	PACKAGE_PIN	T11		[get_ports 	gt1_refclk_p	] ; 

# Clock (161 MHz)
#set_property	PACKAGE_PIN	P10		[get_ports 	gt1_refclk_n	] ; 
#set_property	PACKAGE_PIN	P11		[get_ports 	gt1_refclk_p	] ; 

# Transceiver
set_property	PACKAGE_PIN	U4		[get_ports 	{gt1_rxp_in[0]}	] ; 
set_property	PACKAGE_PIN	U3		[get_ports 	{gt1_rxn_in[0]}	] ; 
set_property	PACKAGE_PIN	U9		[get_ports 	{gt1_txp_out[0]} ] ;
set_property	PACKAGE_PIN	U8		[get_ports 	{gt1_txn_out[0]} ] ;
set_property	PACKAGE_PIN	T2		[get_ports 	{gt1_rxp_in[1]}	] ;
set_property	PACKAGE_PIN	T1		[get_ports 	{gt1_rxn_in[1]}	] ; 
set_property	PACKAGE_PIN	T7		[get_ports 	{gt1_txp_out[1]} ] ; 
set_property	PACKAGE_PIN	T6		[get_ports 	{gt1_txn_out[1]} ] ; 
set_property	PACKAGE_PIN	R4		[get_ports 	{gt1_rxp_in[2]}	] ; 
set_property	PACKAGE_PIN	R3		[get_ports 	{gt1_rxn_in[2]}	] ; 
set_property	PACKAGE_PIN	R9		[get_ports 	{gt1_txp_out[2]} ] ;
set_property	PACKAGE_PIN	R8		[get_ports 	{gt1_txn_out[2]} ] ;
set_property	PACKAGE_PIN	P2		[get_ports 	{gt1_rxp_in[3]}	] ; 
set_property	PACKAGE_PIN	P1		[get_ports 	{gt1_rxn_in[3]}	] ; 
set_property	PACKAGE_PIN	P7		[get_ports 	{gt1_txp_out[3]} ] ;
set_property	PACKAGE_PIN	P6		[get_ports 	{gt1_txn_out[3]} ] ; 
