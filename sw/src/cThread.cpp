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

#include <coyote/cThread.hpp>

#include <chrono>
#include <string>
#include <random>
#include <fstream>
#include <iostream>

#include <fcntl.h>
#include <netdb.h>
#include <syslog.h>

#include <sys/file.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <linux/mman.h>

namespace coyote {

/// Event handler function which processes user interrupts in a dedicated thread; never throws: a failed notification is printed and skipped, the thread stops only if epoll or the eventfd fails
void eventHandler(int fd, int efd, int terminate_efd, std::function<void(int)> uisr, int32_t ctid) {
    DBG1("cThread: Called eventHandler"); 

    // Prints one error line from the current errno
    auto error = [ctid]() {
        int e = errno;
        printError(errnoToError(e), strerror(e), "cThread::eventHandler(ctid=", ctid, ")");
    };

    // Create events to listen on
	struct epoll_event event, events[MAX_EVENTS]; 
	int epoll_fd = epoll_create1(0); 
	if (epoll_fd == -1) {
		error();
		return;
	}

    // Configure the event for user interrupts
	event.events = EPOLLIN; 
	event.data.fd = efd;
	if (epoll_ctl(epoll_fd, EPOLL_CTL_ADD, efd, &event)) {
        close(epoll_fd);
		error();
		return;
	}

    // Configure the event for termination
	event.events = EPOLLIN;
	event.data.fd = terminate_efd;
	if (epoll_ctl(epoll_fd, EPOLL_CTL_ADD, terminate_efd, &event)) {
        close(epoll_fd);
		error();
		return;
	}

    bool running = true;
	while (running) {
		int event_count = epoll_wait(epoll_fd, events, MAX_EVENTS, -1);
        if (event_count == -1 && errno != EINTR) {
            error();
            break;
        }

		for (int i = 0; i < event_count; i++) {
			// User interrupt, read the eventfd value and call the uisr function
            if (events[i].data.fd == efd) {
                // Read the event, which should return 0 on success
                eventfd_t val;
				if (eventfd_read(efd, &val) != 0) {
                    error();
                    running = false;
                    break;
                }

                /* 
                 * Get the interrupt value via IOCTL.
                 * NOTE: Older versions of Coyote used to get the interrupt value directly from
                 * the eventfd. However, recent changes in the API of the kernel made this
                 * implementation infeasible from the coyote driver perspective.
                 * Read the comments in driver/fpga_isr.c, function 'vfpga_notify_handler' for further details.
                 */
                uint64_t tmp[MAX_USER_ARGS];
                tmp[0] = ctid;
                // A failed ioctl loses only this notification: it is still acknowledged, so the driver delivers the next one
                if (ioctl(fd, IOCTL_GET_NOTIFICATION_VALUE, &tmp)) {
                    error();
                } else {
                    uint32_t isr_val = tmp[0];
                    DBG1("cThread: Caught an event which is " << isr_val);
                    uisr(isr_val);
                }

                tmp[0] = ctid;
                if (ioctl(fd, IOCTL_SET_NOTIFICATION_PROCESSED, &tmp)) {
                    error();
                }
			}

            // If event is a terminate_efd, terminate the event thread 
			else if (events[i].data.fd == terminate_efd) {
                DBG1("cThread: eventHandler caught a termination event"); 
				running = false;
			}
		}
	}

	close(epoll_fd);
}

static unsigned seed = std::chrono::system_clock::now().time_since_epoch().count();

cThread::cThread(int32_t vfid, pid_t hpid, uint32_t device, std::function<void(int)> uisr, uint32_t timeout_ms):
  hpid(hpid), vfid(vfid), timeout_ms(timeout_ms), additional_state(nullptr) {
	DBG1("cThread: opening vFPGA " << vfid << ", hpid " << hpid);

    // On failure, print the error, release everything set up so far and leave the cThread invalid (ctid = -1)
    auto abortConstruction = [&](CoyoteError err, const char* step, int e) {
        std::string detail = e ? sysDetail(step, e) : step;
        setError(err, detail.c_str(), "cThread(vfid=", vfid, ", hpid=", hpid, ", device=", device, ")");
        releaseResources();
        ctid = -1;
    };

	// Open char device with the name specified in the driver; not inherited across exec, so a child process cannot keep the ctid alive
	std::string region = "/dev/coyote_fpga_" + std::to_string(device) + "_v" + std::to_string(vfid);
    this->fd = open(region.c_str(), O_RDWR | O_SYNC | O_CLOEXEC); 
	if (fd == -1) { 
        // A missing device node means the card or vFPGA is not there
        int e = errno;
        abortConstruction(e == ENOENT ? CoyoteError::NO_DEVICE : errnoToError(e), ("open " + region).c_str(), e);
        return;
    }

    // Obtain new Coyote thread ID (ctid) and register it with the driver
	uint64_t tmp[MAX_USER_ARGS];
    tmp[0] = hpid;

    try {
	    if (ioctl(fd, IOCTL_REGISTER_CTID, &tmp)) { 
            abortConstruction(errnoToError(errno), "IOCTL_REGISTER_CTID", errno);
            return;
        }
        this->ctid = tmp[1];  
	    DBG1("cThread: registered ctid " << ctid);
	
        // Read shell configuration from the driver
	    if (ioctl(fd, IOCTL_READ_SHELL_CONFIG, &tmp)) { 
            abortConstruction(errnoToError(errno), "IOCTL_READ_SHELL_CONFIG", errno);
            return;
        }
        fcnfg.parseCnfg(tmp[0]);
        fcnfg.parseCtrlReg(tmp[1]);

        // Register user interrupt service routine (uisr) and start the interrupt processing thread
        if (uisr) {
            DBG1("cThread: user interrupt service routine provided, trying to create efd and terminate_efd"); 
        
		    efd = eventfd(0, EFD_CLOEXEC);
		    if (efd == -1) { 
                abortConstruction(errnoToError(errno), "eventfd", errno);
                return;
            }

		    terminate_efd = eventfd(0, EFD_CLOEXEC);
		    if (terminate_efd == -1) { 
                abortConstruction(errnoToError(errno), "eventfd", errno);
                return;
            }

            event_thread = std::thread(eventHandler, fd, efd, terminate_efd, uisr, ctid);

            tmp[0] = ctid; 
		    tmp[1] = efd;
		    if (ioctl(fd, IOCTL_REGISTER_EVENTFD, &tmp)) {
                abortConstruction(errnoToError(errno), "IOCTL_REGISTER_EVENTFD", errno);
                return;
            }

            DBG1("cThread: user interrupt service routine registered, thread running..."); 
        }

        // Set the local QP, if RDMA is enabled
        qpair = std::make_unique<ibvQp>();
        if (fcnfg.en_rdma) {
            std::default_random_engine rand_gen(seed);
            std::uniform_int_distribution<int> distr(0, std::numeric_limits<std::uint32_t>::max());

            if (ioctl(fd, IOCTL_GET_IP_ADDRESS, &tmp)) {
                abortConstruction(errnoToError(errno), "IOCTL_GET_IP_ADDRESS", errno);
                return;
            }

            uint32_t ibv_ip_addr = (uint32_t) tmp[0];
            qpair->local.ip_addr = ibv_ip_addr;
            qpair->local.uintToGid(0, ibv_ip_addr);
            qpair->local.uintToGid(8, ibv_ip_addr);
            qpair->local.uintToGid(16, ibv_ip_addr);
            qpair->local.uintToGid(24, ibv_ip_addr);

            // QPN is obtained from the vfid and ctid 
            qpair->local.qpn = ((vfid & N_REG_MASK) << PID_BITS) | (ctid & PID_MASK); 
            qpair->local.psn = distr(rand_gen) & 0xFFFFFF;      // Generate a random PSN to start with on the local side 
            qpair->local.rkey = 0;                              // Local rkey is hard-coded to 0 

            DBG2("cThread: RDMA is enabled, created the local QP with QPN " << qpair->local.qpn << ", local PSN " << qpair->local.psn << ", and local rkey " << qpair->local.rkey);
        }

        const char* mmap_region = nullptr;
        CoyoteError err = mmapFpga(mmap_region);
        if (err != CoyoteError::OK) {
            abortConstruction(err, mmap_region, errno);
            return;
        }
    } catch (const std::bad_alloc&) {
        // Containers and threads may throw; the constructor does not
        abortConstruction(CoyoteError::NO_MEMORY, "out of memory", 0);
        return;
    } catch (...) {
        abortConstruction(CoyoteError::UNKNOWN, "unexpected exception", 0);
        return;
    }

	clearCompleted();

    DBG1("cThread: constructor finished");
}

cThread::~cThread() {
	DBG1("cThread: destructor, ctid: " << ctid << ", vfid: " << vfid << ", hpid: " << hpid);

    releaseResources();
}

bool cThread::isValid() const { return ctid != -1; }

bool cThread::checkValid(const char* call) const {
    if (!isValid()) {
        printError(CoyoteError::NO_DEVICE, "the cThread is not valid, its constructor failed", "cThread::", call);
    }
    return isValid();
}

CoyoteError cThread::getLastError() const { return last_error; }

void cThread::releaseResources() noexcept {
    // Release the lock, if acquired (closing fd would release it too, unless a forked child still holds fd)
    if (lock_acquired) {
        flock(fd, LOCK_UN);
        lock_acquired = false;
    }

    // Stop the user interrupt thread before close(fd), as it issues ioctls on fd
    if (efd != -1) {
        if (terminate_efd != -1) {
            eventfd_write(terminate_efd, 1);
        }

        if (event_thread.joinable()) {
		    event_thread.join();
        }

        if (terminate_efd != -1) {
            close(terminate_efd);
            terminate_efd = -1;
        }
        close(efd);
        efd = -1;
    }

    // Close the RDMA connection before the buffers are released: the remote side may still access them
    if (fcnfg.en_rdma && is_connected) {
        closeConn();
    }

    // Free user pages and unmap the mapped regions; if freeMem fails (it prints why), drop the entry anyway
	while (!mapped_pages.empty()) {
        void* vaddr = mapped_pages.begin()->first;
        freeMem(vaddr);
        mapped_pages.erase(vaddr);
	}
	munmapFpga();

    // The driver releases the ctid and its eventfd, and anything still mapped, when the fd is closed (vfpga_dev_release)
    // Also called by the destructor of a cThread whose constructor failed, so every step above and below is idempotent
    if (fd != -1) {
	    close(fd);
        fd = -1;
    }
}

// Detail for a failed postCmd()
static const char* postCmdDetail(CoyoteError err) {
    return err == CoyoteError::TIMEOUT ? "the vFPGA did not accept new commands in time" : "FPGA registers not accessible";
}

CoyoteError cThread::postCmd(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0) {
    DBG1(
        "cThread: Called postCmd with offsets: " << 
        std::hex << offs_3 << ", " << offs_2 << ", " << offs_1 << ", " << offs_0 << std::dec
    );

    // Check outstanding commands; to avoid oversaturating the command FIFO
    // Give up after timeout_ms; a card that is gone (e.g., surprise removal) reads all ones
    auto start = std::chrono::steady_clock::now();
    while (cmd_cnt > (CMD_FIFO_DEPTH - CMD_FIFO_THR)) {
        #ifdef EN_AVX
        uint64_t used = fcnfg.en_avx ? LOW_32(_mm256_extract_epi32(avxRegs()[static_cast<uint32_t>(CnfgAvxRegs::CTRL_REG)], 0x0)) :
                                cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)];
        uint64_t all_ones = fcnfg.en_avx ? 0xffffffffULL : ~0ULL;
        #else
        uint64_t used = cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)];
        uint64_t all_ones = ~0ULL;
        #endif

        if (used == all_ones) {
            return CoyoteError::NO_DEVICE;
        }

        cmd_cnt = used;
        if (cmd_cnt > (CMD_FIFO_DEPTH - CMD_FIFO_THR)) {
            if (std::chrono::steady_clock::now() - start > std::chrono::milliseconds(timeout_ms)) {
                return CoyoteError::TIMEOUT;
            }
            std::this_thread::sleep_for(std::chrono::nanoseconds(SLEEP_TIME));
        }
    }

    // Send the commands
    #ifdef EN_AVX
    if (fcnfg.en_avx) {
        avxRegs()[static_cast<uint32_t>(CnfgAvxRegs::CTRL_REG)] = _mm256_set_epi64x(offs_3, offs_2, offs_1, offs_0);
    } else {
    #endif
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::VADDR_WR_REG)] = offs_3;
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG_2)] = offs_2;
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::VADDR_RD_REG)] = offs_1;
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)] = offs_0;
    #ifdef EN_AVX
    }
    #endif

    // Increment
    cmd_cnt++;
    return CoyoteError::OK;
}

CoyoteError cThread::mmapFpga(const char*& region) {
    DBG1("cThread: Called mmapFpga");
    // Staging mmap results prevents assigning MAP_FAILED to member pointers on error
    void* mmap_res = nullptr;

	// Config 
    #ifdef EN_AVX
	if (fcnfg.en_avx) {
		region = "mmap of the AVX config registers";
		mmap_res = (__m256i*) mmap(NULL, CNFG_AVX_REGION_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_CNFG_AVX);
		if (mmap_res == MAP_FAILED) {
			return errnoToError(errno);
        }
        cnfg_reg_avx = (__m256i*) mmap_res;

		DBG1("cThread: mapped cnfg_reg_avx at: " << std::hex << reinterpret_cast<uint64_t>(cnfg_reg_avx) << std::dec);
	} else {
    #endif
		region = "mmap of the config registers";
		mmap_res = (uint64_t*) mmap(NULL, CNFG_REGION_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_CNFG);
		if (mmap_res == MAP_FAILED) {
			return errnoToError(errno);
        }
        cnfg_reg = (uint64_t*) mmap_res;
		
		DBG1("cThread: mapped cnfg_reg at: " << std::hex << reinterpret_cast<uint64_t>(cnfg_reg) << std::dec);
    #ifdef EN_AVX
	}
    #endif

	// Control - map the user CSRs into memory 
	region = "mmap of the user control registers";
	mmap_res = (uint64_t*) mmap(NULL, CTRL_REGION_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_CTRL);
	if (mmap_res == MAP_FAILED) {
		return errnoToError(errno);
    }
    ctrl_reg = (uint64_t*) mmap_res;
	
	DBG1("cThread: mapped ctrl_reg at: " << std::hex << reinterpret_cast<uint64_t>(ctrl_reg) << std::dec);

	// Writeback
	if (fcnfg.en_wb) {
		region = "mmap of the writeback region";
		mmap_res = (uint32_t*) mmap(NULL, WBACK_REGION_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_WB);
		if (mmap_res == MAP_FAILED) {
			return errnoToError(errno);
        }
        wback = (uint32_t*) mmap_res;

		DBG1("cThread: mapped writeback regions at: " << std::hex << reinterpret_cast<uint64_t>(wback) << std::dec);
	}

    return CoyoteError::OK;
}

void cThread::munmapFpga() noexcept {
	DBG1("cThread: Called munmapFpga");

	// Config
    #ifdef EN_AVX
	if (fcnfg.en_avx) {
		if (cnfg_reg_avx != 0) {
			munmap((void*)cnfg_reg_avx, CNFG_AVX_REGION_SIZE);
        }
	} else {
    #endif
		if (cnfg_reg != 0) {
			munmap((void*)cnfg_reg, CNFG_REGION_SIZE);
        }
    #ifdef EN_AVX
	}
    #endif

	// User CSRs
	if (ctrl_reg != 0) {
        munmap((void*)ctrl_reg, CTRL_REGION_SIZE);
    }

	// Writeback
	if (fcnfg.en_wb) {
		if (wback != 0) {
			munmap((void*)wback, WBACK_REGION_SIZE);
        }
	}

    #ifdef EN_AVX
	cnfg_reg_avx = 0;
    #endif
	cnfg_reg = 0;
	ctrl_reg = 0;
	wback = 0;
}

CoyoteError cThread::userMap(void *vaddr, uint64_t len, int32_t mem_block) try {
    DBG1("cThread: Called userMap to map user buffer, vaddr " << vaddr << ", length " << len << ", memory block " << mem_block << " and ctid " << ctid);
    if (!checkValid("userMap")) { return CoyoteError::NO_DEVICE; }

    uint64_t tmp[MAX_USER_ARGS];

    #if defined(EN_ROCM)
    {
        // Detect ROCm device memory via HIP pointer attribute query
        hipPointerAttribute_t attr;
        if (hipPointerGetAttributes(&attr, vaddr) == hipSuccess && attr.type == hipMemoryTypeDevice) {
            // Export the DMA Buffer; the HIP virtual address may not be page-aligned, so
            // the driver receives the page-aligned base (vaddr - offset) via tmp[1].
            int32_t dmabuf_fd;
            size_t offset = 0;
            if (hsa_amd_portable_export_dmabuf(vaddr, len, &dmabuf_fd, &offset) != HSA_STATUS_SUCCESS) {
                setError(CoyoteError::UNKNOWN, "hsa_amd_portable_export_dmabuf failed", "userMap(vaddr=", vaddr, ", len=", len, ")");
                return CoyoteError::UNKNOWN;
            }

            tmp[0] = static_cast<uint64_t>(dmabuf_fd);
            tmp[1] = reinterpret_cast<uint64_t>(vaddr) - offset;
            tmp[2] = static_cast<uint64_t>(ctid);
            tmp[3] = static_cast<uint64_t>(mem_block);
            if (ioctl(fd, IOCTL_MAP_DMABUF, &tmp)) {
                int e = errno;
                hsa_amd_portable_close_dmabuf(dmabuf_fd);
                setError(errnoToError(e), strerror(e), "userMap(vaddr=", vaddr, ", len=", len, ")");
                return errnoToError(e);
            }

            gpu_dmabuf_fds[vaddr] = dmabuf_fd;
            return CoyoteError::OK;
        }
    }
    #endif

    #if defined(EN_CUDA)
    {
        // Detect CUDA device memory via pointer attribute query (requires an active CUDA context)
        unsigned int mem_type = 0;
        CUresult cu_res = cuPointerGetAttribute(&mem_type, CU_POINTER_ATTRIBUTE_MEMORY_TYPE, (CUdeviceptr)(uintptr_t)vaddr);
        if (cu_res == CUDA_SUCCESS && mem_type == CU_MEMORYTYPE_DEVICE) {
            int32_t dmabuf_fd;
            CUresult res = cuMemGetHandleForAddressRange(
                (void*)&dmabuf_fd,
                (CUdeviceptr)(uintptr_t)vaddr,
                len,
                CU_MEM_RANGE_HANDLE_TYPE_DMA_BUF_FD,
                0
            );
            if (res != CUDA_SUCCESS) {
                setError(CoyoteError::UNKNOWN, "cuMemGetHandleForAddressRange failed", "userMap(vaddr=", vaddr, ", len=", len, ")");
                return CoyoteError::UNKNOWN;
            }

            tmp[0] = static_cast<uint64_t>(dmabuf_fd);
            tmp[1] = reinterpret_cast<uint64_t>(vaddr);
            tmp[2] = static_cast<uint64_t>(ctid);
            tmp[3] = static_cast<uint64_t>(mem_block);
            if (ioctl(fd, IOCTL_MAP_DMABUF, &tmp)) {
                int e = errno;
                close(dmabuf_fd);
                setError(errnoToError(e), strerror(e), "userMap(vaddr=", vaddr, ", len=", len, ")");
                return errnoToError(e);
            }

            gpu_dmabuf_fds[vaddr] = dmabuf_fd;
            return CoyoteError::OK;
        }
    }
    #endif

    // Non-GPU path: host memory
	tmp[0] = reinterpret_cast<uint64_t>(vaddr);
	tmp[1] = static_cast<uint64_t>(len);
	tmp[2] = static_cast<uint64_t>(ctid);
	tmp[3] = static_cast<uint64_t>(mem_block);

    int ret_val = ioctl(fd, IOCTL_MAP_USER_MEM, &tmp);
	if (ret_val == -1) {
        int e = errno;
        setError(errnoToError(e), strerror(e), "userMap(vaddr=", vaddr, ", len=", len, ")");
        return errnoToError(e);
    } else if (ret_val == BUFF_NEEDS_EXP_SYNC_RET_CODE) {
        std::cerr << "WARNING: userMap detected that the mapped buffer may need explicit synchronization due to caching effects; see dmesg for more details" << std::endl;
    }

    return CoyoteError::OK;
} catch (const std::bad_alloc&) {
    setError(CoyoteError::NO_MEMORY, nullptr, "userMap(vaddr=", vaddr, ", len=", len, ")");
    return CoyoteError::NO_MEMORY;
}

CoyoteError cThread::userUnmap(void *vaddr) {
    DBG1("cThread: Called userUnmap to unmap user buffers, vaddr " << vaddr);
    if (!checkValid("userUnmap")) { return CoyoteError::NO_DEVICE; }

	uint64_t tmp[MAX_USER_ARGS];
	tmp[0] = reinterpret_cast<uint64_t>(vaddr);
	tmp[1] = static_cast<uint64_t>(ctid);

    auto gpu_it = gpu_dmabuf_fds.find(vaddr);
    if (gpu_it != gpu_dmabuf_fds.end()) {
        // Release the exported dmabuf even if the driver failed to unmap it
        int ret_val = ioctl(fd, IOCTL_UNMAP_DMABUF, &tmp);
        int e = errno;

        #if defined(EN_ROCM)
            if (hsa_amd_portable_close_dmabuf(gpu_it->second) != HSA_STATUS_SUCCESS) {
                std::cerr << "WARNING: cThread::userUnmap() - hsa_amd_portable_close_dmabuf failed" << std::endl;
            }
        #elif defined(EN_CUDA)
            close(gpu_it->second);
        #endif

        gpu_dmabuf_fds.erase(gpu_it);
        if (ret_val) {
            setError(errnoToError(e), strerror(e), "userUnmap(vaddr=", vaddr, ")");
            return errnoToError(e);
        }
        return CoyoteError::OK;
    }

    if (ioctl(fd, IOCTL_UNMAP_USER_MEM, &tmp)) {
        int e = errno;
        setError(errnoToError(e), strerror(e), "userUnmap(vaddr=", vaddr, ")");
        return errnoToError(e);
    }

    return CoyoteError::OK;
}

void* cThread::getMem(CoyoteAlloc&& alloc) try {
    DBG1("cThread: Called getMem to obtain memory with size " << alloc.size); 
    if (!checkValid("getMem")) { return nullptr; }

	void *mem = nullptr;

	if (alloc.size > 0) {
        // On failure, userMap() prints the error; release the allocation and return nullptr
		switch (alloc.alloc)  {
            // Regular allocation 
			case CoyoteAllocType::REG : {
                DBG1("cThread: Obtain regular memory"); 
                mem = mmap(NULL, alloc.size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
                if (mem == MAP_FAILED) {
                    int e = errno;
                    setError(errnoToError(e), strerror(e), "getMem(REG, size=", alloc.size, ")");
                    return nullptr;
                }
				if (userMap(mem, alloc.size, alloc.mem_block) != CoyoteError::OK) {
                    munmap(mem, alloc.size);
                    return nullptr;
                }
				break;
            }

            // Allocation of transparent huge pages  (concatenated regular pages)
			case CoyoteAllocType::THP : {
                DBG1("cThread: Obtain transparent huge page memory"); 
                int ret_val = posix_memalign(&mem, HUGE_PAGE_SIZE, alloc.size);
                if (ret_val != 0) {
                    setError(errnoToError(ret_val), strerror(ret_val), "getMem(THP, size=", alloc.size, ")");
                    return nullptr;
                }
                if (userMap(mem, alloc.size, alloc.mem_block) != CoyoteError::OK) {
                    free(mem);
                    return nullptr;
                }
                break;
            }

            // Allocation of huge pages 
            case CoyoteAllocType::HPF: {
                DBG1("cThread: Obtain huge page memory");

                mem = MAP_FAILED;
                int  huge_flag = (fcnfg.ctrl_reg.pg_l_bits << MAP_HUGE_SHIFT);

                mem = mmap(
                    NULL,
                    alloc.size,
                    PROT_READ | PROT_WRITE,
                    MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB | huge_flag,
                    -1,
                    0
                );

                if (mem != MAP_FAILED) {
                    DBG1("cThread: Allocated huge pages successfully");
                } else {
                    // Typically, no free hugepages of the shell's page size (see /proc/meminfo)
                    int e = errno;
                    setError(errnoToError(e), strerror(e), "getMem(HPF, size=", alloc.size, ", page size=", 1UL << fcnfg.ctrl_reg.pg_l_bits, ")");
                    return nullptr;
                }

                if (userMap(mem, alloc.size, alloc.mem_block) != CoyoteError::OK) {
                    munmap(mem, alloc.size);
                    return nullptr;
                }
                break;
            }


            // GPU memory allocation
            case CoyoteAllocType::GPU : {
            #if defined(EN_ROCM)
                // Verify the current HIP device matches the target before allocating
                int current_hip_dev;
                if (hipGetDevice(&current_hip_dev) != hipSuccess) {
                    setError(CoyoteError::UNKNOWN, "hipGetDevice failed", "getMem(GPU, size=", alloc.size, ")");
                    return nullptr;
                }
                if (current_hip_dev != static_cast<int>(alloc.gpu_dev_id)) {
                    setError(CoyoteError::INVALID_ARG, "current HIP device does not match gpu_dev_id", "getMem(GPU, size=", alloc.size, ", gpu_dev_id=", alloc.gpu_dev_id, ")");
                    return nullptr;
                }

                // Allocate the GPU memory
                if (hipMalloc((void **) &mem, alloc.size)) {
                    setError(CoyoteError::NO_MEMORY, "hipMalloc failed", "getMem(GPU, size=", alloc.size, ")");
                    return nullptr;
                }

                if (userMap(mem, alloc.size, alloc.mem_block) != CoyoteError::OK) {
                    if (hipFree(mem) != hipSuccess) {
                        std::cerr << "WARNING: cThread::getMem() - hipFree failed during cleanup" << std::endl;
                    }
                    return nullptr;
                }

                DBG1("Allocated ROCm GPU memory with address: " << std::hex << reinterpret_cast<uint64_t>(mem) << std::dec);
                alloc.mem = mem;

            #elif defined(EN_CUDA)
                CUresult res;

                // Initialize CUDA Driver API
                res = cuInit(0);
                if (res != CUDA_SUCCESS) {
                    setError(CoyoteError::UNKNOWN, "cuInit failed", "getMem(GPU, size=", alloc.size, ")");
                    return nullptr;
                }

                // Set target device
                CUdevice dev;
                res = cuDeviceGet(&dev, alloc.gpu_dev_id);
                if (res != CUDA_SUCCESS) {
                    setError(CoyoteError::INVALID_ARG, "cuDeviceGet failed", "getMem(GPU, size=", alloc.size, ", gpu_dev_id=", alloc.gpu_dev_id, ")");
                    return nullptr;
                }

                // Check DMA Buffer supported
                int dma_buff_supported = 0;
                res = cuDeviceGetAttribute(
                    &dma_buff_supported,
                    CU_DEVICE_ATTRIBUTE_DMA_BUF_SUPPORTED,
                    dev
                );

                if (res != CUDA_SUCCESS) {
                    setError(CoyoteError::UNKNOWN, "cuDeviceGetAttribute failed", "getMem(GPU, size=", alloc.size, ")");
                    return nullptr;
                }

                if (!dma_buff_supported) {
                    setError(CoyoteError::NOT_SUPPORTED, "the GPU does not support DMA buffers", "getMem(GPU, size=", alloc.size, ")");
                    return nullptr;
                }

                // Obtain & set GPU context
                CUcontext ctx;
                res = cuDevicePrimaryCtxRetain(&ctx, dev);                
                if (res != CUDA_SUCCESS) {
                    setError(CoyoteError::UNKNOWN, "cuDevicePrimaryCtxRetain failed", "getMem(GPU, size=", alloc.size, ")");
                    return nullptr;
                }

                res = cuCtxSetCurrent(ctx);                
                if (res != CUDA_SUCCESS) {
                    setError(CoyoteError::UNKNOWN, "cuCtxSetCurrent failed", "getMem(GPU, size=", alloc.size, ")");
                    cuDevicePrimaryCtxRelease(dev);
                    return nullptr;
                }

                // Allocate memory
                res = cuMemAlloc(&alloc.cu_dev_ptr, alloc.size);
                if (res != CUDA_SUCCESS) {
                    setError(CoyoteError::NO_MEMORY, "cuMemAlloc failed", "getMem(GPU, size=", alloc.size, ")");
                    cuDevicePrimaryCtxRelease(dev);
                    return nullptr;
                }

                mem = (void *) alloc.cu_dev_ptr;

                if (userMap(mem, alloc.size, alloc.mem_block) != CoyoteError::OK) {
                    cuMemFree(alloc.cu_dev_ptr);
                    cuDevicePrimaryCtxRelease(dev);
                    return nullptr;
                }

                DBG1("Allocated CUDA GPU memory with address: " << std::hex << static_cast<uint64_t>(alloc.cu_dev_ptr) << std::dec);
                alloc.mem = mem;
                cuDevicePrimaryCtxRelease(dev);

            #else
                setError(CoyoteError::NOT_SUPPORTED, "compile the software with -DEN_ROCM=1 or -DEN_CUDA=1", "getMem(GPU, size=", alloc.size, ")");
                return nullptr;
            #endif
                break;
            }

            // PRM is reserved for cRcnfg
			default:
                setError(CoyoteError::INVALID_ARG, nullptr, "getMem(type=", static_cast<int>(alloc.alloc), ", size=", alloc.size, ")");
				return nullptr;
		}
        
        mapped_pages.emplace(mem, alloc);
		DBG1("Mapped mem at: " << std::hex << reinterpret_cast<uint64_t>(mem) << std::dec);

        if (alloc.remote) {
            DBG3("cThread: Allocation is remote, so QP is equipped with the vaddr " << mem << " and has size " << alloc.size);
            qpair->local.vaddr = mem;
            qpair->local.size =  alloc.size;  
        }

	} else {
        setError(CoyoteError::INVALID_ARG, nullptr, "getMem(size=0)");
    }

	return mem;
} catch (const std::bad_alloc&) {
    setError(CoyoteError::NO_MEMORY, nullptr, "getMem(size=", alloc.size, ")");
    return nullptr;
}

CoyoteError cThread::freeMem(void* vaddr) {
    DBG1("cThread: Releasing memory at vaddr " << vaddr);
    if (!checkValid("freeMem")) { return CoyoteError::NO_DEVICE; }

	if (mapped_pages.find(vaddr) != mapped_pages.end()) {
		auto mapped = mapped_pages[vaddr];

        // Keep the memory if it cannot be unmapped from the vFPGA; userUnmap() prints the error
        CoyoteError err = userUnmap(vaddr);
        if (err != CoyoteError::OK) {
            return err;
        }
		
		switch (mapped.alloc) {
            case CoyoteAllocType::REG : {
                munmap(vaddr, mapped.size);
                break;
            }
            case CoyoteAllocType::THP : { 
                free(vaddr);
                break;
            }
            case CoyoteAllocType::HPF : {
                munmap(vaddr, mapped.size);
                break;
            }
            case CoyoteAllocType::GPU : {
            #if defined(EN_ROCM)
                // Release the memory
                if (hipFree(mapped.mem)) {
                    setError(CoyoteError::UNKNOWN, "hipFree failed", "freeMem(vaddr=", vaddr, ")");
                    err = CoyoteError::UNKNOWN;
                }

            #elif defined(EN_CUDA)
                CUresult res;

                // Initialize CUDA Driver API
                res = cuInit(0);
                if (res != CUDA_SUCCESS) {
                    setError(CoyoteError::UNKNOWN, "cuInit failed", "freeMem(vaddr=", vaddr, ")");
                    return CoyoteError::UNKNOWN;
                }

                // Set target device
                CUdevice dev;
                res = cuDeviceGet(&dev, mapped.gpu_dev_id);
                if (res != CUDA_SUCCESS) {
                    setError(CoyoteError::UNKNOWN, "cuDeviceGet failed", "freeMem(vaddr=", vaddr, ")");
                    return CoyoteError::UNKNOWN;
                }

                // Obtain & set GPU context
                CUcontext ctx;
                res = cuDevicePrimaryCtxRetain(&ctx, dev);
                if (res != CUDA_SUCCESS) {
                    setError(CoyoteError::UNKNOWN, "cuDevicePrimaryCtxRetain failed", "freeMem(vaddr=", vaddr, ")");
                    return CoyoteError::UNKNOWN;
                }

                res = cuCtxSetCurrent(ctx);
                if (res != CUDA_SUCCESS) {
                    cuDevicePrimaryCtxRelease(dev);
                    setError(CoyoteError::UNKNOWN, "cuCtxSetCurrent failed", "freeMem(vaddr=", vaddr, ")");
                    return CoyoteError::UNKNOWN;
                }

                // Release the memory
                if (cuMemFree(mapped.cu_dev_ptr)) {
                    setError(CoyoteError::UNKNOWN, "cuMemFree failed", "freeMem(vaddr=", vaddr, ")");
                    err = CoyoteError::UNKNOWN;
                }

                // Release context
                cuDevicePrimaryCtxRelease(dev);

            #endif
                break;
            }
            default:
                break;
		}

        // Reset QP, if the allocation was remote
        if (mapped.remote) {
            qpair->local.vaddr = 0;
            qpair->local.size =  0;
        }

        mapped_pages.erase(vaddr);
        return err;
	}

    setError(CoyoteError::INVALID_ARG, "not allocated with getMem", "freeMem(vaddr=", vaddr, ")");
    return CoyoteError::INVALID_ARG;
}

void cThread::setCSR(uint64_t val, uint32_t offs) {
    if (!checkValid("setCSR")) { return; }
    ctrl_reg[offs] = val; 
}

uint64_t cThread::getCSR(uint32_t offs) const {
    if (!checkValid("getCSR")) { return 0; }
    return ctrl_reg[offs];
}

CoyoteError cThread::invoke(CoyoteOper oper, syncSg sg) {
    DBG1("cThread: Call invoke for a sync/offload operation with address " << sg.addr << ", length " << sg.len);
    if (!checkValid("invoke")) { return CoyoteError::NO_DEVICE; }

    auto error = [&](CoyoteError err, const char* detail) {
        setError(err, detail, "invoke(oper=", static_cast<int>(oper), ", addr=", sg.addr, ", len=", sg.len, ")");
        return err;
    };

    // Argument checks
    if (!isLocalSync(oper)) {
        return error(CoyoteError::INVALID_ARG, "syncSg requires LOCAL_SYNC or LOCAL_OFFLOAD");
    }

    if (!fcnfg.en_mem) {
        return error(CoyoteError::NOT_SUPPORTED, "the shell has no card memory");
    }

    if (sg.len > MAX_TRANSFER_SIZE) {
        return error(CoyoteError::INVALID_ARG, "transfers over 128 MB are not supported");
    }

    // Trigger the operation
    if (oper == CoyoteOper::LOCAL_OFFLOAD) {
        uint64_t tmp[MAX_USER_ARGS];
        tmp[0] = reinterpret_cast<uint64_t>(sg.addr);
        tmp[1] = reinterpret_cast<uint64_t>(sg.len);
        tmp[2] = ctid;
        if (ioctl(fd, IOCTL_OFFLOAD_REQ, &tmp)) {
            return error(errnoToError(errno), sysDetail("IOCTL_OFFLOAD_REQ", errno).c_str());
        }  
    } else {
        uint64_t tmp[MAX_USER_ARGS];
        tmp[0] = reinterpret_cast<uint64_t>(sg.addr);
        tmp[1] = reinterpret_cast<uint64_t>(sg.len);
        tmp[2] = ctid;
        if (ioctl(fd, IOCTL_SYNC_REQ, &tmp)) {
            return error(errnoToError(errno), sysDetail("IOCTL_SYNC_REQ", errno).c_str());
        }
    }

    return CoyoteError::OK;
}

CoyoteError cThread::invoke(CoyoteOper oper, localSg sg, bool last) {
    // Argument checks
    DBG1("cThread: Call invoke for a one-side local operation with address " << sg.addr << ", length " << sg.len);
    if (!checkValid("invoke")) { return CoyoteError::NO_DEVICE; }

    auto error = [&](CoyoteError err, const char* detail) {
        setError(err, detail, "invoke(oper=", static_cast<int>(oper), ", addr=", sg.addr, ", len=", sg.len, ")");
        return err;
    };

    if (oper != CoyoteOper::LOCAL_READ && oper != CoyoteOper::LOCAL_WRITE) {
        return error(CoyoteError::INVALID_ARG, "localSg requires LOCAL_READ or LOCAL_WRITE");
    }

    if (!fcnfg.en_strm && !fcnfg.en_mem) {
        return error(CoyoteError::NOT_SUPPORTED, "the shell has no host or card streams");
    }

    if (sg.len > MAX_TRANSFER_SIZE) {
        return error(CoyoteError::INVALID_ARG, "transfers over 128 MB are not supported");
    }

    // Trigger the operation
    CoyoteError err;
    if (oper == CoyoteOper::LOCAL_READ) {
        uint64_t ctrl_cmd_src =
            ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
            ((sg.dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
            (last ? CTRL_LAST : 0x0) |
            ((sg.stream & CTRL_STRM_MASK) << CTRL_STRM_OFFS) | 
            (CTRL_START) | 
            (0x0) | 
            (static_cast<uint64_t>(sg.len) << CTRL_LEN_OFFS);
        
        uint64_t addr_cmd_src = reinterpret_cast<uint64_t>(sg.addr);

        err = postCmd(0, 0, addr_cmd_src, ctrl_cmd_src);

    } else {
        uint64_t ctrl_cmd_dst =
            ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
            ((sg.dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
            (last ? CTRL_LAST : 0x0) |
            ((sg.stream & CTRL_STRM_MASK) << CTRL_STRM_OFFS) | 
            (CTRL_START) | 
            (0x0) | 
            (static_cast<uint64_t>(sg.len) << CTRL_LEN_OFFS);

        uint64_t addr_cmd_dst = reinterpret_cast<uint64_t>(sg.addr);

        err = postCmd(addr_cmd_dst, ctrl_cmd_dst, 0, 0);
    }

    return err == CoyoteError::OK ? err : error(err, postCmdDetail(err));
}

CoyoteError cThread::invoke(CoyoteOper oper, localSg src_sg, localSg dst_sg, bool last) {
    // Argument checks
    DBG1(
        "cThread: Call invoke for a two-sided local operation with source address " 
        << src_sg.addr << ", source length " << src_sg.len << "destination address "
        << dst_sg.addr << ", destination length " << dst_sg.len
    );
    if (!checkValid("invoke")) { return CoyoteError::NO_DEVICE; }

    auto error = [&](CoyoteError err, const char* detail) {
        setError(
            err, detail, "invoke(oper=", static_cast<int>(oper), ", src=", src_sg.addr, ", src_len=", src_sg.len,
            ", dst=", dst_sg.addr, ", dst_len=", dst_sg.len, ")"
        );
        return err;
    };

    if (oper != CoyoteOper::LOCAL_TRANSFER) {
        return error(CoyoteError::INVALID_ARG, "two localSg require LOCAL_TRANSFER");
    }

    if (!fcnfg.en_strm && !fcnfg.en_mem) {
        return error(CoyoteError::NOT_SUPPORTED, "the shell has no host or card streams");
    }

    if (src_sg.len > MAX_TRANSFER_SIZE || dst_sg.len > MAX_TRANSFER_SIZE) {
        return error(CoyoteError::INVALID_ARG, "transfers over 128 MB are not supported");
    }

    // Trigger the operation
    uint64_t ctrl_cmd_src =
        ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
        ((src_sg.dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
        (last ? CTRL_LAST : 0x0) |
        ((src_sg.stream & CTRL_STRM_MASK) << CTRL_STRM_OFFS) |
        (CTRL_START) |
        (0x0) |
        (static_cast<uint64_t>(src_sg.len) << CTRL_LEN_OFFS);

    uint64_t ctrl_cmd_dst =
        ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
        ((dst_sg.dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
        (last ? CTRL_LAST : 0x0) |
        ((dst_sg.stream & CTRL_STRM_MASK) << CTRL_STRM_OFFS) |
        (CTRL_START) |
        (0x0) |
        (static_cast<uint64_t>(dst_sg.len) << CTRL_LEN_OFFS);

    uint64_t addr_cmd_src = reinterpret_cast<uint64_t>(src_sg.addr);
    uint64_t addr_cmd_dst = reinterpret_cast<uint64_t>(dst_sg.addr);

    CoyoteError err = postCmd(addr_cmd_dst, ctrl_cmd_dst, addr_cmd_src, ctrl_cmd_src);
    return err == CoyoteError::OK ? err : error(err, postCmdDetail(err));
}

CoyoteError cThread::invoke(CoyoteOper oper, rdmaSg sg, bool last) {
    // Argument checks
    DBG1("cThread: Call invoke for a RDMA operation with length " << sg.len);
    if (!checkValid("invoke")) { return CoyoteError::NO_DEVICE; }

    auto error = [&](CoyoteError err, const char* detail) {
        setError(
            err, detail, "invoke(oper=", static_cast<int>(oper), ", local_offs=", sg.local_offs,
            ", remote_offs=", sg.remote_offs, ", len=", sg.len, ")"
        );
        return err;
    };

    if (!isRemoteRdma(oper)) {
        return error(CoyoteError::INVALID_ARG, "rdmaSg requires REMOTE_RDMA_READ, REMOTE_RDMA_WRITE or REMOTE_RDMA_SEND");
    }

    if (!fcnfg.en_rdma) {
        return error(CoyoteError::NOT_SUPPORTED, "the shell has no RDMA");
    }

    if (sg.len > MAX_TRANSFER_SIZE) {
        return error(CoyoteError::INVALID_ARG, "transfers over 128 MB are not supported");
    }

    // Trigger the operation
    if (qpair->local.ip_addr == qpair->remote.ip_addr) {
        DBG1("cThread: remote and local node for RDMA operation are identical; calling memcpy");
        
        void *local_addr = (void*) ((uint64_t) qpair->local.vaddr + sg.local_offs);
        void *remote_addr = (void*) ((uint64_t) qpair->remote.vaddr + sg.remote_offs);
        memcpy(remote_addr, local_addr, sg.len);

    } else {
        // Local command and address
        uint64_t ctrl_cmd_l =
            (((static_cast<uint64_t>(oper) - REMOTE_OFFS_OPS) & CTRL_OPCODE_MASK) << CTRL_OPCODE_OFFS) |
            ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
            ((sg.local_dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
            (last ? CTRL_LAST : 0x0) |
            ((sg.local_stream & CTRL_STRM_MASK) << CTRL_STRM_OFFS) | 
            (0x0) | 
            (static_cast<uint64_t>(sg.len) << CTRL_LEN_OFFS);
        
        uint64_t addr_cmd_l = static_cast<uint64_t>((uint64_t) qpair->local.vaddr + sg.local_offs);

        // Remote command and address
        uint64_t ctrl_cmd_r =                    
            (((static_cast<uint64_t>(oper) - REMOTE_OFFS_OPS) & CTRL_OPCODE_MASK) << CTRL_OPCODE_OFFS) |
            ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
            ((sg.remote_dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
            (last ? CTRL_LAST : 0x0) |
            ((STRM_RDMA & CTRL_STRM_MASK) << CTRL_STRM_OFFS) | 
            (CTRL_START) |
            (0x0) | 
            (static_cast<uint64_t>(sg.len) << CTRL_LEN_OFFS);

        uint64_t addr_cmd_r = static_cast<uint64_t>((uint64_t) qpair->remote.vaddr + sg.remote_offs); 

        // Order - based on the distinction between Read and Write, determine what is source and what is destination 
        uint64_t ctrl_cmd_src = isRemoteRead(oper) ? ctrl_cmd_r : ctrl_cmd_l;
        uint64_t addr_cmd_src = isRemoteRead(oper) ? addr_cmd_r : addr_cmd_l;
        uint64_t ctrl_cmd_dst = isRemoteRead(oper) ? ctrl_cmd_l : ctrl_cmd_r;
        uint64_t addr_cmd_dst = isRemoteRead(oper) ? addr_cmd_l : addr_cmd_r;

        CoyoteError err = postCmd(addr_cmd_dst, ctrl_cmd_dst, addr_cmd_src, ctrl_cmd_src);
        if (err != CoyoteError::OK) {
            return error(err, postCmdDetail(err));
        }
    }

    return CoyoteError::OK;
}

CoyoteError cThread::invoke(CoyoteOper oper, tcpSg sg, bool last) {
    // Argument checks
    DBG1("cThread: Call invoke for a TCP operation with length " << sg.len);
    if (!checkValid("invoke")) { return CoyoteError::NO_DEVICE; }

    auto error = [&](CoyoteError err, const char* detail) {
        setError(err, detail, "invoke(oper=", static_cast<int>(oper), ", len=", sg.len, ")");
        return err;
    };

    if (!isRemoteTcp(oper)) {
        return error(CoyoteError::INVALID_ARG, "tcpSg requires REMOTE_TCP_SEND");
    }

    if (!fcnfg.en_tcp) {
        return error(CoyoteError::NOT_SUPPORTED, "the shell has no TCP");
    }

    if (sg.len > MAX_TRANSFER_SIZE) {
        return error(CoyoteError::INVALID_ARG, "transfers over 128 MB are not supported");
    }

    // Trigger the operation
    uint64_t ctrl_cmd_src = 0;
    uint64_t ctrl_cmd_dst = 
        ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
        ((sg.stream & CTRL_STRM_MASK) << CTRL_STRM_OFFS) | 
        ((sg.dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
        (last ? CTRL_LAST : 0x0) |
        (CTRL_START) |
        (static_cast<uint64_t>(sg.len) << CTRL_LEN_OFFS);

    uint64_t addr_cmd_src = 0;
    uint64_t addr_cmd_dst = 0;

    CoyoteError err = postCmd(addr_cmd_dst, ctrl_cmd_dst, addr_cmd_src, ctrl_cmd_src);
    return err == CoyoteError::OK ? err : error(err, postCmdDetail(err));
}

uint32_t cThread::checkCompleted(CoyoteOper coper) const {
    DBG1("cThread: Called checkCompleted");
    if (!checkValid("checkCompleted")) { return 0; }

    /*
     * The order of these if-else clauses is very important in this function
     * LOCAL_TRANSFER are two-sided operations, which means isLocalRead and isLocalWrite
     * will be true at the same time for LOCAL_TRANSFER operations.
     * However, by definition, writes happen after reads, so if we check for reads first,
     * it may return true before the write is actually completed. So here, we must check 
     * for writes first, then reads, and finally remote operations.
     */
	if (isLocalWrite(coper)) {
		if (fcnfg.en_wb) {
            return wback[ctid + WR_WBACK * N_CTID_MAX];
		} else {
            #ifdef EN_AVX
			if (fcnfg.en_avx) 
				return _mm256_extract_epi32(avxRegs()[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + ctid], 1);
			else
            #endif
				return (HIGH_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_DMA_REG) + ctid]));
		}
	} else if (isLocalRead(coper)) {
		if (fcnfg.en_wb) {
			return wback[ctid + RD_WBACK * N_CTID_MAX];
		} else {
            #ifdef EN_AVX
			if (fcnfg.en_avx)
            	return _mm256_extract_epi32(avxRegs()[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + ctid], 0);
			else 
            #endif
				return (LOW_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_DMA_REG) + ctid]));
		}
	} else if (isRemoteRead(coper)) {
		if (fcnfg.en_wb) {
			return wback[ctid + RD_RDMA_WBACK*N_CTID_MAX];
		} else {
            #ifdef EN_AVX
			if (fcnfg.en_avx) 
				return _mm256_extract_epi32(avxRegs()[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + ctid], 2);
			else 
            #endif
				return (LOW_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_RDMA_REG) + ctid]));
		}
	} else if (isRemoteWriteOrSend(coper)) {
        if (fcnfg.en_wb) {
            return wback[ctid + WR_RDMA_WBACK*N_CTID_MAX];
        } else {
            #ifdef EN_AVX
            if (fcnfg.en_avx) 
                return _mm256_extract_epi32(avxRegs()[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + ctid], 3);
            else
            #endif
                return (HIGH_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_RDMA_REG) + ctid]));  
        }
    } else {
        return 0;
    }
}

void cThread::clearCompleted() {
    DBG1("cThread: Called clearCompleted"); 
    if (!checkValid("clearCompleted")) { return; }
    
    if (fcnfg.en_wb) {
        for (int i = 0; i < N_WBACKS; i++) {
            wback[ctid + i * N_CTID_MAX] = 0;
        }
    }

    #ifdef EN_AVX
	if (fcnfg.en_avx) {
		avxRegs()[static_cast<uint32_t>(CnfgAvxRegs::CTRL_REG)] = _mm256_set_epi64x(0, CTRL_CLR_STAT | ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS), 0, CTRL_CLR_STAT | ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS));
    } else {
    #endif
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG_2)] = CTRL_CLR_STAT | ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS);
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)] = CTRL_CLR_STAT | ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS);
    #ifdef EN_AVX
    }
    #endif
}

void cThread::doArpLookup(uint32_t ip_addr) {
    DBG3("cThread: Called doArpLookup for IP address " << ip_addr); 
    if (!checkValid("doArpLookup")) { return; }

    #ifdef EN_AVX
    if (fcnfg.en_avx) {
        avxRegs()[static_cast<uint32_t>(CnfgAvxRegs::NET_ARP_REG)] = _mm256_set_epi64x(0, 0, 0, ip_addr);
    } else {
    #endif
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::NET_ARP_REG)] = ip_addr;
    #ifdef EN_AVX
    }
    #endif

	usleep(SLEEP_TIME);
}

void cThread::writeQpContext(uint32_t port) {
    DBG3("cThread: Called writeQpContext"); 

    uint64_t offs[3];
    if (isValid() && fcnfg.en_rdma) {
        // Derive register values from QP number, rkey, PSN and virtual address 
        offs[0] = ((static_cast<uint64_t>(qpair->local.qpn) & 0xffffff) << QP_CONTEXT_QPN_OFFS) |
                  ((static_cast<uint64_t>(qpair->remote.rkey) & 0xffffffff) << QP_CONTEXT_RKEY_OFFS);

        offs[1] = ((static_cast<uint64_t>(qpair->local.psn) & 0xffffff) << QP_CONTEXT_LPSN_OFFS) | 
                  ((static_cast<uint64_t>(qpair->remote.psn) & 0xffffff) << QP_CONTEXT_RPSN_OFFS);

        offs[2] = ((static_cast<uint64_t>((uint64_t) qpair->remote.vaddr) & 0xffffffffffff) << QP_CONTEXT_VADDR_OFFS);

    	
        // Write this information to the vFPGA configuration registers
        #ifdef EN_AVX
        if (fcnfg.en_avx) {
            avxRegs()[static_cast<uint32_t>(CnfgAvxRegs::RDMA_CTX_REG)] = _mm256_set_epi64x(0, offs[2], offs[1], offs[0]);
        } else {
        #endif
            cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CTX_REG_0)] = offs[0];
            cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CTX_REG_1)] = offs[1];
            cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CTX_REG_2)] = offs[2];
        #ifdef EN_AVX
        }
        #endif

        // Write connection context - port (given as function argument), local and remote QPN, GID etc. to the config registers 
        offs[0] = ((static_cast<uint64_t>(port) & 0xffff) << CONN_CONTEXT_PORT_OFFS) | 
                  ((static_cast<uint64_t>(qpair->remote.qpn) & 0xffffff) << CONN_CONTEXT_RQPN_OFFS) | 
                  ((static_cast<uint64_t>(qpair->local.qpn) & 0xffff) << CONN_CONTEXT_LQPN_OFFS);

        offs[1] = (htols(static_cast<uint64_t>(qpair->remote.gidToUint(8)) & 0xffffffff) << 32) |
                  (htols(static_cast<uint64_t>(qpair->remote.gidToUint(0)) & 0xffffffff) << 0);

        offs[2] = (htols(static_cast<uint64_t>(qpair->remote.gidToUint(24)) & 0xffffffff) << 32) | 
                  (htols(static_cast<uint64_t>(qpair->remote.gidToUint(16)) & 0xffffffff) << 0);

        #ifdef EN_AVX
        if (fcnfg.en_avx) {
            avxRegs()[static_cast<uint32_t>(CnfgAvxRegs::RDMA_CONN_REG)] = _mm256_set_epi64x(0, offs[2], offs[1], offs[0]);
        } else {
        #endif
            cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CONN_REG_0)] = offs[0];
            cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CONN_REG_1)] = offs[1];
            cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CONN_REG_2)] = offs[2];
        #ifdef EN_AVX
        }
        #endif
        
        usleep(SLEEP_TIME);
    }
}
 
CoyoteError cThread::readAck(uint32_t& ack) {
    DBG3("cThread: Called to read an ACK");

    ssize_t n = ::read(connfd, &ack, sizeof(uint32_t));
    if (n != sizeof(uint32_t)) {
        // Connection closed or short read
        if (n >= 0) { errno = ECONNRESET; }
        return errnoToError(errno);
    }

    return CoyoteError::OK;
}

CoyoteError cThread::sendAck(uint32_t ack) {
    DBG3("cThread: Called to send an ACK");

    ssize_t n = ::write(connfd, &ack, sizeof(uint32_t));
    if (n != sizeof(uint32_t))  {
        if (n >= 0) { errno = ECONNRESET; }
        return errnoToError(errno);
    }

    return CoyoteError::OK;
}

CoyoteError cThread::connSync(bool client) {
    DBG3("cThread: Called connSync for handshaking");
    if (!checkValid("connSync")) { return CoyoteError::NO_DEVICE; }

    uint32_t ack;
    const char* step = client ? "send ack" : "read ack";
    CoyoteError err = client ? sendAck(0) : readAck(ack);
    if (err == CoyoteError::OK) {
        step = client ? "read ack" : "send ack";
        err = client ? readAck(ack) : sendAck(0);
    }

    if (err != CoyoteError::OK) {
        setError(err, sysDetail(step, errno).c_str(), "connSync(client=", client, ")");
    }
    return err;
}

void* cThread::initRDMA(uint64_t buffer_size, uint16_t port, const char* server_address, void* mem) {
    if (!checkValid("initRDMA")) { return nullptr; }

    // Prints the error, closes the out-of-band connection and returns nullptr
    auto error = [&](CoyoteError err, const char* detail) -> void* {
        setError(err, detail, "initRDMA(size=", buffer_size, ", port=", port, ", server=", server_address ? server_address : "none", ")");
        releaseConn();
        return nullptr;
    };

    // Served address provided, so this node is the client
    if (server_address) {
        DBG3("cThread: initRDMA called from client side with server address " << server_address);

        char* service;
        if (asprintf(&service, "%d", port) < 0) { 
            return error(CoyoteError::NO_MEMORY, "asprintf failed");
        }

        // Open the out-of-band connection to the server
        struct addrinfo *res;
        struct addrinfo hints = {};
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_STREAM;
        int n = getaddrinfo(server_address, service, &hints, &res);
        free(service);
        if (n != 0) {
            return error(CoyoteError::INVALID_ARG, gai_strerror(n));
        }

        struct addrinfo *t;
        for (t = res; t; t = t->ai_next) {
            connfd = ::socket(t->ai_family, t->ai_socktype, t->ai_protocol);
            if (connfd >= 0) {
                if (!::connect(connfd, t->ai_addr, t->ai_addrlen)) {
                    break;
                } else {
                    ::close(connfd);
                    connfd = -1;
                }
            }
        }
        freeaddrinfo(res);

        if (connfd < 0) {
            return error(errnoToError(errno), sysDetail("connect", errno).c_str());
        } else {
            is_connected = true;
        }

        // Allocate memory for RDMA operations, or use the user-provided staging buffer; getMem prints the error
        if (mem == nullptr) {
            mem = getMem({CoyoteAllocType::HPF, buffer_size, true});
            if (mem == nullptr) {
                releaseConn();
                return nullptr;
            }
        } else {
            qpair->local.vaddr = mem;
            qpair->local.size  = buffer_size;
        }

        // Send the memory address to the server
        if (write(connfd, &(qpair->local), sizeof(ibvQ)) != sizeof(ibvQ)) {
            return error(CoyoteError::UNKNOWN, "failed to send the queue pair to the server");
        }

        // Read server's memory address
        char recv_buff[RECV_BUFF_SIZE];
        if (read(connfd, recv_buff, sizeof(ibvQ)) != sizeof(ibvQ)) {
            return error(CoyoteError::UNKNOWN, "failed to read the queue pair from the server");
        }
        memcpy(&(qpair->remote), recv_buff, sizeof(ibvQ));

        // Write necessary information to the hardware registers
        writeQpContext(port);
        doArpLookup(qpair->remote.ip_addr);
        
        // Debug info
        std::cout << "Queue pair: " << std::endl;
        qpair->local.print("Local: ");
        qpair->remote.print("Remote: ");
        std::cout << "Client registered" << std::endl;

        return mem;
    
    // Served address not provided, so this node is the server
    } else {
        DBG3("cThread: initRDMA called from server side");

        // Accept connections on the specified port from the client(s)
        sockfd = ::socket(AF_INET, SOCK_STREAM, 0); 
        if (sockfd == -1) {
            return error(errnoToError(errno), sysDetail("socket", errno).c_str());
        }

        int optval = 1;
        ::setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval));

        struct sockaddr_in server; 
        server.sin_family = AF_INET; 
        server.sin_port = htons(port); 
        server.sin_addr.s_addr = INADDR_ANY; 

        if (::bind(sockfd, (struct sockaddr*) &server, sizeof(server)) < 0) {
            return error(errnoToError(errno), sysDetail("bind", errno).c_str());
        }

        if (listen(sockfd, MAX_NUM_CLIENTS) == -1) {
            return error(errnoToError(errno), sysDetail("listen", errno).c_str());
        }

        if ((connfd = ::accept(sockfd, NULL, 0)) != -1) {
            is_connected = true;
            uint32_t n; 

            // Allocate a receive buffer for data sent through the out-of-band connection
            char recv_buf[RECV_BUFF_SIZE]; 
            memset(recv_buf, 0, RECV_BUFF_SIZE); 
            
            // Read QP from the client
            if ((n = ::read(connfd, recv_buf, sizeof(ibvQ))) == sizeof(ibvQ)) {
                memcpy(&(qpair->remote), recv_buf, sizeof(ibvQ));
            } else {
                return error(CoyoteError::UNKNOWN, "failed to read the queue pair from the client");
            }

            if (mem == nullptr) {
                mem = getMem({CoyoteAllocType::HPF, buffer_size, true});
                if (mem == nullptr) {
                    releaseConn();
                    return nullptr;
                }
            } else {
                qpair->local.vaddr = mem;
                qpair->local.size  = buffer_size;
            }

            // Send QP to the client
            if (::write(connfd, &(qpair->local), sizeof(ibvQ)) != sizeof(ibvQ))  {
                return error(CoyoteError::UNKNOWN, "failed to send the queue pair to the client");
            }

            //  Write necessary information to the hardware registers
            writeQpContext(port); 
            doArpLookup(qpair->remote.ip_addr); 
            
            std::cout << "Server registered" << std::endl;
            return mem;

        } else {
            return error(errnoToError(errno), sysDetail("accept", errno).c_str());
        }
    }

}

void cThread::releaseConn() {
    if (connfd != -1) {
        ::close(connfd);
        connfd = -1;
    }
    if (sockfd != -1) {
        ::close(sockfd);
        sockfd = -1;
    }
    is_connected = false;
}

void cThread::closeConn() {
    DBG3("cThread: Called closeConn to release the out-of-band connection");
    if (!checkValid("closeConn")) { return; }

    if (is_connected) {
        // sockfd is different than -1, meaning this cThread acted as a server during set-up
        if (sockfd != -1) {
            // Process request close request
            char recv_buf[RECV_BUFF_SIZE];
            ssize_t n = read(connfd, recv_buf, sizeof(int32_t));
            if (n == sizeof(int32_t)) {
                int32_t request;
                memcpy(&request, recv_buf, sizeof(int32_t));
                if (request == DEF_OP_CLOSE_CONN) {
                    std::cout << "Successfully closed connection to the client" << std::endl;
                } else {
                    std::cerr << "ERROR: Received an unexpected request from the client: " << request << std::endl;
                }
            } else if (n == 0) {
                std::cout << "Client disconnected without a close request. Closing connection" << std::endl;
            } else {
                std::cerr << "ERROR: Failed to read close connection request from the client" << std::endl;
            }
            releaseConn();

        // This cThread was a client
        } else {
            int32_t req = DEF_OP_CLOSE_CONN;
            if (write(connfd, &req, sizeof(int32_t)) != sizeof(int32_t)) {
                std::cerr << "ERROR: Failed to send close connection request to the server" << std::endl;
            }
            releaseConn();
            std::cout << "Successfully closed connection to the server" << std::endl;
        }
    }
}

CoyoteError cThread::lock() {
    DBG3("cThread: Called lock");
    if (!checkValid("lock")) { return CoyoteError::NO_DEVICE; }
    if (lock_acquired) { return CoyoteError::OK; }

    // Poll instead of blocking: a holder that hangs is still alive, so the kernel does not release the lock for it
    auto start = std::chrono::steady_clock::now();
    while (flock(fd, LOCK_EX | LOCK_NB) == -1) {
        int e = errno;
        if (e != EWOULDBLOCK) {
            setError(errnoToError(e), sysDetail("flock", e).c_str(), "lock()");
            return errnoToError(e);
        }
        if (std::chrono::steady_clock::now() - start > std::chrono::milliseconds(timeout_ms)) {
            setError(CoyoteError::TIMEOUT, "another cThread holds the vFPGA lock", "lock()");
            return CoyoteError::TIMEOUT;
        }

        // A signal ends the wait
        struct timespec poll_interval = {0, 1000000};
        if (nanosleep(&poll_interval, nullptr) == -1) {
            e = errno;
            setError(errnoToError(e), sysDetail("waiting for the vFPGA lock", e).c_str(), "lock()");
            return errnoToError(e);
        }
    }
    lock_acquired = true;
    return CoyoteError::OK;
}

CoyoteError cThread::unlock() {
    DBG3("cThread: Called unlock");
    if (!checkValid("unlock")) { return CoyoteError::NO_DEVICE; }

    if (lock_acquired) {
        if (flock(fd, LOCK_UN) == -1) {
            int e = errno;
            setError(errnoToError(e), strerror(e), "unlock()");
            return errnoToError(e);
        }
        lock_acquired = false;
    }
    return CoyoteError::OK;
}

int32_t cThread::getVfid() const { return vfid;};

int32_t cThread::getCtid() const { return ctid; };

pid_t  cThread::getHpid() const { return hpid; };

ibvQp* cThread::getQpair() const { return qpair.get(); }
	
void cThread::printDebug() const {
    if (!checkValid("printDebug")) { return; }
	std::cout << "-- STATISTICS - ID: cThread ID" << ctid << ", vFPGA ID" << vfid << std::endl;
	std::cout << "-----------------------------------------------" << std::endl;
    
    #ifdef EN_AVX
	if (fcnfg.en_avx) {
		std::cout << std::setw(35) << "Sent local reads: \t" <<  _mm256_extract_epi64(avxRegs()[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_0)], 0x0) << std::endl;
        std::cout << std::setw(35) << "Sent local writes: \t" <<  _mm256_extract_epi64(avxRegs()[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_0)], 0x1) << std::endl;
        std::cout << std::setw(35) << "Sent remote reads: \t" <<  _mm256_extract_epi64(avxRegs()[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_0)], 0x2) << std::endl;
        std::cout << std::setw(35) << "Sent remote writes: \t" <<  _mm256_extract_epi64(avxRegs()[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_0)], 0x3) << std::endl;
        
        std::cout << std::setw(35) << "Invalidations received: \t" <<  _mm256_extract_epi64(avxRegs()[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_1)], 0x0) << std::endl;
        std::cout << std::setw(35) << "Page faults received: \t" <<  _mm256_extract_epi64(avxRegs()[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_1)], 0x1) << std::endl;
        std::cout << std::setw(35) << "Notifications received: \t" <<  _mm256_extract_epi64(avxRegs()[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_1)], 0x2) << std::endl;
	} else {
    #endif
		std::cout << std::setw(35) << "Sent local reads: \t" <<  cnfg_reg[static_cast<uint64_t>(CnfgLegRegs::STAT_REG_0)] << std::endl;
        std::cout << std::setw(35) << "Sent local writes: \t" <<  cnfg_reg[static_cast<uint64_t>(CnfgLegRegs::STAT_REG_1)] << std::endl;
        std::cout << std::setw(35) << "Sent remote reads: \t" <<  cnfg_reg[static_cast<uint64_t>(CnfgLegRegs::STAT_REG_2)] << std::endl;
        std::cout << std::setw(35) << "Sent remote writes: \t" <<  cnfg_reg[static_cast<uint64_t>(CnfgLegRegs::STAT_REG_3)] << std::endl;

        std::cout << std::setw(35) << "Invalidations received: \t" <<  cnfg_reg[static_cast<uint64_t>(CnfgLegRegs::STAT_REG_4)] << std::endl;
        std::cout << std::setw(35) << "Page faults received: \t" <<  cnfg_reg[static_cast<uint64_t>(CnfgLegRegs::STAT_REG_5)] << std::endl;
        std::cout << std::setw(35) << "Notifications received: \t" <<  cnfg_reg[static_cast<uint64_t>(CnfgLegRegs::STAT_REG_6)] << std::endl;	
    #ifdef EN_AVX
	}
    #endif

	std::cout << std::endl;
}

// Empty additional state class because we only need this for the simulation environment.
class cThread::AdditionalState {};

}
