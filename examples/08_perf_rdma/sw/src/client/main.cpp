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
#include "constants.hpp"

constexpr bool const IS_CLIENT = true;

double run_bench(
    coyote::cThread<std::any> &coyote_thread, coyote::sgEntry &sg, 
    int *mem, uint transfers, uint n_runs, bool operation
) {
    // When writing, the server asserts the written payload is correct (which the client sets)
    // When reading, the client asserts the read payload is correct (which the server sets)
    for (int i = 0; i < sg.rdma.len / sizeof(int); i++) {
        mem[i] = operation ? i : 0;         
    }
    
    // Before every benchmark, clear previous completion flags and sync with server
    // Sync is in a way equivalent to MPI_Barrier()
    auto prep_fn = [&]() {
        coyote_thread.clearCompleted();
        coyote_thread.connSync(IS_CLIENT);
    };
    
    /* Benchmark function; as eplained in the README
     * For RDMA_WRITEs, the client writes multiple times to the server and then the server writes the same content back
     * For RDMA READs, the client reads from the server multiple times
     * In boths cases, that means there will be n_transfers completed writes to local memory (LOCAL_WRITE)
     */
    coyote::CoyoteOper coyote_operation = operation ? coyote::CoyoteOper::REMOTE_RDMA_WRITE : coyote::CoyoteOper::REMOTE_RDMA_READ;
    auto bench_fn = [&]() {        
        for (int i = 0; i < transfers; i++) {
            coyote_thread.invoke(coyote_operation, &sg);
        }

        while (coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != transfers) {}
    };

    // Execute benchmark
    coyote::cBench bench(n_runs, 0);
    bench.execute(bench_fn, prep_fn);

    // Functional correctness check
    if (!operation) {
        for (int i = 0; i < sg.rdma.len / sizeof(int); i++) {
            assert(mem[i] == i);
        }
    }
    
    // For writes, divide by 2, since that is sent two ways (from client to server and then from server to client)
    // Reads are one way, so no need to scale
    return bench.getAvg() / (1. + (double) operation);
}

int main(int argc, char *argv[])  {
    // CLI arguments
    bool operation;
    std::string server_ip;
    unsigned int min_size, max_size, n_runs;

    boost::program_options::options_description runtime_options("Coyote Perf RDMA Options");
    runtime_options.add_options()
        ("ip_address,i", boost::program_options::value<std::string>(&server_ip), "Server's IP address")
        ("operation,o", boost::program_options::value<bool>(&operation)->default_value(false), "Benchmark operation: READ(0) or WRITE(1)")
        ("runs,r", boost::program_options::value<unsigned int>(&n_runs)->default_value(10), "Number of times to repeat the test")
        ("min_size,x", boost::program_options::value<unsigned int>(&min_size)->default_value(64), "Starting (minimum) transfer size")
        ("max_size,X", boost::program_options::value<unsigned int>(&max_size)->default_value(1 * 1024 * 1024), "Ending (maximum) transfer size");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    PR_HEADER("CLI PARAMETERS:");
    std::cout << "Server's TCP address: " << server_ip << std::endl;
    std::cout << "Benchmark operation: " << (operation ? "WRITE" : "READ") << std::endl;
    std::cout << "Number of test runs: " << n_runs << std::endl;
    std::cout << "Starting transfer size: " << min_size << std::endl;
    std::cout << "Ending transfer size: " << max_size << std::endl << std::endl;

    /* Coyote completely abstracts the complexity behind exchanging QPs and setting up an RDMA connection
     * Instead, given a cThread, the target RDMA buffer size and the remote server's TCP address,
     * One can use the function initRDMA, which will allocate the buffer and 
     * Exchange the necessary information with the server; the server calls the equivalent function but without the IP address
     */
    coyote::cThread<std::any> coyote_thread(DEFAULT_VFPGA_ID, getpid(), 0);
    int *mem = (int *) coyote_thread.initRDMA(max_size, coyote::defPort, server_ip.c_str());
    if (!mem) { throw std::runtime_error("Could not allocate memory; exiting..."); }

    // Benchmark sweep of latency and throughput
    PR_HEADER("RDMA BENCHMARK: CLIENT");
    unsigned int curr_size = min_size;
    while(curr_size <= max_size) {
        std::cout << "Size: " << std::setw(8) << curr_size << "; ";
        
        coyote::sgEntry sg;
        sg.rdma = { .len = curr_size };
    
        double throughput_time = run_bench(coyote_thread, sg, mem, N_THROUGHPUT_REPS, n_runs, operation);
        double throughput = ((double) N_THROUGHPUT_REPS * (double) curr_size) / (1024.0 * 1024.0 * throughput_time * 1e-9);
        std::cout << "Average throughput: " << std::setw(8) << throughput << " MB/s; ";
        
        double latency_time = run_bench(coyote_thread, sg, mem, N_LATENCY_REPS, n_runs, operation);
        std::cout << "Average latency: " << std::setw(8) << latency_time / 1e3 << " us" << std::endl;

        curr_size *= 2;
    }

    // Final sync and exit
    coyote_thread.connSync(IS_CLIENT);
    return EXIT_SUCCESS;
}