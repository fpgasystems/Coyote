set numlanes 12

upvar #0 cfg cnfg

# Add source files, as references to the source tree - don't copy them into
# the project.
set files [list \
    [file normalize "$enzian_dir/src/ccpi/ccpi_blk_crc.vhd"] \
    [file normalize "$enzian_dir/src/ccpi/ccpi_rx_blk_sync_gbx.vhd"] \
    [file normalize "$enzian_dir/src/ccpi/ccpi_rx_blk_sync.vhd"] \
    [file normalize "$enzian_dir/src/ccpi/ccpi_tx_blk_sync_gbx.vhd"] \
    [file normalize "$enzian_dir/src/ccpi/ccpi_tx_blk_sync.vhd"] \
    [file normalize "$enzian_dir/src/eci/eci_defs.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_defs.vhd"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/block_types.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_link/eci_link.sv"] \
    [file normalize "$enzian_dir/src/eci/com/eci_io_bridge.vhd"] \
    [file normalize "$enzian_dir/src/eci/com/vc_word_extractor.vhd"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/axi_fifo.v"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/mem_re.v"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/mem.v"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/vc_fifo.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/vc_fifo_xpm.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/lin_packer_10ip.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/vc_cbuf.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/vc_stream_arb.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/serializer_1op.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/link_tlk.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/link_state_machine.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/tlk_arb.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/tlk_fifos.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/link_rlk.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/block_decoder.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/vcs_decoder.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/rlk_fifos.sv"] \
    [file normalize "$enzian_dir/src/eci/vio_send_ecicmd.sv"] \
    [file normalize "$enzian_dir/src/crc/crc32c.vhd"] \
    [file normalize "$enzian_dir/src/crc/crc_64_32_1edc6f41.vhd"] \
    [file normalize "$enzian_dir/src/crc/crc_64_24_328b63.vhd"] \
    [file normalize "$enzian_dir/src/interlaken/il_rx_descrambler.vhd"] \
    [file normalize "$enzian_dir/src/interlaken/il_rx_frame_lock.vhd"] \
    [file normalize "$enzian_dir/src/interlaken/il_rx_framing.vhd"] \
    [file normalize "$enzian_dir/src/interlaken/il_rx_lane_diag.vhd"] \
    [file normalize "$enzian_dir/src/interlaken/il_rx_lane_gearbox.vhd"] \
    [file normalize "$enzian_dir/src/interlaken/il_rx_lane_sync.vhd"] \
    [file normalize "$enzian_dir/src/interlaken/il_rx_link_gearbox.vhd"] \
    [file normalize "$enzian_dir/src/interlaken/il_rx_word_lock.vhd"] \
    [file normalize "$enzian_dir/src/interlaken/il_tx_framing.vhd"] \
    [file normalize "$enzian_dir/src/interlaken/il_tx_lane_diag.vhd"] \
    [file normalize "$enzian_dir/src/interlaken/il_tx_lane_gearbox.vhd"] \
    [file normalize "$enzian_dir/src/interlaken/il_tx_link_gearbox.vhd"] \
    [file normalize "$enzian_dir/src/interlaken/il_tx_metaframe.vhd"] \
    [file normalize "$enzian_dir/src/interlaken/il_tx_scrambler.vhd"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/vc_co_arb.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/vc_cd_arb.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/gen_3_vc_arbiter.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/gen_2_vc_arbiter.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/axis_pipeline_stage.sv"] \
    [file normalize "$enzian_dir/src/eci/eci_link/block_layer/tlk_arb_priority_cntrllr.sv"] \
    [file normalize "$enzian_dir/src/eci_read_write/common/eci_cmd_defs.sv"] \
    [file normalize "$enzian_dir/src/eci_read_write/common/simple_deserializer/rtl/simple_deserializer.sv"] \
    [file normalize "$enzian_dir/src/eci_read_write/common/vc_eci_packetizer/rtl/eci_get_num_words_in_pkt.sv"] \
    [file normalize "$enzian_dir/src/eci_read_write/common/vc_eci_packetizer/rtl/vc_eci_packetizer.sv"] \
    [file normalize "$enzian_dir/src/eci_read_write/common/loopback_vc_resp_nodata/rtl/loopback_vc_resp_nodata.sv"] \
    [file normalize "$enzian_dir/src/eci_read_write/common/stream_2ip_arb/rtl/stream_2ip_arb.sv"] \
    [file normalize "$enzian_dir/src/eci_read_write/common/axis_eci_pkt_to_vc/rtl/axis_eci_pkt_to_vc.sv"] \
    [file normalize "$enzian_dir/src/eci_read_write/eci_co_cd_top/rtl/c_route_co_vc6_7.sv"] \
    [file normalize "$enzian_dir/src/eci_read_write/eci_co_cd_top/rtl/gen_vc_ecip_router.sv"] \
    [file normalize "$enzian_dir/src/eci_read_write/eci_co_cd_top/rtl/gen_vc_ecih_router.sv"] \
    [file normalize "$enzian_dir/src/eci_read_write/eci_co_cd_top/rtl/vc_eci_pkt_router.sv"] \
    [file normalize "$enzian_dir/src/eci_read_write/eci_co_cd_top/rtl/eci_pkt_vc_router.sv"] \
]
add_files -norecurse -fileset [get_filesets sources_1] $files

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
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {50.000} \
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

set cmd "set_property -dict \[list CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {$cnfg(uclk_f)}] \[get_ips clk_wiz_0]"
eval $cmd
set cmd "set_property -dict \[list CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {$cnfg(nclk_f)}] \[get_ips clk_wiz_0]"
eval $cmd
set cmd "set_property -dict \[list CONFIG.CLKOUT4_REQUESTED_OUT_FREQ 100] \[get_ips clk_wiz_0]"
eval $cmd

# Instantiate link 1 transceivers (0-11)
create_ip -name gtwizard_ultrascale -vendor xilinx.com -library ip \
          -module_name xcvr_link1
set_property -dict [list \
    CONFIG.preset {GTY-10GBASE-KR}] [get_ips xcvr_link1]


## allocate transceivers
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
CONFIG.FREERUN_FREQUENCY {50}] \
[get_ips xcvr_link1]

generate_target all [get_ips xcvr_link1]

# VIO for the XCVR link
create_ip -name vio -vendor xilinx.com -library ip \
        -module_name vio_xcvr
set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN {8} \
    CONFIG.C_NUM_PROBE_OUT {2} \
    CONFIG.C_PROBE_IN0_WIDTH {1} \
    CONFIG.C_PROBE_IN1_WIDTH {3} \
    CONFIG.C_PROBE_IN2_WIDTH {1} \
    CONFIG.C_PROBE_IN3_WIDTH {1} \
    CONFIG.C_PROBE_IN4_WIDTH {1} \
    CONFIG.C_PROBE_IN5_WIDTH {3} \
    CONFIG.C_PROBE_IN6_WIDTH {1} \
    CONFIG.C_PROBE_IN7_WIDTH {1} \
    CONFIG.C_PROBE_OUT0_WIDTH {1} \
    CONFIG.C_PROBE_OUT1_WIDTH {1} \
] [get_ips vio_xcvr]
generate_target all [get_ips vio_xcvr]

# VIO for the ECI packet injector
create_ip -name vio -vendor xilinx.com -library ip \
        -module_name vio_0
set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN {0} \
    CONFIG.C_NUM_PROBE_OUT {2} \
    CONFIG.C_PROBE_OUT0_WIDTH {1} \
    CONFIG.C_PROBE_OUT0_INIT_VAL {0x0} \
    CONFIG.C_PROBE_OUT1_WIDTH {64} \
    CONFIG.C_PROBE_OUT1_INIT_VAL {0x00018fc02200000e} \
] [get_ips vio_0]
generate_target all [get_ips vio_0]

# ILA for ECI edge signals
create_ip -name ila -vendor xilinx.com -library ip \
              -module_name ila_3
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {10} \
    CONFIG.C_DATA_DEPTH {4096} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.C_ADV_TRIGGER {true} \
    CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.C_PROBE0_WIDTH {512} \
    CONFIG.C_PROBE1_WIDTH {1} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {512} \
    CONFIG.C_PROBE6_WIDTH {1} \
    CONFIG.C_PROBE7_WIDTH {1} \
    CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {1} \
    CONFIG.ALL_PROBE_SAME_MU {true} \
    CONFIG.C_PROBE0_MU_CNT {2} \
    ] [get_ips ila_3]
generate_target all [get_ips ila_3]

# Export the hardware definition for the Microblaze.
file mkdir "$build_dir/$project.sdk"
