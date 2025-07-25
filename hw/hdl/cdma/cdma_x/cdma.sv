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
    parameter integer                   ID_BITS = AXI_ID_BITS,
    parameter integer                   DBG = 0
) (
    input  wire                         aclk,
    input  wire                         aresetn,

    dmaIntf.s                           rd_CDMA,
    dmaIntf.s                           wr_CDMA,

    AXI4.m                              m_axi_ddr,

    AXI4S.s                             s_axis_ddr,
    AXI4S.m                             m_axis_ddr
);

logic s2mm_error;
logic mm2s_error;
logic [7:0] rd_sts;
logic [7:0] wr_sts;

logic [79:0] rd_req;
logic [79:0] wr_req;

if (DBG == 1) begin
ila_cdma inst_ila_cdma (
    .clk(aclk),
    .probe0(rd_CDMA.valid),
    .probe1(rd_CDMA.ready),
    .probe2(rd_CDMA.req.paddr), // 40
    .probe3(rd_CDMA.req.len),  // 28
    .probe4(rd_CDMA.req.last),
    .probe5(rd_CDMA.rsp.done),

    .probe6(wr_CDMA.valid),
    .probe7(wr_CDMA.ready),
    .probe8(wr_CDMA.req.paddr), // 40
    .probe9(wr_CDMA.req.len), // 28
    .probe10(wr_CDMA.req.last),
    .probe11(wr_CDMA.rsp.done),  

    .probe12(s_axis_ddr.tvalid),
    .probe13(s_axis_ddr.tready),
    .probe14(s_axis_ddr.tlast),

    .probe15(m_axis_ddr.tvalid),
    .probe16(m_axis_ddr.tready),
    .probe17(m_axis_ddr.tlast)
);
end

// RD
assign rd_req = {8'h0, 24'h0, rd_CDMA.req.paddr, 1'b1, rd_CDMA.req.last, 6'h0, 1'b1, rd_CDMA.req.len[22:0]};
// WR
assign wr_req = {8'h0, 24'h0, wr_CDMA.req.paddr, 1'b1, wr_CDMA.req.last, 6'h0, 1'b1, wr_CDMA.req.len[22:0]};

cdma_datamover inst_cdma_datamover (
    // RD clk
    .m_axi_mm2s_aclk(aclk),// : IN STD_LOGIC;
    .m_axi_mm2s_aresetn(aresetn), //: IN STD_LOGIC;
    .m_axis_mm2s_cmdsts_aclk(aclk), //: IN STD_LOGIC;
    .m_axis_mm2s_cmdsts_aresetn(aresetn), //: IN STD_LOGIC;
    .mm2s_err(mm2s_error), //: OUT STD_LOGIC;
    // RD cmd
    .s_axis_mm2s_cmd_tvalid(rd_CDMA.valid), //: IN STD_LOGIC;
    .s_axis_mm2s_cmd_tready(rd_CDMA.ready), //: OUT STD_LOGIC;
    .s_axis_mm2s_cmd_tdata(rd_req), //: IN STD_LOGIC_VECTOR(103 DOWNTO 0);
    // RD sts
    .m_axis_mm2s_sts_tvalid(rd_CDMA.rsp.done), //: OUT STD_LOGIC;
    .m_axis_mm2s_sts_tready(1'b1), //: IN STD_LOGIC;
    .m_axis_mm2s_sts_tdata(rd_sts), //: OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    .m_axis_mm2s_sts_tkeep(), //: OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
    .m_axis_mm2s_sts_tlast(), //: OUT STD_LOGIC;
    // RD channel AXI
    .m_axi_mm2s_arid(m_axi_ddr.arid), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axi_mm2s_araddr(m_axi_ddr.araddr), //: OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    .m_axi_mm2s_arlen(m_axi_ddr.arlen), //: OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    .m_axi_mm2s_arsize(m_axi_ddr.arsize), //: OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    .m_axi_mm2s_arburst(m_axi_ddr.arburst), //: OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    .m_axi_mm2s_arprot(m_axi_ddr.arprot), //: OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    .m_axi_mm2s_arcache(m_axi_ddr.arcache), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axi_mm2s_aruser(), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axi_mm2s_arvalid(m_axi_ddr.arvalid), //: OUT STD_LOGIC;
    .m_axi_mm2s_arready(m_axi_ddr.arready), //: IN STD_LOGIC;
    .m_axi_mm2s_rdata(m_axi_ddr.rdata), //: IN STD_LOGIC_VECTOR(511 DOWNTO 0);
    .m_axi_mm2s_rresp(m_axi_ddr.rresp), //: IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    .m_axi_mm2s_rlast(m_axi_ddr.rlast), //: IN STD_LOGIC;
    .m_axi_mm2s_rvalid(m_axi_ddr.rvalid), //: IN STD_LOGIC;
    .m_axi_mm2s_rready(m_axi_ddr.rready), //: OUT STD_LOGIC;
    // RD channel AXIS
    .m_axis_mm2s_tdata(m_axis_ddr.tdata), //: OUT STD_LOGIC_VECTOR(511 DOWNTO 0);
    .m_axis_mm2s_tkeep(m_axis_ddr.tkeep), //: OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
    .m_axis_mm2s_tlast(m_axis_ddr.tlast), //: OUT STD_LOGIC;
    .m_axis_mm2s_tvalid(m_axis_ddr.tvalid), //: OUT STD_LOGIC;
    .m_axis_mm2s_tready(m_axis_ddr.tready), //: IN STD_LOGIC;

    // WR clk
    .m_axi_s2mm_aclk(aclk), //: IN STD_LOGIC;
    .m_axi_s2mm_aresetn(aresetn), //: IN STD_LOGIC;
    .m_axis_s2mm_cmdsts_awclk(aclk), //: IN STD_LOGIC;
    .m_axis_s2mm_cmdsts_aresetn(aresetn), //: IN STD_LOGIC;
    .s2mm_err(s2mm_error), //: OUT STD_LOGIC;
    // WR cmd
    .s_axis_s2mm_cmd_tvalid(wr_CDMA.valid), //: IN STD_LOGIC;
    .s_axis_s2mm_cmd_tready(wr_CDMA.ready), //: OUT STD_LOGIC;
    .s_axis_s2mm_cmd_tdata(wr_req), //: IN STD_LOGIC_VECTOR(103 DOWNTO 0);
    // WR sts
    .m_axis_s2mm_sts_tvalid(wr_CDMA.rsp.done), //: OUT STD_LOGIC;
    .m_axis_s2mm_sts_tready(1'b1), //: IN STD_LOGIC;
    .m_axis_s2mm_sts_tdata(wr_sts), //: OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    .m_axis_s2mm_sts_tkeep(), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axis_s2mm_sts_tlast(), //: OUT STD_LOGIC;
    // WR channel AXI
    .m_axi_s2mm_awid(m_axi_ddr.awid), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axi_s2mm_awaddr(m_axi_ddr.awaddr), //: OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    .m_axi_s2mm_awlen(m_axi_ddr.awlen), //: OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    .m_axi_s2mm_awsize(m_axi_ddr.awsize), //: OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    .m_axi_s2mm_awburst(m_axi_ddr.awburst), //: OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    .m_axi_s2mm_awprot(m_axi_ddr.awprot), //: OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    .m_axi_s2mm_awcache(m_axi_ddr.awcache), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axi_s2mm_awuser(), //: OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    .m_axi_s2mm_awvalid(m_axi_ddr.awvalid), //: OUT STD_LOGIC;
    .m_axi_s2mm_awready(m_axi_ddr.awready), //: IN STD_LOGIC;
    .m_axi_s2mm_wdata(m_axi_ddr.wdata), //: OUT STD_LOGIC_VECTOR(511 DOWNTO 0);
    .m_axi_s2mm_wstrb(m_axi_ddr.wstrb), //: OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
    .m_axi_s2mm_wlast(m_axi_ddr.wlast), //: OUT STD_LOGIC;
    .m_axi_s2mm_wvalid(m_axi_ddr.wvalid), //: OUT STD_LOGIC;
    .m_axi_s2mm_wready(m_axi_ddr.wready), //: IN STD_LOGIC;
    .m_axi_s2mm_bresp(m_axi_ddr.bresp), //: IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    .m_axi_s2mm_bvalid(m_axi_ddr.bvalid), //: IN STD_LOGIC;
    .m_axi_s2mm_bready(m_axi_ddr.bready), //: OUT STD_LOGIC;
    // WR channel AXIS
    .s_axis_s2mm_tdata(s_axis_ddr.tdata), //: IN STD_LOGIC_VECTOR(511 DOWNTO 0);
    .s_axis_s2mm_tkeep(s_axis_ddr.tkeep), //: IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    .s_axis_s2mm_tlast(s_axis_ddr.tlast), //: IN STD_LOGIC;
    .s_axis_s2mm_tvalid(s_axis_ddr.tvalid), //: IN STD_LOGIC;
    .s_axis_s2mm_tready(s_axis_ddr.tready) //: OUT STD_LOGIC;
);

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_CDMA_X

`endif

endmodule
