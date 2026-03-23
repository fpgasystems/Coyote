##
## QSFP 0
##

# Reference clock (322 MHz)
set_property    PACKAGE_PIN AR51    [get_ports 	gt0_refclk_p]; 

# Transceiver connections
set_property    PACKAGE_PIN AE67    [get_ports  {gt0_rxp_in[0]} ];
set_property    PACKAGE_PIN AE64    [get_ports  {gt0_rxp_in[1]} ];
set_property    PACKAGE_PIN AC67    [get_ports  {gt0_rxp_in[2]} ];
set_property    PACKAGE_PIN AC64    [get_ports  {gt0_rxp_in[3]} ];

set_property    PACKAGE_PIN AG61    [get_ports  {gt0_txp_out[0]} ];  
set_property    PACKAGE_PIN AG58    [get_ports  {gt0_txp_out[1]} ];
set_property    PACKAGE_PIN AE61    [get_ports  {gt0_txp_out[2]} ];
set_property    PACKAGE_PIN AE58    [get_ports  {gt0_txp_out[3]} ];
