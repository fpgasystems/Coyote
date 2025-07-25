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

module axi_stripe_b (
    input  logic                            aclk,
    input  logic                            aresetn,

    // B
    input  logic [AXI_ID_BITS-1:0]          s_axi_bid,
    input  logic [1:0]                      s_axi_bresp,
    input  logic                            s_axi_bvalid,
    output logic                            s_axi_bready,

    output logic [AXI_ID_BITS-1:0]          m_axi_bid,
    output logic [1:0]                      m_axi_bresp,
    output logic                            m_axi_bvalid,
    input  logic                            m_axi_bready,

    // Mux
    metaIntf.s                              mux
);

// -- Constants
localparam integer BEAT_LOG_BITS = $clog2(AXI_DATA_BITS/8);
localparam integer BLEN_BITS = LEN_BITS - BEAT_LOG_BITS;

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

// -- Internal regs
logic ctl_C, ctl_N;
logic [N_DDR_CHAN_BITS-1:0] id_C, id_N;

// -- Internal
logic [N_DDR_CHAN-1:0] bvalid_sink;
logic [N_DDR_CHAN-1:0] bready_sink;
logic [N_DDR_CHAN-1:0][1:0] bresp_sink;
logic [N_DDR_CHAN-1:0] bvalid_src;
logic [N_DDR_CHAN-1:0] bready_src;
logic [N_DDR_CHAN-1:0][1:0] bresp_src;

// REG
always_ff @(posedge aclk) begin
    if(~aresetn) begin
        state_C <= ST_IDLE;
        id_C <= 'X;
        ctl_C <= 'X;
    end
    else begin
        state_C <= state_N;
        id_C <= id_N;
        ctl_C <= ctl_N;
    end
end

// NSL
always_comb begin
    state_N = state_C;

    case (state_C)
        ST_IDLE:
            state_N = mux.valid ? ST_MUX : ST_IDLE;

        ST_MUX:
            state_N = (m_axi_bvalid && m_axi_bready) ? (mux.valid ? ST_MUX : ST_IDLE) : ST_MUX;
        
    endcase
end

// DP
always_comb begin
    id_N = id_C;
    ctl_N = ctl_C;

    mux.ready = 1'b0;

    bready_src = 0;

    m_axi_bvalid = 1'b0;
    m_axi_bresp = bresp_src[id_C];

    case (state_C)
        ST_IDLE: begin
            if(mux.valid) begin
                mux.ready = 1'b1;
                id_N = mux.data[8];
                ctl_N = mux.data[9];
            end
        end 

        ST_MUX: begin
            m_axi_bvalid = bvalid_src[id_C];
            bready_src[id_C] = m_axi_bready;

            if(m_axi_bvalid && m_axi_bready) begin
                if(mux.valid) begin
                    mux.ready = 1'b1;
                    id_N = mux.data[8];
                    ctl_N = mux.data[9];
                end
            end
        end
        
    endcase

end

// Reorder buffers
for(genvar i = 0; i < N_DDR_CHAN; i++) begin
    assign bvalid_sink[i] = (i == s_axi_bid) ? s_axi_bvalid : 1'b0;
    assign bresp_sink[i] = s_axi_bresp;

    assign s_axi_bready = bready_sink[s_axi_bid];

    axis_data_fifo_stripe_b inst_reorder (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(bvalid_sink[i]),
        .s_axis_tready(bready_sink[i]),
        .s_axis_tuser(bresp_sink[i]),
        .m_axis_tvalid(bvalid_src[i]),
        .m_axis_tready(bready_src[i]),
        .m_axis_tuser(bresp_src[i])
    );
end

endmodule