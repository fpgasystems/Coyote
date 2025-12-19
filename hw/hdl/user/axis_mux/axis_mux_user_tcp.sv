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
 * @brief   User logic multiplexer read
 *
 *
 */
module axis_mux_user_tcp #(
    parameter integer N_DESTS = 1
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    muxIntf.s                               s_rq,
    muxIntf.m                               m_rq,

    AXI4S.s                                 s_axis,
    AXI4SR.m                                m_axis [N_DESTS]
);

// -- Constants
localparam integer N_DESTS_BITS = clog2s(N_DESTS);

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

// -- Internal regs
logic [N_DESTS_BITS-1:0] dest_C, dest_N;
logic [BLEN_BITS-1:0] cnt_C, cnt_N;
logic [PID_BITS-1:0] pid_C, pid_N;

// -- Internal signals
logic tr_done;

metaIntf #(.STYPE(req_t)) m_rq_int (.*);

// ----------------------------------------------------------------------------------------------------------------------- 
// IO
// ----------------------------------------------------------------------------------------------------------------------- 
logic                                   s_axis_tvalid;
logic                                   s_axis_tready;
logic [AXI_DATA_BITS-1:0]                   s_axis_tdata;
logic [AXI_DATA_BITS/8-1:0]                 s_axis_tkeep;
logic                                   s_axis_tlast;

logic [N_DESTS-1:0]                     m_axis_tvalid;
logic [N_DESTS-1:0]                     m_axis_tready;
logic [N_DESTS-1:0][AXI_DATA_BITS-1:0]      m_axis_tdata;
logic [N_DESTS-1:0][AXI_DATA_BITS/8-1:0]    m_axis_tkeep;
logic [N_DESTS-1:0]                     m_axis_tlast;
logic [N_DESTS-1:0][PID_BITS-1:0]       m_axis_tid;

assign s_axis_tvalid = s_axis.tvalid;
assign s_axis_tdata  = s_axis.tdata;
assign s_axis_tkeep  = s_axis.tkeep;
assign s_axis_tlast  = s_axis.tlast;
assign s_axis.tready = s_axis_tready;

for(genvar i = 0; i < N_DESTS; i++) begin
    assign m_axis[i].tvalid = m_axis_tvalid[i];
    assign m_axis[i].tdata  = m_axis_tdata[i];
    assign m_axis[i].tkeep  = m_axis_tkeep[i];
    assign m_axis[i].tlast  = m_axis_tlast[i];
    assign m_axis[i].tid    = m_axis_tid[i];
    assign m_axis_tready[i] = m_axis[i].tready;
end

// ----------------------------------------------------------------------------------------------------------------------- 
// Mux
// ----------------------------------------------------------------------------------------------------------------------- 
always_comb begin
    for(int i = 0; i < N_DESTS; i++) begin
        m_axis_tdata[i] = s_axis_tdata;
        m_axis_tkeep[i] = s_axis_tkeep;
        m_axis_tlast[i] = s_axis_tlast;
        m_axis_tid[i]   = pid_C;

        if(state_C == ST_MUX) begin
            m_axis_tvalid[i] = (dest_C == i) ? s_axis_tvalid : 1'b0;
        end
        else begin
            m_axis_tvalid[i] = 1'b0;
        end
    end

    if(dest_C < N_DESTS && state_C == ST_MUX) 
        s_axis_tready = m_axis_tready[dest_C];
    else
        s_axis_tready = 1'b0;
end

// ----------------------------------------------------------------------------------------------------------------------- 
// State
// ----------------------------------------------------------------------------------------------------------------------- 
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
    state_C <= ST_IDLE;

    cnt_C <= 'X;
    dest_C <= 'X;
    pid_C <= 'X;
end
else
    state_C <= state_N;
  
    cnt_C <= cnt_N;
    dest_C <= dest_N;
    pid_C <= pid_N;
end

// -- NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			state_N = (s_rq.valid & m_rq_int.ready) ? ST_MUX : ST_IDLE;

        ST_MUX:
            state_N = tr_done ? (s_rq.valid & m_rq_int.ready ? ST_MUX : ST_IDLE) : ST_MUX;

	endcase // state_C
end

// -- DP
always_comb begin : DP
  cnt_N = cnt_C;
  dest_N = dest_C;
  pid_N = pid_C;

  // Transfer done
  tr_done = (cnt_C == 0) && (s_axis_tvalid & s_axis_tready);

  // IO
  s_rq.ready = 1'b0;
  m_rq_int.valid = 1'b0;
  m_rq_int.data = s_rq.data;

  case(state_C)
    ST_IDLE: begin
      if(s_rq.valid & m_rq_int.ready) begin
        s_rq.ready = 1'b1;
        m_rq_int.valid = 1'b1;
        pid_N = s_rq.data.pid;
        cnt_N = (s_rq.data.len - 1) >> BEAT_LOG_BITS;
        dest_N = s_rq.data.dest;
      end   
    end

    ST_MUX: begin
      if(tr_done) begin
        if(s_rq.valid & m_rq_int.ready) begin
            s_rq.ready = 1'b1;
            m_rq_int.valid = 1'b1;
            pid_N = s_rq.data.pid;
            cnt_N = (s_rq.data.len - 1) >> BEAT_LOG_BITS;
            dest_N = s_rq.data.dest;
        end  
      end 
      else begin
        cnt_N = (s_axis_tvalid & s_axis_tready) ? cnt_C - 1 : cnt_C;
      end
    end

  endcase
end

meta_queue #(.QDEPTH(32)) inst_out_reg  (.aclk(aclk), .aresetn(aresetn), .s_meta(m_rq_int), .m_meta(m_rq));

endmodule