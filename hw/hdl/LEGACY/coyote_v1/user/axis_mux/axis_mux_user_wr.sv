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
 * @brief   User logic multiplexer write
 *
 *
 */
module axis_mux_user_wr #(
    parameter integer N_DESTS = 1
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    metaIntf.s                              mux,

    AXI4S.s                                 s_axis [N_DESTS],
    AXI4S.m                                 m_axis
);

// -- Constants
localparam integer N_DESTS_BITS = clog2s(N_DESTS);

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

// -- Internal regs
logic [N_DESTS_BITS-1:0] dest_C, dest_N;
logic [BLEN_BITS-1:0] cnt_C, cnt_N;

// -- Internal signals
logic tr_done; 

// ----------------------------------------------------------------------------------------------------------------------- 
// IO
// ----------------------------------------------------------------------------------------------------------------------- 
logic [N_DESTS-1:0]                     s_axis_tvalid;
logic [N_DESTS-1:0]                     s_axis_tready;
logic [N_DESTS-1:0][AXI_DATA_BITS-1:0]      s_axis_tdata;
logic [N_DESTS-1:0][AXI_DATA_BITS/8-1:0]    s_axis_tkeep;
logic [N_DESTS-1:0]                     s_axis_tlast;

logic                                   m_axis_tvalid;
logic                                   m_axis_tready;
logic [AXI_DATA_BITS-1:0]                   m_axis_tdata;
logic [AXI_DATA_BITS/8-1:0]                 m_axis_tkeep;
logic                                   m_axis_tlast;

for(genvar i = 0; i < N_DESTS; i++) begin
    assign s_axis_tvalid[i] = s_axis[i].tvalid;
    assign s_axis_tdata[i] = s_axis[i].tdata;
    assign s_axis_tkeep[i] = s_axis[i].tkeep;
    assign s_axis_tlast[i] = s_axis[i].tlast;
    assign s_axis[i].tready = s_axis_tready[i];
end

assign m_axis.tvalid = m_axis_tvalid;
assign m_axis.tdata = m_axis_tdata;
assign m_axis.tkeep = m_axis_tkeep;
assign m_axis.tlast = m_axis_tlast;
assign m_axis_tready = m_axis.tready;

// ----------------------------------------------------------------------------------------------------------------------- 
// Mux
// ----------------------------------------------------------------------------------------------------------------------- 
always_comb begin
    for(int i = 0; i < N_DESTS; i++) begin
        if(state_C == ST_MUX)
          s_axis_tready[i] = (dest_C == i) ? m_axis_tready : 1'b0;      
        else 
          s_axis_tready[i] = 1'b0;
    end

    if(dest_C < N_DESTS && state_C == ST_MUX) begin
        m_axis_tdata = s_axis_tdata[dest_C];
        m_axis_tkeep = s_axis_tkeep[dest_C];
        m_axis_tlast = s_axis_tlast[dest_C];
        m_axis_tvalid = s_axis_tvalid[dest_C];
    end
    else begin
        m_axis_tdata = 0;
        m_axis_tkeep = 0;
        m_axis_tlast = 1'b0;
        m_axis_tvalid = 1'b0;
    end
end

// ----------------------------------------------------------------------------------------------------------------------- 
// State
// ----------------------------------------------------------------------------------------------------------------------- 
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
	state_C <= ST_IDLE;

    cnt_C <= 'X;
    dest_C <= 'X;
end
else
  state_C <= state_N;

  cnt_C <= cnt_N;
  dest_C <= dest_N;
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
  dest_N = dest_C;

  // Transfer done
  tr_done = (cnt_C == 0) && (m_axis_tvalid & m_axis_tready);

  // Mux
  mux.ready = 1'b0;

  case(state_C)
    ST_IDLE: begin
      if(mux.valid) begin
        mux.ready = 1'b1;
        cnt_N = mux.data.len;
        dest_N = mux.data.dest[N_DESTS_BITS-1:0];
      end   
    end

    ST_MUX: begin
      if(tr_done) begin
        if(mux.valid) begin
            mux.ready = 1'b1;
            cnt_N = mux.data.len;
            dest_N = mux.data.dest[N_DESTS_BITS-1:0];
        end 
      end 
      else begin
        cnt_N = (m_axis_tvalid & m_axis_tready) ? cnt_C - 1 : cnt_C;
      end
    end

  endcase
end

endmodule