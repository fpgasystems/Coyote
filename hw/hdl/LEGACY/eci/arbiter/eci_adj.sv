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