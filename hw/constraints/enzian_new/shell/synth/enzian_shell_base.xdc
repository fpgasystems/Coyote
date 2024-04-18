# XCLK
create_clock -period 3.333 [get_ports xclk]

# CMAC clocks
create_clock -period 3.103 [get_ports gt0_refclk_p]
create_clock -period 3.103 [get_ports gt1_refclk_p]