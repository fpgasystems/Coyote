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
#include "gbm_dtrees.hpp"
#include "types.hpp"

using namespace std;
using namespace fpga;

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
    cService *cservice = cService::getInstance("streaming", false, vfid, cs_dev);
    std::cout << std::endl << "Shell loading ..." << std::endl << std::endl;
    cservice->shellReconfigure("shell_bstream.bin");

    /**
     * @brief Load all operators (partial images) into the scheduler and start the operation
     * 
     */

    cservice->addBitstream("app_bstream_hloglog.bin", operatorHLL);
    cservice->addBitstream("app_bstream_dtrees.bin", operatorDtrees);
    
    // The Hyper-Log-Log task
    cservice->addFunction(fidHLL, std::unique_ptr<bFunc>(new cFunc<double, uint64_t, uint64_t, uint32_t>(operatorHLL,
        [=] (cThread<double> *cthread, uint64_t d_mem, uint64_t r_mem, uint32_t n_tuples) -> double { // returns time
            void* dMem = (void*) d_mem;
            void* rMem = (void*) r_mem;

            syslog(LOG_NOTICE, "Executing HLL task, params: dMem %lx, rMem %lx, tuples %d", (uint64_t)dMem, (uint64_t)rMem, n_tuples);
            
            // SG entries --------------------------------------------------------------------------------------------------
            // -------------------------------------------------------------------------------------------------------------
            sgEntry sg;
            memset(&sg, 0, sizeof(localSg));
            sg.local.src_addr = dMem; sg.local.src_len = n_tuples * defDW;
            sg.local.dst_addr = rMem; sg.local.dst_len = defDW;

            // User map ----------------------------------------------------------------------------------------------------
            // -------------------------------------------------------------------------------------------------------------
            cthread->userMap(dMem, n_tuples * defDW);
            cthread->userMap(rMem, defDW);
            
            // Lock vFPGA (scheduler will load the required bitstream if necessary) ----------------------------------------
            // -------------------------------------------------------------------------------------------------------------
            cthread->pLock(operatorHLL, opPriority); 

            // Invoke (move the data) --------------------------------------------------------------------------------------
            // -------------------------------------------------------------------------------------------------------------
            auto begin_time = chrono::high_resolution_clock::now();
            cthread->invoke(CoyoteOper::LOCAL_TRANSFER, &sg, {true, true, true});
            auto end_time = chrono::high_resolution_clock::now();

            // Unlock vFPGA ------------------------------------------------------------------------------------------------
            // -------------------------------------------------------------------------------------------------------------
            cthread->pUnlock();

            // User unmap
            cthread->userUnmap(dMem);
            cthread->userUnmap(rMem);
            
            double time = chrono::duration_cast<std::chrono::microseconds>(end_time - begin_time).count();
            syslog(LOG_NOTICE, "Task HLL executed, time %f", time);
            
            return { time };
        }
    )));
    
    // Load Decision trees task
    cservice->addFunction(fidDtrees, std::unique_ptr<bFunc>(new cFunc<double, uint64_t, uint64_t, int32_t, int32_t>(operatorDtrees,
        [=] (cThread<double> *cthread, uint64_t d_mem, uint64_t r_mem, int32_t n_tuples, int32_t n_features) -> double { // returns time
        void* dMem = (void*) d_mem;
        void* rMem = (void*) r_mem;

        syslog(LOG_NOTICE, "Executing D-trees task, params: dMem %lx, rMem %lx, tuples %d, features %d", (uint64_t)dMem, (uint64_t)rMem, n_tuples, n_features);
        
        // Prep the dtrees parameters ----------------------------------------------------------------------------------
        // -------------------------------------------------------------------------------------------------------------
        int32_t depth = 5; 
        int32_t numTrees = 109; 

        int32_t result_size = defDW * n_tuples;
        int32_t data_size = n_features * n_tuples * defDW;

        uint outputNumCLs = result_size/64 + ((result_size%64 > 0)? 1 : 0);

        unsigned char puTrees = numTrees/28 + ((numTrees%28 == 0)? 0 : 1);

        int numnodes = pow(2, depth) - 1;
        int tree_size = 2*(pow(2,depth-1) - 1) + 10*pow(2,depth-1) + 1;
        tree_size = tree_size + ( ((tree_size%16) > 0)? 16 - (tree_size%16) : 0);

        int trees_size = tree_size*numTrees*4;

        //uint64_t n_trees_pages = trees_size/hugePageSize + ((trees_size%hugePageSize > 0)? 1 : 0);
        short lastOutLineMask = ((n_tuples%16) > 0)? 0xFFFF << (n_tuples%16) : 0x0000;
        
        // Initialize the trees ----------------------------------------------------------------------------------------
        // -------------------------------------------------------------------------------------------------------------
        std::unique_ptr<cThread<std::any>> cthread_model;
        void* tMem;

        // Allocate Trees Memory
        try {
            // Thread to offload the model
            cthread_model = std::make_unique<cThread<std::any>>(vfid, getpid(), cs_dev);
        } catch(...) {
            return { 0 };
        }

        tMem = cthread_model->getMem({CoyoteAlloc::HPF, (uint32_t)trees_size});
        initTrees(((uint32_t*)(tMem)), numTrees, numnodes, depth);

        // User map ----------------------------------------------------------------------------------------------------
        // -------------------------------------------------------------------------------------------------------------
        cthread->userMap(dMem, n_tuples * n_features * defDW);
        cthread->userMap(rMem, n_tuples * defDW);

        // SG entries (prep for model offload) -------------------------------------------------------------------------
        // -------------------------------------------------------------------------------------------------------------
        sgEntry sg;
        memset(&sg, 0, sizeof(localSg));
        sg.local.src_addr = tMem; sg.local.src_len = (uint32_t) trees_size;

        // Lock vFPGA (scheduler will load the required bitstream if necessary) ----------------------------------------
        // -------------------------------------------------------------------------------------------------------------
        cthread->pLock(operatorDtrees, opPriority);

        // Set HW kernel params ----------------------------------------------------------------------------------------
        // -------------------------------------------------------------------------------------------------------------
        cthread->setCSR(n_features,       1);
        cthread->setCSR(depth,            2);
        cthread->setCSR(puTrees,          3);
        cthread->setCSR(outputNumCLs,     4);
        cthread->setCSR(lastOutLineMask,  5);
        cthread->setCSR(0x1, 0); // ap_start

        // Push trees to the FPGA, blocking, returns when all trees have been streamed to the FPGA ---------------------
        // -------------------------------------------------------------------------------------------------------------
        //cthread->invoke(cs_invoke);
        cthread_model->invoke(CoyoteOper::LOCAL_READ, &sg, {true, true, true});


        // Stream data into the FPGA, blocking, initiate transfer in both directions (results writen back) -------------       
        // -------------------------------------------------------------------------------------------------------------
        sg.local.src_addr = dMem; // Read
        sg.local.src_len = (uint32_t) data_size;
        sg.local.dst_addr = rMem;
        sg.local.src_len = (uint32_t) result_size;

        auto begin_time = chrono::high_resolution_clock::now();
        cthread->invoke(CoyoteOper::LOCAL_TRANSFER, &sg, {true, true, true});
        auto end_time = chrono::high_resolution_clock::now();

        // Unlock vFPGA ------------------------------------------------------------------------------------------------
        // -------------------------------------------------------------------------------------------------------------
        cthread->pUnlock();

        // User unmap --------------------------------------------------------------------------------------------------
        // -------------------------------------------------------------------------------------------------------------
        cthread->userUnmap(dMem);
        cthread->userUnmap(rMem);
        cthread_model->freeMem(tMem);

        double time = chrono::duration_cast<std::chrono::microseconds>(end_time - begin_time).count();
        syslog(LOG_NOTICE, "Task D-trees executed, time %f", time);
        
        return { time };
    })));

    //
    // Start a daemon
    //
    std::cout << "Forking ..." << std::endl << std::endl;
    cservice->start();
}

