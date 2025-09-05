// Includes 
#include <any>
#include <chrono>
#include <thread>
#include <iostream>
#include <boost/program_options.hpp>

#include "cThread.hpp"

// Constants 
#define CLOCK_PERIOD_NS 4
#define DEFAULT_VFPGA_ID 0

#define N_LATENCY_REPS 1
#define N_THROUGHPUT_REPS 64

// Registers, corresponding to the AXI CTRL registers defined in the vFPGA
enum class BenchmarkRegisters: uint32_t {
    HOST_NETWORKING_VADDR_REG = 0,           // tart, read or write
    HOST_NETWORKING_PID_REG = 1
};

// Main function for the host networking example 
int main(int argc, char *argv[]) {
    
    // Obtain a Coyote thread for handling of the buffers 
    std::unique_ptr<coyote::cThread<std::any>> coyote_thread(new coyote::cThread<std::any>(DEFAULT_VFPGA_ID, getpid(), 0));

    // Allocate two buffers for RX and TX traffic 
    int *rx_mem, *tx_mem;
    rx_mem = (int *) coyote_thread->getMem({coyote::CoyoteAlloc::HPF, 4*1024*1024});
    tx_mem = (int *) coyote_thread->getMem({coyote::CoyoteAlloc::HPF, 4*1024*1024});

    // Exit if memory couldn't be allocated 
    if (!rx_mem || !tx_mem) { throw std::runtime_error("Could not allocate memory; exiting..."); }

    // Create a scatter-gather entry for the TX-stream for outgoing traffic 
    coyote::sgEntry sg; 
    sg.local = {.src_addr = tx_mem, .src_len=512}; // It should not be required to set the RX-buffer as it is served automatically by the FPGA 

    // Communicate the details of the RX-buffer to the vFPGA via the CTRL register 
    coyote_thread->setCSR(reinterpret_cast<uint64_t>(rx_mem), static_cast<uint32_t>(BenchmarkRegisters::HOST_NETWORKING_VADDR_REG)); // Set vaddr 
    coyote_thread->setCSR(coyote_thread->getCtid(), static_cast<uint32_t>(BenchmarkRegisters::HOST_NETWORKING_PID_REG)); // Set PID

    // Write a potential packet to the TX-buffer and then via a LOCAL_WRITE invoke to the FPGA and onto the Ethernet wire 
    /* for(int i = 0; i < 128; i++) {
        tx_mem[i] = i;
    } */ 

    tx_mem[0] = 0x0b350a00; 
    tx_mem[1] = 0x0a009824; 
    tx_mem[2] = 0x28250b35; 
    tx_mem[3] = 0x02450008; 
    tx_mem[4] = 0x00003010; 
    tx_mem[5] = 0x11640040; 
    tx_mem[6] = 0xfd0af55b; 
    tx_mem[7] = 0xfd0a684a; 
    tx_mem[8] = 0x3848644a; 
    tx_mem[9] = 0x1c10b712; 
    tx_mem[10] = 0x000d0000; 
    tx_mem[11] = 0x0000ffff; 
    tx_mem[12] = 0x00000000; 
    tx_mem[13] = 0x001f48cf;
    tx_mem[14] = 0x04d2ea19; 
    tx_mem[15] = 0x00000000;

    coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ, &sg); 

    // Afterwards: Print everything that is coming in via the RX-buffer 
    while(true) {
        // Print the data in the RX-buffer
        for(int i = 0; i < 128; i++) {
            std::cout << rx_mem[i] << " ";
            // sleep(1); 
        }
    }

    // Return value at the end
    return EXIT_SUCCESS;
}

