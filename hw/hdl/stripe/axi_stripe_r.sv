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

module axi_stripe_r (
    input  logic                            aclk,
    input  logic                            aresetn,

    // R
    input  logic [AXI_DATA_BITS-1:0]        s_axi_rdata,
    input  logic [AXI_ID_BITS-1:0]          s_axi_rid,
    input  logic                            s_axi_rlast,
    input  logic [1:0]                      s_axi_rresp,
    input  logic                            s_axi_rvalid,
    output logic                            s_axi_rready,

    output logic [AXI_DATA_BITS-1:0]        m_axi_rdata,
    output logic [AXI_ID_BITS-1:0]          m_axi_rid,
    output logic                            m_axi_rlast,
    output logic [1:0]                      m_axi_rresp,
    output logic                            m_axi_rvalid,
    input  logic                            m_axi_rready,

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
logic [7:0] cnt_C, cnt_N;
logic ctl_C, ctl_N;
logic [N_DDR_CHAN_BITS-1:0] id_C, id_N;

// -- Internal
logic [N_DDR_CHAN-1:0] rvalid_sink;
logic [N_DDR_CHAN-1:0] rready_sink;
logic [N_DDR_CHAN-1:0][1:0] rresp_sink;
logic [N_DDR_CHAN-1:0][AXI_DATA_BITS-1:0] rdata_sink;
logic [N_DDR_CHAN-1:0] rlast_sink;
logic [N_DDR_CHAN-1:0] rvalid_src;
logic [N_DDR_CHAN-1:0] rready_src;
logic [N_DDR_CHAN-1:0][1:0] rresp_src;
logic [N_DDR_CHAN-1:0][AXI_DATA_BITS-1:0] rdata_src;
logic [N_DDR_CHAN-1:0] rlast_src;

// REG
always_ff @(posedge aclk) begin
    if(~aresetn) begin
        state_C <= ST_IDLE;
        cnt_C <= 0;
        id_C <= 'X;
        ctl_C <= 'X;
    end
    else begin
        state_C <= state_N;
        cnt_C <= cnt_N;
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
            state_N = ((cnt_C == 0) && m_axi_rvalid && m_axi_rready) ? (mux.valid ? ST_MUX : ST_IDLE) : ST_MUX;
        
    endcase
end

// DP
always_comb begin
    cnt_N = cnt_C;
    id_N = id_C;
    ctl_N = ctl_C;

    mux.ready = 1'b0;

    rready_src = 0;

    m_axi_rvalid = 1'b0;
    m_axi_rdata = rdata_src[id_C];
    m_axi_rresp = rresp_src[id_C];
    m_axi_rlast = (cnt_C == 0) & ctl_C;

    case (state_C)
        ST_IDLE: begin
            if(mux.valid) begin
                mux.ready = 1'b1;
                cnt_N = mux.data[7:0];
                id_N = mux.data[8];
                ctl_N = mux.data[9];
            end
        end 

        ST_MUX: begin
            m_axi_rvalid = rvalid_src[id_C];
            rready_src[id_C] = m_axi_rready;

            if(m_axi_rvalid && m_axi_rready) begin
                if(cnt_C == 0) begin
                    if(mux.valid) begin
                        mux.ready = 1'b1;
                        cnt_N = mux.data[7:0];
                        id_N = mux.data[8];
                        ctl_N = mux.data[9];
                    end
                end
                else begin
                    cnt_N = cnt_C - 1;
                end
            end
        end
        
    endcase

end

// Reorder buffers
for(genvar i = 0; i < N_DDR_CHAN; i++) begin
    assign rvalid_sink[i] = (i == s_axi_rid) ? s_axi_rvalid : 1'b0;
    assign rdata_sink[i] = s_axi_rdata;
    assign rlast_sink[i] = s_axi_rlast;
    assign rresp_sink[i] = s_axi_rresp;

    assign s_axi_rready = rready_sink[s_axi_rid];

    axis_data_fifo_stripe_r inst_reorder (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(rvalid_sink[i]),
        .s_axis_tready(rready_sink[i]),
        .s_axis_tdata(rdata_sink[i]),
        .s_axis_tlast(rlast_sink[i]),
        .s_axis_tuser(rresp_sink[i]),
        .m_axis_tvalid(rvalid_src[i]),
        .m_axis_tready(rready_src[i]),
        .m_axis_tdata(rdata_src[i]),
        .m_axis_tlast(rlast_src[i]),
        .m_axis_tuser(rresp_src[i])
    );
end

endmodule