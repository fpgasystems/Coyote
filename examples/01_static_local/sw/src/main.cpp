/**
  * Copyright (c) 2021-2024, Systems Group, ETH Zurich
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

#include <any>
#include <iostream>
#include <cstdlib>

// External library for easier parsing of CLI arguments by the executable
#include <boost/program_options.hpp>

// Coyote-specific includes
#include "cBench.hpp"
#include "cThread.hpp"

// Constants
#define N_LATENCY_REPS 1
#define N_THROUGHPUT_REPS 32

// Default vFPGA to assign cThreads to; for designs with one region (vFPGA) this is the only possible value
#define DEFAULT_VFPGA_ID 0

double run_bench(
    std::unique_ptr<coyote::cThread<std::any>> &coyote_thread, coyote::sgEntry &sg, 
    int *src_mem, int *dst_mem, uint transfers, uint n_runs, bool sync_back
) {
    // Initialise helper benchmarking class
    // Used for keeping track of execution times & some helper functions (mean, P25, P75 etc.)
    coyote::cBench bench(n_runs);
    
    // Randomly set the source data between -512 and +512; initialise destination memory to 0
    assert(sg.local.src_len == sg.local.dst_len);
    for (int i = 0; i < sg.local.src_len / sizeof(int); i++) {
        src_mem[i] = rand() % 1024 - 512;     
        dst_mem[i] = 0;                        
    }

    // Function called before every iteration of the benchmark, can be used to clear previous flags, states etc.
    auto prep_fn = [&] {
        // Clear the completion counters, so that the test can be repeated multiple times independently
        // Essentially, sets the result from the function checkCompleted(...) to zero
        coyote_thread->clearCompleted();
    };

    // Execute benchmark
    auto bench_fn = [&]() {
        // Launch (queue) multiple transfers in parallel for throughput tests, or 1 in case of latency tests
        // Recall, coyote_thread->invoke is asynchronous (can be made sync through different sgFlags)
        for (int i = 0; i < transfers; i++) {
            coyote_thread->invoke(coyote::CoyoteOper::LOCAL_TRANSFER, &sg);
        }

        // Wait until all of them are finished
        while (coyote_thread->checkCompleted(coyote::CoyoteOper::LOCAL_TRANSFER) != transfers) {}
    };

    bench.execute(bench_fn, prep_fn);
    
    // Sync data back, if required (stream == CARD)
    if (sync_back) {
        coyote::sgEntry sg_sync;
        sg_sync.sync = {.addr = src_mem, .size = sg.local.src_len }; 
        coyote_thread->invoke(coyote::CoyoteOper::LOCAL_SYNC, &sg_sync, {true, false, true});
        
        sg_sync.sync = {.addr = dst_mem, .size = sg.local.src_len }; 
        coyote_thread->invoke(coyote::CoyoteOper::LOCAL_SYNC, &sg_sync, {true, false, true});
    }

    // Make sure destination matches the source + 1 (the vFPGA logic in perf_local adds 1 to every 32-bit element, i.e. integer)
    for (int i = 0; i < sg.local.src_len / sizeof(int); i++) {
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
    boost::program_options::options_description runtime_options("Coyote Perf Local Options");
    runtime_options.add_options()
        ("hugepages,h", boost::program_options::value<bool>(&hugepages)->default_value(true), "Use hugepages")
        ("mapped,m", boost::program_options::value<bool>(&mapped)->default_value(true), "Use mapped memory (see README for more details)")
        ("stream,s", boost::program_options::value<bool>(&stream)->default_value(1), "Source / destination data stream: HOST(1) or FPGA(0)")
        ("runs,r", boost::program_options::value<unsigned int>(&n_runs)->default_value(100), "Number of times to repeat the test")
        ("min_size,x", boost::program_options::value<unsigned int>(&min_size)->default_value(64), "Starting (minimum) transfer size")
        ("max_size,X", boost::program_options::value<unsigned int>(&max_size)->default_value(4 * 1024 * 1024), "Ending (maximum) transfer size");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    PR_HEADER("CLI PARAMETERS:");
    std::cout << "Enable hugepages: " << hugepages << std::endl;
    std::cout << "Enable mapped pages: " << mapped << std::endl;
    std::cout << "Data stream: " << (stream ? "HOST" : "CARD") << std::endl;
    std::cout << "Number of test runs: " << n_runs << std::endl;
    std::cout << "Starting transfer size: " << min_size << std::endl;
    std::cout << "Ending transfer size: " << max_size << std::endl << std::endl;

    // Obtain a Coyote thread
    std::unique_ptr<coyote::cThread<std::any>> coyote_thread(new coyote::cThread<std::any>(DEFAULT_VFPGA_ID, getpid(), 0));

    // Allocate memory for source and destination data
    // We cast to integer arrays, so that we can compare source and destination values after transfers 
    // For more details on the difference between mapped and non-mapped memory, refer to the README for this example
    int *src_mem, *dst_mem;
    if (mapped) {
        if (hugepages) {
            src_mem = (int *) coyote_thread->getMem({coyote::CoyoteAlloc::HPF, max_size});
            dst_mem = (int *) coyote_thread->getMem({coyote::CoyoteAlloc::HPF, max_size});
        } else {
            src_mem = (int *) coyote_thread->getMem({coyote::CoyoteAlloc::REG, max_size});
            dst_mem = (int *) coyote_thread->getMem({coyote::CoyoteAlloc::REG, max_size});
        }
    } else {
        if (hugepages) {
            src_mem = (int *) mmap(NULL, max_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
            dst_mem = (int *) mmap(NULL, max_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
        } else {
            src_mem = (int *) aligned_alloc(coyote::pageSize, max_size);
            dst_mem = (int *) aligned_alloc(coyote::pageSize, max_size);
        }
    }

    // Exit if memory couldn't be allocated
    if (!src_mem || !dst_mem) { throw std::runtime_error("Could not allocate memory; exiting..."); }

    // Initialises a Scatter-Gather (SG) entry 
    // SG entries are used in DMA operations to describe source & dest memory buffers, their addresses, sizes etc.
    // Coyote has its own implementation of SG entires for various data mvoements, such as local, RDMA, TCP etc, with varying fields
    coyote::sgEntry sg;
    sg.local = {.src_addr = src_mem, .src_stream = stream, .dst_addr = dst_mem, .dst_stream = stream};

    PR_HEADER("PERF LOCAL");
    unsigned int curr_size = min_size;
    while(curr_size <= max_size) {
        // Update SG size entry
        std::cout << "Size: " << std::setw(8) << curr_size << "; ";
        sg.local.src_len = curr_size; sg.local.dst_len = curr_size; 

        // Run throughput test
        double throughput_time = run_bench(coyote_thread, sg, src_mem, dst_mem, N_THROUGHPUT_REPS, n_runs, !stream);
        double throughput = ((double) N_THROUGHPUT_REPS * (double) curr_size) / (1024.0 * 1024.0 * throughput_time * 1e-9);
        std::cout << "Average throughput: " << std::setw(8) << throughput << " MB/s; ";
        
        // Run latency test
        double latency_time = run_bench(coyote_thread, sg, src_mem, dst_mem, N_LATENCY_REPS, n_runs, !stream);
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
