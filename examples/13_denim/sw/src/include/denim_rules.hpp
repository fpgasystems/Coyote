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
#include <string>
#include <utility>
#include <vector>

/**
 * DENIM rule grammar.
 *
 *     <condition>[, <condition>...] : <effect>[, <effect>...]
 *
 * Conditions are AND-ed and omitted fields are wildcards. The first matching
 * rule wins and all of its effects apply.
 *
 *     qpn 3, psn 50-150   : delay 1us       # emulate queueing over a window
 *     src_ip 10.1.212.62  : ecn             # fake congestion per sender
 *     qpn 2, psn +100     : drop            # single loss at a relative PSN
 *     qpn 2               : count           # monitor only
 *     qpn 4, psn 0-500    : ecn, delay 2us  # two effects on one packet
 *
 * Conditions: qpn N | psn N | psn A-B | psn +K | src_ip a.b.c.d |
 *             dst_ip a.b.c.d | opcode 0xNN
 * Effects:    ecn | drop | delay <t>(ns|us) | count
 */
namespace denim {

struct Rule {
    bool     qpn_en = false;
    uint32_t qpn    = 0;

    bool     psn_en = false;
    uint32_t psn_lo = 0;
    uint32_t psn_hi = 0;

    // psn +K and psn +A-B are relative to the connection's initial PSN, which
    // only exists at run time.
    bool     psn_relative = false;

    bool     src_en = false;
    uint32_t ip_src = 0;
    bool     dst_en = false;
    uint32_t ip_dst = 0;

    bool     op_en  = false;
    uint8_t  opcode = 0;

    uint8_t  eff_mask     = 0;
    uint32_t delay_cycles = 0;

    // How many packets this rule may act on before it disarms itself
    uint32_t shots        = 0;
};

enum class ParseResult {
    Ok,      // a rule was parsed
    Skip,    // blank line or comment, not an error
    Error,   // malformed, err holds the reason
};

/**
 * Parse one line. nclk_mhz converts delay times into cycles and must match the
 * NCLK_F the bitstream was built with, or every delay will be wrong by that
 * ratio without anything reporting it.
 */
ParseResult parse_rule(const std::string &line, Rule &out, std::string &err,
                       uint32_t nclk_mhz);

/**
 * Resolve a relative PSN once the connection's initial PSN is known.
 */

/**
 * Register writes that install a rule into a slot, in order.
 */
std::vector<std::pair<uint32_t, uint64_t>> rule_to_csr_writes(const Rule &r, int slot);

/**
 * Writes that disarm a slot. A single ENABLE=0, leaving the fields intact so
 * that a rule can be edited and re-armed without rewriting all of it.
 */
std::vector<std::pair<uint32_t, uint64_t>> rule_clear_writes(int slot);

/**
 * Rebuild a rule from the eight register values of one slot, indexed by
 * RuleField. Used by --status, and the inverse of rule_to_csr_writes, so the
 * two are round-trip tested against each other.
 */
Rule rule_from_regs(const uint64_t reg[8], bool &enabled);

/**
 * Render a rule back to grammar form, for --status output.
 */
std::string rule_to_string(const Rule &r, uint32_t nclk_mhz);

} // namespace denim
