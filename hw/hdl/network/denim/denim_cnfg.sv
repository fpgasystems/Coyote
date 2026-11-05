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
 * @brief   DENIM configuration and counter transport
 *
 * Owns the register file. Configuration arrives as {addr, data} beats from the
 * control vFPGA and counters are streamed back the same way, both crossing the
 * clock domain outside this module in denim_top.
 *
 */
module denim_cnfg (
    /* Config in: {addr[7:0], data[63:0]} */
    input  logic [71:0]         s_cnfg_tdata,
    input  logic                s_cnfg_tvalid,
    output logic                s_cnfg_tready,

    /* Register mirror out: {reg_id[7:0], value[63:0]} */
    output logic [71:0]         m_stat_tdata,
    output logic                m_stat_tvalid,
    input  logic                m_stat_tready,

    /* Decoded configuration */
    output denim_rule_t         rules [N_RULES],
    output logic [31:0]         delay_cycles [N_RULES],
    output logic                global_en,
    output logic [15:0]         roce_port,
    output logic                ctr_clear,

    /* Live counters */
    input  logic [31:0]         match_count [N_RULES],
    input  logic [31:0]         all_pkts,
    input  logic [31:0]         roce_pkts,
    input  logic [31:0]         drop_count,
    input  logic [31:0]         ecn_count,
    input  logic [31:0]         ovf_count [N_RULES],
    input  logic [31:0]         ovf_total,
    input  logic [N_RULES-1:0]  psn_captured,
    input  logic [N_RULES-1:0]  rule_armed,

    input  logic                nclk,
    input  logic                nresetn
);

// Bump on any change to the register map. denim_ctl refuses to run on a mismatch.
// {major[15:0], minor[15:0]} 
localparam logic [31:0] DENIM_VERSION = 32'h0001_0003;

localparam integer N_GLOBAL   = 8;
localparam integer RULE_STRIDE = 8;
localparam integer N_REGS     = N_GLOBAL + N_RULES * RULE_STRIDE;   // 72

// Global register indices
localparam integer REG_VERSION   = 0;
localparam integer REG_CTRL      = 1;
localparam integer REG_PKT_COUNT = 2;
localparam integer REG_EFF_COUNT = 3;
localparam integer REG_ROCE_PORT = 4;
localparam integer REG_ECN_COUNT = 5;
localparam integer REG_DEBUG     = 6;

// Per-rule field offsets from base 8 + 8i
localparam integer FLD_ENABLE      = 0;
localparam integer FLD_MATCH_QPN   = 1;
localparam integer FLD_MATCH_PSN   = 2;
localparam integer FLD_MATCH_IP    = 3;
localparam integer FLD_MATCH_FLAGS = 4;
localparam integer FLD_EFFECT_MASK = 5;
localparam integer FLD_EFFECT_PARM = 6;
localparam integer FLD_COUNTERS    = 7;     // read only, not stored

/**
 * Write path
 */
logic [7:0]  cnfg_addr;
logic [63:0] cnfg_data;
logic        cnfg_fire;

assign s_cnfg_tready = 1'b1;                // a config write is never refused
assign cnfg_addr     = s_cnfg_tdata[71:64];
assign cnfg_data     = s_cnfg_tdata[63:0];
assign cnfg_fire     = s_cnfg_tvalid & s_cnfg_tready;

// Only the writable registers are stored. Offset 7 of each slot is a counter
// pair and offsets 6 and 7 of the global block are unused, so neither is here.
logic [63:0] rule_reg [N_RULES][RULE_STRIDE-1];
logic [63:0] ctrl_reg;
logic [15:0] port_reg;

logic is_global;

assign is_global = (cnfg_addr < N_GLOBAL);

// Each rule register decodes its own address and carries its own enable.
generate
    for (genvar gr = 0; gr < N_RULES; gr++) begin : g_rule
        for (genvar gf = 0; gf < RULE_STRIDE-1; gf++) begin : g_field
            always_ff @(posedge nclk) begin
                if (~nresetn) begin
                    rule_reg[gr][gf] <= '0;
                end else if (cnfg_fire && !is_global &&
                             cnfg_addr == 8'(N_GLOBAL + gr*RULE_STRIDE + gf)) begin
                    rule_reg[gr][gf] <= cnfg_data;
                end
            end
        end
    end
endgenerate

always_ff @(posedge nclk) begin
    if (~nresetn) begin
        ctrl_reg  <= '0;
        port_reg  <= ROCE_UDP_PORT;
        ctr_clear <= 1'b0;
    end else begin
        ctr_clear <= 1'b0;

        if (cnfg_fire) begin
            if (is_global) begin
                case (cnfg_addr[2:0])
                    REG_CTRL[2:0]: begin
                        ctrl_reg  <= {cnfg_data[63:2], 1'b0, cnfg_data[0]};
                        ctr_clear <= cnfg_data[1];
                    end
                    REG_ROCE_PORT[2:0]:
                        port_reg <= cnfg_data[15:0];
                    default: ;         // VERSION and the counters are read only
                endcase
            end
            // Rule registers are written by the generate block above
        end
    end
end

/**
 * Decode
 */
// Layout mirrored exactly by the enum in denim_ctl.
always_comb begin
    global_en = ctrl_reg[0];
    roce_port = port_reg;

    for (int r = 0; r < N_RULES; r++) begin
        rules[r].en        = rule_reg[r][FLD_ENABLE][0];

        rules[r].qpn       = rule_reg[r][FLD_MATCH_QPN][23:0];
        rules[r].qpn_en    = rule_reg[r][FLD_MATCH_QPN][32];

        rules[r].psn_lo    = rule_reg[r][FLD_MATCH_PSN][23:0];
        rules[r].psn_hi    = rule_reg[r][FLD_MATCH_PSN][55:32];
        rules[r].psn_en    = rule_reg[r][FLD_MATCH_PSN][56];
        rules[r].psn_rel   = rule_reg[r][FLD_MATCH_PSN][57];

        rules[r].ip_src    = rule_reg[r][FLD_MATCH_IP][31:0];
        rules[r].ip_dst    = rule_reg[r][FLD_MATCH_IP][63:32];

        rules[r].src_en    = rule_reg[r][FLD_MATCH_FLAGS][0];
        rules[r].dst_en    = rule_reg[r][FLD_MATCH_FLAGS][1];
        rules[r].op_en     = rule_reg[r][FLD_MATCH_FLAGS][2];
        rules[r].opcode    = rule_reg[r][FLD_MATCH_FLAGS][15:8];

        rules[r].eff_mask  = rule_reg[r][FLD_EFFECT_MASK][3:0];
        // Spare bits of the same register, so a shot limit needs no new
        // address and the stride stays at eight.
        rules[r].shots     = rule_reg[r][FLD_EFFECT_MASK][31:16];
        rules[r].eff_param = rule_reg[r][FLD_EFFECT_PARM][31:0];

        delay_cycles[r]    = rule_reg[r][FLD_EFFECT_PARM][31:0];
    end
end

/**
 * Observability
 */
// Config-path observability, at global register 6. This reports what the
// datapath actually received, as opposed to what software believes it sent.
logic [23:0] dbg_beats;
logic [7:0]  dbg_last_addr;
logic [15:0] dbg_last_data;

always_ff @(posedge nclk) begin
    if (~nresetn) begin
        dbg_beats     <= '0;
        dbg_last_addr <= '0;
        dbg_last_data <= '0;
    end else if (cnfg_fire) begin
        dbg_beats     <= dbg_beats + 24'd1;
        dbg_last_addr <= cnfg_addr;
        dbg_last_data <= cnfg_data[15:0];
    end
end

/**
 * Register mirror
 */
logic [7:0]  stat_idx;
logic [63:0] stat_val;
logic [2:0]  stat_rule;
logic [2:0]  stat_fld;
logic [5:0]  stat_off;

assign stat_off  = stat_idx[5:0] - N_GLOBAL[5:0];
assign stat_rule = stat_off[5:3];
assign stat_fld  = stat_off[2:0];

always_comb begin
    if (stat_idx < N_GLOBAL) begin
        case (stat_idx[2:0])
            REG_VERSION[2:0]:   stat_val = {32'd0, DENIM_VERSION};
            REG_CTRL[2:0]:      stat_val = ctrl_reg;
            REG_PKT_COUNT[2:0]: stat_val = {roce_pkts, all_pkts};
            REG_EFF_COUNT[2:0]: stat_val = {ovf_total, drop_count};
            REG_ROCE_PORT[2:0]: stat_val = {48'd0, port_reg};
            REG_ECN_COUNT[2:0]: stat_val = {32'd0, ecn_count};
            REG_DEBUG[2:0]:     stat_val = {rule_armed, psn_captured,
                                            dbg_last_data, dbg_last_addr,
                                            dbg_beats};
            default:            stat_val = '0;
        endcase
    end else if (stat_fld == FLD_COUNTERS[2:0]) begin
        stat_val = {ovf_count[stat_rule], match_count[stat_rule]};
    end else begin
        stat_val = rule_reg[stat_rule][stat_fld];
    end
end

always_ff @(posedge nclk) begin
    if (~nresetn) begin
        stat_idx <= '0;
    end else if (m_stat_tvalid & m_stat_tready) begin
        stat_idx <= (stat_idx == N_REGS[7:0] - 8'd1) ? 8'd0 : stat_idx + 8'd1;
    end
end

assign m_stat_tvalid = 1'b1;
assign m_stat_tdata  = {stat_idx, stat_val};

endmodule
