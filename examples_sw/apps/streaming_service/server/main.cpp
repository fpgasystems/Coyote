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
#include "gbm_dtrees.hpp"

using namespace std;
using namespace fpga;

// Runtime
constexpr auto const devBus = "81";
constexpr auto const devSlot = "00";

constexpr auto const defTargetVfid = 0;

// Operators
constexpr auto const operatorHLL = 1;
constexpr auto const operatorDtrees = 2;

constexpr auto const opPriority = 1;

// Tuple width
constexpr auto const defDW = 4;

/**
 * @brief Main
 *  
 */
int main(int argc, char *argv[]) 
{   
    /* Args */
    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options()
        ("bus,b", boost::program_options::value<string>(), "Device bus")
        ("slot,s", boost::program_options::value<string>(), "Device slot")
        ("vfid,i", boost::program_options::value<uint32_t>(), "Target vFPGA");

    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    csDev cs_dev = { devBus, devSlot }; 
    uint32_t vfid = defTargetVfid;

    if(commandLineArgs.count("bus") > 0) cs_dev.bus = commandLineArgs["bus"].as<string>();
    if(commandLineArgs.count("slot") > 0) cs_dev.slot = commandLineArgs["slot"].as<string>();
    if(commandLineArgs.count("vfid") > 0) vfid = commandLineArgs["vfid"].as<uint32_t>();
    
    /* Create a daemon */
    cService *cservice = cService::getInstance(vfid, cs_dev);

    /**
     * @brief Load all operators
     * 
     */

    // Load application bitstreams
    cservice->addBitstream("app_bstream_hll.bin", operatorHLL);
    cservice->addBitstream("app_bstream_dtrees.bin", operatorDtrees);

    // Load HyperLogLog task
    cservice->addTask(operatorHLL, [] (cThread *cthread, std::vector<uint64_t> params) -> cmplVal { // addr, n_tuples -> exec. time
        /*
        void* dMem = (void*) params[0];
        void* rMem = (void*) params[1];
        uint32_t n_tuples = (uint32_t) params[2];
        
        // SG entries --------------------------------------------------------------------------------------------------
        // -------------------------------------------------------------------------------------------------------------
        sgEntry sg;
        csInvoke cs_invoke;
        
        memset(&sg, 0, sizeof(localSg));
        sg.local.src_addr = dMem; // Read
        sg.local.src_len = n_tuples * defDW;

        sg.local.dst_addr = rMem; // Write
        sg.local.dst_len = 64;

        // CS
        cs_invoke.oper = CoyoteOper::LOCAL_TRANSFER; // Rd + Wr
        cs_invoke.sg_list = &sg;
        cs_invoke.num_sge = 1;
        cs_invoke.sg_flags = {true, true, true}; // last, clr, poll

        // User map ----------------------------------------------------------------------------------------------------
        // -------------------------------------------------------------------------------------------------------------
        cthread->userMap(dMem, n_tuples * defDW);
        cthread->userMap(rMem, pageSize);
        
        // Lock vFPGA (scheduler will load the required bitstream if necessary) ----------------------------------------
        // -------------------------------------------------------------------------------------------------------------
        cthread->pLock(operatorHLL, opPriority); 

        // Invoke (move the data) --------------------------------------------------------------------------------------
        // -------------------------------------------------------------------------------------------------------------
        auto begin_time = chrono::high_resolution_clock::now();
        cthread->invoke(cs_invoke);
        auto end_time = chrono::high_resolution_clock::now();

        // Unlock vFPGA ------------------------------------------------------------------------------------------------
        // -------------------------------------------------------------------------------------------------------------
        cthread->pUnlock();

        // User unmap
        cthread->userUnmap((void*)params[0]);
        
        double time = chrono::duration_cast<std::chrono::microseconds>(end_time - begin_time).count();
        return { time };
        */
       syslog(LOG_NOTICE, "Task HLL executed");
       return { 0 };
    });

    // Load Decision trees task
    cservice->addTask(operatorDtrees, [] (cThread *cthread, std::vector<uint64_t> params) -> cmplVal { // addr, n_tuples, n_features -> exec. time
        
        /*
        void* dMem = (void*) params[0];
        void* rMem = (void*) params[1];

        // Prep the dtrees parameters ----------------------------------------------------------------------------------
        // -------------------------------------------------------------------------------------------------------------

        int32_t n_tuples = (int32_t) params[2];
        int32_t n_features = (int32_t) params[3];
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

        uint64_t n_trees_pages = trees_size/hugePageSize + ((trees_size%hugePageSize > 0)? 1 : 0);
        short lastOutLineMask = ((n_tuples%16) > 0)? 0xFFFF << (n_tuples%16) : 0x0000;

        // Allocate Trees Memory
        void* tMem = (uint64_t*) cthread->getMem({CoyoteAlloc::HPF, (uint32_t)n_trees_pages});

        // Initialize the trees ----------------------------------------------------------------------------------------
        // -------------------------------------------------------------------------------------------------------------
        initTrees(((uint*)(tMem)), numTrees, numnodes, depth);

        // SG entries (prep for model offload) -------------------------------------------------------------------------
        // -------------------------------------------------------------------------------------------------------------
        sgEntry sg;
        csInvoke cs_invoke;

        memset(&sg, 0, sizeof(localSg));
        sg.local.src_addr = tMem; // Read
        sg.local.src_len = (uint32_t) trees_size;

        // CS
        cs_invoke.oper = CoyoteOper::LOCAL_READ; // Rd
        cs_invoke.sg_list = &sg;
        cs_invoke.num_sge = 1;
        cs_invoke.sg_flags = {true, true, true}; // last, clr, poll

        // User map ----------------------------------------------------------------------------------------------------
        // -------------------------------------------------------------------------------------------------------------
        cthread->userMap(dMem, n_tuples * n_features * defDW);
        cthread->userMap(rMem, n_tuples * defDW);

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
        cthread->invoke(cs_invoke);


        // Stream data into the FPGA, non-blocking, initiate transfer in both directions (results writen back) ---------        
        // -------------------------------------------------------------------------------------------------------------
        sg.local.src_addr = dMem; // Read
        sg.local.src_len = (uint32_t) data_size;
        sg.local.dst_addr = rMem;
        sg.local.src_len = (uint32_t) result_size;
        cs_invoke.oper = CoyoteOper::LOCAL_TRANSFER; // Rd + Wr

        auto begin_time = chrono::high_resolution_clock::now();
        cthread->invoke(cs_invoke);
        auto end_time = chrono::high_resolution_clock::now();

        // Unlock vFPGA ------------------------------------------------------------------------------------------------
        // -------------------------------------------------------------------------------------------------------------
        cthread->pUnlock();

        // User unmap --------------------------------------------------------------------------------------------------
        // -------------------------------------------------------------------------------------------------------------
        cthread->userUnmap((void*)params[0]);

        double time = chrono::duration_cast<std::chrono::microseconds>(end_time - begin_time).count();
        return { time };
        */

       syslog(LOG_NOTICE, "Task Dtrees executed");
       return { 1 };
    });

    //
    // Run a daemon
    //
    cservice->run();
}

