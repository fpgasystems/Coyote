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

#include <chrono>
#include <string>

#include "cOps.hpp"
#include "cFunc.hpp"
#include "cThread.hpp"
#include "cService.hpp"

#include <boost/program_options.hpp>

// Constants
#define DEFAULT_VFPGA_ID 0
#define DEFAULT_DEVICE 0

int main(int argc, char *argv[]) {
    std::string bitstream_path;

    boost::program_options::options_description runtime_options("HyperLogLog client options");
    runtime_options.add_options()
        ("bitstream,b", boost::program_options::value<std::string>(&bitstream_path), "Path to partial app bitstream");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    // Creates an instance of a background Coyote service that can host multiple functions
    coyote::cService *cservice = coyote::cService::getInstance("hyperloglog", false, DEFAULT_VFPGA_ID, DEFAULT_DEVICE);
    
    // Create an instance of a Coyote bFunc, which can be defined to execute arbitrary code withing Coyote
    // For each function, three variables need to be specified:
    // 1. A unique function ID, in this case 0, since there is only one function (HyperLogLog)
    // 2. The path to the partial application bitstream, which is loaded dynamically when the function is executed
    // 3. A lambda function that takes the Coyote thread and the function parameters, specifying how the function is executed on the vFPGA 
    // In this case, the function does HyperLogLog cardinality estimation, given a buffer memory addresses and its size
    // Finally, the function returns a float, which corresponds to the time taken to execute the function
    std::unique_ptr<coyote::bFunc> hll_fn(new coyote::cFunc<float, uint64_t, uint64_t, size_t>(
        0, bitstream_path,
        [=] (coyote::cThread *coyote_thread, uint64_t ptr_input, uint64_t ptr_result, size_t size) -> float {
            syslog(
                LOG_NOTICE, 
                "Starting HyperLogLog cardinality estimation, params: ptr_input %lx, ptr_input %lx, size %ld", 
                ptr_input, ptr_input, size
            );
            auto begin_time = std::chrono::high_resolution_clock::now();

            // Cast uint64_t (corresponding to a memory address) to float pointers
            // Note, how there is no memory allocation in this function - these memories are allocated by the client
            // and passed to the function as memory addresses (pointers)
            uint32_t *input = (uint32_t *) ptr_input;
            float *results = (float *) ptr_result;
            
            // Run the Euclidean distance operator on the vFPGA; similar to HLS Vector Addition from Example 2
            coyote::localSg src_sg = { .addr = input, .len = size };
            coyote::localSg dst_sg = { .addr = results, .len = sizeof(float) };

            // Invoke kernel, data flow is host => HLL vFPGA => vFPGA
            coyote_thread->invoke(coyote::CoyoteOper::LOCAL_TRANSFER, src_sg, dst_sg);
    
            // Wait until completed
            while (!coyote_thread->checkCompleted(coyote::CoyoteOper::LOCAL_TRANSFER)) {}


            // IMPORTANT: The Coyote thread must clear completion counter after the function execution.
            // The client - service set-up is such that there is a unique Coyote thread for each client
            // However, if a client submits multiple tasks, the Coyote completion counters will just accumulate
            // Therefore, for subsequent client tasks, these must be cleared.
            coyote_thread->clearCompleted();

            auto end_time = std::chrono::high_resolution_clock::now();
            double time = std::chrono::duration_cast<std::chrono::microseconds>(end_time - begin_time).count();
            syslog(LOG_NOTICE, "HyperLogLog cardinality completed, time taken %f us", time);
            return time;
        }
    ));
    
    // Register the function with the service
    if (cservice->addFunction(std::move(hll_fn))) {
        std::cerr << "Failed to register function; double check the function ID and bitstream path; see syslog for any errors." << std::endl;
        return EXIT_FAILURE;
    }

    // Start the background service; this will start a daemon that listens for client connections
    // and processes requests from clients. Generally, all functions should be registered before
    // starting the service. While the background service can accept new functions after it 
    // has started,unpredictable bugs with reconfiguration memory mapping have been observed in the past.
    std::cout << "Starting background daemon ..." << std::endl;
    cservice->start();

}
