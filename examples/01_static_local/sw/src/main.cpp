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
#include "cBench.hpp"
#include "cThread.hpp"

// Constants
#define N_LATENCY_REPS 1
#define N_THROUGHPUT_REPS 32

#define DEFAULT_GPU_ID 4
#define DEFAULT_VFPGA_ID 0

// Note, how the Coyote thread is passed by reference; to avoid creating a copy of 
// the thread object which can lead to undefined behaviour and bugs. 
double run_bench(
    coyote::cThread &coyote_thread, std::vector<hipStream_t> &hip_streams_d2h, std::vector<hipStream_t> &hip_streams_h2d, coyote::localSg &src_sg, coyote::localSg &dst_sg, 
    int *cyt_src_mem, int *cyt_dst_mem, int *gpu_src_mem, int *gpu_dst_mem, unsigned int transfers, unsigned int n_runs, unsigned int mode
) {
    // Initialise helper benchmarking class
    // Used for keeping track of execution times & some helper functions (mean, P25, P75 etc.)
    coyote::cBench bench(n_runs);
    
    // Randomly set the source data between -512 and +512; initialise destination memory to 0
    assert(src_sg.len == dst_sg.len);
    if (mode) {
        for (int i = 0; i < src_sg.len / sizeof(int); i++) {
            cyt_src_mem[i] = rand() % 1024 - 512;     
            cyt_dst_mem[i] = 0;                        
        }
    } else {
        for (int i = 0; i < src_sg.len / sizeof(int); i++) {
            gpu_src_mem[i] = rand() % 1024 - 512;     
            gpu_dst_mem[i] = 0;                        
        }
    }

    // For non-P2P, to keep track what streams have completed
    bool gpu_to_cpu_done;
    std::vector<bool> stream_completed;
    for (int i = 0 ; i < transfers; i++) {
        stream_completed.push_back(false);
    }

    // Function called before every iteration of the benchmark, can be used to clear previous flags, states etc.
    auto prep_fn = [&]() {
        // Clear the completion counters, so that the test can be repeated multiple times independently
        // Essentially, sets the result from the function checkCompleted(...) to zero
        coyote_thread.clearCompleted();

        // Also, synchronize the GPU
        hipDeviceSynchronize();

        // Reset stream completions
        for (int i = 0 ; i < transfers; i++) {
            stream_completed[i] = false;
        }

    };

    // Execute benchmark
    auto bench_fn = [&]() {
        // Non-P2P case
        if (!mode) {
            // First, do a memcpy from GPU to to CPU
            // For throughput tests, launch multiple transfers in parallel; for latency tests, launch one
            for (int i = 0; i < transfers; i++) {
                hipMemcpyWithStream(cyt_src_mem, gpu_src_mem, src_sg.len, hipMemcpyDeviceToHost, hip_streams_d2h[i]);
            }

            // As soon as one is finished, launch its corresponding Coyote transfer: CPU => vFPGA => CPU (non-P2P)
            gpu_to_cpu_done = false;
            while (!gpu_to_cpu_done) {
                gpu_to_cpu_done = true;
                for (unsigned int i = 0; i < transfers; i++) {
                    if (hipStreamQuery(hip_streams_d2h[i]) != hipSuccess) {
                        gpu_to_cpu_done = false;
                    } else {
                        if (!stream_completed[i]) {
                            // std::cout << "Invoking" << std::endl;
                            coyote_thread.invoke(coyote::CoyoteOper::LOCAL_TRANSFER, src_sg, dst_sg);
                            stream_completed[i] = true;
                        }
                    }
                }        
            }

            // Now, as soon as one Coyote transfer is finished, launch its corresponding GPU transfer: CPU => GPU
            unsigned int completed_coyote = 0;
            while (completed_coyote < transfers) {
                unsigned int old_completed_coyote = completed_coyote;
                completed_coyote = coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_TRANSFER);
                
                for (unsigned int i = old_completed_coyote; i < completed_coyote; i++) {
                    // Launch the GPU transfer for the completed Coyote transfer
                    hipMemcpyWithStream(gpu_dst_mem, cyt_dst_mem, dst_sg.len, hipMemcpyHostToDevice, hip_streams_h2d[i]);
                }
            
            }

            // Simply synchronize the device to ensure that all transfers are complete
            hipDeviceSynchronize();
            
        // P2P case
        } else {
            // For P2P, do a GPU => vFPGA => GPU transfer
            for (int i = 0; i < transfers; i++) {
                coyote_thread.invoke(coyote::CoyoteOper::LOCAL_TRANSFER, src_sg, dst_sg);
            }

            // Wait until all transfers are complete
            while (coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_TRANSFER) != transfers) {}
        
            // Synchronize just to make sure consistency with P2P case
            hipDeviceSynchronize();
        }

    };

    bench.execute(bench_fn, prep_fn);
    
    // Make sure destination matches the source + 1 (the vFPGA logic in perf_local adds 1 to every 32-bit element, i.e. integer)
    if (mode) {
        for (int i = 0; i < src_sg.len / sizeof(int); i++) {
            assert(cyt_src_mem[i] + 1 == cyt_dst_mem[i]); 
        }
    } else {
        for (int i = 0; i < src_sg.len / sizeof(int); i++) {
            assert(gpu_src_mem[i] + 1 == gpu_dst_mem[i]); 
        }
    }

    // Return average time taken for the data transfer
    return bench.getAvg();
}

int main(int argc, char *argv[])  {
    // CLI arguments
    unsigned int min_size, max_size, n_runs, mode;
    boost::program_options::options_description runtime_options("Coyote Perf GPU Options");
    runtime_options.add_options()
        ("runs,r", boost::program_options::value<unsigned int>(&n_runs)->default_value(50), "Number of times to repeat the test")
        ("mode,m", boost::program_options::value<unsigned int>(&mode)->default_value(1), "Benchmark mode: 1 (P2P) or 0 (baseline)")
        ("min_size,x", boost::program_options::value<unsigned int>(&min_size)->default_value(64), "Starting (minimum) transfer size")
        ("max_size,X", boost::program_options::value<unsigned int>(&max_size)->default_value(4 * 1024 * 1024), "Ending (maximum) transfer size");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    HEADER("CLI PARAMETERS: two-sided, host-initiated transfers");
    std::cout << "MODE: " << mode << std::endl;
    std::cout << "Number of test runs: " << n_runs << std::endl;
    std::cout << "Starting transfer size: " << min_size << std::endl;
    std::cout << "Ending transfer size: " << max_size << std::endl << std::endl;

    // GPU memory will be allocated on the GPU set using hipSetDevice(...)
    if (hipSetDevice(DEFAULT_GPU_ID)) { throw std::runtime_error("Couldn't select GPU!"); }

    // Create a HIP stream; one for each parallel transfer
    std::vector<hipStream_t> hip_streams_d2h, hip_streams_h2d;
    for (unsigned int i = 0; i < N_THROUGHPUT_REPS; i++) {
        hipStream_t stream_d2h;
        if (hipStreamCreate(&stream_d2h)) { throw std::runtime_error("Couldn't create D2H HIP stream!"); }
        hip_streams_d2h.emplace_back(stream_d2h);
    
        hipStream_t stream_h2d;
        if (hipStreamCreate(&stream_h2d)) { throw std::runtime_error("Couldn't create H2D HIP stream!"); }
        hip_streams_h2d.emplace_back(stream_h2d);
    }

    // Obtain a Coyote thread and allocate memory
    // Note, the only difference from Example 1 is the way memory is allocated
    coyote::cThread coyote_thread(DEFAULT_VFPGA_ID, getpid());
    int *cyt_src_mem, *cyt_dst_mem, *gpu_src_mem, *gpu_dst_mem;
    if (mode) {
        cyt_src_mem = (int *) coyote_thread.getMem({coyote::CoyoteAllocType::GPU, max_size, false, DEFAULT_GPU_ID});
        cyt_dst_mem = (int *) coyote_thread.getMem({coyote::CoyoteAllocType::GPU, max_size, false, DEFAULT_GPU_ID});
        gpu_src_mem = nullptr;
        gpu_dst_mem = nullptr;
    } else {
        cyt_src_mem = (int *) coyote_thread.getMem({coyote::CoyoteAllocType::HPF, max_size});
        cyt_dst_mem = (int *) coyote_thread.getMem({coyote::CoyoteAllocType::HPF, max_size});
        hipMalloc((void **) &gpu_src_mem, max_size);
        hipMalloc((void **) &gpu_dst_mem, max_size);
        if (gpu_src_mem == nullptr || gpu_dst_mem == nullptr) {  throw std::runtime_error("Could not allocate GPU memory; exiting..."); }
    }
    if (cyt_src_mem == nullptr || cyt_dst_mem == nullptr) { throw std::runtime_error("Could not allocate Coyote memory; exiting..."); }

    // Scatter-Gather (SG) entries
    coyote::localSg src_sg = { .addr = cyt_src_mem };
    coyote::localSg dst_sg = { .addr = cyt_dst_mem };
    
    HEADER("PERF GPU");
    unsigned int curr_size = min_size;
    while(curr_size <= max_size) {
        // Update SG size entry
        std::cout << "Size: " << std::setw(8) << curr_size << "; ";
        src_sg.len = curr_size; dst_sg.len = curr_size; 

        // Run throughput test
        double throughput_time = run_bench(coyote_thread, hip_streams_d2h, hip_streams_h2d, src_sg, dst_sg, cyt_src_mem, cyt_dst_mem, gpu_src_mem, gpu_dst_mem, N_THROUGHPUT_REPS, n_runs, mode);
        double throughput = ((double) N_THROUGHPUT_REPS * (double) curr_size) / (1024.0 * 1024.0 * throughput_time * 1e-9);
        std::cout << "Average throughput: " << std::setw(8) << throughput << " MB/s; ";
        
        // Run latency test
        double latency_time = run_bench(coyote_thread, hip_streams_d2h, hip_streams_h2d, src_sg, dst_sg, cyt_src_mem, cyt_dst_mem, gpu_src_mem, gpu_dst_mem, N_LATENCY_REPS, n_runs, mode);
        std::cout << "Average latency: " << std::setw(8) << latency_time / 1e3 << " us" << std::endl;

        // Update size and proceed to next iteration
        curr_size *= 2;
    }

    hipFree(gpu_src_mem);
    hipFree(gpu_dst_mem);
    for (unsigned int i = 0; i < N_THROUGHPUT_REPS; i++) {
        hipStreamDestroy(hip_streams_d2h[i]);
        hipStreamDestroy(hip_streams_h2d[i]);
    }

    // Note, how there is no memory de-allocation, since the memory was allocated using coyote_thread->getMem(...)
    // A Coyote thread always keeps track of the memory it allocated and internally handles de-allocation
    return EXIT_SUCCESS;
}
