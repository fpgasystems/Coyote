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
    /* Args */
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
    */
    cService *cservice = cService::getInstance("rdma", true, vfid, cs_dev, nullptr, defPort);
    //std::cout << std::endl << "Shell loading ..." << std::endl << std::endl;
    //cservice->shellReconfigure("shell_bstream.bin");
    
    // The Hyper-Log-Log task
    cservice->addFunction(fidRDMA, std::unique_ptr<bFunc>(new cFunc<int, bool, uint32_t, uint32_t, uint32_t, uint32_t>(operatorRDMA,
        [=] (cThread<int> *cthread, bool rdwr, uint32_t min_size, uint32_t max_size, uint32_t n_reps_thr, uint32_t n_reps_lat) -> int { 
            syslog(LOG_NOTICE, "Executing RDMA benchmark, %s, min_size %d, max_size %d, n_reps_thr %d, n_reps_lat %d", 
                (rdwr ? "RDMA WRITE" : "RDMA READ"), min_size, max_size, n_reps_thr, n_reps_lat);       

            // SG entries
            sgEntry sg;
            csInvoke cs_invoke;
            memset(&sg, 0, sizeof(rdmaSg));
            sg.rdma.len = min_size;
            sg.rdma.local_stream = strmHost;

            // CS
            cs_invoke.oper = CoyoteOper::REMOTE_RDMA_WRITE;
            cs_invoke.sg_list = &sg;
            cs_invoke.num_sge = 1;

            while(sg.rdma.len <= max_size) {
                // Sync
                cthread->clearCompleted();
                cthread->connSync(false);
                

                if(rdwr) {
                    // THR
                    while(cthread->checkCompleted(CoyoteOper::LOCAL_WRITE) < n_reps_thr) { }
                        
                    for(int i = 0; i < n_reps_thr; i++)
                        cthread->invoke(cs_invoke);

                    // Sync
                    cthread->clearCompleted();
                    cthread->connSync(false);

                    // LAT
                    for(int i = 0; i < n_reps_lat; i++) {
                        while(cthread->checkCompleted(CoyoteOper::LOCAL_WRITE) < i+1) { }
                        cthread->invoke(cs_invoke);
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
    cservice->start();
}

