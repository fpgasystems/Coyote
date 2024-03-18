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