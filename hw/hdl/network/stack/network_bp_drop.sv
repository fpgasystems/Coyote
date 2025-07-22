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