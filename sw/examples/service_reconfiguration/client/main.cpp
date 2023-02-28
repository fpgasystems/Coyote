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

// Runtime
constexpr auto const defSize = 4 * 1024;
constexpr auto const defAdd = 10;
constexpr auto const defMul = 2;
constexpr auto const defType = 0;
constexpr auto const defPredicate = 100;

constexpr auto const defAddMul = true;
constexpr auto const defMinMax = true;
constexpr auto const defRotate = true;
constexpr auto const defSelect = true;

// Operators
constexpr auto const opIdAddMul = 1;
constexpr auto const opIdMinMax = 2;
constexpr auto const opIdRotate = 3;
constexpr auto const opIdSelect = 4;

int main(int argc, char *argv[]) 
{
    // Read arguments
    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options()
        ("size,s", boost::program_options::value<uint32_t>(), "Data size")
        ("addmul,a", boost::program_options::value<bool>(), "Run addmul")
        ("minmax,m", boost::program_options::value<bool>(), "Run minmax")
        ("rotate,r", boost::program_options::value<bool>(), "Run rotate")
        ("count,c", boost::program_options::value<bool>(), "Run count");

    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    uint32_t size = defSize;
    bool runAddMul = defAddMul;
    bool runMinMax = defMinMax;
    bool runAddMul = defRotate;
    bool runSelect = defSelect;

    if(commandLineArgs.count("size") > 0) size = commandLineArgs["size"].as<uint32_t>();
    if(commandLineArgs.count("addmul") > 0) runAddMul = commandLineArgs["addmul"].as<bool>();
    if(commandLineArgs.count("minmax") > 0) runMinMax = commandLineArgs["minmax"].as<bool>();
    if(commandLineArgs.count("rotate") > 0) runRotate = commandLineArgs["rotate"].as<bool>();
    if(commandLineArgs.count("select") > 0) runSelect = commandLineArgs["select"].as<bool>();

    // Some random data ...
    void *hMem = memalign(axiDataWidth, size);
    for(int i = 0; i < size / 8; i++) {
        ((uint64_t*) hMem)[i] = rand();
    }

    // 
    // Open a UDS and sent a task request
    // This is the only place of interaction needed with Coyote daemon !!!
    // 
    cLib clib("/tmp/coyote-daemon-vfid-0");

    // Addmul operator
    if(runAddMul) std::cout << "Task AddMul completed, code: " << clib.task({opIdAddMul, {(uint64_t) hMem, (uint64_t) size, (uint64_t) defAdd, (uint64_t) defMul}}) << std::endl;

    // Statistics on the data, returns maximum
    if(runMinMax) std::cout << "Task MinMax completed, code (max val): " << clib.task({opIdMinMax, {(uint64_t) hMem, (uint64_t) size}}) << std::endl;

    // Rotation 
    if(runRotate) std::cout << "Task Rotate completed, code: " << clib.task({opIdRotate, {(uint64_t) hMem, (uint64_t) size}}) << std::endl;

    // Select count, returns count
    if(runSelect) std::cout << "Task Select completed, code (select count): " << clib.task({opIdSelect, {(uint64_t) hMem, (uint64_t) size, (uint64_t) defType, (uint64_t) defPredicate}}) << std::endl;

    return (EXIT_SUCCESS);
}
