#include <iostream>
#include <algorithm>
#include <string>
#include <malloc.h>
#include <time.h> 
#include <sys/time.h>  
#include <chrono>
#include <fstream>
#include <fcntl.h>
#include <unistd.h>
#include <iomanip>
#ifdef EN_AVX
#include <x86intrin.h>
#endif
#include <boost/program_options.hpp>
#include <numeric>
#include <stdlib.h>

#include "cBench.hpp"
#include "cThread.hpp"

using namespace std;
using namespace fpga;

/* Def params */
constexpr auto const defDevice = 0;
constexpr auto const defTargetVfid = 0;

constexpr auto const maxHostMemSize = 2 * 1024 * 1024;

enum class SnifferCSRs : uint32_t {
    CTRL_0 = 0, // to start sniffing
    CTRL_1 = 1, // to notify host memory info ready
    CTRL_FILTER = 2, // filter configuration
    SNIFFER_STATE = 3,
    SNIFFER_SIZE = 4,
    SNIFFER_TIMER = 5,
    HOST_VADDR = 6,
    HOST_LEN = 7,
    HOST_PID = 8,
    HOST_DEST = 9
};

enum class SnifferState : uint8_t {
    IDLE = 0b00,
    SNIFFING = 0b01,
    WAIT_HOST_MEM = 0b11,
    WRITING_DATA = 0b10
};

void getAllCSRs(cThread<int> &t) {
    PR_HEADER("BEGIN CSR INFO");
    std::cout << "CTRL_0:        " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::CTRL_0))
              << "CTRL_1:        " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::CTRL_1))
              << "CTRL_FILTER:   " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::CTRL_FILTER))
              << "SNIFFER_STATE: " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::SNIFFER_STATE))
              << "SNIFFER_SIZE:  " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::SNIFFER_SIZE))
              << "SNIFFER_TIMER: " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::SNIFFER_TIMER))
              << "HOST_VADDR:    " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::HOST_VADDR))
              << "HOST_LEN:      " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::HOST_LEN))
              << "HOST_PID:      " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::HOST_PID))
              << "HOST_DEST:     " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::HOST_DEST)) 
              << std::endl;
    PR_HEADER("END CSR INFO");
}

int main(int argc, char *argv[]) {
    // ---------------------------------------------------------------
    // Init 
    // ---------------------------------------------------------------

    // Handles and alloc
    cThread<int> cthread(defTargetVfid, getpid(), defDevice);
    void *hMem = cthread.getMem({CoyoteAlloc::HPF, maxHostMemSize});
    memset(hMem, 0, maxHostMemSize);

    // Reset CSRs
    cthread.setCSR(0, static_cast<uint32_t>(SnifferCSRs::CTRL_0));
    cthread.setCSR(0, static_cast<uint32_t>(SnifferCSRs::CTRL_1));

    getAllCSRs(cthread);
    
    // ---------------------------------------------------------------
    // Start Sniffer
    // ---------------------------------------------------------------
    PR_HEADER("START SNIFFER");
    cthread.setCSR(1, static_cast<uint32_t>(SnifferCSRs::CTRL_0));
    while (static_cast<uint8_t>(cthread.getCSR(static_cast<uint32_t>(SnifferCSRs::SNIFFER_STATE))) == static_cast<uint8_t>(SnifferState::IDLE));

    PR_HEADER("SNIFFER STARTED");
    getAllCSRs(cthread);

    // ---------------------------------------------------------------
    // Stop Sniffer
    // ---------------------------------------------------------------
    sleep(1);
    PR_HEADER("STOP SNIFFER");
    cthread.setCSR(0, static_cast<uint32_t>(SnifferCSRs::CTRL_0));
    while (static_cast<uint8_t>(cthread.getCSR(static_cast<uint32_t>(SnifferCSRs::SNIFFER_STATE))) == static_cast<uint8_t>(SnifferState::SNIFFING));

    PR_HEADER("SNIFFER STOPPED");
    getAllCSRs(cthread);

    // ---------------------------------------------------------------
    // Setup Host Memory Config
    // ---------------------------------------------------------------
    PR_HEADER("HOST MEM CONFIG");
    cthread.setCSR(reinterpret_cast<uint64_t>(hMem), static_cast<uint32_t>(SnifferCSRs::HOST_VADDR));
    cthread.setCSR(maxHostMemSize, static_cast<uint32_t>(SnifferCSRs::HOST_LEN));
    cthread.setCSR(cthread.getHpid(), static_cast<uint32_t>(SnifferCSRs::HOST_PID));
    cthread.setCSR(0, static_cast<uint32_t>(SnifferCSRs::HOST_DEST));
    sleep(1); // make sure everything is written, maybe polling is better
    cthread.setCSR(1, static_cast<uint32_t>(SnifferCSRs::CTRL_1));
    while (static_cast<uint8_t>(cthread.getCSR(static_cast<uint32_t>(SnifferCSRs::SNIFFER_STATE))) == static_cast<uint8_t>(SnifferState::WAIT_HOST_MEM));
    getAllCSRs(cthread);

    // ---------------------------------------------------------------
    // Wait for finishing
    // ---------------------------------------------------------------
    while (static_cast<uint8_t>(cthread.getCSR(static_cast<uint32_t>(SnifferCSRs::SNIFFER_STATE))) == static_cast<uint8_t>(SnifferState::WRITING_DATA));
    PR_HEADER("DATA WRITE FINISHED");
    getAllCSRs(cthread);

    // Validate Memory Content
    PR_HEADER("VALIDATING MEM");
    for (int i = 0; i < 16; ++i) std::cout << i << " : " << *(((uint64_t *)hMem) + i) << std::endl;

    // Cleanup CSRs
    cthread.setCSR(0, static_cast<uint32_t>(SnifferCSRs::CTRL_0));
    cthread.setCSR(0, static_cast<uint32_t>(SnifferCSRs::CTRL_1));

    return 0;
}