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
constexpr auto const opPriority = 1;

constexpr auto const opIdAddMul = 1;
    constexpr auto const opAddMulMulReg = 0;
    constexpr auto const opAddMulAddReg = 1;
constexpr auto const opIdMinMax = 2;
    constexpr auto const opMinMaxCtrlReg = 0;
    constexpr auto const opMinMaxStatReg = 1;
    constexpr auto const opMinMaxMinReg = 2;
    constexpr auto const opMinMaxMaxReg = 3;
constexpr auto const opIdRotate = 3;
constexpr auto const opIdSelect = 4;
    constexpr auto const opSelectCtrlReg = 0;
    constexpr auto const opSelectStatReg = 1;
    constexpr auto const opSelectTypeReg = 2;
    constexpr auto const opSelectPredReg = 3;
    constexpr auto const opSelectRsltReg = 4;

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

    // Load addmul task
    cservice->addTask(opIdAddMul, [] (cProcess *cproc, std::vector<uint64_t> params) -> int32_t { // addr, len, mul, add
        // Lock vFPGA
        cproc->pLock(opIdAddMul, opPriority);
        
        // Prep
        cproc->setCSR(params[2], opAddMulMulReg); // Multiplication
        cproc->setCSR(params[3], opAddMulAddReg); // Addition

        // User map
        cproc->userMap((void*)params[0], (uint32_t)params[1]);

        // Invoke
        cproc->invoke({CoyoteOper::TRANSFER, (void*)params[0], (void*)params[0], (uint32_t) params[1], (uint32_t) params[1]});

        // User unmap
        cproc->userUnmap((void*)params[0]);

        // Unlock vFPGA
        cproc->pUnlock();
        
        return 0;
    });
    
    // Load minmax bitstream
    cservice->addBitstream("part_bstream_c1_" + std::to_string(vfid) + ".bin", opIdMinMax);

    // Load minmax task
    cservice->addTask(opIdMinMax, [] (cProcess *cproc, std::vector<uint64_t> params) -> int32_t { // addr, len
        // Lock vFPGA
        cproc->pLock(opIdMinMax, opPriority);
        
        // Prep
        cproc->setCSR(0x1, opMinMaxCtrlReg); // Start kernel

        // User map
        cproc->userMap((void*)params[0], (uint32_t)params[1]);

        // Invoke
        cproc->invoke({CoyoteOper::READ, (void*)params[0], (uint32_t) params[1]});

        // User unmap
        cproc->userUnmap((void*)params[0]);

        // Get max
        int max =  cproc->getCSR(opMinMaxMaxReg);

        // Unlock vFPGA
        cproc->pUnlock();

        return max;
    });

    // Load rotate bitstream
    cservice->addBitstream("part_bstream_c2_" + std::to_string(vfid) + ".bin", opIdRotate);

    // Load rotate task
    cservice->addTask(opIdRotate, [] (cProcess *cproc, std::vector<uint64_t> params) -> int32_t { // addr, len
        // Lock vFPGA
        cproc->pLock(opIdRotate, opPriority);
        
        // User map
        cproc->userMap((void*)params[0], (uint32_t)params[1]);

        // Invoke
        cproc->invoke({CoyoteOper::TRANSFER, (void*)params[0], (void*)params[0], (uint32_t) params[1], (uint32_t) params[1]});

        // User unmap
        cproc->userUnmap((void*)params[0]);

        // Unlock vFPGA
        cproc->pUnlock();

        return 0;
    });

    // Load select bitstream
    cservice->addBitstream("part_bstream_c3_" + std::to_string(vfid) + ".bin", opIdSelect);

    // Load select task
    cservice->addTask(opIdSelect, [] (cProcess *cproc, std::vector<uint64_t> params) { // addr, len, type, cond
        // Lock vFPGA
        cproc->pLock(opIdSelect, opPriority);
        
        // Prep
        cproc->setCSR(params[2], opSelectTypeReg); // Type of comparison
        cproc->setCSR(params[3], opSelectPredReg); // Predicate
        cproc->setCSR(0x1, opSelectCtrlReg); // Start kernel
        
        // User map
        cproc->userMap((void*)params[0], (uint32_t)params[1]);

        // Invoke
        cproc->invoke({CoyoteOper::READ, (void*)params[0], (uint32_t) params[1]});

        // User unmap
        cproc->userUnmap((void*)params[0]);

        // Check for completion
        while(cproc->getCSR(1) != 0x1) { nanosleep((const struct timespec[]){{0, 100L}}, NULL); }

        // Get count
        int count = cproc->getCSR(opSelectRsltReg);

        // Unlock vFPGA
        cproc->pUnlock();

        return count;
    });

    /* Run a daemon */
    cservice->run();
}

