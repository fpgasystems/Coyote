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
#include "include/conversion.hpp"

using namespace std;
using namespace fpga;

/* Def params */
constexpr auto const defDevice = 0;
constexpr auto const defTargetVfid = 0;
constexpr auto const defHostMemPages = 8;
constexpr auto const defFilterConfig = 0;

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
    // Args
    // ---------------------------------------------------------------
    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options()
        ("npages,n", boost::program_options::value<uint32_t>(), "Number of Memory Pages")
        ("device,d", boost::program_options::value<uint32_t>(), "Target device")
        ("vfpga,v", boost::program_options::value<uint32_t>(), "vFPGAs id")
        ("no-ipv4", boost::program_options::value<bool>(), "Ignore IPv4")
        ("no-ipv6", boost::program_options::value<bool>(), "Ignore IPv6")
        ("no-arp", boost::program_options::value<bool>(), "Ignore ARP")
        ("no-icmp-v4", boost::program_options::value<bool>(), "Ignore ICMP on IPv4")
        ("no-icmp-v6", boost::program_options::value<bool>(), "Ignore ICMP on IPv6")
        ("no-udp-v4", boost::program_options::value<bool>(), "Ignore UDP on IPv4")
        ("no-udp-payload-v4", boost::program_options::value<bool>(), "Ignore UDP Payload on IPv4")
        ("no-udp-v6", boost::program_options::value<bool>(), "Ignore UDP on IPv6")
        ("no-udp-payload-v6", boost::program_options::value<bool>(), "Ignore UDP Payload on IPv6")
        ("no-tcp-v4", boost::program_options::value<bool>(), "Ignore TCP on IPv4")
        ("no-tcp-payload-v4", boost::program_options::value<bool>(), "Ignore TCP Payload on IPv4")
        ("no-roce-v4", boost::program_options::value<bool>(), "Ignore RoCEv2 on IPv4")
        ("no-roce-payload-v4", boost::program_options::value<bool>(), "Ignore RoCEv2 Payload on IPv4")
        ("raw-filename,r", boost::program_options::value<string>(), "Filename to save raw captured data")
        ("pcap-filename,p", boost::program_options::value<string>(), "Filename to save converted pcap data")
        ("conversion-only,c", boost::program_options::value<bool>(), "Only convert previously captured data");
    
    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    uint32_t cs_device = defDevice;
    uint32_t target_vfid = defTargetVfid;
    uint32_t host_mem_pages = defHostMemPages;
    uint64_t filter_config = defFilterConfig;
    std::string raw_file = "capture.txt";
    std::string pcap_file = "capture.pcap";
    bool conversion_only = false;

    if (commandLineArgs.count("raw-filename") > 0) raw_file = commandLineArgs["raw-filename"].as<string>();
    if (commandLineArgs.count("pcap-filename") > 0) pcap_file = commandLineArgs["pcap-filename"].as<string>();

    if (commandLineArgs.count("device") > 0) cs_device = commandLineArgs["device"].as<uint32_t>();
    if (commandLineArgs.count("npages") > 0) host_mem_pages = commandLineArgs["npages"].as<uint32_t>();
    if (commandLineArgs.count("vfpga") > 0) target_vfid = commandLineArgs["vfpga"].as<uint32_t>();

    if (commandLineArgs.count("no-ipv4") > 0) filter_config |= (1ULL << 8);
    if (commandLineArgs.count("no-ipv6") > 0) filter_config |= (1ULL << 9);
    if (commandLineArgs.count("no-arp") > 0) filter_config |= (1ULL << 16);
    if (commandLineArgs.count("no-icmp-v4") > 0) filter_config |= (1ULL << 18);
    if (commandLineArgs.count("no-icmp-v6") > 0) filter_config |= (1ULL << 20);
    if (commandLineArgs.count("no-udp-v4") > 0) filter_config |= (1ULL << 22);
    if (commandLineArgs.count("no-udp-payload-v4") > 0) filter_config |= (1ULL << 23);
    if (commandLineArgs.count("no-udp-v6") > 0) filter_config |= (1ULL << 24);
    if (commandLineArgs.count("no-udp-payload-v6") > 0) filter_config |= (1ULL << 25);
    if (commandLineArgs.count("no-tcp-v4") > 0) filter_config |= (1ULL << 26);
    if (commandLineArgs.count("no-tcp-payload-v4") > 0) filter_config |= (1ULL << 27);
    if (commandLineArgs.count("no-roce-v4") > 0) filter_config |= (1ULL << 30);
    if (commandLineArgs.count("no-roce-payload-v4") > 0) filter_config |= (1ULL << 31);

    if (commandLineArgs.count("conversion-only") > 0) conversion_only = true;

    PR_HEADER("PARAMS");
    if (conversion_only) {
        printf("Conversion Only Mode\n");
        printf("Raw captured data file: %s\n", raw_file.c_str());
        printf("PCAP file: %s\n", pcap_file.c_str());
    } else {
        printf("Device ID: %d\n", cs_device);
        printf("Target vFPGA ID: %d\n", target_vfid);
        printf("Number of Mmeory Pages: %d\n", host_mem_pages);
        printf("Filter Config: %lx\n", filter_config);
        printf("Raw captured data file: %s\n", raw_file.c_str());
        printf("PCAP file: %s\n", pcap_file.c_str());
    }

    if (conversion_only) {
        pcap_conversion(raw_file, pcap_file);
        return 0;
    }


    // ---------------------------------------------------------------
    // Init 
    // ---------------------------------------------------------------

    // vfpga handler and mem alloc
    cThread<int> cthread(target_vfid, getpid(), cs_device);
    void *hMem = cthread.getMem({CoyoteAlloc::HPF, (uint32_t)hugePageSize * host_mem_pages});
    memset(hMem, 0, hugePageSize * host_mem_pages);
    // offload memory to card
    sgEntry *hmem_sg = (sgEntry *)malloc(sizeof(sgEntry));
    hmem_sg->sync.addr = (void *)((uintptr_t)hMem);
    cthread.invoke(CoyoteOper::LOCAL_OFFLOAD, hmem_sg, {false, false, false}, 1);

    // Reset CSRs
    cthread.setCSR(0, static_cast<uint32_t>(SnifferCSRs::CTRL_0));
    cthread.setCSR(0, static_cast<uint32_t>(SnifferCSRs::CTRL_1));

    PR_HEADER("STARTUP CHECK");
    getAllCSRs(cthread);

    // ---------------------------------------------------------------
    // Set Memory Address
    // ---------------------------------------------------------------
    cthread.setCSR(reinterpret_cast<uint64_t>(hMem), static_cast<uint32_t>(SnifferCSRs::HOST_VADDR));
    cthread.setCSR(hugePageSize * host_mem_pages, static_cast<uint32_t>(SnifferCSRs::HOST_LEN));
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
                printf("\n");
                printf("-- h: help\n");
                printf("-- p: print CSRs\n");
                printf("-- s: start sniffer\n");
                break;
        }
        printf("> ");
    } while (scanf(" %c", &cmd) != -1 && cmd != 's');

    PR_HEADER("STARTING SNIFFER");
    cthread.setCSR(filter_config, static_cast<uint32_t>(SnifferCSRs::CTRL_FILTER));
    cthread.setCSR(1, static_cast<uint32_t>(SnifferCSRs::CTRL_0));
    while (static_cast<uint8_t>(cthread.getCSR(static_cast<uint32_t>(SnifferCSRs::SNIFFER_STATE))) == static_cast<uint8_t>(SnifferState::IDLE));
    PR_HEADER("SNIFFER STARTED");
    getAllCSRs(cthread);

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
                printf("\n");
                printf("-- h: help\n");
                printf("-- p: print CSRs\n");
                printf("-- s: stop sniffer\n");
                break;
        }
        printf("> ");
    } while (scanf(" %c", &cmd) != -1 && cmd != 's');

    PR_HEADER("STOPPING SNIFFER");
    cthread.setCSR(0, static_cast<uint32_t>(SnifferCSRs::CTRL_0));
    while (static_cast<uint8_t>(cthread.getCSR(static_cast<uint32_t>(SnifferCSRs::SNIFFER_STATE))) != static_cast<uint8_t>(SnifferState::IDLE));
    PR_HEADER("SNIFFER STOPPED");
    getAllCSRs(cthread);

    // ---------------------------------------------------------------
    // Sync Back Memory
    // ---------------------------------------------------------------
    sleep(1);
    cthread.invoke(CoyoteOper::LOCAL_SYNC, hmem_sg, {false, false, false}, 1);

    // Save data
    PR_HEADER("SAVING DATA");
    uint32_t captured_sz = static_cast<uint32_t>(cthread.getCSR(static_cast<uint32_t>(SnifferCSRs::SNIFFER_SIZE)));
    printf("Captured size: %u Bytes\n", captured_sz);
    printf("Total Memory size: %llu Bytes\n", hugePageSize * host_mem_pages);
    FILE *raw_f = fopen(raw_file.c_str(), "w");
    fprintf(raw_f, "%lx\n", filter_config);
    for (uint32_t i = 0; i * 8 < captured_sz && i * 8 < hugePageSize * host_mem_pages; ++i) {
    // for (uint32_t i = 0; i * 8 < 128; ++i) {
        uint64_t *ptr = ((uint64_t *)hMem) + i;
        uint8_t *ptr_u8 = (uint8_t *)ptr;
        fprintf(raw_f, "%08x: ", i * 8);
        fprintf(raw_f, "%02x %02x %02x %02x %02x %02x %02x %02x\n",
                *(ptr_u8 + 0), *(ptr_u8 + 1), *(ptr_u8 + 2), *(ptr_u8 + 3), 
                *(ptr_u8 + 4), *(ptr_u8 + 5), *(ptr_u8 + 6), *(ptr_u8 + 7));
    }
    fclose(raw_f);

    pcap_conversion(raw_file, pcap_file);

    PR_HEADER("CLEAN UP");
    // Cleanup CSRs
    cthread.setCSR(0, static_cast<uint32_t>(SnifferCSRs::CTRL_0));
    cthread.setCSR(0, static_cast<uint32_t>(SnifferCSRs::CTRL_1));

    return 0;
}