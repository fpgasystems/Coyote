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

#include <any>
#include <iostream>

// External library for easier parsing of CLI arguments by the executable
#include <boost/program_options.hpp>

// Coyote-specific includes
#include "cBench.hpp"
#include "cThread.hpp"

// Default vFPGA to assign cThread to
#define DEFAULT_VFPGA_ID 0

double run_bench(
   coyote::cThread &coyote_thread, uint32_t *src_mem, float *dst_mem, 
   coyote::localSg src_sg, coyote::localSg dst_sg, uint n_runs
) {
    // Initialise helper benchmarking class
    // Used for keeping track of execution times & some helper functions (mean, P25, P75 etc.)
    coyote::cBench bench(n_runs);
    
    // Randomly set the source data; initialise destination memory to 0
    for(int i = 0; i < src_sg.len / sizeof(uint32_t); i++) {
        src_mem[i] = i;
    }
    dst_mem[0] = 0;

    // Function called before every iteration of the benchmark, can be used to clear previous flags, states etc.
    auto prep_fn = [&] {
        // Clear the completion counters, so that the test can be repeated multiple times independently
        // Essentially, sets the result from the function checkCompleted(...) to zero
        coyote_thread.clearCompleted();
    };

    // Execute benchmark
    auto bench_fn = [&]() {
        // Invoke kernel, data flow is host => HLL vFPGA => vFPGA
        coyote_thread.invoke(coyote::CoyoteOper::LOCAL_TRANSFER, src_sg, dst_sg);
    
        // Wait until completed
        while (!coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_TRANSFER)) {}
    };

    bench.execute(bench_fn, prep_fn);
    std::cout << "Estimated cardinality: " << dst_mem[0] << std::endl;

    // Return average throughput
    std::vector<double> latencies = bench.getAll();
    double tmp = 0;
    double sum = 0;    
    for (auto t: latencies) {
        tmp = ((double) src_sg.len) / (1024.0 * 1024.0 * 1e-9 * t);
        sum += tmp;
    }
    double throughput = sum / (double) latencies.size();     
    return throughput;
}

int main(int argc, char *argv[]) {
    // CLI
    unsigned int n_runs, min_size, max_size;

    boost::program_options::options_description runtime_options("Coyote HyperLogLog Cardinality Estimation Example");
    runtime_options.add_options()
        ("runs,r", boost::program_options::value<unsigned int>(&n_runs)->default_value(50), "Number of times to repeat the test")
        ("min_size,x", boost::program_options::value<unsigned int>(&min_size)->default_value(64), "Starting (minimum) transfer size")
        ("max_size,X", boost::program_options::value<unsigned int>(&max_size)->default_value(4 * 1024 * 1024), "Ending (maximum) transfer size");
    
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    HEADER("CLI ARGUMENTS:");
    std::cout << "Starting transfer size: " << min_size << std::endl;
    std::cout << "Ending transfer size: " << max_size << std::endl << std::endl;
    std::cout << "Number of reps: " << n_runs << std::endl;

    // Create Coyote thread
    coyote::cThread coyote_thread(DEFAULT_VFPGA_ID, getpid());
    
    // Allocated memory for the source and destination buffers
    uint32_t* src_mem = (uint32_t*) coyote_thread.getMem({coyote::CoyoteAllocType::HPF, max_size});
    float* dst_mem = (float*) coyote_thread.getMem({coyote::CoyoteAllocType::REG, sizeof(float)});

    // Initialises a Scatter-Gather (SG) entry 
    // SG entries are used in DMA operations to describe source & dest memory buffers, their addresses, sizes etc.
    coyote::localSg src_sg = { .addr = src_mem };
    coyote::localSg dst_sg = { .addr = dst_mem, .len = sizeof(float) };

    HEADER("HLL CARDINALITY ESTIMATION");
    unsigned int curr_size = min_size;
    while(curr_size <= max_size) {
        // Set transfer size and run benchmark
        src_sg.len = curr_size; 
        double throughput = run_bench(coyote_thread, src_mem, dst_mem, src_sg, dst_sg, n_runs);
        std::cout << "Size: " << curr_size << "; Average throughput: " << throughput << " MB/s; " << std::endl;
        
        // Update size and proceed to next iteration of the experiment
        curr_size *= 2;
    }

    return EXIT_SUCCESS;
}

