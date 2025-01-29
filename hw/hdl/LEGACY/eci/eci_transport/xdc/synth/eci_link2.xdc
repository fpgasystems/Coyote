# ECI link 2
create_clock -period 6.400 -name {gt_eci_clk_p_link2[3]} -waveform {0.000 3.200} [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[0\].ref_buf_link2/I}]]]
create_clock -period 6.400 -name {gt_eci_clk_p_link2[4]} -waveform {0.000 3.200} [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[1\].ref_buf_link2/I}]]]
create_clock -period 6.400 -name {gt_eci_clk_p_link2[5]} -waveform {0.000 3.200} [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[2\].ref_buf_link2/I}]]]
