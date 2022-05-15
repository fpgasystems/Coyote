#include <iostream>
#include <string>
#include <malloc.h>
#include <time.h>
#include <sys/time.h>
#include <chrono>
#include <set>
#include <vector>
#include <sstream>

#include "cArbiter.hpp"

using namespace std;
using namespace std::chrono;

constexpr auto const nRegions = 2;
constexpr auto const nReps = 1;
constexpr auto const defSize = 512;
constexpr auto const nOper = 3;
constexpr auto const nTasks = 10;
constexpr auto const rsltLen = 4;

constexpr auto const randomOrder = true;

template<typename S>
auto select_random(const S &s, size_t n) {
  auto it = std::begin(s);
  // 'advance' the iterator n times
  std::advance(it,n);
  return it;
}

/**
 * @brief Tasks
 * 
 */

// Add + multiply
constexpr auto const defAddmul = 2; 

auto addmul = [](cThread *cthread, uint32_t size, uint32_t add, uint32_t mul) {
    // Allocate some memory
    uint32_t *hMem = malloc(size);
    uint32_t *rMem = malloc(size);

    // Fill
    for(int i = 0; i < size/4; i++) 
        hMem[i] = defAddmul;

    // Prep
    cthread->setCSR(add, 0);
    cthread->setCSR(mul, 1);

    // Invoke
    cthread->invoke({CoyoteOper::TRANSFER, (void*)hMem, (void*)rMem, size, size});

    // Check results
    bool k = true;
    for(int i = 0; i < size/4; i++) 
        if(rMem[i] != defAddmul * mul + add) k = false;
    if (!k)  std::cout << "ADDMUL fail!" << std::endl;
};

// Stream statistics
auto minmaxsum = [](cThread *cthread, uint32_t *hmem, uint32_t *rmem, uint32_t size) {
    // Allocate some memory
    uint32_t *hMem = malloc(size);
    
    // Prep
    cthread->setCSR(0x1, 0);

    // Invoke
    cthread->invoke({CoyoteOper::READ, (void*)hmem, size, true, false});
    while(cthread->getCSR(1) != 0x1) { nanosleep((const struct timespec[]){{0, 100L}}, NULL); }

    // Stats
    std::cout << "Min: " << cthread->getCSR(2) << std::endl;
    std::cout << "Max: " << cthread->getCSR(3) << std::endl;
    std::cout << "Sum: " << cthread->getCSR(4) << std::endl;
};

// Rotate
constexpr auto const defRot = 2; 

auto rotate = [](cThread *cthread, uint32_t *hmem, uint32_t *rmem, uint32_t size, uint32_t rot) {
    // Allocate some memory
    uint32_t *hMem = malloc(size);
    uint32_t *rMem = malloc(size);

    // Fill
    for(int i = 0; i < size/4; i++) 
        hMem[i] = defRot;

    // Prep
    cthread->setCSR(rot, 0);

    // Invoke
    cthread->invoke({CoyoteOper::TRANSFER, (void*)hMem, (void*)rMem, size, size});

    // Check results
    bool k = true;
    for(int i = 0; i < size/4; i++) 
        if(rMem[i] != defRot << rot) k = false;
    if (!k)  std::cout << "ROTATE fail!" << std::endl;
};

// Testcount
auto testcount = [](cThread *cthread, uint32_t *hmem, uint32_t *rmem, uint32_t size, uint32_t type, uint32_t cond) {
    // Allocate some memory
    uint32_t *hMem = malloc(size);
    
    // Prep
    cthread->setCSR(type, 2);
    cthread->setCSR(cond, 3);
    cthread->setCSR(0x1, 0);

    // Invoke
    cthread->invoke({CoyoteOper::TRANSFER, (void*)hmem, (void*)rmem, size, size, true, false});
    while(cthread->getCSR(1) != 0x1) { nanosleep((const struct timespec[]){{0, 100L}}, NULL); }

    // Stats
    rmem[0] = cthread->getCSR(4); // result
};


/**
 * @brief PR scheduling example
 * 
 */
int main()
{
    // Arbiter
    cArbiter carbiter;

    // Add threads and bitstreams
    for(int i = 0; i < nRegions; i++) {
        carbiter.addCThread(i, i, getpid());
        
        for(int j = 0; j < nOper; j++) {
            std::stringstream tmp_ss;
            tmp_ss << "bitstreams/part_bstream_c" << j << "_" << i << ".bin";
            carbiter.getCThread(i)->addBitstream(tmp_ss.str(), j);
        }
    }

    // Create tasks
    std::vector<std::unique_ptr<bTask>> tasks [nOper];

    for(int i = 0; i < nOper; i++) {
        for(int j = 0; j < nTasks; j++) {
            switch (i)
            {
            case 0: // addmul
                tasks[i].emplace_back(new cTask(i*nTasks + j, i, 1, addmul, 2, 3));
                break;
            
            default:
                break;
            }


            auto f = [=](cProc* cproc) {
                std::cout << "This is an operator: " << i << ", task id: " << i*nTasks + j << std::endl;
                sleep(1);
            };
            tasks[i].emplace_back(new cTask(i*nTasks + j, i, 1, f));
        }
    }
    DBG1("All tasks created");

    // Schedule tasks
    if(randomOrder) {
        srand(time(0));
        int tmp[nOper];
        set<int> s;
        for(int i = 0; i < nOper; i++) {
            tmp[i] = 0;
            s.insert(i);
        } 

        for(int i = 0; i < nOper * nTasks; i++) {
            auto r = rand() % s.size(); 
            auto n = *select_random(s, r);

            carbiter.scheduleTask(std::move(tasks[n][tmp[n]]));
            tmp[n]++;

            if(tmp[n] == nTasks)
                s.erase(n);
        }
    } else {
        for(int i = 0; i < nTasks; i++) {
            for(int j = 0; j < nOper; j++) {
                carbiter.scheduleTask(std::move(tasks[j][i]));
            }
        }
    }
    DBG1("All tasks scheduled");

    // Start arbitration
    carbiter.start();

    // Start the measurements
    high_resolution_clock::time_point begin = high_resolution_clock::now();

    while(carbiter.getCompletedCnt() != nOper * nTasks) nanosleep(&MSPAUSE, NULL);

    int tcmpld0 = carbiter.getCompletedCnt();
    cout << "COMPLETED COUNT: " << tcmpld0 << endl;
    
    int32_t tid;
    do {
        tid = carbiter.getCompletedNext(0);
        cout << "TID 0: " << tid << endl;
    } while(tid != -1);

    do {
        tid = carbiter.getCompletedNext(1);
        cout << "TID 1: " << tid << endl;
    } while(tid != -1);

    high_resolution_clock::time_point end = high_resolution_clock::now();
	auto duration = duration_cast<microseconds>(end - begin).count();
    std::cout << std::dec << "All tasks completed in: " << duration << " us" << std::endl;

    return 0;
}