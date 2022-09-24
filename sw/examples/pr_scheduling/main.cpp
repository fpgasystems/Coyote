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
constexpr auto const defSize = 4 * 1024;
constexpr auto const nOper = 4;
constexpr auto const nTasks = 10;

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
    uint32_t *hMem = (uint32_t*) malloc(size);
    uint32_t *rMem = (uint32_t*) malloc(size);

    // Fill
    for(int i = 0; i < size/4; i++) 
        hMem[i] = defAddmul;

    // Prep
    cthread->setCSR(mul, 0); // Addition
    cthread->setCSR(add, 1); // Multiplication

    // Invoke
    cthread->invoke({CoyoteOper::TRANSFER, (void*)hMem, (void*)rMem, size, size});

    // Check results
    bool k = true;
    for(int i = 0; i < size/4; i++) 
        if(rMem[i] != defAddmul * mul + add) k = false;
    if (!k)  std::cout << "ERR:  Addmul failed!" << std::endl;

    // Free
    free((void*) hMem);
    free((void*) rMem);
};

// Stream statistics
constexpr auto const defMin = 10; 
constexpr auto const defMax = 20; 
auto minmaxsum = [](cThread *cthread, uint32_t size) {
    // Allocate some memory
    uint32_t *hMem = (uint32_t*) malloc(size);
    
    // Fill
    uint32_t sum = 0;
    for(int i = 0; i < size/4; i++) {
        hMem[i] = i%2 ? defMin : defMax;
        sum += hMem[i];
    }

    // Prep
    cthread->setCSR(0x1, 0); // Start kernel

    // Invoke
    cthread->invoke({CoyoteOper::READ, (void*)hMem, size, true, false});
    while(cthread->getCSR(1) != 0x1) { nanosleep((const struct timespec[]){{0, 100L}}, NULL); } // Poll for completion

    // Check results
    if((cthread->getCSR(2) != defMin) || (cthread->getCSR(2) != defMax) || (sum != cthread->getCSR(4)))
    std::cout << "ERR:  MinMaxSum failed!" << std::endl;  

    // Free
    free((void*) hMem);
};

// Rotation
constexpr auto const defRot = 0xefbeadde; 
constexpr auto const expRot = 0xdeadbeef;
auto rotation = [](cThread *cthread, uint32_t size) {
    // Allocate some memory
    uint32_t *hMem = (uint32_t*) malloc(size);
    uint32_t *rMem = (uint32_t*) malloc(size);

    // Fill
    for(int i = 0; i < size/4; i++) 
        hMem[i] = defRot; 

    // Invoke
    cthread->invoke({CoyoteOper::TRANSFER, (void*)hMem, (void*)rMem, size, size});

    // Check results
    bool k = true;
    for(int i = 0; i < size/4; i++) 
        if(rMem[i] != expRot) k = false;
    std::cout << "ERR:  Rotate failed!" << std::endl;  

    // Free
    free((void*) hMem);
    free((void*) rMem);
};

// Testcount
auto testcount = [](cThread *cthread, uint32_t size, uint32_t type, uint32_t cond) {
    // Allocate some memory
    uint32_t *hMem = (uint32_t*) malloc(size);

    // Fill
    for(int i = 0; i < size/4; i++) 
        hMem[i] = i; 
    
    // Prep
    cthread->setCSR(type, 2); // Type of comparison
    cthread->setCSR(cond, 3); // Predicate
    cthread->setCSR(0x1, 0); // Start kernel

    // Invoke
    cthread->invoke({CoyoteOper::READ, (void*)hMem, size, true, false});
    while(cthread->getCSR(1) != 0x1) { nanosleep((const struct timespec[]){{0, 100L}}, NULL); }

    // Stats
    if(cthread->getCSR(4) != size/4) 
        std::cout << "ERR:  Testcount failed!" << std::endl;

    // Free
    free((void*) hMem);
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
            case 0: // Addmul
                tasks[i].emplace_back(new cTask(i*nTasks + j, i, 1, addmul, defSize, 2, 3)); // TId, Oid, Priority, F, Args... 
                break;
            case 1: // Minmaxsum
                tasks[i].emplace_back(new cTask(i*nTasks + j, i, 1, minmaxsum, defSize)); // TId, Oid, Priority, F, Args...
                break;
            case 2: // Rotate
                tasks[i].emplace_back(new cTask(i*nTasks + j, i, 1, rotation, defSize)); // TId, Oid, Priority, F, Args...
                break;
            case 3: // Testcount
                tasks[i].emplace_back(new cTask(i*nTasks + j, i, 1, testcount, defSize, 0, 0)); // TId, Oid, Priority, F, Args...
            default:
                break;
            }
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
    cout << "Arbiter tasks completed " << carbiter.getCompletedCnt() << endl;

    high_resolution_clock::time_point end = high_resolution_clock::now();
	auto duration = duration_cast<microseconds>(end - begin).count();
    std::cout << std::dec << "All tasks completed in: " << duration << " us" << std::endl;

    return 0;
}