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

#include <dirent.h>
#include <iterator>
#include <cstdlib>
#include <cstring>
#include <sstream>
#include <iostream>
#include <stdlib.h>
#include <string>
#include <sys/stat.h>
#include <syslog.h>
#include <unistd.h>
#include <vector>
#include <signal.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <iomanip>
#include <chrono>
#include <thread>
#include <limits>
#include <assert.h>
#include <stdio.h>
#include <sys/un.h>
#include <errno.h>
#include <wait.h>
#include <vector>
#include <unordered_map>
#include <mutex>
#include <condition_variable>
#include <boost/program_options.hpp>

#include "cService.hpp"
#include "cFunc.hpp"
#include "types.hpp"
#include "cBench.hpp"

using namespace std;
using namespace fpga;

/* Def params */
constexpr auto const defDevice = 0;
constexpr auto const defTargetVfid = 0;

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
        ("device,d", boost::program_options::value<uint32_t>(), "Target device")
        ("vfid,i", boost::program_options::value<uint32_t>(), "Target vFPGA");

    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    uint32_t cs_dev = defDevice; 
    uint32_t vfid = defTargetVfid;

    if(commandLineArgs.count("device") > 0) cs_dev = commandLineArgs["device"].as<uint32_t>();
    if(commandLineArgs.count("vfid") > 0) vfid = commandLineArgs["vfid"].as<uint32_t>();

    /**
     * @brief Load all service functions and start the server
     * 
     * Instantiate a daemon for the server-side of RDMA: "remote" is set to true 
     * 
    */
    # ifdef VERBOSE
        std::cout << "rdma_server: Get an instance of the cService for rdma with vfid " << vfid << " and for device " << cs_dev << std::endl; 
    # endif
    cService *cservice = cService::getInstance("rdma", true, vfid, cs_dev, nullptr, defPort);

    //std::cout << std::endl << "Shell loading ..." << std::endl << std::endl;
    //cservice->shellReconfigure("shell_bstream.bin");
    
    // RDMA perf: Add a new function for execution to the cService, which takes the experiment parameters as input for the lambda-function 
    # ifdef VERBOSE
        std::cout << "rdma_server: Add a function for experiment-execution." << std::endl; 
    # endif
    cservice->addFunction(fidRDMA, std::unique_ptr<bFunc>(new cFunc<int, bool, uint32_t, uint32_t, uint32_t, uint32_t>(operatorRDMA,
        [=] (cThread<int> *cthread, bool rdwr, uint32_t min_size, uint32_t max_size, uint32_t n_reps_thr, uint32_t n_reps_lat) -> int { 
            syslog(LOG_NOTICE, "Executing RDMA benchmark, %s, min_size %d, max_size %d, n_reps_thr %d, n_reps_lat %d", 
                (rdwr ? "RDMA WRITE" : "RDMA READ"), min_size, max_size, n_reps_thr, n_reps_lat);       

            // SG entries
            # ifdef VERBOSE
                std::cout << "rdma_server: Create a sg-Entry for the RDMA-operation." << std::endl; 
            # endif

            sgEntry sg;
            memset(&sg, 0, sizeof(rdmaSg));
            sg.rdma.len = min_size; sg.rdma.local_stream = strmHost;

            while(sg.rdma.len <= max_size) {
                // Sync via the cThread that is part of the cService-daemon that was just started in the background 
                # ifdef VERBOSE
                    std::cout << "rdma_server: Perform a clear Completed in cThread." << std::endl; 
                # endif 
                cthread->clearCompleted();
                # ifdef VERBOSE
                    std::cout << "rdma_server: Perform a connection sync in cThread." << std::endl; 
                # endif
                cthread->connSync(false);
                

                if(rdwr) {
                    // THR - wait until all expected WRITEs are coming in. Incoming RDMA_WRITEs are LOCAL_WRITEs on this side 
                    while(cthread->checkCompleted(CoyoteOper::LOCAL_WRITE) < n_reps_thr) { }
                    
                    // THR - issuing the same amount of "Write-Backs" to the client 
                    for(int i = 0; i < n_reps_thr; i++)
                        # ifdef VERBOSE 
                            std::cout << "rdma_server: invoke the operation " << std::endl; 
                        # endif
                        cthread->invoke(CoyoteOper::REMOTE_RDMA_WRITE, &sg);

                    // Sync via the thread that is located within the cService-daemon 
                    # ifdef VERBOSE
                        std::cout << "rdma_server: Perform a clearCompleted." << std::endl; 
                    # endif
                    cthread->clearCompleted();
                    # ifdef VERBOSE
                        std::cout << "rdma_server: Perform a connection sync in cThread." << std::endl; 
                    # endif
                    cthread->connSync(false);

                    // LAT - iterate over the number of ping-pong-exchanges according to the desired experiment setting 
                    for(int i = 0; i < n_reps_lat; i++) {
                        // Wait for the next incoming WRITE 
                        while(cthread->checkCompleted(CoyoteOper::LOCAL_WRITE) < i+1) { }
                        cthread->invoke(CoyoteOper::REMOTE_RDMA_WRITE, &sg);
                    }
                } else {
                    // Read
                    cthread->connSync(false);
                }

                sg.rdma.len *= 2;
            }

            cthread->connSync(false);

            syslog(LOG_NOTICE, "RDMA benchmark executed");
            return 0;
        }
    )));

    //
    // Start a daemon
    //
    std::cout << "Forking ..." << std::endl << std::endl;
    # ifdef VERBOSE
        std::cout << "rdma_server: Start the background daemon." << std::endl; 
    # endif
    cservice->start();
}

