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
#include "cThread.hpp"
#include "constants.hpp"

constexpr bool const IS_CLIENT = false;

void run_bench(
    coyote::cThread<std::any> &coyote_thread, coyote::sgEntry &sg, 
    int *mem, uint transfers, uint n_runs, bool operation
) {
    // When writing, the server asserts the written payload is correct (which the client sets)
    // When reading, the client asserts the read payload is correct (which the server sets)
    for (int i = 0; i < sg.rdma.len / sizeof(int); i++) {
        mem[i] = operation ? 0 : i;        
    }

    for (int i = 0; i < n_runs; i++) {
        // Clear previous completion flags and sync with client
        coyote_thread.clearCompleted();
        coyote_thread.connSync(IS_CLIENT);

        // For writes, wait until client has written the targer number of messages; then write them back
        if (operation) {
            while (coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != transfers) {}

            for (int i = 0; i < transfers; i++) {
                coyote_thread.invoke(coyote::CoyoteOper::REMOTE_RDMA_WRITE, &sg);
            }
        // For reads, the server is completely passive 
        } else { 

        }
    }
    
    // Functional correctness check
    if (operation) {
        for (int i = 0; i < sg.rdma.len / sizeof(int); i++) {
            assert(mem[i] == i);                        
        }
    }
}

int main(int argc, char *argv[])  {
    // CLI arguments
    bool operation;
    unsigned int min_size, max_size, n_runs;

    boost::program_options::options_description runtime_options("Coyote Perf RDMA Options");
    runtime_options.add_options()
        ("operation,o", boost::program_options::value<bool>(&operation)->default_value(false), "Benchmark operation: READ(0) or WRITE(1)")
        ("runs,r", boost::program_options::value<unsigned int>(&n_runs)->default_value(100), "Number of times to repeat the test")
        ("min_size,x", boost::program_options::value<unsigned int>(&min_size)->default_value(64), "Starting (minimum) transfer size")
        ("max_size,X", boost::program_options::value<unsigned int>(&max_size)->default_value(1 * 1024 * 1024), "Ending (maximum) transfer size");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    PR_HEADER("CLI PARAMETERS:");
    std::cout << "Benchmark operation: " << (operation ? "WRITE" : "READ") << std::endl;
    std::cout << "Number of test runs: " << n_runs << std::endl;
    std::cout << "Starting transfer size: " << min_size << std::endl;
    std::cout << "Ending transfer size: " << max_size << std::endl << std::endl;

    // Allocate Coyothe threa and set-up RDMA connections, buffer etc.
    // initRDMA is explained in more detail in client/main.cpp
    coyote::cThread<std::any> coyote_thread(DEFAULT_VFPGA_ID, getpid(), 0);
    int *mem = (int *) coyote_thread.initRDMA(max_size, coyote::defPort);
    if (!mem) { throw std::runtime_error("Could not allocate memory; exiting..."); }

    // Benchmark sweep; exactly like done in the client code
    PR_HEADER("RDMA BENCHMARK: SERVER");
    unsigned int curr_size = min_size;
    while(curr_size <= max_size) {
        coyote::sgEntry sg;
        sg.rdma = { .len = curr_size };
        run_bench(coyote_thread, sg, mem, N_THROUGHPUT_REPS, n_runs, operation);
        run_bench(coyote_thread, sg, mem, N_LATENCY_REPS, n_runs, operation);
        curr_size *= 2;
    }

    // Final sync and exit
    coyote_thread.connSync(IS_CLIENT);
    return EXIT_SUCCESS;
}