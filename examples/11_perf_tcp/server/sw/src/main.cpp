#include <iostream>
#include <sstream>
#include <string>
#include <stdexcept>
#include <cstdint>
#include <algorithm>
#include <boost/program_options.hpp>
#include <unistd.h>   // getpid, sleep
#include "cThread.hpp"

#define DEFAULT_VFPGA_ID 0

enum class PerfRegs : uint32_t {
    LISTEN_PORT_SIGNAL = 0,
    LISTEN_PORT        = 1,
    PORT_STATUS_SIGNAL = 2,
    PORT_STATUS        = 3,
    PORT_STATUS_READ   = 4,
    LISTEN_PORT_NUM    = 5
};

// clamp/validate helpers
static void ensure_u16(const char* name, uint64_t v) {
    if (v > 0xFFFFull)
        throw std::invalid_argument(std::string("--") + name + " out of range (0..65535)");
}

int main(int argc, char* argv[]) {
    namespace po = boost::program_options;

    // ---- CLI ----
    // We only really need the TCP listen port to configure the FPGA.
    uint64_t port_u = 0; // we'll range check to 16 bits

    po::options_description desc("tcp_perf_client host options (listen controller)");
    desc.add_options()
        ("help,h", "Show help")
        ("port,p", po::value<uint64_t>(&port_u)->required(),
                   "TCP listen port (0..65535, required)");

    po::variables_map vm;
    try {
        po::store(po::parse_command_line(argc, argv, desc), vm);
        if (vm.count("help")) {
            std::cout << desc << "\n";
            return EXIT_SUCCESS;
        }
        po::notify(vm);
    } catch (const po::error& e) {
        std::cerr << "Argument error: " << e.what() << "\n\n" << desc << std::endl;
        return EXIT_FAILURE;
    }

    // ---- Range checks ----
    ensure_u16("port", port_u);
    uint16_t port_listen = static_cast<uint16_t>(port_u);

    // ---- Coyote thread ----
    coyote::cThread coyote_thread(DEFAULT_VFPGA_ID, getpid());

    std::cout << "[CFG] listen_port=" << port_listen << std::endl;

    coyote_thread.setCSR(static_cast<uint64_t>(port_listen),
                         static_cast<uint32_t>(PerfRegs::LISTEN_PORT));

    coyote_thread.setCSR(static_cast<uint64_t>(1),
                         static_cast<uint32_t>(PerfRegs::LISTEN_PORT_SIGNAL));

    std::cout << "[INFO] Start command issued. Waiting for ready..." << std::endl;

 
    uint64_t ready_val = 0;
    while (true) {
        ready_val = coyote_thread.getCSR(static_cast<uint32_t>(PerfRegs::PORT_STATUS_SIGNAL));
        if ( (ready_val & 0x1ULL) != 0 ) {
            break;
        }
        sleep(1);
    }

    uint64_t status_val = coyote_thread.getCSR(static_cast<uint32_t>(PerfRegs::PORT_STATUS));
    uint64_t acc_val    = coyote_thread.getCSR(static_cast<uint32_t>(PerfRegs::LISTEN_PORT_NUM));

    uint8_t  status_code = static_cast<uint8_t>(status_val & 0xFFu);
    uint32_t acc_cnt     = static_cast<uint32_t>(acc_val & 0xFFFFFFFFu);

    std::cout << "[STATUS] ready=1"
              << " status_code=0x" << std::hex << (unsigned)status_code << std::dec
              << " (" << (unsigned)status_code << ")"
              << " opened_ports=" << acc_cnt
              << std::endl;

    coyote_thread.setCSR(static_cast<uint64_t>(1),
                         static_cast<uint32_t>(PerfRegs::PORT_STATUS_READ));

    std::cout << "[DONE]" << std::endl;
    return EXIT_SUCCESS;
}
