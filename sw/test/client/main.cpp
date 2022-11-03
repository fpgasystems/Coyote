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
#include "cLib.hpp"

using namespace std;
using namespace std::this_thread; // sleep_for, sleep_until
using namespace std::chrono; // nanoseconds, system_clock, seconds
using namespace fpga;

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
    cLib clib("/tmp/coyote-daemon-vfid-0");
    uint64_t delay = 1;

    clib.task({1, {2}});

    return EXIT_SUCCESS;
}