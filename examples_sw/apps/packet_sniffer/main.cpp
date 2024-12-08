#include <iostream>
#include <cstdio>
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
constexpr auto const hostMemPages = 8;

uint64_t filter_config = 0x0000000000800000; // ignore udp/ipv4 payload

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
    FINISHING = 0b11,
};

void getAllCSRs(cThread<int> &t) {
    std::cout << "CTRL_0:        " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::CTRL_0)) << std::endl
              << "CTRL_1:        " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::CTRL_1)) << std::endl
              << "CTRL_FILTER:   " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::CTRL_FILTER)) << std::endl
              << "SNIFFER_STATE: " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::SNIFFER_STATE)) << std::endl
              << "SNIFFER_SIZE:  " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::SNIFFER_SIZE)) << std::endl
              << "SNIFFER_TIMER: " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::SNIFFER_TIMER)) << std::endl
              << "HOST_VADDR:    " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::HOST_VADDR)) << std::endl
              << "HOST_LEN:      " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::HOST_LEN)) << std::endl
              << "HOST_PID:      " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::HOST_PID)) << std::endl
              << "HOST_DEST:     " << t.getCSR(static_cast<uint32_t>(SnifferCSRs::HOST_DEST)) << std::endl;
}

int main(int argc, char *argv[]) {
    // ---------------------------------------------------------------
    // Init 
    // ---------------------------------------------------------------

    // vfpga handler and mem alloc
    cThread<int> cthread(defTargetVfid, getpid(), defDevice);
    void *hMem = cthread.getMem({CoyoteAlloc::HPF, hugePageSize * hostMemPages});
    memset(hMem, 0, hugePageSize * hostMemPages);
    // offload memory to card
    sgEntry *hmem_sg = (sgEntry *)malloc(sizeof(sgEntry) * hostMemPages);
    for (int i = 0; i < hostMemPages; ++i) hmem_sg[i].sync.addr = (void *)((uintptr_t)hMem + (i * hugePageSize));
    cthread.invoke(CoyoteOper::LOCAL_OFFLOAD, hmem_sg, {false, false, false}, hostMemPages);

    // Reset CSRs
    cthread.setCSR(0, static_cast<uint32_t>(SnifferCSRs::CTRL_0));
    cthread.setCSR(0, static_cast<uint32_t>(SnifferCSRs::CTRL_1));

    PR_HEADER("STARTUP CHECK");
    getAllCSRs(cthread);

    // ---------------------------------------------------------------
    // Set Memory Address
    // ---------------------------------------------------------------
    cthread.setCSR(reinterpret_cast<uint64_t>(hMem), static_cast<uint32_t>(SnifferCSRs::HOST_VADDR));
    cthread.setCSR(hugePageSize * hostMemPages, static_cast<uint32_t>(SnifferCSRs::HOST_LEN));
    cthread.setCSR(cthread.getHpid(), static_cast<uint32_t>(SnifferCSRs::HOST_PID));
    cthread.setCSR(0, static_cast<uint32_t>(SnifferCSRs::HOST_DEST));
    cthread.setCSR(1, static_cast<uint32_t>(SnifferCSRs::CTRL_1));

    PR_HEADER("MEMORY SET");
    getAllCSRs(cthread);
    
    // ---------------------------------------------------------------
    // Start Sniffer
    // ---------------------------------------------------------------
    char cmd = 'h';
    do {
        switch (cmd) {
            case 'p':
                getAllCSRs(cthread);
                break;
            default:
                printf("-- h: help\n");
                printf("-- p: print CSRs\n");
                printf("-- s: start sniffer\n");
                break;
        }
        printf("> ");
    } while (scanf("%c", &cmd) != -1 && cmd != 's');

    PR_HEADER("STARTING SNIFFER");
    cthread.setCSR(filter_config, static_cast<uint32_t>(SnifferCSRs::CTRL_FILTER));
    cthread.setCSR(1, static_cast<uint32_t>(SnifferCSRs::CTRL_0));
    while (static_cast<uint8_t>(cthread.getCSR(static_cast<uint32_t>(SnifferCSRs::SNIFFER_STATE))) == static_cast<uint8_t>(SnifferState::IDLE));
    // PR_HEADER("SNIFFER STARTED");
    // getAllCSRs(cthread);

    // ---------------------------------------------------------------
    // Stop Sniffer
    // ---------------------------------------------------------------
    cmd = 'h';
    do {
        switch (cmd) {
            case 'p':
                getAllCSRs(cthread);
                break;
            default:
                printf("-- h: help\n");
                printf("-- p: print CSRs\n");
                printf("-- s: stop sniffer\n");
                break;
        }
        printf("> ");
    } while (scanf("%c", &cmd) != -1 && cmd != 's');

    PR_HEADER("STOPPING SNIFFER");
    cthread.setCSR(0, static_cast<uint32_t>(SnifferCSRs::CTRL_0));
    while (static_cast<uint8_t>(cthread.getCSR(static_cast<uint32_t>(SnifferCSRs::SNIFFER_STATE))) != static_cast<uint8_t>(SnifferState::IDLE));
    // PR_HEADER("SNIFFER STOPPED");
    // getAllCSRs(cthread);

    // ---------------------------------------------------------------
    // Sync Back Memory
    // ---------------------------------------------------------------
    cthread.invoke(CoyoteOper::LOCAL_SYNC, hmem_sg, {false, false, false}, hostMemPages);

    // Save data
    PR_HEADER("SAVING DATA");
    FILE *data_f = fopen("data.txt", "rw");
    uint32_t captured_sz = static_cast<uint32_t>(cthread.getCSR(static_cast<uint32_t>(SnifferCSRs::SNIFFER_SIZE)));
    for (uint32_t i = 0; i < captured_sz; ++i) {
        uint64_t *ptr = ((uint64_t *)hMem) + i;
        uint8_t *ptr_u8 = (uint8_t *)ptr;
        fprintf(data_f, "%02x %02x %02x %02x %02x %02x %02x %02x\n",
                *(ptr_u8 + 0), *(ptr_u8 + 1), *(ptr_u8 + 2), *(ptr_u8 + 3), 
                *(ptr_u8 + 4), *(ptr_u8 + 5), *(ptr_u8 + 6), *(ptr_u8 + 7));
    }
    fclose(data_f);

    // Cleanup CSRs
    cthread.setCSR(0, static_cast<uint32_t>(SnifferCSRs::CTRL_0));
    cthread.setCSR(0, static_cast<uint32_t>(SnifferCSRs::CTRL_1));

    return 0;
}