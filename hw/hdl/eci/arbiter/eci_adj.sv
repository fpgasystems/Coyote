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

module eci_adj (
    input  logic                aclk,
    input  logic                aresetn,

    dmaIntf.s                   s_rdCDMA,
    dmaIntf.m                   m_rdCDMA,

    dmaIntf.s                   s_wrCDMA,
    dmaIntf.m                   m_wrCDMA,

    AXI4S.s                     s_axis_rd,
    AXI4S.m                     m_axis_rd,

    AXI4S.s                     s_axis_wr,
    AXI4S.m                     m_axis_wr
);

// RD ------------------------------------------------------------------------------------------
dmaIntf rdCDMA_que ();

logic rd_seq_snk_valid, rd_seq_snk_ready;
logic rd_seq_src_data;

// Request queue rd
queue_stream #(
  .QTYPE(dma_req_t),
  .QDEPTH(N_OUTSTANDING)
) inst_rddma_out (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(s_rdCDMA.valid),
  .rdy_snk(s_rdCDMA.ready),
  .data_snk(s_rdCDMA.req),
  .val_src(rdCDMA_que.valid),
  .rdy_src(rdCDMA_que.ready),
  .data_src(rdCDMA_que.req)
);

// CTL sequencing rd
queue_stream #(
  .QTYPE(logic),
  .QDEPTH(N_OUTSTANDING)
) inst_ctl_seq_rd (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(rd_seq_snk_valid),
  .rdy_snk(rd_seq_snk_ready),
  .data_snk(rdCDMA_que.req.ctl),
  .val_src(),
  .rdy_src(m_rdCDMA.rsp.done),
  .data_src(rd_seq_src_data)
);

always_comb begin
    // =>
    rdCDMA_que.ready = m_rdCDMA.ready & rd_seq_snk_ready & rdCDMA_que.valid;
    m_rdCDMA.valid = rdCDMA_que.ready;
    rd_seq_snk_valid = rdCDMA_que.ready;

    m_rdCDMA.req = rdCDMA_que.req;

    // <= 
    rdCDMA_que.rsp.done = m_rdCDMA.rsp.done; // passthrough
    s_rdCDMA.rsp.done = rdCDMA_que.rsp.done & rd_seq_src_data;

    // Data
    m_axis_rd.tlast  = s_axis_rd.tlast;
    m_axis_rd.tdata  = s_axis_rd.tdata;
    m_axis_rd.tkeep  = s_axis_rd.tkeep;
    m_axis_rd.tvalid = s_axis_rd.tvalid;
    s_axis_rd.tready  = m_axis_rd.tready;
end

// WR ------------------------------------------------------------------------------------------
dmaIntf wrCDMA_que ();

logic wr_seq_snk_valid, wr_seq_snk_ready;
logic wr_seq_src_data;

// Request queue wr
queue_stream #(
  .QTYPE(dma_req_t),
  .QDEPTH(N_OUTSTANDING)
) inst_wrdma_out (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(s_wrCDMA.valid),
  .rdy_snk(s_wrCDMA.ready),
  .data_snk(s_wrCDMA.req),
  .val_src(wrCDMA_que.valid),
  .rdy_src(wrCDMA_que.ready),
  .data_src(wrCDMA_que.req)
);

// CTL sequencing wr
queue_stream #(
  .QTYPE(logic),
  .QDEPTH(N_OUTSTANDING)
) inst_ctl_seq_wr (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(wr_seq_snk_valid),
  .rdy_snk(wr_seq_snk_ready),
  .data_snk(wrCDMA_que.req.ctl),
  .val_src(),
  .rdy_src(m_wrCDMA.rsp.done),
  .data_src(wr_seq_src_data)
);

always_comb begin
    // =>
    wrCDMA_que.ready = m_wrCDMA.ready & wr_seq_snk_ready & wrCDMA_que.valid;
    m_wrCDMA.valid = wrCDMA_que.ready;
    wr_seq_snk_valid = wrCDMA_que.ready;

    m_wrCDMA.req = wrCDMA_que.req;

    // <= 
    wrCDMA_que.rsp.done = m_wrCDMA.rsp.done; // passthrough
    s_wrCDMA.rsp.done = wrCDMA_que.rsp.done & wr_seq_src_data;

    // Data
    m_axis_wr.tlast  = s_axis_wr.tlast;
    m_axis_wr.tdata  = s_axis_wr.tdata;
    m_axis_wr.tkeep  = s_axis_wr.tkeep;
    m_axis_wr.tvalid = s_axis_wr.tvalid;
    s_axis_wr.tready  = m_axis_wr.tready;
end

endmodule