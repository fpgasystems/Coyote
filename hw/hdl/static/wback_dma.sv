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

/**
 * WBACK DMA
 *
 */
module wback_dma #(
    parameter integer                   QDEPTH = 16  
) (
	input  logic    					aclk,    
	input  logic    					aresetn,

    // Wback meta
    metaIntf.s                          s_wback,

    // DMA
    dmaIntf.m                           m_dma_wr,
    AXI4S.m                             m_axis_wback
);

// DMA out
dmaIntf wb_req ();
dmaIntf dma_wr();

always_comb begin
  wb_req.valid = s_wback.valid;
  s_wback.ready = wb_req.ready;
  wb_req.req = 0;
  wb_req.req.last = 1'b1;
  wb_req.req.paddr = s_wback.data.paddr;
  wb_req.req.len = 4;
end

axis_data_fifo_wb_dma_static inst_que_wb (
  .s_axis_aclk(aclk),
  .s_axis_aresetn(aresetn),
  .s_axis_tvalid(wb_req.valid),
  .s_axis_tready(wb_req.ready),
  .s_axis_tdata(wb_req.req),
  .m_axis_tvalid(dma_wr.valid),
  .m_axis_tready(dma_wr.ready),
  .m_axis_tdata(dma_wr.req)
);
dma_reg_array_static #(.N_STAGES(N_REG_DYN_HOST_S0)) inst_dma_out (.aclk(aclk), .aresetn(aresetn), .s_req(dma_wr), .m_req(m_dma_wr));

// STREAM out
metaIntf #(.STYPE(logic[31:0])) wback ();
metaIntf #(.STYPE(logic[31:0])) wback_out ();

axis_data_fifo_wb_data_static inst_que_wb_data (
  .s_axis_aclk(aclk),
  .s_axis_aresetn(aresetn),
  .s_axis_tvalid(wb_req.valid & wb_req.ready),
  .s_axis_tready(),
  .s_axis_tdata(s_wback.data.value),
  .m_axis_tvalid(wback.valid),
  .m_axis_tready(wback.ready),
  .m_axis_tdata(wback.data)
);
meta_reg_array_static #(.DATA_BITS(32), .N_STAGES(N_REG_DYN_HOST_S0)) inst_data_out (.aclk(aclk), .aresetn(aresetn), .s_meta(wback),  .m_meta(wback_out));

assign m_axis_wback.tvalid   = wback_out.valid;
assign wback_out.ready = m_axis_wback.tready;
assign m_axis_wback.tdata[31:0]    = wback_out.data;
assign m_axis_wback.tkeep[3:0]    = ~0;
assign m_axis_wback.tlast    = 1'b1;

endmodule