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
 * User multiplexer 
 */
module axis_mux_dma_sink #(
    parameter integer                       N_SPLIT_CHAN = N_CHAN, 
    parameter integer                       MUX_DATA_BITS = AXI_DATA_BITS
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    muxIntf.s                               mux,

    AXI4S.s                                 axis_in [N_SPLIT_CHAN],
    AXI4S.m                                 axis_out
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
logic [N_SPLIT_CHAN-1:0]                            axis_in_tvalid;
logic [N_SPLIT_CHAN-1:0]                            axis_in_tready;
logic [N_SPLIT_CHAN-1:0][MUX_DATA_BITS-1:0]         axis_in_tdata;
logic [N_SPLIT_CHAN-1:0][MUX_DATA_BITS/8-1:0]       axis_in_tkeep;
logic [N_SPLIT_CHAN-1:0]                            axis_in_tlast;

logic                                       axis_out_tvalid;
logic                                       axis_out_tready;
logic [MUX_DATA_BITS-1:0]                   axis_out_tdata;
logic [MUX_DATA_BITS/8-1:0]                 axis_out_tkeep;
logic                                       axis_out_tlast;

for(genvar i = 0; i < N_SPLIT_CHAN; i++) begin
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
    for(int i = 0; i < N_SPLIT_CHAN; i++) begin
        if(state_C == ST_MUX)
          axis_in_tready[i] = (id_C == i) ? axis_out_tready : 1'b0;      
        else 
          axis_in_tready[i] = 1'b0;
    end

    if(id_C < N_SPLIT_CHAN && state_C == ST_MUX) begin
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
// Memory subsystem 
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

  // Transfer done
  tr_done = (cnt_C == 0) && (axis_out_tvalid & axis_out_tready);

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
        cnt_N = (axis_out_tvalid & axis_out_tready) ? cnt_C - 1 : cnt_C;
      end
    end

  endcase
end

endmodule