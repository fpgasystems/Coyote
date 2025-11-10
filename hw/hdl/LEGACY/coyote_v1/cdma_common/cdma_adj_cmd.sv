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
 * @brief   Stripe request adjustment
 *
 * Adjustment layer for striping CDMA requests. Splits the requests between
 * all available DDR channels.
 * 
 *  @param DATA_BITS    Size of the data bus (both AXI and stream)
 */
module cdma_adj_cmd #(
    parameter integer                       DATA_BITS = AXI_DATA_BITS
)(
    input  logic                            aclk,
    input  logic                            aresetn,

    dmaIntf.s                               CDMA,                   // Regular
    dmaIntf.m                              CDMA_adj [N_MEM_CHAN],   // Adjusted

    muxIntf.s                               s_mux_card
);

localparam integer BEAT_LOG_BITS = $clog2(DATA_BITS/8);
localparam integer BLEN_BITS = LEN_BITS - BEAT_LOG_BITS;

// I/O interface issues
// -------------------------------------------------------
dma_req_t cdma_req;
logic cdma_valid;
logic cdma_ready;
logic cdma_done;

dma_req_t [N_MEM_CHAN-1:0] cdma_adj_req;
logic [N_MEM_CHAN-1:0] cdma_adj_valid;
logic [N_MEM_CHAN-1:0] cdma_adj_ready;
logic [N_MEM_CHAN-1:0] cdma_adj_done;

// Assign
always_comb begin
    cdma_req = CDMA.req;
    cdma_valid = CDMA.valid;
    CDMA.ready = cdma_ready;
    CDMA.rsp.done = cdma_done;
    CDMA.rsp.pid = 0; // ow
end

for(genvar i = 0; i < N_MEM_CHAN; i++) begin
    assign CDMA_adj[i].req = cdma_adj_req[i];
    assign CDMA_adj[i].valid = cdma_adj_valid[i];
    assign cdma_adj_ready[i] = CDMA_adj[i].ready;
    assign cdma_adj_done[i] = CDMA_adj[i].rsp.done;
end

// Internal ----------------------------------------------
// -------------------------------------------------------
logic [N_MEM_CHAN_BITS-1:0] aoffs;
logic [N_MEM_CHAN_BITS-1:0] loffs;

assign aoffs = cdma_req.paddr[BEAT_LOG_BITS+:N_MEM_CHAN_BITS];
assign loffs = cdma_req.len[BEAT_LOG_BITS+:N_MEM_CHAN_BITS];

muxIntf #(.N_ID_BITS(N_MEM_CHAN_BITS), .ARB_DATA_BITS(DATA_BITS)) mux_card_in ();

// Adjust
always_comb begin
    // hshake
    cdma_ready = &cdma_adj_ready && mux_card_in.ready;
    cdma_done = s_mux_card.done;

    // mux 
    mux_card_in.valid = cdma_valid & cdma_ready;
    mux_card_in.len = (cdma_req.len - 1) >> BEAT_LOG_BITS;
    mux_card_in.vfid = aoffs;
    mux_card_in.ctl = cdma_req.ctl;

    for(int i = 0; i < N_MEM_CHAN; i++) begin
        // paddr
        if(i >= aoffs) 
            cdma_adj_req[i].paddr = {{N_MEM_CHAN_BITS{1'b0}}, cdma_req.paddr[N_MEM_CHAN_BITS+:PADDR_BITS-N_MEM_CHAN_BITS]};
        else
            cdma_adj_req[i].paddr = {{N_MEM_CHAN_BITS{1'b0}}, cdma_req.paddr[N_MEM_CHAN_BITS+:PADDR_BITS-N_MEM_CHAN_BITS]} + (1 << BEAT_LOG_BITS);

        // len
        if(i < loffs)
            cdma_adj_req[aoffs+i].len = {{N_MEM_CHAN_BITS{1'b0}}, cdma_req.len[N_MEM_CHAN_BITS+:LEN_BITS-N_MEM_CHAN_BITS]} + (1 << BEAT_LOG_BITS);
        else 
            cdma_adj_req[aoffs+i].len = {{N_MEM_CHAN_BITS{1'b0}}, cdma_req.len[N_MEM_CHAN_BITS+:LEN_BITS-N_MEM_CHAN_BITS]};

        // meta
        cdma_adj_req[i].ctl = cdma_req.ctl;
        cdma_adj_req[i].dest = cdma_req.dest;
        cdma_adj_req[i].pid = cdma_req.pid;
        cdma_adj_req[i].rsrvd = 0;

        // hshake
        cdma_adj_valid[i] = cdma_valid & cdma_ready;
    end 
end

// Multiplexer sequence
queue #(
    .QTYPE(logic [1+N_MEM_CHAN_BITS+BLEN_BITS-1:0]),
    .QDEPTH(N_OUTSTANDING)
) inst_seq_que (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(mux_card_in.valid),
    .rdy_snk(mux_card_in.ready),
    .data_snk({mux_card_in.ctl, mux_card_in.vfid, mux_card_in.len}),
    .val_src(s_mux_card.valid),
    .rdy_src(s_mux_card.ready),
    .data_src({s_mux_card.ctl, s_mux_card.vfid, s_mux_card.len})
);

/////////////////////////////////////////////////////////////////////////////
// DEBUG
/////////////////////////////////////////////////////////////////////////////
`ifdef DBG_CDMA_ADJ_CMD

`endif

endmodule