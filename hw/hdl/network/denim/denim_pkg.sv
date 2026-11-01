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

/**
 * @brief   DENIM shared definitions
 *
 * One source of truth for the verdict tag layout, the frame byte offsets and
 * the rule record.
 */
package denim_pkg;

localparam integer N_RULES      = 8;
localparam integer RULE_ID_BITS = $clog2(N_RULES);
localparam integer TAG_BITS     = 8;

// Verdict tag layout: {effect_mask[3:0], rule_id[2:0], valid}. A bitmask
// rather than an enum, so several effects chain within one rule.
localparam integer TAG_VALID_BIT = 0;
localparam integer TAG_ID_LSB    = 1;
localparam integer TAG_MASK_LSB  = 4;

// Effect bit positions, within eff_mask and within tag[7:4] alike.
localparam integer EFF_ECN   = 0;
localparam integer EFF_DROP  = 1;
localparam integer EFF_DELAY = 2;
localparam integer EFF_COUNT = 3;

// Frame byte offsets, assuming a 20 byte IPv4 header and no VLAN tag (the
// same simplifications packet_filter already makes).
localparam integer O_ETHERTYPE = 12;
localparam integer O_IP_TOS    = 15;
localparam integer O_IP_PROTO  = 23;
localparam integer O_IP_CSUM   = 24;
localparam integer O_IP_SRC    = 26;
localparam integer O_IP_DST    = 30;
localparam integer O_UDP_DPORT = 36;
localparam integer O_BTH_OP    = 42;
localparam integer O_BTH_QPN   = 47;
localparam integer O_BTH_PSN   = 51;

localparam logic [15:0] ETHERTYPE_IPV4 = 16'h0800;
localparam logic [7:0]  IP_PROTO_UDP   = 8'h11;

localparam logic [15:0] ROCE_UDP_PORT = 16'h12b7;

// A rule slot. Each condition carries its own enable, and a disabled
// condition is a wildcard, so a slot with none enabled matches every RoCE
// packet.
typedef struct packed {
    logic        en;
    logic        qpn_en;
    logic        psn_en;
    // psn_lo and psn_hi are offsets from the connection's first observed PSN
    // rather than absolute values.
    logic        psn_rel;
    logic        src_en;
    logic        dst_en;
    logic        op_en;
    logic [23:0] qpn;
    logic [23:0] psn_lo;
    logic [23:0] psn_hi;
    logic [31:0] ip_src;
    logic [31:0] ip_dst;
    logic [7:0]  opcode;
    logic [3:0]  eff_mask;
    logic [31:0] eff_param;
    // How many packets this rule may act on before it disarms itself.
    logic [15:0] shots;
} denim_rule_t;

endpackage
