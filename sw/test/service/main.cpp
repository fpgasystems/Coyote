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
#include "cThread.hpp"
#include "cService.hpp"

using namespace std;
using namespace std::this_thread; // sleep_for, sleep_until
using namespace std::chrono; // nanoseconds, system_clock, seconds
using namespace fpga;

/* Def params */
constexpr auto const nRegions = 1;
constexpr auto const defHuge = false;
constexpr auto const nReps = 1;
constexpr auto const defMinSize = 128;
constexpr auto const defMaxSize = 32 * 1024;
constexpr auto const nBenchRuns = 1;

/**
 * @brief Loopback example
 * 
 */
int main(int argc, char *argv[])  
{

    // ---------------------------------------------------------------
    // Init 
    // ---------------------------------------------------------------

    // Handles
    cService *cservice = cService::getInstance(0);

    auto prnt = [](cProcess *cprocess, std::vector<uint64_t> params)
    {
        syslog(LOG_NOTICE, "This is a task that runs for %lds, it starts now...", params[0]);
        sleep(params[0]);
        syslog(LOG_NOTICE, "Done, waking up");
    };

    cservice->addTask(1, prnt);
    cservice->run();

    return EXIT_SUCCESS;
}