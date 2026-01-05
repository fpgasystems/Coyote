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

`ifndef AXI_INTF_SV_
`define AXI_INTF_SV_

`timescale 1ns / 1ps

import lynxTypes::*;

`include "assert_macros.svh"

// ----------------------------------------------------------------------------
// AXI4
// ----------------------------------------------------------------------------
interface AXI4 #(
	parameter AXI4_ADDR_BITS = 64,
	parameter AXI4_DATA_BITS = AXI_DATA_BITS,
	parameter AXI4_ID_BITS = AXI_ID_BITS
) (
	input  logic aclk
);

typedef logic [AXI4_ADDR_BITS-1:0] addr_t;
typedef logic [AXI4_DATA_BITS-1:0] data_t;
typedef logic [AXI4_DATA_BITS/8-1:0] strb_t;
typedef logic [AXI4_ID_BITS-1:0] id_t;

// AR channel
addr_t 			araddr;
logic[1:0]		arburst;
logic[3:0]		arcache;
id_t      		arid;
logic[7:0]		arlen;
logic[0:0]		arlock;
logic[2:0]		arprot;
logic[3:0]		arqos;
logic[3:0]		arregion;
logic[2:0]		arsize;
logic			arready;
logic			arvalid;

// AW channel
addr_t 			awaddr;
logic[1:0]		awburst;
logic[3:0]		awcache;
id_t		    awid;
logic[7:0]		awlen;
logic[0:0]		awlock;
logic[2:0]		awprot;
logic[3:0]		awqos;
logic[3:0]		awregion;
logic[2:0]		awsize;
logic			awready;
logic			awvalid;
 
// R channel
data_t 			rdata;
id_t      		rid;
logic			rlast;
logic[1:0]		rresp;
logic 			rready;
logic			rvalid;

// W channel
data_t 			wdata;
logic			wlast;
strb_t 			wstrb;
logic			wready;
logic			wvalid;

// B channel
id_t      		bid;
logic[1:0]		bresp;
logic			bready;
logic			bvalid;

// Tie off unused master signals
task tie_off_m ();
	araddr    = 0;
    arburst   = 2'b01;
    arcache   = 4'b0;
    arid      = 0;
    arlen     = 8'b0;	
    arlock    = 1'b0;	
    arprot    = 3'b0;	
    arqos     = 4'b0;	
    arregion  = 4'b0;	
    arsize    = 3'b0;	
    arvalid   = 1'b0;	
    awaddr    = 0;	
    awburst   = 2'b01;
    awcache   = 4'b0;	
    awid      = 0;
    awlen     = 8'b0;	
    awlock    = 1'b0;	
    awprot    = 3'b0;	
    awqos     = 4'b0;	
    awregion  = 4'b0;	
    awsize    = 3'b0;	
    awvalid   = 1'b0;
    bready    = 1'b0;    
    rready    = 1'b0;	
    wdata     = 0;	
    wlast     = 1'b0;
    wstrb     = 0;	
    wvalid    = 1'b0;	
endtask

// Tie off unused slave signals
task tie_off_s ();
	arready  = 1'b0;     
    awready  = 1'b0;
    bresp    = 2'b0;
    bvalid   = 1'b0;
    bid      = 0;	
    rdata    = 0;
    rid      = 0;
    rlast    = 1'b0;
    rresp    = 2'b0;
    rvalid   = 1'b0;
    wready   = 1'b0;
endtask

// Master
modport m (
	import tie_off_m,
	// AR
	input awready,
	output awaddr, awburst, awcache, awlen, awlock, awprot, awqos, awregion, awsize, awvalid, awid,
	// AW
	input arready,
	output araddr, arburst, arcache, arlen, arlock, arprot, arqos, arregion, arsize, arvalid, arid,
	// R
	input rlast, rresp, rdata, rvalid, rid,
	output rready,
	// W
	input wready,
	output wdata, wlast, wstrb, wvalid,
	// B
	input bresp, bvalid, bid,
	output bready
);

// Slave
modport s (
	import tie_off_s,
	// AR
	input awaddr, awburst, awcache, awlen, awlock, awprot, awqos, awregion, awsize, awvalid, awid,
	output awready,
	// AW
	input araddr, arburst, arcache, arlen, arlock, arprot, arqos, arregion, arsize, arvalid, arid,
	output arready,
	// R
	input rready,
	output rlast, rresp, rdata, rvalid, rid,
	// W
	input wdata, wlast, wstrb, wvalid,
	output wready,
	// B
	input bready,
	output bresp, bvalid, bid
);

endinterface

// ----------------------------------------------------------------------------
// AXI4 lite
// ----------------------------------------------------------------------------
interface AXI4L #(
	parameter AXI4L_ADDR_BITS = AXI_ADDR_BITS,
	parameter AXI4L_DATA_BITS = AXIL_DATA_BITS
) (
	input logic aclk,
    input logic aresetn
);

typedef logic [AXI4L_ADDR_BITS-1:0] addr_t;
typedef logic [AXI4L_DATA_BITS-1:0] data_t;
typedef logic [AXI4L_DATA_BITS/8-1:0] strb_t;

// AR channel
addr_t 			araddr;
logic[2:0]		arprot;
logic[3:0]		arqos;
logic[3:0]		arregion;
logic			arready;
logic			arvalid;

// AW channel
addr_t 			awaddr;
logic[2:0]		awprot;
logic[3:0]		awqos;
logic[3:0]		awregion;
logic			awready;
logic			awvalid;
 
// R channel
data_t 			rdata;
logic[1:0]		rresp;
logic 			rready;
logic			rvalid;

// W channel
data_t 			wdata;
strb_t 			wstrb;
logic			wready;
logic			wvalid;

// B channel
logic[1:0]		bresp;
logic			bready;
logic			bvalid;

// Tie off unused master signals
task tie_off_m ();
	araddr    = 0;
    arprot    = 3'b0;	
    arqos     = 4'b0;	
    arregion  = 4'b0;	
    arvalid   = 1'b0;	
    awaddr    = 0;	
    awprot    = 3'b0;	
    awqos     = 4'b0;	
    awregion  = 4'b0;		
    awvalid   = 1'b0;	
    bready    = 1'b0;	
    rready    = 1'b0;	
    wdata     = 0;	
    wstrb     = 0;	
    wvalid    = 1'b0;	
endtask

// Tie off unused slave signals
task tie_off_s ();
	arready  = 1'b0;     
    awready  = 1'b0;
    bresp    = 2'b0;
    bvalid   = 1'b0;
    rdata    = 0;
    rresp    = 2'b0;
    rvalid   = 1'b0;
    wready   = 1'b0;
endtask

// Master
modport m (
	import tie_off_m,
	// AR
	input awready,
	output awaddr, awprot, awqos, awregion, awvalid,
	// AW
	input arready,
	output araddr, arprot, arqos, arregion, arvalid,
	// R
	input rresp, rdata, rvalid,
	output rready,
	// W
	input wready,
	output wdata, wstrb, wvalid,
	// B
	input bresp, bvalid,
	output bready
);

// Slave
modport s (
	import tie_off_s,
	// AR
	input awaddr, awprot, awqos, awregion, awvalid,
	output awready,
	// AW
	input araddr, arprot, arqos, arregion, arvalid,
	output arready,
	// R
	input rready,
	output rresp, rdata, rvalid,
	// W
	input wdata, wstrb, wvalid,
	output wready,
	// B
	input bready,
	output bresp, bvalid
);

`ifndef SYNTHESIS
// Clocking blocks for simulation timing
clocking cbm @(posedge aclk);
    default input #INPUT_TIMING output #OUTPUT_TIMING;
    input  awready, arready, rresp, rdata, rvalid, wready, bresp, bvalid;
    output awaddr, awprot, awqos, awregion, awvalid, 
           araddr, arprot, arqos, arregion, arvalid,
           rready,
           wdata, wstrb, wvalid, 
           bready;
endclocking

clocking cbs @(posedge aclk);
    default input #INPUT_TIMING output #OUTPUT_TIMING;
    input  awaddr, awprot, awqos, awregion, awvalid,
           araddr, arprot, arqos, arregion, arvalid,
           rready,
           wdata, wstrb, wvalid,
           bready;
    output awready, arready, rresp, rdata, rvalid, wready, bresp, bvalid;
endclocking

// Assertions
`ASSERT_STABLE(awaddr, awvalid, awready);
`ASSERT_STABLE(awprot, awvalid, awready);
`ASSERT_STABLE(awqos, awvalid, awready);
`ASSERT_STABLE(awregion, awvalid, awready);
`ASSERT_NOT_UNDEFINED(awvalid);
`ASSERT_NOT_UNDEFINED(awready);

`ASSERT_STABLE(araddr, arvalid, arready);
`ASSERT_STABLE(arprot, arvalid, arready);
`ASSERT_STABLE(arqos, arvalid, arready);
`ASSERT_STABLE(arregion, arvalid, arready);
`ASSERT_NOT_UNDEFINED(arvalid);
`ASSERT_NOT_UNDEFINED(arready);

`ASSERT_STABLE(wdata, wvalid, wready);
`ASSERT_STABLE(wstrb, wvalid, wready);
`ASSERT_NOT_UNDEFINED(wvalid);
`ASSERT_NOT_UNDEFINED(wready);

`ASSERT_STABLE(rresp, rvalid, rready);
`ASSERT_STABLE(rdata, rvalid, rready);
`ASSERT_NOT_UNDEFINED(rvalid);
`ASSERT_NOT_UNDEFINED(rready);

`ASSERT_STABLE(bresp, bvalid, bready);
`ASSERT_NOT_UNDEFINED(bvalid);
`ASSERT_NOT_UNDEFINED(bready);
`endif

endinterface

// ----------------------------------------------------------------------------
// AXI4 stream 
// ----------------------------------------------------------------------------
interface AXI4S #(
	parameter AXI4S_DATA_BITS = AXI_DATA_BITS
) (
    input logic aclk,
    input logic aresetn
);

typedef logic [AXI4S_DATA_BITS-1:0] data_t;
typedef logic [AXI4S_DATA_BITS/8-1:0] keep_t;

data_t          tdata;
keep_t  		tkeep;
logic           tlast;
logic           tready;
logic           tvalid;

// Tie off unused master signals
task tie_off_m ();
    tdata      = 0;
    tkeep      = 0;
    tlast     = 1'b0;
    tvalid     = 1'b0;
endtask

// Tie off unused slave signals
task tie_off_s ();
    tready     = 1'b0;
endtask

// Master
modport m (
	import tie_off_m,
	input tready,
	output tdata, tkeep, tlast, tvalid
);

// Slave
modport s (
    import tie_off_s,
    input tdata, tkeep, tlast, tvalid,
    output tready
);

`ifndef SYNTHESIS
// Assertions
`ASSERT_SIGNAL_STABLE(tdata);
`ASSERT_SIGNAL_STABLE(tkeep);
`ASSERT_SIGNAL_STABLE(tlast);
`ASSERT_NOT_UNDEFINED(tvalid);
`ASSERT_NOT_UNDEFINED(tready);
`endif

endinterface


// ----------------------------------------------------------------------------
// AXI4 stream routed
// ----------------------------------------------------------------------------
interface AXI4SR #(
	parameter AXI4S_DATA_BITS = AXI_DATA_BITS,
	parameter AXI4S_ID_BITS = PID_BITS
) (
    input logic aclk,
    input logic aresetn
);

typedef logic [AXI4S_DATA_BITS-1:0] data_t;
typedef logic [AXI4S_DATA_BITS/8-1:0] keep_t;
typedef logic [AXI4S_ID_BITS-1:0] id_t;
 
data_t          tdata;
keep_t  		tkeep;
id_t  			tid;
logic           tlast;
logic           tready;
logic           tvalid;

// Tie off unused master signals
task tie_off_m ();
    tdata      = 0;
    tkeep      = 0;
    tlast      = 1'b0;
	tid 	   = 0;
    tvalid     = 1'b0;
endtask

// Tie off unused slave signals
task tie_off_s ();
    tready     = 1'b0;
endtask

// Master
modport m (
	import tie_off_m,
	input tready,
	output tdata, tkeep, tlast, tvalid, tid
);

// Slave
modport s (
    import tie_off_s,
    input tdata, tkeep, tlast, tvalid, tid,
    output tready
);

`ifndef SYNTHESIS
// Clocking blocks for simulation timing
clocking cbm @(posedge aclk);
    default input #INPUT_TIMING output #OUTPUT_TIMING;
    input  tready;
    output tdata, tkeep, tlast, tvalid, tid;
endclocking

clocking cbs @(posedge aclk);
    default input #INPUT_TIMING output #OUTPUT_TIMING;
    input  tdata, tkeep, tlast, tvalid, tid;
    output tready;
endclocking

// Assertions
`ASSERT_SIGNAL_STABLE(tdata);
`ASSERT_SIGNAL_STABLE(tid);
`ASSERT_SIGNAL_STABLE(tkeep);
`ASSERT_SIGNAL_STABLE(tlast);
`ASSERT_NOT_UNDEFINED(tvalid);
`ASSERT_NOT_UNDEFINED(tready);
`endif

endinterface

// ----------------------------------------------------------------------------
// Fixed logic META stream interface
// ----------------------------------------------------------------------------
interface LMetaIntf #(
	parameter METAF_DATA_BITS = AXI_DATA_BITS
) (
    input  logic aclk
);

typedef logic [METAF_DATA_BITS-1:0] data_t;
 
logic valid;
logic ready;
data_t data;

task tie_off_s ();
	ready = 1'b1;
endtask

task tie_off_m ();
	data = 0;
	valid = 1'b0;
endtask

modport s (
	import tie_off_s,
	input  valid,
	output ready,
	input  data
);

modport m (
	import tie_off_m,
	output valid,
	input  ready,
	output data
);

endinterface

`endif