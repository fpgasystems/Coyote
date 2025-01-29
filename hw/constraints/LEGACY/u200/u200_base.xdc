# Board constraints
# Bitstream Generation for QSPI                              
#set_property CONFIG_VOLTAGE 1.8                        [current_design]
#set_property BITSTREAM.CONFIG.CONFIGFALLBACK Enable    [current_design]                  ;# Golden image is the fall back image if  new bitstream is corrupted.    
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

# Clocks and reset
set_property PACKAGE_PIN AL20 [get_ports sys_resetn_nb]

# Reset false path

# User general purpose (156.25 MHz)
set_property PACKAGE_PIN AU19 [get_ports {user_clk_clk_p[0]}]
set_property PACKAGE_PIN AV19 [get_ports {user_clk_clk_n[0]}]

set_operating_conditions -design_power_budget 160
set_property IOSTANDARD LVCMOS12 [get_ports sys_resetn_nb]
set_false_path -from [get_ports sys_resetn_nb]
set_property IOSTANDARD LVDS [get_ports {user_clk_clk_n[0]}]
set_property IOSTANDARD LVDS [get_ports {user_clk_clk_p[0]}]

####################################################################################
# Constraints from file : 'u250_pcie.xdc'
####################################################################################

