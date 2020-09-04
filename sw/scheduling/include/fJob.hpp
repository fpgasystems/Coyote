#ifndef __FJOB_HPP__
#define __FJOB_HPP__

#include <iostream>
#include <locale>
#include <thread>

#include "fDev.hpp"

using namespace std;

enum jobState {idle, running, done};

struct jobCmpr;

/**
 * FPGA job
 */
class fJob {
private:
    uint32_t id;
    uint32_t op_id;
    uint32_t priority;

    jobState state;

protected:
    fDev *fdev;

public:
    fJob(uint32_t id, uint32_t priority, uint32_t op_id) {
        this->id = id;
        this->priority = priority;
        this->op_id = op_id;
        state = idle;
        fdev = 0;
    }

    friend struct jobCmpr;

    // Getters
    uint32_t getId() {
        return id;
    }

    uint32_t getOperator() {
        return op_id;
    }

    uint32_t getPriority() {
        return priority;
    }

    jobState getState() {
        return state;
    }

    // Check whether the job has been completed
    bool isDone() {
        return state == done;
    }

    // Attach a job to the FPGA device
    void attachJob(fDev* fdev) {
        this->fdev = fdev;
    }

    // Start the job
    void start() {
        if(fdev) {
            state = running;
            run();
            state = done;
        }
    }

    // Run
    virtual void run() = 0;
};

struct jobCmpr {
    bool operator()(const fJob* fjob1, const fJob* fjob2) {
        // Comparison
        if(fjob1->priority < fjob2->priority) return true;
        else if(fjob1->priority == fjob2->priority) {
            if(fjob1->op_id > fjob2->op_id)
                return true;
        }
        return false;
    }
};


#endif