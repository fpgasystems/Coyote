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
// A bitstream consists of a pointer to memory and its length in combination 
using bStream = std::pair<void*, uint32_t>; // vaddr*, length

/**
 * @brief Coyote reconfiguration loader
 * 
 * Partial bitstream loader, required for loading partial bitstreams into the vFPGAs 
 * 
 */
class cRnfg {
protected: 
	/* Fpga device */
	int32_t fd = { 0 }; // File Descript
    pid_t pid; // Process ID
    uint32_t crid; // Configuration ID (I guess?)
    static std::atomic_uint32_t crid_gen; // Atomic for Configuration ID, not sure what this is used for 

    /* Locks */
    named_mutex mlock; // Internal memory lock

	/* Bitstream memory */
	std::unordered_map<void*, csAlloc> mapped_pages;

	/* PR */
	uint8_t readByte(ifstream& fb); // Function to read a byte from an input stream 
	bStream readBitstream(ifstream& fb); // Function to read a bitstream from an input stream 
    void reconfigureBase(void* vaddr, uint32_t len, uint32_t vfid = -1); // Function to reconfigure the base of the FPGA via the bitstream (pointer to it), length of the bitstream and vFPGA-ID

	/* Memory alloc */
	void* getMem(csAlloc&& cs_alloc); // Function to allocate memory via a csAlloc-object as defined in cDefs
	void freeMem(void* vaddr); // Function to free memory via its start-address

public:

	/**
	 * @brief Ctor, Dtor - Constructor and Destructor 
	 * 
	 */
	cRnfg(uint32_t dev);
	~cRnfg();

	/**
	 * @brief Shell reconfiguration - function to call for reconfiguration of the shell 
	*/
	void shellReconfigure(std::string name);

};

} /* namespace fpga */

