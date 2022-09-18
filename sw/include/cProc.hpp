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

using namespace std;
using namespace boost::interprocess;

namespace fpga {

/* Command FIFOs */
constexpr auto cmd_fifo_depth = cmdFifoDepth; 
constexpr auto cmd_fifo_thr = cmdFifoThr;

/* Spinlock */
class sLock {
private:
	std::atomic_flag lck = ATOMIC_FLAG_INIT;

public:
	void lock() { while(lck.test_and_set(std::memory_order_acquire)) {} }
	void unlock() {lck.clear(std::memory_order_relaxed); }
};

/**
 * @brief Invoke struct
 * 
 */
struct csInvokeAll {
	// Operation
	CoyoteOper oper = { CoyoteOper::NOOP };
	
	// Data
	void* src_addr = { nullptr }; 
	void* dst_addr = { nullptr };
	uint32_t src_len = { 0 };
	uint32_t dst_len = { 0 }; 

	// Flags
	bool clr_stat = true;
	bool poll = true;
	uint8_t dest = { 0 };
	bool stream = true;
};

/**
 * @brief Invoke struct with single src/dst location (simplification only)
 * 
 */
struct csInvoke {
	// Operation
	CoyoteOper oper = { CoyoteOper::NOOP };
	
	// Data
	void* addr = { nullptr }; 
	uint32_t len = { 0 };

	// Flags
	bool clr_stat = true;
	bool poll = true;
	uint8_t dest = { 0 };
	bool stream = true;
};

using mappedVal = std::pair<csAlloc, void*>; // n_pages, vaddr_non_aligned
using bStream = std::pair<void*, uint32_t>; // vaddr*, length

/**
 * @brief Coyote process, a single vFPGA region
 * 
 */
class cProc {
protected: 
	/* Fpga device */
	int32_t fd = { 0 };
	int32_t vfid = { -1 };
	int32_t cpid = { -1 };
	pid_t pid = { 0 };
	fCnfg fcnfg;

	/* Locks */
	sLock tlock;
	named_mutex plock;
	named_mutex dlock;

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

	/* Partial bitstreams */
	std::unordered_map<int32_t, bStream> bstreams;

	/* Utility */
	void mmapFpga();
	void munmapFpga();

	/* PR */
	uint8_t readByte(ifstream& fb);
	void reconfigure(void* vaddr, uint32_t len);

	/* Post to controller */
	void postCmd(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0);
	void postPrep(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0, uint8_t offs_reg = 0);
	uint32_t last_qp = { 0 };

public:

	/**
	 * @brief Ctor, Dtor
	 * 
	 */
	cProc(int32_t vfid, pid_t pid);
	~cProc();

	/**
	 * @brief Getters
	 * 
	 */
	inline auto getVfid() const { return vfid; }
	inline auto getCpid() const { return cpid; }
	inline auto getPid()  const { return pid; }

	/**
	 * @brief Locks
	 * 
	 */
	inline auto tLock() { tlock.lock(); }
	inline auto tUnlock() { tlock.unlock(); }

	inline auto pLock() { plock.lock(); }
	inline auto pUnlock() { plock.unlock(); }

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
	 * @brief Reconfigure the vFPGA
	 * 
	 * @param oid : operator ID
	 */
	void reconfigure(int32_t oid);
	void addBitstream(std::string name, int32_t oid);
	void removeBitstream(int32_t oid);	
	auto isReconfigurable() const { return fcnfg.en_pr; }

	/**
	 * @brief Change the IP address and board numbers
	 * 
	 */
    void changeIpAddress(uint32_t ip_addr);
    void changeBoardNumber(uint32_t board_num);

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
	uint32_t checkIbvAcks();
	void clearIbvAcks();

	/**
	 * @brief Debug
	 * 
	 */
	void printDebug();
	void printNetDebug();

};

} /* namespace fpga */

