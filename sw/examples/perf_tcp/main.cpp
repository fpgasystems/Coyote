#include "cDefs.hpp"

#include <iostream>
#include <string>
#include <malloc.h>
#include <time.h> 
#include <sys/time.h>  
#include <chrono>
#include <fstream>
#include <fcntl.h>
#include <unistd.h>
#include <iomanip>
#include <random>
#include <x86intrin.h>

#include <boost/program_options.hpp>

#include "cBench.hpp"
#include "cProcess.hpp"

using namespace std;
using namespace std::chrono;
using namespace fpga;

/* Def params */
constexpr auto const targetRegion = 0;
constexpr auto const freq = 250; // MHz

/**
 * @brief TCP benchmarking
 * 
 */
int main(int argc, char *argv[])  
{
    // ---------------------------------------------------------------
    // Initialization 
    // ---------------------------------------------------------------
    // const char* masterAddr = "10.1.212.121";

    // Read arguments
    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options()
        ("useConn,c", boost::program_options::value<uint64_t>(), "Number of connections")
        ("useIpAddr,i", boost::program_options::value<uint64_t>(), "Number of IP addresses")
        ("port,p", boost::program_options::value<uint64_t>(), "Port number")
        ("pkgWordCount,w", boost::program_options::value<uint64_t>(), "Number of 512-bit work in a packet")
        ("timeInSeconds,t", boost::program_options::value<uint64_t>(), "Time in second")
        ("transferBytes,b", boost::program_options::value<uint64_t>(), "TransferBytes")
        ("server,s", boost::program_options::value<uint64_t>(), "Run as iperf server");
    
    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    // Stat
    uint32_t local_ip = 0x0A01D497; 
    uint32_t target_ip = 0x0A01D498;
    uint64_t useConn = 1;
    uint64_t useIpAddr = 1;
    uint64_t port = 5001;
    uint64_t pkgWordCount = 64;
    uint64_t timeInSeconds = 1;
    uint64_t timeInCycles;
    uint64_t dualModeEn = 64;
    uint64_t packetGap = 0;
    uint64_t server = 0;
    uint64_t transferBytes = 1024;

    // Runs
    if(commandLineArgs.count("useConn") > 0) useConn = commandLineArgs["useConn"].as<uint64_t>();
    if(commandLineArgs.count("useIpAddr") > 0) useIpAddr = commandLineArgs["useIpAddr"].as<uint64_t>();
    if(commandLineArgs.count("port") > 0) port = commandLineArgs["port"].as<uint64_t>();
    if(commandLineArgs.count("pkgWordCount") > 0) pkgWordCount = commandLineArgs["pkgWordCount"].as<uint64_t>();
    if(commandLineArgs.count("timeInSeconds") > 0) timeInSeconds = commandLineArgs["timeInSeconds"].as<uint64_t>();
    if(commandLineArgs.count("server") > 0) server = commandLineArgs["server"].as<uint64_t>();
    if(commandLineArgs.count("transferBytes") > 0) transferBytes = commandLineArgs["transferBytes"].as<uint64_t>();

    timeInCycles = timeInSeconds * freq * 1000000;
    if (server == 1) {
        local_ip = 0x0A01D498;
        target_ip = 0x0A01D497;
    }

    printf("usecon:%ld, useIP:%ld, pkgWordCount:%ld,port:%ld, local ip:%x, target ip:%x, time:%ld, is server:%ld, transferBytes:%ld\n", useConn, useIpAddr, pkgWordCount, port, local_ip, target_ip, timeInCycles, server, transferBytes);
    
    // FPGA handles
    cProcess cproc(targetRegion, getpid());

    // ARP lookup
    // cproc.doArpLookup();

/** 
 * -- Register map
 *  0 (WO)  : Control
 *  1 (RO)  : Status
 *  2 (RW)  : useConn
 *  3 (RW)  : useIpAddr
 *  4 (RW)  : pkgWordCount
 *  5 (RW)  : basePort
 *  6 (RW)  : baseIpAddr
 *  7 (RW)  : transferSize
 *  8 (RW)  : isServer
 *  9 (RW)  : timeInSeconds
 *  10 (RW) : timeInCycles
 *  11 (R)  : execution_cycles
 *  12 (R)  : consumed_bytes
 *  13 (R)  : produced_bytes
 *  14 (R)  : openCon_cycles
 */
    cproc.setCSR(useConn, 2);
    cproc.setCSR(useIpAddr, 3);
    cproc.setCSR(pkgWordCount, 4);
    cproc.setCSR(port, 5);
    cproc.setCSR(target_ip, 6);
    cproc.setCSR(transferBytes, 7);
    cproc.setCSR(server, 8);
    cproc.setCSR(timeInSeconds, 9);
    cproc.setCSR(timeInCycles, 10);
    std::cout << "Start" << std::endl;
    auto start = std::chrono::high_resolution_clock::now();

    //set the control bit to start the kernel
    cproc.setCSR(1, 0);    

    //Probe the done signal
    while (cproc.getCSR(1) != 1) {}
    // std::this_thread::sleep_for(1s);

    auto end = std::chrono::high_resolution_clock::now();
    double durationUs = 0.0;
    durationUs = (std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count() / 1000.0);
    cout<< "Experiment finished durationUs: " << durationUs << endl;

    if(server ==0) {
        uint64_t tx_bytes = cproc.getCSR(13);
        uint64_t openCon_cycles = cproc.getCSR(14);
        uint64_t total_cycles = cproc.getCSR(11);
        uint64_t cycles = (total_cycles - openCon_cycles) / 2;
        
        cout << "tx_bytes: " << tx_bytes << " open con cycles: " << openCon_cycles << " total_cycles: " << total_cycles << " single trip transfer cycle: " << cycles << endl;
        double throughput = (double)tx_bytes * 8.0 * freq / ((double)cycles*1000.0);
        double latency = (double)cycles / freq;
        cout << "throughput [gbps]: " << throughput << " latency[us]: " << latency << endl;
    }

    return EXIT_SUCCESS;
}

