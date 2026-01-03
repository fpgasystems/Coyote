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
#include <random>
#include <string>
#include <iostream>

// External library, Boost, for easier parsing of CLI arguments to the binary
#include <boost/program_options.hpp>

// Coyote-specific includes
#include <coyote/cThread.hpp>
#include <coyote/cRcnfg.hpp>

// Default (physical) FPGA device for nodes with multiple FPGAs
#define DEFAULT_DEVICE 0

// Default vFPGA to assign cThreads to
#define DEFAULT_VFPGA_ID 0

//////////////////////////////////////////////////////
// Source code from Example 2: HLS Vector Addition //
////////////////////////////////////////////////////
#define VECTOR_ELEMENTS 1024

void run_hls_vadd() {
    coyote::cThread coyote_thread(DEFAULT_VFPGA_ID, getpid());
    float *a = (float *) coyote_thread.getMem({coyote::CoyoteAllocType::HPF, VECTOR_ELEMENTS * (uint) sizeof(float) });
    float *b = (float *) coyote_thread.getMem({coyote::CoyoteAllocType::HPF, VECTOR_ELEMENTS * (uint) sizeof(float) });
    float *c = (float *) coyote_thread.getMem({coyote::CoyoteAllocType::HPF, VECTOR_ELEMENTS * (uint) sizeof(float) });
    if (!a || !b || !c) { throw std::runtime_error("Could not allocate memory for vectors, exiting..."); }

    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_real_distribution<float> dis(-512.0, 512.0); 
    for (int i = 0; i < VECTOR_ELEMENTS; i++) {
        a[i] = dis(gen);    
        b[i] = dis(gen);
        c[i] = 0;                        
    }

    coyote::localSg sg_a = {.addr = a, .len = VECTOR_ELEMENTS * (uint) sizeof(float), .dest = 0};
    coyote::localSg sg_b = {.addr = b, .len = VECTOR_ELEMENTS * (uint) sizeof(float), .dest = 1};
    coyote::localSg sg_c = {.addr = c, .len = VECTOR_ELEMENTS * (uint) sizeof(float), .dest = 0};

    coyote_thread.invoke(coyote::CoyoteOper::LOCAL_READ,  sg_a);
    coyote_thread.invoke(coyote::CoyoteOper::LOCAL_READ,  sg_b);
    coyote_thread.invoke(coyote::CoyoteOper::LOCAL_WRITE, sg_c);
    while (
        coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != 1 || 
        coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_READ) != 2
    ) {}

    for (int i = 0; i < VECTOR_ELEMENTS; i++) { assert((a[i] + b[i]) == c[i]); }
    std::cout << "HLS Vector Addition completed successfully!" << std::endl << std::endl;
}

//////////////////////////////////////////////////
// Source code from Example 4: User Interrupts //
////////////////////////////////////////////////
#define INTERRUPT_TRANSFER_SIZE_BYTES 64

void interrupt_callback(int value) {
    std::cout << "Hello from my interrupt callback! The interrupt received a value: " << value << std::endl << std::endl;
}

void run_user_interrupts() {
    coyote::cThread coyote_thread(DEFAULT_VFPGA_ID, getpid(), DEFAULT_DEVICE, interrupt_callback);
    int *data = (int *) coyote_thread.getMem({coyote::CoyoteAllocType::REG, INTERRUPT_TRANSFER_SIZE_BYTES});
    coyote::localSg sg = {.addr = data, .len = INTERRUPT_TRANSFER_SIZE_BYTES};

    data[0] = 73;
    std::cout << "I am now starting a data transfer which will cause an interrupt..." << std::endl;
    coyote_thread.invoke(coyote::CoyoteOper::LOCAL_READ, sg);

    while (!coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_READ)) {}
    coyote_thread.clearCompleted();

    // Short delay, to avoid triggering the reconfiguration before the interrupt has been processed
    sleep(1);
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
        // To reconfigure, we need to create an instance of cRcnfg for the target (physical) FPGA device
        coyote::cRcnfg rcnfg(DEFAULT_DEVICE);
        std::cout << "Reconfiguring the shell with bitstream: " << bitstream_path << std::endl;
        
        // Then, trigger shell reconfiguration
        auto begin_time = std::chrono::high_resolution_clock::now();
        rcnfg.reconfigureShell(bitstream_path);
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
