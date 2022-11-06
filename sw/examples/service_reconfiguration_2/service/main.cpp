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

#include "cService.hpp"

using namespace std;
using namespace fpga;

constexpr auto const targetRegion = 0;
constexpr auto const opIdAddMul = 1;
constexpr auto const opIdMinMax = 2;
constexpr auto const opIdRotate = 3;

/**
 * @brief Main
 *  
 */
int main(void) 
{   
    /* Create a daemon */
    cService *cservice = cService::getInstance(targetRegion);

    /**
     * @brief Load all operators
     * 
     */

    // Load addmul bitstream
    cservice->addBitstream("part_bstream_c0_0.bin", opIdAddMul);

    // Load addmul operator
    cservice->addTask(opIdAddMul, [] (cProcess *cproc, std::vector<uint64_t> params) { // addr, len, add, mul
        // Prep
        cthread->setCSR(params[3], 0); // Addition
        cthread->setCSR(params[4], 1); // Multiplication

        // User map
        cproc->userMap((void*)params[0], (uint32_t)params[1]);

        // Invoke
        cproc->invoke({CoyoteOper::TRANSFER, (void*)params[0], (void*)params[0], (uint32_t) params[1], (uint32_t) params[1]});

        // User unmap
        cproc->userUnmap((void*)params[0]);
    });
    
    // Load minmax bitstream
    cservice->addBitstream("part_bstream_c1_0.bin", opIdMinMax);

    // Load minmax operator
    cservice->addTask(opIdMinMax, [] (cProcess *cproc, std::vector<uint64_t> params) { // addr, len
        // Prep
        cthread->setCSR(0x1, 1); // Start kernel

        // User map
        cproc->userMap((void*)params[0], (uint32_t)params[1]);

        // Invoke
        cproc->invoke({CoyoteOper::READ, (void*)params[0], (uint32_t) params[1]});

        // User unmap
        cproc->userUnmap((void*)params[0]);
    });

    // Load rotate bitstream
    cservice->addBitstream("part_bstream_c2_0.bin", opIdRotate);

    // Load minmax operator
    cservice->addTask(opIdMinMax, [] (cProcess *cproc, std::vector<uint64_t> params) { // addr, len
        // User map
        cproc->userMap((void*)params[0], (uint32_t)params[1]);

        // Invoke
        cproc->invoke({CoyoteOper::TRANSFER, (void*)params[0], (void*)params[0], (uint32_t) params[1], (uint32_t) params[1]});

        // User unmap
        cproc->userUnmap((void*)params[0]);
    });

    // Load rotate bitstream
    cservice->addBitstream("part_bstream_c3_0.bin", opIdTescount);

    // Load testcount
    cservice->addTask(opIdTescount, [] (cProcess *cproc, std::vector<uint64_t> params) { // addr, len, type, cond
        // Prep
        cthread->setCSR(params[2], 2); // Type of comparison
        cthread->setCSR(params[3], 3); // Predicate
        cthread->setCSR(0x1, 0); // Start kernel
        
        // User map
        cproc->userMap((void*)params[0], (uint32_t)params[1]);

        // Invoke
        cproc->invoke({CoyoteOper::READ, (void*)params[0], (uint32_t) params[1]});
        while(cthread->getCSR(1) != 0x1) { nanosleep((const struct timespec[]){{0, 100L}}, NULL); }

        // User unmap
        cproc->userUnmap((void*)params[0]);
    });

    /* Run a daemon */
    cservice->run();
}

