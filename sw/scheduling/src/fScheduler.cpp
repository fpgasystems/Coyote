#include "fScheduler.hpp"

void fScheduler::processRequests() {
    unique_lock<mutex> lck(mtx);
    run = true;
    fJob* currJob;
    uint32_t curr_op_id = -1;
    cv.notify_one();
    lck.unlock();

    while(run || !fque.empty()) {
        lck.lock();
        if(!fque.empty()) {
#ifdef REQUEST_SCHEDULING
            if(fque.top() != nullptr) {
#else
            if(fque.front() !=nullptr) {
#endif
                // Check whether PR is needed
#ifdef REQUEST_SCHEDULING
                if(curr_op_id != fque.top()->getOperator()) {
#else
                if(curr_op_id != fque.front()->getOperator()) {
#endif
                    // PR execution
#ifdef REQUEST_SCHEDULING
                    this->reconfigure(fque.top()->getOperator());
#else
                    this->reconfigure(fque.front()->getOperator());
#endif
                }

                // Remove next job from the queue
#ifdef REQUEST_SCHEDULING
                currJob = fque.top();
#else
                currJob = fque.front();
#endif

#ifdef VERBOSE_DEBUG
                cout << "Process Requests: current region ID: " <<  region_id << ", current thread ID: " << currJob->getId() << ", current operation ID: " << currJob->getOperator() << ", current priority: " << currJob->getPriority() << endl;
#endif
                fque.pop();

                // Run the job
                curr_op_id = currJob->getOperator();
                currJob->start();  
            }
            else {
                fque.pop();
                curr_op_id = -1;
            }
        }

        lck.unlock();

        nanosleep(&PAUSE, NULL);
    }
}