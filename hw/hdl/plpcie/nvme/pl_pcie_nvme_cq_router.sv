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
 * Each lane has a registered AW stage and a W stage. A buffered, fenced write
 * takes the AW stage as soon as it is free, so AWs run ahead of earlier W
 * bursts; W bursts follow in AW order and stream back to back (the last beat
 * of one burst prefetches the next). Buffer space is released in lane order.
 *
 * A delivery error suppresses subsequent CQ publication until reset, returning
 * SLVERR for those buffered writes. Reset must reset both downstream domains
 * and abort/drain the NVMe queue, as for the original interconnect.
 * Raw CQ reads quiesce writes and drain ordinary reads before entering M_CQ.
 */
module pl_pcie_nvme_cq_router #(
    parameter integer DEPTH = 32,
    parameter integer DATA_FIFO_BEATS = 1024,
    parameter integer CQ_FIFO_BEATS = 512,
    parameter integer SEQ_BITS = 16,
    parameter logic [63:0] CQ_BASE = 64'h0000_0fff_f402_0000,
    parameter logic [63:0] CQ_MASK = 64'hffff_ffff_ffff_0000,
    parameter logic [63:0] PAYLOAD_LIMIT = 64'h0000_0c00_0000_0000
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

);
    localparam integer PTR_BITS = $clog2(DEPTH);
    localparam integer CNT_BITS = $clog2(DEPTH+1);
    localparam integer DATA_PTR_BITS = $clog2(DATA_FIFO_BEATS);
    localparam integer CQ_PTR_BITS = $clog2(CQ_FIFO_BEATS);
    localparam integer BUF_PTR_BITS = (DATA_PTR_BITS > CQ_PTR_BITS) ? DATA_PTR_BITS : CQ_PTR_BITS;
    localparam integer BUF_CNT_BITS = BUF_PTR_BITS+1;

    typedef struct packed {
        logic [3:0] id;
        logic [63:0] addr;
        logic [7:0] len;
        logic [2:0] size;
        logic [1:0] burst;
        logic lock;
        logic [3:0] cache;
        logic [2:0] prot;
        logic [3:0] qos, region;
        logic [54:0] user_bits;
        logic cq, invalid, barrier;
        logic [BUF_PTR_BITS-1:0] base;
        logic [SEQ_BITS-1:0] fence;
    } desc_t;

    typedef struct packed {
        logic [3:0] id;
        logic [63:0] addr;
        logic [7:0] len;
        logic [2:0] size;
        logic [1:0] burst;
        logic lock;
        logic [3:0] cache;
        logic [2:0] prot;
        logic [3:0] qos, region;
        logic [54:0] user_bits;
    } aw_t;

    // Sequence distance is bounded by the descriptor ledger, including B
    // responses that have completed downstream but have not retired upstream.
    initial begin
        if (DEPTH < 2 || (DEPTH & (DEPTH-1)) != 0 ||
            DATA_FIFO_BEATS < 256 || (DATA_FIFO_BEATS & (DATA_FIFO_BEATS-1)) != 0 ||
            CQ_FIFO_BEATS < 256 || (CQ_FIFO_BEATS & (CQ_FIFO_BEATS-1)) != 0 ||
            SEQ_BITS < $clog2(2*DEPTH+1))
            $error("Invalid CQ router ring/fence parameters");
    end

    function automatic logic is_cq(input logic [63:0] addr);
        is_cq = (addr & CQ_MASK) == CQ_BASE;
    endfunction

    // Validate the entire burst. QDMA emits INCR; retain legal FIXED/WRAP.
    function automatic logic burst_valid(
        input logic [63:0] addr, input logic [7:0] len,
        input logic [2:0] size, input logic [1:0] burst
    );
        logic [64:0] first, last_byte, beat_mask, span;
        logic wrap_len;
        begin
            beat_mask = (65'd1 << size)-1'b1;
            first = {1'b0,addr} & ~beat_mask;
            span = (65'(len)+1'b1) << size;
            wrap_len = len==1 || len==3 || len==7 || len==15;
            case (burst)
                2'b00: last_byte = first + beat_mask;
                2'b01: last_byte = first + span - 1'b1;
                2'b10: begin
                    first = {1'b0,addr} & ~(span-1'b1);
                    last_byte = first + span - 1'b1;
                end
                default: last_byte = 65'h1_0000_0000_0000_0000;
            endcase
            burst_valid = size <= 6 && burst != 2'b11 &&
                (burst != 2'b00 || len <= 15) &&
                (burst != 2'b10 || (wrap_len && (addr & beat_mask[63:0])==0)) &&
                !last_byte[64] && (addr[63:12] == last_byte[63:12]) &&
                (is_cq(addr) == is_cq(last_byte[63:0]));
        end
    endfunction

    function automatic logic reached(
        input logic [SEQ_BITS-1:0] completed, input logic [SEQ_BITS-1:0] fence
    );
        logic signed [SEQ_BITS-1:0] distance;
        begin
            distance = $signed(completed-fence);
            reached = distance >= 0;
        end
    endfunction

    desc_t desc [DEPTH];
    logic [DEPTH-1:0] w_complete, w_bad, issued, local_response, response_done;
    logic [1:0] response [DEPTH];
    logic [PTR_BITS-1:0] alloc_ptr, w_ptr, retire_ptr;
    logic [CNT_BITS-1:0] wr_count, w_count;
    logic [7:0] input_beat;
    logic [3:0] active_id;
    logic faulted;

    logic [PTR_BITS-1:0] route_slots [2][DEPTH];
    logic [PTR_BITS-1:0] route_tail [2], route_issue [2], route_response [2];
    logic [CNT_BITS-1:0] issue_count [2], response_count [2];
    logic [BUF_PTR_BITS-1:0] alloc_base [2];
    logic [BUF_CNT_BITS-1:0] used_beats [2];
    logic [SEQ_BITS-1:0] accepted_seq [2], completed_seq [2];

    wire aw_cq = is_cq(s_axi_awaddr);
    wire [8:0] aw_beats = {1'b0,s_axi_awlen}+9'd1;
    wire ar_cq = is_cq(s_axi_araddr);
    wire ar_ok = burst_valid(s_axi_araddr,s_axi_arlen,s_axi_arsize,s_axi_arburst);
    logic cq_read_active, error_read_active;
    logic [CNT_BITS-1:0] data_read_count;
    logic [3:0] error_read_id;
    logic [7:0] error_read_left;
    wire read_barrier = cq_read_active || error_read_active ||
                        (s_axi_arvalid && (ar_cq || !ar_ok));
    assign s_axi_awready = aresetn && !read_barrier && wr_count < CNT_BITS'(DEPTH) &&
        (wr_count == 0 || s_axi_awid == active_id) &&
        ({1'b0,used_beats[aw_cq]} + (BUF_CNT_BITS+1)'(aw_beats) <=
         (aw_cq ? (BUF_CNT_BITS+1)'(CQ_FIFO_BEATS) : (BUF_CNT_BITS+1)'(DATA_FIFO_BEATS)));
    wire aw_fire = s_axi_awvalid && s_axi_awready;
    assign s_axi_wready = aresetn && w_count != 0;
    wire w_fire = s_axi_wvalid && s_axi_wready;
    wire input_last = input_beat == desc[w_ptr].len;
    wire w_finish = w_fire && input_last;
    assign s_axi_bid = desc[retire_ptr].id;
    assign s_axi_bresp = response[retire_ptr];
    assign s_axi_bvalid = aresetn && wr_count != 0 && response_done[retire_ptr];
    wire retire_fire = s_axi_bvalid && s_axi_bready;

    (* ram_style = "block" *) logic [575:0] data_ram [DATA_FIFO_BEATS];
    (* ram_style = "block" *) logic [575:0] cq_ram [CQ_FIFO_BEATS];
    logic [575:0] payload_q [2];
    // AW stage: one registered AW per lane, which may run ahead of W.
    aw_t aw_q [2];
    logic [1:0] aw_busy;
    logic [PTR_BITS-1:0] aw_slot_q [2];
    // A dropped write holds the AW stage for one cycle; its local response is
    // recorded from registers, off the fence/start path.
    logic [1:0] drop_q;
    logic [PTR_BITS-1:0] drop_slot_q [2];
    logic [1:0] drop_resp_q [2];
    // The head's start conditions are registered; once true they stay true
    // while it remains the head. This keeps the fence compare off the stages.
    logic [1:0] head_ok_q, head_bad_q;
    wire [1:0] head_ready;
    // W jobs in AW order. A skipped (dropped) job only releases its buffer.
    logic [BUF_PTR_BITS-1:0] job_base [2][DEPTH];
    logic [7:0] job_len [2][DEPTH];
    logic [DEPTH-1:0] job_skip [2];
    logic [PTR_BITS-1:0] job_head [2], job_tail [2];
    logic [CNT_BITS-1:0] job_count [2];
    // W stage: payload_q holds beat w_beat of the current job, read from w_addr.
    logic [1:0] w_busy;
    logic [7:0] w_beat [2], w_len [2];
    logic [BUF_PTR_BITS-1:0] w_addr [2];
    wire [PTR_BITS-1:0] issue_slot [2];
    wire [PTR_BITS-1:0] response_slot [2];
    wire [1:0] start_lane, drop_lane;
    wire [1:0] w_last, job_finish, job_load, beat_load, skip_pop;
    wire [1:0] lane_awvalid, lane_awready, lane_wvalid, lane_wready;
    wire [1:0] lane_bvalid, lane_bready, lane_bfire, local_bfire;
    wire [1:0] lane_resp [2];
    wire [3:0] lane_bid [2];
    wire [1:0] lane_awfire = lane_awvalid & lane_awready;
    wire [1:0] lane_wfire = lane_wvalid & lane_wready;
    wire [1:0] consume_response = lane_bfire | local_bfire;
    wire [BUF_PTR_BITS-1:0] read_address [2];
    wire [BUF_PTR_BITS-1:0] write_address =
        desc[w_ptr].base + BUF_PTR_BITS'(input_beat);

    assign lane_awready = {m_cq_awready,m_data_awready};
    assign lane_wready = {m_cq_wready,m_data_wready};
    assign lane_bvalid = {m_cq_bvalid,m_data_bvalid};
    assign lane_resp[0] = m_data_bresp;
    assign lane_resp[1] = m_cq_bresp;
    assign lane_bid[0] = m_data_bid;
    assign lane_bid[1] = m_cq_bid;
    assign m_data_bready = lane_bready[0];
    assign m_cq_bready = lane_bready[1];

    for (genvar g=0; g<2; g=g+1) begin : lanes
        assign issue_slot[g] = route_slots[g][route_issue[g]];
        assign response_slot[g] = route_slots[g][route_response[g]];
        wire fence_ready = g == 1 ?
            reached(completed_seq[0],desc[issue_slot[g]].fence) :
            (!desc[issue_slot[g]].barrier ||
             reached(completed_seq[1],desc[issue_slot[g]].fence));
        assign head_ready[g] = issue_count[g] != 0 && w_complete[issue_slot[g]] && fence_ready;
        // A buffered, fenced write takes the free AW stage while earlier W runs.
        assign start_lane[g] = aresetn && head_ok_q[g] && !aw_busy[g] && !drop_q[g];
        assign drop_lane[g] = start_lane[g] && (head_bad_q[g] || (g == 1 && faulted));
        assign lane_awvalid[g] = aresetn && aw_busy[g];
        // W follows AW order; a last beat prefetches the next job's first beat.
        wire job_ready = job_count[g] != 0 && !job_skip[g][job_head[g]];
        assign w_last[g] = w_beat[g] == w_len[g];
        assign lane_wvalid[g] = aresetn && w_busy[g];
        assign job_finish[g] = lane_wfire[g] && w_last[g];
        assign job_load[g] = job_ready && (!w_busy[g] || job_finish[g]);
        assign beat_load[g] = lane_wfire[g] && !w_last[g];
        assign skip_pop[g] = !w_busy[g] && job_count[g] != 0 && job_skip[g][job_head[g]];
        assign lane_bready[g] = aresetn && response_count[g] != 0 &&
            issued[response_slot[g]] && !local_response[response_slot[g]];
        assign lane_bfire[g] = lane_bready[g] && lane_bvalid[g];
        assign local_bfire[g] = aresetn && response_count[g] != 0 &&
            issued[response_slot[g]] && local_response[response_slot[g]];
        assign read_address[g] = (w_busy[g] && !w_last[g]) ?
            w_addr[g]+1'b1 : job_base[g][job_head[g]];
    end

    always_ff @(posedge aclk) begin
        if (w_fire && !desc[w_ptr].cq)
            data_ram[write_address[DATA_PTR_BITS-1:0]] <= {s_axi_wstrb,s_axi_wdata};
        if (w_fire && desc[w_ptr].cq)
            cq_ram[write_address[CQ_PTR_BITS-1:0]] <= {s_axi_wstrb,s_axi_wdata};
        if (job_load[0] || beat_load[0])
            payload_q[0] <= data_ram[read_address[0][DATA_PTR_BITS-1:0]];
        if (job_load[1] || beat_load[1])
            payload_q[1] <= cq_ram[read_address[1][CQ_PTR_BITS-1:0]];
    end

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            alloc_ptr <= '0; w_ptr <= '0; retire_ptr <= '0;
            wr_count <= '0; w_count <= '0; input_beat <= '0; active_id <= '0;
            w_complete <= '0; w_bad <= '0; issued <= '0;
            local_response <= '0; response_done <= '0; faulted <= 1'b0;
            aw_busy <= '0; drop_q <= '0; w_busy <= '0; head_ok_q <= '0;
            for (integer g=0; g<2; g=g+1) begin
                route_tail[g] <= '0; route_issue[g] <= '0; route_response[g] <= '0;
                issue_count[g] <= '0; response_count[g] <= '0;
                used_beats[g] <= '0; alloc_base[g] <= '0;
                job_head[g] <= '0; job_tail[g] <= '0; job_count[g] <= '0;
                w_beat[g] <= '0; w_len[g] <= '0; w_addr[g] <= '0;
                accepted_seq[g] <= '0; completed_seq[g] <= '0;
            end
        end else begin
            case ({aw_fire,retire_fire})
                2'b10: wr_count <= wr_count+1'b1;
                2'b01: wr_count <= wr_count-1'b1;
                default: ;
            endcase
            case ({aw_fire,w_finish})
                2'b10: w_count <= w_count+1'b1;
                2'b01: w_count <= w_count-1'b1;
                default: ;
            endcase
            if (aw_fire) begin
                active_id <= s_axi_awid;
                desc[alloc_ptr].id <= s_axi_awid;
                desc[alloc_ptr].addr <= s_axi_awaddr;
                desc[alloc_ptr].len <= s_axi_awlen;
                desc[alloc_ptr].size <= s_axi_awsize;
                desc[alloc_ptr].burst <= s_axi_awburst;
                desc[alloc_ptr].lock <= s_axi_awlock;
                desc[alloc_ptr].cache <= s_axi_awcache;
                desc[alloc_ptr].prot <= s_axi_awprot;
                desc[alloc_ptr].qos <= s_axi_awqos;
                desc[alloc_ptr].region <= s_axi_awregion;
                desc[alloc_ptr].user_bits <= s_axi_awuser;
                desc[alloc_ptr].cq <= aw_cq;
                desc[alloc_ptr].invalid <= !burst_valid(s_axi_awaddr,s_axi_awlen,s_axi_awsize,s_axi_awburst);
                desc[alloc_ptr].barrier <= s_axi_awaddr >= PAYLOAD_LIMIT || s_axi_awlock;
                desc[alloc_ptr].base <= alloc_base[aw_cq];
                desc[alloc_ptr].fence <= accepted_seq[!aw_cq];
                w_complete[alloc_ptr] <= 1'b0;
                w_bad[alloc_ptr] <= 1'b0;
                issued[alloc_ptr] <= 1'b0;
                local_response[alloc_ptr] <= 1'b0;
                response_done[alloc_ptr] <= 1'b0;
                alloc_ptr <= alloc_ptr+1'b1;
            end
            if (w_fire) begin
                if (s_axi_wlast != input_last) w_bad[w_ptr] <= 1'b1;
                if (input_last) begin
                    w_complete[w_ptr] <= 1'b1;
                    w_ptr <= w_ptr+1'b1;
                    input_beat <= '0;
                end else input_beat <= input_beat+1'b1;
            end
            if (retire_fire) retire_ptr <= retire_ptr+1'b1;

            for (integer g=0; g<2; g=g+1) begin
                case ({aw_fire && aw_cq == (g==1),start_lane[g]})
                    2'b10: issue_count[g] <= issue_count[g]+1'b1;
                    2'b01: issue_count[g] <= issue_count[g]-1'b1;
                    default: ;
                endcase
                case ({start_lane[g],job_load[g] || skip_pop[g]})
                    2'b10: job_count[g] <= job_count[g]+1'b1;
                    2'b01: job_count[g] <= job_count[g]-1'b1;
                    default: ;
                endcase
                case ({aw_fire && aw_cq == (g==1),consume_response[g]})
                    2'b10: response_count[g] <= response_count[g]+1'b1;
                    2'b01: response_count[g] <= response_count[g]-1'b1;
                    default: ;
                endcase
                // Buffer space is released in lane order: after a job's last
                // W beat, or when a skipped job reaches the W stage.
                used_beats[g] <= used_beats[g] +
                    ((aw_fire && aw_cq == (g==1)) ? BUF_CNT_BITS'(aw_beats) : BUF_CNT_BITS'(0)) -
                    (job_finish[g] ? (BUF_CNT_BITS'(w_len[g])+BUF_CNT_BITS'(1)) :
                     skip_pop[g] ? (BUF_CNT_BITS'(job_len[g][job_head[g]])+BUF_CNT_BITS'(1)) :
                     BUF_CNT_BITS'(0));
                if (aw_fire && aw_cq == (g==1)) begin
                    route_slots[g][route_tail[g]] <= alloc_ptr;
                    route_tail[g] <= route_tail[g]+1'b1;
                    if (g==0)
                        alloc_base[g] <= BUF_PTR_BITS'(DATA_PTR_BITS'(alloc_base[g]+BUF_PTR_BITS'(aw_beats)));
                    else
                        alloc_base[g] <= BUF_PTR_BITS'(CQ_PTR_BITS'(alloc_base[g]+BUF_PTR_BITS'(aw_beats)));
                    accepted_seq[g] <= accepted_seq[g]+1'b1;
                end
                head_ok_q[g] <= head_ready[g] && !start_lane[g];
                head_bad_q[g] <= desc[issue_slot[g]].invalid || w_bad[issue_slot[g]];
                if (start_lane[g]) begin
                    route_issue[g] <= route_issue[g]+1'b1;
                    job_base[g][job_tail[g]] <= desc[issue_slot[g]].base;
                    job_len[g][job_tail[g]] <= desc[issue_slot[g]].len;
                    job_skip[g][job_tail[g]] <= drop_lane[g];
                    job_tail[g] <= job_tail[g]+1'b1;
                    if (drop_lane[g]) begin
                        drop_q[g] <= 1'b1;
                        drop_slot_q[g] <= issue_slot[g];
                        drop_resp_q[g] <= desc[issue_slot[g]].invalid ? 2'b11 : 2'b10;
                    end else begin
                        aw_busy[g] <= 1'b1;
                        aw_slot_q[g] <= issue_slot[g];
                        aw_q[g].id <= desc[issue_slot[g]].id;
                        aw_q[g].addr <= desc[issue_slot[g]].addr;
                        aw_q[g].len <= desc[issue_slot[g]].len;
                        aw_q[g].size <= desc[issue_slot[g]].size;
                        aw_q[g].burst <= desc[issue_slot[g]].burst;
                        aw_q[g].lock <= desc[issue_slot[g]].lock;
                        aw_q[g].cache <= desc[issue_slot[g]].cache;
                        aw_q[g].prot <= desc[issue_slot[g]].prot;
                        aw_q[g].qos <= desc[issue_slot[g]].qos;
                        aw_q[g].region <= desc[issue_slot[g]].region;
                        aw_q[g].user_bits <= desc[issue_slot[g]].user_bits;
                    end
                end
                if (drop_q[g]) begin
                    drop_q[g] <= 1'b0;
                    issued[drop_slot_q[g]] <= 1'b1;
                    local_response[drop_slot_q[g]] <= 1'b1;
                    response[drop_slot_q[g]] <= drop_resp_q[g];
                end
                // AXI B follows AW and the last W, so a sent AW may take its B.
                if (lane_awfire[g]) begin
                    aw_busy[g] <= 1'b0;
                    issued[aw_slot_q[g]] <= 1'b1;
                end
                if (job_load[g]) begin
                    w_busy[g] <= 1'b1;
                    w_beat[g] <= '0;
                    w_len[g] <= job_len[g][job_head[g]];
                    w_addr[g] <= job_base[g][job_head[g]];
                end else if (beat_load[g]) begin
                    w_beat[g] <= w_beat[g]+1'b1;
                    w_addr[g] <= w_addr[g]+1'b1;
                end else if (job_finish[g]) w_busy[g] <= 1'b0;
                if (job_load[g] || skip_pop[g]) job_head[g] <= job_head[g]+1'b1;
                if (consume_response[g]) begin
                    route_response[g] <= route_response[g]+1'b1;
                    completed_seq[g] <= completed_seq[g]+1'b1;
                    response_done[response_slot[g]] <= 1'b1;
                    if (lane_bfire[g])
                        response[response_slot[g]] <= lane_bid[g] == desc[response_slot[g]].id ?
                            lane_resp[g] : 2'b10;
                    if ((lane_bfire[g] && (lane_resp[g][1] ||
                         lane_bid[g] != desc[response_slot[g]].id)) ||
                        (local_bfire[g] && response[response_slot[g]][1]))
                        faulted <= 1'b1;
                end
            end
        end
    end
    assign m_data_awid = aw_q[0].id;
    assign m_data_awaddr = aw_q[0].addr;
    assign m_data_awlen = aw_q[0].len;
    assign m_data_awsize = aw_q[0].size;
    assign m_data_awburst = aw_q[0].burst;
    assign m_data_awlock = aw_q[0].lock;
    assign m_data_awcache = aw_q[0].cache;
    assign m_data_awprot = aw_q[0].prot;
    assign m_data_awqos = aw_q[0].qos;
    assign m_data_awregion = aw_q[0].region;
    assign m_data_awuser = aw_q[0].user_bits;
    assign m_data_awvalid = lane_awvalid[0];
    assign m_data_wdata = payload_q[0][511:0];
    assign m_data_wstrb = payload_q[0][575:512];
    assign m_data_wlast = w_last[0];
    assign m_data_wvalid = lane_wvalid[0];
    assign m_cq_awid = aw_q[1].id;
    assign m_cq_awaddr = aw_q[1].addr;
    assign m_cq_awlen = aw_q[1].len;
    assign m_cq_awsize = aw_q[1].size;
    assign m_cq_awburst = aw_q[1].burst;
    assign m_cq_awlock = aw_q[1].lock;
    assign m_cq_awcache = aw_q[1].cache;
    assign m_cq_awprot = aw_q[1].prot;
    assign m_cq_awqos = aw_q[1].qos;
    assign m_cq_awregion = aw_q[1].region;
    assign m_cq_awuser = aw_q[1].user_bits;
    assign m_cq_awvalid = lane_awvalid[1];
    assign m_cq_wdata = payload_q[1][511:0];
    assign m_cq_wstrb = payload_q[1][575:512];
    assign m_cq_wlast = w_last[1];
    assign m_cq_wvalid = lane_wvalid[1];

    // CQ readback drains accepted writes and ordinary reads.
    wire special_read_ready = wr_count == 0 && data_read_count == 0 &&
                              !cq_read_active && !error_read_active;
    assign m_data_arvalid = aresetn && s_axi_arvalid && !ar_cq && ar_ok &&
        !cq_read_active && !error_read_active && data_read_count < CNT_BITS'(DEPTH);
    assign m_cq_arvalid = aresetn && s_axi_arvalid && ar_cq && ar_ok && special_read_ready;
    assign s_axi_arready = aresetn && !cq_read_active && !error_read_active &&
        (!ar_ok ? special_read_ready :
         ar_cq ? (special_read_ready && m_cq_arready) :
         (data_read_count < CNT_BITS'(DEPTH) && m_data_arready));
    assign s_axi_rvalid = aresetn && (error_read_active || (cq_read_active ? m_cq_rvalid : m_data_rvalid));
    assign s_axi_rid = error_read_active ? error_read_id : cq_read_active ? m_cq_rid : m_data_rid;
    assign s_axi_rdata = error_read_active ? 512'd0 : cq_read_active ? m_cq_rdata : m_data_rdata;
    assign s_axi_rresp = error_read_active ? 2'b11 : cq_read_active ? m_cq_rresp : m_data_rresp;
    assign s_axi_rlast = error_read_active ? error_read_left == 0 : cq_read_active ? m_cq_rlast : m_data_rlast;
    assign m_cq_rready = aresetn && cq_read_active && s_axi_rready;
    assign m_data_rready = aresetn && !cq_read_active && !error_read_active && s_axi_rready;
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            cq_read_active <= 1'b0; error_read_active <= 1'b0;
            data_read_count <= '0; error_read_id <= '0; error_read_left <= '0;
        end else begin
            case ({m_data_arvalid && m_data_arready,
                   m_data_rvalid && m_data_rready && m_data_rlast})
                2'b10: data_read_count <= data_read_count+1'b1;
                2'b01: data_read_count <= data_read_count-1'b1;
                default: ;
            endcase
            if (m_cq_arvalid && m_cq_arready) cq_read_active <= 1'b1;
            if (m_cq_rvalid && m_cq_rready && m_cq_rlast) cq_read_active <= 1'b0;
            if (s_axi_arvalid && s_axi_arready && !ar_ok) begin
                error_read_active <= 1'b1;
                error_read_id <= s_axi_arid;
                error_read_left <= s_axi_arlen;
            end
            if (error_read_active && s_axi_rready) begin
                if (error_read_left == 0) error_read_active <= 1'b0;
                else error_read_left <= error_read_left-1'b1;
            end
        end
    end
    assign m_data_arid = s_axi_arid;
    assign m_data_araddr = s_axi_araddr;
    assign m_data_arlen = s_axi_arlen;
    assign m_data_arsize = s_axi_arsize;
    assign m_data_arburst = s_axi_arburst;
    assign m_data_arlock = s_axi_arlock;
    assign m_data_arcache = s_axi_arcache;
    assign m_data_arprot = s_axi_arprot;
    assign m_data_arqos = s_axi_arqos;
    assign m_data_arregion = s_axi_arregion;
    assign m_data_aruser = s_axi_aruser;
    assign m_cq_arid = s_axi_arid;
    assign m_cq_araddr = s_axi_araddr;
    assign m_cq_arlen = s_axi_arlen;
    assign m_cq_arsize = s_axi_arsize;
    assign m_cq_arburst = s_axi_arburst;
    assign m_cq_arlock = s_axi_arlock;
    assign m_cq_arcache = s_axi_arcache;
    assign m_cq_arprot = s_axi_arprot;
    assign m_cq_arqos = s_axi_arqos;
    assign m_cq_arregion = s_axi_arregion;
    assign m_cq_aruser = s_axi_aruser;
endmodule
