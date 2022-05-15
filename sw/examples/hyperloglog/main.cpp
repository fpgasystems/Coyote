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

#include "cThread.hpp"
#include "cTask.hpp"

using namespace std;
using namespace fpga;

/* Def params */
constexpr auto const targetRegion = 0;
constexpr auto const defReps = 1;
constexpr auto const defSize = 4 * 1024;
constexpr auto const defDW = 4;
constexpr auto const defOpId = 0;
constexpr auto const defPr = 0;

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
    uint32_t reps = defReps;
    if(commandLineArgs.count("size") > 0) size = commandLineArgs["size"].as<uint32_t>();
    if(commandLineArgs.count("reps") > 0) reps = commandLineArgs["reps"].as<uint32_t>();

    uint32_t n_pages_host = (size + hugePageSize - 1) / hugePageSize;
    uint32_t n_pages_rslt = (reps * 4 + pageSize - 1) / pageSize;

    PR_HEADER("PARAMS");
    std::cout << "vFPGA ID: " << targetRegion << std::endl;
    std::cout << "Number of allocated pages per run: " << n_pages_host << std::endl;
    std::cout << "Data size: " << size << std::endl;
    std::cout << "Number of reps: " << reps << std::endl;

    // ---------------------------------------------------------------
    // Init 
    // ---------------------------------------------------------------

    // Handles and alloc
    cThread cthread(targetRegion, getpid());

    // Memory
    uint32_t* hMem[reps];
    float* rMem;

    // Fill
    for(int i = 0; i < reps; i++) {
        hMem[i] = (uint32_t*) cthread.getMem({CoyoteAlloc::REG_4K, n_pages_host});
        for(int j = 0; j < size/defDW; j++) {
            hMem[i][j] = rand();
        }
    }
    rMem = (float*) cthread.getMem({CoyoteAlloc::REG_4K, n_pages_rslt});

    // Task
    auto hll = [=](cThread* cthread, uint32_t* hmem, float* rmem, int rep){
        // Invoke
        cthread->invoke({CoyoteOper::TRANSFER, (void*)hmem, (void*)rmem, size, 4, true, true});
        std::cout << "Rep " << rep << " card: " << rmem[0] << std::endl;
    };

    // ---------------------------------------------------------------
    // Runs 
    // ---------------------------------------------------------------
    
    for(int i = 0; i < reps; i++) {
        cthread.scheduleTask(std::unique_ptr<bTask>(new cTask(i, defOpId, defPr, hll, hMem[i], &rMem[i], i)));
    }
    while(cthread.getCompletedCnt() != reps) {}
    std::cout << "Estimation completed" << std::endl;

    // ---------------------------------------------------------------
    // Exit 
    // ---------------------------------------------------------------
    
    return EXIT_SUCCESS;
}
