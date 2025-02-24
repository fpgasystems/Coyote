#include <any>
#include <iostream>

// Coyote-specific includes
#include "cThread.hpp"

// Data size in bytes; corresponds to 512 bits, which is the default AXI stream bit width in Coyote
#define DATA_SIZE_BYTES 64

// Default vFPGA to assign cThreads to
#define DEFAULT_VFPGA_ID 0

// Interrupts callback; this function is called when the vFPGA issues an interrupt
// This is a very simple interrupt, that simple prints the interrupt value sent by the vFPGA
// NOTE: This function runs on a separate thread; so the stdout prints might be out-of-order relative to the main thread
void interrupt_callback(int value) {
    std::cout << "Hello from my interrupt callback! The interrupt received a value: " << value << std::endl;
}

int main(int argc, char *argv[])  { 
    // Obtain a Coyote thread
    // Note, now, how the above-defined interrupt_callback method is passed to cThread constructors as a parameter
    std::unique_ptr<coyote::cThread<std::any>> coyote_thread(
      new coyote::cThread<std::any>(DEFAULT_VFPGA_ID, getpid(), 0, nullptr, interrupt_callback)
    );

    // Allocate & initialise data
    int* data = (int *) coyote_thread->getMem({coyote::CoyoteAlloc::REG, DATA_SIZE_BYTES});
    for (int i = 0; i < DATA_SIZE_BYTES / sizeof(int); i++) {
      data[i] = i;
    }

    // Initialise the SG entry 
    coyote::sgEntry sg;
    sg.local = {.src_addr = data, .src_len = DATA_SIZE_BYTES};

    // Run a test that will issue an interrupt
    data[0] = 73;
    std::cout << "I am now starting a data transfer which will cause an interrupt..." << std::endl;
    coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ, &sg, {true, true, true});
    
    // Now, run a case which won't issue an interrupt
    data[0] = 1024;
    std::cout << "I am now starting a data transfer which shouldn't cause an interrupt..." << std::endl;
    coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ, &sg, {true, true, true});
    std::cout << "And, as promised, there was no interrupt!" << std::endl;
    
    return EXIT_SUCCESS;
}
