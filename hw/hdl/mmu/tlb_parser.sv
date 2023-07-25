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
 * @brief   TLB parsing of the incoming requests
 *
 * Parses the requests to the provided PARSE_SIZE.
 */
module tlb_parser (
    input  logic            aclk,
    input  logic            aresetn,
    
    metaIntf.s              s_req,
    metaIntf.m              m_req
);

localparam integer PARSE_SIZE = PMTU_BYTES; // probably best to keep at PMTU size

// -- FSM
typedef enum logic[1:0]  {ST_IDLE, ST_PARSE, ST_SEND} state_t;
logic [1:0] state_C, state_N;

logic [LEN_BITS-1:0] len_C, len_N;
logic [VADDR_BITS-1:0] vaddr_C, vaddr_N;
logic ctl_C, ctl_N;
logic sync_C, sync_N;
logic stream_C, stream_N;
logic [DEST_BITS-1:0] dest_C, dest_N;
logic [PID_BITS-1:0] pid_C, pid_N;
logic [N_REGIONS_BITS-1:0] vfid_C, vfid_N;
logic host_C, host_N;

logic [LEN_BITS-1:0] plen_C, plen_N;
logic [VADDR_BITS-1:0] pvaddr_C, pvaddr_N;
logic pctl_C, pctl_N;

// REG
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
	state_C <= ST_IDLE;

    len_C <= 'X;
    vaddr_C <= 'X;
    ctl_C <= 'X;
    sync_C <= 'X;
    stream_C <= 'X;
    dest_C <= 'X;
    pid_C <= 'X;
    vfid_C <= 'X;
    host_C <= 'X;

    plen_C <= 'X;
    pvaddr_C <= 'X;
    pctl_C <= 'X;
end
else
	state_C <= state_N;

    len_C <= len_N;
    vaddr_C <= vaddr_N;
    ctl_C <= ctl_N;
    sync_C <= sync_N;
    stream_C <= stream_N;
    dest_C <= dest_N;
    pid_C <= pid_N;
    vfid_C <= vfid_N;
    host_C <= host_N;

    plen_C <= plen_N;
    pvaddr_C <= pvaddr_N;
    pctl_C <= pctl_N;
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
    len_N = len_C;
    vaddr_N = vaddr_C;
    ctl_N = ctl_C;
    sync_N = sync_C;
    stream_N = stream_C;
    dest_N = dest_C;
    pid_N = pid_C;
    vfid_N = vfid_C;
    host_N = host_C;

    plen_N = plen_C;
    pvaddr_N = pvaddr_C;
    pctl_N = pctl_C;

    // Flow
    s_req.ready = 1'b0;
    m_req.valid = 1'b0;

    // Data
    m_req.data.len = plen_C;
    m_req.data.vaddr = pvaddr_C;
    m_req.data.ctl = pctl_C;
    m_req.data.sync = sync_C;
    m_req.data.stream = stream_C;
    m_req.data.dest = dest_C;
    m_req.data.pid = pid_C;
    m_req.data.vfid = vfid_C;
    m_req.data.host = host_C;
    m_req.data.rsrvd = 0;

    case(state_C)
        ST_IDLE: begin
            s_req.ready = 1'b1;
            if(s_req.valid) begin
                len_N = s_req.data.len;
                vaddr_N = s_req.data.vaddr;
                ctl_N = s_req.data.ctl;
                sync_N = s_req.data.sync;
                stream_N = s_req.data.stream;
                dest_N = s_req.data.dest;
                pid_N = s_req.data.pid;
                vfid_N = vfid_C;
                host_N = s_req.data.host;
            end
        end

        ST_PARSE: begin
            pvaddr_N = vaddr_N;
            
            if(len_C > PARSE_SIZE) begin
                vaddr_N = vaddr_C + PARSE_SIZE;
                len_N = len_C - PARSE_SIZE;

                plen_N = PARSE_SIZE;
                pctl_N = 1'b0;
            end
            else begin
                len_N = 0;

                plen_N = len_C;
                pctl_N = ctl_C;
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