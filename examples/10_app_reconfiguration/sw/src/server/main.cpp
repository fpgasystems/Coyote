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

#include <chrono>

#include <coyote/cOps.hpp>
#include <coyote/cFunc.hpp>
#include <coyote/cThread.hpp>
#include <coyote/cService.hpp>

#include "constants.hpp"  

int main(int argc, char *argv[]) {
    // Creates an instance of a background Coyote service that can host multiple functions
    coyote::cService *cservice = coyote::cService::getInstance("pr-example", false, DEFAULT_VFPGA_ID, DEFAULT_DEVICE);
    
    // Create an instance of a Coyote bFunc, which can be defined to execute arbitrary code withing Coyote
    // For each function, three variables need to be specified:
    // 1. A unique function ID, in this case OP_EUCLIDEAN_DISTANCE
    // 2. The path to the partial application bitstream, which is loaded dynamically when the function is executed
    // 3. A lambda function that takes the Coyote thread and the function parameters, specifying how the function is executed on the vFPGA 
    // In this case, the function calculates the Euclidean distance between two vectors of floats, given their memory addresses and size
    // Finally, the function returns a float, which corresponds to the time taken to execute the function
    std::unique_ptr<coyote::bFunc> euclidean_distance_fn(new coyote::cFunc<float, uint64_t, uint64_t, uint64_t, size_t>(
        OP_EUCLIDEAN_DISTANCE, "app_euclidean_distance.bin",
        [=] (coyote::cThread *coyote_thread, uint64_t ptr_a, uint64_t ptr_b, uint64_t ptr_c, size_t size) -> float {
            syslog(
                LOG_NOTICE, 
                "Calculating Euclidean distance, params: a %lx, b %lx, c %lx, size %ld", 
                ptr_a, ptr_b, ptr_c, size
            );
            auto begin_time = std::chrono::high_resolution_clock::now();

            // Cast uint64_t (corresponding to a memory address) to float pointers
            // Note, how there is no memory allocation in this function - these memories are allocated by the client
            // and passed to the function as memory addresses (pointers)
            float *a = (float *) ptr_a;
            float *b = (float *) ptr_b;
            float *c = (float *) ptr_c;
            
            // The buffers a, b, and c are not owned by this process; therefore they must be mapped to the vFPGA's memory
            // This can be done automatically by Coyote, when it detects page fault on the buffers (similar to Example 1 
            // with card memory). Alternatively, the user can explicitly map the memory buffers to the vFPGA's memory as below.
            // coyote_thread->userMap(a, size * (uint) sizeof(float));

            // Run the Euclidean distance operator on the vFPGA; similar to HLS Vector Addition from Example 2
            coyote::localSg sg_a = {.addr = a, .len = (uint) (size * sizeof(float)), .dest = 0};
            coyote::localSg sg_b = {.addr = b, .len = (uint) (size * sizeof(float)), .dest = 1};
            coyote::localSg sg_c = {.addr = c, .len = sizeof(float), .dest = 0};
            
            coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ,  sg_a);
            coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ,  sg_b);
            coyote_thread->invoke(coyote::CoyoteOper::LOCAL_WRITE, sg_c);
            while (
                coyote_thread->checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != 1 || 
                coyote_thread->checkCompleted(coyote::CoyoteOper::LOCAL_READ) != 2
            ) {}
            
            // Same as above; the memory addresses can be explicitly unmapped, but this is not necessary
            // If left out, the Coyote thread will automatically unmap the memory when it is no longer needed
            // coyote_thread->userUnmap(a);
            
            // IMPORTANT: The Coyote thread must clear comletion counter after the function execution.
            // The client - service set-up is such that there is a unique Coyote thread for each client
            // However, if a client submits multiple tasks, the Coyote completion counters will just accumulate
            // Therefore, for subsequent client tasks, these must be cleared.
            coyote_thread->clearCompleted();

            auto end_time = std::chrono::high_resolution_clock::now();
            double time = std::chrono::duration_cast<std::chrono::microseconds>(end_time - begin_time).count();
            syslog(LOG_NOTICE, "Euclidean distance calculated, time taken %f us", time);
            return time;
        }
    ));
    
    // Register the function with the service
    if (cservice->addFunction(std::move(euclidean_distance_fn))) {
        std::cerr << "Failed to register function; double check the function ID and bitstream path; see syslog for any errors." << std::endl;
        return EXIT_FAILURE;
    }

    // Repeat the same for the cosine similarity function
    // These two code blocks could probably be unified, but for the sake of clarity, they are kept separate
    std::unique_ptr<coyote::bFunc> cosine_similarity_fn(new coyote::cFunc<float, uint64_t, uint64_t, uint64_t, size_t>(
        OP_COSINE_SIMILARITY, "app_cosine_similarity.bin",
        [=] (coyote::cThread *coyote_thread, uint64_t ptr_a, uint64_t ptr_b, uint64_t ptr_c, size_t size) -> float {
            syslog(
                LOG_NOTICE, 
                "Calculating cosine similarity, params: a %lx, b %lx, c %lx, size %ld", 
                ptr_a, ptr_b, ptr_c, size
            );
            auto begin_time = std::chrono::high_resolution_clock::now();

            float *a = (float *) ptr_a;
            float *b = (float *) ptr_b;
            float *c = (float *) ptr_c;
            
            coyote::localSg sg_a = {.addr = a, .len = (uint) (size * sizeof(float)), .dest = 0};
            coyote::localSg sg_b = {.addr = b, .len = (uint) (size * sizeof(float)), .dest = 1};
            coyote::localSg sg_c = {.addr = c, .len = sizeof(float), .dest = 0};
            
            coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ,  sg_a);
            coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ,  sg_b);
            coyote_thread->invoke(coyote::CoyoteOper::LOCAL_WRITE, sg_c);
            while (
                coyote_thread->checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != 1 || 
                coyote_thread->checkCompleted(coyote::CoyoteOper::LOCAL_READ) != 2
            ) {}
            coyote_thread->clearCompleted();

            auto end_time = std::chrono::high_resolution_clock::now();
            double time = std::chrono::duration_cast<std::chrono::microseconds>(end_time - begin_time).count();
            syslog(LOG_NOTICE, "Cosine similarity calculated, time taken %f us", time);
            return time;
        }
    ));

    if (cservice->addFunction(std::move(cosine_similarity_fn)))  {
        std::cerr << "Failed to register function; double check the function ID and the bitstream path; see syslog for any errors." << std::endl;
        return EXIT_FAILURE;
    }

    // Start the background service; this will start a daemon that listens for client connections
    // and processes requests from clients. Generally, all functions should be registered before
    // starting the service. While the background service can accept new functions after it 
    // has started,unpredictable bugs with reconfiguration memory mapping have been observed in the past.
    std::cout << "Starting background daemon ..." << std::endl;
    cservice->start();

}
