/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
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

AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) s_axis_rclk_int (.aclk(rclk), .aresetn(rresetn));
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) m_axis_rclk_int (.aclk(rclk), .aresetn(rresetn));
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) s_axis_nclk_int (.aclk(nclk), .aresetn(nresetn));
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) m_axis_nclk_int (.aclk(nclk), .aresetn(nresetn));

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
