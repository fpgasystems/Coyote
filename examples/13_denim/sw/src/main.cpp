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

#include <algorithm>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <string>
#include <vector>

#include <boost/program_options.hpp>
#include <coyote/cThread.hpp>

#include "include/denim_regs.hpp"
#include "include/denim_rules.hpp"

using namespace denim;

constexpr uint32_t DEF_DEVICE = 0;
constexpr uint32_t DEF_VFID   = 0;
constexpr uint32_t DEF_NCLK   = 250;   // must match the NCLK_F of the bitstream

namespace {

void write_regs(coyote::cThread &t,
                const std::vector<std::pair<uint32_t, uint64_t>> &writes) {
    // Note the argument order: setCSR takes the value first, the address
    // second. Reversing them writes an address into a register.
    for (const auto &w : writes) t.setCSR(w.second, w.first);
}

uint16_t shell_minor = 0;

bool check_version(coyote::cThread &t) {
    const uint32_t v     = static_cast<uint32_t>(t.getCSR(REG_VERSION));
    const uint16_t major = v >> 16,          minor = v & 0xFFFF;
    shell_minor = minor;
    const uint16_t want_major = VERSION_EXPECTED >> 16,
                   want_minor = VERSION_EXPECTED & 0xFFFF;

    if (major != want_major) {
        std::cerr << "denim_ctl: register map mismatch. Shell reports "
                  << major << "." << minor << ", this build expects "
                  << want_major << "." << want_minor << "\n"
                  << "  Major versions differ, so the register map is not "
                     "compatible. Rebuild one to match the other.\n";
        return false;
    }
    if (minor != want_minor) {
        std::cerr << "denim_ctl: shell is " << major << "." << minor
                  << ", this build expects " << want_major << "." << want_minor
                  << ". Continuing -- the map is compatible, but fields added "
                     "after " << major << "." << minor << " read as zero.\n";
    }
    return true;
}

void set_global_en(coyote::cThread &t, bool on) {
    const uint64_t ctrl = t.getCSR(REG_CTRL);
    t.setCSR(on ? (ctrl | CTRL_GLOBAL_EN) : (ctrl & ~CTRL_GLOBAL_EN), REG_CTRL);
}

void clear_slot(coyote::cThread &t, int slot) {
    write_regs(t, rule_clear_writes(slot));
}

/**
 * Install a rule and confirm if it was successful.
 */
bool install_rule(coyote::cThread &t, int slot, const Rule &r, uint32_t nclk_mhz) {
    if (r.shots != 0 && shell_minor < 3) {
        std::cerr << "denim_ctl: this shell is 1." << shell_minor
                  << " and has no shot limit, so 'once' and 'shots' cannot be "
                     "honoured.\n";
        return false;
    }
    clear_slot(t, slot);
    write_regs(t, rule_to_csr_writes(r, slot));

    uint64_t reg[RULE_STRIDE];
    for (int f = 0; f < RULE_STRIDE; f++)
        reg[f] = t.getCSR(rule_reg(slot, static_cast<RuleField>(f)));

    bool enabled = false;
    const Rule back = rule_from_regs(reg, enabled);
    if (!enabled || rule_to_string(back, nclk_mhz) != rule_to_string(r, nclk_mhz)) {
        std::cerr << "denim_ctl: slot " << slot << " did not take.\n"
                  << "  wrote: " << rule_to_string(r, nclk_mhz) << "\n"
                  << "  read:  " << (enabled ? rule_to_string(back, nclk_mhz)
                                             : std::string("(disarmed)")) << "\n";
        return false;
    }
    return true;
}

int load_file(coyote::cThread &t, const std::string &path, uint32_t nclk_mhz) {
    std::ifstream in(path);
    if (!in) {
        std::cerr << "denim_ctl: cannot open " << path << "\n";
        return 1;
    }

    std::vector<Rule> rules;
    std::string line;
    int lineno = 0;
    while (std::getline(in, line)) {
        lineno++;
        Rule r;
        std::string err;
        switch (parse_rule(line, r, err, nclk_mhz)) {
            case ParseResult::Skip:
                continue;
            case ParseResult::Error:
                std::cerr << path << ":" << lineno << ": " << err << "\n";
                return 1;
            case ParseResult::Ok:
                rules.push_back(r);
                break;
        }
    }

    if (static_cast<int>(rules.size()) > N_RULES) {
        std::cerr << path << ": " << rules.size() << " rules, but only " << N_RULES
                  << " slots exist\n";
        return 1;
    }

    // Drop GLOBAL_EN first so that no intermediate state goes live while the
    // slots are rewritten, then re-enable once every slot is settled.
    set_global_en(t, false);
    for (int i = 0; i < N_RULES; i++) clear_slot(t, i);

    for (size_t i = 0; i < rules.size(); i++) {
        if (!install_rule(t, static_cast<int>(i), rules[i], nclk_mhz)) return 1;
        std::cout << "slot " << i << ": " << rule_to_string(rules[i], nclk_mhz) << "\n";
    }
    set_global_en(t, true);

    std::cout << rules.size() << " rule(s) installed, GLOBAL_EN set\n";
    return 0;
}

void print_status(coyote::cThread &t, uint32_t nclk_mhz) {
    const uint64_t ver   = t.getCSR(REG_VERSION);
    const uint64_t ctrl  = t.getCSR(REG_CTRL);
    const uint64_t pkts  = t.getCSR(REG_PKT_COUNT);
    const uint64_t effs  = t.getCSR(REG_EFFECT_COUNT);
    const uint64_t port  = t.getCSR(REG_ROCE_PORT);
    const uint64_t ecn   = t.getCSR(REG_ECN_COUNT);
    const uint64_t slv   = t.getCSR(REG_SLV_STATUS);

    std::cout << "DENIM " << ((ver >> 16) & 0xFFFF) << "." << (ver & 0xFFFF)
              << "   global_en=" << ((ctrl & CTRL_GLOBAL_EN) ? 1 : 0)
              << "   roce_udp_port=0x" << std::hex << (port & 0xFFFF) << std::dec << "\n\n";

    std::cout << "  packets seen      " << (pkts & 0xFFFFFFFF) << "\n"
              << "  parsed as RoCE    " << (pkts >> 32) << "\n"
              << "  marked ECN        " << (ecn & 0xFFFFFFFF) << "\n"
              << "  dropped           " << (effs & 0xFFFFFFFF) << "\n"
              << "  delay overflows   " << (effs >> 32) << "\n";

    if (slv & SLV_CFG_LOST) {
        std::cout << "\n  WARNING: a configuration write was lost; installed rules "
                     "may not match what was asked for\n";
    }
    if (slv & SLV_CFG_PARTIAL) {
        std::cout << "\n  WARNING: a sub-word configuration write was seen. A whole "
                     "register crosses at a time, so it was forwarded with bytes "
                     "the host did not write\n";
    }

    bool any_enabled = false;

    // Which relative rules have latched a base PSN.
    const uint64_t dbg      = t.getCSR(REG_DEBUG);
    const uint64_t captured = (dbg >> DBG_CAPTURED_SHIFT) & 0xFF;

    // Which rules may still fire.
    const uint64_t armed    = (dbg >> DBG_ARMED_SHIFT) & 0xFF;

    std::cout << "\nslot  matched     overflow    rule\n";
    for (int i = 0; i < N_RULES; i++) {
        uint64_t reg[RULE_STRIDE];
        for (int f = 0; f < RULE_STRIDE; f++)
            reg[f] = t.getCSR(rule_reg(i, static_cast<RuleField>(f)));

        bool enabled = false;
        const Rule r = rule_from_regs(reg, enabled);
        const uint64_t counters = reg[FLD_COUNTERS];
        any_enabled |= enabled;

        std::cout << std::setw(4) << i << "  " << std::setw(10)
                  << (counters & 0xFFFFFFFF) << "  " << std::setw(10) << (counters >> 32)
                  << "    " << (enabled ? rule_to_string(r, nclk_mhz)
                                        : std::string("(empty)"))
                  << (enabled && r.psn_relative
                          ? ((captured >> i) & 1 ? "   [base captured]"
                                                 : "   [waiting for first packet]")
                          : "")
                  << (enabled && r.shots != 0
                          ? ((armed >> i) & 1
                                 ? "   [" + std::to_string(r.shots - std::min<uint32_t>(r.shots, counters & 0xFFFFFFFF)) + " of " + std::to_string(r.shots) + " shots left]"
                                 : std::string("   [spent]"))
                          : std::string(""))
                  << "\n";
    }

    if (any_enabled && !(ctrl & CTRL_GLOBAL_EN)) {
        std::cout << "\nNote: rules are installed but GLOBAL_EN is 0, so none of them "
                     "can match. Arm with --global-en 1.\n";
    }

    if ((pkts >> 32) == 0 && (pkts & 0xFFFFFFFF) != 0) {
        std::cout << "\nNote: packets are arriving but none parsed as RoCE v2. Check "
                     "roce_udp_port against what the peer actually sends.\n";
    }
}

} // namespace

int main(int argc, char *argv[]) {
    boost::program_options::options_description opts("denim_ctl options");
    opts.add_options()
        ("help,h", "this message")
        ("device", boost::program_options::value<uint32_t>(), "Coyote device id")
        ("vfpga", boost::program_options::value<uint32_t>(), "target vFPGA id")
        ("nclk", boost::program_options::value<uint32_t>(),
            "network clock in MHz, must match the bitstream's NCLK_F")
        ("load", boost::program_options::value<std::string>(),
            "install a rule file; line i goes to slot i, so file order is match priority")
        ("slot", boost::program_options::value<int>(), "slot for --rule")
        ("rule", boost::program_options::value<std::string>(),
            "a single rule to install into --slot")
        ("clear", boost::program_options::value<int>()->implicit_value(-1),
            "disarm one slot, or every slot if given no argument")
        ("global-en", boost::program_options::value<int>(),
            "set GLOBAL_EN; 0 disarms every rule without erasing it")
        ("clear-counters", "zero all counters")
        ("roce-port", boost::program_options::value<std::string>(),
            "override the expected RoCE v2 UDP destination port, e.g. 0x12b7")
        ("status", "print counters and the installed rules")
        ("peek", boost::program_options::value<int>(), "read one register by index")
        ("poke", boost::program_options::value<std::string>(),
            "write one register: --poke <index>=<value>, both accepting 0x")
        ("scan", "write a probe value to every writable register and report which took")
        ("debug", "decode the datapath observability register");

    boost::program_options::variables_map args;
    boost::program_options::store(
        boost::program_options::parse_command_line(argc, argv, opts), args);
    boost::program_options::notify(args);

    if (args.count("help") || argc == 1) {
        std::cout << opts << "\n";
        return 0;
    }

    const uint32_t device   = args.count("device") ? args["device"].as<uint32_t>() : DEF_DEVICE;
    const uint32_t vfid     = args.count("vfpga") ? args["vfpga"].as<uint32_t>() : DEF_VFID;
    const uint32_t nclk_mhz = args.count("nclk") ? args["nclk"].as<uint32_t>() : DEF_NCLK;

    coyote::cThread cthread(vfid, getpid(), device);

    if (!check_version(cthread)) return 1;

    if (args.count("roce-port")) {
        const std::string s = args["roce-port"].as<std::string>();
        const uint64_t p = std::stoull(s, nullptr, 0);
        cthread.setCSR(p & 0xFFFF, REG_ROCE_PORT);
        std::cout << "roce_udp_port set to 0x" << std::hex << (p & 0xFFFF) << std::dec << "\n";
    }

    if (args.count("clear")) {
        const int slot = args["clear"].as<int>();
        if (slot < 0) {
            for (int i = 0; i < N_RULES; i++) clear_slot(cthread, i);
            std::cout << "all slots disarmed\n";
        } else if (slot >= N_RULES) {
            std::cerr << "denim_ctl: slot " << slot << " does not exist, there are "
                      << N_RULES << "\n";
            return 1;
        } else {
            clear_slot(cthread, slot);
            std::cout << "slot " << slot << " disarmed\n";
        }
    }

    if (args.count("clear-counters")) {
        const uint64_t ctrl = cthread.getCSR(REG_CTRL);
        cthread.setCSR(ctrl | CTRL_CTR_CLEAR, REG_CTRL);
        std::cout << "counters cleared\n";
    }

    if (args.count("load")) {
        const int rc = load_file(cthread, args["load"].as<std::string>(), nclk_mhz);
        if (rc) return rc;
    }

    if (args.count("rule")) {
        if (!args.count("slot")) {
            std::cerr << "denim_ctl: --rule needs --slot\n";
            return 1;
        }
        const int slot = args["slot"].as<int>();
        if (slot < 0 || slot >= N_RULES) {
            std::cerr << "denim_ctl: slot " << slot << " does not exist, there are "
                      << N_RULES << "\n";
            return 1;
        }

        Rule r;
        std::string err;
        const auto res = parse_rule(args["rule"].as<std::string>(), r, err, nclk_mhz);
        if (res != ParseResult::Ok) {
            std::cerr << "denim_ctl: " << (err.empty() ? "not a rule" : err) << "\n";
            return 1;
        }
        if (!install_rule(cthread, slot, r, nclk_mhz)) return 1;
        std::cout << "slot " << slot << ": " << rule_to_string(r, nclk_mhz) << "\n";

        // --load arms the table itself, this path is the incremental edit and
        // deliberately leaves GLOBAL_EN alone, which after programming means
        // off.
        if (!(cthread.getCSR(REG_CTRL) & CTRL_GLOBAL_EN)) {
            std::cout << "warning: GLOBAL_EN is 0, so no rule will match. "
                         "Arm with --global-en 1\n";
        }
    }

    if (args.count("global-en")) {
        const bool on = args["global-en"].as<int>() != 0;
        set_global_en(cthread, on);
        std::cout << "GLOBAL_EN " << (on ? "set" : "cleared") << "\n";
    }

    if (args.count("peek")) {
        const int r = args["peek"].as<int>();
        std::cout << "reg " << r << " = 0x" << std::hex << std::setw(16)
                  << std::setfill('0') << cthread.getCSR(r) << std::dec
                  << std::setfill(' ') << "\n";
    }

    if (args.count("poke")) {
        const std::string s = args["poke"].as<std::string>();
        const auto eq = s.find('=');
        if (eq == std::string::npos) {
            std::cerr << "denim_ctl: --poke needs <index>=<value>\n";
            return 1;
        }
        const uint32_t r = std::stoul(s.substr(0, eq), nullptr, 0);
        const uint64_t v = std::stoull(s.substr(eq + 1), nullptr, 0);
        cthread.setCSR(v, r);
        std::cout << "reg " << r << " <- 0x" << std::hex << v << ", reads back 0x"
                  << cthread.getCSR(r) << std::dec << "\n";
    }

    // Writes a distinct probe to every writable register and reports which
    // ones held it. A register that reads back its probe is reachable, one
    // that does not is either read only or not being decoded.
    if (args.count("scan")) {
        std::cout << "reg   wrote               read back           result\n";
        int reachable = 0, dead = 0;
        for (int r = 0; r < N_REGS; r++) {
            const bool ro = (r == REG_VERSION || r == REG_PKT_COUNT ||
                             r == REG_EFFECT_COUNT || r == REG_ECN_COUNT ||
                             r == REG_SLV_STATUS ||
                             (r >= N_GLOBAL && ((r - N_GLOBAL) % RULE_STRIDE) == FLD_COUNTERS));
            if (ro) continue;

            const uint64_t probe = 0xA5A50000ull | static_cast<uint64_t>(r);
            const uint64_t before = cthread.getCSR(r);
            cthread.setCSR(probe, r);
            const uint64_t after = cthread.getCSR(r);
            const bool took = (after == probe);
            took ? reachable++ : dead++;
            std::cout << std::setw(3) << r << "   0x" << std::hex << std::setw(16)
                      << std::setfill('0') << probe << "  0x" << std::setw(16) << after
                      << std::dec << std::setfill(' ') << "  " << (took ? "ok" : "NOT WRITTEN")
                      << "\n";
            cthread.setCSR(before, r);
        }
        std::cout << "\n" << reachable << " reachable, " << dead << " not written\n";
        std::cout << "Registers restored to their previous values.\n";
    }

    // What the datapath received, as opposed to what software believes it sent.
    if (args.count("debug")) {
        const uint64_t d = cthread.getCSR(REG_DEBUG);
        std::cout << "config beats applied : "
                  << ((d >> DBG_BEATS_SHIFT) & 0xFFFFFF) << "\n"
                  << "last address seen    : "
                  << ((d >> DBG_LAST_ADDR_SHIFT) & 0xFF) << "\n"
                  << "last data[15:0]      : 0x" << std::hex
                  << ((d >> DBG_LAST_DATA_SHIFT) & 0xFFFF) << std::dec << "\n";
    }

    if (args.count("status")) print_status(cthread, nclk_mhz);

    return 0;
}
