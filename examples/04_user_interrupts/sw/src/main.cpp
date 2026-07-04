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

#include <iostream>

// Coyote-specific includes
#include <coyote/cThread.hpp>

// Data size in bytes; corresponds to 512 bits, which is the default AXI stream bit width in Coyote
#define DATA_SIZE_BYTES 64

// Default vFPGA to assign cThreads to
#define DEFAULT_VFPGA_ID 0

// Interrupts callback; this function is called when the vFPGA issues an interrupt
// This is a very simple interrupt, that simple prints the interrupt value sent by the vFPGA
// NOTE: This function runs on a separate thread; so the stdout prints might be out-of-order relative to the main thread
void interrupt_callback(int value) {
    std::cout << "Hello from my interrupt callback! The interrupt received a value: " << value << std::endl << std::endl;
}

int main(int argc, char *argv[])  { 
    // Obtain a Coyote thread; zero corresponds to the target FPGA card (only relavant for systems that have multiple FPGAs)
    // Note, now, how the above-defined interrupt_callback method is passed to cThread constructors as a parameter
    coyote::cThread coyote_thread(DEFAULT_VFPGA_ID, getpid(), 0, interrupt_callback);

    // Allocate & initialise data
    int *data = (int *) coyote_thread.getMem({coyote::CoyoteAllocType::REG, DATA_SIZE_BYTES});
    for (int i = 0; i < DATA_SIZE_BYTES / sizeof(int); i++) {
        data[i] = i;
    }

    // Initialise the SG entry 
    coyote::localSg sg = { .addr = data, .len = DATA_SIZE_BYTES };

    // Run a test that will issue an interrupt
    data[0] = 73;
    std::cout << std::endl << "I am now starting a data transfer which will cause an interrupt..." << std::endl;
    coyote_thread.invoke(coyote::CoyoteOper::LOCAL_READ, sg);

    // Poll on completion of the transfer & once complete, clear
    while (!coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_READ)) {}
    coyote_thread.clearCompleted();

    // Short delay for demonstration purposes; keeps the two cases separate and the output readable
    sleep(1);
    
    // Now, run a case which won't issue an interrupt
    data[0] = 1024;
    std::cout << "I am now starting a data transfer which shouldn't cause an interrupt..." << std::endl;
    coyote_thread.invoke(coyote::CoyoteOper::LOCAL_READ, sg);
    while (!coyote_thread.checkCompleted(coyote::CoyoteOper::LOCAL_READ)) {}
    coyote_thread.clearCompleted();
    std::cout << "And, as promised, there was no interrupt!" << std::endl << std::endl;

    return EXIT_SUCCESS;
}
