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
constexpr auto const defType = 2;
constexpr auto const defPredicate = 20;

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
    bool runRotate = defRotate;
    bool runSelect = defSelect;

    if(commandLineArgs.count("size") > 0) size = commandLineArgs["size"].as<uint32_t>();
    if(commandLineArgs.count("addmul") > 0) runAddMul = commandLineArgs["addmul"].as<bool>();
    if(commandLineArgs.count("minmax") > 0) runMinMax = commandLineArgs["minmax"].as<bool>();
    if(commandLineArgs.count("rotate") > 0) runRotate = commandLineArgs["rotate"].as<bool>();
    if(commandLineArgs.count("select") > 0) runSelect = commandLineArgs["select"].as<bool>();

    // Some random data ...
    void *hMem = memalign(axiDataWidth, size);

    // 
    // Open a UDS and sent a task request
    // This is the only place of interaction needed with Coyote daemon !!!
    // 
    cLib clib("/tmp/coyote-daemon-vfid-0");

    int32_t ret_code;
    bool k;

    //
    // Addmul operator
    //
    if(runAddMul) {
        // Dummy data
        for(int i = 0; i < size / 16; i++) {
            ((uint32_t*) hMem)[i] = i;
        }

        // Task
        ret_code = clib.task({opIdAddMul, {(uint64_t) hMem, (uint64_t) size, (uint64_t) defMul, (uint64_t) defAdd}});

        // Check results
        k = true;
        for(int i = 0; i < size / 16; i++) {
            if( ((uint32_t*) hMem)[i] != (i << defMul) + defAdd ) k = false;
        }

        std::cout << "Task completed: addmul, " << (k ? "results correct" : "results incorrect") << std::endl;
    } 

    //
    // Statistics on the data, returns maximum
    //
    if(runMinMax) {
        // Dummy data
        for(int i = 0; i < size / 16; i++) {
            ((uint32_t*) hMem)[i] = i;
        }

        // Task
        ret_code = clib.task({opIdMinMax, {(uint64_t) hMem, (uint64_t) size}});

        // Check results
        k = (ret_code == size/16 -1);
        
        std::cout << "Task completed: minmax, " << (k ? "results correct" : "results incorrect") << std::endl;
    }
        
    //
    // Rotation 
    //
    if(runRotate) {
        // Dummy data
        for(int i = 0; i < size / 16; i++) {
            ((uint32_t*) hMem)[i] = i;
        }

        // Task
        clib.task({opIdRotate, {(uint64_t) hMem, (uint64_t) size}});

        // Check results
        k = true;
        for(int i = 0; i < size / 16; i++) {
            uint32_t tmp_val = ((uint32_t*) hMem)[i];
            if((tmp_val & 0xff) != (i >> 24)) k = false;
            if(((tmp_val >> 8) & 0xff) != (i & 0xff)) k = false;
            if(((tmp_val >> 16) & 0xff) != ((i >> 8) & 0xff)) k = false;
            if(((tmp_val >> 24) & 0xff) != ((i >> 16) & 0xff)) k = false;
        }

        std::cout << "Task completed: rotate, " << (k ? "results correct" : "results incorrect") << std::endl;
    }

    //
    // Select count, returns count
    //
    if(runSelect) {
        // Dummy data
        for(int i = 0; i < size / 16; i++) {
            ((uint32_t*) hMem)[i] = i;
        }

        // Task
        clib.task({opIdSelect, {(uint64_t) hMem, (uint64_t) size, (uint64_t) defType, (uint64_t) defPredicate}});

        // Check results
        k = (ret_code == defPredicate);

        std::cout << "Task completed: select count, " << (k ? "results correct" : "results incorrect") << std::endl;
    }

    return (EXIT_SUCCESS);
}
