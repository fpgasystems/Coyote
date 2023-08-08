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
constexpr auto const freq = 300; // MHz

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
        ("port,p", boost::program_options::value<uint64_t>(), "Port number")
        ("pkgWordCount,w", boost::program_options::value<uint64_t>(), "Number of 512-bit work in a packet")
        ("timeInSeconds,t", boost::program_options::value<uint64_t>(), "Time in second")
        ("transferBytes,b", boost::program_options::value<uint64_t>(), "TransferBytes")
        ("server,s", boost::program_options::value<uint64_t>(), "Run as iperf server")
        ("target,r", boost::program_options::value<uint32_t>(), "Target IP");
    
    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    // Stat
    uint32_t target_ip = 0x0AFD4A68; //0x0A01D498;
    uint64_t port = 5001;
    uint64_t pkgWordCount = 64;
    uint64_t timeInSeconds = 1;
    uint64_t timeInCycles;
    uint64_t server = 0;
    uint64_t transferBytes = 1024;
    uint32_t session = 0;

    // Runs
    char const* env_var_ip = std::getenv("DEVICE_1_IP_ADDRESS_0");
    if(env_var_ip == nullptr) 
        throw std::runtime_error("Local IP address not provided");
    string local_ip(env_var_ip);
    if(commandLineArgs.count("port") > 0) port = commandLineArgs["port"].as<uint64_t>();
    if(commandLineArgs.count("pkgWordCount") > 0) pkgWordCount = commandLineArgs["pkgWordCount"].as<uint64_t>();
    if(commandLineArgs.count("timeInSeconds") > 0) timeInSeconds = commandLineArgs["timeInSeconds"].as<uint64_t>();
    if(commandLineArgs.count("server") > 0) server = commandLineArgs["server"].as<uint64_t>();
    if(commandLineArgs.count("transferBytes") > 0) transferBytes = commandLineArgs["transferBytes"].as<uint64_t>();
    if(commandLineArgs.count("target") > 0) target_ip = commandLineArgs["target"].as<uint32_t>();

    timeInCycles = timeInSeconds * freq * 1000000;

    std::cout << "pkgWordCount:" << pkgWordCount << ", port:" << port << ", local ip:" << local_ip
            << ", target ip:" << target_ip << std::dec << ", time:" << timeInCycles
            << ", is server:" << server << ", transferBytes:" << transferBytes << std::endl;    

    // FPGA handles
    cProcess cproc(targetRegion, getpid());



/** 
 * -- Register map
/ 0 (WO)  : Control
/ 1 (RO)  : Status
/ 2 (RW)  : useConn
/ 3 (RW)  : useIpAddr
/ 4 (RW)  : pkgWordCount
/ 5 (RW)  : basePort
/ 6 (RW)  : baseIpAddr
/ 7 (RW)  : transferSize
/ 8 (RW)  : isServer
/ 9 (RW)  : timeInSeconds
/ 10 (RW) : timeInCycles
/ 11 (R)  : execution_cycles
/ 12 (R)  : consumed_bytes
/ 13 (R)  : produced_bytes
/ 15 (RW) : sessionID
 */

    bool success = false;

    success = cproc.tcpOpenPort(port);
    std::cout<<"TCP open port:"<<port<<", success:"<<success<<std::endl;

    if(server == 0)
    {
        success = cproc.tcpOpenCon(target_ip, port, &session);
        std::cout<<"TCP open Connection: target ip:"<<target_ip<<", port:"<<port<<", session:"<<session<<", success:"<<success<<std::endl;
        cproc.setCSR((uint64_t)session, 15);
    }

    cproc.setCSR(pkgWordCount, 4);
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

    if(server == 0) {
        uint64_t tx_bytes = cproc.getCSR(13);
        uint64_t total_cycles = cproc.getCSR(11);
        uint64_t cycles = total_cycles / 2;
        
        cout << "tx_bytes: " << tx_bytes << " total_cycles: " << total_cycles << " single trip transfer cycle: " << cycles << endl;
        double throughput = (double)tx_bytes * 8.0 * freq / ((double)cycles*1000.0);
        double latency = (double)cycles / freq;
        cout << "throughput [gbps]: " << throughput << " latency[us]: " << latency << endl;
    }

    return EXIT_SUCCESS;
}

