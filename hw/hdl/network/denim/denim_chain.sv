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
 * @brief   DENIM effect chain
 *
 * filter -> drop -> ECN -> delay, plus the register file that configures them.
 *
 */
module denim_chain #(
    parameter integer           DATA_BITS  = 512,
    parameter integer           FIFO_BEATS = 512,
    parameter integer           META_ENTRIES = 512,
    parameter integer           PMTU_BYTES = 4096
) (
    /* Network stream, nclk domain */
    input  logic [DATA_BITS-1:0]    s_axis_tdata,
    input  logic [DATA_BITS/8-1:0]  s_axis_tkeep,
    input  logic                    s_axis_tlast,
    input  logic                    s_axis_tvalid,
    output logic                    s_axis_tready,

    output logic [DATA_BITS-1:0]    m_axis_tdata,
    output logic [DATA_BITS/8-1:0]  m_axis_tkeep,
    output logic                    m_axis_tlast,
    output logic                    m_axis_tvalid,
    input  logic                    m_axis_tready,

    /* Config in, register mirror out */
    input  logic [71:0]             s_cnfg_tdata,
    input  logic                    s_cnfg_tvalid,
    output logic                    s_cnfg_tready,

    output logic [71:0]             m_stat_tdata,
    output logic                    m_stat_tvalid,
    input  logic                    m_stat_tready,

    input  logic                    nclk,
    input  logic                    nresetn
);

/**
 * Configuration
 */
denim_rule_t rules [N_RULES];
logic [31:0] delay_cycles [N_RULES];
logic        global_en;
logic [15:0] roce_port;
logic        ctr_clear;

logic [31:0] match_count [N_RULES];
logic [31:0] all_pkts;
logic [31:0] roce_pkts;
logic [31:0] drop_count;
logic [31:0] ecn_count;
logic [31:0] ovf_count [N_RULES];
logic [31:0] ovf_total;
logic [N_RULES-1:0] psn_captured;
logic [N_RULES-1:0] rule_armed;

denim_cnfg inst_cnfg (
    .s_cnfg_tdata   (s_cnfg_tdata),
    .s_cnfg_tvalid  (s_cnfg_tvalid),
    .s_cnfg_tready  (s_cnfg_tready),

    .m_stat_tdata   (m_stat_tdata),
    .m_stat_tvalid  (m_stat_tvalid),
    .m_stat_tready  (m_stat_tready),

    .rules          (rules),
    .delay_cycles   (delay_cycles),
    .global_en      (global_en),
    .roce_port      (roce_port),
    .ctr_clear      (ctr_clear),

    .match_count    (match_count),
    .all_pkts       (all_pkts),
    .roce_pkts      (roce_pkts),
    .drop_count     (drop_count),
    .ecn_count      (ecn_count),
    .ovf_count      (ovf_count),
    .ovf_total      (ovf_total),
    .psn_captured   (psn_captured),
    .rule_armed     (rule_armed),

    .nclk           (nclk),
    .nresetn        (nresetn)
);

/**
 * Datapath
 */
logic [DATA_BITS-1:0]   flt_tdata, drp_tdata, ecn_tdata;
logic [DATA_BITS/8-1:0] flt_tkeep, drp_tkeep, ecn_tkeep;
logic                   flt_tlast, drp_tlast, ecn_tlast;
logic                   flt_tvalid, drp_tvalid, ecn_tvalid;
logic                   flt_tready, drp_tready, ecn_tready;

(* max_fanout = 16 *) logic [TAG_BITS-1:0] flt_tid, drp_tid, ecn_tid;

denim_filter #(.DATA_BITS(DATA_BITS)) inst_filter (
    .s_axis_tdata(s_axis_tdata), .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tlast(s_axis_tlast), .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),

    .m_axis_tdata(flt_tdata), .m_axis_tkeep(flt_tkeep),
    .m_axis_tlast(flt_tlast), .m_axis_tvalid(flt_tvalid),
    .m_axis_tready(flt_tready), .m_axis_tid(flt_tid),

    .rules(rules), .global_en(global_en), .roce_port(roce_port),
    .match_count(match_count), .all_pkts(all_pkts), .roce_pkts(roce_pkts),
    .psn_captured(psn_captured), .rule_armed(rule_armed),
    .ctr_clear(ctr_clear),

    .nclk(nclk), .nresetn(nresetn)
);

denim_drop #(.DATA_BITS(DATA_BITS)) inst_drop (
    .s_axis_tdata(flt_tdata), .s_axis_tkeep(flt_tkeep),
    .s_axis_tlast(flt_tlast), .s_axis_tvalid(flt_tvalid),
    .s_axis_tready(flt_tready), .s_axis_tid(flt_tid),

    .m_axis_tdata(drp_tdata), .m_axis_tkeep(drp_tkeep),
    .m_axis_tlast(drp_tlast), .m_axis_tvalid(drp_tvalid),
    .m_axis_tready(drp_tready), .m_axis_tid(drp_tid),

    .drop_count(drop_count), .ctr_clear(ctr_clear),

    .nclk(nclk), .nresetn(nresetn)
);

denim_ecn #(.DATA_BITS(DATA_BITS)) inst_ecn (
    .s_axis_tdata(drp_tdata), .s_axis_tkeep(drp_tkeep),
    .s_axis_tlast(drp_tlast), .s_axis_tvalid(drp_tvalid),
    .s_axis_tready(drp_tready), .s_axis_tid(drp_tid),

    .m_axis_tdata(ecn_tdata), .m_axis_tkeep(ecn_tkeep),
    .m_axis_tlast(ecn_tlast), .m_axis_tvalid(ecn_tvalid),
    .m_axis_tready(ecn_tready), .m_axis_tid(ecn_tid),

    .ecn_count(ecn_count), .ctr_clear(ctr_clear),

    .nclk(nclk), .nresetn(nresetn)
);

// The tag ends here. Downstream is the IP handler, which knows nothing about DENIM and must see an ordinary AXI4-Stream.
denim_delay #(
    .DATA_BITS(DATA_BITS), .FIFO_BEATS(FIFO_BEATS),
    .META_ENTRIES(META_ENTRIES), .PMTU_BYTES(PMTU_BYTES)
) inst_delay (
    .s_axis_tdata(ecn_tdata), .s_axis_tkeep(ecn_tkeep),
    .s_axis_tlast(ecn_tlast), .s_axis_tvalid(ecn_tvalid),
    .s_axis_tready(ecn_tready), .s_axis_tid(ecn_tid),

    .m_axis_tdata(m_axis_tdata), .m_axis_tkeep(m_axis_tkeep),
    .m_axis_tlast(m_axis_tlast), .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready), .m_axis_tid(),

    .delay_cycles(delay_cycles),
    .ovf_count(ovf_count), .ovf_total(ovf_total), .ctr_clear(ctr_clear),

    .nclk(nclk), .nresetn(nresetn)
);

endmodule
