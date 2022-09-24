# Board constraints
set_operating_conditions -design_power_budget 63
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
set_property PACKAGE_PIN G16      [get_ports user_clk_clk_n]       ;# Bank  68 VCCO - VCC1V8   - IO_L11N_T1U_N9_GC_68
set_property IOSTANDARD  LVDS     [get_ports user_clk_clk_n]       ;# Bank  68 VCCO - VCC1V8   - IO_L11N_T1U_N9_GC_68
set_property PACKAGE_PIN G17      [get_ports user_clk_clk_p]       ;# Bank  68 VCCO - VCC1V8   - IO_L11P_T1U_N8_GC_68
set_property IOSTANDARD  LVDS     [get_ports user_clk_clk_p]       ;# Bank  68 VCCO - VCC1V8   - IO_L11P_T1U_N8_GC_68
set_property DQS_BIAS TRUE        [get_ports user_clk_clk_p]       ;# Bank  68 VCCO - VCC1V8   - IO_L11P_T1U_N8_GC_68

set_property PACKAGE_PIN BC18     [get_ports hbm_clk_clk_n]       ;# Bank  64 VCCO - VCC1V8   - IO_L11N_T1U_N9_GC_64
set_property IOSTANDARD  LVDS     [get_ports hbm_clk_clk_n]       ;# Bank  64 VCCO - VCC1V8   - IO_L11N_T1U_N9_GC_64
set_property PACKAGE_PIN BB18     [get_ports hbm_clk_clk_p]       ;# Bank  64 VCCO - VCC1V8   - IO_L11P_T1U_N8_GC_64
set_property IOSTANDARD  LVDS     [get_ports hbm_clk_clk_p]       ;# Bank  64 VCCO - VCC1V8   - IO_L11P_T1U_N8_GC_64
set_property DQS_BIAS TRUE        [get_ports hbm_clk_clk_p]       ;# Bank  64 VCCO - VCC1V8   - IO_L11P_T1U_N8_GC_64

create_clock -period 10.000 -name hbmrefclk     [get_ports  hbm_clk_clk_p] ;

# Burn
set_property PACKAGE_PIN J18      [get_ports fpga_burn]       ;# Bank  68 VCCO - VCC1V8   - IO_L6N_T0U_N11_AD6N_68
set_property IOSTANDARD  LVCMOS18 [get_ports fpga_burn]       ;# Bank  68 VCCO - VCC1V8   - IO_L6N_T0U_N11_AD6N_68
set_property PULLDOWN TRUE        [get_ports fpga_burn]       ;# Bank  68 VCCO - VCC1V8   - IO_L6N_T0U_N11_AD6N_68

# Manually set clk for hbm debug core
connect_debug_port dbg_hub/clk [get_nets hclk]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
