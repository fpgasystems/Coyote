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
 * @brief   Host multiplexer sink
 *
 * Sinks multiple vFPGA stream into one XDMA stream.
 *
 *  @param DATA_BITS    Data bus size
 */
module axis_mux_host_sink #(
    parameter integer DATA_BITS = AXI_DATA_BITS,
    parameter integer N_ID = N_REGIONS
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    metaIntf.s                              s_mux,

    AXI4S.s                                 s_axis [N_ID],
    AXI4S.m                                 m_axis
);

// -- Constants
localparam integer BEAT_LOG_BITS = $clog2(DATA_BITS/8);
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
// Mux 
// ----------------------------------------------------------------------------------------------------------------------- 
// -- interface loop issues => temp signals
logic [N_ID-1:0]                            s_axis_tvalid;
logic [N_ID-1:0]                            s_axis_tready;
logic [N_ID-1:0][DATA_BITS-1:0]         s_axis_tdata;
logic [N_ID-1:0][DATA_BITS/8-1:0]       s_axis_tkeep;
logic [N_ID-1:0]                            s_axis_tlast;

logic                                       m_axis_tvalid;
logic                                       m_axis_tready;
logic [DATA_BITS-1:0]                   m_axis_tdata;
logic [DATA_BITS/8-1:0]                 m_axis_tkeep;
logic                                       m_axis_tlast;

for(genvar i = 0; i < N_ID; i++) begin
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

// -- Mux
always_comb begin
    for(int i = 0; i < N_ID; i++) begin
        if(state_C == ST_MUX)
          s_axis_tready[i] = (vfid_C == i) ? m_axis_tready : 1'b0;      
        else 
          s_axis_tready[i] = 1'b0;
    end

    if(vfid_C < N_ID && state_C == ST_MUX) begin
        m_axis_tdata = s_axis_tdata[vfid_C];
        m_axis_tkeep = s_axis_tkeep[vfid_C];
        m_axis_tlast = s_axis_tlast[vfid_C] && last_C;
        m_axis_tvalid = s_axis_tvalid[vfid_C];
    end
    else begin
        m_axis_tdata = 0;
        m_axis_tkeep = 0;
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
  tr_done = (cnt_C == 0) && (m_axis_tvalid & m_axis_tready);

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
        cnt_N = (m_axis_tvalid & m_axis_tready) ? cnt_C - 1 : cnt_C;
      end
    end

  endcase
end

endmodule