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

#include <cstdlib>
#include <iostream>

// External library for easier parsing of CLI arguments by the executable
#include <boost/program_options.hpp>

// Coyote-specific includes
#include <coyote/cBench.hpp>
#include <coyote/cThread.hpp>

// Constants
#define N_LATENCY_REPS 1
#define N_THROUGHPUT_REPS 32

// Default vFPGA to assign cThreads to; for designs with one region (vFPGA) this is the only possible value
#define DEFAULT_VFPGA_ID 0

// Note, how the Coyote thread is passed by reference; to avoid creating a copy of 
// the thread object which can lead to undefined behaviour and bugs. 
double run_bench(
    coyote::cThread &coyote_thread, coyote::localSg &src_sg, coyote::localSg &dst_sg, 
    int *src_mem, int *dst_mem, uint transfers, uint n_runs, bool sync_back
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

        // Wait until all of them are finished; short sleep to avoid busy-waiting
        while (coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_TRANSFER) != transfers) {}
    };

    bench.execute(bench_fn, prep_fn);
    
    // Sync data back, if required (stream == CARD)
    if (sync_back) {
        coyote::syncSg sg_sync;
        sg_sync = {.addr = src_mem, .len = src_sg.len }; 
        coyote_thread.invoke(coyote::CoyoteOper::LOCAL_SYNC, sg_sync);

        sg_sync = {.addr = dst_mem, .len = dst_sg.len }; 
        coyote_thread.invoke(coyote::CoyoteOper::LOCAL_SYNC, sg_sync);
    }

    // Make sure destination matches the source + 1 (the vFPGA logic in perf_local adds 1 to every 32-bit element, i.e. integer)
    for (int i = 0; i < src_sg.len / sizeof(int); i++) {
        assert(src_mem[i] + 1 == dst_mem[i]); 
    }

    // Return average time taken for the data transfer
    return bench.getAvg();
}

int main(int argc, char *argv[])  {
    // Run-time options; for more details see the description below
    bool hugepages, mapped, stream;
    unsigned int min_size, max_size, n_runs;

    // Parse CLI arguments using Boost, an external library, providing easy parsing of run-time parameters
    // We can easily set the variable type, the variable used for storing the parameter and default values
    boost::program_options::options_description runtime_options("Coyote Hello World Example");
    runtime_options.add_options()
        ("hugepages,h", boost::program_options::value<bool>(&hugepages)->default_value(true), "Use hugepages")
        ("mapped,m", boost::program_options::value<bool>(&mapped)->default_value(true), "Use mapped memory (see README for more details)")
        ("stream,s", boost::program_options::value<bool>(&stream)->default_value(1), "Source / destination data stream: HOST(1) or FPGA(0)")
        ("runs,r", boost::program_options::value<unsigned int>(&n_runs)->default_value(50), "Number of times to repeat the test")
        ("min_size,x", boost::program_options::value<unsigned int>(&min_size)->default_value(64), "Starting (minimum) transfer size [B]")
        ("max_size,X", boost::program_options::value<unsigned int>(&max_size)->default_value(4 * 1024 * 1024), "Ending (maximum) transfer size [B]");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    HEADER("CLI PARAMETERS:");
    std::cout << "Enable hugepages: " << hugepages << std::endl;
    std::cout << "Enable mapped pages: " << mapped << std::endl;
    std::cout << "Data stream: " << (stream ? "HOST" : "CARD") << std::endl;
    std::cout << "Number of test runs: " << n_runs << std::endl;
    std::cout << "Starting transfer size: " << min_size << std::endl;
    std::cout << "Ending transfer size: " << max_size << std::endl << std::endl;

    // Obtain a Coyote thread
    coyote::cThread coyote_thread(DEFAULT_VFPGA_ID, getpid());

    // Allocate memory for source and destination data
    // We cast to integer arrays, so that we can compare source and destination values after transfers 
    // For more details on the difference between mapped and non-mapped memory, refer to the README for this example
    int *src_mem, *dst_mem;
    if (mapped) {
        if (hugepages) {
            src_mem = (int *) coyote_thread.getMem({coyote::CoyoteAllocType::HPF, max_size});
            dst_mem = (int *) coyote_thread.getMem({coyote::CoyoteAllocType::HPF, max_size});
        } else {
            src_mem = (int *) coyote_thread.getMem({coyote::CoyoteAllocType::REG, max_size});
            dst_mem = (int *) coyote_thread.getMem({coyote::CoyoteAllocType::REG, max_size});
        }
    } else {
        if (hugepages) {
            src_mem = (int *) mmap(NULL, max_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
            dst_mem = (int *) mmap(NULL, max_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
        } else {
            src_mem = (int *) aligned_alloc(coyote::PAGE_SIZE, max_size);
            dst_mem = (int *) aligned_alloc(coyote::PAGE_SIZE, max_size);
        }
    }

    // Exit if memory couldn't be allocated
    if (!src_mem || !dst_mem) { throw std::runtime_error("Could not allocate memory; exiting..."); }

    // Initialises a Scatter-Gather (SG) entry 
    // SG entries are used in DMA operations to describe source & dest memory buffers, their addresses, sizes etc.
    // Coyote has its own implementation of SG entires for various data movement, such as local, RDMA, TCP etc, with varying fields
    coyote::localSg src_sg = { .addr = src_mem, .stream = stream };
    coyote::localSg dst_sg = { .addr = dst_mem, .stream = stream };

    HEADER("PERF LOCAL");
    unsigned int curr_size = min_size;
    while(curr_size <= max_size) {
        // Update SG size entry
        std::cout << "Size: " << std::setw(8) << curr_size << "; ";
        src_sg.len = curr_size; dst_sg.len = curr_size; 

        // Run throughput test
        double throughput_time = run_bench(coyote_thread, src_sg, dst_sg, src_mem, dst_mem, N_THROUGHPUT_REPS, n_runs, !stream);
        double throughput = ((double) N_THROUGHPUT_REPS * (double) curr_size) / (1024.0 * 1024.0 * throughput_time * 1e-9);
        std::cout << "Average throughput: " << std::setw(8) << throughput << " MB/s; ";
        
        // Run latency test
        double latency_time = run_bench(coyote_thread, src_sg, dst_sg, src_mem, dst_mem, N_LATENCY_REPS, n_runs, !stream);
        std::cout << "Average latency: " << std::setw(8) << latency_time / 1e3 << " us" << std::endl;

        // Update size and proceed to next iteration
        curr_size *= 2;
    }

    // Release dynamically allocated memory & exit
    // NOTE: For memory allocated using Coyote's internal getMem()
    // Memory de-allocation is automatically handled in the the thread destructor
    if(!mapped) {
        if(!hugepages) { free(src_mem); free(dst_mem); }
        else { munmap(src_mem, max_size); munmap(dst_mem, max_size); }
    }
    
    return EXIT_SUCCESS;
}
