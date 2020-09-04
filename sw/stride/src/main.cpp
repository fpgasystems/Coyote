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
#include <random>

#include <x86intrin.h>

#include <boost/program_options.hpp>

#include "fDev.hpp"
#include "fView.hpp"
#include "fBench.hpp"

using namespace std;
using namespace std::chrono;
using namespace fpga;
using namespace comm;

/* Runtime */
#define N_NODES             2
#define N_PAGES             2
#define N_ID_MASTER         0
#define N_REGIONS           3
#define N_REPS              1
#define DEF_DWITDH          6
#define DEF_STRIDE          64
#define DEF_NELEM           1

int main(int argc, char *argv[])  
{
    // ---------------------------------------------------------------
    // -- Initialization 
    // ---------------------------------------------------------------
    const char* masterAddr = "10.1.212.121";

    // Read arguments
    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options()("nnodes,n", boost::program_options::value<uint32_t>(), "Number of system nodes")
                                    ("npages,p", boost::program_options::value<uint32_t>(), "Buffer size in 2MB pages")
                                    ("nodeid,i", boost::program_options::value<uint32_t>(), "Node ID")
                                    ("nregions,g", boost::program_options::value<uint32_t>(), "Number of FPGA regions")
                                    ("reps,r", boost::program_options::value<uint32_t>(), "Number of repetitions")
                                    ("dwidth,d", boost::program_options::value<uint32_t>(), "Data width")
                                    ("stride,s", boost::program_options::value<uint32_t>(), "Stride offset")
                                    ("elems,e", boost::program_options::value<uint32_t>(), "Number of elements");
    
    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    // Stat
    uint32_t n_nodes = N_NODES;
    uint64_t n_pages = N_PAGES;
    uint32_t node_id = N_ID_MASTER;
    uint32_t n_regions = N_REGIONS;
    // Runs
    uint32_t n_reps = N_REPS;
    uint32_t dwidth = DEF_DWITDH;
    uint32_t stride = DEF_STRIDE;
    uint32_t n_elem = DEF_NELEM;

    if(commandLineArgs.count("nnodes") > 0) n_nodes = commandLineArgs["nnodes"].as<uint32_t>();
    if(commandLineArgs.count("npages") > 0) n_pages = commandLineArgs["npages"].as<uint32_t>();
    if(commandLineArgs.count("nodeid") > 0) node_id = commandLineArgs["nodeid"].as<uint32_t>();
    if(commandLineArgs.count("nregions") > 0) n_regions = commandLineArgs["nregions"].as<uint32_t>();
    if(commandLineArgs.count("reps") > 0) n_reps = commandLineArgs["reps"].as<uint32_t>();
    if(commandLineArgs.count("dwidth") > 0) dwidth = commandLineArgs["dwidth"].as<uint32_t>();
    if(commandLineArgs.count("stride") > 0) stride = commandLineArgs["stride"].as<uint32_t>();
    if(commandLineArgs.count("elems") > 0) n_elem = commandLineArgs["elems"].as<uint32_t>();
    
    // FPGA handles
    fDev *fdev = new fDev[n_regions];

    // Buffers
    uint64_t *hMem[N_REGIONS];

    uint32_t qpairs[n_nodes];
    for(int i = 0; i < n_nodes; i++)
        qpairs[i] = n_regions;

    // 2 nodes example
    uint32_t l_id = node_id;
    uint32_t r_id = (node_id + 1) % n_nodes;

    // Obtain regions
    for (int i = 0; i < n_regions; i++) {
        if (!fdev[i].acquireRegion(i)) return EXIT_FAILURE;
        fdev[i].clearCompleted();
    }

    // Farview
    fView *fview = new fView(fdev, l_id, n_nodes, qpairs, n_regions, masterAddr);

    // Allocate buffers
    for(int i = 0; i < n_regions; i++)
        hMem[i] = fview->allocWindow(r_id, i, n_pages);

    // Sync up
    fview->syncRemote(r_id);

    // Latency measurements ----------------------------------------------------------------------------------
    if(!l_id) {
        // Sender 

        // ---------------------------------------------------------------
        // -- Runs 
        // ---------------------------------------------------------------
        Bench bench(1);
        uint32_t n_runs = 0;

        auto benchmark_thr = [&fview, &fdev, &hMem, &n_runs, r_id, n_reps, n_regions, dwidth, stride, n_elem]() {
            bool k = false;
            n_runs++;
            
            for(int i = 0; i < n_reps; i++) {
                for(int j = 0; j < n_regions; j++) {
                    fview->farviewStride(r_id, j, 0, 0, dwidth, stride, n_elem);  
                }
            }

            while(!k) {
                k = true;
                for(int j = 0; j < n_regions; j++) {
                    if(fview->pollRemoteWrite(r_id, j) != n_reps * n_runs) k = false;
                }
            }
        };
        bench.runtime(benchmark_thr);
        std::cout << "Throughput: " << ((n_regions * n_elem * 1000 * (1<<dwidth))) / (bench.getAvg() / n_reps) << " MB/s" << std::endl;

        for(int i = 0; i < n_regions; i++)
            fdev[i].clearCompleted();
        n_runs = 0;

        auto benchmark_lat = [&fview, &fdev, &hMem, &n_runs, r_id, n_reps, n_regions, dwidth, stride, n_elem]() {
            n_runs++;
            
            for(int i = 0; i < n_reps; i++) {
                for(int j = 0; j < n_regions; j++) {
                    fview->farviewStride(r_id, j, 0, 0, dwidth, stride, n_elem);  
                    while(fview->pollRemoteWrite(r_id, j) != (i+1) + ((n_runs-1) * n_reps)) ;
                }
            }
        };
        bench.runtime(benchmark_lat);
        std::cout << "Latency: " << bench.getAvg() / n_reps << " ns" << std::endl;

        // Done
        fview->replyRemote(r_id, 1);
	    fview->waitOnCloseRemote(r_id);
    } else {
        // Receiver

        // Done
        fview->waitOnReplyRemote(r_id);
	    fview->closeConnections();
    }

    // Free buffers
    for(int i = 0; i < n_regions; i++)
        fview->freeWindow(r_id, i);
    
    // Print status
    for (int i = 0; i < n_regions; i++) {
        fdev[i].printDebugXDMA();
    }

    // Release regions
    for (int i = 0; i < n_regions; i++) {
        fdev[i].releaseRegion();
    }

    return EXIT_SUCCESS;
}
