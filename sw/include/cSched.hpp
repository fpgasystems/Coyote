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

using namespace std;
using namespace boost::interprocess;

namespace fpga {

/* Alias */
using mappedVal = std::pair<csAlloc, void*>; // n_pages, vaddr_non_aligned
using bStream = std::pair<void*, uint32_t>; // vaddr*, length

/* Struct */
struct cLoad {
    int32_t cpid;
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
class cSched {
protected: 
	/* Fpga device */
	int32_t fd = { 0 };
	int32_t vfid = { -1 };
	fCnfg fcnfg;

	/* Locks */
    named_mutex plock; // Internal vFPGA lock
    named_mutex mlock; // Internal memory lock

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
    int curr_cpid = { -1 };

    condition_variable cv_cmplt;
    mutex mtx_cmplt;
    bool curr_run = { false };

	/* Bitstream memory */
	std::unordered_map<void*, mappedVal> mapped_pages;

	/* Partial bitstreams */
	std::unordered_map<int32_t, bStream> bstreams;

	/* PR */
	uint8_t readByte(ifstream& fb);
	void reconfigure(int32_t oid);
    void reconfigure(void* vaddr, uint32_t len);

	/* Internal locks */
	inline auto mLock() { mlock.lock(); }
	inline auto mUnlock() { mlock.unlock(); }

	/* Memory alloc */
	void* getMem(const csAlloc& cs_alloc);
	void freeMem(void* vaddr);

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
     * @param cpid - Coyote id
     * @param oid - operator id
     * @param priority - task priority
     */
    void pLock(int32_t cpid, int32_t oid, uint32_t priority);
    void pUnlock(int32_t cpid);

};

} /* namespace fpga */

