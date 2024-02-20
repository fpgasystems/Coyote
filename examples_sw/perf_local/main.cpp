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
#ifdef EN_AVX
#include <x86intrin.h>
#endif
#include <signal.h> 
#include <boost/program_options.hpp>


#include "cBench.hpp"
#include "cThread.hpp"

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

/* Def params */
constexpr auto const nRegions = 3;
constexpr auto const defHuge = true;
constexpr auto const defMappped = true;
constexpr auto const defStream = true;
constexpr auto const nRepsThr = 10000;
constexpr auto const nRepsLat = 100;
constexpr auto const defMinSize = 1024;
constexpr auto const defMaxSize = 1 * 1024 * 1024;
constexpr auto const nBenchRuns = 1;

/**
 * @brief Loopback example
 * 
 */
int main(int argc, char *argv[])  
{
    // ---------------------------------------------------------------
    // Args 
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
        ("regions,n", boost::program_options::value<uint32_t>(), "Number of vFPGAs")
        ("hugepages,h", boost::program_options::value<bool>(), "Hugepages")
        ("mapped,m", boost::program_options::value<bool>(), "Mapped / page fault")
        ("stream,t", boost::program_options::value<bool>(), "Streaming interface")
        ("repst,r", boost::program_options::value<uint32_t>(), "Number of repetitions (throughput)")
        ("repsl,l", boost::program_options::value<uint32_t>(), "Number of repetitions (latency)")
        ("min_size,s", boost::program_options::value<uint32_t>(), "Starting transfer size")
        ("max_size,e", boost::program_options::value<uint32_t>(), "Ending transfer size");
    
    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    uint32_t n_regions = nRegions;
    bool huge = defHuge;
    bool mapped = defMappped;
    bool stream = defStream;
    uint32_t n_reps_thr = nRepsThr;
    uint32_t n_reps_lat = nRepsLat;
    uint32_t curr_size = defMinSize;
    uint32_t max_size = defMaxSize;

    if(commandLineArgs.count("regions") > 0) n_regions = commandLineArgs["regions"].as<uint32_t>();
    if(commandLineArgs.count("hugepages") > 0) huge = commandLineArgs["hugepages"].as<bool>();
    if(commandLineArgs.count("mapped") > 0) mapped = commandLineArgs["mapped"].as<bool>();
    if(commandLineArgs.count("stream") > 0) stream = commandLineArgs["stream"].as<bool>();
    if(commandLineArgs.count("repst") > 0) n_reps_thr = commandLineArgs["repst"].as<uint32_t>();
    if(commandLineArgs.count("repsl") > 0) n_reps_lat = commandLineArgs["repsl"].as<uint32_t>();
    if(commandLineArgs.count("min_size") > 0) curr_size = commandLineArgs["min_size"].as<uint32_t>();
    if(commandLineArgs.count("max_size") > 0) max_size = commandLineArgs["max_size"].as<uint32_t>();

    uint32_t n_pages = huge ? ((max_size + hugePageSize - 1) / hugePageSize) : ((max_size + pageSize - 1) / pageSize);

    PR_HEADER("PARAMS");
    std::cout << "Number of regions: " << n_regions << std::endl;
    std::cout << "Hugepages: " << huge << std::endl;
    std::cout << "Mapped pages: " << mapped << std::endl;
    std::cout << "Streaming: " << stream << std::endl;
    std::cout << "Number of allocated pages: " << n_pages << std::endl;
    std::cout << "Number of repetitions (thr): " << n_reps_thr << std::endl;
    std::cout << "Number of repetitions (lat): " << n_reps_lat << std::endl;
    std::cout << "Starting transfer size: " << curr_size << std::endl;
    std::cout << "Ending transfer size: " << max_size << std::endl;

    // ---------------------------------------------------------------
    // Init 
    // ---------------------------------------------------------------

    // Handles
    std::vector<std::unique_ptr<cThread>> cthread; // Coyote threads
    void* hMem[n_regions];
    
    // Obtain resources
    for (int i = 0; i < n_regions; i++) {
        cthread.emplace_back(new cThread(i, getpid()));
        hMem[i] = mapped ? (cthread[i]->getMem({huge ? CoyoteAlloc::HPF : CoyoteAlloc::REG, n_pages})) 
                         : (huge ? (mmap(NULL, max_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0))
                                 : (malloc(max_size)));
    }

    sgEntry sg[n_regions];
    csInvoke cs_invoke[n_regions];

    for(int i = 0; i < n_regions; i++) {
        // SG entries
        memset(&sg[i], 0, sizeof(localSg));
        sg[i].local.src_addr = hMem[i]; // Read
        sg[i].local.src_len = curr_size;
        sg[i].local.src_stream = stream;

        sg[i].local.dst_addr = hMem[i]; // Write
        sg[i].local.dst_len = curr_size;
        sg[i].local.dst_stream = stream;

        // CS
        cs_invoke[i].oper = CoyoteOper::LOCAL_TRANSFER; // Rd + Wr
        cs_invoke[i].sg_list = &sg[i];
        cs_invoke[i].num_sge = 1;
    }

    // ---------------------------------------------------------------
    // Runs 
    // ---------------------------------------------------------------
    cBench bench(nBenchRuns);
    uint32_t n_runs;

    PR_HEADER("PERF HOST");
    while(curr_size <= max_size) {
        
#ifdef EN_THR_TESTS        
        // Prep for throughput test
        for(int i = 0; i < n_regions; i++) {
            cthread[i]->clearCompleted();
            sg[i].local.src_len = curr_size; sg[i].local.dst_len = curr_size;
            cs_invoke[i].sg_flags = { true, false, false };
        }
        n_runs = 0;
        
        // Throughput test
        auto benchmark_thr = [&]() {
            bool k = false;
            n_runs++;

            // Transfer the data
            for(int i = 0; i < n_reps_thr; i++)
                for(int j = 0; j < n_regions; j++) 
                    cthread[j]->invoke(cs_invoke[j]);

            while(!k) {
                k = true;
                for(int i = 0; i < n_regions; i++) 
                    if(cthread[i]->checkCompleted(CoyoteOper::LOCAL_WRITE) != n_reps_thr * n_runs) k = false;
                    //if(cthread[i]->checkCompleted(CoyoteOper::LOCAL_TRANSFER) != n_reps_thr * n_runs) k = false;
                if(stalled.load()) throw std::runtime_error("Stalled, SIGINT caught");
            }  
        };
        bench.runtime(benchmark_thr);
        std::cout << std::fixed << std::setprecision(2);
        std::cout << "Size: " << std::setw(8) << curr_size << ", thr: " << std::setw(8) << (n_regions * 1000 * curr_size) / (bench.getAvg() / n_reps_thr) << " MB/s";
    #ifndef EN_LAT_TESTS
        std::cout << std::endl;
    #endif
#endif

#ifdef EN_LAT_TESTS
        // Prep for latency test
        for(int i = 0; i < n_regions; i++) {
            cthread[i]->clearCompleted();
            sg[i].local.src_len = curr_size; sg[i].local.dst_len = curr_size;
            cs_invoke[i].sg_flags = { true, true, false };
        }
        n_runs = 0;

        // Latency test
        auto benchmark_lat = [&]() {
            // Transfer the data
            for(int i = 0; i < n_reps_lat; i++) {
                for(int j = 0; j < n_regions; j++) {
                    cthread[j]->invoke(cs_invoke[j]);
                    while(cthread[j]->checkCompleted(CoyoteOper::LOCAL_WRITE) != 1) 
                        if(stalled.load()) throw std::runtime_error("Stalled, SIGINT caught");           
                }
            }
        };
        bench.runtime(benchmark_lat);
        std::cout << ", lat: " << std::setw(8) << bench.getAvg() / (n_reps_lat) << " ns" << std::endl;
#endif

        curr_size *= 2;
    }

    std::cout << std::endl;
    
    // ---------------------------------------------------------------
    // Release 
    // ---------------------------------------------------------------
    
    // Print status
    for (int i = 0; i < n_regions; i++) {
        if(!mapped) {
            if(!huge) free(hMem[i]);
            else      munmap(hMem[i], max_size);  
        }
        cthread[i]->printDebug();
    }
    
    return EXIT_SUCCESS;
}
