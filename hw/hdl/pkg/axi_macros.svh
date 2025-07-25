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

`ifndef AXI_MACROS_SVH_
`define AXI_MACROS_SVH_

`define AXIS_ASSIGN(s, m)              	            \
	assign m.tdata      = s.tdata;     	            \
	assign m.tkeep      = s.tkeep;     	            \
	assign m.tlast      = s.tlast;     	            \
	assign m.tvalid     = s.tvalid;    	            \
	assign s.tready     = m.tready;

`define AXISR_ASSIGN(s, m)                          \
	assign m.tdata      = s.tdata;     	            \
	assign m.tkeep      = s.tkeep;     	            \
	assign m.tlast      = s.tlast;     	            \
	assign m.tvalid     = s.tvalid;    	            \
	assign s.tready     = m.tready;		            \
	assign m.tid  		= s.tid; 	

`define AXISR_ASSIGN_FIRST(s, m, l) 	            \
	assign m.tdata      = s.tdata;     	            \
	assign m.tkeep      = s.tkeep;     	            \
	assign m.tlast      = s.tlast;     	            \
	assign m.tvalid     = s.tvalid;    	            \
	assign s.tready     = m.tready;		            \
	assign m.tid  		= 0;			

`define AXIS_TIE_OFF_M(m)				            \
	assign m.tvalid		= 1'b0;			            \
	assign m.tdata		= 0;			            \
	assign m.tkeep 		= 0;			            \
	assign m.tlast 		= 1'b0;			

`define AXIS_TIE_OFF_S(s)				            \
	assign s.tready		= 1'b1;			

`define AXIS_TIE_ACTIVE_M(m)			            \
	assign m.tvalid		= 1'b1;			            \
	assign m.tdata		= ~0;			            \
	assign m.tkeep 		= ~0;			            \
	assign m.tlast 		= 1'b0;			            \
	
`define AXIS_TIE_ACTIVE_S(s)			            \
	assign s.tready 	= 1'b1;

`define AXIL_ASSIGN(s, m)              	            \
	assign m.araddr 	= s.araddr;		            \
	assign m.arprot 	= s.arprot; 	            \
	assign m.arvalid 	= s.arvalid;	            \
	assign m.awaddr		= s.awaddr;		            \
	assign m.awprot		= s.awprot;		            \
	assign m.awvalid	= s.awvalid;	            \
	assign m.bready 	= s.bready;		            \
	assign m.rready 	= s.rready; 	            \
	assign m.wdata		= s.wdata;		            \
	assign m.wstrb		= s.wstrb;		            \
	assign m.wvalid 	= s.wvalid;		            \
	assign s.arready 	= m.arready;	            \
	assign s.awready	= m.awready; 	            \
	assign s.bresp		= m.bresp;		            \
	assign s.bvalid 	= m.bvalid;		            \
	assign s.rdata		= m.rdata;		            \
	assign s.rresp		= m.rresp;		            \
	assign s.rvalid		= m.rvalid;		            \
	assign s.wready 	= m.wready;

`define AXIL_TIE_OFF_M(m)				            \
	assign m.araddr		= 0;			            \
	assign m.arprot  	= 0;			            \
	assign m.arqos		= 0;			            \
	assign m.arregion 	= 0; 			            \
	assign m.arvalid 	= 1'b0;			            \
	assign m.awaddr		= 0;			            \
	assign m.awprot  	= 0;			            \
	assign m.awqos		= 0;			            \
	assign m.awregion 	= 0; 			            \
	assign m.awvalid 	= 1'b0;			            \
	assign m.rready 	= 1'b1;			            \
	assign m.wdata 		= 0;			            \
	assign m.wstrb 		= 0;			            \
	assign m.valid 		= 1'b0;			            \
	assign m.bready 	= 1'b1;

`define AXIL_TIE_OFF_S(s)				            \
	assign s.arready	= 1'b1;			            \
	assign s.awready  	= 1'b1;			            \
	assign s.rdata 		= 0;			            \
	assign s.rresp 		= 0;			            \
	assign s.rvalid 	= 1'b0;			            \
	assign s.wready 	= 1'b0;			            \
	assign s.bresp 		= 0;			            \
	assign s.bvalid		= 1'b0;	
	
`define AXI_ASSIGN(s, m) 				            \
	assign m.araddr 	= s.araddr;		            \
	assign m.arburst 	= s.arburst;	            \
	assign m.arcache	= s.arcache;	            \
	assign m.arid		= s.arid;		            \
	assign m.arlen		= s.arlen;		            \
	assign m.arlock		= s.arlock;		            \
	assign m.arprot		= s.arprot;		            \
	assign m.arqos		= s.arqos;		            \
	assign m.arregion	= s.arregion;	            \
	assign m.arsize		= s.arsize;		            \
	assign m.arvalid 	= s.arvalid;	            \
	assign s.arready	= m.arready;	            \
	assign m.awaddr 	= s.awaddr;		            \
	assign m.awburst 	= s.awburst;	            \
	assign m.awcache	= s.awcache;	            \
	assign m.awid		= s.awid;		            \
	assign m.awlen		= s.awlen;		            \
	assign m.awlock		= s.awlock;		            \
	assign m.awprot		= s.awprot;		            \
	assign m.awqos		= s.awqos;		            \
	assign m.awregion	= s.awregion;	            \
	assign m.awsize		= s.awsize;		            \
	assign m.awvalid 	= s.awvalid;	            \
	assign s.awready	= m.awready;	            \
	assign s.rdata		= m.rdata;		            \
	assign s.rid 		= m.rid;		            \
	assign s.rlast 		= m.rlast;		            \
	assign s.rresp		= m.rresp;		            \
	assign m.rready		= s.rready;		            \
	assign s.rvalid 	= m.rvalid;		            \
	assign m.wdata		= s.wdata;		            \
	assign m.wlast		= s.wlast;		            \
	assign m.wstrb		= s.wstrb;		            \
	assign s.wready		= m.wready;		            \
	assign m.wvalid		= s.wvalid;		            \
	assign s.bid		= m.bid;		            \
	assign s.bresp		= m.bresp;		            \
	assign m.bready		= s.bready;		            \
	assign s.bvalid		= m.bvalid;			

`define AXI_TIE_OFF_M(m)				            \
	assign m.araddr		= 0;			            \
	assign m.arburst	= 0;			            \
	assign m.arcache	= 0;			            \
	assign m.arid		= 0;			            \
	assign m.arlen		= 0;			            \
	assign m.arlock		= 0;			            \
	assign m.arprot  	= 0;			            \
	assign m.arqos		= 0;			            \
	assign m.arregion 	= 0; 			            \
	assign m.arsize		= 0;			            \
	assign m.arvalid 	= 1'b0;			            \
	assign m.awaddr		= 0;			            \
	assign m.awburst	= 0;			            \
	assign m.awcache	= 0;			            \
	assign m.awid		= 0;			            \
	assign m.awlen		= 0;			            \
	assign m.awlock		= 0;			            \
	assign m.awprot  	= 0;			            \
	assign m.awqos		= 0;			            \
	assign m.awregion 	= 0; 			            \
	assign m.awsize		= 0;			            \
	assign m.awvalid 	= 1'b0;			            \
	assign m.rready 	= 1'b1;			            \
	assign m.wdata 		= 0;			            \
	assign m.wstrb 		= 0;			            \
	assign m.wlast 		= 1'b0;			            \
	assign m.valid 		= 1'b0;			            \
	assign m.bready 	= 1'b1;

`define AXI_TIE_OFF_S(s)				            \
	assign s.arready	= 1'b1;			            \
	assign s.awready  	= 1'b1;			            \
	assign s.rdata 		= 0;			            \
	assign s.rid 		= 0;			            \
	assign s.rlast 		= 1'b0;			            \
	assign s.rresp 		= 0;			            \
	assign s.rvalid 	= 1'b0;			            \
	assign s.wready 	= 1'b0;			            \
	assign s.bresp 		= 0;			            \
	assign s.bvalid		= 1'b0;			            \
	assign s.bid 		= 1'b0;	

`define AXI_ASSIGN_S2I(s, m) 				        \
	assign ``m``.araddr 	= ``s``_araddr;		    \
	assign ``m``.arburst 	= ``s``_arburst;	    \
	assign ``m``.arcache	= ``s``_arcache;	    \
	assign ``m``.arid		= ``s``_arid;		    \
	assign ``m``.arlen		= ``s``_arlen;		    \
	assign ``m``.arlock		= ``s``_arlock;		    \
	assign ``m``.arprot		= ``s``_arprot;		    \
	assign ``m``.arqos		= ``s``_arqos;		    \
	assign ``m``.arregion	= ``s``_arregion;	    \
	assign ``m``.arsize		= ``s``_arsize;		    \
	assign ``m``.arvalid 	= ``s``_arvalid;	    \
	assign ``s``_arready	= ``m``.arready;	    \
	assign ``m``.awaddr 	= ``s``_awaddr;		    \
	assign ``m``.awburst 	= ``s``_awburst;	    \
	assign ``m``.awcache	= ``s``_awcache;	    \
	assign ``m``.awid		= ``s``_awid;		    \
	assign ``m``.awlen		= ``s``_awlen;		    \
	assign ``m``.awlock		= ``s``_awlock;		    \
	assign ``m``.awprot		= ``s``_awprot;		    \
	assign ``m``.awqos		= ``s``_awqos;		    \
	assign ``m``.awregion	= ``s``_awregion;	    \
	assign ``m``.awsize		= ``s``_awsize;		    \
	assign ``m``.awvalid 	= ``s``_awvalid;	    \
	assign ``s``_awready	= ``m``.awready;	    \
	assign ``s``_rdata		= ``m``.rdata;		    \
	assign ``s``_rid 		= ``m``.rid;		    \
	assign ``s``_rlast 		= ``m``.rlast;		    \
	assign ``s``_rresp		= ``m``.rresp;		    \
	assign ``m``.rready		= ``s``_rready;		    \
	assign ``s``_rvalid 	= ``m``.rvalid;		    \
	assign ``m``.wdata		= ``s``_wdata;		    \
	assign ``m``.wlast		= ``s``_wlast;		    \
	assign ``m``.wstrb		= ``s``_wstrb;		    \
	assign ``s``_wready		= ``m``.wready;		    \
	assign ``m``.wvalid		= ``s``_wvalid;		    \
	assign ``s``_bid		= ``m``.bid;		    \
	assign ``s``_bresp		= ``m``.bresp;		    \
	assign ``m``.bready		= ``s``_bready;		    \
	assign ``s``_bvalid		= ``m``.bvalid;	

`define AXI_ASSIGN_I2S(s, m) 				        \
	assign ``m``_araddr 	= ``s``.araddr;		    \
	assign ``m``_arburst 	= ``s``.arburst;	    \
	assign ``m``_arcache	= ``s``.arcache;	    \
	assign ``m``_arid		= ``s``.arid;		    \
	assign ``m``_arlen		= ``s``.arlen;		    \
	assign ``m``_arlock		= ``s``.arlock;		    \
	assign ``m``_arprot		= ``s``.arprot;		    \
	assign ``m``_arqos		= ``s``.arqos;		    \
	assign ``m``_arregion	= ``s``.arregion;	    \
	assign ``m``_arsize		= ``s``.arsize;		    \
	assign ``m``_arvalid 	= ``s``.arvalid;	    \
	assign ``s``.arready	= ``m``_arready;	    \
	assign ``m``_awaddr 	= ``s``.awaddr;		    \
	assign ``m``_awburst 	= ``s``.awburst;	    \
	assign ``m``_awcache	= ``s``.awcache;	    \
	assign ``m``_awid		= ``s``.awid;		    \
	assign ``m``_awlen		= ``s``.awlen;		    \
	assign ``m``_awlock		= ``s``.awlock;		    \
	assign ``m``_awprot		= ``s``.awprot;		    \
	assign ``m``_awqos		= ``s``.awqos;		    \
	assign ``m``_awregion	= ``s``.awregion;	    \
	assign ``m``_awsize		= ``s``.awsize;		    \
	assign ``m``_awvalid 	= ``s``.awvalid;	    \
	assign ``s``.awready	= ``m``_awready;	    \
	assign ``s``.rdata		= ``m``_rdata;		    \
	assign ``s``.rid 		= ``m``_rid;		    \
	assign ``s``.rlast 		= ``m``_rlast;		    \
	assign ``s``.rresp		= ``m``_rresp;		    \
	assign ``m``_rready		= ``s``.rready;		    \
	assign ``s``.rvalid 	= ``m``_rvalid;		    \
	assign ``m``_wdata		= ``s``.wdata;		    \
	assign ``m``_wlast		= ``s``.wlast;		    \
	assign ``m``_wstrb		= ``s``.wstrb;		    \
	assign ``s``.wready		= ``m``_wready;		    \
	assign ``m``_wvalid		= ``s``.wvalid;		    \
	assign ``s``.bid		= ``m``_bid;		    \
	assign ``s``.bresp		= ``m``_bresp;		    \
	assign ``m``_bready		= ``s``.bready;		    \
	assign ``s``.bvalid		= ``m``_bvalid;	

`define AXIL_ASSIGN_S2I(s, m)              	        \
	assign ``m``.araddr 	= ``s``_araddr;		    \
	assign ``m``.arprot 	= ``s``_arprot; 	    \
	assign ``m``.arvalid 	= ``s``_arvalid;	    \
	assign ``m``.awaddr		= ``s``_awaddr;		    \
	assign ``m``.awprot		= ``s``_awprot;		    \
	assign ``m``.awvalid	= ``s``_awvalid;	    \
	assign ``m``.bready 	= ``s``_bready;		    \
	assign ``m``.rready 	= ``s``_rready; 	    \
	assign ``m``.wdata		= ``s``_wdata;		    \
	assign ``m``.wstrb		= ``s``_wstrb;		    \
	assign ``m``.wvalid 	= ``s``_wvalid;		    \
	assign ``s``_arready 	= ``m``.arready;	    \
	assign ``s``_awready	= ``m``.awready; 	    \
	assign ``s``_bresp		= ``m``.bresp;		    \
	assign ``s``_bvalid 	= ``m``.bvalid;		    \
	assign ``s``_rdata		= ``m``.rdata;		    \
	assign ``s``_rresp		= ``m``.rresp;		    \
	assign ``s``_rvalid		= ``m``.rvalid;		    \
	assign ``s``_wready 	= ``m``.wready;	

`define AXIL_ASSIGN_I2S(s, m)              	        \
	assign ``m``_araddr 	= ``s``.araddr;		    \
	assign ``m``_arprot 	= ``s``.arprot; 	    \
	assign ``m``_arvalid 	= ``s``.arvalid;	    \
	assign ``m``_awaddr		= ``s``.awaddr;		    \
	assign ``m``_awprot		= ``s``.awprot;		    \
	assign ``m``_awvalid	= ``s``.awvalid;	    \
	assign ``m``_bready 	= ``s``.bready;		    \
	assign ``m``_rready 	= ``s``.rready; 	    \
	assign ``m``_wdata		= ``s``.wdata;		    \
	assign ``m``_wstrb		= ``s``.wstrb;		    \
	assign ``m``_wvalid 	= ``s``.wvalid;		    \
	assign ``s``.arready 	= ``m``_arready;	    \
	assign ``s``.awready	= ``m``_awready; 	    \
	assign ``s``.bresp		= ``m``_bresp;		    \
	assign ``s``.bvalid 	= ``m``_bvalid;		    \
	assign ``s``.rdata		= ``m``_rdata;		    \
	assign ``s``.rresp		= ``m``_rresp;		    \
	assign ``s``.rvalid		= ``m``_rvalid;		    \
	assign ``s``.wready 	= ``m``_wready;	

`define AXIS_ASSIGN_S2I(s, m)                       \
    assign ``m``.tdata    = ``s``_tdata;            \
	assign ``m``.tkeep    = ``s``_tkeep;            \
	assign ``m``.tlast    = ``s``_tlast;            \
	assign ``m``.tvalid   = ``s``_tvalid;           \
	assign ``s``_tready   = ``m``.tready;

`define AXIS_ASSIGN_I2S(s, m)                       \
    assign ``m``_tdata    = ``s``.tdata;            \
	assign ``m``_tkeep    = ``s``.tkeep;            \
	assign ``m``_tlast    = ``s``.tlast;            \
	assign ``m``_tvalid   = ``s``.tvalid;           \
	assign ``s``.tready   = ``m``_tready;

`define AXISR_ASSIGN_S2I(s, m)                      \
    assign ``m``.tdata    = ``s``_tdata;            \
	assign ``m``.tkeep    = ``s``_tkeep;            \
	assign ``m``.tlast    = ``s``_tlast;            \
    assign ``m``.tid      = ``s``_tid;              \
	assign ``m``.tvalid   = ``s``_tvalid;           \
	assign ``s``_tready   = ``m``.tready;

`define AXISR_ASSIGN_I2S(s, m)                      \
    assign ``m``_tdata    = ``s``.tdata;            \
	assign ``m``_tkeep    = ``s``.tkeep;            \
	assign ``m``_tlast    = ``s``.tlast;            \
    assign ``m``_tid      = ``s``.tid;              \
	assign ``m``_tvalid   = ``s``.tvalid;           \
	assign ``s``.tready   = ``m``_tready;

`define LMETA_ASSIGN(s, m)              	        \
	assign m.data		= s.data;					\
	assign m.valid 		= s.valid; 					\
	assign s.ready 		= m.ready;

`define LMETA_ASSIGN_I2S(s, m)              		\
	assign ``m``_data		= ``s``.data;			\
	assign ``m``_valid 		= ``s``.valid; 			\
	assign ``s``.ready 		= ``m``_ready;

`define LMETA_ASSIGN_S2I(s, m)              		\
	assign ``m``.data		= ``s``_data;			\
	assign ``m``.valid 		= ``s``_valid; 			\
	assign ``s``_ready 		= ``m``.ready;

`endif