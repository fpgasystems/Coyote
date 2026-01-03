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

#include <cmath>
#include <random>

#include <boost/program_options.hpp>

#include <coyote/cConn.hpp>
#include "constants.hpp"

int main(int argc, char *argv[]) {
    // CLI arguments
    size_t size;
    uint operation;

    boost::program_options::options_description runtime_options("Coyote Vector Similarity/Distance Options");
    runtime_options.add_options()
        ("size,s", boost::program_options::value<size_t>(&size)->default_value(1024), "Vector size")
        ("operation,o", boost::program_options::value<uint>(&operation)->default_value(0), "Operation: Euclidean distance (0) or cosine similarity (1)");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    if (operation) {
        HEADER("PR example: vector Euclidean distance"); 
        std::cout << "Vector elements: " << size << std::endl;       
    } else {
        HEADER("PR example: vector cosine similarity"); 
        std::cout << "Vector elements: " << size << std::endl;       
    }

    // Allocate memory for the two vectors and the result; note we are not using the Coyote memory allocator here, but rather the standard aligned_alloc function
    float *a = (float *) aligned_alloc(coyote::PAGE_SIZE, size * (uint) sizeof(float));
    float *b = (float *) aligned_alloc(coyote::PAGE_SIZE, size * (uint) sizeof(float));
    float *c = (float *) aligned_alloc(coyote::PAGE_SIZE, sizeof(float));

    // Set vectors to random values and result to 0
    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_real_distribution<float> dis(-512.0, 512.0); 
    for (int i = 0; i < size; i++) {
        a[i] = dis(gen);    
        b[i] = dis(gen);               
    }
    c[0] = 0;      

    /*
     * Connect to the Coyote daemon
     * The following two lines are the only place of interaction with Coyote in the client code; the rest is standard C++ code
     * 
     * Note how the daemon name is derived from the name specified (pr-example) in the server code
     */
    coyote::cConn conn("/tmp/coyote-daemon-dev-0-vfid-0-pr-example"); 

    /** 
     * Submit task to the background daemon and wait until completed; returns the time taken
     * The first parameter is the operation to perform (0 for Euclidean distance, 1 for cosine similarity)
     * The next three parameters are the pointers to the input vectors (a, b) and note how the other
     * parameters (and the function template) matches the function signature defined in the server code
     * The function returns a float, the time it takes to execute the operation in microseconds as measured by the Coyote daemon
     */
    float time = conn.task<float, uint64_t, uint64_t, uint64_t, size_t>(operation, (uint64_t) a, (uint64_t) b, (uint64_t) c, size);

    // Compare the result with the expected value
    // Note how the result is stored in the vector c, just like with other Coyote examples, 
    // where a data buffer was used with the invoke(...) function
    float expected = 0;
    if (operation) {
        // Cosine similarity
        float norm_a = 0;
        float norm_b = 0;
        for (int i = 0; i < size; i++) {
            expected += a[i] * b[i];
            norm_a += a[i] * a[i];
            norm_b += b[i] * b[i];
        }
        expected = expected / (std::sqrt(norm_a) * std::sqrt(norm_b));
    } else {
        // Euclidean distance   
        for (int i = 0; i < size; i++) {
            expected += (a[i] - b[i]) * (a[i] - b[i]);
        }
        expected = std::sqrt(expected);
    }

    // The result is stored in the first element of the result vector (c)
    assert(std::fabs(c[0] - expected) < 1e-3);
    std::cout << "Validation passed; result: " << c[0] << std::endl;
    std::cout << "Time taken: " << time << " us" << std::endl;
    
    // Release the dynamically allocated memory
    free(a);
    free(b);
    free(c);
    
    return EXIT_SUCCESS;
}
