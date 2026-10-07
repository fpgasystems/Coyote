/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2026, Systems Group, ETH Zurich
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

import denim_pkg::*;

/**
 * @brief   DENIM drop effect
 *
 * Removes every beat of a packet whose verdict tag carries the drop bit. The
 * block reads only the tag, never the frame: the filter parsed the headers
 * already.
 *
 * Suppression follows packet_filter: tvalid, tkeep and tlast are forced low
 * downstream while the stream is consumed at full rate. Nothing is buffered,
 * so a dropped packet costs no cycles and the sink never sees it.
 *
 */
module denim_drop #(
    parameter integer           DATA_BITS = 512
) (
    /* Network stream in, carrying the filter's verdict tag */
    input  logic [DATA_BITS-1:0]    s_axis_tdata,
    input  logic [DATA_BITS/8-1:0]  s_axis_tkeep,
    input  logic                    s_axis_tlast,
    input  logic                    s_axis_tvalid,
    output logic                    s_axis_tready,
    input  logic [TAG_BITS-1:0]     s_axis_tid,

    /* Network stream out, tag passed on to the next effect block */
    output logic [DATA_BITS-1:0]    m_axis_tdata,
    output logic [DATA_BITS/8-1:0]  m_axis_tkeep,
    output logic                    m_axis_tlast,
    output logic                    m_axis_tvalid,
    input  logic                    m_axis_tready,
    output logic [TAG_BITS-1:0]     m_axis_tid,

    /* Counters */
    output logic [31:0]             drop_count,
    input  logic                    ctr_clear,

    input  logic                    nclk,
    input  logic                    nresetn
);

/**
 * Per-packet drop decision
 */
// Only the first beat of a packet carries a meaningful tag, so the verdict is
// latched and held for the trailing beats: dropping just the header beat would
// leave the payload behind as a runt frame.
logic in_pkt_not_first;
logic dropping_r;
logic pkt_start;
logic pkt_first;
logic drop_this;

assign pkt_start = ~in_pkt_not_first & s_axis_tvalid;
assign pkt_first = pkt_start & s_axis_tready;
assign drop_this = pkt_start ? (s_axis_tid[TAG_VALID_BIT] & s_axis_tid[TAG_MASK_LSB + EFF_DROP])
                             : dropping_r;

always_ff @(posedge nclk) begin
    if (~nresetn) begin
        in_pkt_not_first <= 1'b0;
        dropping_r       <= 1'b0;
    end else if (s_axis_tvalid & s_axis_tready) begin
        in_pkt_not_first <= ~s_axis_tlast;
        dropping_r       <= s_axis_tlast ? 1'b0 : drop_this;
    end
end

/**
 * Counters
 */
// Counted once per packet, on the beat that carried the decision, so the
// figure is comparable with the filter's match_count for the same rule.
always_ff @(posedge nclk) begin
    if (~nresetn || ctr_clear) begin
        drop_count <= '0;
    end else if (pkt_first & drop_this) begin
        drop_count <= drop_count + 32'd1;
    end
end

/**
 * Stream
 */
// tready comes straight from downstream and is never gated on drop_this: the
// CMAC RX has no flow control, so a dropped packet must be consumed at line
// rate rather than stalled off the wire.
assign m_axis_tdata  = s_axis_tdata;
assign m_axis_tid    = s_axis_tid;
assign m_axis_tvalid = s_axis_tvalid & ~drop_this;
assign m_axis_tkeep  = drop_this ? '0 : s_axis_tkeep;
assign m_axis_tlast  = drop_this ? 1'b0 : s_axis_tlast;
assign s_axis_tready = m_axis_tready;

endmodule
