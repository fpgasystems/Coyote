# ECI link 2
set_property PACKAGE_PIN T11 [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[0\].ref_buf_link2/I}]]]
set_property PACKAGE_PIN T10 [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[0\].ref_buf_link2/IB}]]]
set_property PACKAGE_PIN M11 [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[1\].ref_buf_link2/I}]]]
set_property PACKAGE_PIN M10 [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[1\].ref_buf_link2/IB}]]]
set_property PACKAGE_PIN H11 [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[2\].ref_buf_link2/I}]]]
set_property PACKAGE_PIN H10 [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[2\].ref_buf_link2/IB}]]]

# Disable delay alignment
set_property RXSYNC_SKIP_DA 1'b1 [get_cells -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/xcvr2/inst/gen_gtwizard_gtye4_top.xcvr_link.*GTYE4_CHANNEL_PRIM_INST}]

create_clock -period 6.400 -name {gt_eci_clk_p_link2[3]} -waveform {0.000 3.200} [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[0\].ref_buf_link2/I}]]]
create_clock -period 6.400 -name {gt_eci_clk_p_link2[4]} -waveform {0.000 3.200} [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[1\].ref_buf_link2/I}]]]
create_clock -period 6.400 -name {gt_eci_clk_p_link2[5]} -waveform {0.000 3.200} [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[2\].ref_buf_link2/I}]]]
