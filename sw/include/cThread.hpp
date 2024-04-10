#pragma once

#include "cDefs.hpp"

#include <cstdint>
#include <cstdio>
#include <string>
#include <unordered_map> 
#include <unordered_set> 
#include <boost/functional/hash.hpp>
#include <boost/interprocess/sync/scoped_lock.hpp>
#include <boost/interprocess/sync/named_mutex.hpp>
#ifdef EN_AVX
#include <x86intrin.h>
#include <smmintrin.h>
#include <immintrin.h>
#endif
#include <unistd.h>
#include <errno.h>
#include <byteswap.h>
#include <iostream>
#include <fcntl.h>
#include <inttypes.h>
#include <mutex>
#include <atomic>
#include <sys/mman.h>
#include <sys/types.h>
#include <thread>
#include <sys/ioctl.h>
#include <fstream>
#include <sys/eventfd.h>
#include <sys/epoll.h>
#include <thread>

#include "cSched.hpp"
#include "cTask.hpp"
#include "bThread.hpp"

using namespace std;
using namespace boost::interprocess;
namespace fpga {

/**
 * @brief Coyote thread, a single thread of execution within vFPGAs
 * 
 */
template<typename Cmpl>
class cThread : public bThread {
protected: 

    /* Task queue */
    mutex mtx_task;
    condition_variable cv_task;
    queue<std::unique_ptr<bTask<Cmpl>>> task_queue;

    /* Completion queue */
    mutex mtx_cmpl;
    queue<std::pair<int32_t, Cmpl>> cmpl_queue;
    std::atomic<int32_t> cnt_cmpl = { 0 };

public:

	/**
	 * @brief Ctor, Dtor
	 * 
	 */
	cThread(int32_t vfid, pid_t hpid, uint32_t dev, cSched *csched = nullptr, void (*uisr)(int) = nullptr) :
        bThread(vfid, hpid, dev, csched, uisr) { }
	
    ~cThread() {
        if(run) {
            run = false;

            DBG3("cThread:  joining");
            c_thread.join();
        }
    }

    /**
     * @brief Task execution
     * 
     * @param ctask - lambda to be scheduled
     * 
     */
    void start() {
        run = true;

        unique_lock<mutex> lck(mtx_task);
        DBG3("cThread:  initial lock");

        c_thread = thread(&cThread::processTasks, this);
        DBG3("cThread:  thread started");

        cv_task.wait(lck);
    }

    void scheduleTask(std::unique_ptr<bTask<Cmpl>> ctask) {
        lock_guard<mutex> lck2(mtx_task);
        task_queue.emplace(std::move(ctask));
    }

    bool getTaskCompletedNext(int32_t tid, Cmpl &cmpl) {
        if(!cmpl_queue.empty()) {
            lock_guard<mutex> lck(mtx_cmpl);
            tid = std::get<0>(cmpl_queue.front());
            cmpl = std::get<1>(cmpl_queue.front());
            cmpl_queue.pop();
            return true;
        } else {
            return false;
        }
    }

    inline auto getTaskCompletedCnt() { return cnt_cmpl.load(); }
    inline auto getTaskQueueSize() { return task_queue.size(); }


protected:
    /* Task execution */
    void processTasks() {
        Cmpl cmpl_code;
        unique_lock<mutex> lck(mtx_task);
        run = true;
        lck.unlock();
        cv_task.notify_one();

        while(run || !task_queue.empty()) {
            lck.lock();
            if(!task_queue.empty()) {
                if(task_queue.front() != nullptr) {
                    
                    // Remove next task from the queue
                    auto curr_task = std::move(const_cast<std::unique_ptr<bTask<Cmpl>>&>(task_queue.front()));
                    task_queue.pop();
                    lck.unlock();

                    DBG3("Process task: vfid: " <<  getVfid() << ", tid: " << curr_task->getTid() 
                        << ", oid: " << curr_task->getOid() << ", prio: " << curr_task->getPriority());

                    // Run the task                
                    cmpl_code = curr_task->run(this);

                    // Completion
                    cnt_cmpl++;
                    mtx_cmpl.lock();
                    cmpl_queue.push({curr_task->getTid(), cmpl_code});
                    mtx_cmpl.unlock();
                    
                } else {
                    task_queue.pop();
                    lck.unlock();
                }
            } else {
                lck.unlock();
            }

            nanosleep(&PAUSE, NULL);
        }
    }

};

} /* namespace fpga */

