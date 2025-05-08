

#include <chrono>

#include "cFunc.hpp"
#include "cService.hpp"

#include "constants.hpp"  

int main(int argc, char *argv[]) {
    ///////////////////////////////////////////////////////////
    //              Register service & load shell           //   
    //////////////////////////////////////////////////////////
    // Creates an instance of a background Coyote service that can host multiple functions
    coyote::cService *cservice = coyote::cService::getInstance("pr-example", false, DEFAULT_VFPGA_ID, DEFAULT_DEVICE);
    
    std::cout << "Loading shell..." << std::endl;
    cservice->reconfigureShell("shell_top.bin");

    ///////////////////////////////////////////////////////////
    //              Euclidean distance task                 //   
    //////////////////////////////////////////////////////////
    // For the Euclidean operator, add the target partial bitstream (found inside hw/build/bitstreams/config_0/vfpga_c0_0.bin and renamed to app_euclidean_distance.bin)
    cservice->addBitstream("app_euclidean_distance.bin", OP_EUCLIDEAN_DISTANCE);
    
    /* 
     * The following code registers a function for calculating the Euclidean distance between two vectors on the FPGA
     * Each function is identified by a unique function ID and the corresponding software code  (cFunc) to execute it
     * The cFunc is defined with a lambda expression, which captures the necessary parameters and performs the computation
     * The function takes in pointers (as uint64_t memory addresses) to the input and output vectors, and the vector size
     */
    cservice->addFunction(
        OP_EUCLIDEAN_DISTANCE, std::unique_ptr<coyote::bFunc>(new coyote::cFunc<double, uint64_t, uint64_t, uint64_t, uint>(OP_EUCLIDEAN_DISTANCE,
        [=] (coyote::cThread<double> *coyote_thread, uint64_t ptr_a, uint64_t ptr_b, uint64_t ptr_c, uint size) -> double {
            syslog(
                LOG_NOTICE, 
                "Calculating Euclidean distance; params: a %lx, b %lx, c %lx, size %d", 
                ptr_a, ptr_b, ptr_c, size
            );
            
            // Cast uint64_t (corresponding to a memory address) to float pointers
            float *a = (float *) ptr_a;
            float *b = (float *) ptr_b;
            float *c = (float *) ptr_c;

            // Create the SG entries for the two input vectors and the result
            // The output is a single float (the distance), whereas the inputs are vectors of floats (with arbitrary, user-specified size)
            coyote::sgEntry sg_a, sg_b, sg_c;
            sg_a.local = {.src_addr = a, .src_len = size * (uint) sizeof(float), .src_dest = 0};
            sg_b.local = {.src_addr = b, .src_len = size * (uint) sizeof(float), .src_dest = 1};
            sg_c.local = {.dst_addr = c, .dst_len = (uint) sizeof(float), .dst_dest = 0};
            
            // Map the user memory to the FPGA TLBs; this can be omitted
            // If omitted, we will have a page fault during the invoke operation, as explained in Example 1
            coyote_thread->userMap(a, size * (uint) sizeof(float));
            coyote_thread->userMap(b, size * (uint) sizeof(float));
            coyote_thread->userMap(c, (uint) sizeof(float));

            // Places a new request in the request queue, for the given operator ID and priority
            // The scheduler will load the necessary bitstream (as specified above) once the request is at the top of the queue
            coyote_thread->pLock(OP_EUCLIDEAN_DISTANCE, DEFAULT_OPERATOR_PRIORITY); 
            
            // Invoke the kernel and wait for it to finish; the syntax is the same as in all the other examples (e.g., Example 2: HLS Vector Add)
            auto begin_time = chrono::high_resolution_clock::now();
            coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ,  &sg_a);
            coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ,  &sg_b);
            coyote_thread->invoke(coyote::CoyoteOper::LOCAL_WRITE, &sg_c);
            while (
                coyote_thread->checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != 1 || 
                coyote_thread->checkCompleted(coyote::CoyoteOper::LOCAL_READ) != 2
            ) {}
            auto end_time = chrono::high_resolution_clock::now();
            double time = chrono::duration_cast<std::chrono::microseconds>(end_time - begin_time).count();

            // Unlock
            coyote_thread->pUnlock();

            // Unmap the user memory from the FPGA TLBs
            coyote_thread->userUnmap(a);
            coyote_thread->userUnmap(b);
            coyote_thread->userUnmap(c);

            syslog(LOG_NOTICE, "Euclidean distance caluclated, time taken %f us", time);
            return { time };
        }
    )));

    ///////////////////////////////////////////////////////////
    //              Cosine similarity task                  //   
    //////////////////////////////////////////////////////////
    // The following is largely the same as the Euclidean distance task, but for the cosine similarity operator
    // Since the two operators have the same input and output types, most of the code is reused
    cservice->addBitstream("app_cosine_similarity.bin", OP_COSINE_SIMILARITY);
    
    cservice->addFunction(
        OP_COSINE_SIMILARITY, std::unique_ptr<coyote::bFunc>(new coyote::cFunc<double, uint64_t, uint64_t, uint64_t, uint>(OP_COSINE_SIMILARITY,
        [=] (coyote::cThread<double> *coyote_thread, uint64_t ptr_a, uint64_t ptr_b, uint64_t ptr_c, uint size) -> double {
            syslog(
                LOG_NOTICE, 
                "Calculating cosine similarity; params: a %lx, b %lx, c %lx, size %d", 
                ptr_a, ptr_b, ptr_c, size
            );
            
            float *a = (float *) ptr_a;
            float *b = (float *) ptr_b;
            float *c = (float *) ptr_c;

            coyote::sgEntry sg_a, sg_b, sg_c;
            sg_a.local = {.src_addr = a, .src_len = size * (uint) sizeof(float), .src_dest = 0};
            sg_b.local = {.src_addr = b, .src_len = size * (uint) sizeof(float), .src_dest = 1};
            sg_c.local = {.dst_addr = c, .dst_len = (uint) sizeof(float), .dst_dest = 0};
        
            coyote_thread->userMap(a, size * (uint) sizeof(float));
            coyote_thread->userMap(b, size * (uint) sizeof(float));
            coyote_thread->userMap(c, (uint) sizeof(float));

            coyote_thread->pLock(OP_COSINE_SIMILARITY, DEFAULT_OPERATOR_PRIORITY); 
            
            auto begin_time = chrono::high_resolution_clock::now();
            coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ,  &sg_a);
            coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ,  &sg_b);
            coyote_thread->invoke(coyote::CoyoteOper::LOCAL_WRITE, &sg_c);
            while (
                coyote_thread->checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != 1 || 
                coyote_thread->checkCompleted(coyote::CoyoteOper::LOCAL_READ) != 2
            ) {}
            auto end_time = chrono::high_resolution_clock::now();
            double time = chrono::duration_cast<std::chrono::microseconds>(end_time - begin_time).count();

            coyote_thread->pUnlock();

            coyote_thread->userUnmap(a);
            coyote_thread->userUnmap(b);
            coyote_thread->userUnmap(c);

            syslog(LOG_NOTICE, "Cosine similarity caluclated, time taken %f us", time);
            return { time };
        }
    )));
    
    // Start the background daemon
    std::cout << "Starting background daemon ..." << std::endl;
    cservice->start();
}
