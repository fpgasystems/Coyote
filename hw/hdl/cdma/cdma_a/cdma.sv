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
 * @brief   Aligned CDMA top level
 *
 * The aligned CDMA top level. Contains read and write DMA engines. 
 * Outstanding queues at the input. Low resource overhead.
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
    parameter integer                   ID_BITS = AXI_ID_BITS,
    parameter integer                   BURST_OUTSTANDING = N_OUTSTANDING
) (
    input  logic                        aclk,
    input  logic                        aresetn,

    dmaIntf.s                           rd_CDMA,
    dmaIntf.s                           wr_CDMA,

    AXI4.m                              m_axi_ddr,

    AXI4S.s                             s_axis_ddr,
    AXI4S.m                             m_axis_ddr
);

// Decoupling
dmaIntf rd_CDMA_int ();
dmaIntf wr_CDMA_int ();

// RD ------------------------------------------------------------------------------------------
// CDMA completion
assign rd_CDMA.rsp.done = rd_CDMA_int.rsp.done;

// Request queue
queue_stream #(
    .QTYPE(dma_req_t),
    .QDEPTH(N_OUTSTANDING)
) inst_rddma_out (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(rd_CDMA.valid),
  .rdy_snk(rd_CDMA.ready),
  .data_snk(rd_CDMA.req),
  .val_src(rd_CDMA_int.valid),
  .rdy_src(rd_CDMA_int.ready),
  .data_src(rd_CDMA_int.req)
);

// WR ------------------------------------------------------------------------------------------
// CDMA completion
assign wr_CDMA.rsp.done = wr_CDMA_int.rsp.done;

queue_stream #(
    .QTYPE(dma_req_t),
    .QDEPTH(N_OUTSTANDING)
) inst_wrdma_out (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(wr_CDMA.valid),
  .rdy_snk(wr_CDMA.ready),
  .data_snk(wr_CDMA.req),
  .val_src(wr_CDMA_int.valid),
  .rdy_src(wr_CDMA_int.ready),
  .data_src(wr_CDMA_int.req)
);

// 
// CDMA
//

// RD channel
axi_dma_rd #(
    .BURST_LEN(BURST_LEN),
    .DATA_BITS(DATA_BITS),
    .ADDR_BITS(ADDR_BITS),
    .ID_BITS(ID_BITS),
    .MAX_OUTSTANDING(BURST_OUTSTANDING)
) axi_dma_rd_inst (
    .aclk(aclk),
    .aresetn(aresetn),

    // CS
    .ctrl_valid(rd_CDMA_int.valid),
    .stat_ready(rd_CDMA_int.ready),
    .ctrl_addr(rd_CDMA_int.req.paddr),
    .ctrl_len(rd_CDMA_int.req.len),
    .ctrl_ctl(rd_CDMA_int.req.last),
    .stat_done(rd_CDMA_int.rsp.done),

    // AXI
    .arvalid(m_axi_ddr.arvalid),
    .arready(m_axi_ddr.arready),
    .araddr(m_axi_ddr.araddr),
    .arid(m_axi_ddr.arid),
    .arlen(m_axi_ddr.arlen),
    .arsize(m_axi_ddr.arsize),
    .arburst(m_axi_ddr.arburst),
    .arlock(m_axi_ddr.arlock),
    .arcache(m_axi_ddr.arcache),
    .arprot(m_axi_ddr.arprot),
    .rvalid(m_axi_ddr.rvalid),
    .rready(m_axi_ddr.rready),
    .rdata(m_axi_ddr.rdata),
    .rlast(m_axi_ddr.rlast),
    .rid(m_axi_ddr.rid),
    .rresp(m_axi_ddr.rresp),

    // AXIS
    .axis_out_tdata(m_axis_ddr.tdata),
    .axis_out_tkeep(m_axis_ddr.tkeep),
    .axis_out_tvalid(m_axis_ddr.tvalid),
    .axis_out_tready(m_axis_ddr.tready),
    .axis_out_tlast(m_axis_ddr.tlast)
);

// Tie-off RD
assign m_axi_ddr.arqos = 0;
assign m_axi_ddr.arregion = 0;

// WR channel
axi_dma_wr #(
    .BURST_LEN(BURST_LEN),
    .DATA_BITS(DATA_BITS),
    .ADDR_BITS(ADDR_BITS),
    .ID_BITS(ID_BITS),
    .MAX_OUTSTANDING(BURST_OUTSTANDING)
) axi_dma_wr_inst (
    .aclk(aclk),
    .aresetn(aresetn),

    // CS
    .ctrl_valid(wr_CDMA_int.valid),
    .stat_ready(wr_CDMA_int.ready),
    .ctrl_addr(wr_CDMA_int.req.paddr),
    .ctrl_len(wr_CDMA_int.req.len),
    .ctrl_ctl(wr_CDMA_int.req.last),
    .stat_done(wr_CDMA_int.rsp.done),

    // AXI
    .awvalid(m_axi_ddr.awvalid),
    .awready(m_axi_ddr.awready),
    .awaddr(m_axi_ddr.awaddr),
    .awid(m_axi_ddr.awid),
    .awlen(m_axi_ddr.awlen),
    .awsize(m_axi_ddr.awsize),
    .awburst(m_axi_ddr.awburst),
    .awlock(m_axi_ddr.awlock),
    .awcache(m_axi_ddr.awcache),
    .wdata(m_axi_ddr.wdata),
    .wstrb(m_axi_ddr.wstrb),
    .wlast(m_axi_ddr.wlast),
    .wvalid(m_axi_ddr.wvalid),
    .wready(m_axi_ddr.wready),
    .bid(m_axi_ddr.bid),
    .bresp(m_axi_ddr.bresp),
    .bvalid(m_axi_ddr.bvalid),
    .bready(m_axi_ddr.bready),

    // AXIS
    .axis_in_tdata(s_axis_ddr.tdata),
    .axis_in_tkeep(s_axis_ddr.tkeep),
    .axis_in_tvalid(s_axis_ddr.tvalid),
    .axis_in_tready(s_axis_ddr.tready),
    .axis_in_tlast(s_axis_ddr.tlast)
);

// Tie-off WR
assign m_axi_ddr.awqos = 0;
assign m_axi_ddr.awregion = 0;

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_CDMA_A

`endif

endmodule
