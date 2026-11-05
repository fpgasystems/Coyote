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

#include "include/denim_rules.hpp"
#include "include/denim_regs.hpp"

#include <algorithm>
#include <cctype>
#include <sstream>

namespace denim {

namespace {

std::string trim(const std::string &s) {
    auto b = s.find_first_not_of(" \t\r\n");
    if (b == std::string::npos) return {};
    auto e = s.find_last_not_of(" \t\r\n");
    return s.substr(b, e - b + 1);
}

std::vector<std::string> split(const std::string &s, char sep) {
    std::vector<std::string> out;
    size_t start = 0;
    for (;;) {
        const auto p = s.find(sep, start);
        if (p == std::string::npos) {
            out.push_back(trim(s.substr(start)));
            return out;
        }
        out.push_back(trim(s.substr(start, p - start)));
        start = p + 1;
    }
}

std::vector<std::string> words(const std::string &s) {
    std::vector<std::string> out;
    std::istringstream is(s);
    std::string w;
    while (is >> w) out.push_back(w);
    return out;
}

bool parse_uint(const std::string &s, uint64_t &out) {
    if (s.empty()) return false;
    size_t pos = 0;
    int base = 10;
    std::string body = s;
    if (s.size() > 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
        base = 16;
        body = s.substr(2);
        if (body.empty()) return false;
    }
    try {
        out = std::stoull(body, &pos, base);
    } catch (...) {
        return false;
    }
    return pos == body.size();
}

bool parse_ipv4(const std::string &s, uint32_t &out) {
    auto parts = split(s, '.');
    if (parts.size() != 4) return false;
    uint32_t v = 0;
    for (const auto &p : parts) {
        uint64_t o = 0;
        if (p.empty() || !parse_uint(p, o) || o > 255) return false;
        v = (v << 8) | static_cast<uint32_t>(o);
    }
    out = v;
    return true;
}

// "1us" or "500ns" into network clock cycles. Nanoseconds are computed as
// value * mhz / 1000, which truncates: at 250 MHz the finest representable
bool parse_delay(const std::string &s, uint32_t nclk_mhz, uint32_t &cycles,
                 std::string &err) {
    if (nclk_mhz == 0) {
        err = "network clock frequency is zero";
        return false;
    }
    size_t unit = s.find_first_not_of("0123456789");
    if (unit == std::string::npos || unit == 0) {
        err = "delay '" + s + "' needs a value and a unit, e.g. 1us or 500ns";
        return false;
    }
    uint64_t value = 0;
    if (!parse_uint(s.substr(0, unit), value)) {
        err = "delay '" + s + "' has a malformed value";
        return false;
    }
    const std::string suffix = s.substr(unit);

    uint64_t c;
    if (suffix == "us") {
        c = value * nclk_mhz;
    } else if (suffix == "ns") {
        c = value * nclk_mhz / 1000;
        if (c == 0 && value != 0) {
            err = "delay '" + s + "' is shorter than one clock cycle at " +
                  std::to_string(nclk_mhz) + " MHz";
            return false;
        }
    } else {
        err = "delay unit '" + suffix + "' is not ns or us";
        return false;
    }

    if (c > 0xFFFFFFFFull) {
        err = "delay '" + s + "' does not fit in 32 bits of cycles";
        return false;
    }
    cycles = static_cast<uint32_t>(c);
    return true;
}

// A relative window that includes offset zero can never match. The base is
// captured from the packet that arms the rule.
bool check_relative_zero(const Rule &r, const std::string &arg, std::string &err) {
    if (r.psn_relative && r.psn_lo == 0) {
        err = "psn '" + arg + "' includes offset 0, which can never match: the "
              "base is captured from that packet, not matched against it";
        return false;
    }
    return true;
}

bool parse_condition(const std::string &cond, Rule &r, std::string &err) {
    const auto w = words(cond);
    if (w.empty()) {
        err = "empty condition";
        return false;
    }
    const std::string &key = w[0];

    if (w.size() != 2) {
        err = "condition '" + key + "' expects one argument";
        return false;
    }
    const std::string &arg = w[1];

    if (key == "qpn") {
        uint64_t v;
        if (!parse_uint(arg, v) || v > 0xFFFFFF) {
            err = "qpn '" + arg + "' is not a 24 bit value";
            return false;
        }
        r.qpn_en = true;
        r.qpn = static_cast<uint32_t>(v);
        return true;
    }

    if (key == "psn") {
        r.psn_en = true;

        std::string body = arg;
        if (body[0] == '+') {
            r.psn_relative = true;
            body = body.substr(1);
            if (body.empty()) {
                err = "psn '" + arg + "' needs an offset after the '+'";
                return false;
            }
        }
        const std::string &arg_ = body;

        const auto dash = arg_.find('-');
        if (dash != std::string::npos) {
            uint64_t lo, hi;
            if (!parse_uint(arg_.substr(0, dash), lo) ||
                !parse_uint(arg_.substr(dash + 1), hi)) {
                err = "psn range '" + arg + "' is malformed";
                return false;
            }
            if (lo > hi) {
                err = "psn range '" + arg + "' has its bounds reversed";
                return false;
            }
            if (hi > 0xFFFFFF) {
                err = "psn range '" + arg + "' exceeds 24 bits";
                return false;
            }
            r.psn_lo = static_cast<uint32_t>(lo);
            r.psn_hi = static_cast<uint32_t>(hi);
            return check_relative_zero(r, arg, err);
        }
        uint64_t v;
        if (!parse_uint(arg_, v) || v > 0xFFFFFF) {
            err = "psn '" + arg + "' is not a 24 bit value";
            return false;
        }
        r.psn_lo = r.psn_hi = static_cast<uint32_t>(v);
        return check_relative_zero(r, arg, err);
    }

    if (key == "src_ip" || key == "dst_ip") {
        uint32_t ip;
        if (!parse_ipv4(arg, ip)) {
            err = key + " '" + arg + "' is not a dotted quad";
            return false;
        }
        if (key == "src_ip") {
            r.src_en = true;
            r.ip_src = ip;
        } else {
            r.dst_en = true;
            r.ip_dst = ip;
        }
        return true;
    }

    if (key == "opcode") {
        uint64_t v;
        if (!parse_uint(arg, v) || v > 0xFF) {
            err = "opcode '" + arg + "' is not an 8 bit value";
            return false;
        }
        r.op_en = true;
        r.opcode = static_cast<uint8_t>(v);
        return true;
    }

    err = "unknown condition '" + key + "'";
    return false;
}

bool parse_effect(const std::string &eff, Rule &r, uint32_t nclk_mhz,
                  std::string &err) {
    const auto w = words(eff);
    if (w.empty()) {
        err = "empty effect";
        return false;
    }
    const std::string &key = w[0];

    if (key == "ecn" || key == "drop" || key == "count") {
        if (w.size() != 1) {
            err = "effect '" + key + "' takes no argument";
            return false;
        }
        r.eff_mask |= (key == "ecn") ? EFF_ECN : (key == "drop") ? EFF_DROP : EFF_COUNT;
        return true;
    }

    if (key == "once") {
        if (w.size() != 1) {
            err = "'once' takes no argument";
            return false;
        }
        r.shots = 1;
        return true;
    }

    if (key == "shots") {
        if (w.size() != 2) {
            err = "'shots' needs a count, e.g. shots 6";
            return false;
        }
        uint64_t v;
        if (!parse_uint(w[1], v) || v == 0 || v > 0xFFFF) {
            err = "shots '" + w[1] + "' is not a count between 1 and 65535";
            return false;
        }
        r.shots = static_cast<uint32_t>(v);
        return true;
    }

    if (key == "delay") {
        if (w.size() != 2) {
            err = "effect 'delay' needs a time, e.g. delay 1us";
            return false;
        }
        uint32_t cycles;
        if (!parse_delay(w[1], nclk_mhz, cycles, err)) return false;
        r.eff_mask |= EFF_DELAY;
        r.delay_cycles = cycles;
        return true;
    }

    err = "unknown effect '" + key + "'";
    return false;
}

} // namespace

ParseResult parse_rule(const std::string &line, Rule &out, std::string &err,
                       uint32_t nclk_mhz) {
    out = Rule{};
    err.clear();

    std::string body = line;
    const auto hash = body.find('#');
    if (hash != std::string::npos) body = body.substr(0, hash);
    body = trim(body);
    if (body.empty()) return ParseResult::Skip;

    const auto colon = body.find(':');
    if (colon == std::string::npos) {
        err = "no ':' separating conditions from effects";
        return ParseResult::Error;
    }

    const std::string lhs = trim(body.substr(0, colon));
    const std::string rhs = trim(body.substr(colon + 1));

    if (rhs.empty()) {
        err = "no effects given";
        return ParseResult::Error;
    }

    // An empty left side is a rule with no conditions. It matches every RoCE
    // packet. Allowed but easy to write by accident.
    if (!lhs.empty()) {
        for (const auto &c : split(lhs, ',')) {
            if (c.empty()) {
                err = "empty condition, check for a stray comma";
                return ParseResult::Error;
            }
            if (!parse_condition(c, out, err)) return ParseResult::Error;
        }
    }

    for (const auto &e : split(rhs, ',')) {
        if (e.empty()) {
            err = "empty effect, check for a stray comma";
            return ParseResult::Error;
        }
        if (!parse_effect(e, out, nclk_mhz, err)) return ParseResult::Error;
    }

    return ParseResult::Ok;
}

std::vector<std::pair<uint32_t, uint64_t>> rule_to_csr_writes(const Rule &r, int slot) {
    std::vector<std::pair<uint32_t, uint64_t>> w;

    w.emplace_back(rule_reg(slot, FLD_MATCH_QPN),
                   (r.qpn_en ? (1ull << 32) : 0ull) | r.qpn);

    w.emplace_back(rule_reg(slot, FLD_MATCH_PSN),
                   (r.psn_en ? (1ull << 56) : 0ull) |
                   (r.psn_relative ? (1ull << 57) : 0ull) |
                   (static_cast<uint64_t>(r.psn_hi) << 32) | r.psn_lo);

    w.emplace_back(rule_reg(slot, FLD_MATCH_IP),
                   (static_cast<uint64_t>(r.ip_dst) << 32) | r.ip_src);

    w.emplace_back(rule_reg(slot, FLD_MATCH_FLAGS),
                   (r.src_en ? 1ull : 0ull) |
                   (r.dst_en ? 2ull : 0ull) |
                   (r.op_en  ? 4ull : 0ull) |
                   (static_cast<uint64_t>(r.opcode) << 8));

    w.emplace_back(rule_reg(slot, FLD_EFFECT_MASK),
                   (static_cast<uint64_t>(r.shots) << 16) | r.eff_mask);
    w.emplace_back(rule_reg(slot, FLD_EFFECT_PARAM), r.delay_cycles);

    w.emplace_back(rule_reg(slot, FLD_ENABLE), 1ull);
    return w;
}

std::vector<std::pair<uint32_t, uint64_t>> rule_clear_writes(int slot) {
    return {{rule_reg(slot, FLD_ENABLE), 0ull}};
}

Rule rule_from_regs(const uint64_t reg[8], bool &enabled) {
    Rule r;
    enabled = (reg[FLD_ENABLE] & 1ull) != 0;

    r.qpn_en = (reg[FLD_MATCH_QPN] >> 32) & 1ull;
    r.qpn    = static_cast<uint32_t>(reg[FLD_MATCH_QPN] & 0xFFFFFFull);

    r.psn_en       = (reg[FLD_MATCH_PSN] >> 56) & 1ull;
    r.psn_relative = (reg[FLD_MATCH_PSN] >> 57) & 1ull;
    r.psn_lo       = static_cast<uint32_t>(reg[FLD_MATCH_PSN] & 0xFFFFFFull);
    r.psn_hi       = static_cast<uint32_t>((reg[FLD_MATCH_PSN] >> 32) & 0xFFFFFFull);

    r.ip_src = static_cast<uint32_t>(reg[FLD_MATCH_IP] & 0xFFFFFFFFull);
    r.ip_dst = static_cast<uint32_t>(reg[FLD_MATCH_IP] >> 32);

    r.src_en = reg[FLD_MATCH_FLAGS] & 1ull;
    r.dst_en = (reg[FLD_MATCH_FLAGS] >> 1) & 1ull;
    r.op_en  = (reg[FLD_MATCH_FLAGS] >> 2) & 1ull;
    r.opcode = static_cast<uint8_t>((reg[FLD_MATCH_FLAGS] >> 8) & 0xFFull);

    r.eff_mask     = static_cast<uint8_t>(reg[FLD_EFFECT_MASK] & 0xFull);
    r.shots        = static_cast<uint32_t>((reg[FLD_EFFECT_MASK] >> 16) & 0xFFFFull);
    r.delay_cycles = static_cast<uint32_t>(reg[FLD_EFFECT_PARAM] & 0xFFFFFFFFull);

    // Bit 57 says the bounds are offsets rather than absolute PSNs.
    return r;
}

std::string rule_to_string(const Rule &r, uint32_t nclk_mhz) {
    std::ostringstream os;
    std::vector<std::string> conds;

    if (r.qpn_en) conds.push_back("qpn " + std::to_string(r.qpn));
    if (r.psn_en) {
        const std::string rel = r.psn_relative ? "+" : "";
        if (r.psn_lo == r.psn_hi) {
            conds.push_back("psn " + rel + std::to_string(r.psn_lo));
        } else {
            conds.push_back("psn " + rel + std::to_string(r.psn_lo) + "-" +
                            std::to_string(r.psn_hi));
        }
    }
    auto ip_str = [](uint32_t v) {
        return std::to_string((v >> 24) & 0xFF) + "." + std::to_string((v >> 16) & 0xFF) +
               "." + std::to_string((v >> 8) & 0xFF) + "." + std::to_string(v & 0xFF);
    };
    if (r.src_en) conds.push_back("src_ip " + ip_str(r.ip_src));
    if (r.dst_en) conds.push_back("dst_ip " + ip_str(r.ip_dst));
    if (r.op_en) {
        std::ostringstream o;
        o << "opcode 0x" << std::hex << static_cast<int>(r.opcode);
        conds.push_back(o.str());
    }

    for (size_t i = 0; i < conds.size(); i++) {
        os << conds[i];
        if (i + 1 < conds.size()) os << ", ";
    }

    os << " : ";
    std::vector<std::string> effs;
    if (r.eff_mask & EFF_ECN) effs.push_back("ecn");
    if (r.eff_mask & EFF_DROP) effs.push_back("drop");
    if (r.eff_mask & EFF_DELAY) {
        if (nclk_mhz != 0 && r.delay_cycles % nclk_mhz == 0) {
            effs.push_back("delay " + std::to_string(r.delay_cycles / nclk_mhz) + "us");
        } else if (nclk_mhz != 0) {
            effs.push_back("delay " + std::to_string(r.delay_cycles * 1000 / nclk_mhz) + "ns");
        } else {
            effs.push_back("delay " + std::to_string(r.delay_cycles) + "cyc");
        }
    }
    if (r.eff_mask & EFF_COUNT) effs.push_back("count");
    if (effs.empty()) effs.push_back("(none)");
    if (r.shots == 1)      effs.push_back("once");
    else if (r.shots != 0) effs.push_back("shots " + std::to_string(r.shots));

    for (size_t i = 0; i < effs.size(); i++) {
        os << effs[i];
        if (i + 1 < effs.size()) os << ", ";
    }
    return os.str();
}

} // namespace denim
