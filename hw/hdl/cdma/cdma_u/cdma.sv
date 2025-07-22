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
 * @brief   Unaligned CDMA top level
 *
 * The unaligned CDMA top level. Contains read and write DMA engines. 
 * Outstanding queues at the input. High resource overhead.
 *
 *  @param BURST_LEN    Maximum burst length size
 *  @param DATA_BITS    Size of the data bus (both AXI and stream)
 *  @param ADDR_BITS    Size of the address bits
 *  @param ID_BITS      Size of the ID bits
 */
module cdma #(
    parameter integer                   BURST_LEN = 64,
    parameter integer                   DATA_BITS = AXI_DATA_BITS,
    parameter integer                   ADDR_BITS = AXI_ADDR_BITS,
    parameter integer                   ID_BITS = AXI_ID_BITS
) (
    input  wire                         aclk,
    input  wire                         aresetn,

    dmaIntf.s                           rd_CDMA,
    dmaIntf.s                           wr_CDMA,

    AXI4.m                              m_axi_ddr,

    AXI4S.s                             s_axis_ddr,
    AXI4S.m                             m_axis_ddr
);

// RD ------------------------------------------------------------------------------------------
dmaIntf rd_CDMA_que ();
dmaIntf rd_CDMA_int ();

logic rd_seq_snk_valid, rd_seq_snk_ready;
logic rd_seq_src_data;

logic tmp_last_rd;

// Request queue rd
queue_stream #(
  .QTYPE(dma_req_t),
  .QDEPTH(N_OUTSTANDING)
) inst_rddma_out (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(rd_CDMA.valid),
  .rdy_snk(rd_CDMA.ready),
  .data_snk(rd_CDMA.req),
  .val_src(rd_CDMA_que.valid),
  .rdy_src(rd_CDMA_que.ready),
  .data_src(rd_CDMA_que.req)
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
  .data_snk(rd_CDMA_que.req.last),
  .val_src(),
  .rdy_src(rd_CDMA_int.rsp.done),
  .data_src(rd_seq_src_data)
);

always_comb begin
    // =>
    rd_CDMA_que.ready = rd_CDMA_int.ready & rd_seq_snk_ready & rd_CDMA_que.valid;
    rd_CDMA_int.valid = rd_CDMA_que.ready;
    rd_seq_snk_valid = rd_CDMA_que.ready;

    rd_CDMA_int.req = rd_CDMA_que.req;

    // <= 
    rd_CDMA_que.rsp.done = rd_CDMA_int.rsp.done; // passthrough
    rd_CDMA.rsp.done = rd_CDMA_que.rsp.done & rd_seq_src_data;

    m_axis_ddr.tlast = tmp_last_rd & rd_seq_src_data;
end

// WR ------------------------------------------------------------------------------------------
dmaIntf wr_CDMA_que ();
dmaIntf wr_CDMA_int ();

logic wr_seq_snk_valid, wr_seq_snk_ready;
logic wr_seq_src_data;

// Request queue wr
queue_stream #(.QTYPE(dma_req_t)) inst_wrdma_out (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(wr_CDMA.valid),
  .rdy_snk(wr_CDMA.ready),
  .data_snk(wr_CDMA.req),
  .val_src(wr_CDMA_que.valid),
  .rdy_src(wr_CDMA_que.ready),
  .data_src(wr_CDMA_que.req)
);

// CTL sequencing wr
queue_stream #(.QTYPE(logic)) inst_ctl_seq_wr (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(wr_seq_snk_valid),
  .rdy_snk(wr_seq_snk_ready),
  .data_snk(wr_CDMA_que.req.last),
  .val_src(),
  .rdy_src(wr_CDMA_int.rsp.done),
  .data_src(wr_seq_src_data)
);

always_comb begin
    // =>
    wr_CDMA_que.ready = wr_CDMA_int.ready & wr_seq_snk_ready & wr_CDMA_que.valid;
    wr_CDMA_int.valid = wr_CDMA_que.ready;
    wr_seq_snk_valid = wr_CDMA_que.ready;

    wr_CDMA_int.req = wr_CDMA_que.req;

    // <= 
    wr_CDMA_que.rsp.done = wr_CDMA_int.rsp.done; // passthrough
    wr_CDMA.rsp.done = wr_CDMA_que.rsp.done & wr_seq_src_data;
end

// 
// CDMA
//
axi_dma_rd #(
    .AXI_DATA_WIDTH(DATA_BITS),
    .AXI_ADDR_WIDTH(ADDR_BITS),
    .AXI_STRB_WIDTH(DATA_BITS/8),
    .AXI_MAX_BURST_LEN(BURST_LEN),
    .AXIS_DATA_WIDTH(DATA_BITS),
    .AXIS_KEEP_ENABLE(1),
    .AXIS_KEEP_WIDTH(DATA_BITS/8),
    .AXIS_LAST_ENABLE(1'b1),
    .LEN_WIDTH(LEN_BITS),
    .AXI_ID_BITS(ID_BITS)
)
axi_dma_rd_inst (
    .aclk(aclk),
    .aresetn(aresetn),

    /*
     * AXI read descriptor input
     */
    .s_axis_read_desc_addr(rd_CDMA_int.req.paddr),
    .s_axis_read_desc_len(rd_CDMA_int.req.len),
    .s_axis_read_desc_valid(rd_CDMA_int.valid),
    .s_axis_read_desc_ready(rd_CDMA_int.ready),

    /*
     * AXI read descriptor status output
     */
    .m_axis_read_desc_status_valid(rd_CDMA_int.rsp.done),

    /*
     * AXI stream read data output
     */
    .m_axis_read_data_tdata(m_axis_ddr.tdata),
    .m_axis_read_data_tkeep(m_axis_ddr.tkeep),
    .m_axis_read_data_tvalid(m_axis_ddr.tvalid),
    .m_axis_read_data_tready(m_axis_ddr.tready),
    .m_axis_read_data_tlast(tmp_last_rd),

    /*
     * AXI master interface
     */
    .m_axi_arid(m_axi_ddr.arid),
    .m_axi_araddr(m_axi_ddr.araddr),
    .m_axi_arlen(m_axi_ddr.arlen),
    .m_axi_arsize(m_axi_ddr.arsize),
    .m_axi_arburst(m_axi_ddr.arburst),
    .m_axi_arlock(m_axi_ddr.arlock),
    .m_axi_arcache(m_axi_ddr.arcache),
    .m_axi_arprot(m_axi_ddr.arprot),
    .m_axi_arvalid(m_axi_ddr.arvalid),
    .m_axi_arready(m_axi_ddr.arready),
    .m_axi_rid(m_axi_ddr.rid),
    .m_axi_rdata(m_axi_ddr.rdata),
    .m_axi_rresp(m_axi_ddr.rresp),
    .m_axi_rlast(m_axi_ddr.rlast),
    .m_axi_rvalid(m_axi_ddr.rvalid),
    .m_axi_rready(m_axi_ddr.rready)
);

axi_dma_wr #(
    .AXI_DATA_WIDTH(DATA_BITS),
    .AXI_ADDR_WIDTH(ADDR_BITS),
    .AXI_STRB_WIDTH(DATA_BITS/8),
    .AXI_MAX_BURST_LEN(BURST_LEN),
    .AXIS_DATA_WIDTH(DATA_BITS),
    .AXIS_KEEP_ENABLE(1),
    .AXIS_KEEP_WIDTH(DATA_BITS/8),
    .AXIS_LAST_ENABLE(0),
    .LEN_WIDTH(LEN_BITS),
    .AXI_ID_BITS(ID_BITS)
)
axi_dma_wr_inst (
    .aclk(aclk),
    .aresetn(aresetn),

    /*
     * AXI write descriptor input
     */
    .s_axis_write_desc_addr(wr_CDMA_int.req.paddr),
    .s_axis_write_desc_len(wr_CDMA_int.req.len),
    .s_axis_write_desc_valid(wr_CDMA_int.valid),
    .s_axis_write_desc_ready(wr_CDMA_int.ready),

    /*
     * AXI write descriptor status output
     */
    .m_axis_write_desc_status_valid(wr_CDMA_int.rsp.done),

    /*
     * AXI stream write data input
     */
    .s_axis_write_data_tdata(s_axis_ddr.tdata),
    .s_axis_write_data_tkeep(s_axis_ddr.tkeep),
    .s_axis_write_data_tvalid(s_axis_ddr.tvalid),
    .s_axis_write_data_tready(s_axis_ddr.tready),
    .s_axis_write_data_tlast(s_axis_ddr.tlast),

    /*
     * AXI master interface
     */
    .m_axi_awid(m_axi_ddr.awid),
    .m_axi_awaddr(m_axi_ddr.awaddr),
    .m_axi_awlen(m_axi_ddr.awlen),
    .m_axi_awsize(m_axi_ddr.awsize),
    .m_axi_awburst(m_axi_ddr.awburst),
    .m_axi_awlock(m_axi_ddr.awlock),
    .m_axi_awcache(m_axi_ddr.awcache),
    .m_axi_awvalid(m_axi_ddr.awvalid),
    .m_axi_awready(m_axi_ddr.awready),
    .m_axi_wdata(m_axi_ddr.wdata),
    .m_axi_wstrb(m_axi_ddr.wstrb),
    .m_axi_wlast(m_axi_ddr.wlast),
    .m_axi_wvalid(m_axi_ddr.wvalid),
    .m_axi_wready(m_axi_ddr.wready),
    .m_axi_bid(m_axi_ddr.bid),
    .m_axi_bresp(m_axi_ddr.bresp),
    .m_axi_bvalid(m_axi_ddr.bvalid),
    .m_axi_bready(m_axi_ddr.bready)
);

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_CDMA_U

`endif

endmodule
