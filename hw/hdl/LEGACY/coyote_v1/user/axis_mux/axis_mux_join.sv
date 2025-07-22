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