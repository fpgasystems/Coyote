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
#include <sys/eventfd.h>
#include <sys/epoll.h>
#include <thread>

#include "cSched.hpp"
#include "cTask.hpp"

using namespace std;
using namespace boost::interprocess;
namespace fpga {

/* Command FIFOs */
constexpr auto cmd_fifo_depth = cmdFifoDepth; 
constexpr auto cmd_fifo_thr = cmdFifoThr;

/**
 * @brief Coyote thread, a single thread of execution within vFPGAs
 * 
 */
class bThread {
protected: 
	/* Fpga device */
	int32_t fd = { 0 };
	int32_t vfid = { -1 };
	int32_t ctid = { -1 };
	pid_t hpid = { 0 };
	fCnfg fcnfg;

    /* Thread */
    thread c_thread;
    bool run = { false };

    /* Remote */
    std::unique_ptr<ibvQp> qpair;
    bool is_buff_attached;

    /* Connection */
    int connection = { 0 };
    bool is_connected;

	/* Locks */
    named_mutex plock; // User vFPGA lock

    /* Scheduler */
    cSched *csched = { nullptr };

	/* Used markers */
	uint32_t cmd_cnt = { 0 };

    /* eventfd */
	int32_t efd = { -1 };
	int32_t terminate_efd = { -1 };
	std::thread event_thread;

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

	/* Utility */
	void mmapFpga();
	void munmapFpga();

    /* Connection */
    void sendAck(uint32_t ack);
    uint32_t readAck();
    void closeAck();

	/* Post to controller */
	void postCmd(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0);

public:

	/**
	 * @brief Ctor, Dtor
	 * 
	 */
	bThread(int32_t vfid, pid_t hpid, csDev dev, cSched *csched = nullptr, void (*uisr)(int) = nullptr);
	~bThread();

    /**
	 * @brief vFPGA lock
     * This is the main sync mechanism for threads within a single vFPGA
     * It is also used to request a reconfiguration of the vFPGA
	 * 
	 */
	void pLock(int32_t oid, uint32_t priority);
	void pUnlock();

	/**
	 * @brief Memory management
	 * 
	 * @param vaddr : pointer to allocated memory
	 * @param len : length to map
     * @param cs_alloc : Coyote allocation struct
	 */
	void userMap(void *vaddr, uint32_t len, bool remote = false);
	void userUnmap(void *vaddr);

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
	void invoke(const csInvoke& cs_invoke);

	/**
	 * @brief Return the number of completed operations
	 * 
	 * @param coper : operation to check for
	 */
	uint32_t checkCompleted(CoyoteOper coper);
	void clearCompleted();

    /**
     * @brief Process connection
     * 
     */
    inline auto isConnected() { return is_connected; }
    void setConnection(int connection);
    void closeConnection();

	/**
	 * @brief RDMA connection management
	 * 
	 */
    bool doArpLookup(uint32_t ip_addr);
    bool writeQpContext(uint32_t port);

    void rdmaConnSync(bool client);
    void rdmaConnClose(bool client);

    /**
	 * @brief Getters, setters
	 * 
	 */
	inline auto getVfid() const { return vfid; }
	inline auto getCtid() const { return ctid; }
	inline auto getHpid() const { return hpid; }

    inline auto getQpair() { return qpair.get(); }
    
	/**
	 * @brief Debug
	 * 
	 */
	void printDebug();

};

} /* namespace fpga */

