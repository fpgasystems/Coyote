# Aurora link to the BMC
#set_property PACKAGE_PIN BF5 [get_ports {B_C2C_RX_P}]
#set_property PACKAGE_PIN BF4 [get_ports {B_C2C_RX_N}]
#set_property PACKAGE_PIN BC2 [get_ports {B_C2C_TX_P}]
#set_property PACKAGE_PIN BC1 [get_ports {B_C2C_TX_N}]
#set_property PACKAGE_PIN AW9 [get_ports {B_C2CC_CLK_P}]
#set_property PACKAGE_PIN AW8 [get_ports {B_C2CC_CLK_N}]

# Fabric clocks
set_property PACKAGE_PIN AY26 [get_ports {prgc_clk_p[0]}]
set_property PACKAGE_PIN AY27 [get_ports {prgc_clk_n[0]}]
set_property PACKAGE_PIN AW28 [get_ports {prgc_clk_p[1]}]
set_property PACKAGE_PIN AY28 [get_ports {prgc_clk_n[1]}]

# ECI
set_property PACKAGE_PIN AT10 [get_ports {ccpi_clk_n[0]}]
set_property PACKAGE_PIN AT11 [get_ports {ccpi_clk_p[0]}]
set_property PACKAGE_PIN AM10 [get_ports {ccpi_clk_n[1]}]
set_property PACKAGE_PIN AM11 [get_ports {ccpi_clk_p[1]}]
set_property PACKAGE_PIN AH10 [get_ports {ccpi_clk_n[2]}]
set_property PACKAGE_PIN AH11 [get_ports {ccpi_clk_p[2]}]
set_property PACKAGE_PIN T11 [get_ports {ccpi_clk_p[3]}]
set_property PACKAGE_PIN T10 [get_ports {ccpi_clk_n[3]}]
set_property PACKAGE_PIN M11 [get_ports {ccpi_clk_p[4]}]
set_property PACKAGE_PIN M10 [get_ports {ccpi_clk_n[4]}]
set_property PACKAGE_PIN H11 [get_ports {ccpi_clk_p[5]}]
set_property PACKAGE_PIN H10 [get_ports {ccpi_clk_n[5]}]

set_property PACKAGE_PIN AU4 [get_ports {ccpi_0_rxp[0]}]
set_property PACKAGE_PIN AU3 [get_ports {ccpi_0_rxn[0]}]
set_property PACKAGE_PIN AU9 [get_ports {ccpi_0_txp[0]}]
set_property PACKAGE_PIN AU8 [get_ports {ccpi_0_txn[0]}]
set_property PACKAGE_PIN AT2 [get_ports {ccpi_0_rxp[1]}]
set_property PACKAGE_PIN AT1 [get_ports {ccpi_0_rxn[1]}]
set_property PACKAGE_PIN AT7 [get_ports {ccpi_0_txp[1]}]
set_property PACKAGE_PIN AT6 [get_ports {ccpi_0_txn[1]}]
set_property PACKAGE_PIN AR4 [get_ports {ccpi_0_rxp[2]}]
set_property PACKAGE_PIN AR3 [get_ports {ccpi_0_rxn[2]}]
set_property PACKAGE_PIN AR9 [get_ports {ccpi_0_txp[2]}]
set_property PACKAGE_PIN AR8 [get_ports {ccpi_0_txn[2]}]
set_property PACKAGE_PIN AP2 [get_ports {ccpi_0_rxp[3]}]
set_property PACKAGE_PIN AP1 [get_ports {ccpi_0_rxn[3]}]
set_property PACKAGE_PIN AP7 [get_ports {ccpi_0_txp[3]}]
set_property PACKAGE_PIN AP6 [get_ports {ccpi_0_txn[3]}]
set_property PACKAGE_PIN AN4 [get_ports {ccpi_0_rxp[4]}]
set_property PACKAGE_PIN AN3 [get_ports {ccpi_0_rxn[4]}]
set_property PACKAGE_PIN AN9 [get_ports {ccpi_0_txp[4]}]
set_property PACKAGE_PIN AN8 [get_ports {ccpi_0_txn[4]}]
set_property PACKAGE_PIN AM2 [get_ports {ccpi_0_rxp[5]}]
set_property PACKAGE_PIN AM1 [get_ports {ccpi_0_rxn[5]}]
set_property PACKAGE_PIN AM7 [get_ports {ccpi_0_txp[5]}]
set_property PACKAGE_PIN AM6 [get_ports {ccpi_0_txn[5]}]
set_property PACKAGE_PIN AL4 [get_ports {ccpi_0_rxp[6]}]
set_property PACKAGE_PIN AL3 [get_ports {ccpi_0_rxn[6]}]
set_property PACKAGE_PIN AL9 [get_ports {ccpi_0_txp[6]}]
set_property PACKAGE_PIN AL8 [get_ports {ccpi_0_txn[6]}]
set_property PACKAGE_PIN AK2 [get_ports {ccpi_0_rxp[7]}]
set_property PACKAGE_PIN AK1 [get_ports {ccpi_0_rxn[7]}]
set_property PACKAGE_PIN AK7 [get_ports {ccpi_0_txp[7]}]
set_property PACKAGE_PIN AK6 [get_ports {ccpi_0_txn[7]}]
set_property PACKAGE_PIN AJ4 [get_ports {ccpi_0_rxp[8]}]
set_property PACKAGE_PIN AJ3 [get_ports {ccpi_0_rxn[8]}]
set_property PACKAGE_PIN AJ9 [get_ports {ccpi_0_txp[8]}]
set_property PACKAGE_PIN AJ8 [get_ports {ccpi_0_txn[8]}]
set_property PACKAGE_PIN AH2 [get_ports {ccpi_0_rxp[9]}]
set_property PACKAGE_PIN AH1 [get_ports {ccpi_0_rxn[9]}]
set_property PACKAGE_PIN AH7 [get_ports {ccpi_0_txp[9]}]
set_property PACKAGE_PIN AH6 [get_ports {ccpi_0_txn[9]}]
set_property PACKAGE_PIN AG4 [get_ports {ccpi_0_rxp[10]}]
set_property PACKAGE_PIN AG3 [get_ports {ccpi_0_rxn[10]}]
set_property PACKAGE_PIN AG9 [get_ports {ccpi_0_txp[10]}]
set_property PACKAGE_PIN AG8 [get_ports {ccpi_0_txn[10]}]
set_property PACKAGE_PIN AF2 [get_ports {ccpi_0_rxp[11]}]
set_property PACKAGE_PIN AF1 [get_ports {ccpi_0_rxn[11]}]
set_property PACKAGE_PIN AF7 [get_ports {ccpi_0_txp[11]}]
set_property PACKAGE_PIN AF6 [get_ports {ccpi_0_txn[11]}]


# UART
set_property PACKAGE_PIN BB26 [get_ports uart_txd]
set_property PACKAGE_PIN BB27 [get_ports uart_rxd]
set_property PACKAGE_PIN BB25 [get_ports uart_cts]
set_property PACKAGE_PIN BA25 [get_ports uart_rts]

set_property PACKAGE_PIN AP21 [get_ports fmc_prsnt_n]

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


# The FMC presence signals are static.
#set_false_path -from [get_ports fmc_prsnt_n];
#set_input_delay 0 -clock clk_sys [get_ports fmc_prsnt_n];

# The UART is, naturally, asynchronous.
#set_input_delay 0 -clock clk_sys [get_ports uart_txd]
#set_output_delay 0 -clock clk_sys [get_ports uart_rxd]


set_property IOSTANDARD DIFF_SSTL12 [get_ports {prgc_clk_p[0]}]
set_property IOSTANDARD DIFF_SSTL12 [get_ports {prgc_clk_n[0]}]
set_property IOSTANDARD DIFF_SSTL12 [get_ports {prgc_clk_p[1]}]
set_property IOSTANDARD DIFF_SSTL12 [get_ports {prgc_clk_n[1]}]
set_property IOSTANDARD LVCMOS12 [get_ports uart_txd]
set_property IOSTANDARD LVCMOS12 [get_ports uart_rxd]
set_property IOSTANDARD LVCMOS12 [get_ports uart_cts]
set_property IOSTANDARD LVCMOS12 [get_ports uart_rts]
set_property IOSTANDARD LVCMOS18 [get_ports fmc_prsnt_n]
#create_clock -period 3.333 -name prgc_clk -waveform {0.000 1.666} [get_ports {prgc_clk_p[1]}]
set_false_path -from [get_ports uart_txd]
set_false_path -to [get_ports uart_rxd]

## Clock constraints
create_clock -period 6.400 -name {ccpi_clk_p[0]} -waveform {0.000 3.200} [get_ports {ccpi_clk_p[0]}]
create_clock -period 6.400 -name {ccpi_clk_p[1]} -waveform {0.000 3.200} [get_ports {ccpi_clk_p[1]}]
create_clock -period 6.400 -name {ccpi_clk_p[2]} -waveform {0.000 3.200} [get_ports {ccpi_clk_p[2]}]
create_clock -period 6.400 -name {ccpi_clk_p[3]} -waveform {0.000 3.200} [get_ports {ccpi_clk_p[3]}]
create_clock -period 6.400 -name {ccpi_clk_p[4]} -waveform {0.000 3.200} [get_ports {ccpi_clk_p[4]}]
create_clock -period 6.400 -name {ccpi_clk_p[5]} -waveform {0.000 3.200} [get_ports {ccpi_clk_p[5]}]

####################################################################################
# Constraints from file : 'design_static_auto_cc_0_clocks.xdc'
####################################################################################

