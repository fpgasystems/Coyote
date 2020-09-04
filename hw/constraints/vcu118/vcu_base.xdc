set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# Clock and reset

# Use the 300MHz system clock.

# Reset
set_property PACKAGE_PIN BB24 [get_ports reset_0_nb]
set_property IOSTANDARD LVCMOS18 [get_ports reset_0_nb]

# Reset false path
set_false_path -from [get_ports reset_0_nb]
set_false_path -from [get_pins {design_static_i/proc_sys_reset_1/U0/ACTIVE_LOW_PR_OUT_DFF[0].FDRE_PER_N/C}]

