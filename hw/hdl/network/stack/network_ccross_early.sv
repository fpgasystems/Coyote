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

`include "axi_macros.svh"
`include "lynx_macros.svh"

/**
 * @brief   Network early clock crossing
 *
 * Cross early from 322 -> nclk
 */
module network_ccross_early #(
    parameter integer       ENABLED = 1,
    parameter integer       N_STGS = 4
) (
    input  wire             rclk,
    input  wire             rresetn,
    input  wire             nclk,
    input  wire             nresetn,
    
    // Network clock raw - 322 MHz
    AXI4S.s                 s_axis_rclk,
    AXI4S.m                 m_axis_rclk,

    // Network clock internal - whatever
    AXI4S.s                 s_axis_nclk,
    AXI4S.m                 m_axis_nclk
);

reg rresetn_reg = 1'b1;
always @ (posedge rclk) begin
  rresetn_reg <= rresetn;
end

reg nresetn_reg = 1'b1;
always @ (posedge nclk) begin
  nresetn_reg <= nresetn;
end

AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) s_axis_rclk_int();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) m_axis_rclk_int ();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) s_axis_nclk_int ();
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) m_axis_nclk_int ();

axis_reg_array #(.N_STAGES(N_STGS)) inst_1 (.aclk(rclk), .aresetn(rresetn_reg), .s_axis(s_axis_rclk),     .m_axis(s_axis_rclk_int));
axis_reg_array #(.N_STAGES(N_STGS)) inst_2 (.aclk(rclk), .aresetn(rresetn_reg), .s_axis(m_axis_rclk_int), .m_axis(m_axis_rclk));
axis_reg_array #(.N_STAGES(N_STGS)) inst_3 (.aclk(nclk), .aresetn(nresetn_reg), .s_axis(s_axis_nclk),     .m_axis(s_axis_nclk_int));
axis_reg_array #(.N_STAGES(N_STGS)) inst_4 (.aclk(nclk), .aresetn(nresetn_reg), .s_axis(m_axis_nclk_int), .m_axis(m_axis_nclk));

// Sync up
if(ENABLED == 1) begin

  //
  // Crossings
  //

  axis_data_fifo_net_ccross_early_512 inst_cross_ns_nr (
      .m_axis_aclk(rclk),
      .s_axis_aclk(nclk),
      .s_axis_aresetn(nresetn_reg),
      .s_axis_tvalid(s_axis_nclk_int.tvalid),
      .s_axis_tready(s_axis_nclk_int.tready),
      .s_axis_tdata(s_axis_nclk_int.tdata),
      .s_axis_tkeep(s_axis_nclk_int.tkeep),
      .s_axis_tlast(s_axis_nclk_int.tlast),
      .m_axis_tvalid(m_axis_rclk_int.tvalid),
      .m_axis_tready(m_axis_rclk_int.tready),
      .m_axis_tdata(m_axis_rclk_int.tdata),
      .m_axis_tkeep(m_axis_rclk_int.tkeep),
      .m_axis_tlast(m_axis_rclk_int.tlast)
  );

  axis_data_fifo_net_ccross_early_512 inst_cross_nr_ns (
      .m_axis_aclk(nclk),
      .s_axis_aclk(rclk),
      .s_axis_aresetn(rresetn_reg),
      .s_axis_tvalid(s_axis_rclk_int.tvalid),
      .s_axis_tready(s_axis_rclk_int.tready),
      .s_axis_tdata(s_axis_rclk_int.tdata),
      .s_axis_tkeep(s_axis_rclk_int.tkeep),
      .s_axis_tlast(s_axis_rclk_int.tlast),
      .m_axis_tvalid(m_axis_nclk_int.tvalid),
      .m_axis_tready(m_axis_nclk_int.tready),
      .m_axis_tdata(m_axis_nclk_int.tdata),
      .m_axis_tkeep(m_axis_nclk_int.tkeep),
      .m_axis_tlast(m_axis_nclk_int.tlast)
  );
end
else begin
  `AXIS_ASSIGN(s_axis_nclk_int, m_axis_rclk_int)
  `AXIS_ASSIGN(s_axis_rclk_int, m_axis_nclk_int)
end


endmodule
