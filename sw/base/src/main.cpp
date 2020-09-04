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
#include <x86intrin.h>
#include <boost/program_options.hpp>

#include "fBench.hpp"
#include "fDev.hpp"

using namespace std;
using namespace std::chrono;
using namespace fpga;

/* Runtime */
#define N_REGIONS           1
#define N_PAGES             8 // 16 MB
#define N_REPS              1
#define TR_SIZE             (4 * 1024)

/**
 * Loopback example.
 * This code is used to demonstrate data transfer abilities of the system. 
 * It can be used with a number of provided operators with minimal modifications
 * (addmul, AES, chacha, hll, lpn ...)
 */
int main(int argc, char *argv[])  
{
    // ---------------------------------------------------------------
    // -- Initialization 
    // ---------------------------------------------------------------

    // Read arguments
    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options()("regions,n", boost::program_options::value<uint32_t>(), "Number of FPGA regions")
                                    ("host,h", boost::program_options::value<bool>(), "Explicit FPGA memory allocation")
                                    ("stream,t", boost::program_options::value<bool>(), "Host or card")
                                    ("pages,p", boost::program_options::value<uint32_t>(), "Huge page allocation")
                                    ("reps,r", boost::program_options::value<uint32_t>(), "Number of repetitions")
                                    ("size, s", boost::program_options::value<uint32_t>(), "Transfer size");
    
    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    uint32_t n_regions = N_REGIONS;
    bool host = 0;
    bool stream = 1;
    uint32_t n_pages = N_PAGES;
    uint32_t n_reps = N_REPS;
    uint32_t size = TR_SIZE;

    if(commandLineArgs.count("regions") > 0) n_regions = commandLineArgs["regions"].as<uint32_t>();
    if(commandLineArgs.count("host") > 0) host = commandLineArgs["host"].as<bool>();
    if(commandLineArgs.count("stream") > 0) stream = commandLineArgs["stream"].as<bool>();
    if(commandLineArgs.count("pages") > 0) n_pages = commandLineArgs["pages"].as<uint32_t>();
    if(commandLineArgs.count("reps") > 0) n_reps = commandLineArgs["reps"].as<uint32_t>();
    if(commandLineArgs.count("size") > 0) size = commandLineArgs["size"].as<uint32_t>();

    // FPGA handles
    fDev *fdev = new fDev[N_REGIONS];

    // Memory 
    uint64_t *hMem[N_REGIONS];

    // Obtain regions
    for (int i = 0; i < N_REGIONS; i++) {
        if (!fdev[i].acquireRegion(i)) return EXIT_FAILURE;
        fdev[i].clearCompleted(); // Clear records of previous transactions
    }

    // Allocate buffers
    for(int i = 0; i < N_REGIONS; i++) {
        if(host)
            hMem[i] = fdev[i].getHostMem(N_PAGES);
        else
            hMem[i] = (uint64_t*) memalign(64, TR_SIZE);
    }

    // ---------------------------------------------------------------
    // -- Runs 
    // ---------------------------------------------------------------
    Bench bench(n_reps, size);
    uint32_t n_runs = 0;
    
    // Throughput test
    auto benchmark_thr = [&fdev, &hMem, &n_runs, n_reps, n_regions, size, stream]() {
        bool k = false;
        n_runs++;

        // Transfer the data
        for(int i = 0; i < n_reps; i++) {
            for(int j = 0; j < n_regions; j++) {
                fdev[j].transfer(hMem[j], hMem[j], size, size, stream, false);
            }
        }

        while(!k) {
            k = true;
            for(int i = 0; i < n_regions; i++)
                if(fdev[i].checkCompletedWrite() != n_reps * n_runs) k = false;
        }  
    };
    bench.runtime(benchmark_thr);
    std::cout << "Throughput: " << ((n_regions * 1000 * size)) / (bench.getAvg() / n_reps) << " MB/s" << std::endl;

    // Latency test
    auto benchmark_lat = [&fdev, &hMem, n_reps, n_regions, size, stream]() {
        // Transfer the data
        for(int i = 0; i < n_reps; i++) {
            for(int j = 0; j < n_regions; j++) {
                fdev[j].transfer(hMem[j], hMem[j], size, size, stream, true);
                while(fdev[j].checkCompletedWrite() != 1);
            }
        }
    };
    bench.runtime(benchmark_lat);
    std::cout << "Latency: " << bench.getAvg() / n_reps << " ns" << std::endl;

    // Free buffers
    for(int i = 0; i < N_REGIONS; i++) {
        if(host)
            fdev[i].freeHostMem(hMem[i], N_PAGES);
        else
            free(hMem[i]);
    }

    // Release regions
    for (int i = 0; i < N_REGIONS; i++) {
        fdev[i].releaseRegion();
    }

    return EXIT_SUCCESS;
}
