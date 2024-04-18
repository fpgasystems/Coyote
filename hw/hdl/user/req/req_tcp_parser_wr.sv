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
 * @brief   Network command parser
 *
 * Multiplexing of the network commands
 */
module req_tcp_parser_wr #(
    parameter integer       ID_REG = 0,
    parameter integer       DBG = 0
) (
    input  logic            aclk,
    input  logic            aresetn,
    
    metaIntf.s              s_req,
    metaIntf.m              m_req
);

// FSM
typedef enum logic[1:0]  {ST_IDLE, 
    ST_PARSE_WRITE, ST_SEND_WRITE
} state_t;
logic [1:0] state_C, state_N;

req_t req_C, req_N;

logic [0:0] plast_C, plast_N;
logic [LEN_BITS-1:0] plen_C, plen_N;

// Requests internal
metaIntf #(.STYPE(req_t)) req_pre_parsed ();
metaIntf #(.STYPE(req_t)) req_parsed ();

// Decoupling
`META_ASSIGN(s_req, req_pre_parsed)

// REG
always_ff @(posedge aclk) begin: PROC_REG
    if (aresetn == 1'b0) begin
        state_C <= ST_IDLE;
    end
    else begin
        state_C <= state_N;

        req_C <= req_N;
        
        plast_C <= plast_N;
        plen_C <= plen_N;
    end
end

// NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			if(req_pre_parsed.valid) begin
                state_N = ST_PARSE_WRITE;
            end

        // Writes
        ST_PARSE_WRITE:
            state_N = ST_SEND_WRITE;

        ST_SEND_WRITE:
            if(req_parsed.ready) begin
                state_N = req_C.len ? ST_PARSE_WRITE : ST_IDLE;
            end

	endcase // state_C
end

// DP
always_comb begin: DP
    req_N = req_C;

    plast_N = plast_C;
    plen_N = plen_C;

    // Flow
    req_pre_parsed.ready = 1'b0;
    req_parsed.valid = 1'b0;

    // Data
    req_parsed.data = 0;

    req_parsed.data.mode = 1'b0;
    req_parsed.data.rdma = 1'b0;
    req_parsed.data.remote = 1'b1;
    req_parsed.data.pid = req_C.pid;
    req_parsed.data.vfid = req_C.vfid;
    req_parsed.data.dest = req_C.dest;
    req_parsed.data.last = 1'b0;
    req_parsed.data.len = plen_C;
    req_parsed.data.actv = 1'b1;
    req_parsed.data.host = req_C.host;
    req_parsed.data.vaddr = req_C.vaddr;

    case(state_C)
        ST_IDLE: begin
            req_pre_parsed.ready = 1'b1;

            if(req_pre_parsed.valid) begin
                req_N = req_pre_parsed.data;
            end
        end

        // Writes
        ST_PARSE_WRITE: begin
            if(req_C.len > PMTU_BYTES) begin
                req_N.len = req_C.len - PMTU_BYTES;

                plen_N = PMTU_BYTES;  
                plast_N = 1'b0;            
            end
            else begin
                req_N.len = 0;

                plen_N = req_C.len;
                plast_N = req_C.last;
            end
        end
    
        ST_SEND_WRITE:
            req_parsed.valid = 1'b1;

    endcase
end

meta_reg #(.DATA_BITS($bits(req_t))) inst_reg_src  (.aclk(aclk), .aresetn(aresetn), .s_meta(req_parsed), .m_meta(m_req));

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_TCP_PARSER_WR

`endif

endmodule