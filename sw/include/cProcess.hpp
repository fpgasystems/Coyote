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

#include "ibvStructs.hpp"
#include "cSched.hpp"


using namespace std;
using namespace boost::interprocess;

namespace fpga {

/* Command FIFOs */
constexpr auto cmd_fifo_depth = cmdFifoDepth; 
constexpr auto cmd_fifo_thr = cmdFifoThr;

/**
 * @brief Coyote process, a single vFPGA region
 * 
 * This is a process abstraction. Each cProcess object is attached to one of the available vFPGAs.
 * Multiple cProcess objects can be scheduled on the same vFPGA.
 * Just like normal processes, these cProcess objects are isolated and don't share any state (IPC is possible).
 * 
 */
class cProcess {
protected: 
	/* Fpga device */
	int32_t fd = { 0 };
	int32_t vfid = { -1 };
	int32_t cpid = { -1 };
	pid_t pid = { 0 };
	fCnfg fcnfg;

	/* Locks */
    named_mutex plock; // User vFPGA lock
	named_mutex mlock; // Internal memory lock
	named_mutex dlock; // Internal vFPGA lock

    /* Scheduler */
    cSched *csched = { nullptr };

	/* Used markers */
	uint32_t rd_cmd_cnt = { 0 };
	uint32_t wr_cmd_cnt = { 0 };
	uint32_t rdma_cmd_cnt = { 0 };

	/* QSFP port */
	uint32_t qsfp = { 0 };
	uint32_t qsfp_offs = { 0 };

	/* Mmapped regions */
#ifdef EN_AVX
	volatile __m256i *cnfg_reg_avx = { 0 };
#endif
	volatile uint64_t *cnfg_reg = { 0 };
	volatile uint64_t *ctrl_reg = { 0 };

	/* Writeback */
	volatile uint32_t *wback = 0;

	/* Mapped pages */
	std::unordered_map<void*, mappedVal> mapped_pages;

	/* Mapped user pages */
	std::unordered_set<void*> mapped_upages;

	/* Utility */
	void mmapFpga();
	void munmapFpga();

	/* Post to controller */
	void postCmd(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0);
	void postPrep(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0, uint8_t offs_reg = 0);
	uint32_t last_qp = { 0 };

	/* Internal locks */
	inline auto mLock() { mlock.lock(); }
	inline auto mUnlock() { mlock.unlock(); }

public:

	/**
	 * @brief Ctor, Dtor
	 * 
	 */
	cProcess(int32_t vfid, pid_t pid, cSched *csched = nullptr);
	~cProcess();

	/**
	 * @brief Getters, setters
	 * 
	 */
	inline auto getVfid() const { return vfid; }
	inline auto getCpid() const { return cpid; }
	inline auto getPid()  const { return pid; }

	/**
	 * @brief External locks
	 * 
	 */
	void pLock(int32_t oid, uint32_t priority);
	void pUnlock();

	/**
	 * @brief Explicit TLB mapping of user allocated memory
	 * 
	 * @param vaddr : pointer to allocated memory
	 * @param len : length to map
	 */
	void userMap(void *vaddr, uint32_t len);
	void userUnmap(void *vaddr);

	/**
	 * @brief Allocate Coyote memory
	 * 
	 * @param cs_alloc : Coyote allocation struct
	 * @return void* : pointer to allocated memory
	 */
	void* getMem(const csAlloc& cs_alloc);
	void freeMem(void* vaddr);

	/**
	 * @brief CSR registers
	 * 
	 * @param val : value to be written
	 * @param offs : slave register offset
	 */
	inline auto setCSR(uint64_t val, uint32_t offs) { ctrl_reg[offs] = val; }
	inline auto getCSR(uint32_t offs) { return ctrl_reg[offs]; }

	/**
	 * @brief Invoke a transfer
	 * 
	 * @param cs_invoke : Coyote invoke struct
	 */
	void invoke(const csInvokeAll& cs_invoke); // Bidirectional transfer
	void invoke(const csInvoke& cs_invoke); // Wrapper for single direction transfer

	/**
	 * @brief Return the number of completed operations
	 * 
	 * @param coper : operation to check for
	 */
	uint32_t checkCompleted(CoyoteOper coper);
	void clearCompleted();

	/**
	 * @brief Perform an arp lookup
	 * 
	 */
    void doArpLookup(uint32_t ip_addr);

	/**
	 * @brief Write the queue pair context
	 * 
	 * @param qp : queue pair struct
	 */
    void writeQpContext(ibvQp *qp);
	void writeConnContext(ibvQp *qp, uint32_t port);
	
	/**
	 * @brief Initiate an ibv command
	 * 
	 * @param qp : queue pair struct
	 * @param wr : rdma operation context struct
	 */
	void ibvPostSend(ibvQp *qp, ibvSendWr *wr);

	/**
	 * @brief Return the number of completed RDMA acks
	 * 
	 */
    uint32_t ibvCheckAcks();
    int32_t ibvGetCompleted(int32_t &cpid);
	uint32_t checkIbvAcks();
	void clearIbvAcks();

	/**
	 * @brief Network dropper
	 */
	void netDrop(bool clr, bool dir, uint32_t packet_id);


	/**
	 * @brief TCP Open Connection
	 */

	bool tcpOpenCon(uint32_t ip, uint32_t port, uint32_t* session);
	
	/**
	 * @brief TCP Open Port
	 */
	
	bool tcpOpenPort(uint32_t port);

	/**
	 * @brief TCP Close Connection
	 */

	void tcpCloseCon(uint32_t session);

	/**
	 * @brief Debug
	 * 
	 */
	void printDebug();

};

} /* namespace fpga */

