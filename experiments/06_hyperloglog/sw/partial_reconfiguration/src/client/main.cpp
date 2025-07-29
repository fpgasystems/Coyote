/*
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

#include <boost/program_options.hpp>

#include "cConn.hpp"

int main(int argc, char *argv[]) {
    // CLI arguments
    size_t size;

    boost::program_options::options_description runtime_options("HyperLogLog client options");
    runtime_options.add_options()
        ("size,s", boost::program_options::value<size_t>(&size)->default_value(1024), "HyperLogLog size [B]");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    // Allocate memory for the two vectors and the result; note we are not using the Coyote memory allocator here, but rather the standard aligned_alloc function
    uint32_t *input = (uint32_t *) aligned_alloc(coyote::PAGE_SIZE, size);
    float *result = (float *) aligned_alloc(coyote::PAGE_SIZE, sizeof(float));

    // Initialize values
    for(int i = 0; i < size / sizeof(uint32_t); i++) {
        input[i] = i;
    }
    result[0] = 0;      

    /*
     * Connect to the Coyote daemon
     * The following two lines are the only place of interaction with Coyote in the client code; the rest is standard C++ code
     * 
     * Note how the daemon name is derived from the name specified (hyperloglog) in the server code
     */
    coyote::cConn conn("/tmp/coyote-daemon-dev-0-vfid-0-hyperloglog"); 

    /** 
     * Submit task to the background daemon and wait until completed; returns the time taken
     * The first parameter is the operation to perform (since we only defined one op, HyperLogLog, set to 0)
     * The next three parameters are the pointers to the input vectors (a, b) and note how the other
     * parameters (and the function template) matches the function signature defined in the server code
     * The function returns a float, the time it takes to execute the operation in microseconds as measured by the Coyote daemon
     */
    float time = conn.task<float, uint64_t, uint64_t, size_t>(0, (uint64_t) input, (uint64_t) result, size);

    std::cout << "Time taken: " << time << " us, calculated cardinality: " << result[0] << std::endl;
    
    // Release the dynamically allocated memory
    free(input);
    free(result);
    
    return EXIT_SUCCESS;
}
