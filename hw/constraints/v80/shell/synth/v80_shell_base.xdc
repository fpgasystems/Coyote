# Shell clock
create_clock -period 4.000 [get_ports xclk];

# Placeholder: CMAC clocks --- TODO: Modify accordingly for V80 when adding network support
create_clock -period 6.206 [get_ports gt0_refclk_p];
create_clock -period 6.206 [get_ports gt1_refclk_p];

# Placedholder: Debug clock --- TODO: Remove, when debug bridges fully removed
create_clock -period 10.000 [get_ports dclk];
