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
#include <numeric>
#include <stdlib.h>

#include "cBench.hpp"
#include "cProcess.hpp"

using namespace std;
using namespace fpga;

/* Def params */
constexpr auto const targetRegion = 0;
constexpr auto const defReps = 1;
constexpr auto const defSize = 4 * 1024;
constexpr auto const defDW = 4;
constexpr auto const nBenchRuns = 1;

/**
 * @brief Throughput and latency tests, read and write
 */
int main(int argc, char *argv[])  
{
    // ---------------------------------------------------------------
    // Args 
    // ---------------------------------------------------------------

    // Read arguments
    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options() 
        ("size,s", boost::program_options::value<uint32_t>(), "Data size")
        ("reps,r", boost::program_options::value<uint32_t>(), "Number of reps");
    
    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    uint32_t size = defSize;
    uint32_t n_reps = defReps;
    if(commandLineArgs.count("size") > 0) size = commandLineArgs["size"].as<uint32_t>();
    if(commandLineArgs.count("reps") > 0) n_reps = commandLineArgs["reps"].as<uint32_t>();

    uint32_t n_pages_host = (size + hugePageSize - 1) / hugePageSize;
    uint32_t n_pages_rslt = (n_reps * 4 + pageSize - 1) / pageSize;

    PR_HEADER("PARAMS");
    std::cout << "vFPGA ID: " << targetRegion << std::endl;
    std::cout << "Number of allocated pages per run: " << n_pages_host << std::endl;
    std::cout << "Data size: " << size << std::endl;
    std::cout << "Number of reps: " << n_reps << std::endl;

    // ---------------------------------------------------------------
    // Init 
    // ---------------------------------------------------------------

    // Handles and alloc
    cProcess cproc(targetRegion, getpid());

    // Memory
    uint32_t* hMem[n_reps];
    float* rMem;

    // Fill
    for(int i = 0; i < n_reps; i++) {
        hMem[i] = (uint32_t*) cproc.getMem({CoyoteAlloc::HUGE_2M, n_pages_host});
        for(int j = 0; j < size/defDW; j++) {
            hMem[i][j] = rand();
        }
    }
    rMem = (float*) cproc.getMem({CoyoteAlloc::REG_4K, n_pages_rslt});

    // ---------------------------------------------------------------
    // Runs 
    // ---------------------------------------------------------------
    cBench bench(nBenchRuns);
    uint32_t n_runs;

    PR_HEADER("CARDINALITY ESTIMATION");

    auto benchmark_thr = [&]() {
        // Transfer the data
        for(int i = 0; i < n_reps; i++)
            cproc.invoke({CoyoteOper::TRANSFER, hMem[i], &rMem[i], size, 4});
    };
    bench.runtime(benchmark_thr);
    std::cout << std::fixed << std::setprecision(2);
    std::cout << "Size: " << std::setw(8) << size << ", thr: " << std::setw(8) << (1000 * size) / (bench.getAvg() / n_reps) << " MB/s" << std::endl << std::endl;
    for(int i = 0; i < n_reps; i++)
        std::cout << "Repetition: " << std::setw(8) << i << ", cardinality: " << rMem[i] << std::endl;
    std::cout << std::endl;

    std::cout << "Estimation completed" << std::endl;

    // ---------------------------------------------------------------
    // Exit 
    // ---------------------------------------------------------------
    
    return EXIT_SUCCESS;
}
