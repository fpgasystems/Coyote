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

#include <iostream>
#include <string>
#include <malloc.h>
#include <time.h> 
#include <sys/time.h>  
#include <chrono>
#include <fstream>
#include <fcntl.h>
#include <unistd.h>
#include <iomanip>
#include <x86intrin.h>
#include <boost/program_options.hpp>
#include <sys/socket.h>
#include <sys/un.h>
#include <sstream>
#include <sys/mman.h>
#include <signal.h> 
#include <atomic>

#include "cLib.hpp"
#include "types.hpp"
#include "cThread.hpp"
#include "cBench.hpp"

using namespace std;
using namespace fpga;

/* Signal handler */
std::atomic<bool> stalled(false); 
void gotInt(int) {
    stalled.store(true);
}

/* Def params */
constexpr auto const defDevice = 0;
constexpr auto const defTargetVfid = 0;

constexpr auto const defOper = false; // read
constexpr auto const defMinSize = 1024; 
constexpr auto const defMaxSize = 64 * 1024; 
constexpr auto const defNRepsThr = 1000;
constexpr auto const defNRepsLat = 100;
constexpr auto const defVerbose = false; 

/**
 * @brief Main
 *  
 */
int main(int argc, char *argv[]) 
{   
    /* Args
     *
     * Reading of input arguments for experiment execution 
     */
    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options()
        ("bitstream,b", boost::program_options::value<string>(), "Shell bitstream")
        ("device,d", boost::program_options::value<uint32_t>(), "Target device")
        ("vfid,i", boost::program_options::value<uint32_t>(), "Target vFPGA")
        ("tcpaddr,t", boost::program_options::value<string>(), "TCP conn IP")
        ("write,w", boost::program_options::value<bool>(), "Read(0)/Write(1)")
        ("min_size,n", boost::program_options::value<uint32_t>(), "Minimal transfer size")
        ("max_size,x", boost::program_options::value<uint32_t>(), "Maximum transfer size")
        ("reps_thr,r", boost::program_options::value<uint32_t>(), "Number of reps, throughput")
        ("reps_lat,l", boost::program_options::value<uint32_t>(), "Number of reps, latency")
        ("verbose,v", boost::program_options::value<bool>(), "Printout of single messages");

    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    // Set the default values for the input-determined parameters to have a fall-back in case input-values didn't work properly 
    string bstream_path = "";
    uint32_t cs_dev = defDevice; 
    uint32_t vfid = defTargetVfid;
    string tcp_ip;
    bool oper = defOper;
    uint32_t min_size = defMinSize;
    uint32_t max_size = defMaxSize;
    uint32_t n_reps_thr = defNRepsThr;
    uint32_t n_reps_lat = defNRepsLat;
    bool verbose = defVerbose; 

    // Read the actual arguments from the command line and parse them to variables for further usage 
    if(commandLineArgs.count("bitstream") > 0) { 
        bstream_path = commandLineArgs["bitstream"].as<string>();
        
        std::cout << std::endl << "Shell loading (path: " << bstream_path << ") ..." << std::endl;
        cRnfg crnfg(cs_dev);
        crnfg.shellReconfigure(bstream_path);
    }
    if(commandLineArgs.count("device") > 0) cs_dev = commandLineArgs["device"].as<uint32_t>();
    if(commandLineArgs.count("vfid") > 0) vfid = commandLineArgs["vfid"].as<uint32_t>();
    if(commandLineArgs.count("tcpaddr") > 0) {
        tcp_ip = commandLineArgs["tcpaddr"].as<string>();
    } else {
        std::cout << "Provide the TCP/IP address of the server" << std::endl;
        return (EXIT_FAILURE);
    }
    if(commandLineArgs.count("write") > 0) oper = commandLineArgs["write"].as<bool>();
    if(commandLineArgs.count("min_size") > 0) min_size = commandLineArgs["min_size"].as<uint32_t>();
    if(commandLineArgs.count("max_size") > 0) max_size = commandLineArgs["max_size"].as<uint32_t>();
    if(commandLineArgs.count("reps_thr") > 0) n_reps_thr = commandLineArgs["reps_thr"].as<uint32_t>();
    if(commandLineArgs.count("reps_lat") > 0) n_reps_lat = commandLineArgs["reps_lat"].as<uint32_t>();
    if(commandLineArgs.count("verbose") > 0) verbose = commandLineArgs["verbose"].as<bool>(); 

    //----------------------------------------------------------------
    // RDMA server side 
    // ---------------------------------------------------------------

    // Get a cthread for execution: Has the vFPGA-ID, host-process-ID of this calling process and device number 
    cThread<int> cthread(defTargetVfid, getpid(), cs_dev); 

    // Get Memory for this thread that can hold the maximum required buffer size for this experiment 
    cthread.getMem({CoyoteAlloc::HPF, max_size, true}); 

    // Instantiate the cLib specifically as server to initiate the RDMA-QP exchange 
    cLib<int, bool, uint32_t, uint32_t, uint32_t, uint32_t> clib_rdma("/tmp/coyote-daemon-vfid-0-rdma", fidRDMA, &cthread, tcp_ip.c_str(), defPort, false);

    // Create a scatter-gather entry for the RDMA-operations 
    sgEntry sg; 
    memset(&sg, 0, sizeof(rdmaSg)); 

    // Set properties of the Scatter-Gather Entry: Start with the minimum size as required by the params and select hostStream as data origin
    sg.rdma.len = min_size; 
    sg.rdma.local_stream = strmHost; 

    // Get a hmem to write values into the payload of the RDMA-packets. Uses the allocated RDMA-buffer starting at vaddr
    uint64_t *hMem = (uint64_t*)(cthread.getQpair()->local.vaddr); 

    PR_HEADER("RDMA BENCHMARK"); 


    //---------------------------------------------
    // Execution of the experiment 
    //---------------------------------------------

    // Iterate over rdma-buffer lengths up to the maximum required buffer size 
    while(sg.rdma.len <= max_size) {

        // Clear all registers for a clean start 
        cthread.clearCompleted(); 

        // Respond to sync-handshake from the client-side 
        cthread.connSync(false); 

        // Active participation of the server is only required for WRITE-tests (otherwise just responding.) Thus if-case here: 
        if(oper) {

            //------------------------------------------------
            // THROUGHPUT-TEST
            //------------------------------------------------

            // Wait until all expected throughput-WRITEs have been received 
            uint32_t number_of_completed_local_writes = 0; 
            while(cthread.checkCompleted(CoyoteOper::LOCAL_WRITE) < n_reps_thr) { 
                if(number_of_completed_local_writes != cthread.checkCompleted(CoyoteOper::LOCAL_WRITE)) {
                    if(verbose) {
                        std::cout << "SERVER: Received " << number_of_completed_local_writes << " LOCAL WRITES so far." << std::endl;
                    }
                }
                number_of_completed_local_writes = cthread.checkCompleted(CoyoteOper::LOCAL_WRITE); 
            }

            // Issue the same amount of REMOTE WRITEs to the other side 
            for(int i = 0; i < n_reps_thr; i++) {
                // Increment the hMem for increasing payload-numbers 
                hMem[sg.rdma.len/8-1] = hMem[sg.rdma.len/8-1] + 1; 

                // Isse the REMOTE WRITE 
                if(verbose) { 
                    std::cout << "SERVER: Sent out message #" << i << " at message size " << sg.rdma.len << " with content " << hMem[sg.rdma.len/8-1] + 1; 
                }
                cthread.invoke(CoyoteOper::REMOTE_RDMA_WRITE, &sg); 
            }

            // Clear all registers for a clean start of latency 
            cthread.clearCompleted(); 

            // Respond to sync-handshake from the client-side 
            cthread.connSync(false); 


            //-----------------------------------------------
            // LATENCY-TEST
            //-----------------------------------------------

            // Iterate over the number of ping-pong-exchanges according to the desired experiment setting 
            for(int i = 0; i < n_reps_lat; i++) {
                // Wait for the next incoming WRITE 
                bool message_written = false; 
                while(cthread.checkCompleted(CoyoteOper::LOCAL_WRITE) < i+1) {
                    if(!message_written) {
                        // std::cout << "RDMA-Server: Waiting for an incoming RDMA-WRITE at currently " << i << "." << std::endl;
                        message_written = true; 
                    }
                }

                // Increment the number in the payload before writing back 
                hMem[sg.rdma.len/8-1] = hMem[sg.rdma.len/8-1] + 1; 

                // Issuing a WRITE in the reverse direction to the client 
                // std::cout << "RDMA-Server: Invoking a RDMA-WRITE from the Server to the Client at currently " << (i+1) << "." << std::endl; 
                if(verbose) {
                    std::cout << "SERVER: Sent out message #" << i << " at message-size " << sg.rdma.len << " with content " << hMem[sg.rdma.len/8-1] << std::endl;
                }
                cthread.invoke(CoyoteOper::REMOTE_RDMA_WRITE, &sg);
            }
        } else {
            // In read-case, just execute the sync-handshake between throughput and latency 
            cthread.connSync(false); 
        }

        // Increment the RDMA-length
        sg.rdma.len *= 2; 
    }

    // Perform one last sync-handshake with the client 
    cthread.connSync(false); 

    return 0; 
}