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
    pid_t pid;
    uint32_t crid;
    static std::atomic_uint32_t crid_gen;

    /* Locks */
    named_mutex mlock; // Internal memory lock

	/* Bitstream memory */
	std::unordered_map<void*, csAlloc> mapped_pages;

	/* PR */
	uint8_t readByte(ifstream& fb);
	bStream readBitstream(ifstream& fb);
    void reconfigureBase(void* vaddr, uint32_t len, uint32_t vfid = -1);

	/* Memory alloc */
	void* getMem(csAlloc&& cs_alloc);
	void freeMem(void* vaddr);

public:

	/**
	 * @brief Ctor, Dtor
	 * 
	 */
	cRnfg(uint32_t dev);
	~cRnfg();

	/**
	 * @brief Shell reconfiguration
	*/
	void shellReconfigure(std::string name);

};

} /* namespace fpga */

