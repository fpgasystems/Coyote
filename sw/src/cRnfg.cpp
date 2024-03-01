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

	/**
	 * @brief Construct a new cRcnfg, bitstream handler
	 */
	cRnfg::cRnfg(csDev dev) : mlock(open_or_create, "pr_mtx") {
		DBG2("cRnfg:  ctor called");
		// Open
		std::string region = "/dev/fpga_" + dev.bus + "_" + dev.slot + "_pr";
		fd = open(region.c_str(), O_RDWR | O_SYNC);
		if (fd == -1)
			throw std::runtime_error("cRcnfg could not be obtained");
	}

	/**
	 * @brief Destructor cRcnfg
	 *
	 */
	cRnfg::~cRnfg() {
		DBG2("cRnfg:  dtor called");

		// Mapped
		for (auto &it : mapped_pages)
		{
			freeMem(it.first);
		}

        named_mutex::remove("pr_mtx");

		close(fd);
	}

	// ======-------------------------------------------------------------------------------
	// Memory management
	// ======-------------------------------------------------------------------------------

	/**
	 * @brief Bitstream memory allocation
	 *
	 * @param cs_alloc - allocatin config
	 * @return void* - pointer to allocated mem
	 */
	void* cRnfg::getMem(const csAlloc &cs_alloc)
	{
		void *mem = nullptr;
		void *memNonAligned = nullptr;
		uint64_t tmp[1];
		uint32_t size;

		if (cs_alloc.n_pages > 0)
		{
			tmp[0] = static_cast<uint64_t>(cs_alloc.n_pages);

			switch (cs_alloc.alloc)
			{
			case CoyoteAlloc::PRM: // m lock

                //mlock.lock();

				if (ioctl(fd, IOCTL_ALLOC_PR_MEM, &tmp))
				{
					throw std::runtime_error("ioctl_alloc_host_pr_mem mapping failed");
				}

				memNonAligned = mmap(NULL, (cs_alloc.n_pages + 1) * hugePageSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapPr);
				if (memNonAligned == MAP_FAILED)
				{
					throw std::runtime_error("get_pr_mem mmap failed");
				}

                //mlock.unlock();

				mem = (void *)((((reinterpret_cast<uint64_t>(memNonAligned) + hugePageSize - 1) >> hugePageShift)) << hugePageShift);

				break;

			default:
				throw std::runtime_error("unauthorized memory allocation");
			}

			mapped_pages.emplace(mem, std::make_pair(cs_alloc, memNonAligned));
			DBG3("Mapped mem at: " << std::hex << reinterpret_cast<uint64_t>(mem) << std::dec);
		}

		return mem;
	}

	/**
	 * @brief Bitstream memory deallocation
	 *
	 * @param vaddr - mapped al
	 */
	void cRnfg::freeMem(void *vaddr)
	{
		uint64_t tmp[1];
		uint32_t size;

		tmp[0] = reinterpret_cast<uint64_t>(vaddr);

		if (mapped_pages.find(vaddr) != mapped_pages.end())
		{
			auto mapped = mapped_pages[vaddr];

			switch (mapped.first.alloc)
			{

			case CoyoteAlloc::PRM:

                //mlock.lock();

				if (munmap(mapped.second, (mapped.first.n_pages + 1) * hugePageSize) != 0)
				{
					throw std::runtime_error("free_pr_mem munmap failed");
				}

				if (ioctl(fd, IOCTL_FREE_PR_MEM, &vaddr))
				{
					throw std::runtime_error("ioctl_free_host_pr_mem failed");
				}

                //mlock.unlock();

				break;

			default:
				throw std::runtime_error("unauthorized memory deallocation");
			}

			mapped_pages.erase(vaddr);
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
		uint64_t tmp[3];
		tmp[0] = reinterpret_cast<uint64_t>(vaddr);
		tmp[1] = static_cast<uint64_t>(len);
        if(vfid != -1) {
            tmp[2] = static_cast<uint64_t>(vfid);

            if (ioctl(fd, IOCTL_RECONFIGURE_APP, &tmp)) // Blocking
			    throw std::runtime_error("ioctl_reconfig_app failed");

            DBG3("App reconfiguration completed");
        } else {
            if (ioctl(fd, IOCTL_RECONFIGURE_SHELL, &tmp)) // Blocking
			    throw std::runtime_error("ioctl_reconfig_shell failed");

            DBG3("Shell reconfiguration completed");
        }
	}

	// Util
	uint8_t cRnfg::readByte(ifstream &fb)
	{
		char temp;
		fb.read(&temp, 1);
		return (uint8_t)temp;
	}

	/**
	 * @brief Read in a bitstream
	*/
	bStream cRnfg::readBitstream(ifstream& fb) {
		// Size
		uint32_t len = fb.tellg();
		fb.seekg(0);
		uint32_t n_pages = (len + hugePageSize - 1) / hugePageSize;

		// Get mem
		void *vaddr = getMem({CoyoteAlloc::PRM, n_pages});
		uint32_t *vaddr_32 = reinterpret_cast<uint32_t *>(vaddr);

		// Read in
		for (uint32_t i = 0; i < len / 4; i++)
		{
			vaddr_32[i] = 0;
			vaddr_32[i] |= readByte(fb) << 24;
			vaddr_32[i] |= readByte(fb) << 16;
			vaddr_32[i] |= readByte(fb) << 8;
			vaddr_32[i] |= readByte(fb);
		}

		DBG3("Shell bitstream loaded");
		return std::make_pair(vaddr, len);
	}
	

	// ======-------------------------------------------------------------------------------
	// Shell
	// ======-------------------------------------------------------------------------------
	
	/**
	 * @brief Add a bitstream to the map
	 *
	 * @param name - path
	 * @param oid - operator ID
	 */
	void cRnfg::shellReconfigure(std::string name)
	{
		// Stream
		ifstream f_bit(name, ios::ate | ios::binary);
		if (!f_bit)
			throw std::runtime_error("Shell bitstream could not be opened");

		
		bStream bstream = readBitstream(f_bit);
		f_bit.close();

		reconfigureBase(std::get<0>(bstream), std::get<1>(bstream));
	}

}
