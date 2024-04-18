/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
  * All rights reserved.
  *
  * Redistribution and use in source and binary forms, with or without modification,
  * are permitted provided that the following conditions are met:
  *
  * 1. Redistributions of source code must retain the above copyright notice,
  * this list of conditions and the following disclaimer.
  * 2. Redistributions in binary form must reproduce the above copyright notice,
  * this list of conditions and the following disclaimer in the documentation
  * and/or other materials provided with the distribution.
  * 3. Neither the name of the copyright holder nor the names of its contributors
  * may be used to endorse or promote products derived from this software
  * without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  */

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
#include <signal.h> 
#include <boost/program_options.hpp>


#include "cRnfg.hpp"

using namespace std;
using namespace std::chrono;
using namespace fpga;

/* Def params */
constexpr auto const defDevice = 0;

/**
 * @brief Loopback example
 * 
 */
int main(int argc, char *argv[])  
{
    // ---------------------------------------------------------------
    // Args 
    // ---------------------------------------------------------------

    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options()
        ("device,d", boost::program_options::value<uint32_t>(), "Target device")
        ("bpath,b", boost::program_options::value<string>(), "Bitstream path (.bin)");
    
    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    uint32_t cs_dev = defDevice; 

    if(commandLineArgs.count("device") > 0) cs_dev = commandLineArgs["device"].as<uint32_t>();

    try {
        string b_path;

        if(commandLineArgs.count("bpath") == 0) 
            throw std::runtime_error("ERR:   Bitstream path not provided!\n");
        else
            b_path = commandLineArgs["bpath"].as<string>();
    

        // Reconfigure
        cRnfg crnfg(cs_dev);

        std::cout << "Reconfiguring the shell ... " << std::endl;
        std::cout << "Shell path: " << b_path << std::endl;
        
        auto begin_time = std::chrono::high_resolution_clock::now();
        
        crnfg.shellReconfigure(b_path);

        auto end_time = std::chrono::high_resolution_clock::now();
        double time = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - begin_time).count();
        
        std::cout << "Shell loaded" << std::endl;

    }
    catch( const std::exception & ex ) {
        std::cerr << std::endl << ex.what() << std::endl;
    }
    
    return EXIT_SUCCESS;
}
