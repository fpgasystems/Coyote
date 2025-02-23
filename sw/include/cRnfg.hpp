#ifndef __C_RNFG_HPP__
#define __C_RNFG_HPP__

#include <fcntl.h>   
#include <unistd.h> 
#include <sys/mman.h>
#include <unordered_map> 
#include <boost/interprocess/sync/named_mutex.hpp>

#include "cDefs.hpp"

namespace coyote {

// Bitstream alias: pointer to buffer holding its contents and its length 
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
class cRnfg {
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
	std::unordered_map<void*, csAlloc> mapped_pages;

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
	 * @param cs_alloc Allocation parameters; most importantly number of pages for the buffer
	 */
	void* getMem(csAlloc&& cs_alloc);

	/**
	 * @brief Releases dynamically allocated memory (allocated using the above function)
	 * Similar to the standard C/C++ free() function
	 * 
	 * @param virtual_address corresponding to the buffer to be freed 
	 */
	void freeMem(void* virtual_address);

public:
	/**
	 * @brief Default reconfiguration constructor
	 * 
	 * @param device Target (physical) FPGA device to reconfigure
	 *		Only important for systems with multiple FPGA cards
	 *		e.g., reconfiguring 2nd FPGA in a system would mean device = 1
	 */
	cRnfg(unsigned int device = 0);

	/// Default destructor; free up dynamically allocated bitstream_t memory, remove mutex etc.
	~cRnfg();

	/**
	 * @brief Shell reconfiguration 
	 * Loads the partial bitstream into the internal memory and triggers reconfiguration
	 * 
	 * @param bitstream_path Path to partial bitstream (typically shell_top.bin inside build/bitstreams)
	 */
	void reconfigureShell(std::string bitstream_path);
};

}

#endif
