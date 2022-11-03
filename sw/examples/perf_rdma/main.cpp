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
#include <signal.h> 
#include <atomic>

#include <boost/program_options.hpp>

#include "cBench.hpp"
#include "ibvQpMap.hpp"

using namespace std;
using namespace std::chrono;
using namespace fpga;

/* Signal handler */
std::atomic<bool> stalled(false); 
void gotInt(int) {
    stalled.store(true);
}

/* Params */
constexpr auto const mstrNodeId = 0;
constexpr auto const targetRegion = 0;
constexpr auto const qpId = 0;
constexpr auto const port = 18488;

/* Runtime */
constexpr auto const defNodeId = 0;
constexpr auto const defTcpMstrIp = "192.168.98.97";
constexpr auto const defIbvIp = "192.168.98.97";

/* Bench */
constexpr auto const defNBenchRuns = 1; 
constexpr auto const defNReps = 100;
constexpr auto const defMinSize = 128;
constexpr auto const defMaxSize = 32 * 1024;
constexpr auto const defOper = 0;

int main(int argc, char *argv[])  
{
    // ---------------------------------------------------------------
    // Initialization 
    // ---------------------------------------------------------------

    // Sig handler
    struct sigaction sa;
    memset( &sa, 0, sizeof(sa) );
    sa.sa_handler = gotInt;
    sigfillset(&sa.sa_mask);
    sigaction(SIGINT,&sa,NULL);

    // Read arguments
    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options()
        ("node,d", boost::program_options::value<uint32_t>(), "Node ID")
        ("tcpaddr,t", boost::program_options::value<string>(), "TCP conn IP")
        ("ibvaddr,i", boost::program_options::value<string>(), "IBV conn IP")
        ("benchruns,b", boost::program_options::value<uint32_t>(), "Number of bench runs")
        ("reps,r", boost::program_options::value<uint32_t>(), "Number of repetitions within a run")
        ("mins,n", boost::program_options::value<uint32_t>(), "Minimum transfer size")
        ("maxs,x", boost::program_options::value<uint32_t>(), "Maximum transfer size")
        ("oper,w", boost::program_options::value<bool>(), "Read or Write");
    
    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    // Stat
    uint32_t node_id = defNodeId;
    string tcp_mstr_ip = defTcpMstrIp;
    string ibv_ip = defIbvIp;
    uint32_t n_bench_runs = defNBenchRuns;
    uint32_t n_reps = defNReps;
    uint32_t min_size = defMinSize;
    uint32_t max_size = defMaxSize;
    bool oper = defOper;
    bool mstr = true;

    if(commandLineArgs.count("node") > 0) node_id = commandLineArgs["node"].as<uint32_t>();
    if(commandLineArgs.count("tcpaddr") > 0) {
        tcp_mstr_ip = commandLineArgs["tcpaddr"].as<string>();
        mstr = false;
    }
    if(commandLineArgs.count("ibvaddr") > 0) ibv_ip = commandLineArgs["ibvaddr"].as<string>();
    if(commandLineArgs.count("benchruns") > 0) n_bench_runs = commandLineArgs["benchruns"].as<uint32_t>();
    if(commandLineArgs.count("reps") > 0) n_reps = commandLineArgs["reps"].as<uint32_t>();
    if(commandLineArgs.count("mins") > 0) min_size = commandLineArgs["mins"].as<uint32_t>();
    if(commandLineArgs.count("maxs") > 0) max_size = commandLineArgs["maxs"].as<uint32_t>();
    if(commandLineArgs.count("oper") > 0) oper = commandLineArgs["oper"].as<bool>();

    uint32_t n_pages = (max_size + hugePageSize - 1) / hugePageSize;
    uint32_t size = min_size;

    PR_HEADER("PARAMS");
    std::cout << "Node ID: " << node_id << std::endl;
    if(!mstr) { std::cout << "TCP master IP address: " << tcp_mstr_ip << std::endl; }
    std::cout << "IBV IP address: " << ibv_ip << std::endl;
    std::cout << "Number of allocated pages: " << n_pages << std::endl;
    std::cout << (oper ? "Write operation" : "Read operation") << std::endl;
    std::cout << "Min size: " << min_size << std::endl;
    std::cout << "Max size: " << max_size << std::endl;
    std::cout << "Number of reps: " << n_reps << std::endl;

    // Create  queue pairs
    ibvQpMap ictx;
    ictx.addQpair(qpId, targetRegion, node_id, ibv_ip, n_pages);
    mstr ? ictx.exchangeQpMaster(port) : ictx.exchangeQpSlave(tcp_mstr_ip.c_str(), port);
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
 
    uint64_t *hMem = (uint64_t*)iqp->getQpairStruct()->local.vaddr;
    iqp->ibvSync(mstr);
    
    PR_HEADER("RDMA BENCHMARK");
    while(sg.type.rdma.len <= max_size) {
        // Setup
        iqp->ibvClear();
        iqp->ibvSync(mstr);

        // Measurements ----------------------------------------------------------------------------------
        if(mstr) {
            // Inititator 
            
            // ---------------------------------------------------------------
            // Runs 
            // ---------------------------------------------------------------
            cBench bench(n_bench_runs);
            uint32_t n_runs = 0;
            
            auto benchmark_thr = [&]() {
                bool k = false;
                n_runs++;
                
                // Initiate
                for(int i = 0; i < n_reps; i++) {
                    iqp->ibvPostSend(&wr);
                }

                // Wait for completion
                while(iqp->ibvDone() < n_reps * n_runs) { if( stalled.load() ) throw std::runtime_error("Stalled, SIGINT caught");  }
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
                    while(iqp->ibvDone() < (i+1) + ((n_runs-1) * n_reps)) { if( stalled.load() ) throw std::runtime_error("Stalled, SIGINT caught");  }
                }
            };
            bench.runtime(benchmark_lat);
            std::cout << std::fixed << std::setprecision(2) << std::setw(8) << (bench.getAvg()) / (n_reps * (1 + oper)) << " [ns]" << std::endl;
        } else {
            // Server

            if(oper) {
                for(uint32_t n_runs = 1; n_runs <= n_bench_runs; n_runs++) {
                    bool k = false;
                    
                    // Wait for incoming transactions
                    while(iqp->ibvDone() < n_reps * n_runs) { if( stalled.load() ) throw std::runtime_error("Stalled, SIGINT caught");  }

                    // Send back
                    for(int i = 0; i < n_reps; i++) {
                        iqp->ibvPostSend(&wr);
                    }
                }

                // Reset
                iqp->ibvClear();
                //std::cout << "\e[1mSyncing ...\e[0m" << std::endl;
                iqp->ibvSync(mstr);

                for(int n_runs = 1; n_runs <= n_bench_runs; n_runs++) {
                    
                    // Wait for the incoming transaction and send back
                    for(int i = 0; i < n_reps; i++) {
                        while(iqp->ibvDone() < (i+1) + ((n_runs-1) * n_reps)) { if( stalled.load() ) throw std::runtime_error("Stalled, SIGINT caught");  }
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
