#include "cThread.hpp"

cThread::cThread(int32_t vfid, pid_t pid, bool priority, bool reorder) 
    : cProc(vfid, getpid()), priority(priority), reorder(reorder), request_queue(taskCmpr(priority, reorder)) { 

    unique_lock<mutex> lck(mtx_request);
    DBG3("cThread: initial lock");

    scheduler_thread = thread(&cThread::processRequests, this);
    DBG3("cThread: thread started, vfid: " << getVfid());

    cv.wait(lck);
    DBG3("cThread: ctor finished, vfid: " << getVfid());
}

cThread::~cThread() {
    DBG3("cThread: dtor called, vfid: " << getVfid());
    run = false;

    DBG3("cThread: joining");
    scheduler_thread.join();
}

int32_t cThread::getCompletedNext() {
    if(!completion_queue.empty()) {
        lock_guard<mutex> lck2(mtx_completion);
        int32_t tid = completion_queue.front();
        completion_queue.pop();
        return tid;
    } 
    return -1;
}

void cThread::scheduleTask(std::unique_ptr<bTask> ctask) {
    lock_guard<mutex> lck2(mtx_request);
    request_queue.emplace(std::move(ctask));
}

void cThread::processRequests() {
    unique_lock<mutex> lck(mtx_request);
    run = true;
    int32_t curr_op_id = -1;
    cv.notify_one();
    lck.unlock();

    while(run || !request_queue.empty()) {
        lck.lock();
        if(!request_queue.empty()) {
            if(request_queue.top() != nullptr) {
                // Remove next task from the queue
                auto curr_task = std::move(const_cast<std::unique_ptr<bTask>&>(request_queue.top()));
                request_queue.pop();
                lck.unlock();

                // Check whether reconfiguration is needed
                  if(isReconfigurable())
                        if(reorder)
                            if(curr_op_id != curr_task->getOid())
                                reconfigure(curr_task->getOid());

                DBG3("Process request: vfid: " <<  getVfid() << ", task id: " << curr_task->getTid() 
                    << ", operation id: " << curr_task->getOid() << ", priority: " << curr_task->getPriority());

                // Run the task
                curr_op_id = curr_task->getOid();
                
                curr_task->run(this);

                // Completion
                cnt_cmpl++;
                mtx_completion.lock();
                completion_queue.push(curr_task->getTid());
                mtx_completion.unlock();
                 
            } else {
                request_queue.pop();
                lck.unlock();

                curr_op_id = -1;
            }
        } else {
            lck.unlock();
        }

        nanosleep(&PAUSE, NULL);
    }
}