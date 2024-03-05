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
#include <sys/socket.h>
#include <sys/un.h>
#include <sstream>

#include "cLib.hpp"

using namespace std;
using namespace fpga;

// Runtime 
// 2 examples:
//  - HyperLogLog
//  - Decision trees
constexpr auto const operatorHLL = 1;
constexpr auto const operatorDtrees = 2;

constexpr auto const defRunHLL = false;
constexpr auto const defRunDtrees = false;
constexpr auto const defNTuples = 128 * 1024;
constexpr auto const defNFeatures = 5;

// Tuple width
constexpr auto const defDW = 4;

int main(int argc, char *argv[]) 
{
    // Read arguments
    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options()
        ("size,s", boost::program_options::value<uint32_t>(), "Data size")
        ("tuples,t", boost::program_options::value<bool>(), "Number of tuples")
        ("features,f", boost::program_options::value<bool>(), "Number of features")
        ("hloglog,h", boost::program_options::value<bool>(), "Run HyperLogLog")
        ("dtrees,d", boost::program_options::value<bool>(), "Run Decision Trees");

    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    bool runHLL = defRunHLL;
    bool runDtrees = defRunDtrees;
    uint32_t n_tuples = defNTuples;
    uint32_t n_features = defNFeatures;

    if(commandLineArgs.count("hloglog") > 0) runHLL = commandLineArgs["hloglog"].as<bool>();
    if(commandLineArgs.count("dtrees") > 0) runDtrees = commandLineArgs["dtrees"].as<bool>();
    if(commandLineArgs.count("tuples") > 0) n_tuples = commandLineArgs["tuples"].as<uint32_t>();
    if(commandLineArgs.count("features") > 0) n_features = commandLineArgs["features"].as<uint32_t>();

    // 
    // Open a UDS and sent a task request
    // This is the only place of interaction needed with Coyote daemon !!!
    // 
    cLib clib("/tmp/coyote-daemon-vfid-0");

    //
    // HyperLogLog operator
    //
    if(runHLL) {
        // Let's get some buffers and fill it with some random data ...
        uint32_t n_pages_host = (n_tuples * defDW + pageSize - 1) / pageSize;
        uint32_t n_pages_rslt = (defDW + pageSize - 1) / pageSize;

        uint64_t* dMem = (uint64_t*) memalign(axiDataWidth, n_pages_host);
        uint64_t* rMem = (uint64_t*) memalign(axiDataWidth, n_pages_rslt);

        for(int i = 0; i < n_tuples; i++) {
            dMem[i] = rand();
        }

        // Execute the HLL
        cmplVal cmpl_val = clib.task({operatorHLL, {(uint64_t) dMem, (uint64_t) rMem, (uint64_t) n_tuples}});

        //
        PR_HEADER("Hyper-Log-Log");
        std::cout << std::fixed << std::setprecision(2);
        std::cout << "Estimation completed, run time: " << cmpl_val.time << " us" << std::endl << std::endl;

        free(dMem);
        free(rMem);
    } 

    if(runDtrees) {
        // Let's get some buffers and fill it with some random data ...
        uint32_t n_pages_host = (n_tuples * n_features * defDW + pageSize - 1) / pageSize;
        uint32_t n_pages_rslt = (n_tuples * defDW + pageSize - 1) / pageSize;

        uint64_t* dMem = (uint64_t*) memalign(axiDataWidth, n_pages_host);
        uint64_t* rMem = (uint64_t*) memalign(axiDataWidth, n_pages_rslt);

        for (int i = 0; i < n_tuples; ++i) {
            for (int j = 0; j < n_features; ++j) {
                dMem[i * n_features + j] = ((float)(i+1))/((float)(j+i+1));
            }
        }

        // Execute the Decision trees
        cmplVal cmpl_val = clib.task({operatorDtrees, {(uint64_t) dMem, (uint64_t) rMem, (uint64_t) n_tuples, (uint64_t) n_features}});

        PR_HEADER("GBM Decision Trees");
        std::cout << "Estimation completed, run time: " << cmpl_val.time << " us" << std::endl << std::endl;
        
        free(dMem);
        free(rMem);
    }

    return (EXIT_SUCCESS);
}
