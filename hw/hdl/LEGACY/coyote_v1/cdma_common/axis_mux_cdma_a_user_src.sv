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
 * @brief   Striping multiplexer
 *
 * Sources a single vFPGA stream from available DDR channels.
 *
 *  @param DATA_BITS    Data bus size
 */
module axis_mux_cdma_a_user_src #(
    parameter integer                       DATA_BITS = AXI_DATA_BITS
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    muxIntf.m                              m_mux_card,

    AXI4S.s                                 s_axis_card [N_MEM_CHAN],
    AXI4S.m                                m_axis_user
);

localparam integer BEAT_LOG_BITS = $clog2(DATA_BITS/8);
localparam integer BLEN_BITS = LEN_BITS - BEAT_LOG_BITS;

// ----------------------------------------------------------------------------------------------------------------------- 
// interface loop issues => temp signals
// ----------------------------------------------------------------------------------------------------------------------- 
logic                                             m_axis_user_tvalid;
logic                                             m_axis_user_tready;
logic [DATA_BITS-1:0]                             m_axis_user_tdata;
logic [DATA_BITS/8-1:0]                           m_axis_user_tkeep;
logic                                             m_axis_user_tlast;

logic [N_MEM_CHAN-1:0]                            s_axis_card_tvalid;
logic [N_MEM_CHAN-1:0]                            s_axis_card_tready;
logic [N_MEM_CHAN-1:0][DATA_BITS-1:0]             s_axis_card_tdata;
logic [N_MEM_CHAN-1:0][DATA_BITS/8-1:0]           s_axis_card_tkeep;
logic [N_MEM_CHAN-1:0]                            s_axis_card_tlast;

logic [N_MEM_CHAN-1:0]                            axis_fifo_src_tvalid;
logic [N_MEM_CHAN-1:0]                            axis_fifo_src_tready;
logic [N_MEM_CHAN-1:0][DATA_BITS-1:0]             axis_fifo_src_tdata;
logic [N_MEM_CHAN-1:0][DATA_BITS/8-1:0]           axis_fifo_src_tkeep;
logic [N_MEM_CHAN-1:0]                            axis_fifo_src_tlast;

// Assign I/O
assign m_axis_user.tvalid = m_axis_user_tvalid;
assign m_axis_user.tkeep  = m_axis_user_tkeep;
assign m_axis_user.tdata  = m_axis_user_tdata;
assign m_axis_user.tlast  = m_axis_user_tlast;
assign m_axis_user_tready = m_axis_user.tready;

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

    assign s_axis_card_tvalid[i] = s_axis_card[i].tvalid;   
    assign s_axis_card_tdata[i]  = s_axis_card[i].tdata;  
    assign s_axis_card_tkeep[i]  = s_axis_card[i].tkeep; 
    assign s_axis_card_tlast[i]  = s_axis_card[i].tlast; 
    assign s_axis_card[i].tready = s_axis_card_tready[i];  
end

// ----------------------------------------------------------------------------------------------------------------------- 
// Internal
// ----------------------------------------------------------------------------------------------------------------------- 

// FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t; // timing extra states
logic [0:0] state_C, state_N;

// Regs
logic [N_MEM_CHAN_BITS-1:0] sel_C, sel_N;
logic [BLEN_BITS-1:0] cnt_C, cnt_N;
logic ctl_C, ctl_N;

// Internals signals
logic tr_done;
logic rxfer;

// REG
always_ff @(posedge aclk) begin: PROC_REG
if (aresetn == 1'b0) begin
    state_C <= ST_IDLE;
	sel_C <= 'X;
    cnt_C <= 'X;
    ctl_C <= 'X;
end
else
    state_C <= state_N;
	sel_C <= sel_N;
    cnt_C <= cnt_N;
    ctl_C <= ctl_N;
end

// NSL
always_comb begin
    state_N = state_C;

    case(state_C) 
        ST_IDLE:
            state_N = m_mux_card.ready ? ST_MUX : ST_IDLE;

        ST_MUX:
            state_N = (tr_done) ? (m_mux_card.ready ? ST_MUX : ST_IDLE) : ST_MUX;
    endcase 
end

// DP state
assign rxfer = m_axis_user_tvalid & m_axis_user_tready;
assign tr_done = rxfer && (cnt_C == 0);

always_comb begin
    cnt_N = cnt_C;
    ctl_N = ctl_C;
    sel_N = sel_C;

    // Mux
    m_mux_card.valid = 1'b0;
    m_mux_card.done = tr_done & ctl_C;

    // Input
    m_axis_user_tvalid = 1'b0;
    m_axis_user_tlast = (cnt_C == 0) && ctl_C;
    m_axis_user_tdata = axis_fifo_src_tdata[sel_C];
    m_axis_user_tkeep = axis_fifo_src_tkeep[sel_C];

    // FIFO
    for(int i = 0; i < N_MEM_CHAN; i++) begin
        axis_fifo_src_tready[i] = 1'b0;
    end

    // State
    case(state_C) 
        ST_IDLE: begin
            if(m_mux_card.ready) begin
                m_mux_card.valid = 1'b1;
                sel_N = m_mux_card.vfid;
                cnt_N = m_mux_card.len;
                ctl_N = m_mux_card.ctl;
            end
        end

        ST_MUX: begin
            m_axis_user_tvalid = axis_fifo_src_tvalid[sel_C];
            axis_fifo_src_tready[sel_C] = m_axis_user_tready;

            if(tr_done) begin
                if(m_mux_card.ready) begin
                    m_mux_card.valid = 1'b1;
                    sel_N = m_mux_card.vfid;
                    cnt_N = m_mux_card.len;
                    ctl_N = m_mux_card.ctl;
                end
            end
            else begin
                cnt_N = rxfer ? cnt_C - 1 : cnt_C;
                sel_N = rxfer ? sel_C + 1 : sel_C;
            end
        end
    endcase

end

endmodule