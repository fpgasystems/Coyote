// tcp_perf_client_host.cpp (updated for new AXI-Lite map)
// Options: --help/-h, --ip (required), --sessions, --words, --freq, --time

#include <iostream>
#include <sstream>
#include <string>
#include <stdexcept>
#include <cstdint>
#include <algorithm>
#include <boost/program_options.hpp>
#include <unistd.h>   // getpid
#include "cThread.hpp"

#define DEFAULT_VFPGA_ID 0
#define MHZ (1024ULL * 1024ULL)

// HW register map (AXI-Lite)
// 0: START_CLIENT (WR, bit0=start)
// 1: NUMCONNECT (WR, [15:0])
// 2: WORDCOUNT (WR, [31:0])  -- tcp payload = WORDCOUNT * 64B
// 3: SERVERIP  (WR, [31:0])  -- BE: A.B.C.D -> 0xAA_BB_CC_DD
// 4: FREQUENCY (WR, [31:0])
// 5: TIMEINSEC (WR, [31:0])
// 6: TOTALWORD (RO, [31:0])
// 7: CLIENT_STATE(for debug) (RO, [3:0])
enum class PerfRegs : uint32_t {
    START_CLIENT   = 0,
    NUMCONNECT     = 1,
    WORDCOUNT      = 2,
    SERVERIP       = 3,
    FREQUENCY      = 4,
    TIMEINSEC      = 5,
    TOTALWORD      = 6,
    CLIENT_STATE   = 7
};

// "A.B.C.D" -> 0xAA_BB_CC_DD (big-endian)
static uint32_t parseIpBE(const std::string& ip_str) {
    std::istringstream iss(ip_str);
    std::string tok; uint32_t b[4]; int i = 0;
    while (std::getline(iss, tok, '.')) {
        if (i >= 4) throw std::invalid_argument("IP has more than 4 octets");
        tok.erase(tok.begin(), std::find_if(tok.begin(), tok.end(),
                   [](unsigned char c){ return !std::isspace(c); }));
        tok.erase(std::find_if(tok.rbegin(), tok.rend(),
                   [](unsigned char c){ return !std::isspace(c); }).base(), tok.end());
        if (tok.empty()) throw std::invalid_argument("Empty IP octet");
        char* endp = nullptr;
        long v = std::strtol(tok.c_str(), &endp, 10);
        if (*endp != '\0' || v < 0 || v > 255)
            throw std::invalid_argument(std::string("Invalid IP octet: ") + tok);
        b[i++] = static_cast<uint32_t>(v);
    }
    if (i != 4) throw std::invalid_argument("IP must have 4 octets");
    return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | (b[3] << 0);
}

static std::string ipToStr(uint32_t ip_be) {
    return std::to_string((ip_be>>24)&0xFF) + "." +
           std::to_string((ip_be>>16)&0xFF) + "." +
           std::to_string((ip_be>> 8)&0xFF) + "." +
           std::to_string((ip_be>> 0)&0xFF);
}

// clamp/validate 32-bit unsigned range helper
static void ensure_u32(const char* name, uint64_t v) {
    if (v > 0xFFFFFFFFull)
        throw std::invalid_argument(std::string("--") + name + " out of range (0..4294967295)");
}

int main(int argc, char* argv[]) {
    namespace po = boost::program_options;

    // ---- CLI ----
    std::string ip_str;                 // required
    unsigned int sessions = 1;          // 0..65535
    uint64_t words = 16;                // 0..2^32-1
    uint64_t freq  = 0;                 // Hz, 0..2^32-1 (user-defined; default 0)
    uint64_t timeS = 0;                 // seconds, 0..2^32-1 (default 0)

    po::options_description desc("tcp_perf_client host options");
    desc.add_options()
        ("help,h", "Show help")
        ("ip,i",       po::value<std::string>(&ip_str)->required(), "Server IP A.B.C.D (required)")
        ("sessions,s", po::value<unsigned int>(&sessions)->default_value(1), "numSessions (0..65535)")
        ("words,w",    po::value<uint64_t>(&words)->default_value(16),       "WORDCOUNT (payload words, 0..4294967295)")
        ("time,t",     po::value<uint64_t>(&timeS)->default_value(0),        "timeInSeconds (0..4294967295)");

    po::variables_map vm;
    try {
        po::store(po::parse_command_line(argc, argv, desc), vm);
        if (vm.count("help")) { std::cout << desc << "\n"; return EXIT_SUCCESS; }
        po::notify(vm);
    } catch (const po::error& e) {
        std::cerr << "Argument error: " << e.what() << "\n\n" << desc << std::endl;
        return EXIT_FAILURE;
    }

    // ---- Range checks ----
    ensure_u32("words", words);
    ensure_u32("time",  timeS);

    uint32_t ip_be = parseIpBE(ip_str);

    // ---- Coyote thread ----
    coyote::cThread coyote_thread(DEFAULT_VFPGA_ID, getpid());

    std::cout << "[CFG] sessions=" << sessions
              << " words=" << words
              << " time="  << timeS
              << " ip=" << ip_str << " (0x" << std::hex << ip_be << std::dec << ")" << std::endl;

    
    // ---- Write registers ----
    coyote_thread.setCSR(static_cast<uint64_t>(sessions),       (uint32_t)PerfRegs::NUMCONNECT);
    coyote_thread.setCSR(static_cast<uint64_t>(words),          (uint32_t)PerfRegs::WORDCOUNT);
    coyote_thread.setCSR(static_cast<uint64_t>(ip_be),          (uint32_t)PerfRegs::SERVERIP);
    coyote_thread.setCSR(static_cast<uint64_t>(256ULL * MHZ),   (uint32_t)PerfRegs::FREQUENCY);
    coyote_thread.setCSR(static_cast<uint64_t>(timeS),          (uint32_t)PerfRegs::TIMEINSEC);
    coyote_thread.setCSR(static_cast<uint64_t>(1),              (uint32_t)PerfRegs::START_CLIENT);

    while(coyote_thread.getCSR((uint32_t)PerfRegs::CLIENT_STATE) == 0){ // If state == 0, wait (not started)
        sleep(1);
    }

    sleep(timeS);

    while(coyote_thread.getCSR((uint32_t)PerfRegs::CLIENT_STATE) != 0){ // If state != 0, wait (not finished)
        sleep(1);
    }

    uint64_t totalcnt = coyote_thread.getCSR((uint32_t)PerfRegs::WORDCOUNT);
    uint64_t totalbits = totalcnt * words * 512; // TotalSend = payload * words per payload * bits per word  
    double bps = totalbits / timeS;


    // if(bps < 1024 * 1024){
    //     double Kbps = bps / 1024;
    //     std::cout << "[STATS] time=" << timeS << " s, "
    //     << "bits=" << totalbits << "\n"
    //     << "BW = " << Kbps  << " Kbits/s" << std::endl;
    // }
    // else if(bps < (1024 * 1024 * 1024)){
    //     double Mbps = bps / (1024*1024);
    //     std::cout << "[STATS] time=" << timeS << " s, "
    //     << "bits=" << totalbits << "\n"
    //     << "BW = " << Mbps  << " Mbps/s" << std::endl;
    // }
    // else{
    //     double Gbps = bps / (1024*1024*1024);
    //     std::cout << "[STATS] time=" << timeS << " s, "
    //     << "bits=" << totalbits << "\n"
    //     << "BW = " << Gbps  << " Gbits/s" << std::endl;
    // }
    
    // std::cout << coyote_thread.getCSR((uint32_t)PerfRegs::CLIENT_STATE) << std::endl;
    std::cout << "[DONE]\n";
    return EXIT_SUCCESS;
}
