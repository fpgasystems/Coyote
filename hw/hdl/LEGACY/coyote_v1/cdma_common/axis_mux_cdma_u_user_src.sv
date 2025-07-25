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
 * @brief   Striping multiplexer
 *
 * Sources a single vFPGA stream from available DDR channels.
 *
 *  @param DATA_BITS    Data bus size
 */
module axis_mux_cdma_user_src #(
    parameter integer                       DATA_BITS = AXI_DATA_BITS
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    muxIntf.m                              m_mux_card,

    AXI4S.s                         s_axis_card,
    AXI4S.m                                m_axis_user
);

localparam integer BEAT_LOG_BITS = $clog2(DATA_BITS/8);

// ----------------------------------------------------------------------------------------------------------------------- 
// interface loop issues => temp signals
// ----------------------------------------------------------------------------------------------------------------------- 
logic                                             m_axis_user_tvalid;
logic                                             m_axis_user_tready;
logic [DATA_BITS-1:0]                         m_axis_user_tdata;
logic [DATA_BITS/8-1:0]                       m_axis_user_tkeep;
logic                                             m_axis_user_tlast;

logic [N_MEM_CHAN-1:0]                            s_axis_card_tvalid;
logic [N_MEM_CHAN-1:0]                            s_axis_card_tready;
logic [N_MEM_CHAN-1:0][DATA_BITS-1:0]         s_axis_card_tdata;
logic [N_MEM_CHAN-1:0][DATA_BITS/8-1:0]       s_axis_card_tkeep;
logic [N_MEM_CHAN-1:0]                            s_axis_card_tlast;

logic [N_MEM_CHAN-1:0]                            axis_fifo_src_tvalid;
logic [N_MEM_CHAN-1:0]                            axis_fifo_src_tready;
logic [N_MEM_CHAN-1:0][DATA_BITS-1:0]         axis_fifo_src_tdata;
logic [N_MEM_CHAN-1:0][DATA_BITS/8-1:0]       axis_fifo_src_tkeep;
logic [N_MEM_CHAN-1:0]                            axis_fifo_src_tlast;

// Assign I/O
for(genvar i = 0; i < N_MEM_CHAN; i++) begin
  axis_data_fifo_hbm_512 inst_fifo_ddr_sink_mux (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(s_axis_card_tvalid[i]),
        .s_axis_tready(s_axis_card_tready[i]),
        .s_axis_tdata(s_axis_card_tdata[i]),
        .s_axis_tkeep(s_axis_card_tkeep[i]),
        .s_axis_tlast(s_axis_card_tlast[i]),
        .m_axis_tvalid(axis_fifo_src_tvalid[i]),
        .m_axis_tready(axis_fifo_src_tready[i]),
        .m_axis_tdata(axis_fifo_src_tdata[i]),
        .m_axis_tkeep(axis_fifo_src_tkeep[i]),
        .m_axis_tlast(axis_fifo_src_tlast[i])
    );
end

// FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t; // timing extra states
logic [0:0] state_C, state_N;

// Regs
logic [N_MEM_CHAN_BITS-1:0] sel_C, sel_N;
logic [LEN_BITS-BEAT_LOG_BITS-1:0] cnt_C, cnt_N;
logic [LEN_BITS-BEAT_LOG_BITS-1:0] n_beats_C, n_beats_N;
logic ctl_C, ctl_N;

// Internal signals
logic tr_done;
logic wxfer;

// REG
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
    state_C <= ST_IDLE;
	sel_C <= 0;
    cnt_C <= 'X;
    n_beats_C <= 'X;
    ctl_C <= 'X;
end
else
    state_C <= state_N;
	sel_C <= sel_N;
    cnt_C <= cnt_N;
    n_beats_C <= n_beats_N;
    ctl_C <= ctl_N;
end

// NSL
always_comb begin
    state_N = state_C;

    case(state_C) 
        ST_IDLE:
            state_N = m_mux_card.ready ? ST_MUX : ST_IDLE;

        ST_MUX:
            state_N = tr_done ? (m_mux_card.ready ? ST_MUX : ST_IDLE) : ST_MUX;
    endcase 
end

// DP state
always_comb begin
    cnt_N =  cnt_C;
    n_beats_N = n_beats_C;
    ctl_N = ctl_C;

    // Mux
    m_mux_card.valid = 1'b0;

    case(state_C) 
        ST_IDLE: begin
            cnt_N = 0;
            if(m_mux_card.ready) begin
                m_mux_card.valid = 1'b1;
                n_beats_N = m_mux_card.len;
                ctl_N = m_mux_card.ctl;
            end
        end

        ST_MUX: begin
            if(tr_done) begin
                cnt_N = 0;
                if(m_mux_card.ready) begin
                    m_mux_card.valid = 1'b1;
                    n_beats_N = m_mux_card.len;
                    ctl_N = m_mux_card.ctl;
                end
            end
            else begin
                cnt_N = wxfer ? cnt_C + 1 : cnt_C;
            end
        end
    endcase
end

assign wxfer = m_axis_user_tvalid & m_axis_user_tready;
assign tr_done = wxfer && (cnt_C == n_beats_C);

// DP select
always_comb begin
    sel_N = sel_C;

    for(int i = 0; i < N_MEM_CHAN; i++) begin
        axis_fifo_src_tready[i] = 1'b0;
    end

    // Selection
    if(wxfer) begin
        axis_fifo_src_tready[sel_C] = 1'b1;

        if(tr_done && sel_C < N_MEM_CHAN-1) begin
            for(int i = 0; i < N_MEM_CHAN; i++) begin
                if(i > sel_C) begin
                    axis_fifo_src_tready[i] = 1'b1;
                end
            end

            sel_N = 0;
        end

        sel_N = sel_C + 1;
    end
end

assign m_axis_user.tvalid = &axis_fifo_src_tvalid;
assign m_axis_user.tlast = (tr_done & ctl_C) ? 1'b1 : 1'b0;
assign m_axis_user.tdata = axis_fifo_src_tdata[sel_C]; 
assign m_axis_user.tkeep = axis_fifo_src_tkeep[sel_C]; 

// CDMA 
for(genvar i = 0; i < N_MEM_CHAN; i++) begin
    assign s_axis_card_tdata[i] = s_axis_card.tdata[i*DATA_BITS+:DATA_BITS];
    assign s_axis_card_tkeep[i] = s_axis_card.tkeep[i*DATA_BITS/8+:DATA_BITS/8];
    assign s_axis_card_tlast[i] = s_axis_card.tlast;

    assign s_axis_card_tvalid[i] = s_axis_card.tvalid & s_axis_card.tready;
end

assign s_axis_card.tready = &s_axis_card_tready;

endmodule