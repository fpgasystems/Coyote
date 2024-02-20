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

/**
 * @brief Coyote reconfiguration loader
 * 
 * Partial bitstream loader
 * 
 */
class cRnfg {
protected: 
	/* Fpga device */
	int32_t fd = { 0 };

    /* Locks */
    named_mutex mlock; // Internal memory lock

	/* Bitstream memory */
	std::unordered_map<void*, mappedVal> mapped_pages;

	/* PR */
	uint8_t readByte(ifstream& fb);
	bStream readBitstream(ifstream& fb);
    void reconfigureBase(void* vaddr, uint32_t len, uint32_t vfid = -1);

	/* Memory alloc */
	void* getMem(const csAlloc& cs_alloc);
	void freeMem(void* vaddr);

public:

	/**
	 * @brief Ctor, Dtor
	 * 
	 */
	cRnfg();
	~cRnfg();

	/**
	 * @brief Shell reconfiguration
	*/
	void shellReconfigure(std::string name);

};

} /* namespace fpga */

