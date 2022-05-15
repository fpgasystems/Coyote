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

#include "cProc.hpp"
#include "cTask.hpp"

using namespace std;
using namespace fpga;

class taskCmpr {
private:
    bool priority;
    bool reorder;

public: 
    taskCmpr(const bool& priority, const bool& reorder) {
        this->priority = priority;
        this->reorder = reorder;
    }

    bool operator()(const std::unique_ptr<bTask>& task1, const std::unique_ptr<bTask>& task2) {
        // Comparison
        if(priority) {
            if(task1->getPriority() < task2->getPriority()) return true;
        }

        if(reorder) {
            if(task1->getPriority() == task2->getPriority()) {
                if(task1->getOid() > task2->getOid())
                    return true;
            }
        }

        return false;
    }
};

/**
 * @brief Coyote thread
 * 
 */
class cThread : public cProc {
private:
    const bool priority;
    const bool reorder;

    bool run;
    condition_variable cv;

    thread scheduler_thread;

    mutex mtx_request;
    priority_queue<std::unique_ptr<bTask>, vector<std::unique_ptr<bTask>>, taskCmpr> request_queue;

    mutex mtx_completion;
    queue<int32_t> completion_queue;
    std::atomic<int32_t> cnt_cmpl = { 0 };

    void processRequests();

public:

    cThread(int32_t vfid, pid_t pid, bool priority = true, bool reorder = true);
    ~cThread();

    // Get completed
    int32_t getCompletedNext();
    inline auto getCompletedCnt() { return cnt_cmpl.load(); }

    // Get size 
    inline auto getSize() { return request_queue.size(); }

    // Schedule a task
    void scheduleTask(std::unique_ptr<bTask> ctask);

};
