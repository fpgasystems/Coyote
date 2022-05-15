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
#include "cProc.hpp"

using namespace std;
using namespace fpga;

/* Def params */
constexpr auto const nRegions = 1;
constexpr auto const defHuge = false;
constexpr auto const nReps = 1;
constexpr auto const defSize = 512;
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
        ("size,s", boost::program_options::value<uint32_t>(), "Transfer size");
    
    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    uint32_t n_regions = nRegions;
    bool huge = defHuge;
    uint32_t n_reps = nReps;
    uint32_t size = defSize;

    if(commandLineArgs.count("regions") > 0) n_regions = commandLineArgs["regions"].as<uint32_t>();
    if(commandLineArgs.count("huge") > 0) huge = commandLineArgs["huge"].as<bool>();
    if(commandLineArgs.count("reps") > 0) n_reps = commandLineArgs["reps"].as<uint32_t>();
    if(commandLineArgs.count("size") > 0) size = commandLineArgs["size"].as<uint32_t>();

    uint32_t n_pages = huge ? ((size + hugePageSize - 1) / hugePageSize) : ((size + pageSize - 1) / pageSize);

    PR_HEADER("PARAMS");
    std::cout << "Number of regions: " << n_regions << std::endl;
    std::cout << "Huge pages: " << huge << std::endl;
    std::cout << "Number of allocated pages: " << n_pages << std::endl;
    std::cout << "Number of repetitions: " << n_reps << std::endl;
    std::cout << "Transfer size: " << size << std::endl;

    // ---------------------------------------------------------------
    // Init 
    // ---------------------------------------------------------------

    // Handles
    std::vector<std::unique_ptr<cProc>> cproc; // Coyote process
    void* hMem[n_regions];
    
    // Obtain resources
    for (int i = 0; i < n_regions; i++) {
        cproc.emplace_back(new cProc(i, getpid()));
        hMem[i] = cproc[i]->getMem({huge ? CoyoteAlloc::HUGE_2M : CoyoteAlloc::REG_4K, n_pages});
    }
    
    // ---------------------------------------------------------------
    // Runs 
    // ---------------------------------------------------------------
    cBench bench(nBenchRuns);
    uint32_t n_runs = 0;
    
    // Throughput test
    auto benchmark_thr = [&]() {
        bool k = false;
        n_runs++;

        // Transfer the data
        for(int i = 0; i < n_reps; i++)
            for(int j = 0; j < n_regions; j++) 
                cproc[j]->invoke({CoyoteOper::TRANSFER, hMem[j], hMem[j], size, size, false, false});

        while(!k) {
            k = true;
            for(int i = 0; i < n_regions; i++)
                if(cproc[i]->checkCompleted(CoyoteOper::TRANSFER) != n_reps * n_runs) k = false;
        }  
    };
    bench.runtime(benchmark_thr);
    PR_HEADER("THROUGHPUT");
    std::cout << "Throughput: " << (n_regions * 1000 * size) / (bench.getAvg() / n_reps) << " MB/s" << std::endl;
    
    n_runs = 0;

    // Latency test
    auto benchmark_lat = [&]() {
        // Transfer the data
        for(int i = 0; i < n_reps; i++) {
            for(int j = 0; j < n_regions; j++) {
                cproc[j]->invoke({CoyoteOper::TRANSFER, hMem[j], hMem[j], size, size, true, false});
                while(cproc[j]->checkCompleted(CoyoteOper::TRANSFER) != 1) ;            
            }
        }
    };
    bench.runtime(benchmark_lat);
    PR_HEADER("LATENCY");
    std::cout << "Latency: " << bench.getAvg() / (n_reps) << " ns" << std::endl;
    
    // ---------------------------------------------------------------
    // Release 
    // ---------------------------------------------------------------
    
    // Print status
    for (int i = 0; i < n_regions; i++) {
        cproc[i]->printDebug();
    }
    
    return EXIT_SUCCESS;
}
