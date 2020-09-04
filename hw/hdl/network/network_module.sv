/*
 * Copyright (c) 2019, Systems Group, ETH Zurich
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


module network_module
(
    input wire          dclk,
    output wire         net_clk,
    input wire          sys_reset,
    input wire          aresetn,
    output wire         network_init_done,
    
    input wire          gt_refclk_p,
    input wire          gt_refclk_n,
    
	input  wire [3:0] gt_rxp_in,
	input  wire [3:0] gt_rxn_in,
	output wire [3:0] gt_txp_out,
	output wire [3:0] gt_txn_out,

	output wire         user_rx_reset,
	output wire         user_tx_reset,
	output wire         gtpowergood_out,
	
	//Axi Stream Interface
	AXI4S.m       m_axis_net_rx,
	AXI4S.s       s_axis_net_tx
);

reg core_reset_tmp = 1'b0;
reg core_reset = 1'b0;

always @(posedge sys_reset or posedge net_clk) begin 
   if (sys_reset) begin
      core_reset_tmp <= 1'b0;
      core_reset     <= 1'b0;
   end
   else begin
      //Hold core in reset until everything is ready
      //core_reset_tmp <= !(sys_reset | user_tx_reset | user_rx_reset);
      core_reset_tmp <= !(sys_reset | user_tx_reset);
      core_reset     <= core_reset_tmp;
   end
end
assign network_init_done = core_reset;

/*
 * RX
 */
AXI4S rx_axis();

/*
 * TX
 */
AXI4S tx_axis();
AXI4S axis_tx_pkg_to_fifo();
AXI4S axis_tx_padding_to_fifo();

cmac_axis_wrapper cmac_wrapper_inst
(
    .gt_rxp_in(gt_rxp_in),
    .gt_rxn_in(gt_rxn_in),
    .gt_txp_out(gt_txp_out),
    .gt_txn_out(gt_txn_out),
    .gt_ref_clk_p(gt_refclk_p),
    .gt_ref_clk_n(gt_refclk_n),
    .init_clk(dclk),
    .sys_reset(sys_reset),

    .m_rx_axis(rx_axis),
    .s_tx_axis(tx_axis),

    .rx_aligned(gtpowergood_out), //Todo REmove/rename
    .usr_tx_clk(net_clk),
    .tx_rst(user_tx_reset),
    .rx_rst(user_rx_reset),
    .gt_rxrecclkout() //not used
);


//RX Clock crossing (same clock)
axis_data_fifo_512_cc rx_crossing (
  //.s_axis_aresetn(~(sys_reset | user_rx_reset)),
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(net_clk),
  .s_axis_tvalid(rx_axis.tvalid),
  .s_axis_tready(rx_axis.tready),
  .s_axis_tdata(rx_axis.tdata),
  .s_axis_tkeep(rx_axis.tkeep),
  .s_axis_tlast(rx_axis.tlast),
  .m_axis_aclk(net_clk),
  .m_axis_tvalid(m_axis_net_rx.tvalid),
  .m_axis_tready(m_axis_net_rx.tready),
  .m_axis_tdata(m_axis_net_rx.tdata),
  .m_axis_tkeep(m_axis_net_rx.tkeep),
  .m_axis_tlast(m_axis_net_rx.tlast)
);

// TX
// Pad Ethernet frames to at least 64B
// Packet FIFO, makes sure that whole packet is passed in a single burst to the CMAC
axis_data_fifo_512_cc tx_crossing (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(net_clk),
  .s_axis_tvalid(axis_tx_pkg_to_fifo.tvalid),
  .s_axis_tready(axis_tx_pkg_to_fifo.tready),
  .s_axis_tdata(axis_tx_pkg_to_fifo.tdata),
  .s_axis_tkeep(axis_tx_pkg_to_fifo.tkeep),
  .s_axis_tlast(axis_tx_pkg_to_fifo.tlast),
  .m_axis_aclk(net_clk),
  .m_axis_tvalid(tx_axis.tvalid),
  .m_axis_tready(tx_axis.tready),
  .m_axis_tdata(tx_axis.tdata),
  .m_axis_tkeep(tx_axis.tkeep),
  .m_axis_tlast(tx_axis.tlast)
);

axis_pkg_fifo_512 axis_pkg_fifo_512 (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(net_clk),
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
  .m_axis_TVALID(axis_tx_padding_to_fifo.tvalid),
  .m_axis_TREADY(axis_tx_padding_to_fifo.tready),
  .m_axis_TDATA(axis_tx_padding_to_fifo.tdata),
  .m_axis_TKEEP(axis_tx_padding_to_fifo.tkeep),
  .m_axis_TLAST(axis_tx_padding_to_fifo.tlast),
  .s_axis_TVALID(s_axis_net_tx.tvalid),
  .s_axis_TREADY(s_axis_net_tx.tready),
  .s_axis_TDATA(s_axis_net_tx.tdata),
  .s_axis_TKEEP(s_axis_net_tx.tkeep),
  .s_axis_TLAST(s_axis_net_tx.tlast),
  .ap_clk(net_clk),
  .ap_rst_n(aresetn)
);

endmodule

`default_nettype wire
