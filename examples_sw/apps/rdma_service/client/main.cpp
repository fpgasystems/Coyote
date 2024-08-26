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

    string bstream_path = "";
    uint32_t cs_dev = defDevice; 
    uint32_t vfid = defTargetVfid;
    string tcp_ip;
    bool oper = defOper;
    uint32_t min_size = defMinSize;
    uint32_t max_size = defMaxSize;
    uint32_t n_reps_thr = defNRepsThr;
    uint32_t n_reps_lat = defNRepsLat;

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

    // Get a thread ...
    cThread<int> cthread(defTargetVfid, getpid(), cs_dev);
    cthread.getMem({CoyoteAlloc::HPF, max_size, true});

    // Connect to the RDMA server and run the task
    cLib<int, bool, uint32_t, uint32_t, uint32_t, uint32_t> clib_rdma("/tmp/coyote-daemon-vfid-0-rdma", 
        fidRDMA, &cthread, tcp_ip.c_str(), defPort); 

    clib_rdma.iTask(opPriority, oper, min_size, max_size, n_reps_thr, n_reps_lat);

    // Benchmark the RDMA

    // SG entries
    sgEntry sg;
    memset(&sg, 0, sizeof(rdmaSg));
    sg.rdma.len = min_size; sg.rdma.local_stream = strmHost;
    CoyoteOper coper = oper ? CoyoteOper::REMOTE_RDMA_WRITE : CoyoteOper::REMOTE_RDMA_READ;;

    PR_HEADER("RDMA BENCHMARK");
    
    while(sg.rdma.len <= max_size) {
        // Sync
        cthread.clearCompleted();
        cthread.connSync(true);
        cBench bench(1);

        auto benchmark_thr = [&]() {
            for(int i = 0; i < n_reps_thr; i++)
                cthread.invoke(coper, &sg);

            while(cthread.checkCompleted(CoyoteOper::LOCAL_WRITE) < n_reps_thr) { 
                if( stalled.load() ) throw std::runtime_error("Stalled, SIGINT caught");
            }
            
        };  
        bench.runtime(benchmark_thr);
        std::cout << std::fixed << std::setprecision(2);
        std::cout << std::setw(8) << sg.rdma.len << " [bytes], thoughput: " 
                    << std::setw(8) << ((1 + oper) * ((1000 * sg.rdma.len ))) / ((bench.getAvg()) / n_reps_thr) << " [MB/s], latency: ";

        // Sync
        cthread.clearCompleted();
        cthread.connSync(true); 
        
        auto benchmark_lat = [&]() {
            for(int i = 0; i < n_reps_lat; i++) {
                cthread.invoke(coper, &sg);
                while(cthread.checkCompleted(CoyoteOper::LOCAL_WRITE) < i+1) { 
                    if( stalled.load() ) throw std::runtime_error("Stalled, SIGINT caught");
                }
            }
        };
        bench.runtime(benchmark_lat);
	    std::cout << (bench.getAvg()) / (n_reps_lat * (1 + oper)) << " [ns]" << std::endl;
        
        sg.rdma.len *= 2;
    }

    std::cout << std::endl;

    cthread.connSync(true);

    int ret_val = clib_rdma.iCmpl();
        
    return (ret_val);
}
