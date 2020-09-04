#ifndef __FARBITER_HPP__
#define __FARBITER_HPP__

#include <iostream> 
#include <algorithm>
#include <vector>
#include <mutex>
#include <queue>
#include <thread>
#include <condition_variable>
#include <limits>

#include "fDefs.hpp"
#include "fDev.hpp"
#include "fJob.hpp"
#include "fScheduler.hpp"

using namespace std;

class fArbiter {
private:
    bool run;
    mutex mtx;
    condition_variable cv;

    thread arbiterThread;

    vector<fScheduler*> schedulers;
    queue<fJob*> request_queue;

    void processRequests();

public:
    fArbiter() {}

    ~fArbiter() {
        run = false;
#ifdef VERBOSE_DEBUG
        cout << "Arbiter: destructor called" << endl;
#endif

       arbiterThread.join();

       for (auto& it : schedulers) {
            delete it;
        }
    }

    // Add a created scheduler
    void addScheduler(fScheduler *fscheduler) {
        schedulers.push_back(fscheduler);
    }

    // Start arbitration
    void start() {
        unique_lock<mutex> lck(mtx);
#ifdef VERBOSE_DEBUG
        cout << "Arbiter: initial lock" << endl;
#endif

        arbiterThread = thread(&fArbiter::processRequests, this);
#ifdef VERBOSE_DEBUG
        cout << "Arbiter: thread started" << endl;
#endif      

        cv.wait(lck);
    }

    // Getters
    bool isRunning() {
        return run;
    }

    void requestJob(fJob* fjob) {
        lock_guard<mutex> lck2(mtx);
        request_queue.push(fjob);
    }
};

#endif