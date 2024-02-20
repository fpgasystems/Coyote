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
 * @brief   Host multiplexer source
 *
 * Sources multiple vFPGA streams from one XDMA stream.
 *
 *  @param DATA_BITS    Data bus size
 */
module axis_mux_host_src #(
    parameter integer MUX_DATA_BITS = AXI_DATA_BITS,
    parameter integer N_ID = N_REGIONS
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    metaIntf.s                              s_mux,

    AXI4S.s                                 s_axis,
    AXI4S.m                                 m_axis [N_ID]
);

// -- Constants
localparam integer BEAT_LOG_BITS = $clog2(MUX_DATA_BITS/8);
localparam integer BLEN_BITS = LEN_BITS - BEAT_LOG_BITS;
localparam integer N_ID_BITS = clog2s(N_ID);

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

// -- Internal regs
logic [N_ID_BITS-1:0] vfid_C, vfid_N;
logic [BLEN_BITS-1:0] cnt_C, cnt_N;
logic last_C, last_N;

// -- Internal signals
logic tr_done;

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Mux 
// ----------------------------------------------------------------------------------------------------------------------- 
// -- interface loop issues => temp signals
logic                                   s_axis_tvalid;
logic                                   s_axis_tready;
logic [MUX_DATA_BITS-1:0]               s_axis_tdata;
logic [MUX_DATA_BITS/8-1:0]             s_axis_tkeep;
logic                                   s_axis_tlast;

logic [N_ID-1:0]                        m_axis_tvalid;
logic [N_ID-1:0]                        m_axis_tready;
logic [N_ID-1:0][MUX_DATA_BITS-1:0]     m_axis_tdata;
logic [N_ID-1:0][MUX_DATA_BITS/8-1:0]   m_axis_tkeep;
logic [N_ID-1:0]                        m_axis_tlast;

assign s_axis_tvalid = s_axis.tvalid;
assign s_axis_tdata = s_axis.tdata;
assign s_axis_tkeep = s_axis.tkeep;
assign s_axis_tlast = s_axis.tlast;
assign s_axis.tready = s_axis_tready;

for(genvar i = 0; i < N_ID; i++) begin
    assign m_axis[i].tvalid = m_axis_tvalid[i];
    assign m_axis[i].tdata = m_axis_tdata[i];
    assign m_axis[i].tkeep = m_axis_tkeep[i];
    assign m_axis[i].tlast = m_axis_tlast[i];
    assign m_axis_tready[i] = m_axis[i].tready;
end

// -- Mux
always_comb begin
    for(int i = 0; i < N_ID; i++) begin
        m_axis_tdata[i] = s_axis_tdata;
        m_axis_tkeep[i] = s_axis_tkeep;
        m_axis_tlast[i] = s_axis_tlast & last_C;
        if(state_C == ST_MUX) begin
            m_axis_tvalid[i] = (vfid_C == i) ? s_axis_tvalid : 1'b0;
        end
        else begin
            m_axis_tvalid[i] = 1'b0;
        end
    end

    if(vfid_C < N_ID && state_C == ST_MUX) 
        s_axis_tready = m_axis_tready[vfid_C];
    else 
        s_axis_tready = 1'b0;
end

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Memory subsystem 
// ----------------------------------------------------------------------------------------------------------------------- 
// -- REG
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
	state_C <= ST_IDLE;
  cnt_C <= 'X;
  vfid_C <= 'X;
  last_C <= 'X;
end
else
  state_C <= state_N;
  cnt_C <= cnt_N;
  vfid_C <= vfid_N;
  last_C <= last_N;
end

// -- NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			state_N = s_mux.valid ? ST_MUX : ST_IDLE;

    ST_MUX:
      state_N = tr_done ? (s_mux.valid ? ST_MUX : ST_IDLE) : ST_MUX;

	endcase // state_C
end

// -- DP
always_comb begin : DP
  cnt_N = cnt_C;
  vfid_N = vfid_C;
  last_N = last_C;

  // Transfer done
  tr_done = (cnt_C == 0) && (s_axis_tvalid & s_axis_tready);

  // Memory subsystem
  s_mux.ready = 1'b0;

  case(state_C)
    ST_IDLE: begin
      if(s_mux.valid) begin
        s_mux.ready = 1'b1;
        vfid_N = s_mux.data.vfid;
        cnt_N = s_mux.data.len;
        last_N = s_mux.data.last;
      end   
    end

    ST_MUX: begin
      if(tr_done) begin
        if(s_mux.valid) begin
          s_mux.ready = 1'b1;
          vfid_N = s_mux.data.vfid;
          cnt_N = s_mux.data.len;   
          last_N = s_mux.data.last;       
        end
      end 
      else begin
        cnt_N = (s_axis_tvalid & s_axis_tready) ? cnt_C - 1 : cnt_C;
      end
    end

  endcase
end

endmodule