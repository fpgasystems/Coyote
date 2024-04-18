# Generate ECI transceivers
# Instantiate link 1 transceivers (0-11)
create_ip -name gtwizard_ultrascale -vendor xilinx.com -library ip \
          -module_name xcvr_link1
set_property -dict [list \
    CONFIG.preset {GTY-10GBASE-KR}] [get_ips xcvr_link1]

set_property -dict [list \
CONFIG.CHANNEL_ENABLE {X1Y35 X1Y34 X1Y33 X1Y32 \
                        X1Y31 X1Y30 X1Y29 X1Y28 \
                        X1Y27 X1Y26 X1Y25 X1Y24} \
CONFIG.TX_MASTER_CHANNEL {X1Y29} \
CONFIG.RX_MASTER_CHANNEL {X1Y29} \
CONFIG.TX_LINE_RATE {10.3125} \
CONFIG.TX_REFCLK_FREQUENCY {156.25} \
CONFIG.RX_BUFFER_MODE {0} \
CONFIG.RX_LINE_RATE {10.3125} \
CONFIG.RX_REFCLK_FREQUENCY {156.25} \
CONFIG.RX_JTOL_FC {3.7492501} \
CONFIG.RX_EQ_MODE {LPM} \
CONFIG.INS_LOSS_NYQ {3} \
CONFIG.TX_BUFFER_MODE {0} \
CONFIG.TX_DATA_ENCODING {64B67B} \
CONFIG.TX_DIFF_SWING_EMPH_MODE {CUSTOM} \
CONFIG.TX_USER_DATA_WIDTH {64} \
CONFIG.TX_INT_DATA_WIDTH {32} \
CONFIG.RX_DATA_DECODING {64B67B} \
CONFIG.RX_USER_DATA_WIDTH {64} \
CONFIG.RX_INT_DATA_WIDTH {32} \
CONFIG.RX_CB_MAX_LEVEL {6} \
CONFIG.ENABLE_OPTIONAL_PORTS { \
    txdiffctrl_in txpostcursor_in txprecursor_in} \
CONFIG.LOCATE_TX_USER_CLOCKING {EXAMPLE_DESIGN} \
CONFIG.LOCATE_RX_USER_CLOCKING {EXAMPLE_DESIGN} \
CONFIG.FREERUN_FREQUENCY {100}] \
[get_ips xcvr_link1]

generate_target all [get_ips xcvr_link1]

# Instantiate link 2 transceivers (12-23)
create_ip -name gtwizard_ultrascale -vendor xilinx.com -library ip \
          -module_name xcvr_link2
set_property -dict [list \
    CONFIG.preset {GTY-10GBASE-KR}] [get_ips xcvr_link2]


set_property -dict [list \
CONFIG.CHANNEL_ENABLE {X1Y55 X1Y54 X1Y53 X1Y52 \
                        X1Y51 X1Y50 X1Y49 X1Y48 \
                        X1Y47 X1Y46 X1Y45 X1Y44} \
CONFIG.TX_MASTER_CHANNEL {X1Y49} \
CONFIG.RX_MASTER_CHANNEL {X1Y49} \
CONFIG.TX_LINE_RATE {10.3125} \
CONFIG.TX_REFCLK_FREQUENCY {156.25} \
CONFIG.RX_BUFFER_MODE {0} \
CONFIG.RX_LINE_RATE {10.3125} \
CONFIG.RX_REFCLK_FREQUENCY {156.25} \
CONFIG.RX_JTOL_FC {3.7492501} \
CONFIG.RX_EQ_MODE {LPM} \
CONFIG.INS_LOSS_NYQ {3} \
CONFIG.TX_BUFFER_MODE {0} \
CONFIG.TX_DATA_ENCODING {64B67B} \
CONFIG.TX_DIFF_SWING_EMPH_MODE {CUSTOM} \
CONFIG.TX_USER_DATA_WIDTH {64} \
CONFIG.TX_INT_DATA_WIDTH {32} \
CONFIG.RX_DATA_DECODING {64B67B} \
CONFIG.RX_USER_DATA_WIDTH {64} \
CONFIG.RX_INT_DATA_WIDTH {32} \
CONFIG.RX_CB_MAX_LEVEL {6} \
CONFIG.ENABLE_OPTIONAL_PORTS { \
    txdiffctrl_in txpostcursor_in txprecursor_in} \
CONFIG.LOCATE_TX_USER_CLOCKING {EXAMPLE_DESIGN} \
CONFIG.LOCATE_RX_USER_CLOCKING {EXAMPLE_DESIGN} \
CONFIG.FREERUN_FREQUENCY {100}] \
[get_ips xcvr_link2]

generate_target all [get_ips xcvr_link2]

# ILA for ECI edge signals
create_ip -name ila -vendor xilinx.com -library ip \
              -module_name ila_eci_edge
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {55} \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_EN_STRG_QUAL {0} \
    CONFIG.C_ADV_TRIGGER {false} \
    CONFIG.C_INPUT_PIPE_STAGES {0} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {6} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE6_WIDTH {40} \
    CONFIG.C_PROBE6_TYPE {1} \
    CONFIG.C_PROBE7_WIDTH {64} \
    CONFIG.C_PROBE7_TYPE {1} \
    CONFIG.C_PROBE8_WIDTH {64} \
    CONFIG.C_PROBE8_TYPE {1} \
    CONFIG.C_PROBE9_WIDTH {64} \
    CONFIG.C_PROBE9_TYPE {1} \
    CONFIG.C_PROBE10_WIDTH {64} \
    CONFIG.C_PROBE10_TYPE {1} \
    CONFIG.C_PROBE11_WIDTH {64} \
    CONFIG.C_PROBE11_TYPE {1} \
    CONFIG.C_PROBE12_WIDTH {64} \
    CONFIG.C_PROBE12_TYPE {1} \
    CONFIG.C_PROBE13_WIDTH {64} \
    CONFIG.C_PROBE13_TYPE {1} \
    CONFIG.C_PROBE14_WIDTH {24} \
    CONFIG.C_PROBE14_TYPE {1} \
    CONFIG.C_PROBE15_WIDTH {1} \
    CONFIG.C_PROBE16_WIDTH {1} \
    CONFIG.C_PROBE17_WIDTH {1} \
    CONFIG.C_PROBE18_WIDTH {1} \
    CONFIG.C_PROBE19_WIDTH {40} \
    CONFIG.C_PROBE19_TYPE {1} \
    CONFIG.C_PROBE20_WIDTH {64} \
    CONFIG.C_PROBE20_TYPE {1} \
    CONFIG.C_PROBE21_WIDTH {64} \
    CONFIG.C_PROBE21_TYPE {1} \
    CONFIG.C_PROBE22_WIDTH {64} \
    CONFIG.C_PROBE22_TYPE {1} \
    CONFIG.C_PROBE23_WIDTH {64} \
    CONFIG.C_PROBE23_TYPE {1} \
    CONFIG.C_PROBE24_WIDTH {64} \
    CONFIG.C_PROBE24_TYPE {1} \
    CONFIG.C_PROBE25_WIDTH {64} \
    CONFIG.C_PROBE25_TYPE {1} \
    CONFIG.C_PROBE26_WIDTH {64} \
    CONFIG.C_PROBE26_TYPE {1} \
    CONFIG.C_PROBE27_WIDTH {1} \
    CONFIG.C_PROBE28_WIDTH {6} \
    CONFIG.C_PROBE29_WIDTH {1} \
    CONFIG.C_PROBE30_WIDTH {1} \
    CONFIG.C_PROBE31_WIDTH {1} \
    CONFIG.C_PROBE32_WIDTH {1} \
    CONFIG.C_PROBE33_WIDTH {40} \
    CONFIG.C_PROBE33_TYPE {1} \
    CONFIG.C_PROBE34_WIDTH {64} \
    CONFIG.C_PROBE34_TYPE {1} \
    CONFIG.C_PROBE35_WIDTH {64} \
    CONFIG.C_PROBE35_TYPE {1} \
    CONFIG.C_PROBE36_WIDTH {64} \
    CONFIG.C_PROBE36_TYPE {1} \
    CONFIG.C_PROBE37_WIDTH {64} \
    CONFIG.C_PROBE37_TYPE {1} \
    CONFIG.C_PROBE38_WIDTH {64} \
    CONFIG.C_PROBE38_TYPE {1} \
    CONFIG.C_PROBE39_WIDTH {64} \
    CONFIG.C_PROBE39_TYPE {1} \
    CONFIG.C_PROBE40_WIDTH {64} \
    CONFIG.C_PROBE40_TYPE {1} \
    CONFIG.C_PROBE41_WIDTH {24} \
    CONFIG.C_PROBE41_TYPE {1} \
    CONFIG.C_PROBE42_WIDTH {1} \
    CONFIG.C_PROBE43_WIDTH {1} \
    CONFIG.C_PROBE44_WIDTH {1} \
    CONFIG.C_PROBE45_WIDTH {1} \
    CONFIG.C_PROBE46_WIDTH {40} \
    CONFIG.C_PROBE46_TYPE {1} \
    CONFIG.C_PROBE47_WIDTH {64} \
    CONFIG.C_PROBE47_TYPE {1} \
    CONFIG.C_PROBE48_WIDTH {64} \
    CONFIG.C_PROBE48_TYPE {1} \
    CONFIG.C_PROBE49_WIDTH {64} \
    CONFIG.C_PROBE49_TYPE {1} \
    CONFIG.C_PROBE50_WIDTH {64} \
    CONFIG.C_PROBE50_TYPE {1} \
    CONFIG.C_PROBE51_WIDTH {64} \
    CONFIG.C_PROBE51_TYPE {1} \
    CONFIG.C_PROBE52_WIDTH {64} \
    CONFIG.C_PROBE52_TYPE {1} \
    CONFIG.C_PROBE53_WIDTH {64} \
    CONFIG.C_PROBE53_TYPE {1} \
    CONFIG.C_PROBE54_WIDTH {30} \
    CONFIG.C_PROBE54_TYPE {1} \
    CONFIG.ALL_PROBE_SAME_MU {false} \
    ] [get_ips ila_eci_edge]
generate_target all [get_ips ila_eci_edge]

create_ip -name clk_wiz -vendor xilinx.com -library ip \
              -module_name clk_wiz_0
    set_property -dict [list \
        CONFIG.USE_PHASE_ALIGNMENT {true} \
        CONFIG.PRIM_SOURCE {Differential_clock_capable_pin} \
        CONFIG.PRIM_IN_FREQ {300.000} \
        CONFIG.CLKOUT2_USED {true} \
        CONFIG.CLKOUT3_USED {true} \
        CONFIG.CLKOUT4_USED {true} \
        CONFIG.CLKOUT5_USED {true} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.000} \
        CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {300.000} \
        CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {250.000} \
        CONFIG.CLKOUT5_REQUESTED_OUT_FREQ {300.000} \
        CONFIG.USE_LOCKED {false} \
        CONFIG.USE_RESET {false} \
        CONFIG.SECONDARY_SOURCE {Single_ended_clock_capable_pin} \
        CONFIG.CLKIN1_JITTER_PS {33.330000000000005} \
        CONFIG.CLKOUT1_DRIVES {Buffer} \
        CONFIG.CLKOUT2_DRIVES {Buffer} \
        CONFIG.CLKOUT3_DRIVES {Buffer} \
        CONFIG.CLKOUT4_DRIVES {Buffer} \
        CONFIG.CLKOUT5_DRIVES {Buffer} \
        CONFIG.CLKOUT6_DRIVES {Buffer} \
        CONFIG.CLKOUT7_DRIVES {Buffer} \
        CONFIG.MMCM_CLKFBOUT_MULT_F {5.000} \
        CONFIG.MMCM_CLKIN1_PERIOD {3.333} \
        CONFIG.MMCM_CLKIN2_PERIOD {10.0} \
        CONFIG.MMCM_CLKOUT0_DIVIDE_F {30.000} \
        CONFIG.MMCM_CLKOUT1_DIVIDE {5} \
        CONFIG.MMCM_CLKOUT2_DIVIDE {6} \
        CONFIG.MMCM_CLKOUT3_DIVIDE {15} \
        CONFIG.MMCM_CLKOUT4_DIVIDE {5} \
        CONFIG.NUM_OUT_CLKS {5}\
        CONFIG.CLKOUT1_JITTER {108.931} \
        CONFIG.CLKOUT1_PHASE_ERROR {71.599} \
        CONFIG.CLKOUT2_JITTER {76.789} \
        CONFIG.CLKOUT2_PHASE_ERROR {71.599} \
        CONFIG.CLKOUT3_JITTER {79.566} \
        CONFIG.CLKOUT3_PHASE_ERROR {71.599} \
        CONFIG.CLKOUT4_JITTER {95.138} \
        CONFIG.CLKOUT4_PHASE_ERROR {71.599} \
        CONFIG.CLKOUT5_JITTER {76.789} \
        CONFIG.CLKOUT5_PHASE_ERROR {71.599} \
    ] [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]

create_ip -name axi_register_slice -vendor xilinx.com -library ip -version 2.1 -module_name axi_register_slice_eci_1024
set_property -dict [list CONFIG.ADDR_WIDTH {40} CONFIG.DATA_WIDTH {1024} CONFIG.REG_AW {1} CONFIG.REG_AR {1} CONFIG.REG_B {1} CONFIG.ID_WIDTH {5} CONFIG.MAX_BURST_LENGTH {14} CONFIG.NUM_READ_OUTSTANDING {32} CONFIG.NUM_WRITE_OUTSTANDING {32}] [get_ips axi_register_slice_eci_1024]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_eci_1024
set_property -dict [list CONFIG.TDATA_NUM_BYTES {128} CONFIG.REG_CONFIG {8} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1}] [get_ips axis_register_slice_eci_1024]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_vc_1088
set_property -dict [list CONFIG.TDATA_NUM_BYTES {136} CONFIG.FIFO_DEPTH {32} CONFIG.Component_Name {axis_data_fifo_vc_1088}] [get_ips axis_data_fifo_vc_1088]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_vc_64
set_property -dict [list CONFIG.TDATA_NUM_BYTES {8} CONFIG.FIFO_DEPTH {32} CONFIG.Component_Name {axis_data_fifo_vc_64}] [get_ips axis_data_fifo_vc_64]

# Reorder-link layer
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_w_buff
set_property -dict [list CONFIG.TDATA_NUM_BYTES {128} CONFIG.FIFO_DEPTH {32} CONFIG.HAS_TSTRB {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_data_fifo_w_buff]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_splitter_9
set_property -dict [list CONFIG.TDATA_NUM_BYTES {0} CONFIG.TUSER_WIDTH {9} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_splitter_9]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_splitter_48
set_property -dict [list CONFIG.TDATA_NUM_BYTES {6} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_splitter_48]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_r
set_property -dict [list CONFIG.TDATA_NUM_BYTES {128} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_r]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_w
set_property -dict [list CONFIG.TDATA_NUM_BYTES {128} CONFIG.REG_CONFIG {8} CONFIG.HAS_TSTRB {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_register_slice_w]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_b
set_property -dict [list CONFIG.TDATA_NUM_BYTES {0} CONFIG.TUSER_WIDTH {4} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_b]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_wr_req
set_property -dict [list CONFIG.TDATA_NUM_BYTES {136} CONFIG.TUSER_WIDTH {5} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_wr_req]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_vc
set_property -dict [list CONFIG.TDATA_NUM_BYTES {136} CONFIG.TUSER_WIDTH {5} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_vc]

create_ip -name axis_dwidth_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_dwidth_net_user
set_property -dict [list CONFIG.S_TDATA_NUM_BYTES {64} CONFIG.M_TDATA_NUM_BYTES {128} CONFIG.HAS_TLAST {1} CONFIG.HAS_TKEEP {1} CONFIG.HAS_MI_TKEEP {1} ] [get_ips axis_dwidth_net_user]

create_ip -name axis_dwidth_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_dwidth_user_net
set_property -dict [list CONFIG.S_TDATA_NUM_BYTES {128} CONFIG.M_TDATA_NUM_BYTES {64} CONFIG.HAS_TLAST {1} CONFIG.HAS_TKEEP {1} ] [get_ips axis_dwidth_user_net]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_wr_req_w
set_property -dict [list CONFIG.TDATA_NUM_BYTES {128} CONFIG.FIFO_DEPTH {256} CONFIG.HAS_TSTRB {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_data_fifo_wr_req_w]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_wr_req_aw
set_property -dict [list CONFIG.TDATA_NUM_BYTES {6} CONFIG.FIFO_DEPTH {256} ] [get_ips axis_data_fifo_wr_req_aw]