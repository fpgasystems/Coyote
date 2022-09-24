# Power constraint
set_operating_conditions -design_power_budget 160

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# Clocks and reset
set_property	PACKAGE_PIN	L30                 [get_ports  sys_resetn_nb] ; 
set_property	IOSTANDARD		LVCMOS18	    [get_ports 	sys_resetn_nb] ; 

# Reset false path
set_false_path -from [get_ports sys_resetn_nb]
#set_false_path -through [get_nets inst_int_static/xresetn[0]]
#set_false_path -through [get_nets inst_int_static/presetn[0]]
#set_false_path -through [get_nets inst_int_static/aresetn[0]]
#set_false_path -through [get_nets inst_int_static/nresetn[0]]
#set_false_path -through [get_nets inst_int_static/hresetn[0]]
#set_false_path -through [get_nets inst_int_static/uresetn[0]]

# User general purpose (156.25 MHz)
set_property	PACKAGE_PIN	F30		            [get_ports 	user_clk_clk_n] ; 
set_property	IOSTANDARD		LVDS 	        [get_ports 	user_clk_clk_n] ; 
set_property	PACKAGE_PIN	G30		            [get_ports 	user_clk_clk_p] ; 
set_property	IOSTANDARD		LVDS 	        [get_ports 	user_clk_clk_p] ; 

# HBM (100 MHz)
set_property	PACKAGE_PIN	BJ44		        [get_ports 	hbm_clk_clk_n] ; 
set_property	IOSTANDARD		LVDS 	        [get_ports 	hbm_clk_clk_n] ; 
set_property	PACKAGE_PIN	BJ43		        [get_ports 	hbm_clk_clk_p] ; 
set_property	IOSTANDARD		LVDS 	        [get_ports 	hbm_clk_clk_p] ; 

create_clock -period 10.000 -name hbmrefclk     [get_ports  hbm_clk_clk_p] ;

# Xilinx supremacy
set_property	PACKAGE_PIN	D32                 [get_ports  fpga_burn] ; 
set_property	IOSTANDARD		LVCMOS18	    [get_ports 	fpga_burn] ;
set_property    PULLDOWN TRUE                   [get_ports  fpga_burn] ;

# Manually set clk for hbm debug core
connect_debug_port dbg_hub/clk [get_nets hclk]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub] 
