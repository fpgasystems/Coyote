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

#include <string>
#include <fstream>
#include <iostream>

// External library, Boost, for easier parsing of CLI arguments
#include <boost/program_options.hpp>

// Coyote-specific includes
#include <coyote/cBench.hpp>
#include <coyote/cThread.hpp>

// Registers, corresponding to the ones in aes_axi_ctrl_parser
#define KEY_LOW_REG  0
#define KEY_HIGH_REG 1

// 128-bit encryption key
// Partitioned into two 64-bit values, since hardware registers are 64b (8B)
constexpr uint64_t KEY_LOW  = 0x6167717a7a767668;
constexpr uint64_t KEY_HIGH = 0x6a64727366626362;

using sg_pair = std::pair<coyote::localSg, coyote::localSg>;

int main(int argc, char *argv[])  {
    unsigned int n_runs, n_vfpga, message_size;

    boost::program_options::options_description runtime_options("Coyote multi-tenant AES encryption options");
    runtime_options.add_options()
        ("n_vfpga,n", boost::program_options::value<unsigned int>(&n_vfpga)->default_value(1), "Number of Coyote vFPGAs to use simultaneously")
        ("runs,r", boost::program_options::value<unsigned int>(&n_runs)->default_value(50), "Number of times to repeat the test")
        ("message_size,s", boost::program_options::value<unsigned int>(&message_size)->default_value(1024 * 1024), "Message size to be encrypted");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    HEADER("CLI PARAMETERS:");
    std::cout << "Number of Coyote vFPGAs: " << n_vfpga << std::endl;
    std::cout << "Number of test runs: " << n_runs << std::endl;
    std::cout << "Message size: " << message_size << std::endl;

    std::vector<std::unique_ptr<coyote::cThread>> coyote_threads;
    std::vector<char *> src_mems, dst_mems;
    std::vector<sg_pair> sg_list;
    for (unsigned int i = 0; i < n_vfpga; i++) {
        // Create one Coyote thread for each vFPGA
        coyote_threads.emplace_back(new coyote::cThread(i, getpid()));
        
        // Allocate memory for each Coyote thread
        src_mems.emplace_back((char *) coyote_threads[i]->getMem({coyote::CoyoteAllocType::HPF, message_size}));
        dst_mems.emplace_back((char *) coyote_threads[i]->getMem({coyote::CoyoteAllocType::HPF, message_size}));

        // Init src to random values and dst to zeros
        for (int k = 0; k < message_size; k++) {
            src_mems[i][k] = 'A' + (random() % 26);
        }
        memset(dst_mems[i], 0, message_size);
        if (!src_mems[i] || !dst_mems[i]) { throw std::runtime_error("Could not allocate memory; exiting..."); }

        // Allocate scatter-gather entry for this Coyote thread to do encryption
        // We are doing a LOCAL_TRANSFER: CPU MEM => vFPGA (encryption) => CPU MEM
        coyote::localSg src_sg = { .addr = src_mems[i], .len = message_size };
        coyote::localSg dst_sg = { .addr = dst_mems[i], .len = message_size };
        sg_list.emplace_back(std::make_pair(src_sg, dst_sg));

        // Set the encryption keys
        coyote_threads[i]->setCSR(KEY_LOW, KEY_LOW_REG);
        coyote_threads[i]->setCSR(KEY_HIGH, KEY_HIGH_REG);
    }
    
    // Per-thread vector to keep track of execution latencies and threads that have been completed
    std::vector<bool> transfer_done;
    std::vector<std::vector<double>> latencies(n_vfpga);
    std::vector<std::chrono::time_point<std::chrono::high_resolution_clock>> t0, t1;
    for (unsigned int i = 0; i < n_vfpga; i++) {
        transfer_done.emplace_back(false);
        t1.emplace_back(std::chrono::high_resolution_clock::now());
        t0.emplace_back(std::chrono::high_resolution_clock::now());
    }
    
    for (int k = 0; k < n_runs; k++) {
        // Clear the completion counters for the next iteration of the benchmark
        for (unsigned int i = 0; i < n_vfpga; i++) {
            transfer_done[i] = false;
            coyote_threads[i]->clearCompleted();
        }
        
        // Reset timers
        for (unsigned int i = 0; i < n_vfpga; i++) {
            t0[i] = std::chrono::high_resolution_clock::now();
        }

        // Start asynchronous transfer for each thread
        // Flow of data is: plain_text from CPU mem => AES CBC in vFPGA => encrypted text stored in CPU mem
        for (unsigned int i = 0; i < n_vfpga; i++) {
            coyote_threads[i]->invoke(coyote::CoyoteOper::LOCAL_TRANSFER, sg_list[i].first, sg_list[i].second);
        }
        
        // Wait until all the parallel regions are complete; as each finishes, timestamp
        bool done = false;
        while (!done) {
            done = true;
            for (unsigned int i = 0; i <= n_vfpga - 1; i++) {
                if (coyote_threads[i]->checkCompleted(coyote::CoyoteOper::LOCAL_TRANSFER) == 1 && !transfer_done[i]) {
                    transfer_done[i] = true;
                    t1[i] = std::chrono::high_resolution_clock::now();
                }
                done &= transfer_done[i];        
            }        
        }

        // Store latency and proceed to next iteration of the test
        for (unsigned int i = 0; i < n_vfpga; i++) {
            latencies[i].emplace_back(
                std::chrono::duration_cast<std::chrono::nanoseconds>(t1[i] - t0[i]).count()
            );
        } 
    }
    
    // Post-processing: calculate throughput
    for (unsigned int i = 0; i < n_vfpga; i++) {
        double tmp = 0;
        double sum = 0;
        for (const double &t : latencies[i]) {
           tmp = ((double) message_size) / (1024.0 * 1024.0 * 1e-9 * t);
           sum += tmp;
        }
        double throughput = sum / (double) latencies[i].size(); 
        std::cout << "Average throughput for vFPGA " << i << " is " << throughput << " MB/s; " << std::endl;
    }

    return EXIT_SUCCESS;
}
