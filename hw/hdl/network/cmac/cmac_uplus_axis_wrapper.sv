/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
  * All rights reserved.
  *
  * Redistribution and use in source and binary forms, with or without modification,
  * are permitted provided that the following conditions are met:
  *
  * 1. Redistributions of source code must retain the above copyright notice,
  * this list of conditions and the following disclaimer.
  * 2. Redistributions in binary form must reproduce the above copyright notice,
  * this list of conditions and the following disclaimer in the documentation
  * and/or other materials provided with the distribution.
  * 3. Neither the name of the copyright holder nor the names of its contributors
  * may be used to endorse or promote products derived from this software
  * without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  */

`timescale 1ns/1ps

//`define CMAC_DEBUG

import lynxTypes::*;

module cmac_axis_wrapper #(
    parameter integer           QSFP = 0
) (
    input wire                  init_clk,
    input wire                  sys_reset,

    input wire                  gt_ref_clk_p,
    input wire                  gt_ref_clk_n,
    input wire [3:0]            gt_rxp_in,
    input wire [3:0]            gt_rxn_in,
    output wire [3:0]           gt_txn_out,
    output wire [3:0]           gt_txp_out,

    AXI4S.m                     m_rx_axis,
    AXI4S.s                     s_tx_axis,

	output logic                usr_clk,
	output logic                tx_rst
	//output logic                rx_rst
);

// gt_rxrecclkout
logic [3:0] gt_rxrecclkout;

// Loopback
logic[11:0] gt_loopback_in;
assign gt_loopback_in = '0;

// Aligned
wire stat_rx_aligned;

// Clocks
logic gt_txusrclk2;
logic gt_rxusrclk2;
assign usr_clk = gt_txusrclk2;

// Resets
//reg usr_rx_reset_r;
//reg usr_rx_reset_rr;
reg core_tx_reset_r;
reg core_tx_reset_rr;

wire usr_rx_reset_w;
wire core_tx_reset_w;

// Aligned status
assign rx_aligned = stat_rx_aligned;

// Slicing
/*
always @( posedge gt_rxusrclk2 ) begin
    usr_rx_reset_r  <= usr_rx_reset_w;
    usr_rx_reset_rr <= usr_rx_reset_r;
end
*/
always @( posedge gt_txusrclk2 ) begin
    core_tx_reset_r <= core_tx_reset_w;
    core_tx_reset_rr <= core_tx_reset_r;
end

//assign rx_rst = usr_rx_reset_rr;
assign tx_rst = core_tx_reset_rr;

//RX FSM states ----------------------------------------------------------------------
localparam STATE_RX_IDLE             = 0;
localparam STATE_GT_LOCKED           = 1;
localparam STATE_WAIT_RX_ALIGNED     = 2;
localparam STATE_PKT_TRANSFER_INIT   = 3;
localparam STATE_WAIT_FOR_RESTART    = 6;

reg ctl_rx_enable_r, ctl_rx_force_resync_r; 

////State Registers for RX
reg [3:0]  rx_prestate;

//rx reset handling
reg rx_reset_done;
reg stat_rx_aligned_1d;

always @(posedge gt_txusrclk2) begin
    if (usr_rx_reset_w) begin
        rx_prestate            <= STATE_RX_IDLE;
        ctl_rx_enable_r        <= 1'b0;
        ctl_rx_force_resync_r  <= 1'b0;
        stat_rx_aligned_1d <= 1'b0;
        rx_reset_done <= 1'b0;
    end
    else begin
        rx_reset_done <= 1'b1;
        stat_rx_aligned_1d <= stat_rx_aligned;
        case (rx_prestate)
            STATE_RX_IDLE: begin
                ctl_rx_enable_r        <= 1'b0;
                ctl_rx_force_resync_r  <= 1'b0;
                if  (rx_reset_done == 1'b1) begin
                    rx_prestate <= STATE_GT_LOCKED;
                end
            end
            STATE_GT_LOCKED: begin
                 ctl_rx_enable_r        <= 1'b1;
                 ctl_rx_force_resync_r  <= 1'b0;
                 rx_prestate <= STATE_WAIT_RX_ALIGNED;
            end
            STATE_WAIT_RX_ALIGNED: begin
                if  (stat_rx_aligned_1d == 1'b1) begin
                    rx_prestate <= STATE_PKT_TRANSFER_INIT;
                end
            end
            STATE_PKT_TRANSFER_INIT: begin
                if (stat_rx_aligned_1d == 1'b0) begin
                    rx_prestate <= STATE_RX_IDLE;
                end
            end
        endcase
    end
end
wire ctl_rx_enable;
wire ctl_rx_force_resync;
assign ctl_rx_enable            = ctl_rx_enable_r;
assign ctl_rx_force_resync      = ctl_rx_force_resync_r;

// TX FSM States
localparam STATE_TX_IDLE             = 0;
//localparam STATE_GT_LOCKED           = 1;
//localparam STATE_WAIT_RX_ALIGNED     = 2;
//localparam STATE_PKT_TRANSFER_INIT   = 3;
//localparam STATE_LBUS_TX_ENABLE      = 4;
//localparam STATE_LBUS_TX_HALT        = 5;
//localparam STATE_LBUS_TX_DONE        = 6;
//localparam STATE_WAIT_FOR_RESTART    = 7;
reg  [3:0]     tx_prestate;
reg tx_reset_done;
reg            ctl_tx_enable_r, ctl_tx_send_idle_r, ctl_tx_send_rfi_r, ctl_tx_test_pattern_r;
reg            ctl_tx_send_lfi_r;
always @(posedge gt_txusrclk2) begin
    if (core_tx_reset_w) begin
        tx_prestate                       <= STATE_TX_IDLE;
        ctl_tx_enable_r                   <= 1'b0;
        ctl_tx_send_idle_r                <= 1'b0;
        ctl_tx_send_lfi_r                 <= 1'b0;
        ctl_tx_send_rfi_r                 <= 1'b0;
        ctl_tx_test_pattern_r             <= 1'b0;
        tx_reset_done <= 1'b0;
    end
    else begin
        tx_reset_done <= 1'b1;
        //stat_rx_aligned_1d <= cmac_stat.stat_rx_aligned;
        case (tx_prestate)
            STATE_TX_IDLE: begin
                ctl_tx_enable_r        <= 1'b0;
                ctl_tx_send_idle_r     <= 1'b0;
                ctl_tx_send_lfi_r      <= 1'b0;
                ctl_tx_send_rfi_r      <= 1'b0;
                ctl_tx_test_pattern_r  <= 1'b0;
                if  (tx_reset_done == 1'b1) begin
                    tx_prestate <= STATE_GT_LOCKED;
                end
                /*else begin
                    rx_prestate <= STATE_RX_IDLE;
                end*/
            end
            STATE_GT_LOCKED: begin
                ctl_tx_enable_r        <= 1'b0;
                ctl_tx_send_idle_r     <= 1'b0;
                ctl_tx_send_lfi_r      <= 1'b1;
                ctl_tx_send_rfi_r      <= 1'b1;
                tx_prestate <= STATE_WAIT_RX_ALIGNED;
            end
            STATE_WAIT_RX_ALIGNED: begin //TODO rename?
                if  (stat_rx_aligned_1d == 1'b1) begin
                    tx_prestate <= STATE_PKT_TRANSFER_INIT;
                end
            end
            STATE_PKT_TRANSFER_INIT: begin
                ctl_tx_send_idle_r     <= 1'b0;
                ctl_tx_send_lfi_r      <= 1'b0;
                ctl_tx_send_rfi_r      <= 1'b0;
                ctl_tx_enable_r        <= 1'b1;
                if  (stat_rx_aligned_1d == 1'b0) begin
                    tx_prestate <= STATE_TX_IDLE;
                end
            end
        endcase
    end
end
wire ctl_tx_enable;
wire ctl_tx_send_idle;
wire ctl_tx_send_lfi;
wire ctl_tx_send_rfi;
wire ctl_tx_test_pattern;
assign ctl_tx_enable                = ctl_tx_enable_r;
assign ctl_tx_send_idle             = ctl_tx_send_idle_r;
assign ctl_tx_send_lfi              = ctl_tx_send_lfi_r;
assign ctl_tx_send_rfi              = ctl_tx_send_rfi_r;
assign ctl_tx_test_pattern          = ctl_tx_test_pattern_r;

wire            stat_rx_aligned_err;
wire [2:0]      stat_rx_bad_code;
wire [2:0]      stat_rx_bad_fcs;
wire            stat_rx_bad_preamble;
wire            stat_rx_bad_sfd;

wire            stat_rx_got_signal_os;
wire            stat_rx_hi_ber;
wire            stat_rx_inrangeerr;
wire            stat_rx_internal_local_fault;
wire            stat_rx_jabber;
wire            stat_rx_local_fault;
wire [19:0]     stat_rx_mf_err;
wire [19:0]     stat_rx_mf_len_err;
wire [19:0]     stat_rx_mf_repeat_err;
wire            stat_rx_misaligned;

wire            stat_rx_received_local_fault;
wire            stat_rx_remote_fault;
wire            stat_rx_status;
wire [2:0]      stat_rx_stomped_fcs;
wire [19:0]     stat_rx_synced;
wire [19:0]     stat_rx_synced_err;
  
//For debug
logic[6:0]  stat_rx_total_bytes;
logic[13:0] stat_rx_good_bytes;
logic       stat_rx_good_packets;
logic[2:0]  stat_rx_total_packets;

logic[5:0]  stat_tx_total_bytes;
logic[13:0] stat_tx_good_bytes;
logic       stat_tx_good_packets;
logic       stat_tx_total_packets;

logic tx_ovf;//TODO use for debug
logic tx_unf;//TODO use for debug
        
logic rx_axis_tuser;

vio_link inst_vio_link (
    .clk(gt_txusrclk2),
    .probe_in0(stat_rx_aligned),
    .probe_in1(rx_prestate), // 4
    .probe_in2(stat_rx_bad_fcs) // 3
);

//wire tx_user_rst_i;
//assign tx_user_rst_i = sys_reset; //TODO why not 1'b0??

`ifdef POLARITY_INV
wire [3:0] gt_rxpolarity = 4'b0011;
wire [3:0] gt_txpolarity = 4'b0011;
`endif

if(QSFP == 0) begin
cmac_usplus_axis_0 inst_cmac_0 (
        .gt_rxp_in                     (gt_rxp_in),
        .gt_rxn_in                     (gt_rxn_in),
        .gt_txp_out                    (gt_txp_out),
        .gt_txn_out                    (gt_txn_out),

        /*.gt0_rxp_in                    (gt_rxp_in[0]),
        .gt1_rxp_in                    (gt_rxp_in[1]),
        .gt2_rxp_in                    (gt_rxp_in[2]),
        .gt3_rxp_in                    (gt_rxp_in[3]),
        
        .gt0_rxn_in                    (gt_rxn_in[0]),
        .gt1_rxn_in                    (gt_rxn_in[1]),
        .gt2_rxn_in                    (gt_rxn_in[2]),
        .gt3_rxn_in                    (gt_rxn_in[3]),
        
        .gt0_txp_out                   (gt_txp_out[0]),
        .gt1_txp_out                   (gt_txp_out[1]),
        .gt2_txp_out                   (gt_txp_out[2]),
        .gt3_txp_out                   (gt_txp_out[3]),
        
        .gt0_txn_out                   (gt_txn_out[0]),
        .gt1_txn_out                   (gt_txn_out[1]),
        .gt2_txn_out                   (gt_txn_out[2]),
        .gt3_txn_out                   (gt_txn_out[3]),*/
        
        .gt_txusrclk2                  (gt_txusrclk2),
        .gt_loopback_in                (gt_loopback_in),
        .gt_rxrecclkout                (gt_rxrecclkout),
        .gt_powergoodout               (),
        
        .sys_reset                     (sys_reset),
        .gtwiz_reset_tx_datapath       (1'b0),
        .gtwiz_reset_rx_datapath       (1'b0),
        
        .gt_ref_clk_p                  (gt_ref_clk_p),
        .gt_ref_clk_n                  (gt_ref_clk_n),
        .init_clk                      (init_clk),
        .gt_ref_clk_out                (),
        
        
        .rx_axis_tvalid                (m_rx_axis.tvalid),
        .rx_axis_tdata                 (m_rx_axis.tdata),
        .rx_axis_tkeep                 (m_rx_axis.tkeep),
        .rx_axis_tlast                 (m_rx_axis.tlast),
        .rx_axis_tuser                 (rx_axis_tuser),
        .rx_otn_bip8_0                 (),
        .rx_otn_bip8_1                 (),
        .rx_otn_bip8_2                 (),
        .rx_otn_bip8_3                 (),
        .rx_otn_bip8_4                 (),
        .rx_otn_data_0                 (),
        .rx_otn_data_1                 (),
        .rx_otn_data_2                 (),
        .rx_otn_data_3                 (),
        .rx_otn_data_4                 (),
        .rx_otn_ena                    (), //
        .rx_otn_lane0                  (), //
        .rx_otn_vlmarker               (), //

        .rx_preambleout                (),
        .usr_rx_reset                  (usr_rx_reset_w),
        
        .gt_rxusrclk2                  (gt_rxusrclk2),
        
        
        .stat_rx_aligned               (stat_rx_aligned), //
        .stat_rx_aligned_err           (stat_rx_aligned_err), //
        .stat_rx_bad_code              (stat_rx_bad_code),
        .stat_rx_bad_fcs               (stat_rx_bad_fcs),
        .stat_rx_bad_preamble          (stat_rx_bad_preamble), //
        .stat_rx_bad_sfd               (stat_rx_bad_sfd), //
        .stat_rx_bip_err_0             (), // 
        .stat_rx_bip_err_1             (), //
        .stat_rx_bip_err_10            (), //
        .stat_rx_bip_err_11            (), //
        .stat_rx_bip_err_12            (), //
        .stat_rx_bip_err_13            (), //
        .stat_rx_bip_err_14            (), //
        .stat_rx_bip_err_15            (), //
        .stat_rx_bip_err_16            (), //
        .stat_rx_bip_err_17            (), //
        .stat_rx_bip_err_18            (), //
        .stat_rx_bip_err_19            (), //
        .stat_rx_bip_err_2             (), //
        .stat_rx_bip_err_3             (), //
        .stat_rx_bip_err_4             (), //
        .stat_rx_bip_err_5             (), //
        .stat_rx_bip_err_6             (), //
        .stat_rx_bip_err_7             (), //
        .stat_rx_bip_err_8             (), //
        .stat_rx_bip_err_9             (), //
        .stat_rx_block_lock            (),
        .stat_rx_broadcast             (), //
        .stat_rx_fragment              (),
        .stat_rx_framing_err_0         (),
        .stat_rx_framing_err_1         (),
        .stat_rx_framing_err_10        (),
        .stat_rx_framing_err_11        (),
        .stat_rx_framing_err_12        (),
        .stat_rx_framing_err_13        (),
        .stat_rx_framing_err_14        (),
        .stat_rx_framing_err_15        (),
        .stat_rx_framing_err_16        (),
        .stat_rx_framing_err_17        (),
        .stat_rx_framing_err_18        (),
        .stat_rx_framing_err_19        (),
        .stat_rx_framing_err_2         (),
        .stat_rx_framing_err_3         (),
        .stat_rx_framing_err_4         (),
        .stat_rx_framing_err_5         (),
        .stat_rx_framing_err_6         (),
        .stat_rx_framing_err_7         (),
        .stat_rx_framing_err_8         (),
        .stat_rx_framing_err_9         (),
        .stat_rx_framing_err_valid_0   (), //
        .stat_rx_framing_err_valid_1   (), //
        .stat_rx_framing_err_valid_10  (), //
        .stat_rx_framing_err_valid_11  (), //
        .stat_rx_framing_err_valid_12  (), //
        .stat_rx_framing_err_valid_13  (), //
        .stat_rx_framing_err_valid_14  (), //
        .stat_rx_framing_err_valid_15  (), //
        .stat_rx_framing_err_valid_16  (), //
        .stat_rx_framing_err_valid_17  (), //
        .stat_rx_framing_err_valid_18  (), //
        .stat_rx_framing_err_valid_19  (), //
        .stat_rx_framing_err_valid_2   (), //
        .stat_rx_framing_err_valid_3   (), //
        .stat_rx_framing_err_valid_4   (), //
        .stat_rx_framing_err_valid_5   (), //
        .stat_rx_framing_err_valid_6   (), //
        .stat_rx_framing_err_valid_7   (), //
        .stat_rx_framing_err_valid_8   (), //
        .stat_rx_framing_err_valid_9   (), //
        .stat_rx_got_signal_os         (stat_rx_got_signal_os), //
        .stat_rx_hi_ber                (stat_rx_hi_ber), //
        .stat_rx_inrangeerr            (stat_rx_inrangeerr), //
        .stat_rx_internal_local_fault  (stat_rx_internal_local_fault), //
        .stat_rx_jabber                (stat_rx_jabber), //
        .stat_rx_local_fault           (stat_rx_local_fault), //
        .stat_rx_mf_err                (stat_rx_mf_err),
        .stat_rx_mf_len_err            (stat_rx_mf_len_err),
        .stat_rx_mf_repeat_err         (stat_rx_mf_repeat_err),
        .stat_rx_misaligned            (stat_rx_misaligned), //
        .stat_rx_multicast             (), //
        .stat_rx_oversize              (), //
        .stat_rx_packet_1024_1518_bytes(), //
        .stat_rx_packet_128_255_bytes  (), //
        .stat_rx_packet_1519_1522_bytes(), //
        .stat_rx_packet_1523_1548_bytes(), //
        .stat_rx_packet_1549_2047_bytes(), //
        .stat_rx_packet_2048_4095_bytes(), //
        .stat_rx_packet_256_511_bytes  (), //
        .stat_rx_packet_4096_8191_bytes(), //
        .stat_rx_packet_512_1023_bytes (), //
        .stat_rx_packet_64_bytes       (), //
        .stat_rx_packet_65_127_bytes   (), //
        .stat_rx_packet_8192_9215_bytes(), //
        .stat_rx_packet_bad_fcs        (), //
        .stat_rx_packet_large          (), //
        .stat_rx_packet_small          (),
        
        .ctl_rx_enable                 (ctl_rx_enable),
        .ctl_rx_force_resync           (ctl_rx_force_resync),
        .ctl_rx_test_pattern           (1'b0),
        .core_rx_reset                 (1'b0), //TODO 1'b0 in example design
        .rx_clk                        (gt_txusrclk2),
        
        .stat_rx_received_local_fault  (stat_rx_received_local_fault), //
        .stat_rx_remote_fault          (stat_rx_remote_fault), //
        .stat_rx_status                (stat_rx_status), //
        .stat_rx_stomped_fcs           (stat_rx_stomped_fcs),
        .stat_rx_synced                (stat_rx_synced),
        .stat_rx_synced_err            (stat_rx_synced_err),
        .stat_rx_test_pattern_mismatch (),
        .stat_rx_toolong               (), //
        .stat_rx_total_bytes           (stat_rx_total_bytes),
        .stat_rx_total_good_bytes      (stat_rx_good_bytes),
        .stat_rx_total_good_packets    (stat_rx_good_packets), //
        .stat_rx_total_packets         (stat_rx_total_packets),
        .stat_rx_truncated             (), //
        .stat_rx_undersize             (),
        .stat_rx_unicast               (), //
        .stat_rx_vlan                  (), //
        .stat_rx_pcsl_demuxed          (),
        .stat_rx_pcsl_number_0         (),
        .stat_rx_pcsl_number_1         (),
        .stat_rx_pcsl_number_10        (),
        .stat_rx_pcsl_number_11        (),
        .stat_rx_pcsl_number_12        (),
        .stat_rx_pcsl_number_13        (),
        .stat_rx_pcsl_number_14        (),
        .stat_rx_pcsl_number_15        (),
        .stat_rx_pcsl_number_16        (),
        .stat_rx_pcsl_number_17        (),
        .stat_rx_pcsl_number_18        (),
        .stat_rx_pcsl_number_19        (),
        .stat_rx_pcsl_number_2         (),
        .stat_rx_pcsl_number_3         (),
        .stat_rx_pcsl_number_4         (),
        .stat_rx_pcsl_number_5         (),
        .stat_rx_pcsl_number_6         (),
        .stat_rx_pcsl_number_7         (),
        .stat_rx_pcsl_number_8         (),
        .stat_rx_pcsl_number_9         (),
        
        
        .stat_tx_bad_fcs               (),
        .stat_tx_broadcast             (),
        .stat_tx_frame_error           (),
        .stat_tx_local_fault           (),
        .stat_tx_multicast             (),
        .stat_tx_packet_1024_1518_bytes(),
        .stat_tx_packet_128_255_bytes  (),
        .stat_tx_packet_1519_1522_bytes(),
        .stat_tx_packet_1523_1548_bytes(),
        .stat_tx_packet_1549_2047_bytes(),
        .stat_tx_packet_2048_4095_bytes(),
        .stat_tx_packet_256_511_bytes  (),
        .stat_tx_packet_4096_8191_bytes(),
        .stat_tx_packet_512_1023_bytes (),
        .stat_tx_packet_64_bytes       (),
        .stat_tx_packet_65_127_bytes   (),
        .stat_tx_packet_8192_9215_bytes(),
        .stat_tx_packet_large          (),
        .stat_tx_packet_small          (),
        .stat_tx_total_bytes           (stat_tx_total_bytes),
        .stat_tx_total_good_bytes      (stat_tx_good_bytes),
        .stat_tx_total_good_packets    (stat_tx_good_packets),
        .stat_tx_total_packets         (stat_tx_total_packets),
        .stat_tx_unicast               (),
        .stat_tx_vlan                  (),
        
        .ctl_tx_enable                 (ctl_tx_enable),
        .ctl_tx_send_idle              (ctl_tx_send_idle),
        .ctl_tx_send_rfi               (ctl_tx_send_rfi),
        .ctl_tx_send_lfi               (ctl_tx_send_lfi),
        .ctl_tx_test_pattern           (ctl_tx_test_pattern),
        .core_tx_reset                 (1'b0),
        
        .tx_axis_tready                (s_tx_axis.tready),
        .tx_axis_tvalid                (s_tx_axis.tvalid),
        .tx_axis_tdata                 (s_tx_axis.tdata),
        .tx_axis_tkeep                 (s_tx_axis.tkeep),
        .tx_axis_tlast                 (s_tx_axis.tlast),
        .tx_axis_tuser                 (0),

        .tx_ovfout                     (tx_ovf),
        .tx_unfout                     (tx_unf),
        .tx_preamblein                 ({55{1'b0}}),

        .usr_tx_reset                  (core_tx_reset_w),
        
        .core_drp_reset                (1'b0),
        .drp_clk                       (init_clk),
        .drp_addr                      (10'b0),
        .drp_di                        (16'b0),
        .drp_en                        (1'b0),
        .drp_do                        (),
        .drp_rdy                       (),
        .drp_we                        (1'b0),


        // EXTRA STUFF
        .gt_eyescanreset(0),
        .gt_eyescantrigger(0),
        .gt_rxcdrhold(0),
`ifdef POLARITY_INV
        .gt_rxpolarity(gt_rxpolarity),
        .gt_txpolarity(gt_txpolarity),
`else
        .gt_rxpolarity(0),
        .gt_txpolarity(0),
`endif
        .gt_rxrate(0),
        .gt_txdiffctrl(0),
        .gt_txinhibit(0),
        .gt_txpippmen(0),
        .gt_txpippmsel(0),
        .gt_txpostcursor(0),
        .gt_txprbsforceerr(0),
        .gt_txprecursor(0),
        .gt_eyescandataerror(),
        .gt_txbufstatus(),
        .gt_rxdfelpmreset(0),
        .gt_rxlpmen(0),
        .gt_rxprbscntreset(0),
        .gt_rxprbserr(),
        .gt_rxprbssel(0),
        .gt_rxresetdone(),
        .gt_txprbssel(0),
        .gt_txresetdone(),
        .gt_rxbufstatus(),

        .gt_drpclk(init_clk),

        .gt0_drpdo(),
        .gt0_drprdy(),
        .gt0_drpen(0),
        .gt0_drpwe(0),
        .gt0_drpaddr(0),
        .gt0_drpdi(0),

        .gt1_drpdo(),
        .gt1_drprdy(),
        .gt1_drpen(0),
        .gt1_drpwe(0),
        .gt1_drpaddr(0),
        .gt1_drpdi(0),

        .gt2_drpdo(),
        .gt2_drprdy(),
        .gt2_drpen(0),
        .gt2_drpwe(0),
        .gt2_drpaddr(0),
        .gt2_drpdi(0),

        .gt3_drpdo(),
        .gt3_drprdy(),
        .gt3_drpen(0),
        .gt3_drpwe(0),
        .gt3_drpaddr(0),
        .gt3_drpdi(0),

        .common0_drpaddr(0),
        .common0_drpdi(0),
        .common0_drpwe(0),
        .common0_drpen(0),
        .common0_drprdy(),
        .common0_drpdo()
);
end
else begin
cmac_usplus_axis_1 inst_cmac_1 (
        .gt_rxp_in                     (gt_rxp_in),
        .gt_rxn_in                     (gt_rxn_in),
        .gt_txp_out                    (gt_txp_out),
        .gt_txn_out                    (gt_txn_out),

        /*.gt0_rxp_in                    (gt_rxp_in[0]),
        .gt1_rxp_in                    (gt_rxp_in[1]),
        .gt2_rxp_in                    (gt_rxp_in[2]),
        .gt3_rxp_in                    (gt_rxp_in[3]),
        
        .gt0_rxn_in                    (gt_rxn_in[0]),
        .gt1_rxn_in                    (gt_rxn_in[1]),
        .gt2_rxn_in                    (gt_rxn_in[2]),
        .gt3_rxn_in                    (gt_rxn_in[3]),
        
        .gt0_txp_out                   (gt_txp_out[0]),
        .gt1_txp_out                   (gt_txp_out[1]),
        .gt2_txp_out                   (gt_txp_out[2]),
        .gt3_txp_out                   (gt_txp_out[3]),
        
        .gt0_txn_out                   (gt_txn_out[0]),
        .gt1_txn_out                   (gt_txn_out[1]),
        .gt2_txn_out                   (gt_txn_out[2]),
        .gt3_txn_out                   (gt_txn_out[3]),*/
        
        .gt_txusrclk2                  (gt_txusrclk2),
        .gt_loopback_in                (gt_loopback_in),
        .gt_rxrecclkout                (gt_rxrecclkout),
        .gt_powergoodout               (),
        
        .sys_reset                     (sys_reset),
        .gtwiz_reset_tx_datapath       (1'b0),
        .gtwiz_reset_rx_datapath       (1'b0),
        
        .gt_ref_clk_p                  (gt_ref_clk_p),
        .gt_ref_clk_n                  (gt_ref_clk_n),
        .init_clk                      (init_clk),
        .gt_ref_clk_out                (),
        
        
        .rx_axis_tvalid                (m_rx_axis.tvalid),
        .rx_axis_tdata                 (m_rx_axis.tdata),
        .rx_axis_tkeep                 (m_rx_axis.tkeep),
        .rx_axis_tlast                 (m_rx_axis.tlast),
        .rx_axis_tuser                 (rx_axis_tuser),
        .rx_otn_bip8_0                 (),
        .rx_otn_bip8_1                 (),
        .rx_otn_bip8_2                 (),
        .rx_otn_bip8_3                 (),
        .rx_otn_bip8_4                 (),
        .rx_otn_data_0                 (),
        .rx_otn_data_1                 (),
        .rx_otn_data_2                 (),
        .rx_otn_data_3                 (),
        .rx_otn_data_4                 (),
        .rx_otn_ena                    (), //
        .rx_otn_lane0                  (), //
        .rx_otn_vlmarker               (), //

        .rx_preambleout                (),
        .usr_rx_reset                  (usr_rx_reset_w),
        
        .gt_rxusrclk2                  (gt_rxusrclk2),
        
        
        .stat_rx_aligned               (stat_rx_aligned), //
        .stat_rx_aligned_err           (stat_rx_aligned_err), //
        .stat_rx_bad_code              (stat_rx_bad_code),
        .stat_rx_bad_fcs               (stat_rx_bad_fcs),
        .stat_rx_bad_preamble          (stat_rx_bad_preamble), //
        .stat_rx_bad_sfd               (stat_rx_bad_sfd), //
        .stat_rx_bip_err_0             (), // 
        .stat_rx_bip_err_1             (), //
        .stat_rx_bip_err_10            (), //
        .stat_rx_bip_err_11            (), //
        .stat_rx_bip_err_12            (), //
        .stat_rx_bip_err_13            (), //
        .stat_rx_bip_err_14            (), //
        .stat_rx_bip_err_15            (), //
        .stat_rx_bip_err_16            (), //
        .stat_rx_bip_err_17            (), //
        .stat_rx_bip_err_18            (), //
        .stat_rx_bip_err_19            (), //
        .stat_rx_bip_err_2             (), //
        .stat_rx_bip_err_3             (), //
        .stat_rx_bip_err_4             (), //
        .stat_rx_bip_err_5             (), //
        .stat_rx_bip_err_6             (), //
        .stat_rx_bip_err_7             (), //
        .stat_rx_bip_err_8             (), //
        .stat_rx_bip_err_9             (), //
        .stat_rx_block_lock            (),
        .stat_rx_broadcast             (), //
        .stat_rx_fragment              (),
        .stat_rx_framing_err_0         (),
        .stat_rx_framing_err_1         (),
        .stat_rx_framing_err_10        (),
        .stat_rx_framing_err_11        (),
        .stat_rx_framing_err_12        (),
        .stat_rx_framing_err_13        (),
        .stat_rx_framing_err_14        (),
        .stat_rx_framing_err_15        (),
        .stat_rx_framing_err_16        (),
        .stat_rx_framing_err_17        (),
        .stat_rx_framing_err_18        (),
        .stat_rx_framing_err_19        (),
        .stat_rx_framing_err_2         (),
        .stat_rx_framing_err_3         (),
        .stat_rx_framing_err_4         (),
        .stat_rx_framing_err_5         (),
        .stat_rx_framing_err_6         (),
        .stat_rx_framing_err_7         (),
        .stat_rx_framing_err_8         (),
        .stat_rx_framing_err_9         (),
        .stat_rx_framing_err_valid_0   (), //
        .stat_rx_framing_err_valid_1   (), //
        .stat_rx_framing_err_valid_10  (), //
        .stat_rx_framing_err_valid_11  (), //
        .stat_rx_framing_err_valid_12  (), //
        .stat_rx_framing_err_valid_13  (), //
        .stat_rx_framing_err_valid_14  (), //
        .stat_rx_framing_err_valid_15  (), //
        .stat_rx_framing_err_valid_16  (), //
        .stat_rx_framing_err_valid_17  (), //
        .stat_rx_framing_err_valid_18  (), //
        .stat_rx_framing_err_valid_19  (), //
        .stat_rx_framing_err_valid_2   (), //
        .stat_rx_framing_err_valid_3   (), //
        .stat_rx_framing_err_valid_4   (), //
        .stat_rx_framing_err_valid_5   (), //
        .stat_rx_framing_err_valid_6   (), //
        .stat_rx_framing_err_valid_7   (), //
        .stat_rx_framing_err_valid_8   (), //
        .stat_rx_framing_err_valid_9   (), //
        .stat_rx_got_signal_os         (stat_rx_got_signal_os), //
        .stat_rx_hi_ber                (stat_rx_hi_ber), //
        .stat_rx_inrangeerr            (stat_rx_inrangeerr), //
        .stat_rx_internal_local_fault  (stat_rx_internal_local_fault), //
        .stat_rx_jabber                (stat_rx_jabber), //
        .stat_rx_local_fault           (stat_rx_local_fault), //
        .stat_rx_mf_err                (stat_rx_mf_err),
        .stat_rx_mf_len_err            (stat_rx_mf_len_err),
        .stat_rx_mf_repeat_err         (stat_rx_mf_repeat_err),
        .stat_rx_misaligned            (stat_rx_misaligned), //
        .stat_rx_multicast             (), //
        .stat_rx_oversize              (), //
        .stat_rx_packet_1024_1518_bytes(), //
        .stat_rx_packet_128_255_bytes  (), //
        .stat_rx_packet_1519_1522_bytes(), //
        .stat_rx_packet_1523_1548_bytes(), //
        .stat_rx_packet_1549_2047_bytes(), //
        .stat_rx_packet_2048_4095_bytes(), //
        .stat_rx_packet_256_511_bytes  (), //
        .stat_rx_packet_4096_8191_bytes(), //
        .stat_rx_packet_512_1023_bytes (), //
        .stat_rx_packet_64_bytes       (), //
        .stat_rx_packet_65_127_bytes   (), //
        .stat_rx_packet_8192_9215_bytes(), //
        .stat_rx_packet_bad_fcs        (), //
        .stat_rx_packet_large          (), //
        .stat_rx_packet_small          (),
        
        .ctl_rx_enable                 (ctl_rx_enable),
        .ctl_rx_force_resync           (ctl_rx_force_resync),
        .ctl_rx_test_pattern           (1'b0),
        .core_rx_reset                 (1'b0), //TODO 1'b0 in example design
        .rx_clk                        (gt_txusrclk2),
        
        .stat_rx_received_local_fault  (stat_rx_received_local_fault), //
        .stat_rx_remote_fault          (stat_rx_remote_fault), //
        .stat_rx_status                (stat_rx_status), //
        .stat_rx_stomped_fcs           (stat_rx_stomped_fcs),
        .stat_rx_synced                (stat_rx_synced),
        .stat_rx_synced_err            (stat_rx_synced_err),
        .stat_rx_test_pattern_mismatch (),
        .stat_rx_toolong               (), //
        .stat_rx_total_bytes           (stat_rx_total_bytes),
        .stat_rx_total_good_bytes      (stat_rx_good_bytes),
        .stat_rx_total_good_packets    (stat_rx_good_packets), //
        .stat_rx_total_packets         (stat_rx_total_packets),
        .stat_rx_truncated             (), //
        .stat_rx_undersize             (),
        .stat_rx_unicast               (), //
        .stat_rx_vlan                  (), //
        .stat_rx_pcsl_demuxed          (),
        .stat_rx_pcsl_number_0         (),
        .stat_rx_pcsl_number_1         (),
        .stat_rx_pcsl_number_10        (),
        .stat_rx_pcsl_number_11        (),
        .stat_rx_pcsl_number_12        (),
        .stat_rx_pcsl_number_13        (),
        .stat_rx_pcsl_number_14        (),
        .stat_rx_pcsl_number_15        (),
        .stat_rx_pcsl_number_16        (),
        .stat_rx_pcsl_number_17        (),
        .stat_rx_pcsl_number_18        (),
        .stat_rx_pcsl_number_19        (),
        .stat_rx_pcsl_number_2         (),
        .stat_rx_pcsl_number_3         (),
        .stat_rx_pcsl_number_4         (),
        .stat_rx_pcsl_number_5         (),
        .stat_rx_pcsl_number_6         (),
        .stat_rx_pcsl_number_7         (),
        .stat_rx_pcsl_number_8         (),
        .stat_rx_pcsl_number_9         (),
        
        
        .stat_tx_bad_fcs               (),
        .stat_tx_broadcast             (),
        .stat_tx_frame_error           (),
        .stat_tx_local_fault           (),
        .stat_tx_multicast             (),
        .stat_tx_packet_1024_1518_bytes(),
        .stat_tx_packet_128_255_bytes  (),
        .stat_tx_packet_1519_1522_bytes(),
        .stat_tx_packet_1523_1548_bytes(),
        .stat_tx_packet_1549_2047_bytes(),
        .stat_tx_packet_2048_4095_bytes(),
        .stat_tx_packet_256_511_bytes  (),
        .stat_tx_packet_4096_8191_bytes(),
        .stat_tx_packet_512_1023_bytes (),
        .stat_tx_packet_64_bytes       (),
        .stat_tx_packet_65_127_bytes   (),
        .stat_tx_packet_8192_9215_bytes(),
        .stat_tx_packet_large          (),
        .stat_tx_packet_small          (),
        .stat_tx_total_bytes           (stat_tx_total_bytes),
        .stat_tx_total_good_bytes      (stat_tx_good_bytes),
        .stat_tx_total_good_packets    (stat_tx_good_packets),
        .stat_tx_total_packets         (stat_tx_total_packets),
        .stat_tx_unicast               (),
        .stat_tx_vlan                  (),
        
        .ctl_tx_enable                 (ctl_tx_enable),
        .ctl_tx_send_idle              (ctl_tx_send_idle),
        .ctl_tx_send_rfi               (ctl_tx_send_rfi),
        .ctl_tx_send_lfi               (ctl_tx_send_lfi),
        .ctl_tx_test_pattern           (ctl_tx_test_pattern),
        .core_tx_reset                 (1'b0),
        
        .tx_axis_tready                (s_tx_axis.tready),
        .tx_axis_tvalid                (s_tx_axis.tvalid),
        .tx_axis_tdata                 (s_tx_axis.tdata),
        .tx_axis_tkeep                 (s_tx_axis.tkeep),
        .tx_axis_tlast                 (s_tx_axis.tlast),
        .tx_axis_tuser                 (0),

        .tx_ovfout                     (tx_ovf),
        .tx_unfout                     (tx_unf),
        .tx_preamblein                 ({55{1'b0}}),

        .usr_tx_reset                  (core_tx_reset_w),
        
        .core_drp_reset                (1'b0),
        .drp_clk                       (init_clk),
        .drp_addr                      (10'b0),
        .drp_di                        (16'b0),
        .drp_en                        (1'b0),
        .drp_do                        (),
        .drp_rdy                       (),
        .drp_we                        (1'b0),


        // EXTRA STUFF
        .gt_eyescanreset(0),
        .gt_eyescantrigger(0),
        .gt_rxcdrhold(0),
`ifdef POLARITY_INV
        .gt_rxpolarity(gt_rxpolarity),
        .gt_txpolarity(gt_txpolarity),
`else
        .gt_rxpolarity(0),
        .gt_txpolarity(0),
`endif
        .gt_rxrate(0),
        .gt_txdiffctrl(0),
        .gt_txinhibit(0),
        .gt_txpippmen(0),
        .gt_txpippmsel(0),
        .gt_txpostcursor(0),
        .gt_txprbsforceerr(0),
        .gt_txprecursor(0),
        .gt_eyescandataerror(),
        .gt_txbufstatus(),
        .gt_rxdfelpmreset(0),
        .gt_rxlpmen(0),
        .gt_rxprbscntreset(0),
        .gt_rxprbserr(),
        .gt_rxprbssel(0),
        .gt_rxresetdone(),
        .gt_txprbssel(0),
        .gt_txresetdone(),
        .gt_rxbufstatus(),

        .gt_drpclk(init_clk),

        .gt0_drpdo(),
        .gt0_drprdy(),
        .gt0_drpen(0),
        .gt0_drpwe(0),
        .gt0_drpaddr(0),
        .gt0_drpdi(0),

        .gt1_drpdo(),
        .gt1_drprdy(),
        .gt1_drpen(0),
        .gt1_drpwe(0),
        .gt1_drpaddr(0),
        .gt1_drpdi(0),

        .gt2_drpdo(),
        .gt2_drprdy(),
        .gt2_drpen(0),
        .gt2_drpwe(0),
        .gt2_drpaddr(0),
        .gt2_drpdi(0),

        .gt3_drpdo(),
        .gt3_drprdy(),
        .gt3_drpen(0),
        .gt3_drpwe(0),
        .gt3_drpaddr(0),
        .gt3_drpdi(0),

        .common0_drpaddr(0),
        .common0_drpdi(0),
        .common0_drpwe(0),
        .common0_drpen(0),
        .common0_drprdy(),
        .common0_drpdo()
);
end



// `define CMAC_DEBUG
`ifdef CMAC_DEBUG

// Counting packets
logic[31:0] rx_good_packets_count;
logic[31:0] rx_total_packets_count;
logic[31:0] rx_good_bytes_count;
logic[31:0] rx_total_bytes_count;

// Counting errors
logic[15:0] align_errors;
logic[15:0] code_errors;
logic[15:0] fcs_errors;
logic[15:0] preamble_errors;
logic[15:0] sfd_errors;
    
ila_cmac_rx ila_rx (
    .clk(gt_txusrclk2), // input wire clk

    .probe0(ctl_rx_enable), // 1
    .probe1(ctl_rx_force_resync), // 1
    .probe2(stat_rx_aligned_1d), // 1
    .probe3(stat_rx_aligned), // 1
    .probe4(rx_reset_done), // 1
    .probe5(rx_prestate), // 4
    .probe6(m_rx_axis.tvalid), // 1
    .probe7(m_rx_axis.tready), // 1
    .probe8(stat_rx_aligned_err), // 1
    .probe9(stat_rx_bad_code), // 3
    .probe10({sfd_errors, preamble_errors, fcs_errors, code_errors, align_errors}), // 80
    .probe11(rx_good_packets_count), // 32
    .probe12(rx_total_packets_count), // 32
    .probe13(rx_good_bytes_count), // 32
    .probe14(rx_total_bytes_count), // 32
    .probe15(stat_rx_synced_err), // 20
    .probe16({stat_rx_got_signal_os, stat_rx_hi_ber, stat_rx_inrangeerr, stat_rx_internal_local_fault, stat_rx_jabber, stat_rx_local_fault, stat_rx_misaligned}), // 7
    .probe17({stat_rx_received_local_fault, stat_rx_remote_fault, stat_rx_status, stat_rx_stomped_fcs}), // 6
    .probe18(usr_rx_reset_w) // 1
);

always @(posedge gt_txusrclk2) begin
    if (usr_rx_reset_w) begin
        rx_good_packets_count <= '0;
        rx_total_packets_count <= '0;
        rx_good_bytes_count <= '0;
        rx_total_bytes_count <= '0;
    end
    else begin
        rx_good_packets_count <= rx_good_packets_count + stat_rx_good_packets;
        rx_total_packets_count <= rx_total_packets_count + stat_rx_total_packets;
        rx_good_bytes_count <= rx_good_bytes_count + stat_rx_good_bytes;
        rx_total_bytes_count <= rx_total_bytes_count + stat_rx_total_bytes;
    end
end
    
always @(posedge gt_txusrclk2) begin
    if (usr_rx_reset_w) begin
        align_errors <= '0;
        code_errors <= '0;
        fcs_errors <= '0;
        preamble_errors <= '0;
        sfd_errors <= '0;
    end
    else begin
        if (stat_rx_aligned_err != 0) begin
            align_errors <= align_errors + 1;
        end
        if (stat_rx_bad_code != 0) begin
            code_errors <= code_errors + 1;
        end
        if (stat_rx_bad_fcs != 0) begin
            fcs_errors <= fcs_errors + 1;
        end
        if (stat_rx_bad_preamble != 0) begin
            preamble_errors <= preamble_errors + 1;
        end
        if (stat_rx_bad_sfd != 0) begin
            sfd_errors <= sfd_errors + 1;
        end
    end
end


logic[31:0] tx_good_packets_count;
logic[31:0] tx_total_packets_count;
logic[31:0] tx_good_bytes_count;
logic[31:0] tx_total_bytes_count;

always @(posedge gt_txusrclk2) begin
    if (core_tx_reset_w) begin
        tx_good_packets_count <= '0;
        tx_total_packets_count <= '0;
        tx_good_bytes_count <= '0;
        tx_total_bytes_count <= '0;
    end
    else begin
        tx_good_packets_count <= tx_good_packets_count + stat_tx_good_packets;
        tx_total_packets_count <= tx_total_packets_count + stat_tx_total_packets;
        tx_good_bytes_count <= tx_good_bytes_count + stat_tx_good_bytes;
        tx_total_bytes_count <= tx_total_bytes_count + stat_tx_total_bytes;
    end
end

ila_cmac_tx ila_tx (
	.clk(gt_txusrclk2), // input wire clk
	
	.probe0(ctl_tx_enable), // 1
	.probe1(ctl_tx_send_idle), // 1
	.probe2(ctl_tx_send_lfi), // 1
	.probe3(ctl_tx_send_rfi), // 1
	.probe4(ctl_tx_test_pattern), // 1
	.probe5(tx_prestate), // 4
	.probe6(tx_reset_done), // 1
	.probe7(tx_good_packets_count), // 32
	.probe8(tx_total_packets_count), // 32
	.probe9(tx_good_bytes_count), // 32
	.probe10(tx_total_bytes_count), // 32
	.probe11(core_tx_reset_w), // 1 
	.probe12(s_tx_axis.tlast), // 1
	.probe13(s_tx_axis.tready), // 1
	.probe14(s_tx_axis.tvalid) // 1
);

`endif

endmodule

`default_nettype wire
