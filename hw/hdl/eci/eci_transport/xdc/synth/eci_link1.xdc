# ECI link 1
create_clock -period 6.400 -name {gt_eci_clk_p_link1[0]} -waveform {0.000 3.200} [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[0\].ref_buf_link1/I}]]]
create_clock -period 6.400 -name {gt_eci_clk_p_link1[1]} -waveform {0.000 3.200} [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[1\].ref_buf_link1/I}]]]
create_clock -period 6.400 -name {gt_eci_clk_p_link1[2]} -waveform {0.000 3.200} [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[2\].ref_buf_link1/I}]]]

create_generated_clock -name clk_sys [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/xcvr1/inst/gen_gtwizard_gtye4_top.xcvr_link1_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container\[31\].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst\[1\].GTYE4_CHANNEL_PRIM_INST/TXOUTCLK}]
