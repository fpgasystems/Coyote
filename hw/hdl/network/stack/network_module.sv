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
`timescale 1ns / 1ps

import lynxTypes::*;

module network_module #(
    parameter integer   QSFP = 0,
    parameter integer   N_STGS = 2
) (
    input  wire         init_clk,
    input  wire         sys_reset,
    output wire         rclk,
    output wire         rresetn,

    input  wire         gt_refclk_p,
    input  wire         gt_refclk_n,
    
    input  wire [3:0]   gt_rxp_in,
    input  wire [3:0]   gt_rxn_in,
    output wire [3:0]   gt_txp_out,
    output wire [3:0]   gt_txn_out,
	
    // Network streams
    AXI4S.m             m_axis_net_rx,
    AXI4S.s             s_axis_net_tx
);

wire network_init_done;
//wire user_rx_reset;
wire user_tx_reset;
reg core_reset_tmp = 1'b0;
reg core_reset = 1'b0;

// Network reset
always @(posedge rclk) begin 
      //core_reset_tmp <= !(user_tx_reset | user_rx_reset);
      core_reset_tmp <= !(user_tx_reset);
      core_reset     <= core_reset_tmp;
end
assign network_init_done = core_reset;

BUFG bufg_aresetn(
    .I(network_init_done),
    .O(rresetn)
);

/*
 * RX
 */
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) rx_axis_cmac();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) rx_axis();

logic [31:0] wr_cnt;
logic prog_full;

/*
 * TX
 */
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) tx_axis_cmac();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) tx_axis();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_tx_pkg_to_fifo();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_tx_padding_to_fifo();

// CMAC
cmac_axis_wrapper #(
    .QSFP(QSFP)
) cmac_wrapper_inst (
    .init_clk(init_clk),
    .sys_reset(sys_reset),

    .gt_ref_clk_p(gt_refclk_p),
    .gt_ref_clk_n(gt_refclk_n),
    .gt_rxp_in(gt_rxp_in),
    .gt_rxn_in(gt_rxn_in),
    .gt_txp_out(gt_txp_out),
    .gt_txn_out(gt_txn_out),
    
    .m_rx_axis(rx_axis_cmac),
    .s_tx_axis(tx_axis_cmac),

    .usr_clk(rclk),
    .tx_rst(user_tx_reset)
    //.rx_rst(user_rx_reset)
);


// Drop 
network_bp_drop inst_network_bp_drop (
  .aclk(rclk),
  .aresetn(rresetn),
  .prog_full(prog_full),
  .wr_cnt(wr_cnt),
  .s_rx_axis(rx_axis_cmac),
  .m_rx_axis(rx_axis),
  .s_tx_axis(tx_axis),
  .m_tx_axis(tx_axis_cmac)
);

// RX Clock crossing (same clock)
axis_data_fifo_512_cc_rx rx_crossing (
  .s_axis_aresetn(rresetn),
  .s_axis_aclk(rclk),
  .s_axis_tvalid(rx_axis.tvalid),
  .s_axis_tready(rx_axis.tready),
  .s_axis_tdata(rx_axis.tdata),
  .s_axis_tkeep(rx_axis.tkeep),
  .s_axis_tlast(rx_axis.tlast),
  //.m_axis_aclk(rclk),
  .m_axis_tvalid(m_axis_net_rx.tvalid),
  .m_axis_tready(m_axis_net_rx.tready),
  .m_axis_tdata(m_axis_net_rx.tdata),
  .m_axis_tkeep(m_axis_net_rx.tkeep),
  .m_axis_tlast(m_axis_net_rx.tlast),
  .axis_wr_data_count(wr_cnt),
  .prog_full(prog_full)
);

// TX
// Pad Ethernet frames to at least 64B
// Packet FIFO, makes sure that whole packet is passed in a single burst to the CMAC
axis_data_fifo_512_cc_tx tx_crossing (
  .s_axis_aresetn(rresetn),
  .s_axis_aclk(rclk),
  .s_axis_tvalid(axis_tx_pkg_to_fifo.tvalid),
  .s_axis_tready(axis_tx_pkg_to_fifo.tready),
  .s_axis_tdata(axis_tx_pkg_to_fifo.tdata),
  .s_axis_tkeep(axis_tx_pkg_to_fifo.tkeep),
  .s_axis_tlast(axis_tx_pkg_to_fifo.tlast),
  //.m_axis_aclk(rclk),
  .m_axis_tvalid(tx_axis.tvalid),
  .m_axis_tready(tx_axis.tready),
  .m_axis_tdata(tx_axis.tdata),
  .m_axis_tkeep(tx_axis.tkeep),
  .m_axis_tlast(tx_axis.tlast)
);

axis_pkg_fifo_512 axis_pkg_fifo_512 (
  .s_axis_aresetn(rresetn),
  .s_axis_aclk(rclk),
  .s_axis_tvalid(axis_tx_padding_to_fifo.tvalid),
  .s_axis_tready(axis_tx_padding_to_fifo.tready),
  .s_axis_tdata(axis_tx_padding_to_fifo.tdata),
  .s_axis_tkeep(axis_tx_padding_to_fifo.tkeep),
  .s_axis_tlast(axis_tx_padding_to_fifo.tlast),
  .m_axis_tvalid(axis_tx_pkg_to_fifo.tvalid),
  .m_axis_tready(axis_tx_pkg_to_fifo.tready),
  .m_axis_tdata(axis_tx_pkg_to_fifo.tdata),
  .m_axis_tkeep(axis_tx_pkg_to_fifo.tkeep),
  .m_axis_tlast(axis_tx_pkg_to_fifo.tlast)
);

ethernet_frame_padding_512_ip ethernet_frame_padding_inst (
  .ap_clk(rclk),
  .ap_rst_n(rresetn),
  .m_axis_TVALID(axis_tx_padding_to_fifo.tvalid),
  .m_axis_TREADY(axis_tx_padding_to_fifo.tready),
  .m_axis_TDATA(axis_tx_padding_to_fifo.tdata),
  .m_axis_TKEEP(axis_tx_padding_to_fifo.tkeep),
  .m_axis_TLAST(axis_tx_padding_to_fifo.tlast),
  .s_axis_TVALID(s_axis_net_tx.tvalid),
  .s_axis_TREADY(s_axis_net_tx.tready),
  .s_axis_TDATA(s_axis_net_tx.tdata),
  .s_axis_TKEEP(s_axis_net_tx.tkeep),
  .s_axis_TLAST(s_axis_net_tx.tlast)
);

endmodule

`default_nettype wire
