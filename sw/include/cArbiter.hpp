#pragma once

#include "cDefs.hpp"

#include <iostream> 
#include <algorithm>
#include <vector>
#include <mutex>
#include <queue>
#include <thread>
#include <condition_variable>
#include <limits>
#include <unordered_map>

#include "cThread.hpp"

using namespace std;

namespace fpga {

class cArbiter {
private:
    bool run;
    condition_variable cv;

    thread arbiter_thread;
    
    unordered_map<uint32_t, std::unique_ptr<cThread>> cthreads;
    
    mutex mtx;
    queue<std::unique_ptr<bTask>> request_queue;

    void processRequests();

public:

    cArbiter() {}
    ~cArbiter();

    // Threads
    bool addCThread(int32_t ctid, int32_t vfid, pid_t pid);
    void removeCThread(int32_t ctid);
    cThread* getCThread(int32_t ctid); 

    // Start arbitration
    void start();

    // Getters
    inline auto isRunning() { return run; }

    // Send a task
    void scheduleTask(std::unique_ptr<bTask> ctask) {
        lock_guard<mutex> lck2(mtx);
        request_queue.emplace(std::move(ctask));
    }

    cmplEv getCompletedNext(int32_t ctid);
    inline auto getCompletedCnt() {
        int32_t tmp = 0;
        for(auto& it: cthreads) {
            tmp += (it.second->getCompletedCnt());
        }
        return tmp;
    }
};

}