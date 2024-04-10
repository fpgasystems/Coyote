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
 * @brief   User logic multiplexer read
 *
 *
 */
module axis_mux_user_rq #(
    parameter integer N_DESTS = 1
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    metaIntf.s                              s_rq,
    metaIntf.m                              m_rq,

    AXI4S.s                                 s_axis,

    AXI4SR.m                                m_axis_resp [N_DESTS],
    AXI4SR.m                                m_axis_recv [N_DESTS]
);

// -- Constants
localparam integer N_DESTS_BITS = clog2s(N_DESTS);

// -- FSM
typedef enum logic[1:0]  {ST_IDLE, ST_MUX_RESP, ST_MUX_RECV} state_t;
logic [1:0] state_C, state_N;

// -- Internal regs
logic [N_DESTS_BITS-1:0] dest_C, dest_N;
logic [BLEN_BITS-1:0] cnt_C, cnt_N;
logic [PID_BITS-1:0] pid_C, pid_N;

// -- Internal signals
logic tr_done;
logic resp;

metaIntf #(.STYPE(req_t)) m_rq_int ();
metaIntf #(.STYPE(logic[1+BLEN_BITS-1:0])) mux [N_DESTS] ();

// ----------------------------------------------------------------------------------------------------------------------- 
// IO
// ----------------------------------------------------------------------------------------------------------------------- 
logic                                       s_axis_tvalid;
logic                                       s_axis_tready;
logic [AXI_DATA_BITS-1:0]                   s_axis_tdata;
logic [AXI_DATA_BITS/8-1:0]                 s_axis_tkeep;
logic                                       s_axis_tlast;

logic [N_DESTS-1:0]                         m_axis_resp_tvalid;
logic [N_DESTS-1:0]                         m_axis_resp_tready;
logic [N_DESTS-1:0][AXI_DATA_BITS-1:0]      m_axis_resp_tdata;
logic [N_DESTS-1:0][AXI_DATA_BITS/8-1:0]    m_axis_resp_tkeep;
logic [N_DESTS-1:0]                         m_axis_resp_tlast;
logic [N_DESTS-1:0][PID_BITS-1:0]           m_axis_resp_tid;

logic [N_DESTS-1:0]                         m_axis_recv_tvalid;
logic [N_DESTS-1:0]                         m_axis_recv_tready;
logic [N_DESTS-1:0][AXI_DATA_BITS-1:0]      m_axis_recv_tdata;
logic [N_DESTS-1:0][AXI_DATA_BITS/8-1:0]    m_axis_recv_tkeep;
logic [N_DESTS-1:0]                         m_axis_recv_tlast;
logic [N_DESTS-1:0][PID_BITS-1:0]           m_axis_recv_tid;

assign s_axis_tvalid = s_axis.tvalid;
assign s_axis_tdata  = s_axis.tdata;
assign s_axis_tkeep  = s_axis.tkeep;
assign s_axis_tlast  = s_axis.tlast;
assign s_axis.tready = s_axis_tready;

for(genvar i = 0; i < N_DESTS; i++) begin
    assign m_axis_resp[i].tvalid = m_axis_resp_tvalid[i];
    assign m_axis_resp[i].tdata  = m_axis_resp_tdata[i];
    assign m_axis_resp[i].tkeep  = m_axis_resp_tkeep[i];
    assign m_axis_resp[i].tlast  = m_axis_resp_tlast[i];
    assign m_axis_resp[i].tid    = m_axis_resp_tid[i];
    assign m_axis_resp_tready[i] = m_axis_resp[i].tready;

    assign m_axis_recv[i].tvalid = m_axis_recv_tvalid[i];
    assign m_axis_recv[i].tdata  = m_axis_recv_tdata[i];
    assign m_axis_recv[i].tkeep  = m_axis_recv_tkeep[i];
    assign m_axis_recv[i].tlast  = m_axis_recv_tlast[i];
    assign m_axis_recv[i].tid    = m_axis_recv_tid[i];
    assign m_axis_recv_tready[i] = m_axis_recv[i].tready;
end

// ----------------------------------------------------------------------------------------------------------------------- 
// Mux
// ----------------------------------------------------------------------------------------------------------------------- 
always_comb begin
    for(int i = 0; i < N_DESTS; i++) begin
        m_axis_resp_tdata[i] = s_axis_tdata;
        m_axis_resp_tkeep[i] = s_axis_tkeep;
        m_axis_resp_tlast[i] = s_axis_tlast;
        m_axis_resp_tid[i]   = pid_C;

        m_axis_recv_tdata[i] = s_axis_tdata;
        m_axis_recv_tkeep[i] = s_axis_tkeep;
        m_axis_recv_tlast[i] = s_axis_tlast;
        m_axis_recv_tid[i]   = pid_C;

        if(state_C == ST_MUX_RESP) begin
            m_axis_resp_tvalid[i] = (dest_C == i) ? s_axis_tvalid : 1'b0;
            m_axis_recv_tvalid[i] = 1'b0;
        end
        else if(state_C == ST_MUX_RECV) begin
            m_axis_resp_tvalid[i] = 1'b0;
            m_axis_recv_tvalid[i] = (dest_C == i) ? s_axis_tvalid : 1'b0;
        end
        else begin
            m_axis_resp_tvalid[i] = 1'b0;
            m_axis_recv_tvalid[i] = 1'b0;
        end
    end

    if(dest_C < N_DESTS && state_C == ST_MUX_RESP) 
        s_axis_tready = m_axis_resp_tready[dest_C];
    else if(dest_C < N_DESTS && state_C == ST_MUX_RECV)
        s_axis_tready = m_axis_recv_tready[dest_C];
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
			state_N = (s_rq.valid & m_rq_int.ready) ? (resp ? ST_MUX_RESP : ST_MUX_RECV) : ST_IDLE;

        ST_MUX_RESP:
            state_N = tr_done ? (s_rq.valid & m_rq_int.ready ? (resp ? ST_MUX_RESP : ST_MUX_RECV) : ST_IDLE) : ST_MUX_RESP;

        ST_MUX_RECV:
            state_N = tr_done ? (s_rq.valid & m_rq_int.ready ? (resp ? ST_MUX_RESP : ST_MUX_RECV) : ST_IDLE) : ST_MUX_RECV;

	endcase // state_C
end

// -- DP
always_comb begin : DP
  cnt_N = cnt_C;
  dest_N = dest_C;
  pid_N = pid_C;

  // Transfer done
  tr_done = (cnt_C == 0) && (s_axis_tvalid & s_axis_tready);
  resp = is_opcode_rd_resp(s_rq.data.opcode);

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

    ST_MUX_RESP: begin
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
    
    ST_MUX_RECV: begin
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

meta_queue #(.DATA_BITS($bits(req_t))) inst_out_reg  (.aclk(aclk), .aresetn(aresetn), .s_meta(m_rq_int), .m_meta(m_rq));

endmodule