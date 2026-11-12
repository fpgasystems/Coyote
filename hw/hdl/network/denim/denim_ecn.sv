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
 * @brief   DENIM ECN marking effect
 *
 * Sets the IPv4 ECN field to CE on the first beat of every packet whose verdict
 * tag carries the ecn bit, and repairs the header checksum so the receiver's
 * stack accepts the frame it has been handed.
 *
 * The block never re-parses. The tag is what guarantees the packet is IPv4 over
 * Ethernet with a 20 byte header, so the two offsets touched here are known
 * good, an untagged packet is not inspected at all.
 *
 * There is no pipeline stage and no added latency: the patch is a mux on the
 * outgoing beat, so the block is a wire for every packet it does not mark.
 */
module denim_ecn #(
    parameter integer           DATA_BITS = 512
) (
    /* Network stream in, with the verdict tag from upstream */
    input  logic [DATA_BITS-1:0]    s_axis_tdata,
    input  logic [DATA_BITS/8-1:0]  s_axis_tkeep,
    input  logic                    s_axis_tlast,
    input  logic                    s_axis_tvalid,
    output logic                    s_axis_tready,
    input  logic [TAG_BITS-1:0]     s_axis_tid,

    /* Network stream out */
    output logic [DATA_BITS-1:0]    m_axis_tdata,
    output logic [DATA_BITS/8-1:0]  m_axis_tkeep,
    output logic                    m_axis_tlast,
    output logic                    m_axis_tvalid,
    input  logic                    m_axis_tready,
    output logic [TAG_BITS-1:0]     m_axis_tid,

    /* Counters */
    output logic [31:0]             ecn_count,
    input  logic                    ctr_clear,

    input  logic                    nclk,
    input  logic                    nresetn
);

/**
 * First beat detection
 */
// As in denim_filter: a register set on every accepted beat and cleared by
// tlast, so the beat carrying the headers is the one where it reads zero.
logic in_pkt_not_first;
logic pkt_start;
logic pkt_first;

assign pkt_start = ~in_pkt_not_first & s_axis_tvalid;
assign pkt_first = pkt_start & s_axis_tready;

always_ff @(posedge nclk) begin
    if (~nresetn) begin
        in_pkt_not_first <= 1'b0;
    end else if (s_axis_tvalid & s_axis_tready) begin
        in_pkt_not_first <= ~s_axis_tlast;
    end
end

/**
 * ECN patch and incremental checksum
 */
// Byte 15 holds DSCP in its top six bits and ECN in its low two, and is the
// low half of the 16 bit header word at bytes 14-15. Raising ECN therefore adds
// delta to that word, and the checksum, being the complement of the header sum,
// has to lose the same delta.
logic        ecn_req;
logic [1:0]  old_ecn;
logic [1:0]  delta;
logic [15:0] old_csum;
logic [16:0] csum_sub;
logic [15:0] new_csum;
logic        mark_now;

assign ecn_req  = s_axis_tid[TAG_VALID_BIT] & s_axis_tid[TAG_MASK_LSB + EFF_ECN];
assign old_ecn  = s_axis_tdata[O_IP_TOS*8 +: 2];
assign old_csum = {s_axis_tdata[O_IP_CSUM*8 +: 8], s_axis_tdata[(O_IP_CSUM+1)*8 +: 8]};
assign delta    = 2'b11 - old_ecn;

assign csum_sub = {1'b0, old_csum} - {15'b0, delta};
assign new_csum = csum_sub[16] ? (csum_sub[15:0] - 16'd1) : csum_sub[15:0];

assign mark_now = pkt_start & ecn_req & (delta != 2'b00);

always_comb begin
    m_axis_tdata = s_axis_tdata;
    if (mark_now) begin
        m_axis_tdata[O_IP_TOS*8 +: 2]      = 2'b11;
        m_axis_tdata[O_IP_CSUM*8 +: 8]     = new_csum[15:8];
        m_axis_tdata[(O_IP_CSUM+1)*8 +: 8] = new_csum[7:0];
    end
end

/**
 * Counters
 */
// Counts packets this block actually marked, so a packet that arrived already
// CE is not counted. match_count in the filter already reports how many packets
// asked for the effect, and the difference between the two is the traffic that
// was congestion marked before it ever reached DENIM.
always_ff @(posedge nclk) begin
    if (~nresetn || ctr_clear) begin
        ecn_count <= '0;
    end else if (pkt_first & mark_now) begin
        ecn_count <= ecn_count + 32'd1;
    end
end

/**
 * Stream passthrough
 */
// Only tdata is ever rewritten, and only in the beat mux above. tready comes
// straight from downstream.
assign m_axis_tkeep  = s_axis_tkeep;
assign m_axis_tlast  = s_axis_tlast;
assign m_axis_tvalid = s_axis_tvalid;
assign m_axis_tid    = s_axis_tid;
assign s_axis_tready = m_axis_tready;

endmodule
