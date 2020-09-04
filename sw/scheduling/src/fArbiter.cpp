#include "fArbiter.hpp"

void fArbiter::processRequests() {
    unique_lock<mutex> lck(mtx);
    run = true;
    fJob* currJob;
    cv.notify_one();
    lck.unlock();

    while(run || !request_queue.empty()) {
        lck.lock();
        if(!request_queue.empty()) {
            if(request_queue.front() !=nullptr) {
                // Remove next job from the queue
                currJob = request_queue.front();
                request_queue.pop();

                int32_t min = INT32_MAX;
                uint32_t min_id = 0;
                for (auto& it : schedulers) {
                    if(it->getSize() < min) {
                        min = it->getSize();
                        min_id = it->getRegionId();
                    }
                }

                for (auto& it : schedulers) {
                    if(it->getRegionId() == min_id)
                        it->requestJob(currJob);
                }
            }
            else {
                request_queue.pop();
            }
        }

        lck.unlock();

        nanosleep(&PAUSE, NULL);
    }
}