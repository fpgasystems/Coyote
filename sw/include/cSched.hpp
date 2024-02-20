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
#include <tuple>
#include <condition_variable>
#include <thread>
#include <limits>
#include <queue>
#include <syslog.h>

#include "cRnfg.hpp"

using namespace std;
using namespace boost::interprocess;

namespace fpga {

/* Struct */
struct cLoad {
    int32_t ctid;
    int32_t oid;
    uint32_t priority;
};

/* Schedule reordering */
class taskCmprSched {
private:
    bool priority;
    bool reorder;

public: 
    taskCmprSched(const bool& priority, const bool& reorder) {
        this->priority = priority;
        this->reorder = reorder;
    }

    bool operator()(const std::unique_ptr<cLoad>& req1, const std::unique_ptr<cLoad>& req2) {
        // Comparison
        if(priority) {
            if(req1->priority < req2->priority) return true;
        }

        if(reorder) {
            if(req1->priority == req2->priority) {
                if(req1->oid > req2->oid)
                    return true;
            }
        }

        return false;
    }
};

/**
 * @brief Coyote scheduler
 * 
 * This is the main vFPGA scheduler. It schedules submitted user tasks.
 * These tasks trickle down: cTask -> cThread -> cProcess -> cSched -> vFPGA
 * 
 */
class cSched : public cRnfg {
protected: 
	/* vFPGA */
	int32_t vfid = { -1 };
	fCnfg fcnfg;

	/* Locks */
    named_mutex plock; // Internal vFPGA lock

    /* Scheduling */
    const bool priority;
    const bool reorder;

    /* Thread */
    bool run;
    thread scheduler_thread;

    /* Scheduler queue */
    condition_variable cv_queue;
    mutex mtx_queue;
    priority_queue<std::unique_ptr<cLoad>, vector<std::unique_ptr<cLoad>>, taskCmprSched> request_queue;
    
    /* Scheduling and completion */
    condition_variable cv_rcnfg;
    mutex mtx_rcnfg;
    int curr_ctid = { -1 };

    condition_variable cv_cmplt;
    mutex mtx_cmplt;
    bool curr_run = { false };

	/* Partial bitstreams */
	std::unordered_map<int32_t, bStream> bstreams;

	/* PR */
	void reconfigure(int32_t oid);

    /* (Thread) Process requests */
    void processRequests();

public:

	/**
	 * @brief Ctor, Dtor
	 * 
	 */
	cSched(int32_t vfid, bool priority = true, bool reorder = true);
	~cSched();

    /**
     * @brief Run
     * 
     */
    void run_sched();

	/**
	 * @brief Getters
	 * 
	 */
	inline auto getVfid() const { return vfid; }

	/**
	 * @brief Reconfigure the vFPGA
	 * 
	 * @param oid : operator ID
	 */
	auto isReconfigurable() const { return fcnfg.en_pr; }
	void addBitstream(std::string name, int32_t oid);
	void removeBitstream(int32_t oid);	
	bool checkBitstream(int32_t oid); 

    /**
     * @brief Schedule operation
     * 
     * @param ctid - Coyote id
     * @param oid - operator id
     * @param priority - task priority
     */
    void pLock(int32_t ctid, int32_t oid, uint32_t priority);
    void pUnlock(int32_t ctid);

};

} /* namespace fpga */

