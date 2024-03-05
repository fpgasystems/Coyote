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

#include "cSched.hpp"
#include "cBench.hpp"
#include "cProcess.hpp"

using namespace std;
using namespace fpga;

/* Def params */
constexpr auto const targetRegion = 0;

constexpr auto const opAddMul = 0;
constexpr auto const opMinMax = 1;
constexpr auto const opRotate = 2;
constexpr auto const opTestcount = 3;

constexpr auto const defSize = 1024;

/**
 * @brief Loopback example
 * 
 */

int main(int argc, char *argv[])  
{
    // ---------------------------------------------------------------
    // Args 
    // ---------------------------------------------------------------

    // ---------------------------------------------------------------
    // Init 
    // ---------------------------------------------------------------
    cSched csched(targetRegion, false, false);

    csched.addBitstream("bstream_c0_0.bin", opAddMul);
    csched.addBitstream("bstream_c1_0.bin", opMinMax);
    csched.addBitstream("bstream_c2_0.bin", opRotate);
    csched.addBitstream("bstream_c3_0.bin", opTestcount);

    cProcess cproc(targetRegion, getpid());

    //
    // Addmul
    //

    uint32_t *hMem = malloc(defSize);

    // Prep
    cproc.setCSR(2, 0); // Addition
    cproc.setCSR(3, 1); // Multiplication

    // User map
    cproc.userMap((void*)vaddr, (uint32_t)size);

    // Invoke
    cproc.invoke({CoyoteOper::TRANSFER, (void*)hMem, (void*)hMem, (uint32_t) defSize, (uint32_t) defSize});

    // User unmap
    cproc.userUnmap((void*)hMem);


    return EXIT_SUCCESS;
}
