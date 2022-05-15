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

#include "cIpc.hpp"
#include "cLib.hpp"

// Test vector
constexpr auto const keyLow = 0xabf7158809cf4f3c;
constexpr auto const keyHigh = 0x2b7e151628aed2a6;
constexpr auto const plainLow = 0xe93d7e117393172a;
constexpr auto const plainHigh = 0x6bc1bee22e409f96;
constexpr auto const cipherLow = 0xa89ecaf32466ef97;
constexpr auto const cipherHigh = 0x3ad77bb40d7a3660;

constexpr auto const axiDataWidth = 64;
constexpr auto const defSize = 4 * 1024;

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

    // Req
    msgType msg {(uint64_t) memalign(axiDataWidth, size), size, keyLow, keyHigh}; 

    // Fill
    for(int i = 0; i < size / 8; i++) {
        ((uint64_t*) msg.src)[i] = i%2 ? plainHigh : plainLow;
    }

    // Register
    cLib clib{socketName};

    // Encrypt
    clib.run(msg);

    // Check
    bool k = true;
    for(int i = 0; i < size / 8; i++) {
        if(i%2 ? ((uint64_t*) msg.src)[i] != cipherHigh : ((uint64_t*) msg.src)[i] != cipherHigh) {
            k = false;
            break;
        }
    }

    std::cout << "Check returns: " << k << std::endl;

    // Sleep
    /*
    int32_t stime = atoi(argv[2]);
    sleep(stime);

    // Decrypt
    clib.run(msg);
    */
    // Write data

    return (EXIT_SUCCESS);
}
