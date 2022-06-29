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
#include <cstring>

#include <boost/program_options.hpp>

#include "cBench.hpp"
#include "ibvQpMap.hpp"

using namespace std;
using namespace std::chrono;
using namespace fpga;

/* Runtime */
constexpr auto const nIdMaster = 0;
constexpr auto const nBenchRuns = 1; 
constexpr auto const nReps = 1000;
constexpr auto const defSize = 128;
constexpr auto const maxSize = 1 * 1024 * 1024;
constexpr auto const defOper = 0;
constexpr auto const targetRegion = 0;
constexpr auto const defMstrIp = "10.1.212.123";
constexpr auto const defPort = 18488;
constexpr auto const qpId = 0;

int main(int argc, char *argv[])  
{
    // ---------------------------------------------------------------
    // Initialization 
    // ---------------------------------------------------------------

    // Read arguments
    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options()
        ("nodeid,i", boost::program_options::value<uint32_t>(), "Node ID")
        ("oper,w", boost::program_options::value<bool>(), "Read or Write")
        ("size,s", boost::program_options::value<uint32_t>(), "Transfer size")
        ("ipaddr,p", boost::program_options::value<string>(), "IP address")
        ("port,t", boost::program_options::value<uint32_t>(), "Port number");
    
    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    // Stat
    uint32_t node_id = nIdMaster;
    bool oper = defOper;
    uint32_t n_reps = nReps;
    uint32_t size = defSize;
    string mstr_ip_addr = defMstrIp;
    uint32_t port = defPort;

    if(commandLineArgs.count("nodeid") > 0) node_id = commandLineArgs["nodeid"].as<uint32_t>();
    if(commandLineArgs.count("oper") > 0) oper = commandLineArgs["oper"].as<bool>();
    if(commandLineArgs.count("size") > 0) size = commandLineArgs["size"].as<uint32_t>();
    if(commandLineArgs.count("ipaddr") > 0) mstr_ip_addr = commandLineArgs["ipaddr"].as<string>();
    if(commandLineArgs.count("port") > 0) port = commandLineArgs["port"].as<uint32_t>();

    uint32_t n_pages = (size + hugePageSize - 1) / hugePageSize;
    bool mstr = node_id == nIdMaster;
    uint32_t ibv_ip_addr = baseIpAddress + node_id;

    PR_HEADER("PARAMS");
    std::cout << "Node ID: " << node_id << std::endl;
    std::cout << "Number of allocated pages: " << n_pages << std::endl;
    std::cout << (oper ? "Write operation" : "Read operation") << std::endl;
    std::cout << "Transfer size: " << size << std::endl;
    std::cout << "Master IP address: " << mstr_ip_addr << std::endl;

    // Handles
    cProc cproc(targetRegion, getpid());
    cproc.changeIpAddress(ibv_ip_addr);
    cproc.changeBoardNumber(node_id);

    // Create  queue pairs
    ibvQpMap ictx;
    ictx.addQpair(qpId, &cproc, node_id, n_pages);
    mstr ? ictx.exchangeQpMaster(port) : ictx.exchangeQpSlave(mstr_ip_addr.c_str(), port);
    ibvQpConn *iqp = ictx.getQpairConn(qpId);

    // Init app layer --------------------------------------------------------------------------------
    struct ibvSge sg;
    struct ibvSendWr wr;
    
    memset(&sg, 0, sizeof(sg));
    sg.type.rdma.local_offs = 0;
    sg.type.rdma.remote_offs = 0;
    sg.type.rdma.len = size;

    memset(&wr, 0, sizeof(wr));
    wr.sg_list = &sg;
    wr.num_sge = 1;
    wr.opcode = oper ? IBV_WR_RDMA_WRITE : IBV_WR_RDMA_READ;
    wr.send_flags = IBV_LEG_SEP_MASK;
 
    uint64_t *hMem = (uint64_t*)iqp->getQpairStruct()->local.vaddr;

    PR_HEADER("RDMA BENCHMARK");
    while(sg.type.rdma.len <= maxSize) {
        // Setup
        iqp->ibvClear();
        iqp->ibvSync(mstr);

        // Measurements ----------------------------------------------------------------------------------
        if(mstr) {
            // Inititator 
            
            // ---------------------------------------------------------------
            // Runs 
            // ---------------------------------------------------------------
            cBench bench(nBenchRuns);
            uint32_t n_runs = 0;
            
            auto benchmark_thr = [&]() {
                bool k = false;
                n_runs++;
                
                // Initiate
                for(int i = 0; i < n_reps; i++) {
                    iqp->ibvPostSend(&wr);
                }

                // Wait for completion
                while(iqp->ibvDone() < n_reps * n_runs) ;
            };
            bench.runtime(benchmark_thr);
            std::cout << std::setw(5) << sg.type.rdma.len << " [bytes], thoughput: " 
                << std::fixed << std::setprecision(2) << std::setw(8) << ((1 + oper) * ((1000 * sg.type.rdma.len))) / ((bench.getAvg()) / n_reps) << " [MB/s], latency: "; 
            
            // Reset
            iqp->ibvClear();
            n_runs = 0;
            //std::cout << "\e[1mSyncing ...\e[0m" << std::endl;
            iqp->ibvSync(mstr);
            
            auto benchmark_lat = [&]() {
                n_runs++;
                
                // Initiate and wait for completion
                for(int i = 0; i < n_reps; i++) {
                    iqp->ibvPostSend(&wr);
                    while(iqp->ibvDone() < (i+1) + ((n_runs-1) * n_reps)) ;
                }
            };
            bench.runtime(benchmark_lat);
            std::cout << std::fixed << std::setprecision(2) << std::setw(8) << (bench.getAvg()) / (n_reps * (1 + oper)) << " [ns]" << std::endl;
        } else {
            // Server

            if(oper) {
                for(uint32_t n_runs = 1; n_runs <= nBenchRuns; n_runs++) {
                    bool k = false;
                    
                    // Wait for incoming transactions
                    while(iqp->ibvDone() < n_reps * n_runs) ;

                    // Send back
                    for(int i = 0; i < n_reps; i++) {
                        iqp->ibvPostSend(&wr);
                    }
                }

                // Reset
                iqp->ibvClear();
                //std::cout << "\e[1mSyncing ...\e[0m" << std::endl;
                iqp->ibvSync(mstr);

                for(int n_runs = 1; n_runs <= nBenchRuns; n_runs++) {
                    
                    // Wait for the incoming transaction and send back
                    for(int i = 0; i < n_reps; i++) {
                        while(iqp->ibvDone() < (i+1) + ((n_runs-1) * n_reps)) ;
                        iqp->ibvPostSend(&wr);
                    }
                }
            } else {
                //std::cout << "\e[1mSyncing ...\e[0m" << std::endl;
                iqp->ibvSync(mstr);
            }
        }  

        sg.type.rdma.len *= 2;
    }
    std::cout << std::endl;

    // Done
    if (mstr) {
        iqp->sendAck(1);
        iqp->closeAck();
    } else {
        iqp->readAck();
        iqp->closeConnection();
    }

    return EXIT_SUCCESS;
}
