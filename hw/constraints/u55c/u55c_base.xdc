# Board constraints
# Bitstream Generation for QSPI                              
#set_property CONFIG_VOLTAGE 1.8                        [current_design]
   
#set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN disable [current_design]
#set_property BITSTREAM.CONFIG.CONFIGRATE 63.8          [current_design] 
##set_property BITSTREAM.CONFIG.CONFIGRATE 85.0          [current_design]                 ;# Customer can try but may not be reliable over all conditions.
#set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4           [current_design]  
#set_property BITSTREAM.GENERAL.COMPRESS TRUE           [current_design]  
#set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES        [current_design]
#set_property BITSTREAM.CONFIG.SPI_OPCODE 8'h6B         [current_design]
#set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR Yes       [current_design]
#set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup         [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# Clocks
set_property PACKAGE_PIN F23      [get_ports user_clk_clk_n] ;# Bank  72 VCCO - VCC1V8   - IO_L11N_T1U_N9_GC_72_F23
set_property IOSTANDARD  LVDS 	  [get_ports user_clk_clk_n] ;# Bank  72 VCCO - VCC1V8   - IO_L11N_T1U_N9_GC_72_F23
set_property PACKAGE_PIN F24      [get_ports user_clk_clk_p] ;# Bank  72 VCCO - VCC1V8   - IO_L11P_T1U_N8_GC_72_F24
set_property IOSTANDARD  LVDS 	  [get_ports user_clk_clk_p] ;# Bank  72 VCCO - VCC1V8   - IO_L11P_T1U_N8_GC_72_F24  

#set_property PACKAGE_PIN BK44     [get_ports sysclk3_n] ;# Bank  65 VCCO - VCC1V8   - IO_L11N_T1U_N9_GC_A11_D27_65
#set_property IOSTANDARD  LVDS 	  [get_ports sysclk3_n] ;# Bank  65 VCCO - VCC1V8   - IO_L11N_T1U_N9_GC_A11_D27_65
#set_property PACKAGE_PIN BK43     [get_ports sysclk3_p] ;# Bank  65 VCCO - VCC1V8   - IO_L11P_T1U_N8_GC_A10_D26_65
#set_property IOSTANDARD  LVDS 	  [get_ports sysclk3_p] ;# Bank  65 VCCO - VCC1V8   - IO_L11P_T1U_N8_GC_A10_D26_65
set_property PACKAGE_PIN BL10     [get_ports hbm_clk_clk_n] ;# Bank  68 VCCO - VCC1V8   - IO_L11N_T1U_N9_GC_68
set_property IOSTANDARD  LVDS 	  [get_ports hbm_clk_clk_n] ;# Bank  68 VCCO - VCC1V8   - IO_L11N_T1U_N9_GC_68
set_property PACKAGE_PIN BK10     [get_ports hbm_clk_clk_p] ;# Bank  68 VCCO - VCC1V8   - IO_L11P_T1U_N8_GC_68
set_property IOSTANDARD  LVDS 	  [get_ports hbm_clk_clk_p] ;# Bank  68 VCCO - VCC1V8   - IO_L11P_T1U_N8_GC_68

create_clock -period 10.000 -name hbmrefclk     [get_ports  hbm_clk_clk_p] ;

# Burn
set_property PACKAGE_PIN BE45     [get_ports fpga_burn]       ;# Bank  68 VCCO - VCC1V8   - IO_L6N_T0U_N11_AD6N_68
set_property IOSTANDARD  LVCMOS18 [get_ports fpga_burn]       ;# Bank  68 VCCO - VCC1V8   - IO_L6N_T0U_N11_AD6N_68
set_property PULLDOWN TRUE        [get_ports fpga_burn]       ;# Bank  68 VCCO - VCC1V8   - IO_L6N_T0U_N11_AD6N_68

# Manually set clk for hbm debug core
connect_debug_port dbg_hub/clk [get_nets hclk]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub] 
