# Network clock
set_property IOSTANDARD LVDS [get_ports dclk_p]
set_property IOSTANDARD LVDS [get_ports dclk_n]

set_property PACKAGE_PIN AY24 [get_ports dclk_p]
set_property PACKAGE_PIN AY23 [get_ports dclk_n]

create_clock -period 8.000 -name dclk_clk [get_pins dclk_BUFG_inst/O]

### These are sample constraints, please use correct constraints for your device
### update the gt_refclk pin location accordingly and un-comment the below two lines
set_property PACKAGE_PIN W8 [get_ports gt_refclk_n]
set_property PACKAGE_PIN W9 [get_ports gt_refclk_p]

#QSPF28 Connector1
#set_property PACKAGE_PIN Y2 [get_ports {gt_rxp_in[0]}]
#set_property PACKAGE_PIN Y1 [get_ports {gt_rxn_in[0]}]
#set_property PACKAGE_PIN V7 [get_ports {gt_txp_out[0]}]
#set_property PACKAGE_PIN V6 [get_ports {gt_txn_out[0]}]

#set_property PACKAGE_PIN W4 [get_ports {gt_rxp_in[1]}]
#set_property PACKAGE_PIN W3 [get_ports {gt_rxn_in[1]}]
#set_property PACKAGE_PIN T7 [get_ports {gt_txp_out[1]}]
#set_property PACKAGE_PIN T6 [get_ports {gt_txn_out[1]}]

#set_property PACKAGE_PIN V2 [get_ports {gt_rxp_in[2]}]
#set_property PACKAGE_PIN V1 [get_ports {gt_rxn_in[2]}]
#set_property PACKAGE_PIN P7 [get_ports {gt_txp_out[2]}]
#set_property PACKAGE_PIN P6 [get_ports {gt_txn_out[2]}]

#set_property PACKAGE_PIN U4 [get_ports {gt_rxp_in[3]}]
#set_property PACKAGE_PIN U3 [get_ports {gt_rxn_in[3]}]
#set_property PACKAGE_PIN M7 [get_ports {gt_txp_out[3]}]
#set_property PACKAGE_PIN M6 [get_ports {gt_txn_out[3]}]

#QSPF28 Connector2
set_property PACKAGE_PIN T2 [get_ports {gt_rxp_in[0]}]
set_property PACKAGE_PIN T1 [get_ports {gt_rxn_in[0]}]
set_property PACKAGE_PIN L5 [get_ports {gt_txp_out[0]}]
set_property PACKAGE_PIN L4 [get_ports {gt_txn_out[0]}]

set_property PACKAGE_PIN R4 [get_ports {gt_rxp_in[1]}]
set_property PACKAGE_PIN R3 [get_ports {gt_rxn_in[1]}]
set_property PACKAGE_PIN K7 [get_ports {gt_txp_out[1]}]
set_property PACKAGE_PIN K6 [get_ports {gt_txn_out[1]}]

set_property PACKAGE_PIN P2 [get_ports {gt_rxp_in[2]}]
set_property PACKAGE_PIN P1 [get_ports {gt_rxn_in[2]}]
set_property PACKAGE_PIN J5 [get_ports {gt_txp_out[2]}]
set_property PACKAGE_PIN J4 [get_ports {gt_txn_out[2]}]

set_property PACKAGE_PIN M2 [get_ports {gt_rxp_in[3]}]
set_property PACKAGE_PIN M1 [get_ports {gt_rxn_in[3]}]
set_property PACKAGE_PIN H7 [get_ports {gt_txp_out[3]}]
set_property PACKAGE_PIN H6 [get_ports {gt_txn_out[3]}]

#set_property IOSTANDARD LVDS [get_ports uclk_p]
#set_property IOSTANDARD LVDS [get_ports uclk_n]

#set_property PACKAGE_PIN AW22 [get_ports uclk_n]
#set_property PACKAGE_PIN AW23 [get_ports uclk_p]

#create_clock -period 6.400 -name uclk_clk [get_pins uclk_BUFG_inst/O]

set_max_delay -datapath_only -from [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ */channel_inst/*_CHANNEL_PRIM_INST/RXOUTCLK}]] -to [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ */channel_inst/*_CHANNEL_PRIM_INST/TXOUTCLK}]] 6.400
set_max_delay -datapath_only -from [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ */channel_inst/*_CHANNEL_PRIM_INST/TXOUTCLK}]] -to [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ */channel_inst/*_CHANNEL_PRIM_INST/RXOUTCLK}]] 6.400

set_max_delay -datapath_only -from [get_clocks dclk_clk] -to [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ */channel_inst/*_CHANNEL_PRIM_INST/TXOUTCLK}]] 8.000
set_max_delay -datapath_only -from [get_clocks dclk_clk] -to [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ */channel_inst/*_CHANNEL_PRIM_INST/RXOUTCLK}]] 8.000

set_max_delay -datapath_only -from [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ */channel_inst/*_CHANNEL_PRIM_INST/RXOUTCLK}]] -to [get_clocks dclk_clk] 6.400
set_max_delay -datapath_only -from [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ */channel_inst/*_CHANNEL_PRIM_INST/TXOUTCLK}]] -to [get_clocks dclk_clk] 6.400