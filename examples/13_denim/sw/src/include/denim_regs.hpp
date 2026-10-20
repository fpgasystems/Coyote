/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2026, Systems Group, ETH Zurich
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

#pragma once

#include <cstdint>

/**
 * DENIM register map.
 *
 * This mirrors hw/hdl/network/denim/denim_cnfg.sv exactly. The two are not
 * generated from a common source, so DENIM_VERSION_EXPECTED is the guard.
 */
namespace denim {

// {major[15:0], minor[15:0]}. Must track DENIM_VERSION in denim_cnfg.sv.
// 1.1 formalised register 6 and added SLV_CFG_PARTIAL at register 7 bit 1
// 1.2 added relative PSN
// 1.3 added the per-rule shot limit and the armed bitmap
constexpr uint32_t VERSION_EXPECTED = 0x0001'0003;

constexpr int N_RULES     = 8;
constexpr int N_GLOBAL    = 8;
constexpr int RULE_STRIDE = 8;
constexpr int N_REGS      = N_GLOBAL + N_RULES * RULE_STRIDE;   // 72

// Global registers
enum GlobalReg : uint32_t {
    REG_VERSION      = 0,   // RO  {major, minor}
    REG_CTRL         = 1,   // RW  [0] GLOBAL_EN, [1] CTR_CLEAR (self clearing)
    REG_PKT_COUNT    = 2,   // RO  {roce_pkts[63:32], all_pkts[31:0]}
    REG_EFFECT_COUNT = 3,   // RO  {delay_overflows[63:32], drops[31:0]}
    REG_ROCE_PORT    = 4,   // RW  [15:0] expected RoCE v2 UDP destination port
    REG_ECN_COUNT    = 5,   // RO  [31:0] packets this build actually marked
    REG_DEBUG        = 6,   // RO  config path observability, see DBG_* below
    REG_SLV_STATUS   = 7,   // RO  slave local, see SLV_* below
};

// REG_DEBUG fields. What the datapath received, as opposed to what software
// believes it sent.
constexpr int DBG_BEATS_SHIFT     = 0;    // [23:0]  config beats applied
constexpr int DBG_LAST_ADDR_SHIFT = 24;   // [31:24] address of the last beat
constexpr int DBG_LAST_DATA_SHIFT = 32;   // [47:32] low 16 bits of its data
constexpr int DBG_CAPTURED_SHIFT  = 48;   // [55:48] rules that captured a base PSN
constexpr int DBG_ARMED_SHIFT     = 56;   // [63:56] rules that may still fire

// CTRL bits
constexpr uint64_t CTRL_GLOBAL_EN = 1ull << 0;
constexpr uint64_t CTRL_CTR_CLEAR = 1ull << 1;

// REG_SLV_STATUS bits.
constexpr uint64_t SLV_CFG_LOST    = 1ull << 0;   // a config write was dropped
constexpr uint64_t SLV_CFG_PARTIAL = 1ull << 1;   // a sub-word write was seen

// Per-rule field offsets from base 8 + 8i
enum RuleField : uint32_t {
    FLD_ENABLE       = 0,   // RW  [0] enable, written last so arming is atomic
    FLD_MATCH_QPN    = 1,   // RW  [23:0] qpn, [32] field enable
    FLD_MATCH_PSN    = 2,   // RW  [23:0] lo, [55:32] hi, [56] enable, [57] relative
    FLD_MATCH_IP     = 3,   // RW  {dst[63:32], src[31:0]}
    FLD_MATCH_FLAGS  = 4,   // RW  [0] src_en, [1] dst_en, [2] op_en, [15:8] opcode
    FLD_EFFECT_MASK  = 5,   // RW  [3:0] {count, delay, drop, ecn}, [31:16] shots
    FLD_EFFECT_PARAM = 6,   // RW  [31:0] delay in nclk cycles
    FLD_COUNTERS     = 7,   // RO  {overflow[63:32], match[31:0]}
};

// Effect mask bit positions, matching EFF_* in denim_pkg.sv
constexpr uint8_t EFF_ECN   = 1u << 0;
constexpr uint8_t EFF_DROP  = 1u << 1;
constexpr uint8_t EFF_DELAY = 1u << 2;
constexpr uint8_t EFF_COUNT = 1u << 3;

constexpr uint32_t rule_reg(int slot, RuleField f) {
    return static_cast<uint32_t>(N_GLOBAL + slot * RULE_STRIDE) + f;
}

} // namespace denim
