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

module network_bp_drop #(
    parameter integer               N_STGS = 2 
) (
    //
    input  logic                    aclk,
    input  logic                    aresetn,

    input  logic                    prog_full,
    input  logic [31:0]             wr_cnt,

    // RX
    AXI4S.s                         s_rx_axis,
    AXI4S.m                         m_rx_axis,
    
    // TX
    AXI4S.s                         s_tx_axis,
    AXI4S.m                         m_tx_axis
);

// Internal
AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) rx_axis ();

// FSM 
typedef enum logic[1:0]  {ST_IDLE, ST_FWD, ST_DROP} state_t;
logic [1:0] state_C, state_N;

// REG
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
	state_C <= ST_IDLE;
end
else
	state_C <= state_N;
end

// NSL
always_comb begin: NSL
    state_N = state_C;

    case(state_C) 
        ST_IDLE: begin
            state_N = (s_rx_axis.tvalid && ~s_rx_axis.tlast) ? (prog_full ? ST_DROP : ST_FWD) : ST_IDLE;
        end

        ST_FWD:
            state_N = s_rx_axis.tvalid & s_rx_axis.tlast ? ST_IDLE : ST_FWD;

        ST_DROP:
            state_N = s_rx_axis.tvalid & s_rx_axis.tlast ? ST_IDLE : ST_DROP;
    endcase
end

// DP
always_comb begin: DP
    rx_axis.tdata = s_rx_axis.tdata;
    rx_axis.tkeep = s_rx_axis.tkeep;
    rx_axis.tlast = s_rx_axis.tlast;
    rx_axis.tvalid = 1'b0;

    s_rx_axis.tready = 1'b1;

    case(state_C)
        ST_IDLE: begin
            if(!prog_full) begin
                rx_axis.tvalid = s_rx_axis.tvalid;
            end
        end

        ST_FWD: begin
            rx_axis.tvalid = s_rx_axis.tvalid;
        end

        ST_DROP: begin
            rx_axis.tvalid = 1'b0;
        end
    endcase
end

// Slices (RX and TX)
axis_reg_array #(.N_STAGES(N_STGS)) inst_rx (.aclk(aclk), .aresetn(aresetn), .s_axis(rx_axis), .m_axis(m_rx_axis));
axis_reg_array #(.N_STAGES(N_STGS)) inst_tx (.aclk(aclk), .aresetn(aresetn), .s_axis(s_tx_axis), .m_axis(m_tx_axis));
    
endmodule