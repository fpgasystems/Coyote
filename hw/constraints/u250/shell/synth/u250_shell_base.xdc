# XCLK
create_clock -period 4.000 [get_ports xclk]

# CMAC clocks
create_clock -period 6.4 [get_ports gt0_refclk_p]
create_clock -period 6.4 [get_ports gt1_refclk_p]
