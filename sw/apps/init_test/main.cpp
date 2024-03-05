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
#include "cProcess.hpp"

using namespace std;
using namespace std::chrono;
using namespace fpga;

/* Signal handler */
std::atomic<bool> stalled(false); 
void gotInt(int) {
    stalled.store(true);
}

/* Def params */
constexpr auto const nRegions = 1;
constexpr auto const defHuge = true;
constexpr auto const defMappped = false;
constexpr auto const nReps = 1;
constexpr auto const defMinSize = 8 * 1024; //16 * 1024 * 1024;
constexpr auto const defMaxSize = 8 * 1024; //16 * 1024 * 1024;
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
        ("reps,r", boost::program_options::value<uint32_t>(), "Number of repetitions")
        ("min_size,s", boost::program_options::value<uint32_t>(), "Starting transfer size")
        ("max_size,e", boost::program_options::value<uint32_t>(), "Ending transfer size");
    
    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    uint32_t n_regions = nRegions;
    bool huge = defHuge;
    bool mapped = defMappped;
    uint32_t n_reps = nReps;
    uint32_t curr_size = defMinSize;
    uint32_t max_size = defMaxSize;

    if(commandLineArgs.count("regions") > 0) n_regions = commandLineArgs["regions"].as<uint32_t>();
    if(commandLineArgs.count("hugepages") > 0) huge = commandLineArgs["hugepages"].as<bool>();
    if(commandLineArgs.count("mapped") > 0) mapped = commandLineArgs["mapped"].as<bool>();
    if(commandLineArgs.count("reps") > 0) n_reps = commandLineArgs["reps"].as<uint32_t>();
    if(commandLineArgs.count("min_size") > 0) curr_size = commandLineArgs["min_size"].as<uint32_t>();
    if(commandLineArgs.count("max_size") > 0) max_size = commandLineArgs["max_size"].as<uint32_t>();

    uint32_t n_pages = huge ? ((max_size + hugePageSize - 1) / hugePageSize) : ((max_size + pageSize - 1) / pageSize);

    PR_HEADER("PARAMS");
    std::cout << "Number of regions: " << n_regions << std::endl;
    std::cout << "Hugepages: " << huge << std::endl;
    std::cout << "Mapped pages: " << mapped << std::endl;
    std::cout << "Number of allocated pages: " << n_pages << std::endl;
    std::cout << "Min size: " << curr_size << std::endl;
    std::cout << "Max size: " << max_size << std::endl;
    std::cout << "Number of repetitions: " << n_reps << std::endl;

    // ---------------------------------------------------------------
    // Init 
    // ---------------------------------------------------------------

    // Handles
    std::vector<std::unique_ptr<cProcess>> cproc; // Coyote process
    int n_dests = 4;
    void* hMem[n_dests];
    
    // Obtain resources
    for(int i = 0; i < n_regions; i++) {
        cproc.emplace_back(new cProcess(i, getpid()));
    }

    /*
    for(int i = 0; i < n_regions; i++) {   
        hMem[i] = mapped ? (cproc[i]->getMem({huge ? CoyoteAlloc::HPF : CoyoteAlloc::REG, n_pages})) 
                        : (huge ? (mmap(NULL, max_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0))
                                : (memalign(axiDataWidth, max_size)));           

        std::cout << "hMem[" << i << "]: " << std::hex << (uint64_t)(hMem[i]) << std::dec << std::endl;             
    } 
    */     

    for(int i = 0; i < n_dests; i++) {   
        hMem[i] = mapped ? (cproc[0]->getMem({huge ? CoyoteAlloc::HPF : CoyoteAlloc::REG, n_pages})) 
                        : (huge ? (mmap(NULL, max_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0))
                                : (memalign(axiDataWidth, max_size)));           

        std::cout << "hMem[" << i << "]: " << std::hex << (uint64_t)(hMem[i]) << std::dec << std::endl;             
    }         
    
    // ---------------------------------------------------------------
    // Runs 
    // ---------------------------------------------------------------
    cBench bench(nBenchRuns);
    uint32_t n_runs;
    
    cproc[0]->clearCompleted();

    for(int i = 0; i < n_dests; i++)
        cproc[0]->invoke({CoyoteOper::OFFLOAD, 
            hMem[i], curr_size, false, 0,
            true, true, false}); 
    
    
    
    
    PR_HEADER("PERF HOST");
    while(curr_size <= max_size) {
        // Prep
        for(int i = 0; i < n_regions; i++) 
            cproc[i]->clearCompleted();
        n_runs = 0;
        
        // Throughput test
        auto benchmark_thr = [&]() {
            bool k = false;
            n_runs++;

            // Transfer the data
            for(int i = 0; i < n_reps; i++)
                for(int j = 0; j < n_regions; j++) 
                    for(int p = 0; p < n_dests; p++) {
                        /*
                        cproc[j]->invoke({
                            CoyoteOper::TRANSFER, 
                            hMem[j], curr_size, false, (uint32_t)p,
                            hMem[j], curr_size, false, (uint32_t)p,
                            false, true, false}
                        );
                        */

                        cproc[j]->invoke({
                            CoyoteOper::READ, 
                            hMem[p], curr_size, false, (uint32_t)p,
                            false, true, false}
                        );
                    }

            while(!k) {
                k = true;
                for(int i = 0; i < n_regions; i++) 
                    if(cproc[i]->checkCompleted(CoyoteOper::READ) != n_dests * n_reps * n_runs) { k = false; }//cproc[i]->printDebug(); std::cout << std::endl << cproc[i]->checkCompleted(CoyoteOper::TRANSFER) << std::endl; sleep(4); }
                if(stalled.load()) throw std::runtime_error("Stalled, SIGINT caught");
            }  
        };
        bench.runtime(benchmark_thr);
        std::cout << std::fixed << std::setprecision(2);
<<<<<<< HEAD
        std::cout << "Size: " << std::setw(8) << curr_size << ", thr: " << std::setw(8) << (n_dests * n_regions * 1000 * curr_size) / (bench.getAvg() / n_reps) << " MB/s"
         << std::endl;
/*
=======
        std::cout << "Size: " << std::setw(8) << curr_size << ", thr: " << std::setw(8) << (n_regions * 1000 * curr_size) / (bench.getAvg() / n_reps) << " MB/s";
    /*
>>>>>>> 2c873434299ffc31c5025f2cc2d3394b52cb991a
        // Latency test
        auto benchmark_lat = [&]() {
            // Transfer the data
            for(int i = 0; i < n_reps; i++) {
                for(int j = 0; j < n_regions; j++) {
                    cproc[j]->invoke({
                        CoyoteOper::TRANSFER, 
                        hMem[j], curr_size, true, 0,
                        hMem[j], curr_size, true, 0, 
                        true, true, false}
                    );
                    while(cproc[j]->checkCompleted(CoyoteOper::TRANSFER) != 1) {
                        if(stalled.load()) throw std::runtime_error("Stalled, SIGINT caught");           
                    }
                }
            }
        };
        bench.runtime(benchmark_lat);
        std::cout << ", lat: " << std::setw(8) << bench.getAvg() / (n_reps) << " ns" << std::endl;
<<<<<<< HEAD
*/
=======
    */
>>>>>>> 2c873434299ffc31c5025f2cc2d3394b52cb991a
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
    }
    
    return EXIT_SUCCESS;
}
