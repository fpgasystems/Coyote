
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

// Has the cRnfg for handling bitstreams - might be interessant for further checks 
#include "cRnfg.hpp"

using namespace std;
using namespace boost::interprocess;

namespace fpga {

/* Struct 
 * Consists of ctid, oid and priority for scheduling 
*/
struct cLoad {
    int32_t ctid;
    int32_t oid;
    uint32_t priority;
};

/* Schedule reordering */
class taskCmprSched {
private:

    // State variables: Priority and bool for reordering
    bool priority;
    bool reorder;

public: 

    // Constructor: Set state variables 
    taskCmprSched(const bool& priority, const bool& reorder) {
        this->priority = priority;
        this->reorder = reorder;
    }

    // Takes pointers to two cLoads as scheduling requests and decides which one has the higher priority 
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
 * That's not true! There is no cProcess in Coyote v2
 * 
 */
class cSched : public cRnfg {
protected: 
	/* vFPGA */
    // vfid as vFPGA-identifier, fcnfg as the configuration of this vFGPA
	int32_t vfid = { -1 };
	fCnfg fcnfg;

	/* Locks */
    // Lock for thread-safe operations 
    named_mutex plock; // Internal vFPGA lock

    /* Scheduling */
    const bool priority;
    const bool reorder;

    /* Thread */
    // Thread used for scheduling tasks
    bool run;
    thread scheduler_thread;

    /* Scheduler queue */
    // Queue that stores pointers to load-objects. The order of the queue is calculated using the comparator-operator specified in taskCmprSched
    condition_variable cv_queue;
    mutex mtx_queue;
    priority_queue<std::unique_ptr<cLoad>, vector<std::unique_ptr<cLoad>>, taskCmprSched> request_queue;
    
    /* Scheduling and completion */
    condition_variable cv_rcnfg;
    mutex mtx_rcnfg;
    int curr_ctid = { -1 }; // current completion thread ID 

    condition_variable cv_cmplt;
    mutex mtx_cmplt;
    bool curr_run = { false }; // current run ID 

	/* Partial bitstreams */
    // Map with all bitstreams 
	std::unordered_map<int32_t, bStream> bstreams;

	/* PR */
    // Function for FPGA-reconfiguration based on the operator ID 
	void reconfigure(int32_t oid);

    /* (Thread) Process requests */
    // Function for processing Requests 
    void processRequests();

public:

	/**
	 * @brief Ctor, Dtor - constructor and destructor
     * 
     * Seems like scheduler gets created per vfid and device  
	 * 
	 */
	cSched(int32_t vfid, uint32_t dev, bool priority = true, bool reorder = true);
	~cSched();

    /**
     * @brief Run - run the scheduler 
     * 
     */
    void runSched();

	/**
	 * @brief Getters - return the vFGPA-ID 
	 * 
	 */
	inline auto getVfid() const { return vfid; }

	/**
	 * @brief Reconfigure the vFPGA
	 * 
	 * @param oid : operator ID
	 */
	auto isReconfigurable() const { return fcnfg.en_pr; } // Checks if a certain vFPGA is reconfigurable 
	void addBitstream(std::string name, int32_t oid); // Add a new bitstream to the map 
	void removeBitstream(int32_t oid); // Remove a bitstream based on the operator 
	bool checkBitstream(int32_t oid); // Check a bistream (for what?)

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

