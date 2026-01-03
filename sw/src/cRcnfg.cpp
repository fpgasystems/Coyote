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

#include <coyote/cRcnfg.hpp>

namespace coyote {
std::atomic<uint32_t> cRcnfg::crid_gen; 

cRcnfg::cRcnfg(unsigned int device): mlock(boost::interprocess::open_or_create, "reconfig_mtx") {
	DBG2("cRcnfg: Constructor called");

	// Issue driver call to obtain the file descriptor for this (physical) FPGA
	// In the driver, an instance of reconfig_dev is opened, ready for memory mapping and reconfiguration
	std::string dev_name = "/dev/coyote_fpga_" + std::to_string(device) + "_reconfig";
	reconfig_dev_fd = open(dev_name.c_str(), O_RDWR | O_SYNC);
	if (reconfig_dev_fd == -1)
		throw std::runtime_error("ERROR: cRcnfg instance could not be obtained");

	// Get host process ID and generate unique configuration ID, by incrementing atomic variable
	pid = getpid();
	crid = crid_gen++;
}

cRcnfg::~cRcnfg() {
	// Free dynamically allocated memory, remove mutex and close file descriptor
	DBG2("cRcnfg: Destructor called");
	for (auto &it: mapped_pages) {
		freeMem(it.first);
	}
	boost::interprocess::named_mutex::remove("reconfig_mtx");
	close(reconfig_dev_fd);
}

void* cRcnfg::getMem(CoyoteAlloc&& alloc) {
	DBG2("cRcnfg: getMem called to allocate memory for bitstream"); 

	void *mem = nullptr;
	void *mem_non_aligned = nullptr;
	if (alloc.size > 0) {
		if (alloc.alloc == CoyoteAllocType::PRM) {
			mlock.lock();

			// Arguments be passed to the driver's IOCTL call
			uint64_t tmp[MAX_USER_ARGS];
			tmp[0] = static_cast<uint64_t>(alloc.size);
			tmp[1] = static_cast<uint64_t>(pid);
			tmp[2] = static_cast<uint64_t>(crid);

			// Allocate bitstream memory that can be written directly into FPGA memory and memory map it to a virtual address belonging to this process
			if (ioctl(reconfig_dev_fd, IOCTL_ALLOC_HOST_RECONFIG_MEM, &tmp)) {
				throw std::runtime_error("ERROR: IOCTL_ALLOC_HOST_RECONFIG_MEM failed");
			}
			mem_non_aligned = mmap(NULL, (alloc.size + 1) * HUGE_PAGE_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, reconfig_dev_fd, MMAP_RECONFIG);
			if (mem_non_aligned == MAP_FAILED) {
				throw std::runtime_error("ERROR: reconfig_dev mmap() failed");
			}

			mlock.unlock();

			// Align memory to hugepage and and store to the memory map (to keep information for future de-allocation)
			mem = (void *)((((reinterpret_cast<uint64_t>(mem_non_aligned) + HUGE_PAGE_SIZE - 1) >> HUGE_PAGE_SHIFT)) << HUGE_PAGE_SHIFT);
			alloc.mem = mem_non_aligned;
			mapped_pages.emplace(mem, alloc);
			DBG2("cRcnfg: Allocated memory mapped at 0x" << std::hex << reinterpret_cast<uint64_t>(mem) << std::dec);
		} else {
			throw std::runtime_error("ERROR: Unauthorized memory allocation; partial bitsream memory must use PRM (programmable region memory) allocation");
		}
	}
	
	return mem;
}

void cRcnfg::freeMem(void* virtual_address) {
	DBG2("cRcnfg: releasePages called"); 

	// Check mapping exist and is of current type (PRM)
	if (mapped_pages.find(virtual_address) != mapped_pages.end()) {
		auto mapped = mapped_pages[virtual_address];
		if (mapped.alloc == CoyoteAllocType::PRM) {
				mlock.lock();

				// Unmap and de-allocate bitstream memory
				uint64_t tmp[MAX_USER_ARGS];
				tmp[0] = reinterpret_cast<uint64_t>(virtual_address);
				tmp[1] = static_cast<uint64_t>(this->pid);
				tmp[2] = static_cast<uint64_t>(this->crid);

				if (munmap(mapped.mem, (mapped.size + 1) * HUGE_PAGE_SIZE) != 0) {
					throw std::runtime_error("ERROR munmap() failed");
				} 
				
				if (ioctl(reconfig_dev_fd, IOCTL_FREE_HOST_RECONFIG_MEM, &tmp)) {
					throw std::runtime_error("ERROR: IOCTL_FREE_HOST_RECONFIG_MEM() failed");
				}

				mlock.unlock();
		} else {
			throw std::runtime_error("ERROR: Unauthorized memory deallocation");
		}     
	}
}

uint8_t cRcnfg::readByte(std::ifstream& fb) {
	char temp;
	fb.read(&temp, 1);
	return (uint8_t) temp;
}

bitstream_t cRcnfg::readBitstream(std::ifstream& fb) {
	DBG2("cRcnfg: Called readBitstream to read bitstream from input stream");
	
	// Allocate host-side, kernel memory to hold the bitsream 
	uint32_t len = fb.tellg();
	fb.seekg(0);
	uint32_t n_pages = (len + HUGE_PAGE_SIZE - 1) / HUGE_PAGE_SIZE;
	void *vaddr = getMem({CoyoteAllocType::PRM, n_pages}); 
	uint32_t *vaddr_32 = reinterpret_cast<uint32_t *>(vaddr); 

	// Read the input-stream bytewise and store it bytewise to the mapped memory 
	for (uint32_t i = 0; i < len / 4; i++) {
		vaddr_32[i] = 0;
		vaddr_32[i] |= readByte(fb) << 24;
		vaddr_32[i] |= readByte(fb) << 16;
		vaddr_32[i] |= readByte(fb) << 8;
		vaddr_32[i] |= readByte(fb);
	}

	DBG2("cRcnfg: Shell bitstream loaded");
	return std::make_pair(vaddr, len);
}

void cRcnfg::reconfigureBase(bitstream_t bitstream, uint32_t vfid) {
	DBG2(
		"cRcnfg: reconfigureBase called with virtual address 0x" << std::hex << std::get<0>(bitstream) 
		<< std::dec << ", length " << std::get<1>(bitstream) << " and vFPGA ID " << vfid
	);

	// Arguments to be passed to the driver's IOCTL call
	uint64_t tmp[MAX_USER_ARGS];
	tmp[0] = reinterpret_cast<uint64_t>(std::get<0>(bitstream));
	tmp[1] = static_cast<uint64_t>(std::get<1>(bitstream));
	tmp[2] = static_cast<uint64_t>(pid);
	tmp[3] = static_cast<uint64_t>(crid);

	if(vfid != -1) {
		tmp[4] = static_cast<uint64_t>(vfid);

		DBG2("cRcnfg: Starting app reconfiguration");
		if (ioctl(reconfig_dev_fd, IOCTL_RECONFIGURE_APP, &tmp)) {
			throw std::runtime_error("ERROR: IOCTL_RECONFIGURE_APP failed");
		}
		DBG2("cRcnfg: App reconfiguration completed");
	} else {
		DBG2("cRcnfg: Starting shell reconfiguration");
		if (ioctl(reconfig_dev_fd, IOCTL_RECONFIGURE_SHELL, &tmp)) {
			throw std::runtime_error("ERROR: IOCTL_RECONFIGURE_SHELL failed");
		}
		DBG2("cRcnfg: Shell reconfiguration completed");
	}
}

void cRcnfg::reconfigureShell(std::string bitstream_path) {
	DBG2("cRcnfg: Called reconfigureShell"); 
	
	// Read bitstream from file and trigger reconfiguration
	std::ifstream bitstream_file(bitstream_path, std::ios::ate | std::ios::binary);
	if (!bitstream_file) {
		throw std::runtime_error("ERROR: Shell bitstream could not be opened; please check the provided bitstream path...");
	}
	bitstream_t bitstream = readBitstream(bitstream_file);
	bitstream_file.close();
	reconfigureBase(bitstream);
}

void cRcnfg::reconfigureApp(std::string bitstream_path, int vfid) {
	DBG2("cRcnfg: Called reconfigureApp"); 
	
	// Read bitstream from file and trigger reconfiguration
	std::ifstream bitstream_file(bitstream_path, std::ios::ate | std::ios::binary);
	if (!bitstream_file) {
		throw std::runtime_error("ERROR: App bitstream could not be opened; please check the provided bitstream path...");
	}
	bitstream_t bitstream = readBitstream(bitstream_file);
	bitstream_file.close();
	reconfigureBase(bitstream, vfid);
}

}
