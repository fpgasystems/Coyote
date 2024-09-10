#include <iostream>
#include <fcntl.h>
#include <unistd.h>
#include <fstream>
#include <malloc.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <time.h>
#include <sys/time.h>
#include <chrono>
#include <iomanip>
#include <fcntl.h>

#include "cRnfg.hpp"

using namespace std::chrono;

namespace fpga
{

	// ======-------------------------------------------------------------------------------
	// cRnfg management
	// ======-------------------------------------------------------------------------------
    std::atomic<uint32_t> cRnfg::crid_gen; 

	/**
	 * @brief Construct a new cRcnfg, bitstream handler
	 */
	cRnfg::cRnfg(uint32_t dev) : mlock(open_or_create, "pr_mtx") {
		DBG3("cRnfg:  ctor called");

		// Generate a string for the file-descriptor of the programmable region / vFPGA of this FPGA
		std::string region = "/dev/fpga_" + std::to_string(dev) + "_pr";

		// Open the file-descriptor for the vFPGA
		fd = open(region.c_str(), O_RDWR | O_SYNC);
		if (fd == -1)
			throw std::runtime_error("cRcnfg could not be obtained");

		// Get the Process ID of the calling process 
        pid = getpid();

		// Use the atomic crid_gen to generate a new ID 
        crid = crid_gen++;
	}

	/**
	 * @brief Destructor cRcnfg
	 *
	 */
	cRnfg::~cRnfg() {
		DBG3("cRnfg:  dtor called");

		// Mapped: Free all obtained memory pages 
		for (auto &it : mapped_pages)
		{
			freeMem(it.first);
		}

        named_mutex::remove("pr_mtx");

		// Close the file-descriptor
		close(fd);
	}

	// ======-------------------------------------------------------------------------------
	// Memory management
	// ======-------------------------------------------------------------------------------

	/**
	 * @brief Bitstream memory allocation - get memory 
	 *
	 * @param cs_alloc - allocation config as defined in cDefs
	 * @return void* - pointer to allocated mem
	 */
	void* cRnfg::getMem(csAlloc&& cs_alloc)
	{
		// Pre-initialize memory that needs to be allocated 
		void *mem = nullptr;
		void *memNonAligned = nullptr;

		// 64-Bit Array for temporary storage 
		uint64_t tmp[maxUserCopyVals];
		uint32_t size;

		// For a valid requested memory size, proceed with memory allocation 
		if (cs_alloc.size > 0)
		{
			// Store requested size, process ID and cr ID in the temporary array 
			tmp[0] = static_cast<uint64_t>(cs_alloc.size); // n_pages
            tmp[1] = static_cast<uint64_t>(pid);
            tmp[2] = static_cast<uint64_t>(crid);

			// Switch in this case used to check that the requested memory type is PRM (programmale region memory)
			switch (cs_alloc.alloc)
			{
                case CoyoteAlloc::PRM: { // m lock

					// Close lock for thread-safe memory allocation 
                    mlock.lock();

					// IO-Call to the driver for allocating memory for the programmable region 
                    if (ioctl(fd, IOCTL_ALLOC_PR_MEM, &tmp))
                    {
                        throw std::runtime_error("ioctl_alloc_host_pr_mem mapping failed");
                    }

					// Map into memory - not exactly sure how this works at this spot here 
                    memNonAligned = mmap(NULL, (cs_alloc.size + 1) * hugePageSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapPr);
                    
					// Check if memory-mapping worked 
					if (memNonAligned == MAP_FAILED)
                    {
                        throw std::runtime_error("get_pr_mem mmap failed");
                    }

					// Open the lock after the critical memory-operation 
                    mlock.unlock();

					// Align the previously obtained memory for usage for vFPGA-reconfiguration 
                    mem = (void *)((((reinterpret_cast<uint64_t>(memNonAligned) + hugePageSize - 1) >> hugePageShift)) << hugePageShift);
                    
					// Store the non-aligned memory in the csAlloc-struct (not sure why not the aligned memory though?)
					cs_alloc.mem = memNonAligned;

                    break;
                }
                default:
                    throw std::runtime_error("unauthorized memory allocation");
			}

			// Place the obtained memory in the memory-mapping-structure that is part of the thread (thread in charge of calling Reconfiguration?)
			mapped_pages.emplace(mem, cs_alloc);
			DBG3("Mapped mem at: " << std::hex << reinterpret_cast<uint64_t>(mem) << std::dec);
		}

		// Return the pointer to the obtained memory
		return mem;
	}

	/**
	 * @brief Bitstream memory deallocation. Opposite to previous function: Free the obtained memory again. 
	 *
	 * @param vaddr - mapped al
	 */
	void cRnfg::freeMem(void *vaddr)
	{
		// Save vaddr, process ID and cr ID in the temporary array 
		uint64_t tmp[maxUserCopyVals];
		uint32_t size;

		tmp[0] = reinterpret_cast<uint64_t>(vaddr);
        tmp[1] = static_cast<uint64_t>(pid);
        tmp[2] = static_cast<uint64_t>(crid);

		// Check if the current vaddr is actually part of the existing memory mapping
		if (mapped_pages.find(vaddr) != mapped_pages.end())
		{
			// Get the memory-mapping entry for the given vaddr 
			auto mapped = mapped_pages[vaddr];

			// Check the alloc-struct to find more information on the allocation 
			switch (mapped.alloc)
			{
				// Only operate if the allocation is actually for PR memory 
                case CoyoteAlloc::PRM : {

                    mlock.lock();

					// Unmap the mapped memory 
                    if (munmap(mapped.mem, (mapped.size + 1) * hugePageSize) != 0)
                    {
                        throw std::runtime_error("free_pr_mem munmap failed");
                    }

					// Send IO-call for freeing the PR-memory 
                    if (ioctl(fd, IOCTL_FREE_PR_MEM, &tmp))
                    {
                        throw std::runtime_error("ioctl_free_host_pr_mem failed");
                    }

                    mlock.unlock();

                    break;
                }
                default:
                    throw std::runtime_error("unauthorized memory deallocation");
			}

			// mapped_pages.erase(vaddr);
		}
	}

	// ======-------------------------------------------------------------------------------
	// Reconfiguration
	// ======-------------------------------------------------------------------------------

	/**
	 * @brief Reconfiguration IO
	 *
	 * @param vaddr - bitstream pointer
	 * @param len - bitstream length
	 */
	void cRnfg::reconfigureBase(void *vaddr, uint32_t len, uint32_t vfid)
	{
		// Create a tmp-array that holds address of the bitstream, length of the bitstream, process ID and CR ID 
		uint64_t tmp[maxUserCopyVals];
		tmp[0] = reinterpret_cast<uint64_t>(vaddr);
		tmp[1] = static_cast<uint64_t>(len);
        tmp[2] = static_cast<uint64_t>(pid);
        tmp[3] = static_cast<uint64_t>(crid);

		// Check the vFPGA-ID (regular number is vFGPA, -1 indicates that the shell needs reconfiguration)
        if(vfid != -1) {
			// Get the vFPGA-ID as last argument in the tmp-array
            tmp[4] = static_cast<uint64_t>(vfid);

			// Issue a ioctl call to the driver for reconfiguration of the PR 
            if (ioctl(fd, IOCTL_RECONFIGURE_APP, &tmp)) // Blocking
			    throw std::runtime_error("ioctl_reconfig_app failed");

            DBG3("App reconfiguration completed");
        } else {

			// Issue a ioctl call to the driver for reconfiguration of the base shell 
            if (ioctl(fd, IOCTL_RECONFIGURE_SHELL, &tmp)) // Blocking
			    throw std::runtime_error("ioctl_reconfig_shell failed");

            DBG3("Shell reconfiguration completed");
        }
	}

	// Util: Read a byte from the input stream and return it 
	uint8_t cRnfg::readByte(ifstream &fb)
	{
		char temp;
		fb.read(&temp, 1);
		return (uint8_t)temp;
	}

	/**
	 * @brief Read in a bitstream from the input stream 
	*/
	bStream cRnfg::readBitstream(ifstream& fb) {
		// Size
		uint32_t len = fb.tellg(); // Get the current read position in the input stream - should possibly be the length of the input stream 
		fb.seekg(0); // Set read position back to beginning of the input stream 
		uint32_t n_pages = (len + hugePageSize - 1) / hugePageSize; // Calculate the number of required memory pages to store the bitstream 

		// Get mem
		void *vaddr = getMem({CoyoteAlloc::PRM, n_pages}); // Get memory to store the bitstream that is read from the input stream 
		uint32_t *vaddr_32 = reinterpret_cast<uint32_t *>(vaddr); 

		// Read in: Read the input-stream bytewise and store it bytewise in the mapped memory 
		for (uint32_t i = 0; i < len / 4; i++)
		{
			vaddr_32[i] = 0;
			vaddr_32[i] |= readByte(fb) << 24;
			vaddr_32[i] |= readByte(fb) << 16;
			vaddr_32[i] |= readByte(fb) << 8;
			vaddr_32[i] |= readByte(fb);
		}

		DBG3("Shell bitstream loaded");

		// Return the bitstream object 
		return std::make_pair(vaddr, len);
	}
	

	// ======-------------------------------------------------------------------------------
	// Shell
	// ======-------------------------------------------------------------------------------
	
	/**
	 * @brief Add a bitstream to the map - read in a new bitstream, used for adding it to the FPGA
	 *
	 * @param name - path
	 * @param oid - operator ID
	 */
	void cRnfg::shellReconfigure(std::string name)
	{
		// Create a new input stream for the bitstream which is defined via its name as argument 
		ifstream f_bit(name, ios::ate | ios::binary);
		if (!f_bit)
			throw std::runtime_error("Shell bitstream could not be opened");

		// Read the bitstream in (call of the previously defined function)
		bStream bstream = readBitstream(f_bit);

		// Close the input stream 
		f_bit.close();

		// Reconfigure the FPGA with the new loaded bitstream 
		reconfigureBase(std::get<0>(bstream), std::get<1>(bstream));
	}

}
