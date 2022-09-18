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

`ifndef AXI_MACROS_SVH_
`define AXI_MACROS_SVH_

`define AXIS_ASSIGN(s, m)              	\
	assign m.tdata      = s.tdata;     	\
	assign m.tkeep      = s.tkeep;     	\
	assign m.tlast      = s.tlast;     	\
	assign m.tvalid     = s.tvalid;    	\
	assign s.tready     = m.tready;

`define AXISR_ASSIGN(s, m)              \
	assign m.tdata      = s.tdata;     	\
	assign m.tkeep      = s.tkeep;     	\
	assign m.tlast      = s.tlast;     	\
	assign m.tvalid     = s.tvalid;    	\
	assign s.tready     = m.tready;		\
	assign m.tid  		= s.tid; 	

`define AXISR_ASSIGN_FIRST(s, m, l) 	\
	assign m.tdata      = s.tdata;     	\
	assign m.tkeep      = s.tkeep;     	\
	assign m.tlast      = s.tlast;     	\
	assign m.tvalid     = s.tvalid;    	\
	assign s.tready     = m.tready;		\
	assign m.tid  		= 0;			

`define AXIS_TIE_OFF_M(m)				\
	assign m.tvalid		= 1'b0;			\
	assign m.tdata		= 0;			\
	assign m.tkeep 		= 0;			\
	assign m.tlast 		= 1'b0;			

`define AXIS_TIE_OFF_S(s)				\
	assign s.tready		= 1'b0;			

`define AXIS_TIE_ACTIVE_M(m)			\
	assign m.tvalid		= 1'b1;			\
	assign m.tdata		= ~0;			\
	assign m.tkeep 		= ~0;			\
	assign m.tlast 		= 1'b0;			\
	
`define AXIS_TIE_ACTIVE_S(s)			\
	assign s.tready 	= 1'b1;

`define AXIL_ASSIGN(s, m)              	\
	assign m.araddr 	= s.araddr;		\
	assign m.arprot 	= s.arprot; 	\
	assign m.arvalid 	= s.arvalid;	\
	assign m.awaddr		= s.awaddr;		\
	assign m.awprot		= s.awprot;		\
	assign m.awvalid	= s.awvalid;	\
	assign m.bready 	= s.bready;		\
	assign m.rready 	= s.rready; 	\
	assign m.wdata		= s.wdata;		\
	assign m.wstrb		= s.wstrb;		\
	assign m.wvalid 	= s.wvalid;		\
	assign s.arready 	= m.arready;	\
	assign s.awready	= m.awready; 	\
	assign s.bresp		= m.bresp;		\
	assign s.bvalid 	= m.bvalid;		\
	assign s.rdata		= m.rdata;		\
	assign s.rresp		= m.rresp;		\
	assign s.rvalid		= m.rvalid;		\
	assign s.wready 	= m.wready;

`define AXIL_TIE_OFF_M(m)				\
	assign m.araddr		= 0;			\
	assign m.arprot  	= 0;			\
	assign m.arqos		= 0;			\
	assign m.arregion 	= 0; 			\
	assign m.arvalid 	= 1'b0;			\
	assign m.awaddr		= 0;			\
	assign m.awprot  	= 0;			\
	assign m.awqos		= 0;			\
	assign m.awregion 	= 0; 			\
	assign m.awvalid 	= 1'b0;			\
	assign m.rready 	= 1'b0;			\
	assign m.wdata 		= 0;			\
	assign m.wstrb 		= 0;			\
	assign m.valid 		= 1'b0;			\
	assign m.bready 	= 1'b0;

`define AXIL_TIE_OFF_S(s)				\
	assign s.arready	= 1'b0;			\
	assign s.awready  	= 1'b0;			\
	assign s.rdata 		= 0;			\
	assign s.rresp 		= 0;			\
	assign s.rvalid 	= 1'b0;			\
	assign s.wready 	= 1'b0;			\
	assign s.bresp 		= 0;			\
	assign s.bvalid		= 1'b0;	
	
`define AXI_ASSIGN(s, m) 				\
	assign m.araddr 	= s.araddr;		\
	assign m.arburst 	= s.arburst;	\
	assign m.arcache	= s.arcache;	\
	assign m.arid		= s.arid;		\
	assign m.arlen		= s.arlen;		\
	assign m.arlock		= s.arlock;		\
	assign m.arprot		= s.arprot;		\
	assign m.arqos		= s.arqos;		\
	assign m.arregion	= s.arregion;	\
	assign m.arsize		= s.arsize;		\
	assign m.arvalid 	= s.arvalid;	\
	assign s.arready	= m.arready;	\
	assign m.awaddr 	= s.awaddr;		\
	assign m.awburst 	= s.awburst;	\
	assign m.awcache	= s.awcache;	\
	assign m.awid		= s.awid;		\
	assign m.awlen		= s.awlen;		\
	assign m.awlock		= s.awlock;		\
	assign m.awprot		= s.awprot;		\
	assign m.awqos		= s.awqos;		\
	assign m.awregion	= s.awregion;	\
	assign m.awsize		= s.awsize;		\
	assign m.awvalid 	= s.awvalid;	\
	assign s.awready	= m.awready;	\
	assign s.rdata		= m.rdata;		\
	assign s.rid 		= m.rid;		\
	assign s.rlast 		= m.rlast;		\
	assign s.rresp		= m.rresp;		\
	assign m.rready		= s.rready;		\
	assign s.rvalid 	= m.rvalid;		\
	assign m.wdata		= s.wdata;		\
	assign m.wlast		= s.wlast;		\
	assign m.wstrb		= s.wstrb;		\
	assign s.wready		= m.wready;		\
	assign m.wvalid		= s.wvalid;		\
	assign s.bid		= m.bid;		\
	assign s.bresp		= m.bresp;		\
	assign m.bready		= s.bready;		\
	assign s.bvalid		= m.bvalid;			

`define AXI_TIE_OFF_M(m)				\
	assign m.araddr		= 0;			\
	assign m.arburst	= 0;			\
	assign m.arcache	= 0;			\
	assign m.arid		= 0;			\
	assign m.arlen		= 0;			\
	assign m.arlock		= 0;			\
	assign m.arprot  	= 0;			\
	assign m.arqos		= 0;			\
	assign m.arregion 	= 0; 			\
	assign m.arsize		= 0;			\
	assign m.arvalid 	= 1'b0;			\
	assign m.awaddr		= 0;			\
	assign m.awburst	= 0;			\
	assign m.awcache	= 0;			\
	assign m.awid		= 0;			\
	assign m.awlen		= 0;			\
	assign m.awlock		= 0;			\
	assign m.awprot  	= 0;			\
	assign m.awqos		= 0;			\
	assign m.awregion 	= 0; 			\
	assign m.awsize		= 0;			\
	assign m.awvalid 	= 1'b0;			\
	assign m.rready 	= 1'b0;			\
	assign m.wdata 		= 0;			\
	assign m.wstrb 		= 0;			\
	assign m.wlast 		= 1'b0;			\
	assign m.valid 		= 1'b0;			\
	assign m.bready 	= 1'b0;

`define AXI_TIE_OFF_S(s)				\
	assign s.arready	= 1'b0;			\
	assign s.awready  	= 1'b0;			\
	assign s.rdata 		= 0;			\
	assign s.rid 		= 0;			\
	assign s.rlast 		= 1'b0;			\
	assign s.rresp 		= 0;			\
	assign s.rvalid 	= 1'b0;			\
	assign s.wready 	= 1'b0;			\
	assign s.bresp 		= 0;			\
	assign s.bvalid		= 1'b0;			\
	assign s.bid 		= 1'b0;	

`endif