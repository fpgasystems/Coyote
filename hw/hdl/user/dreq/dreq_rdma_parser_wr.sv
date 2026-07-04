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
 * @brief   Network command parser
 *
 * Multiplexing of the network commands
 */
module dreq_rdma_parser_wr #(
    parameter integer       ID_REG = 0,
    parameter integer       DBG = 0
) (
    input  logic            aclk,
    input  logic            aresetn,
    
    metaIntf.s              s_req,
    metaIntf.m              m_req
);

// FSM
typedef enum logic[3:0]  {ST_IDLE, 
    ST_PARSE_WRITE_INIT, ST_PARSE_WRITE, ST_SEND_WRITE,
    ST_PARSE_SEND_INIT, ST_PARSE_SEND, ST_SEND_SEND,
    ST_SEND_BASE
} state_t;
logic [3:0] state_C, state_N;

req_t req_1_C, req_1_N;
req_t req_2_C, req_2_N;

logic [OPCODE_BITS-1:0] pop_C, pop_N;
logic [0:0] plast_C, plast_N;
logic [VADDR_BITS-1:0] plvaddr_C, plvaddr_N;
logic [VADDR_BITS-1:0] prvaddr_C, prvaddr_N;
logic [LEN_BITS-1:0] plen_C, plen_N;

// Requests internal
metaIntf #(.STYPE(dreq_t)) req_pre_parsed (.*);
metaIntf #(.STYPE(dreq_t)) req_parsed (.*);

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
    
        pop_C <= pop_N;
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
                if(req_pre_parsed.data.req_2.mode == RDMA_MODE_RAW) begin
                    state_N = ST_SEND_BASE;
                end
                else begin
                    case(req_pre_parsed.data.req_2.opcode)
                        APP_WRITE:
                            state_N = ST_PARSE_WRITE_INIT;
                        APP_SEND:
                            state_N = ST_PARSE_SEND_INIT;

                        default:
                            state_N = ST_IDLE;
                    endcase
                end
            end

        // Writes
        ST_PARSE_WRITE_INIT: 
            state_N = ST_SEND_WRITE;

        ST_PARSE_WRITE:
            state_N = ST_SEND_WRITE;

        ST_SEND_WRITE:
            if(req_parsed.ready) begin
                state_N = req_2_C.len ? ST_PARSE_WRITE : ST_IDLE;
            end

        // Sends
        ST_PARSE_SEND_INIT:
            state_N = ST_SEND_SEND;
        
        ST_PARSE_SEND:
            state_N = ST_SEND_SEND;
        
        ST_SEND_SEND:
            if(req_parsed.ready) begin
                state_N = req_2_C.len ? ST_PARSE_SEND : ST_IDLE;
            end

        // Base
        ST_SEND_BASE:
            if(req_parsed.ready) begin
                state_N = ST_IDLE;
            end

	endcase // state_C
end

// DP
always_comb begin: DP
    req_1_N = req_1_C;
    req_2_N = req_2_C;

    pop_N = pop_C;
    plast_N = plast_C;
    plen_N = plen_C;
    plvaddr_N = plvaddr_C;
    prvaddr_N = prvaddr_C;

    // Flow
    req_pre_parsed.ready = 1'b0;
    req_parsed.valid = 1'b0;

    // Data
    req_parsed.data = 0;

    req_parsed.data.req_1.opcode = pop_C;
    req_parsed.data.req_1.mode = RDMA_MODE_RAW;
    req_parsed.data.req_1.rdma = 1'b1;
    req_parsed.data.req_1.remote = 1'b1;
    req_parsed.data.req_1.pid = req_2_C.pid;
    req_parsed.data.req_1.vfid = req_2_C.vfid;
    req_parsed.data.req_1.dest = req_2_C.dest;
    req_parsed.data.req_1.last = plast_C;
    req_parsed.data.req_1.strm = req_2_C.strm;
    req_parsed.data.req_1.vaddr = prvaddr_C;
    req_parsed.data.req_1.len = plen_C;
    req_parsed.data.req_1.actv = 1'b1;
    req_parsed.data.req_1.host = req_2_C.host;
    req_parsed.data.req_1.offs = 0;
    
    req_parsed.data.req_2.vaddr = plvaddr_C;
    req_parsed.data.req_2.strm = req_1_C.strm;
    req_parsed.data.req_2.dest = req_1_C.dest;

    case(state_C)
        ST_IDLE: begin
            req_pre_parsed.ready = 1'b1;

            if(req_pre_parsed.valid) begin
                req_1_N = req_pre_parsed.data.req_1;
                req_2_N = req_pre_parsed.data.req_2;

                if(req_pre_parsed.data.req_2.mode == RDMA_MODE_RAW) begin
                    pop_N = req_pre_parsed.data.req_2.opcode;
                    plvaddr_N = req_pre_parsed.data.req_1.vaddr;
                    prvaddr_N = req_pre_parsed.data.req_2.vaddr;
                    plen_N = req_pre_parsed.data.req_2.len;
                    plast_N = req_pre_parsed.data.req_2.last;
                end
            end
        end

        // Writes
        ST_PARSE_WRITE_INIT: begin
            plvaddr_N = req_1_C.vaddr;
            prvaddr_N = req_2_C.vaddr;
            
            if(req_2_C.len > PMTU_BYTES) begin
                req_1_N.vaddr = req_1_C.vaddr + PMTU_BYTES;
                req_2_N.vaddr = req_2_C.vaddr + PMTU_BYTES;
                
                req_2_N.len = req_2_C.len - PMTU_BYTES;

                pop_N = RC_RDMA_WRITE_FIRST;
                plen_N = PMTU_BYTES;   
                plast_N = 1'b0;           
            end
            else begin
                req_2_N.len = 0;

                pop_N = RC_RDMA_WRITE_ONLY;
                plen_N = req_2_C.len;
                plast_N = req_2_C.last;
            end
        end

        ST_PARSE_WRITE: begin
            plvaddr_N = req_1_C.vaddr;
            prvaddr_N = req_2_C.vaddr;
            
            if(req_2_C.len > PMTU_BYTES) begin
                req_1_N.vaddr = req_1_C.vaddr + PMTU_BYTES;
                req_2_N.vaddr = req_2_C.vaddr + PMTU_BYTES;
                
                req_2_N.len = req_2_C.len - PMTU_BYTES;

                pop_N = RC_RDMA_WRITE_MIDDLE;
                plen_N = PMTU_BYTES;  
                plast_N = 1'b0;            
            end
            else begin
                req_2_N.len = 0;

                pop_N = RC_RDMA_WRITE_LAST;
                plen_N = req_2_C.len;
                plast_N = req_2_C.last;
            end
        end
    
        ST_SEND_WRITE:
            req_parsed.valid = 1'b1;
    
        // Sends
        ST_PARSE_SEND_INIT: begin
            plvaddr_N = req_1_C.vaddr;
            prvaddr_N = 0;
            
            if(req_2_C.len > PMTU_BYTES) begin
                req_1_N.vaddr = req_1_C.vaddr + PMTU_BYTES;
                
                req_2_N.len = req_2_C.len - PMTU_BYTES;

                pop_N = RC_SEND_FIRST;
                plen_N = PMTU_BYTES;   
                plast_N = 1'b0;           
            end
            else begin
                req_2_N.len = 0;

                pop_N = RC_SEND_ONLY;
                plen_N = req_2_C.len;
                plast_N = req_2_C.last;
            end
        end

        ST_PARSE_SEND: begin
            plvaddr_N = req_1_C.vaddr;
            prvaddr_N = 0;
            
            if(req_2_C.len > PMTU_BYTES) begin
                req_1_N.vaddr = req_1_C.vaddr + PMTU_BYTES;
                
                req_2_N.len = req_2_C.len - PMTU_BYTES;

                pop_N = RC_SEND_MIDDLE;
                plen_N = PMTU_BYTES;  
                plast_N = 1'b0;            
            end
            else begin
                req_2_N.len = 0;

                pop_N = RC_SEND_LAST;
                plen_N = req_2_C.len;
                plast_N = req_2_C.last;
            end
        end

        ST_SEND_SEND:
            req_parsed.valid = 1'b1;
        
        // Base
        ST_SEND_BASE:
            req_parsed.valid = 1'b1;

    endcase
end

meta_reg #(.DATA_BITS($bits(dreq_t))) inst_reg_src  (.aclk(aclk), .aresetn(aresetn), .s_meta(req_parsed), .m_meta(m_req));

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_RDMA_PARSER_WR

`endif

endmodule