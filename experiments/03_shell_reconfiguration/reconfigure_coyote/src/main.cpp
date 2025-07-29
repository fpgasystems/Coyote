/*
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <string>
#include <iostream>

// External library, Boost, for easier parsing of CLI arguments to the binary
#include <boost/program_options.hpp>

// Coyote-specific includes
#include "cThread.hpp"
#include "cRcnfg.hpp"

// Default (physical) FPGA device for nodes with multiple FPGAs
#define DEFAULT_DEVICE 0

// Default vFPGA to assign cThreads to
#define DEFAULT_VFPGA_ID 0

int main(int argc, char *argv[])  {
    std::string bitstream_path;
    boost::program_options::options_description runtime_options("Coyote Reconfigure Shell Options");
    runtime_options.add_options()
        ("bitstream,b", boost::program_options::value<std::string>(&bitstream_path)->required(), "Path to partial shell bitstream (.bin)");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    try {
        // To reconfigure, we need to create an instance of cRnfg for the target (physical) FPGA device
        coyote::cRcnfg crnfg(DEFAULT_DEVICE);
        std::cout << "Reconfiguring the shell with bitstream: " << bitstream_path << std::endl;
        
        // Then, trigger shell reconfiguration
        auto begin_time = std::chrono::high_resolution_clock::now();
        crnfg.reconfigureShell(bitstream_path);
        auto end_time = std::chrono::high_resolution_clock::now();

        double time = std::chrono::duration_cast<std::chrono::microseconds>(end_time - begin_time).count();
        std::cout << "Shell loaded in " << time / 1000.0 << " milliseconds" << std::endl << std::endl;

    } catch(const std::exception &e) {
        std::cerr << std::endl << e.what() << std::endl;
        return EXIT_FAILURE;
    }
    
    return EXIT_SUCCESS;
}
