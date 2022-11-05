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
constexpr auto const opIdAes = 1;

/**
 * @brief Main
 *  
 */
int main(void) 
{   
    // Create the daemon
    cService *cservice = cService::getInstance(targetRegion);

    // Load AES service task
    cservice->addTask(opIdAes, [] (cProcess *cproc, std::vector<uint64_t> params) { // addr, len, keyLow, keyHigh
        // Set up the key
        cproc->setCSR(params[2], 1);
        cproc->setCSR(params[3], 2);
        cproc->setCSR(0x1, 0);

        // Invoke
        cproc->invoke({CoyoteOper::TRANSFER, (void*)params[0], (void*)params[0], (uint32_t) params[1], (uint32_t) params[1]});
    });

    // Run the daemon
    cservice->run();
}

