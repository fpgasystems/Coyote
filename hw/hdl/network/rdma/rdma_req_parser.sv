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
 * @brief   RDMA command parser
 *
 * Multiplexing of the RDMA commands
 */
module rdma_req_parser #(
    parameter integer       ID_REG = 0,
    parameter integer       DBG = 0
) (
    input  logic            aclk,
    input  logic            aresetn,
    
    metaIntf.s              s_req,
    metaIntf.m              m_req,

    output logic [31:0]     used
);

// -- FSM
typedef enum logic[2:0]  {ST_IDLE, ST_PARSE_READ, ST_PARSE_WRITE_INIT, ST_PARSE_WRITE, ST_PARSE_SEND, ST_SEND_READ, ST_SEND_WRITE, ST_SEND_BASE} state_t;
logic [2:0] state_C, state_N;

// TODO: Needs interfaces, cleaning necessary

// Cmd 64
logic [RDMA_OPCODE_BITS-1:0] op_C, op_N;
logic [RDMA_QPN_BITS-1:0] qp_C, qp_N;
logic [0:0] host_C, host_N;
logic [0:0] mode_C, mode_N;
// Params 192
logic [RDMA_VADDR_BITS-1:0] lvaddr_C, lvaddr_N;
logic [RDMA_VADDR_BITS-1:0] rvaddr_C, rvaddr_N;
logic [RDMA_LEN_BITS-1:0] len_C, len_N;
logic [RDMA_PARAMS_BITS-1:0] params_C, params_N;

// Send
logic [RDMA_OPCODE_BITS-1:0] pop_C, pop_N;
logic [RDMA_LEN_BITS-1:0] plen_C, plen_N;
logic [RDMA_VADDR_BITS-1:0] plvaddr_C, plvaddr_N;
logic [RDMA_VADDR_BITS-1:0] prvaddr_C, prvaddr_N;

// Requests internal
metaIntf #(.STYPE(rdma_req_t)) req_pre_parsed ();
metaIntf #(.STYPE(rdma_req_t)) req_parsed ();
if(DBG == 1) begin



end
/*
ila_parser inst_ila_parser (
    .clk(aclk),
    .probe0(op_C),  // 5
    .probe1(qp_C[9:0]), // 10
    .probe2(host_C),
    .probe3(mode_C),
    .probe4(lvaddr_C), // 48
    .probe5(rvaddr_C), // 48
    .probe6(len_C), // 32
    .probe7(pop_C), // 5
    .probe8(plen_C), // 32
    .probe9(plvaddr_C), // 48
    .probe10(prvaddr_C), // 48
    .probe11(req_pre_parsed.valid),
    .probe12(req_pre_parsed.ready),
    .probe13(req_pre_parsed.data), // 544
    .probe14(req_parsed.valid),
    .probe15(req_parsed.ready),
    .probe16(req_parsed.data), // 544
    .probe17(state_C) // 3
);
*/
// Decoupling
axis_data_fifo_cnfg_rdma_544 inst_cmd_queue_in (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(s_req.valid),
  .s_axis_tready(s_req.ready),
  .s_axis_tdata(s_req.data),
  .m_axis_tvalid(req_pre_parsed.valid),
  .m_axis_tready(req_pre_parsed.ready),
  .m_axis_tdata(req_pre_parsed.data),
  .axis_wr_data_count(used)
);

logic [31:0] queue_used_out;

axis_data_fifo_cnfg_rdma_544 inst_cmd_queue_out (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(req_parsed.valid),
  .s_axis_tready(req_parsed.ready),
  .s_axis_tdata(req_parsed.data),
  .m_axis_tvalid(m_req.valid),
  .m_axis_tready(m_req.ready),
  .m_axis_tdata(m_req.data),
  .axis_wr_data_count(queue_used_out)
);

// REG
always_ff @(posedge aclk) begin: PROC_REG
    if (aresetn == 1'b0) begin
        state_C <= ST_IDLE;
    end
    else begin
        state_C <= state_N;
    
        op_C <= op_N;
        qp_C <= qp_N;
        host_C <= host_N;
        mode_C <= mode_N;
    
        lvaddr_C <= lvaddr_N;
        rvaddr_C <= rvaddr_N;
        len_C <= len_N;
        params_C <= params_N;
    
        pop_C <= pop_N;
        plen_C <= plen_N;
        plvaddr_C <= plvaddr_N;
        prvaddr_C <= prvaddr_N;
    end
end

// NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			if(req_pre_parsed.valid) begin
                if(req_pre_parsed.data.mode == RDMA_MODE_RAW) begin
                    state_N = ST_SEND_BASE;
                end
                else begin
                    case(req_pre_parsed.data.opcode)
                        APP_READ:
                            state_N = ST_PARSE_READ;
                        APP_WRITE:
                            state_N = ST_PARSE_WRITE_INIT;
                        APP_SEND:
                            state_N = ST_PARSE_SEND;
                        APP_IMMED:
                            state_N = ST_PARSE_SEND;

                        default: state_N = ST_IDLE;
                    endcase
                end
            end

        ST_PARSE_READ:
            state_N = ST_SEND_READ;
    
        ST_PARSE_WRITE_INIT: 
            state_N = ST_SEND_WRITE;

        ST_PARSE_WRITE:
            state_N = ST_SEND_WRITE;

        ST_PARSE_SEND:
            state_N = ST_SEND_READ;

        ST_SEND_READ:
            if(req_parsed.ready) begin
                state_N = ST_IDLE;
            end

        ST_SEND_WRITE:
            if(req_parsed.ready) begin
                state_N = len_C ? ST_PARSE_WRITE : ST_IDLE;
            end

        ST_SEND_BASE:
            if(req_parsed.ready) begin
                state_N = ST_IDLE;
            end

	endcase // state_C
end

// DP
always_comb begin: DP
    op_N = op_C;
    qp_N = qp_C;
    host_N = host_C;
    mode_N = mode_C;

    len_N = len_C;
    lvaddr_N = lvaddr_C;
    rvaddr_N = rvaddr_C;
    params_N = params_C;

    pop_N = pop_C;
    plen_N = plen_C;
    plvaddr_N = plvaddr_C;
    prvaddr_N = prvaddr_C;

    // Flow
    req_pre_parsed.ready = 1'b0;
    req_parsed.valid = 1'b0;

    // Data
    req_parsed.data = 0;
    req_parsed.data.opcode = pop_C;
    req_parsed.data.qpn = qp_C;
    req_parsed.data.host = host_C;
    req_parsed.data.mode = mode_C;
    req_parsed.data.last = 1'b1;
    req_parsed.data.msg[RDMA_LVADDR_OFFS+:RDMA_VADDR_BITS] = plvaddr_C;
    req_parsed.data.msg[RDMA_RVADDR_OFFS+:RDMA_VADDR_BITS] = prvaddr_C;
    req_parsed.data.msg[RDMA_LEN_OFFS+:RDMA_LEN_BITS] = plen_C;
    req_parsed.data.msg[RDMA_PARAMS_OFFS+:RDMA_PARAMS_BITS] = params_C;
    req_parsed.data.rsrvd = 0;

    case(state_C)
        ST_IDLE: begin
            req_pre_parsed.ready = 1'b1;

            qp_N = req_pre_parsed.data.qpn; // qp number
            host_N = req_pre_parsed.data.opcode != APP_IMMED; // host
            params_N = req_pre_parsed.data.msg[RDMA_PARAMS_OFFS+:RDMA_PARAMS_BITS]; // params

            if(req_pre_parsed.valid) begin
                if(req_pre_parsed.data.mode) begin
                    pop_N = req_pre_parsed.data.opcode; // op code              
                    plvaddr_N = req_pre_parsed.data.msg[RDMA_LVADDR_OFFS+:RDMA_VADDR_BITS]; // local vaddr
                    prvaddr_N = req_pre_parsed.data.msg[RDMA_RVADDR_OFFS+:RDMA_VADDR_BITS]; // remote vaddr
                    plen_N = req_pre_parsed.data.msg[RDMA_LEN_OFFS+:RDMA_LEN_BITS]; // length 
                end
                else begin
                    op_N = req_pre_parsed.data.opcode; // op code
                    lvaddr_N = req_pre_parsed.data.msg[RDMA_LVADDR_OFFS+:RDMA_VADDR_BITS]; // local vaddr
                    rvaddr_N = req_pre_parsed.data.msg[RDMA_RVADDR_OFFS+:RDMA_VADDR_BITS]; // remote vaddr
                    len_N = req_pre_parsed.data.msg[RDMA_LEN_OFFS+:RDMA_LEN_BITS]; // length 
                end
            end
        end

        ST_PARSE_READ: begin
            pop_N = RC_RDMA_READ_REQUEST;
            plen_N = len_C;
            plvaddr_N = lvaddr_C;
            prvaddr_N = rvaddr_C;
        end

        ST_PARSE_WRITE_INIT: begin
            plvaddr_N = lvaddr_C;
            prvaddr_N = rvaddr_C;
            
            if(len_C > PMTU_BYTES) begin
                lvaddr_N = lvaddr_C + PMTU_BYTES;
                rvaddr_N = rvaddr_C + PMTU_BYTES;
                len_N = len_C - PMTU_BYTES;

                pop_N = RC_RDMA_WRITE_FIRST;
                plen_N = PMTU_BYTES;              
            end
            else begin
                len_N = 0;

                pop_N = RC_RDMA_WRITE_ONLY;
                plen_N = len_C;
            end
        end

        ST_PARSE_WRITE: begin
            plvaddr_N = lvaddr_C;
            prvaddr_N = rvaddr_C;
            
            if(len_C > PMTU_BYTES) begin
                lvaddr_N = lvaddr_C + PMTU_BYTES;
                rvaddr_N = rvaddr_C + PMTU_BYTES;
                len_N = len_C - PMTU_BYTES;

                pop_N = RC_RDMA_WRITE_MIDDLE;
                plen_N = PMTU_BYTES;              
            end
            else begin
                len_N = 0;

                pop_N = RC_RDMA_WRITE_LAST;
                plen_N = len_C;
            end
        end
    
        ST_PARSE_SEND: begin
            pop_N = RC_SEND_ONLY;
            plen_N = len_C;
            plvaddr_N = lvaddr_C;
            prvaddr_N = rvaddr_C;
        end

        ST_SEND_READ: 
            if(req_parsed.ready) begin
                req_parsed.valid = 1'b1;
            end

        ST_SEND_WRITE:
            if(req_parsed.ready) begin
                req_parsed.valid = 1'b1;
            end

        ST_SEND_BASE:
            if(req_parsed.ready) begin
                req_parsed.valid = 1'b1;
            end

    endcase
end

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_RDMA_REQ_PARSER

`endif

endmodule