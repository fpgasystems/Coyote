#ifndef __FDEV_HPP__
#define __FDEV_HPP__

#include <cstdint>
#include <cstdio>
#include <string>
#include <unordered_map> 
#include <x86intrin.h>
#include <smmintrin.h>
#include <immintrin.h>
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

#include "fDefs.hpp"

namespace fpga {

/* Command FIFO depth */
static const uint32_t cmd_fifo_depth = 64; 
static const uint32_t cmd_fifo_thr = 10;

/**
 * Fpga device region 
 */
class fDev {

	/* Fpga device */
	int32_t fd = 0;

	/* Used markers */
	uint32_t rd_cmd_cnt = 0;
	uint32_t wr_cmd_cnt = 0;
#ifdef EN_RDMA
	uint32_t rdma_cmd_cnt = 0;
#endif

	/* Mmapped regions */
#ifdef EN_AVX
	__m256i *cnfg_reg = 0;
#else 
	uint64_t *cnfg_reg = 0;
#endif
	uint64_t *ctrl_reg = 0;

	/* Mapped large pages hash table */
	std::unordered_map<uint64_t*, uint64_t*> mapped_large;

	/* Utility */
	bool mmapFpga();
	bool munmapFpga();

	/* Send to controller */
    void postCmd(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0);

	/* Check busy */
	bool checkBusyRead();
	bool checkBusyWrite();

	/* Check ready */
	bool checkReadyRead();
	bool checkReadyWrite();

	/* Memory */
	uint64_t* _getHostMem(uint32_t n_pages);
	void _freeHostMem(uint64_t* vaddr, uint32_t n_pages);
	void _userMap(uint64_t *vaddr, uint32_t len);
	void _userUnmap( uint64_t *vaddr, uint32_t len);

	/* Data movement */
	void _read(uint64_t *vaddr, uint32_t len, bool stream = true, bool poll = true, bool clr_stat = true);
	void _write(uint64_t *vaddr, uint32_t len, bool stream = true, bool poll = true, bool clr_stat = true);
	void _transfer(uint64_t *vaddr_src, uint64_t* vaddr_dst, uint32_t len_src, uint32_t len_dst, bool stream = true, bool poll = true, bool clr_stat = true);

	void _offload(uint64_t *vaddr, uint32_t len, bool poll = true);
	void _sync(uint64_t *vaddr, uint32_t len, bool poll = true); 
	

public:

	fDev() {}
	~fDev() {}

	/**
	 * Obtain and release FPGA regions
	 */ 

	// Acquire an FPGA region with target ID
	bool acquireRegion(uint32_t rNum);
	// Release an acquired FPGA region
	void releaseRegion();
	
	/**
	 * Control bus
	 */

	// Control status bus, AXI Lite
	inline void setCSR(uint64_t val, uint32_t offs) { ctrl_reg[offs] = val; }
	inline uint64_t getCSR(uint32_t offs) { return ctrl_reg[offs]; }

	/**
	 * Explicit buffer management
	 * @param n_pages - number of 2MB pages to be allocated
	 */

	// Obtain host memory - pages 2M
	template <typename _Vaddr = uint64_t>
	_Vaddr* getHostMem(uint32_t n_pages) {
		return (_Vaddr*) _getHostMem(n_pages);
	}

	// Free host memory
	template <typename _Vaddr = uint64_t>
	void freeHostMem(_Vaddr* vaddr, uint32_t n_pages) {
		_freeHostMem((uint64_t*)vaddr, n_pages);
	}

	// FPGA user space range mapping
	template <typename _Vaddr = uint64_t>
	void userMap(uint64_t *vaddr, uint32_t len) {
		_userMap((uint64_t*)vaddr, len);
	}

	// FPGA user space range unmapping (auto on release)
	template <typename _Vaddr = uint64_t>
	void userUnmap(_Vaddr *vaddr, uint32_t len) {
		_userUnmap((uint64_t*)vaddr, len);
	}

	// Obtain PR memory - pages 2M
	uint64_t* getPrMem(uint64_t n_pages);
	// Free PR memory
	void freePrMem(uint64_t* vaddr, uint64_t n_pages);

	/**
	 * Bulk transfers
	 * @param vaddr - data pointer
	 * @param len - transfer length
	 * @param poll - blocking vs non-blocking
	 */

	template <typename _Vaddr = uint64_t>
	void read(_Vaddr *vaddr, uint32_t len, bool stream = true, bool poll = true, bool clr_stat = true) {
		_read((uint64_t*)vaddr, len, stream, poll, clr_stat);
	}

	template <typename _Vaddr = uint64_t>
	void write(_Vaddr *vaddr, uint32_t len, bool stream = true, bool poll = true, bool clr_stat = true) {
		_write((uint64_t*)vaddr, len, stream, poll, clr_stat);
	}

	template <typename _Vaddr = uint64_t>
	void transfer(_Vaddr *vaddr_src, _Vaddr *vaddr_dst, uint32_t len_src, uint32_t len_dst, bool stream = true, bool poll = true, bool clr_stat = true) {
		_transfer((uint64_t*)vaddr_src, (uint64_t*)vaddr_dst, len_src, len_dst, stream, poll, clr_stat);
	}

#ifdef EN_DDR
	// Sync operations
	template <typename _Vaddr = uint64_t>
	void sync(uint64_t *vaddr, uint32_t len, bool poll = true) {
		_sync((uint64_t*)vaddr, len, poll);
	}

	template <typename _Vaddr = uint64_t>
	void offload(uint64_t *vaddr, uint32_t len, bool poll = true) {
		_offload((uint64_t*)vaddr, len, poll);
	}
#endif
	
	/**
	 * Check for completion
	 */

	// Returns the number of completed reads
	uint32_t checkCompletedRead();
	// Returns the number of completed writes
	uint32_t checkCompletedWrite();
	// Clear all status
	void clearCompleted();

	// Timers
	void setTimerStopAt(uint64_t tmr_stop_at);
	uint64_t getReadTimer();
	uint64_t getWriteTimer();

	// Debug
	void printDebugXDMA();

	/**
	 * PR
	 */
	void reconfigure(uint64_t* vaddr, uint64_t len);

	/**
	 * Roce operations
	 */

#ifdef EN_RDMA
	// ARP lookup
	bool doArpLookup();
	// Write initial context
    void writeContext(uint64_t r_vaddr, uint32_t r_key, uint32_t l_psn, uint32_t r_psn, uint32_t l_qpn, uint32_t l_region);
    // Write connection
    void writeConnection(uint32_t r_qpn, uint32_t l_qpn, uint32_t port);
	// QPn
	void writeQpn(uint32_t qpn);
	uint32_t getQpn() { return qpn; }
	bool getQpnAttached() { return qpn_attached; }

    // RDMA ops
    bool postWrite(uint64_t *l_addr, uint64_t *r_addr, uint32_t size);
    bool postRead(uint64_t *l_addr, uint64_t *r_addr, uint32_t size);
	bool postRpc(uint64_t *l_addr, uint64_t *r_addr, uint32_t size, uint64_t params);

	// Debug
	void printDebugRDMA();
#endif
};

} /* namespace fpga */

#endif
