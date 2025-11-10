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

module axis_mux_dma_src #(
    parameter integer                       N_SPLIT_CHAN = N_CHAN,  
    parameter integer                       MUX_DATA_BITS = AXI_DATA_BITS
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    muxIntf.s                               mux,

    AXI4S.s                                 axis_in,
    AXI4S.m                                 axis_out [N_SPLIT_CHAN]
);

// -- Constants
localparam integer BEAT_LOG_BITS = $clog2(MUX_DATA_BITS/8);
localparam integer BLEN_BITS = LEN_BITS - BEAT_LOG_BITS;
localparam integer N_SPLIT_CHAN_BITS = $clog2(N_SPLIT_CHAN);

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

// -- Internal regs
logic [N_SPLIT_CHAN_BITS-1:0] id_C, id_N;
logic [BLEN_BITS-1:0] cnt_C, cnt_N;
logic last_C, last_N;

// -- Internal signals
logic tr_done;

// ----------------------------------------------------------------------------------------------------------------------- 
// Mux 
// ----------------------------------------------------------------------------------------------------------------------- 

// -- interface loop issues => temp signals
logic                                           axis_in_tvalid;
logic                                           axis_in_tready;
logic [MUX_DATA_BITS-1:0]                       axis_in_tdata;
logic [MUX_DATA_BITS/8-1:0]                     axis_in_tkeep;
logic                                           axis_in_tlast;

logic [N_SPLIT_CHAN-1:0]                        axis_out_tvalid;
logic [N_SPLIT_CHAN-1:0]                        axis_out_tready;
logic [N_SPLIT_CHAN-1:0][MUX_DATA_BITS-1:0]     axis_out_tdata;
logic [N_SPLIT_CHAN-1:0][MUX_DATA_BITS/8-1:0]   axis_out_tkeep;
logic [N_SPLIT_CHAN-1:0]                        axis_out_tlast;

assign axis_in_tvalid = axis_in.tvalid;
assign axis_in_tdata = axis_in.tdata;
assign axis_in_tkeep = axis_in.tkeep;
assign axis_in_tlast = axis_in.tlast;
assign axis_in.tready = axis_in_tready;

for(genvar i = 0; i < N_SPLIT_CHAN; i++) begin
    assign axis_out[i].tvalid = axis_out_tvalid[i];
    assign axis_out[i].tdata = axis_out_tdata[i];
    assign axis_out[i].tkeep = axis_out_tkeep[i];
    assign axis_out[i].tlast = axis_out_tlast[i];
    assign axis_out_tready[i] = axis_out[i].tready;
end

// -- Mux
always_comb begin
    for(int i = 0; i < N_SPLIT_CHAN; i++) begin
        axis_out_tdata[i] = axis_in_tdata;
        axis_out_tkeep[i] = axis_in_tkeep;
        axis_out_tlast[i] = axis_in_tlast & last_C;
        if(state_C == ST_MUX) begin
            axis_out_tvalid[i] = (id_C == i) ? axis_in_tvalid : 1'b0;
        end
        else begin
            axis_out_tvalid[i] = 1'b0;
        end
    end

    if(id_C < N_SPLIT_CHAN && state_C == ST_MUX) 
        axis_in_tready = axis_out_tready[id_C];
    else 
        axis_in_tready = 1'b0;
end

// ----------------------------------------------------------------------------------------------------------------------- 
// FSM
// ----------------------------------------------------------------------------------------------------------------------- 

// -- REG
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
  state_C <= ST_IDLE;
  cnt_C <= 'X;
  id_C <= 'X;
  last_C <= 'X;
end
else
  state_C <= state_N;
  cnt_C <= cnt_N;
  id_C <= id_N;
  last_C <= last_N;
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
  id_N = id_C;
  last_N = last_C;

  // Transfer done
  tr_done = (cnt_C == 0) && (axis_in_tvalid & axis_in_tready);

  // Memory subsystem
  mux.ready = 1'b0;

  case(state_C)
    ST_IDLE: begin
      if(mux.valid) begin
        mux.ready = 1'b1;
        id_N = mux.data.chan;
        cnt_N = mux.data.len;
        last_N = mux.data.last;
      end   
    end

    ST_MUX: begin
      if(tr_done) begin
        if(mux.valid) begin
          mux.ready = 1'b1;
          id_N = mux.data.chan;
          cnt_N = mux.data.len;   
          last_N = mux.data.last;       
        end
      end 
      else begin
        cnt_N = (axis_in_tvalid & axis_in_tready) ? cnt_C - 1 : cnt_C;
      end
    end

  endcase
end

endmodule