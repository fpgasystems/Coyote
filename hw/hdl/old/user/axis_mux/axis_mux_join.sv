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


module axis_mux_join (
    input  logic                              aclk,
    input  logic                              aresetn,

    metaIntf.s                                s_rq,
    metaIntf.m                                m_sq,

    AXI4SR.s                                  s_axis_recv,
    AXI4SR.s                                  s_axis_resp,
    AXI4SR.m                                  m_axis
);

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

// -- Meta
metaIntf #(.STYPE(req_t)) sq ();
queue_meta inst_queue_rq (.aclk(aclk), .aresetn(aresetn), .s_meta(sq), .m_meta(m_sq));

// -- Internal regs
logic rd_C, rd_N;
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
        axis_int.tvalid = rd_C ? s_axis_resp.tvalid : s_axis_recv.tvalid;
        axis_int.tlast = rd_C ?  s_axis_resp.tlast : s_axis_recv.tlast;
        axis_int.tkeep = rd_C ?  s_axis_resp.tkeep : s_axis_recv.tkeep;
        axis_int.tdata = rd_C ?  s_axis_resp.tdata : s_axis_recv.tdata;
        axis_int.tid = rd_C   ?  s_axis_resp.tid : s_axis_recv.tid;

        s_axis_recv.tready = rd_C ? 1'b0 : axis_int.tready;
        s_axis_resp.tready = rd_C ? axis_int.tready : 1'b0;
    end
    else begin
        axis_int.tvalid = 1'b0;
        axis_int.tlast = 1'b0;
        axis_int.tkeep = 0;
        axis_int.tdata = 0;
        axis_int.tid = 0;
        
        s_axis_recv.tready = 1'b0;
        s_axis_resp.tready = 1'b0;
    end
end

// ----------------------------------------------------------------------------------------------------------------------- 
// State
// ----------------------------------------------------------------------------------------------------------------------- 
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
	state_C <= ST_IDLE;

    cnt_C <= 'X;
    rd_C <= 'X;
end
else
    state_C <= state_N;

    cnt_C <= cnt_N;
    rd_C <= rd_N;
end

// -- NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			state_N = s_rq.valid & sq.ready ? ST_MUX : ST_IDLE;

        ST_MUX:
            state_N = tr_done ? (s_rq.valid & sq.ready ? ST_MUX : ST_IDLE) : ST_MUX;

	endcase // state_C
end

// -- DP
always_comb begin : DP
  cnt_N = cnt_C;
  rd_N = rd_C;

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
        rd_N = is_opcode_rd_req(s_rq.data.opcode);
      end   
    end

    ST_MUX: begin
      if(tr_done) begin
        if(s_rq.valid && sq.ready) begin
            s_rq.ready = 1'b1;
            sq.valid = 1'b1;
            cnt_N = s_rq.data.len;
            rd_N = is_opcode_rd_req(s_rq.data.opcode);
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
    .s_axis_tvalid(axis_int.tvalid),
    .s_axis_tready(axis_int.tready),
    .s_axis_tdata (axis_int.tdata),
    .s_axis_tkeep (axis_int.tkeep),
    .s_axis_tlast (axis_int.tlast),
    .s_axis_tid   (axis_int.tid),
    .m_axis_tvalid(m_axis.tvalid),
    .m_axis_tready(m_axis.tready),
    .m_axis_tdata (m_axis.tdata),
    .m_axis_tkeep (m_axis.tkeep),
    .m_axis_tlast (m_axis.tlast),
    .m_axis_tid   (m_axis.tid)
);

endmodule