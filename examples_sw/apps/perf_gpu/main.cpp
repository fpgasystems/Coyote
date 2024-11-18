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
#ifdef EN_AVX
#include <x86intrin.h>
#endif
#include <signal.h> 
#include <boost/program_options.hpp>
#include <any>
#ifdef EN_DMABUFF
#include <hip/hip_runtime.h>
#include <hsa/hsa_ext_amd.h>
#include <hsa.h>
#include <hsa/hsa_ext_finalize.h>
#include <hsakmt/hsakmt.h>
#endif

#include "cBench.hpp"
#include "cThread.hpp"

#define EN_THR_TESTS
#define EN_LAT_TESTS

using namespace std;
using namespace std::chrono;
using namespace fpga;

/* Signal handler */
std::atomic<bool> stalled(false); 
void gotInt(int) {
    stalled.store(true);
}

/* Def params */
constexpr auto const targetVfid = 0;
constexpr auto const defFpgaDevice = 0;
constexpr auto const defGpuDevice = 0;
constexpr auto const nReps = 1;
constexpr auto const defMinSize = 1 * 1024;
constexpr auto const defMaxSize = 128 * 1024 * 1024;
constexpr auto const nBenchRuns = 1;

/**
 * @brief Validation tests
 * 
 */
int main(int argc, char *argv[])  
{
    // ---------------------------------------------------------------
    // Args 
    // ---------------------------------------------------------------

    // Sig handler
    struct sigaction sa;
    memset( &sa, 0, sizeof(sa) );
    sa.sa_handler = gotInt;
    sigfillset(&sa.sa_mask);
    sigaction(SIGINT,&sa,NULL);

    // Read arguments
    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options()
        ("fdevice,f", boost::program_options::value<uint32_t>(), "Target FPGA device")
        ("gdevice,g", boost::program_options::value<uint32_t>(), "Target GPU device")
        ("bitstream,b", boost::program_options::value<string>(), "Shell bitstream")
        ("reps,r", boost::program_options::value<uint32_t>(), "Number of repetitions")
        ("min_size,n", boost::program_options::value<uint32_t>(), "Starting transfer size")
        ("max_size,x", boost::program_options::value<uint32_t>(), "Ending transfer size");
    
    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    string bstream_path = "";
    uint32_t f_dev = defFpgaDevice; 
    uint32_t g_dev = defGpuDevice; 
    uint32_t n_reps = nReps;
    uint32_t min_size = defMinSize;
    uint32_t max_size = defMaxSize;
    double time;

    if(commandLineArgs.count("fdevice") > 0) f_dev = commandLineArgs["fdevice"].as<uint32_t>();
    if(commandLineArgs.count("fdevice") > 0) f_dev = commandLineArgs["gdevice"].as<uint32_t>();
    if(commandLineArgs.count("bitstream") > 0) { 
        bstream_path = commandLineArgs["bitstream"].as<string>();
        
        std::cout << std::endl << "Shell loading (path: " << bstream_path << ") ..." << std::endl;
        cRnfg crnfg(f_dev);
        crnfg.shellReconfigure(bstream_path);
    }
    if(commandLineArgs.count("reps") > 0) n_reps = commandLineArgs["reps"].as<uint32_t>();
    if(commandLineArgs.count("min_size") > 0) min_size = commandLineArgs["min_size"].as<uint32_t>();
    if(commandLineArgs.count("max_size") > 0) max_size = commandLineArgs["max_size"].as<uint32_t>();

    PR_HEADER("PARAMS");
    std::cout << "FPGA device: " << f_dev << std::endl;
    std::cout << "GPU device: " << g_dev << std::endl;
    std::cout << "Min transfer size: " << min_size << std::endl;
    std::cout << "Max transfer size: " << max_size << std::endl;

    // ---------------------------------------------------------------
    // Init 
    // ---------------------------------------------------------------

    //
    // Handles

    // FPGA
    auto cthread = std::make_unique<cThread<std::any>>(targetVfid, getpid(), f_dev);
    
    // GPU
    int err = hipSetDevice(g_dev); // Just simple way to select the GPU without changing too many variables. agentID=3 -> deviceID=2 -> gpuID=0
	if(err != 0) {
		std::cout<<"Value of err: " << err << std::endl;
		throw std::runtime_error("Wrong GPU selection!");
	}
    
    // 
    // Mem
    
    // Host
    auto cSMem = cthread->getMem({CoyoteAlloc::HPF, max_size});
    std::generate_n((uint8_t*)cSMem, max_size, std::rand);
    auto cDMem = cthread->getMem({CoyoteAlloc::HPF, max_size});
    
    // Gpu
    auto gSMem = cthread->getMem({CoyoteAlloc::GPU, max_size, false, g_dev});
    auto gDMem = cthread->getMem({CoyoteAlloc::GPU, max_size, false, g_dev});

    // ---------------------------------------------------------------
    // Runs 
    // ---------------------------------------------------------------
    
    PR_HEADER("PERF GPU <-> FPGA");
    uint32_t curr_size = min_size;
    while(curr_size <= max_size) {
        
        // Init Gpu buffs
        auto start = std::chrono::high_resolution_clock::now();
        hipMemcpy(gSMem, cSMem, curr_size, hipMemcpyHostToDevice); 
        auto end = std::chrono::high_resolution_clock::now();
        time = (std::chrono::duration_cast<std::chrono::microseconds>(end-start).count());
        
        std::cout << std::fixed << std::setprecision(2);
        std::cout << "S: " << std::setw(10) << curr_size << ", T [H>G]: " << std::setw(10) << time << " us";
        hipMemset(gDMem, 0x0, curr_size);
        
        // Copy through the FPGA
        sgEntry sg; memset(&sg, 0, sizeof(localSg));
        sg.local.src_addr = gSMem; sg.local.src_len = curr_size; sg.local.src_stream = strmHost;
        sg.local.dst_addr = gDMem; sg.local.dst_len = curr_size; sg.local.dst_stream = strmHost;

        start = std::chrono::high_resolution_clock::now();
        cthread->invoke(CoyoteOper::LOCAL_TRANSFER, &sg, {true, true});
        while(!cthread->checkCompleted(CoyoteOper::LOCAL_TRANSFER)) {}
        end = std::chrono::high_resolution_clock::now();
        time = (std::chrono::duration_cast<std::chrono::microseconds>(end-start).count());
        std::cout << ", [G>F>G]: " << std::setw(10) << time << " us";
        double throughput_gfg = (double)curr_size / (time);

        // Move back to host from GPU
        start = std::chrono::high_resolution_clock::now();
        hipMemcpy(cDMem, gDMem, curr_size, hipMemcpyDeviceToHost);
        end = std::chrono::high_resolution_clock::now();
        time = (std::chrono::duration_cast<std::chrono::microseconds>(end-start).count());
        std::cout << ", [G>H]: " << std::setw(10) << time << " us";

        // Loop through host
        sg.local.src_addr = cSMem;
        sg.local.dst_addr = cDMem;

        start = std::chrono::high_resolution_clock::now();
        cthread->invoke(CoyoteOper::LOCAL_TRANSFER, &sg, {true, true});
        while(!cthread->checkCompleted(CoyoteOper::LOCAL_TRANSFER)) {}
        end = std::chrono::high_resolution_clock::now();
        time = (std::chrono::duration_cast<std::chrono::microseconds>(end-start).count());
        std::cout << ", [H>F>H]: " << std::setw(10) << time << " us";
        double throughput_hfh = (double)curr_size / (time);

        std::cout << ", T: [G>F>G]: " << std::setw(10) << throughput_gfg << " MB/s";
        std::cout << ", [H>F>H]: " << std::setw(10) << throughput_hfh << " MB/s" << std::endl;

        curr_size *= 2;
    }

    std::cout << std::endl << "All transfers completed successfully!" << std::endl;

    // Cleanup TODO: Do we need anything here?
    cthread->freeMem(gSMem);
    cthread->freeMem(gDMem);
    cthread->freeMem(cSMem);
    cthread->freeMem(cDMem);

    return EXIT_SUCCESS;
}
