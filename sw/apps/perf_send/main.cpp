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
constexpr auto const targetRegion = 0;
constexpr auto const qpId = 0;
constexpr auto const port = 18488;

/* Bench */
constexpr auto const defNBenchRuns = 1; 
constexpr auto const defNReps = 1;
constexpr auto const defCmdSize = 128;
constexpr auto const defSize = 1024;
constexpr auto const defRemOffs = defSize;

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
        ("tcpaddr,t", boost::program_options::value<string>(), "TCP conn IP")
        ("benchruns,b", boost::program_options::value<uint32_t>(), "Number of bench runs")
        ("reps,r", boost::program_options::value<uint32_t>(), "Number of repetitions within a run")
        ("size,s", boost::program_options::value<uint32_t>(), "Transfer size");
    
    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    // Stat
    string tcp_mstr_ip;
    uint32_t n_bench_runs = defNBenchRuns;
    uint32_t n_reps = defNReps;
    uint32_t size = defSize;
    uint32_t cmd_size = defCmdSize;
    bool mstr = true;

    char const* env_var_ip = std::getenv("FPGA_0_IP_ADDRESS");
    if(env_var_ip == nullptr) 
        throw std::runtime_error("IBV IP address not provided");
    string ibv_ip(env_var_ip);

    if(commandLineArgs.count("tcpaddr") > 0) {
        tcp_mstr_ip = commandLineArgs["tcpaddr"].as<string>();
        mstr = false;
    }
    
    if(commandLineArgs.count("benchruns") > 0) n_bench_runs = commandLineArgs["benchruns"].as<uint32_t>();
    if(commandLineArgs.count("reps") > 0) n_reps = commandLineArgs["reps"].as<uint32_t>();
    if(commandLineArgs.count("size") > 0) size = commandLineArgs["size"].as<uint32_t>();

    uint32_t n_pages = (2 * size + hugePageSize - 1) / hugePageSize;

    PR_HEADER("PARAMS");
    if(!mstr) { std::cout << "TCP master IP address: " << tcp_mstr_ip << std::endl; }
    std::cout << "IBV IP address: " << ibv_ip << std::endl;
    std::cout << "Number of reps: " << n_reps << std::endl;
    std::cout << "Number of allocated pages: " << n_pages << std::endl;
    std::cout << "Transfer size: " << size << std::endl;

    // Create queue pairs
    ibvQpMap ictx;
    ictx.addQpair(qpId, targetRegion, ibv_ip, n_pages);
    mstr ? ictx.exchangeQpMaster(port) : ictx.exchangeQpSlave(tcp_mstr_ip.c_str(), port);
    ibvQpConn *iqp = ictx.getQpairConn(qpId);
    cProcess *cproc = iqp->getCProc();

    // Init app layer --------------------------------------------------------------------------------
    struct ibvSge sg;
    struct ibvSendWr wr;
    
    // Set verb
    memset(&sg, 0, sizeof(sg));
    sg.local_offs = 0;
    sg.remote_offs = 0;
    sg.len = cmd_size;

    memset(&wr, 0, sizeof(wr));
    wr.sg_list = &sg;
    wr.num_sge = 1;
    wr.opcode = IBV_WR_SEND;

    // Set cmd
    uint64_t *lvaddr = (uint64_t*) iqp->getQpairStruct()->local.vaddr;
    uint64_t *rvaddr = (uint64_t*) iqp->getQpairStruct()->remote.vaddr;
    
    if(mstr) {
        lvaddr[0] = 0; // qpn
        lvaddr[1] = (uint64_t) rvaddr;
        lvaddr[2] = (uint64_t) lvaddr + size;
        lvaddr[3] = size;
        lvaddr[8] = (0x33 << 32) | (8 &0xff);
        lvaddr[9] = 4 & 0xff;
    } else {
        for(int i = 0; i < size/8; i++) {
            lvaddr[i] = i + 1;
        }
    }
    
    PR_HEADER("RDMA BENCHMARK");
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
        std::cout << std::fixed << std::setprecision(2);
        std::cout << std::setw(8) << sg.len << " [bytes], thoughput: " 
                    << std::setw(8) << (((1000 * sg.len))) / ((bench.getAvg()) / n_reps) << " [MB/s], latency: "; 
        
        // Reset
        iqp->ibvClear();
        n_runs = 0;
        //std::cout << "\e[1mSyncing ...\e[0m" << std::endl;
        iqp->ibvSync(mstr);
        /*
        auto benchmark_lat = [&]() {
            n_runs++;
            
            // Initiate and wait for completion
            for(int i = 0; i < n_reps; i++) {
                iqp->ibvPostSend(&wr);
                while(iqp->ibvDone() < (i+1) + ((n_runs-1) * n_reps)) { if( stalled.load() ) throw std::runtime_error("Stalled, SIGINT caught");  }
            }
        };
        bench.runtime(benchmark_lat);
        */
        //std::cout << (bench.getAvg()) / (n_reps * (1 + oper)) << " [ns]" << std::endl;
    } else {
        // Server
            
        //std::cout << "\e[1mSyncing ...\e[0m" << std::endl;
        iqp->ibvSync(mstr);
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
