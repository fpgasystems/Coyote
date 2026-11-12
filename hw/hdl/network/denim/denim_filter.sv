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
 * @brief   DENIM match filter
 *
 * Parses the first beat of every frame, compares it against all rule slots in
 * parallel and emits a verdict tag alongside the unmodified stream. The tag is
 * the composability contract: the parse happens here exactly once, and every
 * effect block downstream reads only the tag. Adding an effect is then one
 * pipeline stage and one mask bit, never a change to this parser.
 *
 */
module denim_filter #(
    parameter integer           DATA_BITS = 512
) (
    /* Network stream in */
    input  logic [DATA_BITS-1:0]    s_axis_tdata,
    input  logic [DATA_BITS/8-1:0]  s_axis_tkeep,
    input  logic                    s_axis_tlast,
    input  logic                    s_axis_tvalid,
    output logic                    s_axis_tready,

    /* Network stream out, plus the verdict tag */
    output logic [DATA_BITS-1:0]    m_axis_tdata,
    output logic [DATA_BITS/8-1:0]  m_axis_tkeep,
    output logic                    m_axis_tlast,
    output logic                    m_axis_tvalid,
    input  logic                    m_axis_tready,
    output logic [TAG_BITS-1:0]     m_axis_tid,

    /* Rule table, already in the nclk domain */
    input  denim_rule_t             rules [N_RULES],
    input  logic                    global_en,
    input  logic [15:0]             roce_port,

    /* Counters */
    output logic [31:0]             match_count [N_RULES],
    output logic [31:0]             all_pkts,
    output logic [31:0]             roce_pkts,
    input  logic                    ctr_clear,

    // Which relative rules have captured their base PSN, for readback.
    output logic [N_RULES-1:0]      psn_captured,
    output logic [N_RULES-1:0]      rule_armed,

    input  logic                    nclk,
    input  logic                    nresetn
);

/**
 * First beat detection
 */
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
 * Field extraction
 */
logic [15:0] eth_type;
logic [15:0] udp_dport;
logic [7:0]  ip_proto;
logic [7:0]  bth_op;
logic [31:0] ip_src;
logic [31:0] ip_dst;
logic [23:0] bth_qpn;
logic [23:0] bth_psn;
logic        is_roce;

always_comb begin
    eth_type  = {s_axis_tdata[O_ETHERTYPE*8 +: 8], s_axis_tdata[(O_ETHERTYPE+1)*8 +: 8]};
    ip_proto  =  s_axis_tdata[O_IP_PROTO*8 +: 8];
    udp_dport = {s_axis_tdata[O_UDP_DPORT*8 +: 8], s_axis_tdata[(O_UDP_DPORT+1)*8 +: 8]};
    ip_src    = {s_axis_tdata[O_IP_SRC*8 +: 8],    s_axis_tdata[(O_IP_SRC+1)*8 +: 8],
                 s_axis_tdata[(O_IP_SRC+2)*8 +: 8], s_axis_tdata[(O_IP_SRC+3)*8 +: 8]};
    ip_dst    = {s_axis_tdata[O_IP_DST*8 +: 8],    s_axis_tdata[(O_IP_DST+1)*8 +: 8],
                 s_axis_tdata[(O_IP_DST+2)*8 +: 8], s_axis_tdata[(O_IP_DST+3)*8 +: 8]};
    bth_op    =  s_axis_tdata[O_BTH_OP*8 +: 8];
    bth_qpn   = {s_axis_tdata[O_BTH_QPN*8 +: 8], s_axis_tdata[(O_BTH_QPN+1)*8 +: 8],
                 s_axis_tdata[(O_BTH_QPN+2)*8 +: 8]};
    bth_psn   = {s_axis_tdata[O_BTH_PSN*8 +: 8], s_axis_tdata[(O_BTH_PSN+1)*8 +: 8],
                 s_axis_tdata[(O_BTH_PSN+2)*8 +: 8]};

    // Anything that is not IPv4/UDP on the RoCE port keeps its extracted
    // fields meaningless and can never match. Not parsing something DENIM
    // is supposed to not understand.
    is_roce   = (eth_type == ETHERTYPE_IPV4) && (ip_proto == IP_PROTO_UDP) &&
                (udp_dport == roce_port);
end

/**
 * Match
 */
// All slots compared in parallel; a condition whose enable is clear is a
// wildcard, so a slot with no conditions matches every RoCE packet.
logic [N_RULES-1:0] hit;
logic [N_RULES-1:0] pre_hit;
logic [N_RULES-1:0] psn_ok;
logic [N_RULES-1:0] capture_now;

logic [23:0] psn_lo_eff [N_RULES];
logic [23:0] psn_hi_eff [N_RULES];

always_comb begin
    for (int i = 0; i < N_RULES; i++) begin
        // Everything except the PSN condition.
        pre_hit[i] = rules[i].en && global_en && is_roce
                  && (!rules[i].qpn_en || (bth_qpn == rules[i].qpn))
                  && (!rules[i].src_en || (ip_src == rules[i].ip_src))
                  && (!rules[i].dst_en || (ip_dst == rules[i].ip_dst))
                  && (!rules[i].op_en  || (bth_op == rules[i].opcode));

        // A relative rule matches nothing until it has captured, the offset
        // is meaningless before then.
        psn_ok[i] = !rules[i].psn_en ? 1'b1
                  : (!rules[i].psn_rel || psn_captured[i]) &&
                    (bth_psn >= psn_lo_eff[i]) &&
                    (bth_psn <= psn_hi_eff[i]);

        hit[i] = pre_hit[i] && psn_ok[i] && rule_armed[i];

        // The first packet matching everything but the PSN condition defines
        // the base for a relative rule. It is not itself a match.
        capture_now[i] = pkt_first && pre_hit[i] && rules[i].psn_rel &&
                         !psn_captured[i];
    end
end

/**
 * Relative PSN base capture
 */
always_ff @(posedge nclk) begin
    if (~nresetn) begin
        psn_captured <= '0;
        for (int i = 0; i < N_RULES; i++) begin
            psn_lo_eff[i] <= '0;
            psn_hi_eff[i] <= '0;
        end
    end else begin
        for (int i = 0; i < N_RULES; i++) begin
            if (!rules[i].en)        psn_captured[i] <= 1'b0;
            else if (capture_now[i]) psn_captured[i] <= 1'b1;

            if (!rules[i].psn_rel) begin
                psn_lo_eff[i] <= rules[i].psn_lo;
                psn_hi_eff[i] <= rules[i].psn_hi;
            end else if (capture_now[i]) begin
                psn_lo_eff[i] <= bth_psn + rules[i].psn_lo;
                psn_hi_eff[i] <= bth_psn + rules[i].psn_hi;
            end
        end
    end
end

// First match wins, so slot order is match priority and denim_ctl can map
// rule file order onto it directly. Walking downwards leaves the lowest
// matching index as the surviving assignment.
logic                    win_valid;
logic [RULE_ID_BITS-1:0] win_id;
logic [3:0]              win_mask;

always_comb begin
    win_valid = 1'b0;
    win_id    = '0;
    win_mask  = '0;
    for (int i = N_RULES - 1; i >= 0; i--) begin
        if (hit[i]) begin
            win_valid = 1'b1;
            win_id    = i[RULE_ID_BITS-1:0];
            win_mask  = rules[i].eff_mask;
        end
    end
end

/**
 * Verdict tag
 */
// Latched on the first beat and held for the rest of the packet.
logic [TAG_BITS-1:0] tag_new;

assign tag_new = {win_mask, win_id, win_valid};

/**
 * Shot limit
 */
// A rule may act on at most rules[i].shots packets, zero meaning unlimited
// (default case).
// The point is to be able to selectively introduce e.g. drops, for just
// a limited number of packets.
logic [15:0]        shot_count [N_RULES];
logic [N_RULES-1:0] fire;
logic [N_RULES-1:0] spent;

always_comb begin
    for (int i = 0; i < N_RULES; i++) begin
        fire[i]  = pkt_first && win_valid && (win_id == i[RULE_ID_BITS-1:0]);
        spent[i] = (rules[i].shots != 16'd0) &&
                   ((shot_count[i] + 16'd1) >= rules[i].shots);
    end
end

always_ff @(posedge nclk) begin
    if (~nresetn) begin
        rule_armed <= '1;
        for (int i = 0; i < N_RULES; i++) shot_count[i] <= '0;
    end else begin
        for (int i = 0; i < N_RULES; i++) begin
            // A disabled slot rearms and forgets its count.
            if (!rules[i].en) begin
                rule_armed[i] <= 1'b1;
                shot_count[i] <= '0;
            end else if (fire[i]) begin
                shot_count[i] <= shot_count[i] + 16'd1;
                if (spent[i]) rule_armed[i] <= 1'b0;
            end
        end
    end
end

/**
 * Counters
 */
logic                    ctr_fire;
logic                    ctr_valid;
logic                    ctr_roce;
logic [RULE_ID_BITS-1:0] ctr_id;

always_ff @(posedge nclk) begin
    // A clear discards a count still in flight.
    if (~nresetn || ctr_clear) ctr_fire <= 1'b0;
    else                       ctr_fire <= pkt_first;

    ctr_valid <= win_valid;
    ctr_roce  <= is_roce;
    ctr_id    <= win_id;
end

always_ff @(posedge nclk) begin
    if (~nresetn || ctr_clear) begin
        all_pkts  <= '0;
        roce_pkts <= '0;
        for (int i = 0; i < N_RULES; i++) begin
            match_count[i] <= '0;
        end
    end else if (ctr_fire) begin
        all_pkts <= all_pkts + 32'd1;
        if (ctr_roce) begin
            roce_pkts <= roce_pkts + 32'd1;
        end
        if (ctr_valid) begin
            match_count[ctr_id] <= match_count[ctr_id] + 32'd1;
        end
    end
end

/**
 * Output stage
 */
// The filter observes and never modifies.
(* max_fanout = 64 *) logic out_en;

assign out_en = m_axis_tready;

always_ff @(posedge nclk) begin
    if (~nresetn) begin
        m_axis_tvalid <= 1'b0;
        m_axis_tlast  <= 1'b0;
    end else if (out_en) begin
        m_axis_tvalid <= s_axis_tvalid;
        m_axis_tlast  <= s_axis_tlast;
    end
end

always_ff @(posedge nclk) begin
    if (out_en) begin
        m_axis_tdata <= s_axis_tdata;
        m_axis_tkeep <= s_axis_tkeep;
    end
end

always_ff @(posedge nclk) begin
    if (~nresetn) begin
        m_axis_tid <= '0;
    end else if (pkt_first) begin
        m_axis_tid <= tag_new;
    end
end

// tready comes straight from downstream
assign s_axis_tready = m_axis_tready;

endmodule
