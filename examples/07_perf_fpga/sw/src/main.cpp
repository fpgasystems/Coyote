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

// Includes
#include <chrono>
#include <thread>
#include <vector>
#include <iostream>
#include <boost/program_options.hpp>

#include "cThread.hpp"

#include <hip/hip_runtime.h>

// Constants
#define DEFAULT_GPU_ID 4
#define DEFAULT_VFPGA_ID 0

#define N_LATENCY_REPS 1
#define N_THROUGHPUT_REPS 16

// Registers, corresponding to registers defined the vFPGA
enum class BenchmarkRegisters: uint32_t {
    CTRL_REG = 0,           // AP start, read or write
    DONE_REG = 1,           // Number of completed requests
    TIMER_REG = 2,          // Timer register
    VADDR_REG = 3,          // Buffer virtual address
    LEN_REG = 4,            // Buffer length (size in bytes)
    PID_REG = 5,            // Coyote thread ID
    N_REPS_REG = 6,         // Number of read/write repetitions
    N_BEATS_REG = 7         // Number of expected AXI beats
};

// 01 written to CTRL_REG starts a read operation and 10 written to CTRL registers starts a write
enum class BenchmarkOperation: uint8_t {
    START_RD = 0x1,
    START_WR = 0x2
};

// Note, how the Coyote thread is passed by reference; to avoid creating a copy of 
// the thread object which can lead to undefined behaviour and bugs. 
std::vector<double> run_bench(
    coyote::cThread &coyote_thread, unsigned int size, int *mem, 
    unsigned int transfers, unsigned int n_runs, BenchmarkOperation oper
) {
    // Single iteration of transfers reads or writes
    auto benchmark_run = [&]() {
        coyote_thread.clearCompleted();
        uint64_t n_beats = transfers * ((size + 64 - 1) / 64);
        
        auto start_time = std::chrono::high_resolution_clock::now();
        
        // Set the required registers from SW; the vFPGA uses these registers to start the transfer
        coyote_thread.setCSR(reinterpret_cast<uint64_t>(mem), static_cast<uint32_t>(BenchmarkRegisters::VADDR_REG));
        coyote_thread.setCSR(size, static_cast<uint32_t>(BenchmarkRegisters::LEN_REG));
        coyote_thread.setCSR(coyote_thread.getCtid(), static_cast<uint32_t>(BenchmarkRegisters::PID_REG));
        coyote_thread.setCSR(transfers, static_cast<uint32_t>(BenchmarkRegisters::N_REPS_REG));
        coyote_thread.setCSR(n_beats, static_cast<uint32_t>(BenchmarkRegisters::N_BEATS_REG));
        coyote_thread.setCSR(static_cast<uint64_t>(oper), static_cast<uint32_t>(BenchmarkRegisters::CTRL_REG));
    
        // Poll on completion
        if (oper == BenchmarkOperation::START_RD) {
            while (coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_READ) != 1) {}
        } else {
            while (coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != 1) {}            
        }

        // Capture time taken
        auto end_time = std::chrono::high_resolution_clock::now();
        return (double) std::chrono::duration_cast<std::chrono::nanoseconds>(end_time - start_time).count();

    };

    // Warm-up runs
    for(int j = 0; j < 50; j++) {
        benchmark_run();
    }

    // Run benchmark
    std::vector<double> times;
    for(int j = 0; j < n_runs; j++) {
        double t = benchmark_run();
        times.push_back(t);
    }
    
    return times;
}

int main(int argc, char *argv[]) {
    // CLI arguments
    bool operation;
    unsigned int n_runs, min_size, max_size;

    boost::program_options::options_description runtime_options("Coyote Perf FPGA Options");
    runtime_options.add_options()
        ("operation,o", boost::program_options::value<bool>(&operation)->default_value(false), "Benchmark operation: READ(0) or WRITE(1)")
        ("runs,r", boost::program_options::value<unsigned int>(&n_runs)->default_value(50), "Number of times to repeat the test")
        ("min_size,x", boost::program_options::value<unsigned int>(&min_size)->default_value(256), "Starting (minimum) transfer size")
        ("max_size,X", boost::program_options::value<unsigned int>(&max_size)->default_value(32 * 1024 * 1024), "Ending (maximum) transfer size");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);
    BenchmarkOperation oper = operation ? BenchmarkOperation::START_WR : BenchmarkOperation::START_RD;

    HEADER("CLI PARAMETERS:");
    std::cout << "Benchmark operation: " << (operation ? "WRITE" : "READ") << std::endl;
    std::cout << "Number of test runs: " << n_runs << std::endl;
    std::cout << "Starting transfer size: " << min_size << std::endl;
    std::cout << "Ending transfer size: " << max_size << std::endl << std::endl;

    if (hipSetDevice(DEFAULT_GPU_ID)) { throw std::runtime_error("Couldn't select GPU!"); }

    // Create Coyote thread and allocate source & destination memory
    coyote::cThread coyote_thread(DEFAULT_VFPGA_ID, getpid());
    int* mem =  (int *) coyote_thread.getMem({coyote::CoyoteAllocType::GPU, max_size, false, DEFAULT_GPU_ID});
    if (!mem) { throw std::runtime_error("Could not allocate memory; exiting..."); }

    // Benchmark sweep
    HEADER("PERF FPGA");
    unsigned int curr_size = min_size;
    while(curr_size <= max_size) {
        std::cout << "Size: " << std::setw(8) << curr_size << "; ";

        double avg_time;
        std::vector<double> measured_times;
        
        // Run throughput test
        measured_times = run_bench(coyote_thread, curr_size, mem, N_THROUGHPUT_REPS, n_runs, oper);
        double avg_throughput = 0;
        for (const double &t : measured_times) {
            avg_throughput += ((double) N_THROUGHPUT_REPS * (double) curr_size) / (1024.0 * 1024.0 * 1024.0 * t * 1e-9);;
        }
        avg_throughput = avg_throughput / (double) measured_times.size(); 
        std::cout << "Average throughput: " << avg_throughput << " GB/s (over " << measured_times.size() << " runs); ";
       
        // Run latency test
        measured_times = run_bench(coyote_thread, curr_size, mem, N_LATENCY_REPS, n_runs, oper);
        avg_time = 0;
        for (const double &t : measured_times) {
            avg_time += t;
        }
        avg_time = avg_time / (double) measured_times.size(); 
        std::cout << "Average latency: " << avg_time / 1e3 << " us (over " << measured_times.size() << " runs); ";

        // Update size and proceed to next iteration
        curr_size *= 2;
    }

    return EXIT_SUCCESS;
}

