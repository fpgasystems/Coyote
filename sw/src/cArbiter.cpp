#include "cArbiter.hpp"

namespace fpga {

// ======-------------------------------------------------------------------------------
// Ctor, dtor
// ======-------------------------------------------------------------------------------

cArbiter::~cArbiter() {
    run = false;
    DBG1("cArbiter: dtor called");

    DBG2("cArbiter: joining");
    arbiter_thread.join();
}

// ======-------------------------------------------------------------------------------
// Thread management
// ======-------------------------------------------------------------------------------

bool cArbiter::addCThread(int32_t ctid, int32_t vfid, pid_t pid) {
    if(cthreads.find(ctid) == cthreads.end()) {
        auto cthread = std::make_unique<cThread>(vfid, pid);
        cthreads.emplace(ctid, std::move(cthread));
        DBG1("Thread created, ctid: " << ctid);
        return true;
    }
    return false;
}

void cArbiter::removeCThread(int32_t ctid) {
    if(cthreads.find(ctid) != cthreads.end()) 
        cthreads.erase(ctid);
}

cThread* cArbiter::getCThread(int32_t ctid) {
    if(cthreads.find(ctid) != cthreads.end()) 
        return cthreads[ctid].get();
    
    return nullptr;
}

cmplEv cArbiter::getCompletedNext(int32_t ctid) {
    if(cthreads.find(ctid) != cthreads.end()) {
        return cthreads[ctid]->getCompletedNext();
    }
    return {-1, -1};
}

void cArbiter::start() {
    unique_lock<mutex> lck(mtx);
    DBG1("cArbiter: initial lock");

    arbiter_thread = thread(&cArbiter::processRequests, this);
    DBG1("cArbiter: thread started");

    cv.wait(lck);
    DBG1("cArbiter: thread finished");
}

// ======-------------------------------------------------------------------------------
// Main thread
// ======-------------------------------------------------------------------------------

void cArbiter::processRequests() {
    unique_lock<mutex> lck(mtx);
    run = true;
    cv.notify_one();
    lck.unlock();

    while(run || !request_queue.empty()) {
        lck.lock();
        if(!request_queue.empty()) {
            if(request_queue.front() !=nullptr) {
                // Remove next task from the queue
                auto curr_task = std::move(request_queue.front());
                request_queue.pop();
                lck.unlock();

                int32_t min = INT32_MAX;
                uint32_t min_id = 0;
                for (auto& it : cthreads) {
                    if(it.second->getSize() < min) {
                        min = it.second->getSize();
                        cout << "MIN SIZE: " << min << ", i: " << it.first << endl;
                        min_id = it.first;
                    }
                }

                cthreads[min_id]->scheduleTask(std::move(curr_task));
            }
            else {
                request_queue.pop();
                lck.unlock();
            }
        } else {
            lck.unlock();
        }       

        nanosleep(&PAUSE, NULL);
    }
}


}