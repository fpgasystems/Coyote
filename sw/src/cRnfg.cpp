
#include "cRnfg.hpp"

namespace coyote {
    std::atomic<uint32_t> cRnfg::crid_gen; 

	cRnfg::cRnfg(unsigned int device): mlock(boost::interprocess::open_or_create, "reconfig_mtx") {
		DBG2("cRnfg: Constructor called");

		// Issue driver call to obtain the file descriptor for this (physical) FPGA
		// In the driver, an instance of reconfig_dev is opened, ready for memory mapping and reconfiguration
		std::string dev_name = "/dev/fpga_" + std::to_string(device) + "_pr";
		reconfig_dev_fd = open(dev_name.c_str(), O_RDWR | O_SYNC);
		if (reconfig_dev_fd == -1)
			throw std::runtime_error("cRcnfg could not be obtained");

		// Get host process ID and generate unique configuration ID, by incrementing atomic variable
        pid = getpid();
        crid = crid_gen++;
	}

	cRnfg::~cRnfg() {
		// Free dynamically allocated memory, remove mutex and close file descriptor
		DBG2("cRnfg: Destructor called");
		for (auto &it: mapped_pages) {
			freeMem(it.first);
		}
        boost::interprocess::named_mutex::remove("reconfig_mtx");
		close(reconfig_dev_fd);
	}

	void* cRnfg::getMem(csAlloc&& cs_alloc) {
		DBG2("cRnfg: getMem called to allocate memory for bitstream"); 

		void *mem = nullptr;
		void *mem_non_aligned = nullptr;
		if (cs_alloc.size > 0) {
			if (cs_alloc.alloc == CoyoteAlloc::PRM) {
				mlock.lock();

				// Arguments be passed to the driver's IOCTL call
				uint64_t tmp[maxUserCopyVals];
				tmp[0] = static_cast<uint64_t>(cs_alloc.size);
				tmp[1] = static_cast<uint64_t>(pid);
				tmp[2] = static_cast<uint64_t>(crid);

				// Allocate bitstream memory that can be written directly into FPGA memory and memory map it to a virtual address belonging to this process
				if (ioctl(reconfig_dev_fd, IOCTL_ALLOC_HOST_RECONFIG_MEM, &tmp)) {
					throw std::runtime_error("IOCTL_ALLOC_HOST_RECONFIG_MEM failed");
				}
				mem_non_aligned = mmap(NULL, (cs_alloc.size + 1) * hugePageSize, PROT_READ | PROT_WRITE, MAP_SHARED, reconfig_dev_fd, mmapPr);
				if (mem_non_aligned == MAP_FAILED) {
					throw std::runtime_error("reconfig_dev mmap failed");
				}

				mlock.unlock();

				// Align memory to hugepage and and store to the memory map (to keep information for future de-allocation)
				mem = (void *)((((reinterpret_cast<uint64_t>(mem_non_aligned) + hugePageSize - 1) >> hugePageShift)) << hugePageShift);
				cs_alloc.mem = mem_non_aligned;
				mapped_pages.emplace(mem, cs_alloc);
				DBG2("cRnfg: Allocated memory mapped at 0x" << std::hex << reinterpret_cast<uint64_t>(mem) << std::dec);
			} else {
				throw std::runtime_error("unauthorized memory allocation; partial bitsream memory must use PRM (programmable region memory) allocation");
			}
		}
		
		return mem;
	}

	void cRnfg::freeMem(void* virtual_address) {
		DBG2("cRnfg: releasePages called"); 

		// Check mapping exist and is of current type (PRM)
		if (mapped_pages.find(virtual_address) != mapped_pages.end()) {
			auto mapped = mapped_pages[virtual_address];
			if (mapped.alloc == CoyoteAlloc::PRM) {
                    mlock.lock();

					// Unmap and de-allocate bitstream memory
					uint64_t tmp[maxUserCopyVals];
					tmp[0] = reinterpret_cast<uint64_t>(virtual_address);
					tmp[1] = static_cast<uint64_t>(this->pid);
					tmp[2] = static_cast<uint64_t>(this->crid);

                    if (munmap(mapped.mem, (mapped.size + 1) * hugePageSize) != 0) {
                        throw std::runtime_error("free_pr_mem munmap failed");
                    } 
                    
					if (ioctl(reconfig_dev_fd, IOCTL_FREE_HOST_RECONFIG_MEM, &tmp)) {
                        throw std::runtime_error("ioctl_free_host_pr_mem failed");
                    }

                    mlock.unlock();
					// mapped_pages.erase(virtual_address);
			} else {
				throw std::runtime_error("unauthorized memory deallocation");
			}     
		}
	}

	uint8_t cRnfg::readByte(std::ifstream& fb) {
		char temp;
		fb.read(&temp, 1);
		return (uint8_t) temp;
	}

	bitstream_t cRnfg::readBitstream(std::ifstream& fb) {
		DBG2("cRnfg: Called readBitstream to read bitstream from input stream");
		
		// Allocate host-side, kernel memory to hold the bitsream 
		uint32_t len = fb.tellg();
		fb.seekg(0);
		uint32_t n_pages = (len + hugePageSize - 1) / hugePageSize;
		void *virtual_address = getMem({CoyoteAlloc::PRM, n_pages}); 
		uint32_t *virtual_address_32 = reinterpret_cast<uint32_t *>(virtual_address); 

		// Read the input-stream bytewise and store it bytewise to the mapped memory 
		for (uint32_t i = 0; i < len / 4; i++) {
			virtual_address_32[i] = 0;
			virtual_address_32[i] |= readByte(fb) << 24;
			virtual_address_32[i] |= readByte(fb) << 16;
			virtual_address_32[i] |= readByte(fb) << 8;
			virtual_address_32[i] |= readByte(fb);
		}

		DBG2("cRnfg: Shell bitstream loaded");
		return std::make_pair(virtual_address, len);
	}

	void cRnfg::reconfigureBase(bitstream_t bitstream, uint32_t vfid) {
        DBG2(
			"cRnfg: reconfigureBase called with virtual address 0x" << std::hex << std::get<0>(bitstream) 
			<< std::dec << ", length " << std::get<1>(bitstream) << " and vFPGA ID " << vfid
		);

		// Arguments to be passed to the driver's IOCTL call
		uint64_t tmp[maxUserCopyVals];
		tmp[0] = reinterpret_cast<uint64_t>(std::get<0>(bitstream));
		tmp[1] = static_cast<uint64_t>(std::get<1>(bitstream));
        tmp[2] = static_cast<uint64_t>(pid);
        tmp[3] = static_cast<uint64_t>(crid);

        if(vfid != -1) {
            tmp[4] = static_cast<uint64_t>(vfid);

			DBG2("cRnfg: Starting app reconfiguration");
            if (ioctl(reconfig_dev_fd, IOCTL_RECONFIGURE_APP, &tmp)) {
			    throw std::runtime_error("ioctl_reconfig_app failed");
			}
            DBG2("cRnfg: App reconfiguration completed");
        } else {
			DBG2("cRnfg: Starting shell reconfiguration");
            if (ioctl(reconfig_dev_fd, IOCTL_RECONFIGURE_SHELL, &tmp)) {
			    throw std::runtime_error("ioctl_reconfig_shell failed");
			}
			DBG2("cRnfg: Shell reconfiguration completed");
		}
	}

	void cRnfg::reconfigureShell(std::string bitstream_path) {
		DBG2("cRnfg: Called reconfigureShell"); 
        
		// Read bitstream from file and trigger reconfiguration
		std::ifstream bitstream_file(bitstream_path, std::ios::ate | std::ios::binary);
		if (!bitstream_file) {
			throw std::runtime_error("Shell bitstream could not be opened");
		}
		bitstream_t bitstream = readBitstream(bitstream_file);
		bitstream_file.close();
		reconfigureBase(bitstream);
	}

}
