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
 * @brief  Parsing of the requests
 *
 * Parses the requests to the provided PARSE_SIZE.
 */
module req_parser (
    input  logic            aclk,
    input  logic            aresetn,
    
    metaIntf.s              s_req,
    metaIntf.m              m_req
);

localparam integer PARSE_SIZE = PMTU_BYTES; // probably best to keep at PMTU size

// -- FSM
typedef enum logic[1:0]  {ST_IDLE, ST_PARSE, ST_SEND} state_t;
logic [1:0] state_C, state_N;

// Request
logic [OPCODE_BITS-1:0] opcode_C, opcode_N;
logic mode_C, mode_N;
logic rdma_C, rdma_N;
logic remote_C, remote_N;
logic [PID_BITS-1:0] pid_C, pid_N;
logic [N_REGIONS_BITS-1:0] vfid_C, vfid_N;
logic [DEST_BITS-1:0] dest_C, dest_N;
logic [STRM_BITS-1:0] strm_C, strm_N;
logic last_C, last_N;
logic host_C, host_N;
logic actv_C, actv_N;
logic [LEN_BITS-1:0] len_C, len_N;
logic [VADDR_BITS-1:0] vaddr_C, vaddr_N;

logic [LEN_BITS-1:0] plen_C, plen_N;
logic [VADDR_BITS-1:0] pvaddr_C, pvaddr_N;
logic plast_C, plast_N;

// REG
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
	state_C <= ST_IDLE;

    opcode_C <= 'X;
    mode_C <= 'X;
    rdma_C <= 'X;
    remote_C <= 'X;
    pid_C <= 'X;
    vfid_C <= 'X;
    dest_C <= 'X;
    strm_C <= 'X;
    last_C <= 'X;
    host_C <= 'X;
    actv_C <= 'X;
    len_C <= 'X;
    vaddr_C <= 'X;

    plen_C <= 'X;
    pvaddr_C <= 'X;
    plast_C <= 'X;
end
else
	state_C <= state_N;

    opcode_C <= opcode_N;
    mode_C <= mode_N;
    rdma_C <= rdma_N;
    remote_C <= remote_N;
    pid_C <= pid_N;
    vfid_C <= vfid_N;
    dest_C <= dest_N;
    strm_C <= strm_N;
    last_C <= last_N;
    host_C <= host_N;
    actv_C <= actv_N;
    len_C <= len_N;
    vaddr_C <= vaddr_N;

    plen_C <= plen_N;
    pvaddr_C <= pvaddr_N;
    plast_C <= plast_N;
end

// NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
            if(s_req.valid) begin
                state_N = ST_PARSE;
            end
            
        ST_PARSE:
            state_N = ST_SEND;

        ST_SEND:
            if(m_req.ready) 
                state_N = len_C ? ST_PARSE : ST_IDLE;

	endcase // state_C
end

// DP
always_comb begin: DP
    opcode_N = opcode_C;
    mode_N = mode_C;
    rdma_N = rdma_C;
    remote_N = remote_C;
    pid_N = pid_C;
    vfid_N = vfid_C;
    dest_N = dest_C;
    strm_N = strm_C;
    last_N = last_C;
    host_N = host_C;
    actv_N = actv_C;
    len_N = len_C;
    vaddr_N = vaddr_C;

    plen_N = plen_C;
    pvaddr_N = pvaddr_C;
    plast_N = plast_C;

    // Flow
    s_req.ready = 1'b0;
    m_req.valid = 1'b0;

    // Data
    m_req.data.opcode = opcode_C;
    m_req.data.mode = mode_C;
    m_req.data.rdma = rdma_C;
    m_req.data.remote = remote_C;
    m_req.data.pid = pid_C;
    m_req.data.vfid = vfid_C;
    m_req.data.dest = dest_C;
    m_req.data.strm = strm_C;
    m_req.data.last = plast_C;
    m_req.data.actv = actv_C;
    m_req.data.host = host_C;
    m_req.data.offs = 0;
    m_req.data.vaddr = pvaddr_C;
    m_req.data.len = plen_C;
    m_req.data.rsrvd = 0;

    case(state_C)
        ST_IDLE: begin
            s_req.ready = 1'b1;
            if(s_req.valid) begin
                opcode_N = s_req.data.opcode;
                mode_N = s_req.data.mode;
                rdma_N = s_req.data.rdma;
                remote_N = s_req.data.remote;
                pid_N = s_req.data.pid;
                vfid_N = s_req.data.vfid;
                dest_N = s_req.data.dest;
                strm_N = s_req.data.strm;
                last_N = s_req.data.last;
                host_N = s_req.data.host;
                actv_N = s_req.data.actv;
                len_N = s_req.data.len;
                vaddr_N = s_req.data.vaddr;
            end
        end

        ST_PARSE: begin
            pvaddr_N = vaddr_N;
            
            if(len_C > PARSE_SIZE) begin
                vaddr_N = vaddr_C + PARSE_SIZE;
                len_N = len_C - PARSE_SIZE;

                plen_N = PARSE_SIZE;
                plast_N = 1'b0;
            end
            else begin
                len_N = 0;

                plen_N = len_C;
                plast_N = last_C;
            end
        end

        ST_SEND:
            m_req.valid = 1'b1; 

    endcase
end

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_TLB_PARSER

`endif

endmodule