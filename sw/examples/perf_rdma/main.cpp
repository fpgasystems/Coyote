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
#include <atomic>
#include <signal.h> 
#include <boost/program_options.hpp>

#include "cBench.hpp"
#include "ibvQpMap.hpp"

#define EN_THR_TESTS
#define EN_LAT_TESTS

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
constexpr auto const defNRepsThr = 1000;
constexpr auto const defNRepsLat = 100;
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
        ("tcpaddr,t", boost::program_options::value<string>(), "TCP conn IP")
        ("benchruns,b", boost::program_options::value<uint32_t>(), "Number of bench runs")
        ("repst,r", boost::program_options::value<uint32_t>(), "Number of throughput repetitions within a run")
        ("repsl,l", boost::program_options::value<uint32_t>(), "Number of latency repetitions within a run")
        ("mins,n", boost::program_options::value<uint32_t>(), "Minimum transfer size")
        ("maxs,x", boost::program_options::value<uint32_t>(), "Maximum transfer size")
        ("oper,w", boost::program_options::value<bool>(), "Read or Write");
    
    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    // Stat
    string tcp_mstr_ip;
    uint32_t n_bench_runs = defNBenchRuns;
    uint32_t n_reps_thr = defNRepsThr;
    uint32_t n_reps_lat = defNRepsLat;
    uint32_t min_size = defMinSize;
    uint32_t max_size = defMaxSize;
    bool oper = defOper;
    bool mstr = true;

    char const* env_var_ip = std::getenv("DEVICE_1_IP_ADDRESS_0");
    if(env_var_ip == nullptr) 
        throw std::runtime_error("IBV IP address not provided");
    string ibv_ip(env_var_ip);

    if(commandLineArgs.count("tcpaddr") > 0) {
        tcp_mstr_ip = commandLineArgs["tcpaddr"].as<string>();
        mstr = false;
    }
    
    if(commandLineArgs.count("benchruns") > 0) n_bench_runs = commandLineArgs["benchruns"].as<uint32_t>();
    if(commandLineArgs.count("repst") > 0) n_reps_thr = commandLineArgs["repst"].as<uint32_t>();
    if(commandLineArgs.count("repsl") > 0) n_reps_lat = commandLineArgs["repsl"].as<uint32_t>();
    if(commandLineArgs.count("mins") > 0) min_size = commandLineArgs["mins"].as<uint32_t>();
    if(commandLineArgs.count("maxs") > 0) max_size = commandLineArgs["maxs"].as<uint32_t>();
    if(commandLineArgs.count("oper") > 0) oper = commandLineArgs["oper"].as<bool>();

    uint32_t n_pages = (max_size + hugePageSize - 1) / hugePageSize;
    uint32_t size = min_size;

    PR_HEADER("PARAMS");
    if(!mstr) { std::cout << "TCP master IP address: " << tcp_mstr_ip << std::endl; }
    std::cout << "IBV IP address: " << ibv_ip << std::endl;
    std::cout << "Number of allocated pages: " << n_pages << std::endl;
    std::cout << (oper ? "Write operation" : "Read operation") << std::endl;
    std::cout << "Min size: " << min_size << std::endl;
    std::cout << "Max size: " << max_size << std::endl;
    std::cout << "Number of throughput reps: " << n_reps_thr << std::endl;
    std::cout << "Number of latency reps: " << n_reps_lat << std::endl;
    
    // Create  queue pairs
    ibvQpMap ictx;
    ictx.addQpair(qpId, targetRegion, ibv_ip, n_pages);
    mstr ? ictx.exchangeQpMaster(port) : ictx.exchangeQpSlave(tcp_mstr_ip.c_str(), port);
    ibvQpConn *iqp = ictx.getQpairConn(qpId);
    cProcess *cproc = iqp->getCProc();

    // Init app layer --------------------------------------------------------------------------------
    struct ibvSge sg;
    struct ibvSendWr wr;
    
    memset(&sg, 0, sizeof(sg));
    sg.local_offs = 0;
    sg.remote_offs = 0;
    sg.len = size;

    memset(&wr, 0, sizeof(wr));
    wr.sg_list = &sg;
    wr.num_sge = 1;
    wr.opcode = oper ? IBV_WR_RDMA_WRITE : IBV_WR_RDMA_READ;
 
    uint64_t *hMem = (uint64_t*)iqp->getQpairStruct()->local.vaddr;
    iqp->ibvSync(mstr);

    // Fill the data
    for(int i = 0; i < max_size/64; i++) {
      for(int j = 0; j < 8; j++) {
	      hMem[i*8+j] = i;
      } 
    } 
    
    PR_HEADER("RDMA BENCHMARK");
    while(sg.len <= max_size) {
        // Setup
        iqp->ibvClear();
        iqp->ibvSync(mstr);

        // Measurements ----------------------------------------------------------------------------------
        if(mstr) {
            // Inititator 
	    //
	    //cproc->netDrop(1, 0, 0);
	    //cproc->netDrop(0, 1, 0);
            
            // ---------------------------------------------------------------
            // Runs 
            // ---------------------------------------------------------------
            cBench bench(n_bench_runs);
            uint32_t n_runs = 0;

#ifdef EN_THR_TESTS    
            auto benchmark_thr = [&]() {
                bool k = false;
                n_runs++;
                
                // Initiate
                for(int i = 0; i < n_reps_thr; i++) {
                    iqp->ibvPostSend(&wr);
                }

                // Wait for completion
                while(iqp->ibvDone() < n_reps_thr * n_runs) { if( stalled.load() ) throw std::runtime_error("Stalled, SIGINT caught");  }
            };
            bench.runtime(benchmark_thr);
            std::cout << std::fixed << std::setprecision(2);
            std::cout << std::setw(8) << sg.len << " [bytes], thoughput: " 
                      << std::setw(8) << ((1 + oper) * ((1000 * sg.len))) / ((bench.getAvg()) / n_reps_thr) << " [MB/s], latency: "; 
#endif
            
            // Reset
            iqp->ibvClear();
            n_runs = 0;
            //std::cout << "\e[1mSyncing ...\e[0m" << std::endl;
            iqp->ibvSync(mstr);

#ifdef EN_LAT_TESTS           
            auto benchmark_lat = [&]() {
                n_runs++;
                
                // Initiate and wait for completion
                for(int i = 0; i < n_reps_lat; i++) {
                    iqp->ibvPostSend(&wr);
                    while(iqp->ibvDone() < (i+1) + ((n_runs-1) * n_reps_lat)) { if( stalled.load() ) throw std::runtime_error("Stalled, SIGINT caught");  }
                }
            };
            bench.runtime(benchmark_lat);
	    std::cout << (bench.getAvg()) / (n_reps_lat * (1 + oper)) << " [ns]" << std::endl;
#endif	    

        } else {
            // Server

#ifdef EN_THR_TESTS
            if(oper) {
                for(uint32_t n_runs = 1; n_runs <= n_bench_runs; n_runs++) {
                    bool k = false;
                    
                    // Wait for incoming transactions
                    while(iqp->ibvDone() < n_reps_thr * n_runs) { if( stalled.load() ) throw std::runtime_error("Stalled, SIGINT caught");  }

                    // Send back
                    for(int i = 0; i < n_reps_thr; i++) {
                        iqp->ibvPostSend(&wr);
                    }
                }
#endif

                // Reset
                iqp->ibvClear();
                //std::cout << "\e[1mSyncing ...\e[0m" << std::endl;
                iqp->ibvSync(mstr);

#ifdef EN_LAT_TESTS
                for(int n_runs = 1; n_runs <= n_bench_runs; n_runs++) {
                    
                    // Wait for the incoming transaction and send back
                    for(int i = 0; i < n_reps_lat; i++) {
                        while(iqp->ibvDone() < (i+1) + ((n_runs-1) * n_reps_lat)) { if( stalled.load() ) throw std::runtime_error("Stalled, SIGINT caught");  }
                        iqp->ibvPostSend(&wr);
                    }
                } 
#endif		

            } else {
                //std::cout << "\e[1mSyncing ...\e[0m" << std::endl;
                iqp->ibvSync(mstr);
            }
        }  

        //std::cout << std::endl << std::endl << "ACKs: " << cproc->ibvCheckAcks() << std::endl;
        sg.len *= 2;
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
