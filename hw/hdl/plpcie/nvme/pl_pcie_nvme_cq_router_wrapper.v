/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2026, Systems Group, ETH Zurich
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
/*
 * Split the PL root-port write stream into ordinary and CQ paths.
 *
 * M_DATA retains the original decoder (host, HBM, admin, SQ and PRP).
 * M_CQ has a dedicated 1:1 SmartConnect for width conversion and CDC.
 * A CQ is not even offered downstream until every preceding M_DATA write has
 * produced its real response. Later payloads may run while that CQ is pending.
 * Ordinary writes remain ordered; non-payload/control writes also fence on
 * all earlier CQs. NVMe buffer ownership must prevent simultaneous reuse of
 * an in-flight command's payload; a completion never precedes its own data.
 *
 * AW order assigns both W ownership and the CQ fence. Independent finite
 * payload RAMs remove a waiting CQ from the ordinary W stream. W before AW
 * is legal and backpressured until its descriptor exists (the upstream W
 * FIFO can accept it). Store-and-forward also prevents malformed CQ bursts
 * from partially publishing an entry.
 *
 * Real B responses are collected independently and retired in input AW order.
 * One original write ID may be outstanding at a time, matching the QDMA's
 * one-thread interface; another ID is admitted after the current thread drains.
 * IDs/attributes are preserved, with no early acknowledgement.
 *
 * A delivery error suppresses subsequent CQ publication until reset, returning
 * SLVERR for those buffered writes. Reset must reset both downstream domains
 * and abort/drain the NVMe queue, as for the original interconnect.
 * Raw CQ reads quiesce writes and drain ordinary reads before entering M_CQ.
 */
module pl_pcie_nvme_cq_router_wrapper #(
    parameter integer DEPTH = 32,
    parameter integer DATA_FIFO_BEATS = 1024,
    parameter integer CQ_FIFO_BEATS = 512,
    parameter integer SEQ_BITS = 16,
    parameter [63:0] CQ_BASE = 64'h0000_0fff_f402_0000,
    parameter [63:0] CQ_MASK = 64'hffff_ffff_ffff_0000,
    parameter [63:0] PAYLOAD_LIMIT = 64'h0000_0c00_0000_0000
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF S_AXI:M_DATA:M_CQ, ASSOCIATED_RESET aresetn" *)
    input wire aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW" *)
    input wire aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWID",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4, DATA_WIDTH 512, ADDR_WIDTH 64, ID_WIDTH 4, AWUSER_WIDTH 55, ARUSER_WIDTH 55, NUM_READ_OUTSTANDING 32, NUM_WRITE_OUTSTANDING 32, NUM_READ_THREADS 1, NUM_WRITE_THREADS 1, MAX_BURST_LENGTH 256, SUPPORTS_NARROW_BURST 1" *)
    input wire [3:0] s_axi_awid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    input wire [63:0] s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWLEN" *)
    input wire [7:0] s_axi_awlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWSIZE" *)
    input wire [2:0] s_axi_awsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWBURST" *)
    input wire [1:0] s_axi_awburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWLOCK" *)
    input wire s_axi_awlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWCACHE" *)
    input wire [3:0] s_axi_awcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input wire [2:0] s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWQOS" *)
    input wire [3:0] s_axi_awqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREGION" *)
    input wire [3:0] s_axi_awregion,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWUSER" *)
    input wire [54:0] s_axi_awuser,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input wire s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input wire [511:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input wire [63:0] s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WLAST" *)
    input wire s_axi_wlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input wire s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BID" *)
    output wire [3:0] s_axi_bid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0] s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output wire s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input wire s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARID" *)
    input wire [3:0] s_axi_arid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input wire [63:0] s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARLEN" *)
    input wire [7:0] s_axi_arlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARSIZE" *)
    input wire [2:0] s_axi_arsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARBURST" *)
    input wire [1:0] s_axi_arburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARLOCK" *)
    input wire s_axi_arlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARCACHE" *)
    input wire [3:0] s_axi_arcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input wire [2:0] s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARQOS" *)
    input wire [3:0] s_axi_arqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREGION" *)
    input wire [3:0] s_axi_arregion,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARUSER" *)
    input wire [54:0] s_axi_aruser,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input wire s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RID" *)
    output wire [3:0] s_axi_rid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output wire [511:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0] s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RLAST" *)
    output wire s_axi_rlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output wire s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input wire s_axi_rready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA AWID",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_DATA, PROTOCOL AXI4, DATA_WIDTH 512, ADDR_WIDTH 64, ID_WIDTH 4, AWUSER_WIDTH 55, ARUSER_WIDTH 55, NUM_READ_OUTSTANDING 32, NUM_WRITE_OUTSTANDING 32, NUM_READ_THREADS 1, NUM_WRITE_THREADS 1, MAX_BURST_LENGTH 256, SUPPORTS_NARROW_BURST 1" *)
    output wire [3:0] m_data_awid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA AWADDR" *)
    output wire [63:0] m_data_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA AWLEN" *)
    output wire [7:0] m_data_awlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA AWSIZE" *)
    output wire [2:0] m_data_awsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA AWBURST" *)
    output wire [1:0] m_data_awburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA AWLOCK" *)
    output wire m_data_awlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA AWCACHE" *)
    output wire [3:0] m_data_awcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA AWPROT" *)
    output wire [2:0] m_data_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA AWQOS" *)
    output wire [3:0] m_data_awqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA AWREGION" *)
    output wire [3:0] m_data_awregion,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA AWUSER" *)
    output wire [54:0] m_data_awuser,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA AWVALID" *)
    output wire m_data_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA AWREADY" *)
    input wire m_data_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA WDATA" *)
    output wire [511:0] m_data_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA WSTRB" *)
    output wire [63:0] m_data_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA WLAST" *)
    output wire m_data_wlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA WVALID" *)
    output wire m_data_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA WREADY" *)
    input wire m_data_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA BID" *)
    input wire [3:0] m_data_bid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA BRESP" *)
    input wire [1:0] m_data_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA BVALID" *)
    input wire m_data_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA BREADY" *)
    output wire m_data_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA ARID" *)
    output wire [3:0] m_data_arid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA ARADDR" *)
    output wire [63:0] m_data_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA ARLEN" *)
    output wire [7:0] m_data_arlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA ARSIZE" *)
    output wire [2:0] m_data_arsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA ARBURST" *)
    output wire [1:0] m_data_arburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA ARLOCK" *)
    output wire m_data_arlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA ARCACHE" *)
    output wire [3:0] m_data_arcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA ARPROT" *)
    output wire [2:0] m_data_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA ARQOS" *)
    output wire [3:0] m_data_arqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA ARREGION" *)
    output wire [3:0] m_data_arregion,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA ARUSER" *)
    output wire [54:0] m_data_aruser,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA ARVALID" *)
    output wire m_data_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA ARREADY" *)
    input wire m_data_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA RID" *)
    input wire [3:0] m_data_rid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA RDATA" *)
    input wire [511:0] m_data_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA RRESP" *)
    input wire [1:0] m_data_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA RLAST" *)
    input wire m_data_rlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA RVALID" *)
    input wire m_data_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_DATA RREADY" *)
    output wire m_data_rready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ AWID",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_CQ, PROTOCOL AXI4, DATA_WIDTH 512, ADDR_WIDTH 64, ID_WIDTH 4, AWUSER_WIDTH 55, ARUSER_WIDTH 55, NUM_READ_OUTSTANDING 32, NUM_WRITE_OUTSTANDING 32, NUM_READ_THREADS 1, NUM_WRITE_THREADS 1, MAX_BURST_LENGTH 256, SUPPORTS_NARROW_BURST 1" *)
    output wire [3:0] m_cq_awid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ AWADDR" *)
    output wire [63:0] m_cq_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ AWLEN" *)
    output wire [7:0] m_cq_awlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ AWSIZE" *)
    output wire [2:0] m_cq_awsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ AWBURST" *)
    output wire [1:0] m_cq_awburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ AWLOCK" *)
    output wire m_cq_awlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ AWCACHE" *)
    output wire [3:0] m_cq_awcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ AWPROT" *)
    output wire [2:0] m_cq_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ AWQOS" *)
    output wire [3:0] m_cq_awqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ AWREGION" *)
    output wire [3:0] m_cq_awregion,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ AWUSER" *)
    output wire [54:0] m_cq_awuser,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ AWVALID" *)
    output wire m_cq_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ AWREADY" *)
    input wire m_cq_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ WDATA" *)
    output wire [511:0] m_cq_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ WSTRB" *)
    output wire [63:0] m_cq_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ WLAST" *)
    output wire m_cq_wlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ WVALID" *)
    output wire m_cq_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ WREADY" *)
    input wire m_cq_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ BID" *)
    input wire [3:0] m_cq_bid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ BRESP" *)
    input wire [1:0] m_cq_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ BVALID" *)
    input wire m_cq_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ BREADY" *)
    output wire m_cq_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ ARID" *)
    output wire [3:0] m_cq_arid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ ARADDR" *)
    output wire [63:0] m_cq_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ ARLEN" *)
    output wire [7:0] m_cq_arlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ ARSIZE" *)
    output wire [2:0] m_cq_arsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ ARBURST" *)
    output wire [1:0] m_cq_arburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ ARLOCK" *)
    output wire m_cq_arlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ ARCACHE" *)
    output wire [3:0] m_cq_arcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ ARPROT" *)
    output wire [2:0] m_cq_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ ARQOS" *)
    output wire [3:0] m_cq_arqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ ARREGION" *)
    output wire [3:0] m_cq_arregion,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ ARUSER" *)
    output wire [54:0] m_cq_aruser,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ ARVALID" *)
    output wire m_cq_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ ARREADY" *)
    input wire m_cq_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ RID" *)
    input wire [3:0] m_cq_rid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ RDATA" *)
    input wire [511:0] m_cq_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ RRESP" *)
    input wire [1:0] m_cq_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ RLAST" *)
    input wire m_cq_rlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ RVALID" *)
    input wire m_cq_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_CQ RREADY" *)
    output wire m_cq_rready

);    pl_pcie_nvme_cq_router #(
        .DEPTH(DEPTH),
        .DATA_FIFO_BEATS(DATA_FIFO_BEATS),
        .CQ_FIFO_BEATS(CQ_FIFO_BEATS),
        .SEQ_BITS(SEQ_BITS),
        .CQ_BASE(CQ_BASE),
        .CQ_MASK(CQ_MASK),
        .PAYLOAD_LIMIT(PAYLOAD_LIMIT)
    ) inst_cq_router (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_awid(s_axi_awid),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awlen(s_axi_awlen),
        .s_axi_awsize(s_axi_awsize),
        .s_axi_awburst(s_axi_awburst),
        .s_axi_awlock(s_axi_awlock),
        .s_axi_awcache(s_axi_awcache),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_awqos(s_axi_awqos),
        .s_axi_awregion(s_axi_awregion),
        .s_axi_awuser(s_axi_awuser),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wlast(s_axi_wlast),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bid(s_axi_bid),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_arid(s_axi_arid),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arlen(s_axi_arlen),
        .s_axi_arsize(s_axi_arsize),
        .s_axi_arburst(s_axi_arburst),
        .s_axi_arlock(s_axi_arlock),
        .s_axi_arcache(s_axi_arcache),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_arqos(s_axi_arqos),
        .s_axi_arregion(s_axi_arregion),
        .s_axi_aruser(s_axi_aruser),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rid(s_axi_rid),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rlast(s_axi_rlast),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .m_data_awid(m_data_awid),
        .m_data_awaddr(m_data_awaddr),
        .m_data_awlen(m_data_awlen),
        .m_data_awsize(m_data_awsize),
        .m_data_awburst(m_data_awburst),
        .m_data_awlock(m_data_awlock),
        .m_data_awcache(m_data_awcache),
        .m_data_awprot(m_data_awprot),
        .m_data_awqos(m_data_awqos),
        .m_data_awregion(m_data_awregion),
        .m_data_awuser(m_data_awuser),
        .m_data_awvalid(m_data_awvalid),
        .m_data_awready(m_data_awready),
        .m_data_wdata(m_data_wdata),
        .m_data_wstrb(m_data_wstrb),
        .m_data_wlast(m_data_wlast),
        .m_data_wvalid(m_data_wvalid),
        .m_data_wready(m_data_wready),
        .m_data_bid(m_data_bid),
        .m_data_bresp(m_data_bresp),
        .m_data_bvalid(m_data_bvalid),
        .m_data_bready(m_data_bready),
        .m_data_arid(m_data_arid),
        .m_data_araddr(m_data_araddr),
        .m_data_arlen(m_data_arlen),
        .m_data_arsize(m_data_arsize),
        .m_data_arburst(m_data_arburst),
        .m_data_arlock(m_data_arlock),
        .m_data_arcache(m_data_arcache),
        .m_data_arprot(m_data_arprot),
        .m_data_arqos(m_data_arqos),
        .m_data_arregion(m_data_arregion),
        .m_data_aruser(m_data_aruser),
        .m_data_arvalid(m_data_arvalid),
        .m_data_arready(m_data_arready),
        .m_data_rid(m_data_rid),
        .m_data_rdata(m_data_rdata),
        .m_data_rresp(m_data_rresp),
        .m_data_rlast(m_data_rlast),
        .m_data_rvalid(m_data_rvalid),
        .m_data_rready(m_data_rready),
        .m_cq_awid(m_cq_awid),
        .m_cq_awaddr(m_cq_awaddr),
        .m_cq_awlen(m_cq_awlen),
        .m_cq_awsize(m_cq_awsize),
        .m_cq_awburst(m_cq_awburst),
        .m_cq_awlock(m_cq_awlock),
        .m_cq_awcache(m_cq_awcache),
        .m_cq_awprot(m_cq_awprot),
        .m_cq_awqos(m_cq_awqos),
        .m_cq_awregion(m_cq_awregion),
        .m_cq_awuser(m_cq_awuser),
        .m_cq_awvalid(m_cq_awvalid),
        .m_cq_awready(m_cq_awready),
        .m_cq_wdata(m_cq_wdata),
        .m_cq_wstrb(m_cq_wstrb),
        .m_cq_wlast(m_cq_wlast),
        .m_cq_wvalid(m_cq_wvalid),
        .m_cq_wready(m_cq_wready),
        .m_cq_bid(m_cq_bid),
        .m_cq_bresp(m_cq_bresp),
        .m_cq_bvalid(m_cq_bvalid),
        .m_cq_bready(m_cq_bready),
        .m_cq_arid(m_cq_arid),
        .m_cq_araddr(m_cq_araddr),
        .m_cq_arlen(m_cq_arlen),
        .m_cq_arsize(m_cq_arsize),
        .m_cq_arburst(m_cq_arburst),
        .m_cq_arlock(m_cq_arlock),
        .m_cq_arcache(m_cq_arcache),
        .m_cq_arprot(m_cq_arprot),
        .m_cq_arqos(m_cq_arqos),
        .m_cq_arregion(m_cq_arregion),
        .m_cq_aruser(m_cq_aruser),
        .m_cq_arvalid(m_cq_arvalid),
        .m_cq_arready(m_cq_arready),
        .m_cq_rid(m_cq_rid),
        .m_cq_rdata(m_cq_rdata),
        .m_cq_rresp(m_cq_rresp),
        .m_cq_rlast(m_cq_rlast),
        .m_cq_rvalid(m_cq_rvalid),
        .m_cq_rready(m_cq_rready)
    );
endmodule
