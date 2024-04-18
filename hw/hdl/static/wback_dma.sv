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