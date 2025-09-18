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

`ifndef LYNX_INTF_SV_
`define LYNX_INTF_SV_

`timescale 1ns / 1ps

import lynxTypes::*;

// ----------------------------------------------------------------------------
// Generic meta interface
// ----------------------------------------------------------------------------
interface metaIntf #(
	parameter type STYPE = logic[63:0]
) (
	input  logic aclk
);

logic valid;
logic ready;
STYPE data;

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

// Clocking blocks for simulation timing
clocking cbm @(posedge aclk);
    default input #INPUT_TIMING output #OUTPUT_TIMING;
    input  ready;
    output valid, data;
endclocking

clocking cbs @(posedge aclk);
    default input #INPUT_TIMING output #OUTPUT_TIMING;
    input  valid, data;
    output ready;
endclocking

endinterface

// ----------------------------------------------------------------------------
// TLB interface
// ----------------------------------------------------------------------------
interface tlbIntf #(
	parameter TLB_INTF_DATA_BITS = TLB_DATA_BITS
);

typedef logic [VADDR_BITS-1:0] addr_t;
typedef logic [TLB_INTF_DATA_BITS-1:0] data_t;
typedef logic [PID_BITS-1:0] pid_t;

addr_t 			addr;
data_t 			data;

logic 			valid;
logic 			wr;
pid_t			pid;
logic [STRM_BITS-1:0] strm;
logic 			hit;

modport s (
	input valid,
	input wr,
	input pid,
    input strm,
	input addr,
	output hit,
	output data
);

modport m (
	output valid,
	output wr,
	output pid,
    output strm,
	output addr,
	input hit,
	input data
);

endinterface

// ----------------------------------------------------------------------------
// DMA interface
// ----------------------------------------------------------------------------
interface dmaIntf (
	input  logic aclk
);

dma_req_t   			req;
dma_rsp_t				rsp;
logic 					valid;
logic 					ready;

task tie_off_s ();
	rsp = 0;
	ready = 1'b1;
endtask

task tie_off_m ();
	req = 0;
	valid = 1'b0;
endtask

// Slave
modport s (
	import tie_off_s,
	input  req,
	input  valid,
	output ready,
	output rsp
);

// Master
modport m (
	import tie_off_m,
	output req,
	output valid,
	input  ready,
	input  rsp
);

endinterface

// ----------------------------------------------------------------------------
// DMA ISR interface
// ----------------------------------------------------------------------------
interface dmaIsrIntf ();

dma_isr_req_t 			req;
dma_isr_rsp_t			rsp;
logic 					valid;
logic 					ready;

task tie_off_s ();
	rsp = 0;
	ready = 1'b1;
endtask

task tie_off_m ();
	req = 0;
	valid = 1'b0;
endtask

modport s (
    import tie_off_s,
	input  req,
	input  valid,
	output ready,
	output rsp
);

modport m (
    import tie_off_m,
	output req,
	output valid,
	input  ready,
	input  rsp
);

endinterface

// ---------------------------------------------------------------------------- 
// Multiplexer interface 
// ---------------------------------------------------------------------------- 
interface muxIntf #(
	parameter integer N_ID_BITS = N_REGIONS_BITS,
	parameter integer ARB_DATA_BITS = AXI_DATA_BITS
);

localparam integer BEAT_LOG_BITS = $clog2(ARB_DATA_BITS/8);

logic [N_ID_BITS-1:0]			    vfid;
logic [LEN_BITS-BEAT_LOG_BITS-1:0]	len;
logic 								ctl;

logic 							   	ready;
logic 							   	valid;
logic 								done;

task tie_off_s ();
	vfid = 0;
	len = 0;
	ctl = 1'b0;
	ready = 1'b0;
endtask

task tie_off_m ();
	valid = 1'b0;
	done = 1'b0;
endtask

modport s (
    import tie_off_s,
	output vfid,
	output len,
	output ctl,
	output ready,
	input  valid,
	input  done
);

modport m (
    import tie_off_m,
	input  vfid,
	input  len,
	input  ctl,
	input  ready,
	output valid,
	output done
);

endinterface

// ---------------------------------------------------------------------------- 
// XDMA bypass
// ---------------------------------------------------------------------------- 
interface xdmaIntf ();

logic [63:0] h2c_addr;
logic [27:0] h2c_len;
logic [15:0] h2c_ctl;
logic h2c_valid;
logic h2c_ready;

logic [63:0] c2h_addr;
logic [27:0] c2h_len;
logic [15:0] c2h_ctl;
logic c2h_valid;
logic c2h_ready;

logic [7:0] h2c_status;
logic [7:0] c2h_status;

// Slave
modport s (
	input h2c_addr,
	input h2c_len,
	input h2c_ctl,
	input h2c_valid,
	output h2c_ready,
	input c2h_addr,
	input c2h_len,
	input c2h_ctl,
	input c2h_valid,
	output c2h_ready,
	output h2c_status,
	output c2h_status
);

// Master
modport m (
	output h2c_addr,
	output h2c_len,
	output h2c_ctl,
	output h2c_valid,
	input h2c_ready,
	output c2h_addr,
	output c2h_len,
	output c2h_ctl,
	output c2h_valid,
	input c2h_ready,
	input h2c_status,
	input c2h_status
);

endinterface

// ---------------------------------------------------------------------------- 
// QDMA H2C Data Stream; see Table 59 in QDMA Specification [PG302 v5.0]
// ---------------------------------------------------------------------------- 
interface qdmaH2CS ();

qdma_h2c_data_t 			payload;
logic 						tvalid;
logic 						tlast;
logic 						tready;

modport s (
	input payload,
	input tvalid,
	input tlast,
	output tready
);

modport m (
	output payload,
	output tvalid,
	output tlast,
	input tready
);

endinterface

// ---------------------------------------------------------------------------- 
// QDMA H2C Command Stream; see Table 67 in QDMA Specification [PG302 v5.0]
// ---------------------------------------------------------------------------- 
interface qdmaH2CIntf ();

qdma_h2c_cmd_t  req;
logic  			ready;
logic  			valid;

modport s (
	input req,
	input valid,
	output ready
);

modport m (
	output req,
	output valid,
	input ready
);

endinterface

// ---------------------------------------------------------------------------- 
// QDMA H2C Status; see Table 77 in QDMA Specification [PG302 v5.0]
// ---------------------------------------------------------------------------- 
interface qdmaH2CSts ();

logic [63:0] 	data;
logic [7:0]		op;
logic [2:0] 	port_id;
logic [11:0] 	qid;
logic  			ready;
logic  			valid;

modport s (
	input data,
	input op,
	input port_id,
	input qid,
	output ready,
	input valid
);

modport m (
	output data,
	output op,
	output port_id,
	output qid,
	input ready,
	output valid
);

endinterface

// ---------------------------------------------------------------------------- 
// QDMA C2H Data Stream; see Table 60 in QDMA Specification [PG302 v5.0]
// ---------------------------------------------------------------------------- 
interface qdmaC2HS ();

qdma_c2h_data_t 			payload;
logic 						tvalid;
logic 						tlast;
logic 						tready;

modport s (
	input payload,
	input tvalid,
	input tlast,
	output tready
);

modport m (
	output payload,
	output tvalid,
	output tlast,
	input tready
);

endinterface

// ---------------------------------------------------------------------------- 
// QDMA C2H Command Stream; see Table 69 in QDMA Specification [PG302 v5.0]
// ---------------------------------------------------------------------------- 
interface qdmaC2HIntf ();
qdma_c2h_cmd_t  req;
logic  			ready;
logic  			valid;

modport s (
	input req,
	input valid,
	output ready
);

modport m (
	output req,
	output valid,
	input ready
);

endinterface


// ---------------------------------------------------------------------------- 
// QDMA C2H Status; see Table 62 in QDMA Specification [PG302 v5.0]
// ---------------------------------------------------------------------------- 
interface qdmaC2HSts ();

logic  			valid;
logic [11:0] 	qid;
logic			drop;
logic 			last;
logic 			cmp;
logic 			error;

modport s (
	input valid,
	input qid,
	input drop,
	input last,
	input cmp,
	input error
);

modport m (
	output valid,
	output qid,
	output drop,
	output last,
	output cmp,
	output error
);

endinterface


`endif
