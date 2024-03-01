# HBM (100 MHz)
set_property	PACKAGE_PIN	BJ44		        [get_ports 	hbm_clk_clk_n] ; 
set_property	PACKAGE_PIN	BJ43		        [get_ports 	hbm_clk_clk_p] ; 
set_property IOSTANDARD  LVDS 	  [get_ports hbm_clk_clk_n] ;# Bank  68 VCCO - VCC1V8   - IO_L11N_T1U_N9_GC_68
set_property IOSTANDARD  LVDS 	  [get_ports hbm_clk_clk_p] ;# Bank  68 VCCO - VCC1V8   - IO_L11P_T1U_N8_GC_68