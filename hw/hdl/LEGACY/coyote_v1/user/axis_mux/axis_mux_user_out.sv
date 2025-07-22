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
 * @brief   User logic multiplexer out
 *
 *
 */
module axis_mux_user_out (
    input  logic                            aclk,
    input  logic                            aresetn,

    metaIntf.s                              mux,

    AXI4SR.s                                s_axis_resp,
    AXI4SR.s                                s_axis_recv,
    AXI4SR.m                                m_axis
);

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

// -- Internal regs
logic [BLEN_BITS-1:0] cnt_C, cnt_N;
logic resp_C, resp_N;

// -- Internal signals
logic tr_done;

// ----------------------------------------------------------------------------------------------------------------------- 
// Mux
// ----------------------------------------------------------------------------------------------------------------------- 
always_comb begin
    if(state_C == ST_MUX) begin
        m_axis.tdata = resp_C ? s_axis_resp.tdata : s_axis_recv.tdata;
        m_axis.tkeep = resp_C ? s_axis_resp.tkeep : s_axis_recv.tkeep;
        m_axis.tlast = resp_C ? s_axis_resp.tlast : s_axis_recv.tlast;
        m_axis.tid   = resp_C ? s_axis_resp.tid   : s_axis_recv.tid;
        m_axis.tvalid  = resp_C ? s_axis_resp.tvalid   : s_axis_recv.tvalid;

        s_axis_resp.tready = resp_C ? m_axis.tready : 1'b0;
        s_axis_recv.tready = resp_C ? 1'b0 : m_axis.tready;
    end
    else begin
        m_axis.tdata = 0;
        m_axis.tkeep = 0;
        m_axis.tlast = 1'b0;
        m_axis.tid   = 0;
        m_axis.tvalid = 1'b0;

        s_axis_resp.tready = 1'b0;
        s_axis_recv.tready = 1'b0;
    end
end

// ----------------------------------------------------------------------------------------------------------------------- 
// State
// ----------------------------------------------------------------------------------------------------------------------- 
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
    state_C <= ST_IDLE;

    cnt_C <= 'X;
    resp_C <= 'X;
end
else
    state_C <= state_N;
  
    cnt_C <= cnt_N;
    resp_C <= resp_N;
end

// -- NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			state_N = mux.valid ? ST_MUX : ST_IDLE;

        ST_MUX:
            state_N = tr_done ? (mux.valid ? ST_MUX : ST_IDLE) : ST_MUX;

	endcase // state_C
end

// -- DP
always_comb begin : DP
  cnt_N = cnt_C;
  resp_N = resp_C;

  // Transfer done
  tr_done = (cnt_C == 0) && (m_axis.tvalid & m_axis.tready);

  // Mux
  mux.ready = 1'b0;

  case(state_C)
    ST_IDLE: begin
      if(mux.valid) begin
        mux.ready = 1'b1;
        cnt_N = mux.data[BLEN_BITS-1:0];
        resp_N = mux.data[BLEN_BITS];
      end   
    end

    ST_MUX: begin
      if(tr_done) begin
        if(mux.valid) begin
            mux.ready = 1'b1;
            cnt_N = mux.data[BLEN_BITS-1:0];
            resp_N = mux.data[BLEN_BITS];
        end  
      end 
      else begin
        cnt_N = (m_axis.tvalid & m_axis.tready) ? cnt_C - 1 : cnt_C;
      end
    end

  endcase
end

endmodule