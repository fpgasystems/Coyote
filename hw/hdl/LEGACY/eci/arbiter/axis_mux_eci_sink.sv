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
 * User multiplexer 
 */
module axis_mux_eci_sink #(
    parameter integer MUX_DATA_BITS = ECI_DATA_BITS
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    muxIntf.m                               mux_user,

    AXI4S.s                                 axis_in [N_CHAN],
    AXI4S.m                                 axis_out
);

// -- Constants
localparam integer BEAT_LOG_BITS = $clog2(MUX_DATA_BITS/8);
localparam integer BLEN_BITS = LEN_BITS - BEAT_LOG_BITS;

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

// -- Internal regs
logic [N_CHAN_BITS-1:0] id_C, id_N;
logic [BLEN_BITS-1:0] cnt_C, cnt_N;
logic ctl_C, ctl_N;

// -- Internal signals
logic tr_done; 

// ----------------------------------------------------------------------------------------------------------------------- 
// Mux 
// ----------------------------------------------------------------------------------------------------------------------- 
// -- interface loop issues => temp signals
logic [N_CHAN-1:0]                            axis_in_tvalid;
logic [N_CHAN-1:0]                            axis_in_tready;
logic [N_CHAN-1:0][MUX_DATA_BITS-1:0]         axis_in_tdata;
logic [N_CHAN-1:0][MUX_DATA_BITS/8-1:0]       axis_in_tkeep;
logic [N_CHAN-1:0]                            axis_in_tlast;

logic                                       axis_out_tvalid;
logic                                       axis_out_tready;
logic [MUX_DATA_BITS-1:0]                   axis_out_tdata;
logic [MUX_DATA_BITS/8-1:0]                 axis_out_tkeep;
logic                                       axis_out_tlast;

for(genvar i = 0; i < N_CHAN; i++) begin
    assign axis_in_tvalid[i] = axis_in[i].tvalid;
    assign axis_in_tdata[i] = axis_in[i].tdata;
    assign axis_in_tkeep[i] = axis_in[i].tkeep;
    assign axis_in_tlast[i] = axis_in[i].tlast;
    assign axis_in[i].tready = axis_in_tready[i];
end

assign axis_out.tvalid = axis_out_tvalid;
assign axis_out.tdata = axis_out_tdata;
assign axis_out.tkeep = axis_out_tkeep;
assign axis_out.tlast = axis_out_tlast;
assign axis_out_tready = axis_out.tready;

// -- Mux
always_comb begin
    for(int i = 0; i < N_CHAN; i++) begin
        if(state_C == ST_MUX)
          axis_in_tready[i] = (id_C == i) ? axis_out_tready : 1'b0;      
        else 
          axis_in_tready[i] = 1'b0;
    end

    if(id_C < N_CHAN && state_C == ST_MUX) begin
        axis_out_tdata = axis_in_tdata[id_C];
        axis_out_tkeep = axis_in_tkeep[id_C];
        axis_out_tlast = (cnt_C == 0);
        axis_out_tvalid = axis_in_tvalid[id_C];
    end
    else begin
        axis_out_tdata = 0;
        axis_out_tkeep = 0;
        axis_out_tlast = 1'b0;
        axis_out_tvalid = 1'b0;
    end
end

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Memory subsystem 
// ----------------------------------------------------------------------------------------------------------------------- 
// -- REG
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
	state_C <= ST_IDLE;
  cnt_C <= 'X;
  id_C <= 'X;
  ctl_C <= 'X;
end
else
  state_C <= state_N;
  cnt_C <= cnt_N;
  id_C <= id_N;
  ctl_C <= ctl_N;
end

// -- NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			state_N = mux_user.ready ? ST_MUX : ST_IDLE;

    ST_MUX:
      state_N = tr_done ? (mux_user.ready ? ST_MUX : ST_IDLE) : ST_MUX;

	endcase // state_C
end

// -- DP
always_comb begin : DP
  cnt_N = cnt_C;
  id_N = id_C;

  // Transfer done
  tr_done = (cnt_C == 0) && (axis_out_tvalid & axis_out_tready);

  // Memory subsystem
  mux_user.valid = 1'b0;

  case(state_C)
    ST_IDLE: begin
      if(mux_user.ready) begin
        mux_user.valid = 1'b1;
        id_N = mux_user.vfid;
        cnt_N = mux_user.len;   
        ctl_N = mux_user.ctl;
      end   
    end

    ST_MUX: begin
      if(tr_done) begin
        if(mux_user.ready) begin
          mux_user.valid = 1'b1;
          id_N = mux_user.vfid;
          cnt_N = mux_user.len;    
          ctl_N = mux_user.ctl;
        end
      end 
      else begin
        cnt_N = (axis_out_tvalid & axis_out_tready) ? cnt_C - 1 : cnt_C;
      end
    end

  endcase
end

endmodule