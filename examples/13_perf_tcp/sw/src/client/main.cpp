/**
 * This file is part of Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025-2026, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <iostream>
#include <sstream>
#include <string>
#include <cstdint>
#include <vector>
#include <unistd.h>

#include <boost/program_options.hpp>

#include <coyote/cThread.hpp>

#define DEFAULT_VFPGA_ID 0

// HW register map (AXI-Lite, defined in perf_tcp_axi_ctrl_parser.sv)
// 0: START_CLIENT  (WR, bit[0]=start; auto-cleared when client FSM leaves idle)
// 1: N_SESSIONS    (WR, [15:0]  -- number of TCP sessions)
// 2: PKG_WORD_COUNT(WR, [31:0]  -- payload words per packet; payload = PKG_WORD_COUNT * 64 B)
// 3: SESSION_ID    (WR, [15:0]  -- write once per session; each write injects one session ID)
// 4: CLK_FREQ      (WR, [31:0]  -- design clock frequency in Hz)
// 5: DURATION      (WR, [31:0]  -- benchmark duration in seconds)
// 6: CLIENT_STATE  (RO, [3:0]   -- current FSM state of the client HLS module)
enum class PerfRegs : uint32_t {
    START_CLIENT    = 0,
    N_SESSIONS      = 1,
    PKG_WORD_COUNT  = 2,
    SESSION_ID      = 3,
    CLK_FREQ        = 4,
    DURATION        = 5,
    CLIENT_STATE    = 6
};

// "A.B.C.D" -> 0xAABBCCDD (big-endian)
static uint32_t parseIpBE(const std::string& ip_str) {
    std::istringstream iss(ip_str);
    std::string tok;
    uint32_t b[4];
    int i = 0;
    while (std::getline(iss, tok, '.')) {
        if (i >= 4) throw std::invalid_argument("IP has more than 4 octets");
        char* endp = nullptr;
        long v = std::strtol(tok.c_str(), &endp, 10);
        if (*endp != '\0' || v < 0 || v > 255)
            throw std::invalid_argument(std::string("Invalid IP octet: ") + tok);
        b[i++] = static_cast<uint32_t>(v);
    }
    if (i != 4) throw std::invalid_argument("IP must have 4 octets");
    return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
}

int main(int argc, char* argv[]) {
    std::string ip_str;
    uint16_t sessions, port;
    uint32_t words, timeS, clk_freq;

    boost::program_options::options_description runtime_options("Coyote Example 13: TCP Perf Client");
    runtime_options.add_options()
        ("ip,i",       boost::program_options::value<std::string>(&ip_str)->required(),             "Server IP address (A.B.C.D, required)")
        ("sessions,s", boost::program_options::value<uint16_t>(&sessions)->default_value(1),        "Number of TCP sessions")
        ("words,w",    boost::program_options::value<uint32_t>(&words)->default_value(16),           "Payload words per packet (payload = words * 64 B)")
        ("time,t",     boost::program_options::value<uint32_t>(&timeS)->default_value(10),           "Benchmark duration in seconds")
        ("port,p",     boost::program_options::value<uint16_t>(&port)->default_value(5001),          "Server TCP port")
        ("clk-freq,f", boost::program_options::value<uint32_t>(&clk_freq)->default_value(250000000), "Design clock frequency in Hz");

    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    uint32_t ip_be = parseIpBE(ip_str);

    std::cout << "Server IP:    " << ip_str << " (0x" << std::hex << ip_be << std::dec << ")" << std::endl;
    std::cout << "Server port:  " << port     << std::endl;
    std::cout << "Sessions:     " << sessions  << std::endl;
    std::cout << "Words/packet: " << words     << " (" << words * 64 << " B)" << std::endl;
    std::cout << "Duration:     " << timeS     << " s" << std::endl;
    std::cout << "Clock freq:   " << clk_freq  << " Hz" << std::endl;

    coyote::cThread coyote_thread(DEFAULT_VFPGA_ID, getpid());

    // Open TCP connections to server & collect session IDs
    std::vector<uint16_t> session_ids;
    session_ids.reserve(sessions);
    for (uint16_t i = 0; i < sessions; i++) {
        uint16_t sid = coyote_thread.openConnTcp(ip_be, port);
        session_ids.push_back(sid);
        std::cout << "Connection " << i << " -> session_id=" << sid << std::endl;
    }

    // Write config registers before writing session IDs and asserting start
    coyote_thread.setCSR(static_cast<uint64_t>(sessions), (uint32_t)PerfRegs::N_SESSIONS);
    coyote_thread.setCSR(static_cast<uint64_t>(words),    (uint32_t)PerfRegs::PKG_WORD_COUNT);
    coyote_thread.setCSR(static_cast<uint64_t>(clk_freq), (uint32_t)PerfRegs::CLK_FREQ);
    coyote_thread.setCSR(static_cast<uint64_t>(timeS),    (uint32_t)PerfRegs::DURATION);

    for (uint16_t sid : session_ids) {
        coyote_thread.setCSR(static_cast<uint64_t>(sid), (uint32_t)PerfRegs::SESSION_ID);
        usleep(1000);
    }

    // Start client
    coyote_thread.setCSR(1ULL, (uint32_t)PerfRegs::START_CLIENT);

    // Wait until client leaves idle state
    while (coyote_thread.getCSR((uint32_t)PerfRegs::CLIENT_STATE) == 0) {
        sleep(1);
    }

    // Wait for benchmark to complete
    sleep(timeS);

    // Wait until client finalizes benchmark
    while (coyote_thread.getCSR((uint32_t)PerfRegs::CLIENT_STATE) != 0) {
        sleep(1);
    }

    // Close connections & exit
    for (uint16_t sid : session_ids) {
        coyote_thread.closeConnTcp(sid);
    }

    std::cout << "Done." << std::endl;
    return EXIT_SUCCESS;
}
