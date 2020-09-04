#ifndef __FHLL_HPP__
#define __FHLL_HPP__

#include <iostream>
#include <locale>
#include <thread>
#include <cstdlib>
#include <ctime>

#include "fDev.hpp"
#include "fJob.hpp"
#include "fDefs.hpp"

using namespace std;

static const struct timespec SLEEP_NS {.tv_sec = 0, .tv_nsec = 1000};

/**
 * Hyperloglog
 */
class fHll : public fJob {

public:
    fHll(uint32_t id, uint32_t priority) : fJob(id, priority, OPER_HLL) { }

    void run() {
        uint64_t n_pages = 2;
        uint32_t len = 4 * 1024;
        
        // Gen
        uint32_t* mem = (uint32_t*)fdev->getHostMem(n_pages);
        for(uint32_t i = 0; i < len/4; i++) {
            //mem[i] = rand();
            mem[i] = i;
        }

        auto start_time = std::chrono::high_resolution_clock::now();

        //std::cout << "Data offload" << std::endl;

        // Offload
        fdev->readFrom((uint64_t*)mem, len);

        // Wait for completion of the operation
        while(!fdev->getCSR(1))
            nanosleep(&SLEEP_NS, NULL);

        auto end_time = std::chrono::high_resolution_clock::now();

        double durationUs = std::chrono::duration_cast<std::chrono::microseconds>(end_time-start_time).count();
        std::cout << "duration[us]**:" << durationUs << std::endl;
        double dataSizeGB = (double)((double)(len))/1000.0/1000.0/1000.0;
        double thruput = dataSizeGB/(durationUs/1000.0/1000.0);
        std::cout<<"Datasize[GB]:"<<dataSizeGB<<" Throughput[GB/s]**:"<<thruput<<std::endl;

        // Read result
        cout << "Result: " << fdev->getCSR(2) << endl;   

        fdev->setCSR(0x1, 0);

        fdev->freeHostMem((uint64_t*)mem, n_pages);
    }
};


#endif 