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

// Runtime 
constexpr auto const defDevice = 0;
constexpr auto const defTargetVfid = 0;

constexpr auto const defOper = false; // read
constexpr auto const defMinSize = 1024; 
constexpr auto const defMaxSize = 64 * 1024; 
constexpr auto const defNRepsThr = 1000;
constexpr auto const defNRepsLat = 100;

int main(int argc, char *argv[]) 
{

    // -----------------------------------------------------------------------------------------------------------------------
    // Sig handler
    // -----------------------------------------------------------------------------------------------------------------------

    struct sigaction sa;
    memset( &sa, 0, sizeof(sa) );
    sa.sa_handler = gotInt;
    sigfillset(&sa.sa_mask);
    sigaction(SIGINT,&sa,NULL);

    // -----------------------------------------------------------------------------------------------------------------------
    // ARGS
    // -----------------------------------------------------------------------------------------------------------------------

    // Generates the command-line printout and deals with reading in the user-defined arguments for running the experiments 
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
        ("reps_lat,l", boost::program_options::value<uint32_t>(), "Number of reps, latency");

    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    // Set the default values to variables for further usage 
    string bstream_path = "";
    uint32_t cs_dev = defDevice; 
    uint32_t vfid = defTargetVfid;
    string tcp_ip;
    bool oper = defOper;
    uint32_t min_size = defMinSize;
    uint32_t max_size = defMaxSize;
    uint32_t n_reps_thr = defNRepsThr;
    uint32_t n_reps_lat = defNRepsLat;

    // Read the actual arguments from the command line and parse them to variables for further usage, for setting the experiment correctly 
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

    // -----------------------------------------------------------------------------------------------------------------------
    // RDMA client side
    // -----------------------------------------------------------------------------------------------------------------------

    // Get a thread for execution: Has the vFPGA-ID, host-process-ID of this calling process, and device number
    cThread<int> cthread(defTargetVfid, getpid(), cs_dev);
    # ifdef VERBOSE
        cout << "Created the cThread-object for the RDMA-server-main-code"; 
    # endif

    // Get memory in the max size of the experiment. Argument is a cs_alloc-struct: Huge Page, max size, is remote 
    // This operation attaches the buffer to the Thread, which is required for the cLib constructor for RDMA-capabilities
    cthread.getMem({CoyoteAlloc::HPF, max_size, true});

    // Connect to the RDMA server and run the task

    // This instantiates the communication library cLib with the name of the socket, function-ID (?), the executing cthread, the target IP-address and the target port
    // The constructor of the communication library also automatically does the meta-exchange of information in the beginning to connect the queue pairs from local and remote 
    cLib<int, bool, uint32_t, uint32_t, uint32_t, uint32_t> clib_rdma("/tmp/coyote-daemon-vfid-0-rdma", 
        fidRDMA, &cthread, tcp_ip.c_str(), defPort); 

    // Execute the iTask -> That goes to cLib and from there probably to cFunc for scheduling of the execution of the cThread
    clib_rdma.iTask(opPriority, oper, min_size, max_size, n_reps_thr, n_reps_lat);

    // Benchmark the RDMA

    // SG entries
    
    // Create a Scatter-Gather-Entry, save it in memory - size of the rdmaSg
    // How is this sg-element connected to the thread-attached buffer? Should be the vaddr, shouldn't it? 
    // There has to be a connection, since sg is handed over to the invoke-function, where the local_dest and offset is accessed 
    sgEntry sg;
    memset(&sg, 0, sizeof(rdmaSg));

    // Set properties of the Scatter-Gather-Entry: Min-Size (size to start the experiment with), Stream Host as origin of data to be used for the RDMA-experiment
    sg.rdma.len = min_size; 
    sg.rdma.local_stream = strmHost;

    // Set the Coyote Operation, which can either be a REMOTE_WRITE or a REMOTE_READ, depending on the settings for the experiment 
    CoyoteOper coper = oper ? CoyoteOper::REMOTE_RDMA_WRITE : CoyoteOper::REMOTE_RDMA_READ;;

    PR_HEADER("RDMA BENCHMARK");
    
    // Iterate over the experiment size (for incrementing size up to defined maximum)
    while(sg.rdma.len <= max_size) {

        // Sync
        // Clear the registers that hold information about completed functions 
        cthread.clearCompleted();
        // Initiate a sync between the remote nodes with handshaking via exchanged ACKs 
        cthread.connSync(true);
        // Initialize a benchmark-object to precisely benchmark the RDMA-execution. Number of executions is set to 1 (no further repetitions on this level), no calibration required, no distribution required. 
        cBench bench(1);

        // Lambda-function for throughput-benchmarking
        auto benchmark_thr = [&]() {
            // For the desired number of repetitions per size, invoke the cThread-Function with the coyote-Operation 
            for(int i = 0; i < n_reps_thr; i++)
                cthread.invoke(coper, &sg);

            // Check the number of completed RDMA-transactions, wait until all operations have been completed. Check for stalling in-between. 
            while(cthread.checkCompleted(CoyoteOper::LOCAL_WRITE) < n_reps_thr) { 
                // stalled is an atomic boolean used for event-handling (?) that would indicate a stalled operation
                if( stalled.load() ) throw std::runtime_error("Stalled, SIGINT caught");
            }
        };  

        // Execution of the throughput-lambda-function through the benchmarking-function to get timing
        bench.runtime(benchmark_thr);

        // Generate the required output based on the statistical data from the benchmarking tool 
        std::cout << std::fixed << std::setprecision(2);
        std::cout << std::setw(8) << sg.rdma.len << " [bytes], thoughput: " 
                    << std::setw(8) << ((1 + oper) * ((1000 * sg.rdma.len ))) / ((bench.getAvg()) / n_reps_thr) << " [MB/s], latency: ";

        // Sync - reset the completion counter from the thread, sync-up via ACK-handshakes 
        cthread.clearCompleted();
        cthread.connSync(true); 
        
        // Lambda-function for latency-benchmarking 
        auto benchmark_lat = [&]() {
            // Different than before: Issue one single command via invoke, then wait for its completion (ping-pong-scheme)
            // Repeated for the number of desired repetitions 
            for(int i = 0; i < n_reps_lat; i++) {
                cthread.invoke(coper, &sg);
                while(cthread.checkCompleted(CoyoteOper::LOCAL_WRITE) < i+1) { 
                    // As long as the completion is not yet received, check for a possible stall-event 
                    if( stalled.load() ) throw std::runtime_error("Stalled, SIGINT caught");
                }
            }
        };
        
        // Execution of the latency-lambda-function through the benchmarking-function to get the timing right 
        bench.runtime(benchmark_lat);
        
        // Generate the average time for the latency-test execution 
	    std::cout << (bench.getAvg()) / (n_reps_lat * (1 + oper)) << " [ns]" << std::endl;
        
        // Scale up the Scatter-Gather-length to get to the next step of the experiment 
        sg.rdma.len *= 2;
    }

    // End the printout 
    std::cout << std::endl;

    // Final connection sync via the thread-provided function
    cthread.connSync(true);

    // Try to obtain the completion event at the end - probably has to do with the iTask at the beginning? 
    int ret_val = clib_rdma.iCmpl();
        
    return (ret_val);
}
