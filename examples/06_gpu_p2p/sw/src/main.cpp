/**
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

#include <iostream>
#include <cstdlib>

// AMD GPU management & run-time libraries
#include <hip/hip_runtime.h>

// External library for easier parsing of CLI arguments by the executable
#include <boost/program_options.hpp>

// Coyote-specific includes
#include <coyote/cBench.hpp>
#include <coyote/cThread.hpp>

// Constants
#define N_LATENCY_REPS 1
#define N_THROUGHPUT_REPS 32

#define DEFAULT_GPU_ID 0
#define DEFAULT_VFPGA_ID 0

// Note, how the Coyote thread is passed by reference; to avoid creating a copy of 
// the thread object which can lead to undefined behaviour and bugs. 
double run_bench(
    coyote::cThread &coyote_thread, coyote::localSg &src_sg, coyote::localSg &dst_sg, 
    int *src_mem, int *dst_mem, uint transfers, uint n_runs
) {
    // Initialise helper benchmarking class
    // Used for keeping track of execution times & some helper functions (mean, P25, P75 etc.)
    coyote::cBench bench(n_runs);
    
    // Randomly set the source data between -512 and +512; initialise destination memory to 0
    assert(src_sg.len == dst_sg.len);
    for (int i = 0; i < src_sg.len / sizeof(int); i++) {
        src_mem[i] = rand() % 1024 - 512;     
        dst_mem[i] = 0;                        
    }

    // Function called before every iteration of the benchmark, can be used to clear previous flags, states etc.
    auto prep_fn = [&]() {
        // Clear the completion counters, so that the test can be repeated multiple times independently
        // Essentially, sets the result from the function checkCompleted(...) to zero
        coyote_thread.clearCompleted();
    };

    // Execute benchmark
    auto bench_fn = [&]() {
        // Launch (queue) multiple transfers in parallel for throughput tests, or 1 in case of latency tests
        // Recall, coyote_thread->invoke is asynchronous (can be made sync through different sgFlags)
        for (int i = 0; i < transfers; i++) {
            coyote_thread.invoke(coyote::CoyoteOper::LOCAL_TRANSFER, src_sg, dst_sg);
        }

        // Wait until all of them are finished
        while (coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_TRANSFER) != transfers) {}
    };

    bench.execute(bench_fn, prep_fn);
    
    // Make sure destination matches the source + 1 (the vFPGA logic in perf_local adds 1 to every 32-bit element, i.e. integer)
    for (int i = 0; i < src_sg.len / sizeof(int); i++) {
        assert(src_mem[i] + 1 == dst_mem[i]); 
    }

    // Return average time taken for the data transfer
    return bench.getAvg();
}

int main(int argc, char *argv[])  {
    // CLI arguments
    unsigned int min_size, max_size, n_runs;
    boost::program_options::options_description runtime_options("Coyote Perf GPU Options");
    runtime_options.add_options()
        ("runs,r", boost::program_options::value<unsigned int>(&n_runs)->default_value(50), "Number of times to repeat the test")
        ("min_size,x", boost::program_options::value<unsigned int>(&min_size)->default_value(64), "Starting (minimum) transfer size")
        ("max_size,X", boost::program_options::value<unsigned int>(&max_size)->default_value(4 * 1024 * 1024), "Ending (maximum) transfer size");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    HEADER("CLI PARAMETERS:");
    std::cout << "Number of test runs: " << n_runs << std::endl;
    std::cout << "Starting transfer size: " << min_size << std::endl;
    std::cout << "Ending transfer size: " << max_size << std::endl << std::endl;

    // GPU memory will be allocated on the GPU set using hipSetDevice(...)
    if (hipSetDevice(DEFAULT_GPU_ID)) { throw std::runtime_error("Couldn't select GPU!"); }

    // Obtain a Coyote thread and allocate memory
    // Note, the only difference from Example 1 is the way memory is allocated
    coyote::cThread coyote_thread(DEFAULT_VFPGA_ID, getpid());
    int *src_mem = (int *) coyote_thread.getMem({coyote::CoyoteAllocType::GPU, max_size, false, DEFAULT_GPU_ID});
    int *dst_mem = (int *) coyote_thread.getMem({coyote::CoyoteAllocType::GPU, max_size, false, DEFAULT_GPU_ID});
    if (!src_mem || !dst_mem) { throw std::runtime_error("Could not allocate memory; exiting..."); }

    // Scatter-Gather (SG) entries
    coyote::localSg src_sg = { .addr = src_mem };
    coyote::localSg dst_sg = { .addr = dst_mem };
    
    HEADER("PERF GPU");
    unsigned int curr_size = min_size;
    while(curr_size <= max_size) {
        // Update SG size entry
        std::cout << "Size: " << std::setw(8) << curr_size << "; ";
        src_sg.len = curr_size; dst_sg.len = curr_size; 

        // Run throughput test
        double throughput_time = run_bench(coyote_thread, src_sg, dst_sg, src_mem, dst_mem, N_THROUGHPUT_REPS, n_runs);
        double throughput = ((double) N_THROUGHPUT_REPS * (double) curr_size) / (1024.0 * 1024.0 * throughput_time * 1e-9);
        std::cout << "Average throughput: " << std::setw(8) << throughput << " MB/s; ";
        
        // Run latency test
        double latency_time = run_bench(coyote_thread, src_sg, dst_sg, src_mem, dst_mem, N_LATENCY_REPS, n_runs);
        std::cout << "Average latency: " << std::setw(8) << latency_time / 1e3 << " us" << std::endl;

        // Update size and proceed to next iteration
        curr_size *= 2;
    }

    // Note, how there is no memory de-allocation, since the memory was allocated using coyote_thread->getMem(...)
    // A Coyote thread always keeps track of the memory it allocated and internally handles de-allocation
    return EXIT_SUCCESS;
}
