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
 * @brief   DENIM delay effect
 *
 * Holds a tagged packet until a per-rule number of nclk cycles has elapsed,
 * emulating the queueing delay a congested switch would add.
 */
module denim_delay #(
    parameter integer           DATA_BITS  = 512,
    parameter integer           FIFO_BEATS = 512,
    // Packets in flight, which is a separate bound from beats in flight.
    parameter integer           META_ENTRIES = 512,
    parameter integer           PMTU_BYTES = 4096,
    parameter logic [31:0]      TIME_INIT  = 32'd0
) (
    /* Network stream in, carrying the filter's verdict tag */
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

    /* Per-rule delay, in nclk cycles */
    input  logic [31:0]             delay_cycles [N_RULES],

    /* Counters */
    output logic [31:0]             ovf_count [N_RULES],
    output logic [31:0]             ovf_total,
    input  logic                    ctr_clear,

    input  logic                    nclk,
    input  logic                    nresetn
);

localparam integer PTR_BITS      = $clog2(FIFO_BEATS);
localparam integer META_PTR_BITS = $clog2(META_ENTRIES);
localparam integer KEEP_BITS     = DATA_BITS/8;
localparam integer WORD_BITS     = TAG_BITS + 1 + KEEP_BITS + DATA_BITS;

// Packet length is unknown on the first beat, so admission reserves room for
// the largest frame the build can produce. 
localparam integer MAX_PKT_BEATS = (PMTU_BYTES + 128 + 63) / 64;

/**
 * Storage
 */
logic [WORD_BITS-1:0] mem [FIFO_BEATS];
logic [WORD_BITS-1:0] mem_q;

logic                 last_mem [FIFO_BEATS];

logic [31:0]              rel_mem [META_ENTRIES];

logic [PTR_BITS:0]        wr_ptr;
logic [PTR_BITS:0]        rd_ptr;
logic [META_PTR_BITS:0]   meta_wr;
logic [META_PTR_BITS:0]   meta_rd;
logic [PTR_BITS:0]        occupancy;
logic [META_PTR_BITS:0]   meta_occ;

assign occupancy = wr_ptr - rd_ptr;
assign meta_occ  = meta_wr - meta_rd;

/**
 * Free-running timebase
 */
logic [31:0] now;

always_ff @(posedge nclk) begin
    if (~nresetn) now <= TIME_INIT;
    else          now <= now + 32'd1;
end

/**
 * Ingress
 */
logic in_pkt_not_first;
logic rejecting_r;
logic pkt_start;
logic pkt_first;
logic admit;
logic reject_this;

(* max_fanout = 8 *) logic wr_fire;

assign pkt_start   = ~in_pkt_not_first & s_axis_tvalid;
assign pkt_first   = pkt_start & s_axis_tready;

always_ff @(posedge nclk) begin
    if (~nresetn) begin
        admit <= 1'b1;
    end else begin
        admit <= ((FIFO_BEATS - occupancy) > MAX_PKT_BEATS) &&
                 (meta_occ < (META_ENTRIES - 1));
    end
end

assign reject_this = pkt_start ? ~admit : rejecting_r;
assign wr_fire     = s_axis_tvalid & s_axis_tready & ~reject_this;

// The delay is looked up with the tag's rule id, so two rules can hold their
// packets for different times. An untagged packet, or one whose rule did not
// ask for delay, is released as soon as it reaches the head.
logic [31:0] rel_pre [N_RULES];
logic [31:0] rel_time;
logic        want_delay;

always_ff @(posedge nclk) begin
    if (~nresetn) begin
        for (int i = 0; i < N_RULES; i++) rel_pre[i] <= TIME_INIT;
    end else begin
        // Plus one, because these are registered and therefore consumed on the
        // cycle after they are computed, by which time now has advanced. The
        // result is that rel_pre[i] always reads as now + delay_cycles[i].
        for (int i = 0; i < N_RULES; i++)
            rel_pre[i] <= now + delay_cycles[i] + 32'd1;
    end
end

assign want_delay = s_axis_tid[TAG_VALID_BIT] & s_axis_tid[TAG_MASK_LSB + EFF_DELAY];

assign rel_time = want_delay ? rel_pre[s_axis_tid[TAG_ID_LSB +: RULE_ID_BITS]]
                             : now;

always_ff @(posedge nclk) begin
    if (~nresetn) begin
        in_pkt_not_first <= 1'b0;
        rejecting_r      <= 1'b0;
        wr_ptr           <= '0;
        meta_wr          <= '0;
    end else begin
        if (s_axis_tvalid & s_axis_tready) begin
            in_pkt_not_first <= ~s_axis_tlast;
            rejecting_r      <= s_axis_tlast ? 1'b0 : reject_this;
        end

        if (wr_fire) begin
            mem[wr_ptr[PTR_BITS-1:0]]      <= {s_axis_tid, s_axis_tlast, s_axis_tkeep, s_axis_tdata};
            last_mem[wr_ptr[PTR_BITS-1:0]] <= s_axis_tlast;
            wr_ptr                         <= wr_ptr + 1'b1;
        end

        if (pkt_first & ~reject_this) begin
            rel_mem[meta_wr[META_PTR_BITS-1:0]] <= rel_time;
            meta_wr                        <= meta_wr + 1'b1;
        end
    end
end

/**
 * Egress
 */
logic                 s1_valid;
logic                 s2_valid;
logic [WORD_BITS-1:0] out_word;
logic                 fifo_ne;
logic                 rd_is_last;
logic                 head_due;
logic                 do_read;
logic                 s1_to_s2;
logic                 m_accept;

assign fifo_ne    = (rd_ptr != wr_ptr);
assign rd_is_last = last_mem[rd_ptr[PTR_BITS-1:0]];
assign m_accept   = m_axis_tvalid & m_axis_tready;

assign head_due   = (meta_rd != meta_wr) &&
                    ($signed(now - rel_mem[meta_rd[META_PTR_BITS-1:0]]) >= 0);

assign s1_to_s2 = s1_valid & (~s2_valid | m_accept);
assign do_read  = fifo_ne & head_due & (~s1_valid | s1_to_s2);

always_ff @(posedge nclk) begin
    if (~nresetn) begin
        rd_ptr   <= '0;
        meta_rd  <= '0;
        s1_valid <= 1'b0;
        s2_valid <= 1'b0;
    end else begin
        if (do_read) begin
            mem_q  <= mem[rd_ptr[PTR_BITS-1:0]];
            rd_ptr <= rd_ptr + 1'b1;
            if (rd_is_last) meta_rd <= meta_rd + 1'b1;
        end

        if (s1_to_s2) out_word <= mem_q;

        if (do_read)        s1_valid <= 1'b1;
        else if (s1_to_s2)  s1_valid <= 1'b0;

        if (s1_to_s2)       s2_valid <= 1'b1;
        else if (m_accept)  s2_valid <= 1'b0;
    end
end

/**
 * Counters
 */
// A rejected packet always bumps the total. It bumps a rule's counter only if
// it carried a valid tag: a packet rejected because someone else's delayed
// packet filled the FIFO has no rule to attribute to.
logic ovf_fire;

assign ovf_fire = pkt_first & reject_this;

always_ff @(posedge nclk) begin
    if (~nresetn || ctr_clear) begin
        ovf_total <= '0;
        for (int i = 0; i < N_RULES; i++) ovf_count[i] <= '0;
    end else if (ovf_fire) begin
        ovf_total <= ovf_total + 32'd1;
        if (s_axis_tid[TAG_VALID_BIT])
            ovf_count[s_axis_tid[TAG_ID_LSB +: RULE_ID_BITS]] <=
                ovf_count[s_axis_tid[TAG_ID_LSB +: RULE_ID_BITS]] + 32'd1;
    end
end

/**
 * Stream out
 */
assign s_axis_tready = m_axis_tready;

assign m_axis_tvalid = s2_valid;
assign m_axis_tdata  = out_word[0                       +: DATA_BITS];
assign m_axis_tkeep  = out_word[DATA_BITS               +: KEEP_BITS];
assign m_axis_tlast  = out_word[DATA_BITS + KEEP_BITS];
assign m_axis_tid    = out_word[DATA_BITS + KEEP_BITS + 1 +: TAG_BITS];

endmodule
