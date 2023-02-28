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

// Test vector
constexpr auto const keyLow = 0xabf7158809cf4f3c;
constexpr auto const keyHigh = 0x2b7e151628aed2a6;
constexpr auto const plainLow = 0xe93d7e117393172a;
constexpr auto const plainHigh = 0x6bc1bee22e409f96;
constexpr auto const cipherLow = 0xa89ecaf32466ef97;
constexpr auto const cipherHigh = 0x3ad77bb40d7a3660;

// Runtime
constexpr auto const defSize = 4 * 1024;
constexpr auto const opIdAes = 1;

int main(int argc, char *argv[]) 
{
    // Read arguments
    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options()
        ("size,s", boost::program_options::value<uint32_t>(), "Data size");

    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    uint32_t size = defSize;
    if(commandLineArgs.count("size") > 0) size = commandLineArgs["size"].as<uint32_t>();

    // Some data with plain text ...
    void *hMem = memalign(axiDataWidth, size);
    for(int i = 0; i < size / 8; i++) {
        ((uint64_t*) hMem)[i] = i%2 ? plainHigh : plainLow;
    }

    // 
    // Open a UDS and sent a task request
    // This is the only place of interaction needed with Coyote daemon !!!
    // 
    cLib clib("/tmp/coyote-daemon-vfid-0");
    clib.task({opIdAes, {(uint64_t) hMem, (uint64_t) size, (uint64_t) keyLow, (uint64_t) keyHigh}});

    // Check the results
    bool k = true;
    for(int i = 0; i < size / 8; i++) {
        if(i%2 ? ((uint64_t*) hMem)[i] != cipherHigh : ((uint64_t*) hMem)[i] != cipherLow) {
            k = false;
            break;
        }
    }

    std::cout << (k ? "Success: cipher text matches test vectors!" : "Error: found cipher text that doesn't match the test vector") << std::endl;
    return (EXIT_SUCCESS);
}
