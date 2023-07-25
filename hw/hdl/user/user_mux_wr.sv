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
 * @brief   User logic multiplexer sink
 *
 * Sinks multiple data stream into one XDMA stream.
 *
 *  @param DATA_BITS    Data bus size
 */
module user_mux_wr #(
    parameter integer DATA_BITS = AXI_DATA_BITS,
    parameter integer N_ID = N_STRM_AXI
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    metaIntf.s                              mux,

    AXI4SR.s                                s_axis [N_ID],
    AXI4SR.m                                m_axis
);

// -- Constants
localparam integer BEAT_LOG_BITS = $clog2(DATA_BITS/8);
localparam integer BLEN_BITS = LEN_BITS - BEAT_LOG_BITS;
localparam integer N_ID_BITS = clog2s(N_ID);

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

// -- Internal regs
logic [N_ID_BITS-1:0] dest_C, dest_N;
logic [BLEN_BITS-1:0] cnt_C, cnt_N;

// -- Internal signals
logic tr_done; 

// ----------------------------------------------------------------------------------------------------------------------- 
// Mux 
// ----------------------------------------------------------------------------------------------------------------------- 
// -- interface loop issues => temp signals
logic [N_ID-1:0]                            s_axis_tvalid;
logic [N_ID-1:0]                            s_axis_tready;
logic [N_ID-1:0][DATA_BITS-1:0]             s_axis_tdata;
logic [N_ID-1:0][DATA_BITS/8-1:0]           s_axis_tkeep;
logic [N_ID-1:0][PID_BITS-1:0]              s_axis_tid;
logic [N_ID-1:0]                            s_axis_tlast;

logic                                       m_axis_tvalid;
logic                                       m_axis_tready;
logic [DATA_BITS-1:0]                       m_axis_tdata;
logic [DATA_BITS/8-1:0]                     m_axis_tkeep;
logic [PID_BITS-1:0]                        m_axis_tid;
logic                                       m_axis_tlast;

for(genvar i = 0; i < N_ID; i++) begin
    assign s_axis_tvalid[i] = s_axis[i].tvalid;
    assign s_axis_tdata[i] = s_axis[i].tdata;
    assign s_axis_tkeep[i] = s_axis[i].tkeep;
    assign s_axis_tid[i] = s_axis[i].tid;
    assign s_axis_tlast[i] = s_axis[i].tlast;
    assign s_axis[i].tready = s_axis_tready[i];
end

assign m_axis.tvalid = m_axis_tvalid;
assign m_axis.tdata = m_axis_tdata;
assign m_axis.tkeep = m_axis_tkeep;
assign m_axis.tid = m_axis_tid;
assign m_axis.tlast = m_axis_tlast;
assign m_axis_tready = m_axis.tready;

// -- Mux
always_comb begin
    for(int i = 0; i < N_ID; i++) begin
        if(state_C == ST_MUX)
          s_axis_tready[i] = (dest_C == i) ? m_axis_tready : 1'b0;      
        else 
          s_axis_tready[i] = 1'b0;
    end

    if(dest_C < N_ID && state_C == ST_MUX) begin
        m_axis_tdata = s_axis_tdata[dest_C];
        m_axis_tkeep = s_axis_tkeep[dest_C];
        m_axis_tid = s_axis_tid[dest_C];
        m_axis_tlast = s_axis_tlast[dest_C];
        m_axis_tvalid = s_axis_tvalid[dest_C];
    end
    else begin
        m_axis_tdata = 0;
        m_axis_tkeep = 0;
        m_axis_tid = 0;
        m_axis_tlast = 1'b0;
        m_axis_tvalid = 1'b0;
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

  // Memory subsystem
  mux.ready = 1'b0;

  case(state_C)
    ST_IDLE: begin
      if(mux.valid) begin
        mux.ready = 1'b1;
        dest_N = mux.data[DEST_BITS-1:0];
        cnt_N = (mux.data[DEST_BITS+:BEAT_LOG_BITS] != 0) ? mux.data[(BEAT_LOG_BITS+DEST_BITS)+:BLEN_BITS] : mux.data[(BEAT_LOG_BITS+DEST_BITS)+:BLEN_BITS] - 1;
      end   
    end

    ST_MUX: begin
      if(tr_done) begin
        if(mux.valid) begin
          mux.ready = 1'b1;
          dest_N = mux.data[DEST_BITS-1:0];
          cnt_N = (mux.data[DEST_BITS+:BEAT_LOG_BITS] != 0) ? mux.data[(BEAT_LOG_BITS+DEST_BITS)+:BLEN_BITS] : mux.data[(BEAT_LOG_BITS+DEST_BITS)+:BLEN_BITS] - 1;
        end
      end 
      else begin
        cnt_N = (m_axis_tvalid & m_axis_tready) ? cnt_C - 1 : cnt_C;
      end
    end

  endcase
end

endmodule