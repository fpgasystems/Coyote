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
#include <boost/program_options.hpp>

#include "cBench.hpp"
#include "cProcess.hpp"

using namespace std;
using namespace fpga;

/* Def params */
constexpr auto const nRegions = 1;
constexpr auto const defHuge = false;
constexpr auto const defOper = false; // RD
constexpr auto const nReps = 1;
constexpr auto const defMinSize = 128;
constexpr auto const defMaxSize = 32 * 1024;
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

    // Read arguments
    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options()
        ("regions,n", boost::program_options::value<uint32_t>(), "Number of vFPGAs")
        ("huge,h", boost::program_options::value<bool>(), "Hugepages")
        ("reps,r", boost::program_options::value<uint32_t>(), "Number of repetitions")
        ("oper,o", boost::program_options::value<bool>(), "Rd/Wr")
        ("min_size,s", boost::program_options::value<uint32_t>(), "Starting transfer size")
        ("max_size,e", boost::program_options::value<uint32_t>(), "Ending transfer size");
    
    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    uint32_t n_regions = nRegions;
    bool huge = defHuge;
    uint32_t n_reps = nReps;
    bool oper = defOper;
    uint32_t curr_size = defMinSize;
    uint32_t max_size = defMaxSize;

    if(commandLineArgs.count("regions") > 0) n_regions = commandLineArgs["regions"].as<uint32_t>();
    if(commandLineArgs.count("huge") > 0) huge = commandLineArgs["huge"].as<bool>();
    if(commandLineArgs.count("reps") > 0) n_reps = commandLineArgs["reps"].as<uint32_t>();
    if(commandLineArgs.count("oper") > 0) oper = commandLineArgs["oper"].as<bool>();
    if(commandLineArgs.count("min_size") > 0) curr_size = commandLineArgs["min_size"].as<uint32_t>();
    if(commandLineArgs.count("max_size") > 0) max_size = commandLineArgs["max_size"].as<uint32_t>();

    uint32_t n_pages = huge ? ((max_size + hugePageSize - 1) / hugePageSize) : ((max_size + pageSize - 1) / pageSize);
    CoyoteOper curr_oper = oper ? CoyoteOper::WRITE : CoyoteOper::READ;

    PR_HEADER("PARAMS");
    std::cout << "Number of regions: " << n_regions << std::endl;
    std::cout << "Huge pages: " << huge << std::endl;
    std::cout << "Number of allocated pages: " << n_pages << std::endl;
    std::cout << "Number of repetitions: " << n_reps << std::endl;
    std::cout << "Operation: " << (oper ? "write" : "read") << std::endl;
    std::cout << "Starting transfer size: " << curr_size << std::endl;
    std::cout << "Starting transfer size: " << max_size << std::endl;

    // ---------------------------------------------------------------
    // Init 
    // ---------------------------------------------------------------

    // Handles
    std::vector<std::unique_ptr<cProcess>> cproc; // Coyote process
    void* hMem[n_regions];
    
    // Obtain resources
    for (int i = 0; i < n_regions; i++) {
        cproc.emplace_back(new cProcess(i, getpid()));
        hMem[i] = cproc[i]->getMem({huge ? CoyoteAlloc::HUGE_2M : CoyoteAlloc::REG_4K, n_pages});
    }
    
    // ---------------------------------------------------------------
    // Runs 
    // ---------------------------------------------------------------
    cBench bench(nBenchRuns);
    uint32_t n_runs;

    PR_HEADER("PERF MEM");
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
                    cproc[j]->invoke({curr_oper, hMem[j], hMem[j], curr_size, curr_size, false, false});

            while(!k) {
                k = true;
                for(int i = 0; i < n_regions; i++)
                    if(cproc[i]->checkCompleted(curr_oper) != n_reps * n_runs) k = false;
            }  
        };
        bench.runtime(benchmark_thr);
        std::cout << std::fixed << std::setprecision(2);
        std::cout << "Size: " << std::setw(8) << curr_size << ", thr: " << std::setw(8) << (n_regions * 1000 * curr_size) / (bench.getAvg() / n_reps) << " MB/s";

        // Latency test
        auto benchmark_lat = [&]() {
            // Transfer the data
            for(int i = 0; i < n_reps; i++) {
                for(int j = 0; j < n_regions; j++) {
                    cproc[j]->invoke({curr_oper, hMem[j], hMem[j], curr_size, curr_size, true, false});
                    while(cproc[j]->checkCompleted(curr_oper) != 1) ;            
                }
            }
        };
        bench.runtime(benchmark_lat);
        std::cout << ", lat: " << std::setw(8) << bench.getAvg() / (n_reps) << " ns" << std::endl;

        curr_size *= 2;
    }
    std::cout << std::endl;
    
    // ---------------------------------------------------------------
    // Release 
    // ---------------------------------------------------------------
    
    // Print status
    for (int i = 0; i < n_regions; i++) {
        cproc[i]->printDebug();
    }
    
    return EXIT_SUCCESS;
}
