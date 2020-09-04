#include <iostream>
#include <string>
#include <malloc.h>
#include <time.h>
#include <sys/time.h>
#include <chrono>
#include <set>

#include "fScheduler.hpp"
#include "fArbiter.hpp"
#include "fDefs.hpp"

using namespace std;
using namespace std::chrono;

#define TARGET_FPGA_REGION_0    0
#define TARGET_FPGA_REGION_1    1
#define TARGET_FPGA_REGION_2    2
#define TRANSFER_SIZE           512
#define N_HOST_PG               2
#define N_OPER                  4

template<typename S>
auto select_random(const S &s, size_t n) {
  auto it = std::begin(s);
  // 'advance' the iterator n times
  std::advance(it,n);
  return it;
}

struct jobObj {
    int oper = 0;
    int sent = 0;

    jobObj(int oper) { this->oper = oper; } 
};

int main()
{
    vector<fScheduler*> fscheduler;

    // Acquire an FPGA region 0
    fscheduler.push_back(new fScheduler(TARGET_FPGA_REGION_0));
    if(fscheduler[0]->obtainRegion())
        cout << "Acquired an FPGA region " << TARGET_FPGA_REGION_0 << endl;
    else 
        return EXIT_FAILURE;

    // Add bitstreams
    fscheduler[0]->addBitstream("bitstreams/part_bstream_c0_0.bin", OPER_0);
    fscheduler[0]->addBitstream("bitstreams/part_bstream_c1_0.bin", OPER_1);
    fscheduler[0]->addBitstream("bitstreams/part_bstream_c2_0.bin", OPER_2);
    fscheduler[0]->addBitstream("bitstreams/part_bstream_c3_0.bin", OPER_3);

    // Acquire an FPGA region 1
    fscheduler.push_back(new fScheduler(TARGET_FPGA_REGION_1));
    if(fscheduler[1]->obtainRegion())
        cout << "Acquired an FPGA region " << TARGET_FPGA_REGION_1 << endl;
    else
        return EXIT_FAILURE;

    // Add bitstreams
    fscheduler[1]->addBitstream("bitstreams/part_bstream_c0_1.bin", OPER_0);
    fscheduler[1]->addBitstream("bitstreams/part_bstream_c1_1.bin", OPER_1);
    fscheduler[1]->addBitstream("bitstreams/part_bstream_c2_1.bin", OPER_2);
    fscheduler[1]->addBitstream("bitstreams/part_bstream_c3_1.bin", OPER_3);

    // Acquire an FPGA region 2
    fscheduler.push_back(new fScheduler(TARGET_FPGA_REGION_2));
    if(fscheduler[2]->obtainRegion())
        cout << "Acquired an FPGA region " << TARGET_FPGA_REGION_2 << endl;
    else
        return EXIT_FAILURE;

    // Add bitstreams
    fscheduler[2]->addBitstream("bitstreams/part_bstream_c0_2.bin", OPER_0);
    fscheduler[2]->addBitstream("bitstreams/part_bstream_c1_2.bin", OPER_1);
    fscheduler[2]->addBitstream("bitstreams/part_bstream_c2_2.bin", OPER_2);
    fscheduler[2]->addBitstream("bitstreams/part_bstream_c3_2.bin", OPER_3);

    // Add arbiter
    fArbiter farbiter;

    farbiter.addScheduler(fscheduler[0]);
    farbiter.addScheduler(fscheduler[1]);
    farbiter.addScheduler(fscheduler[2]);

    // Start arbitration
    farbiter.start();

    uint64_t* uMem = (uint64_t*) malloc(TRANSFER_SIZE);

    // Create jobs
    vector<fJob*> jobs [N_OPER];
    for(int i = 0; i < N_JOBS; i++) {
        jobs[0].push_back(new fOp0(uMem, TRANSFER_SIZE, i, 1));
        jobs[1].push_back(new fOp1(uMem, TRANSFER_SIZE, i, 1));
        jobs[2].push_back(new fOp2(uMem, TRANSFER_SIZE, i, 1));
        jobs[3].push_back(new fOp3(uMem, TRANSFER_SIZE, i, 1));
    }

#ifdef VERBOSE_DEBUG
    cout << "All jobs created" << endl;
#endif    

    srand(time(0));
    int tmp[N_OPER];
    set<int> s;
    for(int i = 0; i < N_OPER; i++) {
        tmp[i] = 0;
        s.insert(i);
    } 
     
    // Start the measurements
    high_resolution_clock::time_point begin = high_resolution_clock::now();

#ifdef REQUEST_RANDOM
    for(int i = 0; i < N_OPER * N_JOBS; i++) {
        auto r = rand() % s.size(); 
        auto n = *select_random(s, r);

        farbiter.requestJob(jobs[n][tmp[n]]);
        tmp[n]++;

//#ifdef VERBOSE_DEBUG
//        cout << "OPER: " << n << ", OCC: " << tmp[n] << endl; 
//#endif

        if(tmp[n] == N_JOBS)
            s.erase(n);
    }
#else
    // Schedule jobs
    for(int i = 0; i < N_JOBS; i++) {
        farbiter.requestJob(jobs[0][i]);
        farbiter.requestJob(jobs[1][i]);
        farbiter.requestJob(jobs[2][i]);
        farbiter.requestJob(jobs[3][i]);
    }
#endif

#ifdef VERBOSE_DEBUG
    cout << "All jobs scheduled" << endl;
#endif   

    bool k = false;
    while(!k) {
        k = true;
        for(int i = 0; i < N_JOBS; i++) {
            if(!jobs[0][i]->isDone())
                k = false;
            if(!jobs[1][i]->isDone())
                k = false;
            if(!jobs[2][i]->isDone())
                k = false;
            if(!jobs[3][i]->isDone())
                k = false;
        }
        nanosleep(&PAUSE, NULL);
    }

    high_resolution_clock::time_point end = high_resolution_clock::now();
	auto duration = duration_cast<microseconds>(end - begin).count();
    std::cout << std::dec << "All jobs completed in: " << duration << " us" << std::endl;

    
    fscheduler[0]->removeBitstream(OPER_0);
    fscheduler[0]->removeBitstream(OPER_1);
    fscheduler[0]->removeBitstream(OPER_2);
    fscheduler[0]->removeBitstream(OPER_3);

    fscheduler[1]->removeBitstream(OPER_0);
    fscheduler[1]->removeBitstream(OPER_1);
    fscheduler[1]->removeBitstream(OPER_2);
    fscheduler[1]->removeBitstream(OPER_3);

    fscheduler[2]->removeBitstream(OPER_0);
    fscheduler[2]->removeBitstream(OPER_1);
    fscheduler[2]->removeBitstream(OPER_2);
    fscheduler[2]->removeBitstream(OPER_3);

    return 0;
}