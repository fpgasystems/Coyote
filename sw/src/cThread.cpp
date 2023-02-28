#include "cThread.hpp"

#include <syslog.h>

namespace fpga {

// ======-------------------------------------------------------------------------------
// Ctor, dtor
// ======-------------------------------------------------------------------------------

void cThread::startThread()
{
    // Thread
    unique_lock<mutex> lck(mtx_task);
    DBG3("cThread:  initial lock");

    c_thread = thread(&cThread::processRequests, this);
    DBG3("cThread:  thread started");

    cv_task.wait(lck);
    DBG3("cThread:  ctor finished");
}

cThread::cThread(int32_t vfid, pid_t pid, cSched *csched)  
{ 
    // cProcess
    cproc = std::make_shared<cProcess>(vfid, pid, csched);

    // Thread
    startThread();
}

cThread::cThread(std::shared_ptr<cProcess> cproc)  
{ 
    // cProcess
    this->cproc = cproc;

    // Thread
    startThread();
}


cThread::cThread(cThread &cthread)
{
    // cProcess
    this->cproc = cthread.getCprocess();

    // Thread
    startThread();
}

cThread::~cThread() 
{
    // cProcess
    if(cproc_own) {
        cproc->~cProcess();
    }

    // Thread
    DBG3("cThread:  dtor called");
    run = false;

    DBG3("cThread:  joining");
    c_thread.join();
}


// ======-------------------------------------------------------------------------------
// Main thread
// ======-------------------------------------------------------------------------------

void cThread::processRequests() {
    int32_t cmpl_code;
    unique_lock<mutex> lck(mtx_task);
    run = true;
    lck.unlock();
    cv_task.notify_one();

    while(run || !task_queue.empty()) {
        lck.lock();
        if(!task_queue.empty()) {
            if(task_queue.front() != nullptr) {
                // Remove next task from the queue
                auto curr_task = std::move(const_cast<std::unique_ptr<bTask>&>(task_queue.front()));
                task_queue.pop();
                lck.unlock();

                DBG3("Process task: vfid: " <<  cproc->getVfid() << ", tid: " << curr_task->getTid() 
                    << ", oid: " << curr_task->getOid() << ", prio: " << curr_task->getPriority());

                // Run the task                
                cmpl_code = curr_task->run(cproc.get());

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

// ======-------------------------------------------------------------------------------
// Schedule
// ======-------------------------------------------------------------------------------

cmplEv cThread::getCompletedNext() {
    if(!cmpl_queue.empty()) {
        lock_guard<mutex> lck(mtx_cmpl);
        cmplEv cmpl_ev = cmpl_queue.front();
        cmpl_queue.pop();
        return cmpl_ev;
    } 
    return {-1, -1};
}

void cThread::scheduleTask(std::unique_ptr<bTask> ctask) {
    lock_guard<mutex> lck2(mtx_task);
    task_queue.emplace(std::move(ctask));
}

}