/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
  * All rights reserved.
  *
  * Redistribution and use in source and binary forms, with or without modification,
  * are permitted provided that the following conditions are met:
  *
  * 1. Redistributions of source code must retain the above copyright notice,
  * this list of conditions and the following disclaimer.
  * 2. Redistributions in binary form must reproduce the above copyright notice,
  * this list of conditions and the following disclaimer in the documentation
  * and/or other materials provided with the distribution.
  * 3. Neither the name of the copyright holder nor the names of its contributors
  * may be used to endorse or promote products derived from this software
  * without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  */

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
#include <sys/mman.h>

#include "cLib.hpp"
#include "types.hpp"

using namespace std;
using namespace fpga;

// Runtime 
constexpr auto const defRunHLL = false;
constexpr auto const defRunDtrees = false;
constexpr auto const defNTuples = 128 * 1024;
constexpr auto const defNFeatures = 5;

int main(int argc, char *argv[]) 
{

    
    // Read arguments
    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options()
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
    // HyperLogLog operator
    //
    if(runHLL) {
        // Connect to service
        cLib<double, uint64_t, uint64_t, uint32_t> clib_hll("/tmp/coyote-daemon-vfid-0-streaming", fidHLL); 

        // Let's get some buffers and fill it with some random data ...
        uint32_t* dMem = (uint32_t*) memalign(axiDataWidth, n_tuples * defDW);
        uint32_t* rMem = (uint32_t*) memalign(axiDataWidth, defDW);

        for(int i = 0; i < n_tuples; i++) {
            dMem[i] = rand();
        }
        
        // Execute the HLL
        // This is the only place of interaction with Coyote ...
        double cmpl_ev = clib_hll.task(opPriority, (uint64_t)dMem, (uint64_t)rMem, n_tuples);

        PR_HEADER("Hyper-Log-Log");
        std::cout << std::fixed << std::setprecision(2) << std::dec;
        std::cout << "Estimation completed, run time: " << cmpl_ev << " us" << std::endl;
        std::cout << "Estimated cardinality: " << ((float*)rMem)[0] << std::endl << std::endl;
        
        free(dMem);
        free(rMem);
    }
    
    //
    // Decision trees operator
    //
    if(runDtrees) {
        // Connect to service
        cLib<double, uint64_t, uint64_t, uint32_t, uint32_t> clib_dtrees("/tmp/coyote-daemon-vfid-0-streaming", fidDtrees);

        // Buffers ...
        uint32_t* dMem = (uint32_t*) mmap(NULL, n_tuples * n_features * defDW, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
        uint32_t* rMem = (uint32_t*) memalign(axiDataWidth, n_tuples * defDW);
        
        for (int i = 0; i < n_tuples; ++i) {
            for (int j = 0; j < n_features; ++j) {
                dMem[i * n_features + j] = ((float)(i+1))/((float)(j+i+1));
            }
        }

        // Execute the Decision trees
        // This is the only place of interaction with Coyote ...
        double cmpl_ev = clib_dtrees.task(opPriority, (uint64_t)dMem, (uint64_t)rMem, n_tuples, n_features);

        PR_HEADER("GBM Decision Trees");
        std::cout << std::fixed << std::setprecision(2) << std::dec;
        std::cout << "Estimation completed, run time: " << cmpl_ev << " us" << std::endl;
        std::cout << "Throughput achieved: " << ((double) n_tuples / (double)cmpl_ev) << ", MT/s" << std::endl << std::endl;

        munmap(dMem, n_tuples * n_features * defDW);
        munmap(rMem, n_tuples * defDW);
    }
    
    return (EXIT_SUCCESS);
}
