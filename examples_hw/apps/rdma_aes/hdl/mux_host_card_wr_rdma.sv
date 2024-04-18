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

module mux_host_card_wr_rdma (
    input  logic                              aclk,
    input  logic                              aresetn,

    input  logic [PID_BITS-1:0]               mux_ctid,
    metaIntf.s                                s_rq,
    metaIntf.m                                m_sq,

    AXI4SR.s                                  s_axis,
    AXI4SR.m                                  m_axis_host,
    AXI4SR.m                                  m_axis_card
);

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

// -- Meta
metaIntf #(.STYPE(req_t)) sq ();
queue_meta inst_queue_sq (.aclk(aclk), .aresetn(aresetn), .s_meta(sq), .m_meta(m_sq));

// -- Internal regs
logic host_C, host_N;
logic [BLEN_BITS-1:0] cnt_C, cnt_N;

// -- Internal signals
logic tr_done; 

// -- AXIS
AXI4SR axis_int ();

// ----------------------------------------------------------------------------------------------------------------------- 
// Mux
// ----------------------------------------------------------------------------------------------------------------------- 
always_comb begin
    if(state_C == ST_MUX) begin
        m_axis_host.tvalid  = host_C ? axis_int.tvalid : 1'b0;
        m_axis_host.tlast   = host_C ? axis_int.tlast : 1'b0;
        m_axis_host.tdata   = host_C ? axis_int.tdata : 0;
        m_axis_host.tkeep   = host_C ? axis_int.tkeep : 0;
        m_axis_host.tid     = host_C ? axis_int.tid : 0;

        m_axis_card.tvalid  = ~host_C ? axis_int.tvalid : 1'b0;
        m_axis_card.tlast   = ~host_C ? axis_int.tlast : 1'b0;
        m_axis_card.tdata   = ~host_C ? axis_int.tdata : 0;
        m_axis_card.tkeep   = ~host_C ? axis_int.tkeep : 0;
        m_axis_card.tid     = ~host_C ? axis_int.tid : 0;

        axis_int.tready = host_C ? m_axis_host.tready : m_axis_card.tready;
    end
    else begin
        m_axis_host.tvalid  = 1'b0;
        m_axis_host.tlast   = 1'b0;
        m_axis_host.tdata   = 0;
        m_axis_host.tkeep   = 0;
        m_axis_host.tid     = 0;

        m_axis_card.tvalid  = 1'b0;
        m_axis_card.tlast   = 1'b0;
        m_axis_card.tdata   = 0;
        m_axis_card.tkeep   = 0;
        m_axis_card.tid     = 0;

        axis_int.tready = 1'b0;
    end
end

// ----------------------------------------------------------------------------------------------------------------------- 
// State
// ----------------------------------------------------------------------------------------------------------------------- 
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
	state_C <= ST_IDLE;

    cnt_C <= 'X;
    host_C <= 'X;
end
else
    state_C <= state_N;

    cnt_C <= cnt_N;
    host_C <= host_N;
end

// -- NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			state_N = s_rq.valid && sq.ready ? ST_MUX : ST_IDLE;

        ST_MUX:
            state_N = tr_done ? (s_rq.valid && sq.ready ? ST_MUX : ST_IDLE) : ST_MUX;

	endcase // state_C
end

// -- DP
always_comb begin : DP
  cnt_N = cnt_C;
  host_N = host_C;

  // Transfer done
  tr_done = (cnt_C == 0) && (axis_int.tvalid & axis_int.tready);

  // Mux
  s_rq.ready = 1'b0;
  sq.valid = 1'b0;
  sq.data = s_rq.data;

  case(state_C)
    ST_IDLE: begin
      if(s_rq.valid && sq.ready) begin
        s_rq.ready = 1'b1;
        sq.valid = 1'b1;
        cnt_N = s_rq.data.len;
        host_N = (mux_ctid == s_rq.data.pid);
      end   
    end

    ST_MUX: begin
      if(tr_done) begin
        if(s_rq.valid && sq.ready) begin
            s_rq.ready = 1'b1;
            sq.valid = 1'b1;
            cnt_N = s_rq.data.len;
            host_N = (mux_ctid == s_rq.data.pid);
        end 
      end 
      else begin
        cnt_N = (axis_int.tvalid & axis_int.tready) ? cnt_C - 1 : cnt_C;
      end
    end

  endcase
end

axisr_data_fifo_512 inst_data_fifo (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(s_axis.tvalid),
    .s_axis_tready(s_axis.tready),
    .s_axis_tdata (s_axis.tdata),
    .s_axis_tkeep (s_axis.tkeep),
    .s_axis_tlast (s_axis.tlast),
    .s_axis_tid   (s_axis.tid),
    .m_axis_tvalid(axis_int.tvalid),
    .m_axis_tready(axis_int.tready),
    .m_axis_tdata (axis_int.tdata),
    .m_axis_tkeep (axis_int.tkeep),
    .m_axis_tlast (axis_int.tlast),
    .m_axis_tid   (axis_int.tid)
);

endmodule