#ifndef __FSCHEDULER_HPP__
#define __FSCHEDULER_HPP__

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

using namespace std;

static const struct timespec PAUSE {.tv_sec = 0, .tv_nsec = 1000};
static const struct timespec MSPAUSE {.tv_sec = 0, .tv_nsec = 1000000};

class fScheduler : public fDev {
private:
    uint32_t region_id;

    bool run;
    mutex mtx;
    condition_variable cv;

    thread schedulerThread;

#ifdef REQUEST_SCHEDULING
    priority_queue<fJob*, vector<fJob*>, jobCmpr> fque;
#else
    queue<fJob*> fque;
#endif

    fDev *fdev;

    void processRequests();

public:
    fScheduler(uint32_t region_id) {
        this->region_id = region_id;

        unique_lock<mutex> lck(mtx);
#ifdef VERBOSE_DEBUG
        cout << "Scheduler: initial lock" << endl;
#endif

        schedulerThread = thread(&fScheduler::processRequests, this);
#ifdef VERBOSE_DEBUG
        cout << "Scheduler: thread started" << endl;
#endif      

        cv.wait(lck);
#ifdef VERBOSE_DEBUG
        cout << "Scheduler: constructor finished" << endl;
#endif
    }

    ~fScheduler() {
        run = false;
#ifdef VERBOSE_DEBUG
        cout << "Scheduler: destructor called" << endl;
#endif

        schedulerThread.join();
    }

    // Getters
    bool isRunning() {
        return run;
    }

    uint32_t getSize() {
        return fque.size();
    }

    uint32_t getRegionId() {
        return region_id;
    }

    // Obtain a region
    bool obtainRegion() {
        if(acquireRegion(region_id))
            return true;
        else
            return false;
    }

    // Request a job
    void requestJob(fJob* fjob) {
        if(isRegionAcquired()) {
            fjob->attachJob(this);
            lock_guard<mutex> lck2(mtx);
            fque.push(fjob);
        }
    }
};

#endif