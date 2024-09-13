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
 * General notion: One cThread deals with one vFPGA and has both the memory mapping and control function to control all operations of this vFPGA in interaction with the services of the dynamic layer
 * cThreads inherit from bThreads -> Check these later as well 
 */

template<typename Cmpl>
class cThread : public bThread {
protected: 

    /* Task queue */
    mutex mtx_task;
    condition_variable cv_task; // Condition to wait for / on with the mutex declared before 
    queue<std::unique_ptr<bTask<Cmpl>>> task_queue; // Queue with pointers to bTasks that can be assigned to cThreads for execution 

    /* Completion queue */
    mutex mtx_cmpl; // Condition to wait for / on with the mutex declared before.
    queue<std::pair<int32_t, Cmpl>> cmpl_queue; // Every entry has two components: A 32-Bit task-ID and the completion-element
    std::atomic<int32_t> cnt_cmpl = { 0 }; // Counter for completed operations. Declared as atomic to make it threadsafe in this context. 

public:

	/**
	 * @brief Ctor, Dtor
	 * The cThread inherits from the bThread. Thus, the constructor of the bThread is called with the arguments for vfid, hpid, dev, scheduler and uisr
	 */
	cThread(int32_t vfid, pid_t hpid, uint32_t dev, cSched *csched = nullptr, void (*uisr)(int) = nullptr) :
        bThread(vfid, hpid, dev, csched, uisr) { 
            # ifdef VERBOSE
                std::cout << "cThread: Created an instance with vfid " << vfid << ", hpid " << hpid << ", device " << dev << std::endl; 
            # endif 
        }
	
    // Destructor of the cThread to kill it at the end of its lifetime 
    ~cThread() {
        // If the thread is running at the time of destruction, stop it running, write debugging message and let it join (wait for completion before final destruction)
        if(run) {
            run = false;

            # ifdef VERBOSE
                std::cout << "cThread: Called the destructor." << std::endl; 
            # endif 

            DBG3("cThread:  joining");
            c_thread.join();
        }
    }

    /**
     * @brief Task execution
     * 
     * Interestingly, this cThread uses a regular thread in the background 
     * 
     * @param ctask - lambda to be scheduled
     * 
     */
    void start() {
        # ifdef VERBOSE
            std::cout << "cThread: Called the start()-function" << std::endl; 
        # endif 

        // Set run to true to indicate that the thread is now running 
        run = true;

        // Lock the mutex in the first place to secure the thread 
        unique_lock<mutex> lck(mtx_task);
        DBG3("cThread:  initial lock");

        // Create a new thread-object, give it the process-function defined here and a pointer to itself for execution 
        # ifdef VERBOSE
            std::cout << "cThread: Kicked off the cThread for processing tasks." << std::endl; 
        # endif
        c_thread = thread(&cThread::processTasks, this);
        DBG3("cThread:  thread started");

        // Wait on the condition-variable (until completion of the task?)
        cv_task.wait(lck);
    }

    // Takes a smart pointer to a bTask (which holds reference for completion) and places it in the task queue for later execution
    void scheduleTask(std::unique_ptr<bTask<Cmpl>> ctask) {
        # ifdef VERBOSE
            std::cout << "cThread: Called the scheduleTask() to place a new bTask in the execution queue." << std::endl; 
        # endif 

        lock_guard<mutex> lck2(mtx_task); // Lock the mutex for the duration of the execution of this function to be thread-safe
        task_queue.emplace(std::move(ctask)); // Places the ctask in the task-queue. Uses move to hand over the object itself rather than a copy (important for smart pointers)
    }

    // Checks if there's an entry in the completion queue that shows a completed task 
    bool getTaskCompletedNext(int32_t tid, Cmpl &cmpl) {
        // Check if there's a completion event available in the queue
        # ifdef VERBOSE
            std::cout << "cThread: Called the getTaskCompletedNext() to check if there's a completion event available in the queue." << std::endl; 
        # endif
        if(!cmpl_queue.empty()) {
            lock_guard<mutex> lck(mtx_cmpl); // Lock before interacting with the queue for thread-safety 

            // Get the task ID and the completion element from the front of the completion queue 
            tid = std::get<0>(cmpl_queue.front());
            cmpl = std::get<1>(cmpl_queue.front());
            # ifdef VERBOSE
                std::cout << "cThread: Got the tid from the completion queue: " << tid << std::endl; 
            # endif

            // Pop the first element in the queue 
            cmpl_queue.pop();
            return true;
        } else {
            return false;
        }
    }

    // Returns the current count of completed functions 
    inline auto getTaskCompletedCnt() { return cnt_cmpl.load(); }

    // Returns the current size of the task-queue 
    inline auto getTaskQueueSize() { return task_queue.size(); }


protected:
    /* Task execution */
    void processTasks() {
        # ifdef VERBOSE
            std::cout << "cThread: Called the processTasks()-function in the executor-thread." << std::endl; 
        # endif

        // Create a completion code and a lock as starting conditions for task-processing 
        Cmpl cmpl_code;
        unique_lock<mutex> lck(mtx_task);
        run = true;

        // Unlock the lock as long as nothing is happening
        lck.unlock();

        // Notify a waiting thread to start processing 
        cv_task.notify_one();

        // Processing continues as long as run is true or there are items left for processing in the task queue 
        while(run || !task_queue.empty()) {
            // Lock the lock for safe access to the task queue 
            lck.lock();

            // Check for the first element in the task queue that can be fetched and then processed 
            if(!task_queue.empty()) {
                if(task_queue.front() != nullptr) {
                    
                    // Remove next task from the queue
                    auto curr_task = std::move(const_cast<std::unique_ptr<bTask<Cmpl>>&>(task_queue.front()));
                    task_queue.pop();
                    lck.unlock(); // Unlock the lock since the thread-sensitive interaction with the task-queue is done 

                    # ifdef VERBOSE
                        std::cout << "cThread: Pulled a task from the task_queue with vfid " << getVfid() << ", task ID " << getTid() << ", oid " << getOid() << " and priority " << getPriority() << std::endl; 
                    # endif

                    DBG3("Process task: vfid: " <<  getVfid() << ", tid: " << curr_task->getTid() 
                        << ", oid: " << curr_task->getOid() << ", prio: " << curr_task->getPriority());

                    // Run the task and safe the generated completion code for this
                    # ifdef VERBOSE
                        std::cout << "cThread: Called the run()-function on the current task." << std::endl; 
                    # endif            
                    cmpl_code = curr_task->run(this);

                    // Completion
                    cnt_cmpl++; // Count up the completion counter 
                    # ifdef VERBOSE
                        std::cout << "cThread: Current completion counter: " << cnt_cmpl << std::endl; 
                    # endif

                    // Close the lock for thread-safety, enqueue the completion in the queue and open the lock again after this critical operation 
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

            // Wait for a short period in time (not sure why though)
            nanosleep(&PAUSE, NULL);
        }
    }

};

} /* namespace fpga */

