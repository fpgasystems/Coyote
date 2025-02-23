/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
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
#include <random>
#include <string>
#include <iostream>

// External library, Boost, for easier parsing of CLI arguments to the binary
#include <boost/program_options.hpp>

// Coyote-specific includes
#include "cThread.hpp"
#include "cRnfg.hpp"

// Default (physical) FPGA device for nodes with multiple FPGAs
#define DEFAULT_DEVICE 0

// Default vFPGA to assign cThreads to
#define DEFAULT_VFPGA_ID 0

//////////////////////////////////////////////////////
// Source code from Example 2: HLS Vector Addition //
////////////////////////////////////////////////////
#define VECTOR_ELEMENTS 1024

void run_hls_vadd() {
    std::unique_ptr<coyote::cThread<std::any>> coyote_thread(new coyote::cThread<std::any>(DEFAULT_VFPGA_ID, getpid(), DEFAULT_DEVICE));
    float *a = (float *) coyote_thread->getMem({coyote::CoyoteAlloc::HPF, VECTOR_ELEMENTS});
    float *b = (float *) coyote_thread->getMem({coyote::CoyoteAlloc::HPF, VECTOR_ELEMENTS});
    float *c = (float *) coyote_thread->getMem({coyote::CoyoteAlloc::HPF, VECTOR_ELEMENTS});
    if (!a || !b || !c) { throw std::runtime_error("Could not allocate memory for vectors, exiting..."); }

    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_real_distribution<float> dis(-512.0, 512.0); 
    for (int i = 0; i < VECTOR_ELEMENTS; i++) {
        a[i] = dis(gen); b[i] = dis(gen); c[i] = 0;                        
    }
    
    std::cout << "Starting vector addition with " << VECTOR_ELEMENTS << " numbers..." << std::endl;
    coyote::sgEntry sg_a, sg_b, sg_c;
    sg_a.local = {.src_addr = a, .src_len = VECTOR_ELEMENTS * (uint) sizeof(float), .src_dest = 0};
    sg_b.local = {.src_addr = b, .src_len = VECTOR_ELEMENTS * (uint) sizeof(float), .src_dest = 1};
    sg_c.local = {.dst_addr = c, .dst_len = VECTOR_ELEMENTS * (uint) sizeof(float), .dst_dest = 0};

    coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ,  &sg_a);
    coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ,  &sg_b);
    coyote_thread->invoke(coyote::CoyoteOper::LOCAL_WRITE, &sg_c);
    while (
        coyote_thread->checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != 1 || 
        coyote_thread->checkCompleted(coyote::CoyoteOper::LOCAL_READ) != 2
    ) {}

    for (int i = 0; i < VECTOR_ELEMENTS; i++) { assert(a[i] + b[i] == c[i]); }
    std::cout << "Vector addition completed and verified correct! " << std::endl;
}

//////////////////////////////////////////////////
// Source code from Example 4: User Interrupts //
////////////////////////////////////////////////
#define INTERRUPT_TRANSFER_SIZE_BYTES 64

void interrupt_callback(int value) {
    std::cout << "Hello from my interrupt callback! The interrupt received a value: " << value << std::endl << std::endl;
}

void run_user_interrupts() {
    std::unique_ptr<coyote::cThread<std::any>> coyote_thread(
        new coyote::cThread<std::any>(DEFAULT_VFPGA_ID, getpid(), DEFAULT_DEVICE, nullptr, interrupt_callback)
    );

    int* data = (int *) coyote_thread->getMem({coyote::CoyoteAlloc::REG, INTERRUPT_TRANSFER_SIZE_BYTES});
    for (int i = 0; i < INTERRUPT_TRANSFER_SIZE_BYTES / sizeof(int); i++) { data[i] = i; }

    data[0] = 73;
    coyote::sgEntry sg;
    sg.local = {.src_addr = data, .src_len = INTERRUPT_TRANSFER_SIZE_BYTES};
    coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ, &sg, {true, true, true});
}

//////////////////////////////////////////////////
//                   Main                      //
////////////////////////////////////////////////
int main(int argc, char *argv[])  {
    std::string bitstream_path;
    boost::program_options::options_description runtime_options("Coyote Reconfigure Shell Options");
    runtime_options.add_options()
        ("bitstream,b", boost::program_options::value<std::string>(&bitstream_path)->required(), "Path to HLS Vector Add shell bitstream (.bin)");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    // First, execute a kernel from the previous example, user_interrupts
    run_user_interrupts();

    // Now, let's reconfigure the entire shell with the one from example 2, hls_vadd 
    try {
        // To reconfigure, we need to create an instance of cRnfg for the target (physical) FPGA device
        coyote::cRnfg crnfg(DEFAULT_DEVICE);
        std::cout << "Reconfiguring the shell with bitstream: " << bitstream_path << std::endl;
        
        // Then, trigger shell reconfiguration
        auto begin_time = std::chrono::high_resolution_clock::now();
        crnfg.reconfigureShell(bitstream_path);
        auto end_time = std::chrono::high_resolution_clock::now();

        double time = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - begin_time).count();
        std::cout << "Shell loaded in " << time << " milliseconds" << std::endl << std::endl;

        // Confirm that the shell was indeed reconfigured, by running a kernel from that shell 
        run_hls_vadd();

    } catch(const std::exception &e) {
        std::cerr << std::endl << e.what() << std::endl;
        return EXIT_FAILURE;
    }
    
    return EXIT_SUCCESS;
}
