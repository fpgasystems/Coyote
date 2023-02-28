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

#include "cProcess.hpp"
#include "cTask.hpp"

using namespace std;
using cmplEv = std::pair<int32_t, int32_t>; // tid, code

namespace fpga {

/**
 * @brief Coyote thread
 * 
 * This is a thread abstraction. Each cThread object is attached to one of the available cProcess objects.
 * Multiple cThread objects can run within the same cProcess object.
 * Just like normal threads, these cThreads can share the state.
 * 
 */
class cThread {
private:
    /* Trhead */
    thread c_thread;
    bool run = { false };

    /* cProcess */
    std::shared_ptr<cProcess> cproc;
    bool cproc_own = { false }; 

    /* cSched */
    cSched *csched = { nullptr };

    /* Task queue */
    mutex mtx_task;
    condition_variable cv_task;
    queue<std::unique_ptr<bTask>> task_queue;

    /* Completion queue */
    mutex mtx_cmpl;
    queue<cmplEv> cmpl_queue;
    std::atomic<int32_t> cnt_cmpl = { 0 };

    void startThread();
    void processRequests();

public:

    /**
	 * @brief Ctor, Dtor
	 * 
	 */
    cThread(int32_t vfid, pid_t pid, cSched *csched = nullptr); // create cProcess as well
    cThread(std::shared_ptr<cProcess> cproc); // provide existing cProc
    cThread(cThread &cthread); // copy constructor
    ~cThread();

    /**
     * @brief Getters, setters
     *
     */
    inline auto getCprocess() { return cproc; }
    inline auto getCompletedCnt() { return cnt_cmpl.load(); }
    inline auto getSize() { return task_queue.size(); }

    /**
     * @brief Completion
     * 
     */
    cmplEv getCompletedNext();

    /**
     * @brief Schedule a task
     * 
     * @param ctask - lambda to be scheduled
     */
    void scheduleTask(std::unique_ptr<bTask> ctask);
    

};

}
