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
module dreq_rdma_parser_rd #(
    parameter integer       ID_REG = 0,
    parameter integer       DBG = 0
) (
    input  logic            aclk,
    input  logic            aresetn,
    
    metaIntf.s              s_req,
    metaIntf.m              m_req
);

// FSM
typedef enum logic[1:0]  {ST_IDLE, ST_PARSE_READ, ST_SEND_READ} state_t;
logic [1:0] state_C, state_N;

req_t req_1_C, req_1_N;
req_t req_2_C, req_2_N;

logic [0:0] plast_C, plast_N;
logic [VADDR_BITS-1:0] plvaddr_C, plvaddr_N;
logic [VADDR_BITS-1:0] prvaddr_C, prvaddr_N;
logic [LEN_BITS-1:0] plen_C, plen_N;

// Requests internal
metaIntf #(.STYPE(dreq_t)) req_pre_parsed ();
metaIntf #(.STYPE(dreq_t)) req_parsed ();

// Decoupling
`META_ASSIGN(s_req, req_pre_parsed)

// REG
always_ff @(posedge aclk) begin: PROC_REG
    if (aresetn == 1'b0) begin
        state_C <= ST_IDLE;
    end
    else begin
        state_C <= state_N;

        req_1_C <= req_1_N;
        req_2_C <= req_2_N;
    
        plast_C <= plast_N;
        plvaddr_C <= plvaddr_N;
        prvaddr_C <= prvaddr_N;
        plen_C <= plen_N;
    end
end

// NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			if(req_pre_parsed.valid) begin
                state_N = ST_PARSE_READ;
            end

        // Reads
        ST_PARSE_READ:
            state_N = ST_SEND_READ;

        ST_SEND_READ:
            if(req_parsed.ready) begin
                state_N = req_1_C.len ? ST_PARSE_READ : ST_IDLE;
            end

	endcase // state_C
end

// DP
always_comb begin: DP
    req_1_N = req_1_C;
    req_2_N = req_2_C;

    plast_N = plast_C;
    plen_N = plen_C;
    plvaddr_N = plvaddr_C;
    prvaddr_N = prvaddr_C;

    // Flow
    req_pre_parsed.ready = 1'b0;
    req_parsed.valid = 1'b0;

    // Data
    req_parsed.data = 0;

    req_parsed.data.req_1.opcode = RC_RDMA_READ_REQUEST;
    req_parsed.data.req_1.mode = RDMA_MODE_RAW;
    req_parsed.data.req_1.rdma = 1'b1;
    req_parsed.data.req_1.remote = 1'b1;
    req_parsed.data.req_1.pid = req_1_C.pid;
    req_parsed.data.req_1.vfid = req_1_C.vfid;
    req_parsed.data.req_1.dest = req_1_C.dest;
    req_parsed.data.req_1.last = plast_C;
    req_parsed.data.req_1.strm = req_1_C.strm;
    req_parsed.data.req_1.vaddr = prvaddr_C;
    req_parsed.data.req_1.len = plen_C;
    req_parsed.data.req_1.actv = 1'b1;
    req_parsed.data.req_1.host = req_1_C.host;
    req_parsed.data.req_1.offs = 0;

    req_parsed.data.req_2.vaddr = plvaddr_C;
    req_parsed.data.req_2.dest = req_2_C.dest;
    req_parsed.data.req_2.strm = req_2_C.strm;

    case(state_C)
        ST_IDLE: begin
            req_pre_parsed.ready = 1'b1;

            if(req_pre_parsed.valid) begin
                req_1_N = req_pre_parsed.data.req_1;
                req_2_N = req_pre_parsed.data.req_2;
            end
        end

        ST_PARSE_READ: begin
            prvaddr_N = req_1_C.vaddr;
            plvaddr_N = req_2_C.vaddr;

            if(req_1_C.len > RDMA_MAX_SINGLE_READ) begin
                req_1_N.vaddr = req_1_C.vaddr + RDMA_MAX_SINGLE_READ;
                req_2_N.vaddr = req_2_C.vaddr + RDMA_MAX_SINGLE_READ;
                
                req_1_N.len = req_1_C.len - RDMA_MAX_SINGLE_READ;

                plen_N = RDMA_MAX_SINGLE_READ;
                plast_N = 1'b0;
            end
            else begin
                req_1_N.len = 0;

                plen_N = req_1_C.len;
                plast_N = req_1_C.last;
            end
        end

        ST_SEND_READ: 
            req_parsed.valid = 1'b1;

    endcase
end

meta_reg #(.DATA_BITS($bits(dreq_t))) inst_reg_src  (.aclk(aclk), .aresetn(aresetn), .s_meta(req_parsed), .m_meta(m_req));

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_RDMA_PARSER_RD

`endif

endmodule