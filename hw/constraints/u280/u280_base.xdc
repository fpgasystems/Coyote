# Power constraint
set_operating_conditions -design_power_budget 160

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# Clocks and reset
set_property	PACKAGE_PIN	L30                 [get_ports  resetn_0_nb] ; 
set_property	IOSTANDARD		LVCMOS18	    [get_ports 	resetn_0_nb] ; 

# Reset false path
set_false_path -from [get_ports resetn_0_nb]

# User general purpose (156.25 MHz)
set_property	PACKAGE_PIN	F30		            [get_ports 	user_si570_clk_n] ; 
set_property	IOSTANDARD		LVDS 	        [get_ports 	user_si570_clk_n] ; 
set_property	PACKAGE_PIN	G30		            [get_ports 	user_si570_clk_p] ; 
set_property	IOSTANDARD		LVDS 	        [get_ports 	user_si570_clk_p] ; 

# HBM (100 MHz)
set_property	PACKAGE_PIN	F31		            [get_ports 	sysclk3_100_n] ; 
set_property	IOSTANDARD		LVDS 	        [get_ports 	sysclk3_100_n] ; 
set_property	PACKAGE_PIN	G31		            [get_ports 	sysclk3_100_p] ; 
set_property	IOSTANDARD		LVDS 	        [get_ports 	sysclk3_100_p] ; 

create_clock -period 10.000 -name sysclk3         [get_ports sysclk3_100_p]

# Xilinx supremacy
set_property	PACKAGE_PIN	D32                 [get_ports  fpga_burn] ; 
set_property	IOSTANDARD		LVCMOS18	    [get_ports 	fpga_burn] ; 