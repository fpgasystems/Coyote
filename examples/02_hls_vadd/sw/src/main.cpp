#include <any>
#include <random>
#include <iostream>

// External library for easier parsing of CLI arguments by the executable
#include <boost/program_options.hpp>

// Coyote-specific includes
#include "cThread.hpp"

// Default vFPGA to assign cThreads to
#define DEFAULT_VFPGA_ID 0

int main(int argc, char *argv[]) {
    // CLI arguments
    uint size;
    boost::program_options::options_description runtime_options("Coyote HLS Vector Add Options");
    runtime_options.add_options()("size,s", boost::program_options::value<uint>(&size)->default_value(1024), "Vector size");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    PR_HEADER("Validation: HLS vector addition");
    std::cout << "Vector elements: " << size << std::endl;
    
    // Create a Coyote thread and allocate memory for the vectors
    std::unique_ptr<coyote::cThread<std::any>> coyote_thread(new coyote::cThread<std::any>(DEFAULT_VFPGA_ID, getpid(), 0));
    float *a = (float *) coyote_thread->getMem({coyote::CoyoteAlloc::HPF, size});
    float *b = (float *) coyote_thread->getMem({coyote::CoyoteAlloc::HPF, size});
    float *c = (float *) coyote_thread->getMem({coyote::CoyoteAlloc::HPF, size});
    if (!a || !b || !c) { throw std::runtime_error("Could not allocate memory for vectors, exiting..."); }

    // Initialise the input vectors to a random value between -512 and 512 (these are just arbitrary, any 32-bit FP number will work)
    // Also, initialise resulting vector to 0 (though this really doesn't matter; it will be overwritten by the FPGA)
    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_real_distribution<float> dis(-512.0, 512.0); 
    for (int i = 0; i < size; i++) {
        a[i] = dis(gen);    
        b[i] = dis(gen);
        c[i] = 0;                        
    }
    
    // Set scatter-gather flags; note transfer size is always in bytes, so multiply vector dimensionality with sizeof(float)
    // Note, how the vector b has a destination of 1; corresponding to the second AXI Stream (see README for more details)
    coyote::sgEntry sg_a, sg_b, sg_c;
    sg_a.local = {.src_addr = a, .src_len = size * (uint) sizeof(float), .src_dest = 0};
    sg_b.local = {.src_addr = b, .src_len = size * (uint) sizeof(float), .src_dest = 1};
    sg_c.local = {.dst_addr = c, .dst_len = size * (uint) sizeof(float), .dst_dest = 0};

    // Run kernel and wait until complete
    coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ,  &sg_a);
    coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ,  &sg_b);
    coyote_thread->invoke(coyote::CoyoteOper::LOCAL_WRITE, &sg_c);
    while (
        coyote_thread->checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != 1 || 
        coyote_thread->checkCompleted(coyote::CoyoteOper::LOCAL_READ) != 2
    ) {}

    // Verify correctness of the results
    for (int i = 0; i < size; i++) { assert(a[i] + b[i] == c[i]); }
    PR_HEADER("Validation passed!");
}
