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
#include <iostream>
#include <cstdlib>

// External library for easier parsing of CLI arguments by the executable
#include <boost/program_options.hpp>

// Coyote-specific includes
#include "cBench.hpp"
#include "cThread.hpp"

// Constants
#define DEFAULT_VFPGA_ID 0

using sg_pair = std::pair<coyote::localSg, coyote::localSg>;

int main(int argc, char *argv[])  {
    // CLI arguments
    unsigned int size, threads, runs;
    boost::program_options::options_description runtime_options("Coyote HBM Scaling Options");
    runtime_options.add_options()
        ("runs,r", boost::program_options::value<unsigned int>(&runs)->default_value(50), "Number of times to repeat the test")
        ("size,s", boost::program_options::value<unsigned int>(&size)->default_value(1024 * 1024), "Transfer size [B]")
        ("threads,t", boost::program_options::value<unsigned int>(&threads)->default_value(1), "Number of parallel threads/transfers");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    if (threads > 6) {
        throw std::runtime_error("The shell is built with 6 card streams; cannot have more threads than streams in this specific example...");
    }

    std::vector<std::unique_ptr<coyote::cThread>> coyote_threads;
    std::vector<int *> src_mems, dst_mems;
    std::vector<sg_pair> sg_list;
    for (unsigned int i = 0; i < threads; i++) {
        // Create one instance of Coyote thread per HBM stream
        coyote_threads.emplace_back(new coyote::cThread(DEFAULT_VFPGA_ID, getpid()));
        
        // Allocate source & destination memory
        src_mems.emplace_back((int *) coyote_threads[i]->getMem({coyote::CoyoteAllocType::HPF, size}));
        dst_mems.emplace_back((int *) coyote_threads[i]->getMem({coyote::CoyoteAllocType::HPF, size}));
        if (!src_mems[i] || !dst_mems[i]) { throw std::runtime_error("Could not allocate memory; exiting..."); }

        // Allocate scatter-gather entry for this Coyote thread
        // Note, how dest is set to i, corresponding to the i-th Coyote thread using the i-th HBM data interface
        // Finally, note how the stream is set to 0, indicating data movement from/to card memory (HBM)
        // On the first data movement, Coyote will issue a page fault which will migrate the source and destination buffers to HBM
        coyote::localSg src_sg = { .addr = src_mems[i], .len = size, .stream = 0, .dest = i };
        coyote::localSg dst_sg = { .addr = dst_mems[i], .len = size, .stream = 0, .dest = i };
        sg_list.emplace_back(std::make_pair(src_sg, dst_sg));
    }
    
    // Randomly set the source data for functional verification
    for (int k = 0; k < threads; k++) {
        assert(sg_list[k].first.len == sg_list[k].second.len);
        for (int i = 0; i < sg_list[k].first.len / sizeof(int); i++) {
            src_mems[k][i] = rand() % 1024 - 512;     
            dst_mems[k][i] = 0;                        
        }
    }

    auto prep_fn = [&]() {
        // Clear the completion counters for the next iteration of the benchmark
        for (unsigned int i = 0; i < threads; i++) {
            coyote_threads[i]->clearCompleted();
        }
    };
    
    auto benchmark_thr = [&]() {
        for (unsigned int i = 0; i < threads; i++) {
            // Start asynchronous transfer for each thread
            coyote_threads[i]->invoke(coyote::CoyoteOper::LOCAL_TRANSFER, sg_list[i].first, sg_list[i].second);
        }
        
        // Wait until all the Coyote threads are complete
        bool k = false;
        while(!k) {
            k = true;
            for (unsigned int i = 0; i < threads; i++) {
                if(coyote_threads[i]->checkCompleted(coyote::CoyoteOper::LOCAL_TRANSFER) != 1) k = false;
            }
        } 
    };

    // Start throughput test
    coyote::cBench bench(runs);
    HEADER("HBM SCALING PERFORMANCE");
    bench.execute(benchmark_thr, prep_fn);

    // Check functional correctness
    for (int k = 0; k < threads; k++) {
        // Sync data back
        coyote::syncSg sg_sync;

        sg_sync = {.addr = src_mems[k], .len = sg_list[k].first.len }; 
        coyote_threads[k]->invoke(coyote::CoyoteOper::LOCAL_SYNC, sg_sync);

        sg_sync = {.addr = dst_mems[k], .len = sg_list[k].first.len }; 
        coyote_threads[k]->invoke(coyote::CoyoteOper::LOCAL_SYNC, sg_sync);

        // Make sure destination matches the source + 1 (the vFPGA logic in perf_local adds 1 to every 32-bit element, i.e. integer)
        assert(sg_list[k].first.len == sg_list[k].second.len);
        for (int i = 0; i < sg_list[k].first.len / sizeof(int); i++) {
            assert(src_mems[k][i] + 1 == dst_mems[k][i]); 
        }
    }

    // Finally, calculate throughput
    std::vector<double> latencies = bench.getAll();
    double tmp = 0;
    double sum = 0;    
    for (auto t: latencies) {
        tmp = ((double) size * threads) / (1024.0 * 1024.0 * 1024 * 1e-9 * t);
        sum += tmp;
    }
    double throughput = sum / (double) latencies.size(); 
    std::cout << "Average throughput: " << std::setw(8) << throughput << " GB/s; " << std::endl;
    
    return EXIT_SUCCESS;
}
