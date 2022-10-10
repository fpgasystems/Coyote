set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# Clock and reset

# User general purpose (300 MHz)
set_property PACKAGE_PIN AU19 [get_ports {user_clk_clk_p[0]}]
set_property PACKAGE_PIN AV19 [get_ports {user_clk_clk_n[0]}]

# Reset
set_property PACKAGE_PIN BB24 [get_ports sys_reset_nb]
set_property IOSTANDARD LVCMOS18 [get_ports sys_reset_nb]

# Reset false path
set_false_path -from [get_ports sys_reset_nb]
set_false_path -from [get_pins {design_static_i/proc_sys_reset_1/U0/ACTIVE_LOW_PR_OUT_DFF[0].FDRE_PER_N/C}]

