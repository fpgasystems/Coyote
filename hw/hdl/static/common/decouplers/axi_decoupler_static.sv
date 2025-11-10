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

module axi_decoupler_static #(
	parameter integer ID_BITS = AXI_ID_BITS,
    parameter integer DATA_BITS = AXI_DATA_BITS,
	parameter integer EN_DCPL = 1
) (
	input  logic 					decouple,

	AXI4.s						s_axi,
	AXI4.m						m_axi
);

// ----------------------------------------------------------------------------------------------------------------------- 
// Decoupling
// ----------------------------------------------------------------------------------------------------------------------- 
if(EN_DCPL == 1) begin

logic[AXI_ADDR_BITS-1:0] 			s_axi_araddr;
logic[1:0]							s_axi_arburst;
logic[3:0]							s_axi_arcache;
logic[ID_BITS-1:0]					s_axi_arid;
logic[7:0]							s_axi_arlen;
logic[0:0]							s_axi_arlock;
logic[2:0]							s_axi_arprot;
logic[3:0]							s_axi_arqos;
logic[3:0]							s_axi_arregion;
logic[2:0]							s_axi_arsize;
logic								s_axi_arready;
logic								s_axi_arvalid;
logic[AXI_ADDR_BITS-1:0] 			s_axi_awaddr;
logic[1:0]							s_axi_awburst;
logic[3:0]							s_axi_awcache;
logic[ID_BITS-1:0]					s_axi_awid;
logic[7:0]							s_axi_awlen;
logic[0:0]							s_axi_awlock;
logic[2:0]							s_axi_awprot;
logic[3:0]							s_axi_awqos;
logic[3:0]							s_axi_awregion;
logic[2:0]							s_axi_awsize;
logic								s_axi_awready;
logic								s_axi_awvalid;
logic[DATA_BITS-1:0] 			    s_axi_rdata;
logic[ID_BITS-1:0]		 			s_axi_rid;
logic[1:0]							s_axi_rresp;
logic 								s_axi_rlast;
logic 								s_axi_rready;
logic								s_axi_rvalid;
logic[DATA_BITS-1:0] 			    s_axi_wdata;
logic[DATA_BITS/8-1:0] 			    s_axi_wstrb;
logic 								s_axi_wlast;
logic								s_axi_wready;
logic								s_axi_wvalid;
logic[ID_BITS-1:0]					s_axi_bid;
logic[1:0]							s_axi_bresp;
logic								s_axi_bready;
logic								s_axi_bvalid;

logic[AXI_ADDR_BITS-1:0] 			m_axi_araddr;
logic[1:0]							m_axi_arburst;
logic[3:0]							m_axi_arcache;
logic[ID_BITS-1:0]					m_axi_arid;
logic[7:0]							m_axi_arlen;
logic[0:0]							m_axi_arlock;
logic[2:0]							m_axi_arprot;
logic[3:0]							m_axi_arqos;
logic[3:0]							m_axi_arregion;
logic[2:0]							m_axi_arsize;
logic								m_axi_arready;
logic								m_axi_arvalid;
logic[AXI_ADDR_BITS-1:0] 			m_axi_awaddr;
logic[1:0]							m_axi_awburst;
logic[3:0]							m_axi_awcache;
logic[ID_BITS-1:0]					m_axi_awid;
logic[7:0]							m_axi_awlen;
logic[0:0]							m_axi_awlock;
logic[2:0]							m_axi_awprot;
logic[3:0]							m_axi_awqos;
logic[3:0]							m_axi_awregion;
logic[2:0]							m_axi_awsize;
logic								m_axi_awready;
logic								m_axi_awvalid;
logic[DATA_BITS-1:0] 			    m_axi_rdata;
logic[ID_BITS-1:0]		 			m_axi_rid;
logic[1:0]							m_axi_rresp;
logic 								m_axi_rlast;
logic 								m_axi_rready;
logic								m_axi_rvalid;
logic[DATA_BITS-1:0] 			    m_axi_wdata;
logic[DATA_BITS/8-1:0] 			    m_axi_wstrb;
logic 								m_axi_wlast;
logic								m_axi_wready;
logic								m_axi_wvalid;
logic[ID_BITS-1:0]					m_axi_bid;
logic[1:0]							m_axi_bresp;
logic								m_axi_bready;
logic								m_axi_bvalid;

// In
assign s_axi_araddr 		= s_axi.araddr;
assign s_axi_arburst		= s_axi.arburst;
assign s_axi_arcache		= s_axi.arcache;
assign s_axi_arid			= s_axi.arid;
assign s_axi_arlen			= s_axi.arlen;
assign s_axi_arlock			= s_axi.arlock;
assign s_axi_arprot 		= s_axi.arprot;
assign s_axi_arqos 			= s_axi.arqos;
assign s_axi_arregion 		= s_axi.arregion;
assign s_axi_arsize 		= s_axi.arsize;
assign s_axi_arvalid 		= s_axi.arvalid;
assign s_axi.arready 		= s_axi_arready;

assign s_axi_awaddr 		= s_axi.awaddr;
assign s_axi_awburst		= s_axi.awburst;
assign s_axi_awcache		= s_axi.awcache;
assign s_axi_awid			= s_axi.awid;
assign s_axi_awlen			= s_axi.awlen;
assign s_axi_awlock			= s_axi.awlock;
assign s_axi_awprot 		= s_axi.awprot;
assign s_axi_awqos 			= s_axi.awqos;
assign s_axi_awregion 		= s_axi.awregion;
assign s_axi_awsize 		= s_axi.awsize;
assign s_axi_awvalid 		= s_axi.awvalid;
assign s_axi.awready 		= s_axi_awready;

assign s_axi.rdata 			= s_axi_rdata;
assign s_axi.rlast 			= s_axi_rlast;
assign s_axi.rid 			= s_axi_rid;
assign s_axi.rresp			= s_axi_rresp;
assign s_axi.rvalid 		= s_axi_rvalid;
assign s_axi_rready			= s_axi.rready;

assign s_axi_wdata			= s_axi.wdata;
assign s_axi_wstrb 			= s_axi.wstrb;
assign s_axi_wlast			= s_axi.wlast;
assign s_axi_wvalid			= s_axi.wvalid;
assign s_axi.wready 		= s_axi_wready;

assign s_axi.bid			= s_axi_bid;
assign s_axi.bresp			= s_axi_bresp;
assign s_axi.bvalid 		= s_axi_bvalid;
assign s_axi_bready 		= s_axi.bready;

// Out	
assign m_axi.araddr 		= m_axi_araddr;
assign m_axi.arburst		= m_axi_arburst;
assign m_axi.arcache		= m_axi_arcache;
assign m_axi.arid			= m_axi_arid;
assign m_axi.arlen			= m_axi_arlen;
assign m_axi.arlock			= m_axi_arlock;
assign m_axi.arprot 		= m_axi_arprot;
assign m_axi.arqos 			= m_axi_arqos;
assign m_axi.arsize			= m_axi_arsize;
assign m_axi.arregion		= m_axi_arregion;
assign m_axi.arvalid 		= m_axi_arvalid;
assign m_axi_arready 		= m_axi.arready;

assign m_axi.awaddr 		= m_axi_awaddr;
assign m_axi.awburst		= m_axi_awburst;
assign m_axi.awcache		= m_axi_awcache;
assign m_axi.awid			= m_axi_awid;
assign m_axi.awlen			= m_axi_awlen;
assign m_axi.awlock			= m_axi_awlock;
assign m_axi.awprot 		= m_axi_awprot;
assign m_axi.awqos 			= m_axi_awqos;
assign m_axi.awsize			= m_axi_awsize;
assign m_axi.awregion		= m_axi_awregion;
assign m_axi.awvalid 		= m_axi_awvalid;
assign m_axi_awready 		= m_axi.awready;

assign m_axi_rdata			= m_axi.rdata;
assign m_axi_rid			= m_axi.rid;
assign m_axi_rlast			= m_axi.rlast;
assign m_axi_rresp 			= m_axi.rresp;
assign m_axi_rvalid 		= m_axi.rvalid;
assign m_axi.rready 		= m_axi_rready;

assign m_axi.wdata 			= m_axi_wdata;
assign m_axi.wstrb 			= m_axi_wstrb;
assign m_axi.wlast 			= m_axi_wlast;
assign m_axi.wvalid 		= m_axi_wvalid;
assign m_axi_wready 		= m_axi.wready;

assign m_axi_bid 			= m_axi.bid;
assign m_axi_bresp 			= m_axi.bresp;
assign m_axi_bvalid 		= m_axi.bvalid;
assign m_axi.bready 		= m_axi_bready;

	// ar
	assign m_axi_arvalid 		= decouple ? 1'b0 : s_axi_arvalid;
	assign s_axi_arready		= decouple ? 1'b0 : m_axi_arready;

	assign m_axi_araddr 		= s_axi_araddr;
	assign m_axi_arburst		= s_axi_arburst;
	assign m_axi_arcache		= s_axi_arcache;
	assign m_axi_arid 			= s_axi_arid;
	assign m_axi_arlen 			= s_axi_arlen;
	assign m_axi_arlock 		= s_axi_arlock;
	assign m_axi_arprot 		= s_axi_arprot;
	assign m_axi_arqos 			= s_axi_arqos;
	assign m_axi_arsize 		= s_axi_arsize;
	assign m_axi_arregion 		= s_axi_arregion;

	// aw 
	assign m_axi_awvalid 		= decouple ? 1'b0 : s_axi_awvalid;
	assign s_axi_awready		= decouple ? 1'b0 : m_axi_awready;

	assign m_axi_awaddr 		= s_axi_awaddr;
	assign m_axi_awburst		= s_axi_awburst;
	assign m_axi_awcache		= s_axi_awcache;
	assign m_axi_awid 			= s_axi_awid;
	assign m_axi_awlen 			= s_axi_awlen;
	assign m_axi_awlock 		= s_axi_awlock;
	assign m_axi_awprot 		= s_axi_awprot;
	assign m_axi_awqos 			= s_axi_awqos;
	assign m_axi_awsize 		= s_axi_awsize;
	assign m_axi_awregion 		= s_axi_awregion;

	// b
	assign s_axi_bvalid 		= decouple ? 1'b0 : m_axi_bvalid;
	assign m_axi_bready 		= decouple ? 1'b0 : s_axi_bready;

	assign s_axi_bid 			= m_axi_bid;
	assign s_axi_bresp 			= m_axi_bresp;

	// r
	assign s_axi_rvalid 		= decouple ? 1'b0 : m_axi_rvalid;
	assign m_axi_rready 		= decouple ? 1'b0 : s_axi_rready;

	assign s_axi_rdata 			= m_axi_rdata;
	assign s_axi_rlast 			= m_axi_rlast;
	assign s_axi_rid 			= m_axi_rid;
	assign s_axi_rresp 			= m_axi_rresp;

	// w
	assign m_axi_wvalid 		= decouple ? 1'b0 : s_axi_wvalid;
	assign s_axi_wready 		= decouple ? 1'b0 : m_axi_wready;

	assign m_axi_wdata 			= s_axi_wdata;
	assign m_axi_wstrb 			= s_axi_wstrb;
	assign m_axi_wlast 			= s_axi_wlast;

end
else begin

`AXI_ASSIGN(s_axi, m_axi)

end

endmodule
