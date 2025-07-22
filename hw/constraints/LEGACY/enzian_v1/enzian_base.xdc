# ECI link 1
create_clock -period 6.400 -name {gt_eci_clk_p_link1[0]} -waveform {0.000 3.200} [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[0\].ref_buf_link1/I}]]]
create_clock -period 6.400 -name {gt_eci_clk_p_link1[1]} -waveform {0.000 3.200} [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[1\].ref_buf_link1/I}]]]
create_clock -period 6.400 -name {gt_eci_clk_p_link1[2]} -waveform {0.000 3.200} [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[2\].ref_buf_link1/I}]]]

create_generated_clock -name clk_sys [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/xcvr1/inst/gen_gtwizard_gtye4_top.xcvr_link1_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container\[31\].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst\[1\].GTYE4_CHANNEL_PRIM_INST/TXOUTCLK}]

# ECI link 2
create_clock -period 6.400 -name {gt_eci_clk_p_link2[3]} -waveform {0.000 3.200} [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[0\].ref_buf_link2/I}]]]
create_clock -period 6.400 -name {gt_eci_clk_p_link2[4]} -waveform {0.000 3.200} [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[1\].ref_buf_link2/I}]]]
create_clock -period 6.400 -name {gt_eci_clk_p_link2[5]} -waveform {0.000 3.200} [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[2\].ref_buf_link2/I}]]]

# ECI link 1
set_property PACKAGE_PIN AT11 [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[0\].ref_buf_link1/I}]]]
set_property PACKAGE_PIN AT10 [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[0\].ref_buf_link1/IB}]]]
set_property PACKAGE_PIN AM11 [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[1\].ref_buf_link1/I}]]]
set_property PACKAGE_PIN AM10 [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[1\].ref_buf_link1/IB}]]]
set_property PACKAGE_PIN AH11 [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[2\].ref_buf_link1/I}]]]
set_property PACKAGE_PIN AH10 [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[2\].ref_buf_link1/IB}]]]

# Disable delay alignment
set_property RXSYNC_SKIP_DA 1'b1 [get_cells -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/xcvr1/inst/gen_gtwizard_gtye4_top.xcvr_link.*GTYE4_CHANNEL_PRIM_INST}]

create_clock -period 6.400 -name {gt_eci_clk_p_link1[0]} -waveform {0.000 3.200} [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[0\].ref_buf_link1/I}]]]
create_clock -period 6.400 -name {gt_eci_clk_p_link1[1]} -waveform {0.000 3.200} [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[1\].ref_buf_link1/I}]]]
create_clock -period 6.400 -name {gt_eci_clk_p_link1[2]} -waveform {0.000 3.200} [get_ports -of_objects [get_nets -of [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/eci_refclks\[2\].ref_buf_link1/I}]]]

create_generated_clock -name clk_sys [get_pins -hierarchical -regexp -filter {NAME =~ .*i_eci_transport/xcvr1/inst/gen_gtwizard_gtye4_top.xcvr_link1_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container\[31\].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst\[1\].GTYE4_CHANNEL_PRIM_INST/TXOUTCLK}]

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


# Fabric clocks
set_property PACKAGE_PIN AY26 [get_ports {prgc_clk_p[0]}]
set_property PACKAGE_PIN AY27 [get_ports {prgc_clk_n[0]}]
set_property PACKAGE_PIN AW28 [get_ports {prgc_clk_p[1]}]
set_property PACKAGE_PIN AY28 [get_ports {prgc_clk_n[1]}]

## ECI
#set_property PACKAGE_PIN AT10 [get_ports {ccpi_clk_n[0]}]
#set_property PACKAGE_PIN AT11 [get_ports {ccpi_clk_p[0]}]
#set_property PACKAGE_PIN AM10 [get_ports {ccpi_clk_n[1]}]
#set_property PACKAGE_PIN AM11 [get_ports {ccpi_clk_p[1]}]
#set_property PACKAGE_PIN AH10 [get_ports {ccpi_clk_n[2]}]
#set_property PACKAGE_PIN AH11 [get_ports {ccpi_clk_p[2]}]
#set_property PACKAGE_PIN T11 [get_ports {ccpi_clk_p[3]}]
#set_property PACKAGE_PIN T10 [get_ports {ccpi_clk_n[3]}]
#set_property PACKAGE_PIN M11 [get_ports {ccpi_clk_p[4]}]
#set_property PACKAGE_PIN M10 [get_ports {ccpi_clk_n[4]}]
#set_property PACKAGE_PIN H11 [get_ports {ccpi_clk_p[5]}]
#set_property PACKAGE_PIN H10 [get_ports {ccpi_clk_n[5]}]
#
#set_property PACKAGE_PIN AU4 [get_ports {ccpi_0_rxp[0]}]
#set_property PACKAGE_PIN AU3 [get_ports {ccpi_0_rxn[0]}]
#set_property PACKAGE_PIN AU9 [get_ports {ccpi_0_txp[0]}]
#set_property PACKAGE_PIN AU8 [get_ports {ccpi_0_txn[0]}]
#set_property PACKAGE_PIN AT2 [get_ports {ccpi_0_rxp[1]}]
#set_property PACKAGE_PIN AT1 [get_ports {ccpi_0_rxn[1]}]
#set_property PACKAGE_PIN AT7 [get_ports {ccpi_0_txp[1]}]
#set_property PACKAGE_PIN AT6 [get_ports {ccpi_0_txn[1]}]
#set_property PACKAGE_PIN AR4 [get_ports {ccpi_0_rxp[2]}]
#set_property PACKAGE_PIN AR3 [get_ports {ccpi_0_rxn[2]}]
#set_property PACKAGE_PIN AR9 [get_ports {ccpi_0_txp[2]}]
#set_property PACKAGE_PIN AR8 [get_ports {ccpi_0_txn[2]}]
#set_property PACKAGE_PIN AP2 [get_ports {ccpi_0_rxp[3]}]
#set_property PACKAGE_PIN AP1 [get_ports {ccpi_0_rxn[3]}]
#set_property PACKAGE_PIN AP7 [get_ports {ccpi_0_txp[3]}]
#set_property PACKAGE_PIN AP6 [get_ports {ccpi_0_txn[3]}]
#set_property PACKAGE_PIN AN4 [get_ports {ccpi_0_rxp[4]}]
#set_property PACKAGE_PIN AN3 [get_ports {ccpi_0_rxn[4]}]
#set_property PACKAGE_PIN AN9 [get_ports {ccpi_0_txp[4]}]
#set_property PACKAGE_PIN AN8 [get_ports {ccpi_0_txn[4]}]
#set_property PACKAGE_PIN AM2 [get_ports {ccpi_0_rxp[5]}]
#set_property PACKAGE_PIN AM1 [get_ports {ccpi_0_rxn[5]}]
#set_property PACKAGE_PIN AM7 [get_ports {ccpi_0_txp[5]}]
#set_property PACKAGE_PIN AM6 [get_ports {ccpi_0_txn[5]}]
#set_property PACKAGE_PIN AL4 [get_ports {ccpi_0_rxp[6]}]
#set_property PACKAGE_PIN AL3 [get_ports {ccpi_0_rxn[6]}]
#set_property PACKAGE_PIN AL9 [get_ports {ccpi_0_txp[6]}]
#set_property PACKAGE_PIN AL8 [get_ports {ccpi_0_txn[6]}]
#set_property PACKAGE_PIN AK2 [get_ports {ccpi_0_rxp[7]}]
#set_property PACKAGE_PIN AK1 [get_ports {ccpi_0_rxn[7]}]
#set_property PACKAGE_PIN AK7 [get_ports {ccpi_0_txp[7]}]
#set_property PACKAGE_PIN AK6 [get_ports {ccpi_0_txn[7]}]
#set_property PACKAGE_PIN AJ4 [get_ports {ccpi_0_rxp[8]}]
#set_property PACKAGE_PIN AJ3 [get_ports {ccpi_0_rxn[8]}]
#set_property PACKAGE_PIN AJ9 [get_ports {ccpi_0_txp[8]}]
#set_property PACKAGE_PIN AJ8 [get_ports {ccpi_0_txn[8]}]
#set_property PACKAGE_PIN AH2 [get_ports {ccpi_0_rxp[9]}]
#set_property PACKAGE_PIN AH1 [get_ports {ccpi_0_rxn[9]}]
#set_property PACKAGE_PIN AH7 [get_ports {ccpi_0_txp[9]}]
#set_property PACKAGE_PIN AH6 [get_ports {ccpi_0_txn[9]}]
#set_property PACKAGE_PIN AG4 [get_ports {ccpi_0_rxp[10]}]
#set_property PACKAGE_PIN AG3 [get_ports {ccpi_0_rxn[10]}]
#set_property PACKAGE_PIN AG9 [get_ports {ccpi_0_txp[10]}]
#set_property PACKAGE_PIN AG8 [get_ports {ccpi_0_txn[10]}]
#set_property PACKAGE_PIN AF2 [get_ports {ccpi_0_rxp[11]}]
#set_property PACKAGE_PIN AF1 [get_ports {ccpi_0_rxn[11]}]
#set_property PACKAGE_PIN AF7 [get_ports {ccpi_0_txp[11]}]
#set_property PACKAGE_PIN AF6 [get_ports {ccpi_0_txn[11]}]

# Slave serial configuration
set_property CONFIG_MODE S_SERIAL [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 170.0 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# set_property C_CLK_INPUT_FREQ_HZ 75000000 [get_debug_cores dbg_hub]
# set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
# set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
# connect_debug_port dbg_hub/clk [get_nets clk_75mhz_0_g]

### Timing constraints for the Enzian v3

set_property IOSTANDARD DIFF_SSTL12 [get_ports {prgc_clk_p[0]}]
set_property IOSTANDARD DIFF_SSTL12 [get_ports {prgc_clk_n[0]}]
set_property IOSTANDARD DIFF_SSTL12 [get_ports {prgc_clk_p[1]}]
set_property IOSTANDARD DIFF_SSTL12 [get_ports {prgc_clk_n[1]}]
#create_clock -period 3.333 -name prgc_clk -waveform {0.000 1.666} [get_ports {prgc_clk_p[1]}]

### Clock constraints
#create_clock -period 6.400 -name {ccpi_clk_p[0]} -waveform {0.000 3.200} [get_ports {ccpi_clk_p[0]}]
#create_clock -period 6.400 -name {ccpi_clk_p[1]} -waveform {0.000 3.200} [get_ports {ccpi_clk_p[1]}]
#create_clock -period 6.400 -name {ccpi_clk_p[2]} -waveform {0.000 3.200} [get_ports {ccpi_clk_p[2]}]
#create_clock -period 6.400 -name {ccpi_clk_p[3]} -waveform {0.000 3.200} [get_ports {ccpi_clk_p[3]}]
#create_clock -period 6.400 -name {ccpi_clk_p[4]} -waveform {0.000 3.200} [get_ports {ccpi_clk_p[4]}]
#create_clock -period 6.400 -name {ccpi_clk_p[5]} -waveform {0.000 3.200} [get_ports {ccpi_clk_p[5]}]

