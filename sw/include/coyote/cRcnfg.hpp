/*
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#ifndef _COYOTE_CRCNFG_HPP_
#define _COYOTE_CRCNFG_HPP_

#include <atomic>
#include <fcntl.h> 
#include <fstream>
#include <unistd.h> 
#include <sys/mman.h>
#include <unordered_map> 
#include <boost/interprocess/sync/named_mutex.hpp>

#include <coyote/cOps.hpp>
#include <coyote/cDefs.hpp>

namespace coyote {

/// Bitstream alias: pointer to buffer holding its contents and its length 
using bitstream_t = std::pair<void*, uint32_t>;

/**
 * @brief Coyote reconfiguration class
 * Used for loading partial bitstreams to FPGA memory and triggering reconfiguration
 * Used for both shell reconfiguration (dynamic + user layer) and app reconfiguration (2nd-level PR)
 *
 * The most important function for users here is ```reconfigureShell(std::string bistream_path)````
 * Which is used to reconfigure the entire shell (dynamic + user layer); for more details see comments below
 * 
 * In general, the flow of reconfiguration is (all of which is abstracted by ```reconfigureShell```):
 *	- Allocate host-side, kernel memory to hold the partial bitsream (void* getMem, internally calling the Coyote driver)
 *  - Map the allocated memory to the user-space (using reconfig_mmap from the Coyote driver)
 *	- Load the bitsream from disk and store it to the allocated memory
 * 	- Trigger reconfiguration by writing the memory to FPGA memory and asserting the correct registers
 *  - Once complete, release the allocated memory (void freeMem, internally calling the Coyote driver)
 */
class cRcnfg {

protected: 
	/*
	 * Device file descriptor; corresponds to a char reconfig_dev device from the driver 
	 * This file descriptor is used to issue calls to the driver and hardware, including
	 * bitsream memory allocation and mapping, reconfiguration starting etc.
	 */ 
	int reconfig_dev_fd = { 0 }; 

	/// Host-side process ID
    pid_t pid; 

	/// Unique configuration ID
    uint32_t crid;

	/// A unique generator for crid
    static std::atomic_uint32_t crid_gen;

    /// Global mutex, ensuring no two processes are simultaneously allocating bitstream memory on the same object
    boost::interprocess::named_mutex mlock;

	/*
	 * Map to keep track of pages allocated to hold partial bitstreams
	 * By keeping track, de-allocation can be done internally and is not a responsibility of the user
	 */
	std::unordered_map<void*, CoyoteAlloc> mapped_pages;

	/// Helper function, pops and returns the first byte from the input stream (fb)
	uint8_t readByte(std::ifstream& fb); 
	
	/**
	 * @brief Read bitstream from a file stream, that can be used for reconfiguration
	 * 
	 * @param fb File input stream, corresponding to a .bin file (most likely shell_top.bin)
	 * @return bitstream, an in-memory object of type bitstream with virtual address and length
	 */
	bitstream_t readBitstream(std::ifstream& fb);

	/**
	 * @brief Base reconfiguration function, can be used to reconfigure the whole shell or individual vFPGAs
	 * 
	 * @param bitstream partial bitstream to use for reconfiguration, obtainable from reconfigureBase
	 * @param vfid (optional) vFPGA to reconfigure; default = -1, which reconfigures the entire shell
	 */
    void reconfigureBase(bitstream_t bitstream, uint32_t vfid = -1);

	/**
	 * @brief Allocates a buffer for storing partial bitstream
	 * @param alloc Allocation parameters; most importantly number of pages for the buffer
	 */
	void* getMem(CoyoteAlloc&& alloc);

	/**
	 * @brief Releases dynamically allocated memory (allocated using the above function)
	 * Similar to the standard C/C++ free() function
	 * 
	 * @param vaddr corresponding to the buffer to be freed 
	 */
	void freeMem(void* vaddr);

public:
	/**
	 * @brief Default reconfiguration constructor
	 * 
	 * @param device Target (physical) FPGA device to reconfigure
	 *		Only important for systems with multiple FPGA cards
	 *		e.g., reconfiguring 2nd FPGA in a system would mean device = 1
	 */
	cRcnfg(unsigned int device = 0);

	/// Default destructor; free up dynamically allocated bitstream_t memory, remove mutex etc.
	~cRcnfg();

	/**
	 * @brief Shell reconfiguration 
	 * Loads the partial bitstream into the internal memory and triggers reconfiguration
	 * 
	 * @param bitstream_path Path to partial bitstream (typically shell_top.bin inside build/bitstreams)
	 */
	void reconfigureShell(std::string bitstream_path);

	/**
	 * @brief App reconfiguration 
	 * Loads the partial bitstream into the internal memory and triggers reconfiguration of the specific vFPGA
	 * 
	 * @param bitstream_path Path to partial bitstream (typically shell_top.bin inside build/bitstreams)
	 * @param vfid vFPGA ID to be reconfigured
	 */
	 void reconfigureApp(std::string bitstream_path, int vfid);
};

}

#endif // _COYOTE_CRCNFG_HPP_
