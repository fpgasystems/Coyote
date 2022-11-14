#include <dirent.h>
#include <iterator>
#include <cstdlib>
#include <cstring>
#include <sstream>
#include <iostream>
#include <stdlib.h>
#include <string>
#include <sys/stat.h>
#include <syslog.h>
#include <unistd.h>
#include <vector>
#include <signal.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <iomanip>
#include <chrono>
#include <thread>
#include <limits>
#include <assert.h>
#include <stdio.h>
#include <sys/un.h>
#include <errno.h>
#include <wait.h>
#include <vector>
#include <unordered_map>
#include <mutex>
#include <condition_variable>
#include <boost/program_options.hpp>

#include "cService.hpp"

using namespace std;
using namespace fpga;

// Runtime
constexpr auto const defTargetRegion = 0;

// Operators
constexpr auto const opIdAddMul = 1;
constexpr auto const opIdMinMax = 2;
constexpr auto const opIdRotate = 3;
constexpr auto const opIdSelect = 4;

/**
 * @brief Main
 *  
 */
int main(int argc, char *argv[]) 
{   
    /* Args */
    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options()
        ("vfid,i", boost::program_options::value<uint32_t>(), "Target vFPGA");

    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    uint32_t vfid = defTargetRegion;
    if(commandLineArgs.count("vfid") > 0) vfid = commandLineArgs["vfid"].as<uint32_t>();
    
    /* Create a daemon */
    cService *cservice = cService::getInstance(vfid);

    /**
     * @brief Load all operators
     * 
     */

    // Load addmul bitstream
    cservice->addBitstream("part_bstream_c0_" + std::to_string(vfid) + ".bin", opIdAddMul);

    // Load addmul operator
    cservice->addTask(opIdAddMul, [] (cProcess *cproc, std::vector<uint64_t> params) { // addr, len, add, mul
        // Prep
        cproc->setCSR(params[3], 0); // Addition
        cproc->setCSR(params[4], 1); // Multiplication

        // User map
        cproc->userMap((void*)params[0], (uint32_t)params[1]);

        // Invoke
        cproc->invoke({CoyoteOper::TRANSFER, (void*)params[0], (void*)params[0], (uint32_t) params[1], (uint32_t) params[1]});

        // User unmap
        cproc->userUnmap((void*)params[0]);
    });
    
    // Load minmax bitstream
    cservice->addBitstream("part_bstream_c1_" + std::to_string(vfid) + ".bin", opIdMinMax);

    // Load minmax operator
    cservice->addTask(opIdMinMax, [] (cProcess *cproc, std::vector<uint64_t> params) { // addr, len
        // Prep
        cproc->setCSR(0x1, 1); // Start kernel

        // User map
        cproc->userMap((void*)params[0], (uint32_t)params[1]);

        // Invoke
        cproc->invoke({CoyoteOper::READ, (void*)params[0], (uint32_t) params[1]});

        // User unmap
        cproc->userUnmap((void*)params[0]);
    });

    // Load rotate bitstream
    cservice->addBitstream("part_bstream_c2_" + std::to_string(vfid) + ".bin", opIdRotate);

    // Load rotete operator
    cservice->addTask(opIdRotate, [] (cProcess *cproc, std::vector<uint64_t> params) { // addr, len
        // User map
        cproc->userMap((void*)params[0], (uint32_t)params[1]);

        // Invoke
        cproc->invoke({CoyoteOper::TRANSFER, (void*)params[0], (void*)params[0], (uint32_t) params[1], (uint32_t) params[1]});

        // User unmap
        cproc->userUnmap((void*)params[0]);
    });

    // Load select bitstream
    cservice->addBitstream("part_bstream_c3_" + std::to_string(vfid) + ".bin", opIdSelect);

    // Load select
    cservice->addTask(opIdSelect, [] (cProcess *cproc, std::vector<uint64_t> params) { // addr, len, type, cond
        // Prep
        cproc->setCSR(params[2], 2); // Type of comparison
        cproc->setCSR(params[3], 3); // Predicate
        cproc->setCSR(0x1, 0); // Start kernel
        
        // User map
        cproc->userMap((void*)params[0], (uint32_t)params[1]);

        // Invoke
        cproc->invoke({CoyoteOper::READ, (void*)params[0], (uint32_t) params[1]});
        while(cproc->getCSR(1) != 0x1) { nanosleep((const struct timespec[]){{0, 100L}}, NULL); }

        // User unmap
        cproc->userUnmap((void*)params[0]);
    });

    /* Run a daemon */
    cservice->run();
}

