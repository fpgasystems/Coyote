/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <random>
#include <iostream>

// External library for easier parsing of CLI arguments by the executable
#include <boost/program_options.hpp>

// Coyote-specific includes
#include <coyote/cThread.hpp>

// Default vFPGA to assign cThreads to
#define DEFAULT_VFPGA_ID 0

int main(int argc, char *argv[]) {
    // CLI arguments
    uint size;
    boost::program_options::options_description runtime_options("Coyote HLS Vector Add Options");
    runtime_options.add_options()("size,s", boost::program_options::value<uint>(&size)->default_value(1024), "Vector size");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    HEADER("Validation: HLS vector addition");
    std::cout << "Vector elements: " << size << std::endl;
    
    // Create a Coyote thread and allocate memory for the vectors
    coyote::cThread coyote_thread(DEFAULT_VFPGA_ID, getpid());
    float *a = (float *) coyote_thread.getMem({coyote::CoyoteAllocType::HPF, size * (uint) sizeof(float) });
    float *b = (float *) coyote_thread.getMem({coyote::CoyoteAllocType::HPF, size * (uint) sizeof(float) });
    float *c = (float *) coyote_thread.getMem({coyote::CoyoteAllocType::HPF, size * (uint) sizeof(float) });
    if (!a || !b || !c) { throw std::runtime_error("Could not allocate memory for vectors, exiting..."); }

    // Initialise the input vectors to a random value between -512 and 512 (these are just arbitrary, any 32-bit FP number will work)
    // Also, initialise resulting vector to 0 (though this really doesn't matter; it will be overwritten by the FPGA)
    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_real_distribution<float> dis(-512.0, 512.0); 
    for (int i = 0; i < size; i++) {
        a[i] = dis(gen);    
        b[i] = dis(gen);
        c[i] = 0;                        
    }
    
    // Set scatter-gather flags; note transfer size is always in bytes, so multiply vector dimensionality with sizeof(float)
    // Note, how the vector b has a destination of 1; corresponding to the second AXI Stream (see README for more details)
    coyote::localSg sg_a = {.addr = a, .len = size * (uint) sizeof(float), .dest = 0};
    coyote::localSg sg_b = {.addr = b, .len = size * (uint) sizeof(float), .dest = 1};
    coyote::localSg sg_c = {.addr = c, .len = size * (uint) sizeof(float), .dest = 0};

    // Run kernel and wait until complete
    coyote_thread.invoke(coyote::CoyoteOper::LOCAL_READ,  sg_a);
    coyote_thread.invoke(coyote::CoyoteOper::LOCAL_READ,  sg_b);
    coyote_thread.invoke(coyote::CoyoteOper::LOCAL_WRITE, sg_c);
    while (
        coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != 1 || 
        coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_READ) != 2
    ) {}

    // Verify correctness of the results
    for (int i = 0; i < size; i++) { assert((a[i] + b[i]) == c[i]); }
    HEADER("Validation passed!");
}
