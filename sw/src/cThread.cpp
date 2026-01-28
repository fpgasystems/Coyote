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

namespace coyote {

/// Event handler function which processes user interrupts in a dedicated thread
int eventHandler(int fd, int efd, int terminate_efd, std::function<void(int)> uisr, int32_t ctid) {
    DBG1("cThread: Called eventHandler"); 

    // Create events to listen on
	struct epoll_event event, events[MAX_EVENTS]; 
	int epoll_fd = epoll_create1(0); 
	if (epoll_fd == -1) {
		throw std::runtime_error("ERROR: Failed to create epoll file\n");
	}

    // Configure the event for user interrupts
	event.events = EPOLLIN; 
	event.data.fd = efd;
	if (epoll_ctl(epoll_fd, EPOLL_CTL_ADD, efd, &event)) {
		throw std::runtime_error("ERROR: Failed to add efd event to epoll");
	}

    // Configure the event for termination
	event.events = EPOLLIN;
	event.data.fd = terminate_efd;
	if (epoll_ctl(epoll_fd, EPOLL_CTL_ADD, terminate_efd, &event)) {
		throw std::runtime_error("ERROR: Failed to add terminate_efd event to epoll");
	}

    bool running = true;
	while (running) {
		int event_count = epoll_wait(epoll_fd, events, MAX_EVENTS, -1);

		for (int i = 0; i < event_count; i++) {
			// User interrupt, read the eventfd value and call the uisr function
            if (events[i].data.fd == efd) {
                // Read the event, which should return 0 on success
                eventfd_t val;
				if (eventfd_read(efd, &val) != 0) {
                    throw std::runtime_error("ERROR: Failed to read interrupt");
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
                if (ioctl(fd, IOCTL_GET_NOTIFICATION_VALUE, &tmp)) {
                    throw std::runtime_error("ERROR: IOCTL_GET_NOTIFICATION_VALUE failed");
                }
                uint32_t isr_val = tmp[0];
                DBG1("cThread: Caught an event which is " << isr_val);

				uisr(isr_val);

                tmp[0] = ctid;
                if (ioctl(fd, IOCTL_SET_NOTIFICATION_PROCESSED, &tmp)) {
                    throw std::runtime_error("ERROR: IOCTL_SET_NOTIFICATION_PROCESSED failed");
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
	return 0;
}

static unsigned seed = std::chrono::system_clock::now().time_since_epoch().count();

cThread::cThread(int32_t vfid, pid_t hpid, uint32_t device, std::function<void(int)> uisr):
  hpid(hpid), vfid(vfid),
  vlock(boost::interprocess::open_or_create, ("mutex_dev_" + std::to_string(device) + "_vfpa_" + std::to_string(vfid)).c_str()),
  additional_state(nullptr) {
	DBG1("cThread: opening vFPGA " << vfid << ", hpid " << hpid);

	// Open char device with the name specified in the driver
	std::string region = "/dev/coyote_fpga_" + std::to_string(device) + "_v" + std::to_string(vfid);
    this->fd = open(region.c_str(), O_RDWR | O_SYNC); 
	if (fd == -1) { 
        throw std::runtime_error("ERROR: cThread instance could not be obtained, vfid: " + std::to_string(vfid)); 
    }

    // Obtain new Coyote thread ID (ctid) and register it with the driver
	uint64_t tmp[MAX_USER_ARGS];
    tmp[0] = hpid;
	if (ioctl(fd, IOCTL_REGISTER_CTID, &tmp)) { 
        throw std::runtime_error("ERROR: IOCTL_REGISTER_CTID failed"); 
    }
    this->ctid = tmp[1];  
	DBG1("cThread: registered ctid " << ctid);
	
    // Read shell configuration from the driver
	if (ioctl(fd, IOCTL_READ_SHELL_CONFIG, &tmp)) { 
        throw std::runtime_error("ERROR: IOCTL_READ_SHELL_CONFIG failed"); 
    }
    fcnfg.parseCnfg(tmp[0]);
    fcnfg.parseCtrlReg(tmp[1]);

    // Register user interrupt service routine (uisr) and start the interrupt processing thread
    if (uisr) {
        DBG1("cThread: user interrupt service routine provided, trying to create efd and terminate_efd"); 
        
		efd = eventfd(0, 0);
		if (efd == -1) { 
            throw std::runtime_error("ERROR: cThread could not create eventfd"); 
        }

		terminate_efd = eventfd(0, 0);
		if (terminate_efd == -1) { 
            throw std::runtime_error("ERROR: cThread could not create eventfd"); 
        }

        event_thread = std::thread(eventHandler, fd, efd, terminate_efd, uisr, ctid);

        tmp[0] = ctid; 
		tmp[1] = efd;
		if (ioctl(fd, IOCTL_REGISTER_EVENTFD, &tmp)) {
			throw std::runtime_error("ERROR: IOCTL_REGISTER_EVENTFD failed");
        }

        DBG1("cThread: user interrupt service routine registered, thread running..."); 
    }

    // Set the local QP, if RDMA is enabled
    qpair = std::make_unique<ibvQp>();
    if (fcnfg.en_rdma) {
        std::default_random_engine rand_gen(seed);
        std::uniform_int_distribution<int> distr(0, std::numeric_limits<std::uint32_t>::max());

        if (ioctl(fd, IOCTL_GET_IP_ADDRESS, &tmp)) {
			throw std::runtime_error("ERROR: IOCTL_GET_IP_ADDRESS failed");
        }

        uint32_t ibv_ip_addr = (uint32_t) tmp[0];
        qpair->local.ip_addr = ibv_ip_addr;
        qpair->local.uintToGid(0, ibv_ip_addr);
        qpair->local.uintToGid(8, ibv_ip_addr);
        qpair->local.uintToGid(16, ibv_ip_addr);
        qpair->local.uintToGid(24, ibv_ip_addr);

        // QPN is obtained from the vfid and ctid 
        qpair->local.qpn = ((vfid & N_REG_MASK) << PID_BITS) | (ctid & PID_MASK); 
        if (qpair->local.qpn == -1) {
            throw std::runtime_error("ERROR: Coyote PID incorrect, vfid: " + std::to_string(vfid));
        }
        qpair->local.psn = distr(rand_gen) & 0xFFFFFF;      // Generate a random PSN to start with on the local side 
        qpair->local.rkey = 0;                              // Local rkey is hard-coded to 0 

        DBG2("cThread: RDMA is enabled, created the local QP with QPN " << qpair->local.qpn << ", local PSN " << qpair->local.psn << ", and local rkey " << qpair->local.rkey);
    }

	mmapFpga();

	clearCompleted();

    DBG1("cThread: constructor finished");
}

cThread::~cThread() {
	DBG1("cThread: destructor, ctid: " << ctid << ", vfid: " << vfid << ", hpid: " << hpid);

    // Release the lock, if acquired
    if (lock_acquired) {
        vlock.unlock();
        lock_acquired = false;
    }

    // Free user pages and unmap the mapped regions
	uint64_t tmp[MAX_USER_ARGS];
    tmp[0] = ctid;

	for(auto& it: mapped_pages) {
		freeMem(it.first);
	}
	mapped_pages.clear();
	munmapFpga();

    // Unregister Coyote thread ID
	ioctl(fd, IOCTL_UNREGISTER_CTID, &tmp);

    // Terminate user interrupt thread and release the variables
    if (efd != -1) {
		ioctl(fd, IOCTL_UNREGISTER_EVENTFD, &tmp);

		eventfd_write(terminate_efd, 1);
        if (event_thread.joinable()) {
		    event_thread.join();
        }

		close(efd);
		close(terminate_efd);

        ioctl(fd, IOCTL_SET_NOTIFICATION_PROCESSED, &tmp);
	}

    // Disable RDMA, if enabled and set-up
    if (fcnfg.en_rdma && is_connected) {
        closeConn();
    }

	close(fd);
}

void cThread::postCmd(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0) {
    DBG1(
        "cThread: Called postCmd with offsets: " << 
        std::hex << offs_3 << ", " << offs_2 << ", " << offs_1 << ", " << offs_0 << std::dec
    );

    // Check outstanding commands; to avoid oversaturating the command FIFO
    while (cmd_cnt > (CMD_FIFO_DEPTH - CMD_FIFO_THR)) {
        #ifdef EN_AVX
        cmd_cnt = fcnfg.en_avx ? LOW_32(_mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::CTRL_REG)], 0x0)) :
                                cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)];
        #else
        cmd_cnt = cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)];
        #endif

        if (cmd_cnt > (CMD_FIFO_DEPTH - CMD_FIFO_THR)) {
            std::this_thread::sleep_for(std::chrono::nanoseconds(SLEEP_TIME));
        }
    }

    // Send the commands
    #ifdef EN_AVX
    if (fcnfg.en_avx) {
        cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::CTRL_REG)] = _mm256_set_epi64x(offs_3, offs_2, offs_1, offs_0);
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
}

void cThread::mmapFpga() {
    DBG1("cThread: Called mmapFpga");

	// Config 
    #ifdef EN_AVX
	if (fcnfg.en_avx) {
		cnfg_reg_avx = (__m256i*) mmap(NULL, CNFG_AVX_REGION_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_CNFG_AVX);
		if (cnfg_reg_avx == MAP_FAILED) {
		 	throw std::runtime_error("ERROR: cnfg_reg_avx mmap failed");
        }

		DBG1("cThread: mapped cnfg_reg_avx at: " << std::hex << reinterpret_cast<uint64_t>(cnfg_reg_avx) << std::dec);
	} else {
    #endif
		cnfg_reg = (uint64_t*) mmap(NULL, CNFG_REGION_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_CNFG);
		if (cnfg_reg == MAP_FAILED) {
			throw std::runtime_error("ERROR: cnfg_reg mmap failed");
        }
		
		DBG1("cThread: mapped cnfg_reg at: " << std::hex << reinterpret_cast<uint64_t>(cnfg_reg) << std::dec);
    #ifdef EN_AVX
	}
    #endif

	// Control - map the user CSRs into memory 
	ctrl_reg = (uint64_t*) mmap(NULL, CTRL_REGION_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_CTRL);
	if (ctrl_reg == MAP_FAILED) {
		throw std::runtime_error("ERROR: ctrl_reg mmap failed");
    }
	
	DBG1("cThread: mapped ctrl_reg at: " << std::hex << reinterpret_cast<uint64_t>(ctrl_reg) << std::dec);

	// Writeback
	if (fcnfg.en_wb) {
		wback = (uint32_t*) mmap(NULL, WBACK_REGION_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_WB);
		if (wback == MAP_FAILED) {
			throw std::runtime_error("ERROR: wback mmap failed");
        }

		DBG1("cThread: mapped writeback regions at: " << std::hex << reinterpret_cast<uint64_t>(wback) << std::dec);
	}
}

void cThread::munmapFpga() {
	DBG1("cThread: Called munmapFpga");

	// Config
    #ifdef EN_AVX
	if (fcnfg.en_avx) {
		if (munmap((void*)cnfg_reg_avx, CNFG_AVX_REGION_SIZE) != 0) {
			throw std::runtime_error("ERROR: cnfg_reg_avx munmap failed");
        }
	} else {
    #endif
		if (munmap((void*)cnfg_reg, CNFG_REGION_SIZE) != 0) {
			throw std::runtime_error("ERROR: cnfg_reg munmap failed");
        }
    #ifdef EN_AVX
	}
    #endif

	// User CSRs
	if (munmap((void*)ctrl_reg, CTRL_REGION_SIZE) != 0) {
		throw std::runtime_error("ERROR: ctrl_reg munmap failed");
    }

	// Writeback
	if (fcnfg.en_wb) {
		if (munmap((void*)wback, WBACK_REGION_SIZE) != 0) {
			throw std::runtime_error("ERROR: wback munmap failed");
        }
	}

    #ifdef EN_AVX
	cnfg_reg_avx = 0;
    #endif
	cnfg_reg = 0;
	ctrl_reg = 0;
	wback = 0;
}

void cThread::userMap(void *vaddr, uint32_t len) {
    DBG1("cThread: Called userMap to map user buffer, vaddr " << vaddr << ", length " << len << " and ctid " << ctid);

    uint64_t tmp[MAX_USER_ARGS];
	tmp[0] = reinterpret_cast<uint64_t>(vaddr);
	tmp[1] = static_cast<uint64_t>(len);
	tmp[2] = static_cast<uint64_t>(ctid);

    int ret_val = ioctl(fd, IOCTL_MAP_USER_MEM, &tmp);
	if (ret_val) {
        if (ret_val != BUFF_NEEDS_EXP_SYNC_RET_CODE) {
            throw std::runtime_error("ERROR: IOCTL_MAP_USER_MEM failed");
        } else {
            std::cerr << "WARNING: userMap detected that the mapped buffer may need explicit synchronization due to caching effects; see dmesg for more details" << std::endl;
        }
    }
}

void cThread::userUnmap(void *vaddr) {
    DBG1("cThread: Called userUnmap to unmap user buffers");

	uint64_t tmp[MAX_USER_ARGS];
	tmp[0] = reinterpret_cast<uint64_t>(vaddr);
	tmp[1] = static_cast<uint64_t>(ctid);

    if (ioctl(fd, IOCTL_UNMAP_USER_MEM, &tmp)) {
        throw std::runtime_error("ERROR: IOCTL_UNMAP_USER_MEM failed");
    }
}

void* cThread::getMem(CoyoteAlloc&& alloc) {
    DBG1("cThread: Called getMem to obtain memory with size " << alloc.size); 

	void *mem = nullptr;

	if (alloc.size > 0) {
		switch (alloc.alloc)  {
            // Regular allocation 
			case CoyoteAllocType::REG : {
                DBG1("cThread: Obtain regular memory"); 
                mem = mmap(NULL, alloc.size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
				userMap(mem, alloc.size);
				break;
            }

            // Allocation of transparent huge pages  (concatenated regular pages)
			case CoyoteAllocType::THP : {
                DBG1("cThread: Obtain transparent huge page memory"); 
                int ret_val = posix_memalign(&mem, HUGE_PAGE_SIZE, alloc.size);
                if (ret_val != 0) {
                    std::cerr << "ERROR: cThread::getMem() - Failed to allocate transparent hugepages!" << std::endl;;
                    return nullptr;
                }
                userMap(mem, alloc.size);
                break;
            }

            // Allocation of huge pages 
            case CoyoteAllocType::HPF: {
                DBG1("cThread: Obtain huge page memory");

                size_t sz = alloc.size;
                mem = MAP_FAILED;

                int  huge_flag = (fcnfg.ctrl_reg.pg_l_bits << MAP_HUGE_SHIFT);

                mem = mmap(NULL,
                           sz,
                           PROT_READ | PROT_WRITE,
                           MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB | huge_flag,
                           -1,
                           0);

                if (mem != MAP_FAILED) {
                    DBG1("cThread: Allocated huge pages successfully");
                } else {
                int err = errno;
                fprintf(stderr,
                    "cThread: Hugepage allocation failed: Shell pg_l_bits=%u (requested page size = %lu KB), "
                    "alloc.size=%u, errno=%d (%s)\n",
                    fcnfg.ctrl_reg.pg_l_bits,
                    1UL << fcnfg.ctrl_reg.pg_l_bits,
                    alloc.size,
                    err,
                    strerror(err));

                    throw std::runtime_error("Hugepage allocation failed");
                }



                userMap(mem, sz);
                break;
            }


            // GPU memory allocation
            case CoyoteAllocType::GPU : { 
            #ifdef EN_GPU
                /*
                 * Iterate through the GPUs in the sytem until finding
                 * the one that matches the NUMA ID specified in the allocation request.
                 * Additionally, for the GPU that matches, it will visit its meory regions
                 * and ensure there is sufficient memory for allocation.
                 */
                bool taken = false;
                hsa_agent_t gpu_device;
                hsa_region_t region_to_use = { 0 };
                struct get_region_info_params info_params = {
                    .region = &region_to_use,
                    .desired_allocation_size = alloc.size,
                    .agent = &gpu_device,
                    .taken = &taken
                };

                GpuInfo gpu_info;
                gpu_info.information = &info_params;
                gpu_info.requested_gpu = alloc.gpu_dev_id; 
                hsa_status_t err = hsa_iterate_agents(find_gpu, &gpu_info);
                if (err != HSA_STATUS_SUCCESS || !gpu_info.gpu_set) {
                    std::cerr << "GPU not found. You have specified a GPU with an ID that could not be found; please provide a correct GPU ID" << std::endl;
                    return nullptr;
                }
                gpu_device = gpu_info.gpu_device; 

                #ifdef VERBOSE_DEBUG_1
                print_info_region(info_params.region);
                #endif 

                // Allocate the GPU memory
                err = hsa_memory_allocate(*info_params.region, alloc.size, (void **) &(mem)); 
                if (err != HSA_STATUS_SUCCESS) {
                    std::cerr << "ERROR: cThread::getMem() - Failed to allocate GPU memory!" << std::endl;;
                    return nullptr;
                }
                
                // Export the DMA Buffer and register it with the driver
                // NOTE: The memory pointer returned by hsa_memory_allocate may not be aligned
                // to a page boundary. However, DMA Buff physical addresses always start from the
                // the beginning of a page - therefore, the virtual address is realigned by 
                // subtracting the offset returned from HSA.
                size_t offset = 0;
                err = hsa_amd_portable_export_dmabuf(mem, alloc.size, &alloc.gpu_dmabuf_fd, &offset);
                if (err != HSA_STATUS_SUCCESS) {
                    hsa_amd_portable_close_dmabuf(alloc.gpu_dmabuf_fd);
                    hsa_memory_free(mem);
                    std::cerr << "ERROR: cThread::getMem() - GPU DMA Buff export failed!" << std::endl;
                    return nullptr;
                }
                
                uint64_t tmp[MAX_USER_ARGS];
                tmp[0] = alloc.gpu_dmabuf_fd;
                tmp[1] = reinterpret_cast<uint64_t>(mem) - offset;
                tmp[2] = static_cast<uint64_t>(ctid);
                if (ioctl(fd, IOCTL_MAP_DMABUF, &tmp)) {
                    hsa_amd_portable_close_dmabuf(alloc.gpu_dmabuf_fd);
                    hsa_memory_free(mem);
		            throw std::runtime_error("ERROR: IOCTL_MAP_DMABUF failed");
                }
                
                DBG1("Allocated GPU buffer at: " << std::hex << (reinterpret_cast<uint64_t>(mem)) << ", offset: "<< std::dec << offset);

                alloc.mem = mem;
            #else
                throw std::runtime_error("ERROR: GPU support not enabled; please compile the software with DEN_GPU=1");
            #endif
                break;
            }

			default:
				break;
		}
        
        mapped_pages.emplace(mem, alloc);
		DBG1("Mapped mem at: " << std::hex << reinterpret_cast<uint64_t>(mem) << std::dec);

        if (alloc.remote) {
            DBG3("cThread: Allocation is remote, so QP is equipped with the vaddr " << mem << " and has size " << alloc.size);
            qpair->local.vaddr = mem;
            qpair->local.size =  alloc.size;  
        }

	}

	return mem;
}

void cThread::freeMem(void* vaddr) {
    DBG1("cThread: Releasing memory at vaddr " << vaddr);

	if (mapped_pages.find(vaddr) != mapped_pages.end()) {
		auto mapped = mapped_pages[vaddr];
		
		switch (mapped.alloc) {
            case CoyoteAllocType::REG : {
                userUnmap(vaddr);
                munmap(vaddr, mapped.size);
                break;
            }
            case CoyoteAllocType::THP : { 
                userUnmap(vaddr);
                free(vaddr);
                break;
            }
            case CoyoteAllocType::HPF : {
                userUnmap(vaddr);
                munmap(vaddr, mapped.size);
                break;
            }
            case CoyoteAllocType::GPU : {
            #ifdef EN_GPU   
                // Detach and close the DMABuff
                uint64_t tmp[MAX_USER_ARGS];
                tmp[0] = reinterpret_cast<uint64_t>(mapped.mem);
                tmp[1] = static_cast<uint64_t>(ctid);
                if (ioctl(fd, IOCTL_UNMAP_DMABUF, &tmp)) {
                    throw std::runtime_error("ERROR: ioctl_unmap_dmabuf() failed");
                }

                hsa_status_t err = hsa_amd_portable_close_dmabuf(mapped.gpu_dmabuf_fd);
                if (err != HSA_STATUS_SUCCESS) {
                    std::cerr << "ERROR: cThread::getMem() - Exported dmabuf could not be closed!" << std::endl;
                }
                
                // Release the memory
                err = hsa_memory_free(mapped.mem);
                if (err != HSA_STATUS_SUCCESS) {
                    std::cerr << "GPU buffers not freed properly!" << std::endl;
                }
            #else
                throw std::runtime_error("ERROR: GPU support not enabled; please compile the software with DEN_GPU=1");
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
	}
}

void cThread::setCSR(uint64_t val, uint32_t offs) {
    ctrl_reg[offs] = val; 
}

uint64_t cThread::getCSR(uint32_t offs) const {
    return ctrl_reg[offs];
}

void cThread::invoke(CoyoteOper oper, syncSg sg) {
    DBG1("cThread: Call invoke for a sync/offload operation with address " << sg.addr << ", length " << sg.len);

    // Argument checks
    if (!isLocalSync(oper)) {
        throw std::runtime_error("ERROR: cThread::invoke() called with syncSg flags, but the operation is not a LOCAL_SYNC or LOCAL_OFFLOAD; exiting...");
    }

    if (!fcnfg.en_mem) {
        throw std::runtime_error("ERROR: cThread::invoke() called for a sync/offload operation,but the shell was not synthesized with card memory support, exiting...");
    }

    if (sg.len > MAX_TRANSFER_SIZE) {
        throw std::runtime_error("ERROR: cThread::invoke() - transfers over 128MB are currently not supported in Coyote, exiting...");
    }

    // Trigger the operation
    if (oper == CoyoteOper::LOCAL_OFFLOAD) {
        uint64_t tmp[MAX_USER_ARGS];
        tmp[0] = reinterpret_cast<uint64_t>(sg.addr);
        tmp[1] = reinterpret_cast<uint64_t>(sg.len);
        tmp[2] = ctid;
        if (ioctl(fd, IOCTL_OFFLOAD_REQ, &tmp)) {
            throw std::runtime_error("ERROR: IOCTL_OFFLOAD_REQ failed");
        }  
    } else if (oper == CoyoteOper::LOCAL_SYNC) {
        uint64_t tmp[MAX_USER_ARGS];
        tmp[0] = reinterpret_cast<uint64_t>(sg.addr);
        tmp[1] = reinterpret_cast<uint64_t>(sg.len);
        tmp[2] = ctid;
        if (ioctl(fd, IOCTL_SYNC_REQ, &tmp)) {
            throw std::runtime_error("ERROR: IOCTL_SYNC_REQ failed");
        }
    } else {
        std::cerr << "ERROR: cThread::invoke() called with an unsupported operation type; returning..." << std::endl;
        return;
    }
}

void cThread::invoke(CoyoteOper oper, localSg sg, bool last) {
    // Argument checks
    DBG1("cThread: Call invoke for a one-side local operation with address " << sg.addr << ", length " << sg.len);

    if (!isLocalRead(oper) && !isLocalWrite(oper)) {
        throw std::runtime_error("ERROR: cThread::invoke() called with localSg flags, but the operation is not a LOCAL_READ or LOCAL_WRITE; exiting...");
    }

    if (!fcnfg.en_strm && !fcnfg.en_mem) {
        throw std::runtime_error("ERROR: cThread::invoke() called for a local operation, but the shell was not synthesized with streams from host memory, exiting...");
    }

    if (sg.len > MAX_TRANSFER_SIZE) {
        throw std::runtime_error("ERROR: cThread::invoke() - transfers over 128MB are currently not supported in Coyote, exiting...");
    }

    // Trigger the operation
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

        postCmd(0, 0, addr_cmd_src, ctrl_cmd_src);

    } else if (oper == CoyoteOper::LOCAL_WRITE) {
        uint64_t ctrl_cmd_dst =
            ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
            ((sg.dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
            (last ? CTRL_LAST : 0x0) |
            ((sg.stream & CTRL_STRM_MASK) << CTRL_STRM_OFFS) | 
            (CTRL_START) | 
            (0x0) | 
            (static_cast<uint64_t>(sg.len) << CTRL_LEN_OFFS);

        uint64_t addr_cmd_dst = reinterpret_cast<uint64_t>(sg.addr);

        postCmd(addr_cmd_dst, ctrl_cmd_dst, 0, 0);

    } else {
        std::cerr << "ERROR: cThread::invoke() called with an unsupported operation type; returning..." << std::endl;
        return;
    }
}

void cThread::invoke(CoyoteOper oper, localSg src_sg, localSg dst_sg, bool last) {
    // Argument checks
    DBG1(
        "cThread: Call invoke for a two-sided local operation with source address " 
        << src_sg.addr << ", source length " << src_sg.len << "destination address "
        << dst_sg.addr << ", destination length " << dst_sg.len
    );

    if (!(isLocalRead(oper) && isLocalWrite(oper))) {
        throw std::runtime_error("ERROR: cThread::invoke() called with two localSg flags, but the operation is not a LOCAL_TRANSFER; exiting...");
    }

    if (!fcnfg.en_strm && !fcnfg.en_mem) {
        throw std::runtime_error("ERROR: cThread::invoke() called for a local operation but the shell was not synthesized with streams from host memory, exiting...");
    }

    if (src_sg.len > MAX_TRANSFER_SIZE || dst_sg.len > MAX_TRANSFER_SIZE) {
        throw std::runtime_error("ERROR: cThread::invoke() - transfers over 128MB are currently not supported in Coyote, exiting...");
    }

    // Trigger the operation
    if (oper == CoyoteOper::LOCAL_TRANSFER) {
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

        postCmd(addr_cmd_dst, ctrl_cmd_dst, addr_cmd_src, ctrl_cmd_src);

    } else {
        std::cerr << "ERROR: cThread::invoke() called with an unsupported operation type; returning..." << std::endl;
        return;
    }
}

void cThread::invoke(CoyoteOper oper, rdmaSg sg, bool last) {
    // Argument checks
    DBG1("cThread: Call invoke for a RDMA operation with length " << sg.len);

    if (!isRemoteRdma(oper)) {
        throw std::runtime_error("ERROR: cThread::invoke() called with rdmaSg flags, but the operation is not a REMOTE_READ or REMOTE_WRITE; exiting...");
    }

    if (!fcnfg.en_rdma) {
        throw std::runtime_error("ERROR: cThread::invoke() called for an RDMA operation but the shell was not synthesized with RDMA support, exiting...");
    }

    if (sg.len > MAX_TRANSFER_SIZE) {
        throw std::runtime_error("ERROR: cThread::invoke() - transfers over 128MB are currently not supported in Coyote, exiting...");
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

        postCmd(addr_cmd_dst, ctrl_cmd_dst, addr_cmd_src, ctrl_cmd_src);
    }
}

void cThread::invoke(CoyoteOper oper, tcpSg sg, bool last) {
    // Argument checks
    DBG1("cThread: Call invoke for a TCP operation with length " << sg.len);

    if (!isRemoteTcp(oper)) {
        throw std::runtime_error("ERROR: cThread::invoke() called with tcpSg flags, but the operation is not a TCP_SEND; exiting...");
    }

    if (!fcnfg.en_tcp) {
        throw std::runtime_error("ERROR: cThread::invoke() called for a TCP operation, but the shell was not synthesized with TCP support, exiting...");
    }

    if (sg.len > MAX_TRANSFER_SIZE) {
        throw std::runtime_error("ERROR: cThread::invoke() - transfers over 128MB are currently not supported in Coyote, exiting...");
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

    postCmd(addr_cmd_dst, ctrl_cmd_dst, addr_cmd_src, ctrl_cmd_src);
}

uint32_t cThread::checkCompleted(CoyoteOper coper) const {
    DBG1("cThread: Called checkCompleted");
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
				return _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + ctid], 1);
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
            	return _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + ctid], 0);
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
				return _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + ctid], 2);
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
                return _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + ctid], 3);
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
    
    if (fcnfg.en_wb) {
        for (int i = 0; i < N_WBACKS; i++) {
            wback[ctid + i * N_CTID_MAX] = 0;
        }
    }

    #ifdef EN_AVX
	if (fcnfg.en_avx) {
		cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::CTRL_REG)] = _mm256_set_epi64x(0, CTRL_CLR_STAT | ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS), 0, CTRL_CLR_STAT | ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS));
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

    #ifdef EN_AVX
    if (fcnfg.en_avx) {
        cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::NET_ARP_REG)] = _mm256_set_epi64x(0, 0, 0, ip_addr);
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
    if (fcnfg.en_rdma) {
        // Derive register values from QP number, rkey, PSN and virtual address 
        offs[0] = ((static_cast<uint64_t>(qpair->local.qpn) & 0xffffff) << QP_CONTEXT_QPN_OFFS) |
                  ((static_cast<uint64_t>(qpair->remote.rkey) & 0xffffffff) << QP_CONTEXT_RKEY_OFFS);

        offs[1] = ((static_cast<uint64_t>(qpair->local.psn) & 0xffffff) << QP_CONTEXT_LPSN_OFFS) | 
                  ((static_cast<uint64_t>(qpair->remote.psn) & 0xffffff) << QP_CONTEXT_RPSN_OFFS);

        offs[2] = ((static_cast<uint64_t>((uint64_t) qpair->remote.vaddr) & 0xffffffffffff) << QP_CONTEXT_VADDR_OFFS);

    	
        // Write this information to the vFPGA configuration registers
        #ifdef EN_AVX
        if (fcnfg.en_avx) {
            cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_CTX_REG)] = _mm256_set_epi64x(0, offs[2], offs[1], offs[0]);
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
            cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_CONN_REG)] = _mm256_set_epi64x(0, offs[2], offs[1], offs[0]);
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
 
uint32_t cThread::readAck() {
    DBG3("cThread: Called to read an ACK");

    uint32_t ack;   
    if (::read(connfd, &ack, sizeof(uint32_t)) != sizeof(uint32_t)) {
        ::close(connfd);
        throw std::runtime_error("ERROR: Could not read ack\n");
    }

    return ack;
}

void cThread::sendAck(uint32_t ack) {
    DBG3("cThread: Called to send an ACK");

    if (::write(connfd, &ack, sizeof(uint32_t)) != sizeof(uint32_t))  {
        ::close(connfd);
        throw std::runtime_error("ERROR: Could not send ack\n");
    }
}

void cThread::connSync(bool client) {
    DBG3("cThread: Called connSync for handshaking");

    if (client) {
        sendAck(0);
        readAck();
    } else {
        readAck();
        sendAck(0);
    }
}

void* cThread::initRDMA(uint32_t buffer_size, uint16_t port, const char* server_address) {
    // Served address provided, so this node is the client
    if (server_address) {
        DBG3("cThread: initRDMA called from client side with server address " << server_address);

        char* service;
        if (asprintf(&service, "%d", port) < 0) { 
            throw std::runtime_error("ERROR: asprintf() failed"); 
        }

        // Open the out-of-band connection to the server
        struct addrinfo *res;
        struct addrinfo hints = {};
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_STREAM;
        int n = getaddrinfo(server_address, service, &hints, &res);
        if (n < 0) {
            free(service);
            throw std::runtime_error("ERROR: getaddrinfo() failed");
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

        if (connfd < 0) {
            throw std::runtime_error("ERROR: Could not connect to master: " + std::string(server_address) + ":" + std::to_string(port));
        } else {
            is_connected = true;
        }

        // Allocate memory for RDMA operations
        void *mem = getMem({CoyoteAllocType::HPF, buffer_size, true});
        
        // Send the memory address to the server
        if (write(connfd, &(qpair->local), sizeof(ibvQ)) != sizeof(ibvQ)) {
            throw std::runtime_error("ERROR: Failed to send queue to server");
        }

        // Read server's memory address
        char recv_buff[RECV_BUFF_SIZE];
        if (read(connfd, recv_buff, sizeof(ibvQ)) != sizeof(ibvQ)) {
            throw std::runtime_error("ERROR: Failed to read queue from server");
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
            throw std::runtime_error("ERROR: Could not create a socket");
        }

        struct sockaddr_in server; 
        server.sin_family = AF_INET; 
        server.sin_port = htons(port); 
        server.sin_addr.s_addr = INADDR_ANY; 

        if (::bind(sockfd, (struct sockaddr*) &server, sizeof(server)) < 0) {
            throw std::runtime_error("ERROR: Could not bind a socket");
        }

        if (sockfd < 0) {
            throw std::runtime_error("ERROR: Could not listen to a port: " + std::to_string(port));
        }

        if (listen(sockfd, MAX_NUM_CLIENTS) == -1) {
            throw std::runtime_error("ERROR: sockfd listen failed");
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
                ::close(connfd);
                is_connected = false;
                throw std::runtime_error("ERROR: Failed to read queue from client");
            }

            void *mem = getMem({CoyoteAllocType::HPF, buffer_size, true});

            // Send QP to the client
            if (::write(connfd, &(qpair->local), sizeof(ibvQ)) != sizeof(ibvQ))  {
                ::close(connfd);
                is_connected = false;
                throw std::runtime_error("ERROR: Failed to send queue to client");
            }

            //  Write necessary information to the hardware registers
            writeQpContext(port); 
            doArpLookup(qpair->remote.ip_addr); 
            
            std::cout << "Server registered" << std::endl;
            return mem;

        } else {
            throw std::runtime_error("ERROR: Failed to accept connection from client");
        }
    }

}

void cThread::closeConn() {
    DBG3("cThread: Called closeConn to release the out-of-band connection");

    if (is_connected) {
        // sockfd is different than -1, meaning this cThread acted as a server during set-up
        if (sockfd != -1) {
            // Process request close request
            char recv_buf[RECV_BUFF_SIZE];
            if (read(connfd, recv_buf, sizeof(int32_t)) == sizeof(int32_t)) {
                int32_t request;
                memcpy(&request, recv_buf, sizeof(int32_t));
                if (request == DEF_OP_CLOSE_CONN) {
                    close(connfd);
                    connfd = -1;
                    close(sockfd);
                    sockfd = -1;
                    is_connected = false;
                    std::cout << "Successfully closed connection to the client" << std::endl;
                } else {
                    std::cerr << "ERROR: Received an unexpected request from the client: " << request << std::endl;
                }  
            } else {
                std::cerr << "ERROR: Failed to read close connection request from the client" << std::endl;
            }

        // This cThread was a client
        } else {
            int32_t req = DEF_OP_CLOSE_CONN;
            if (write(connfd, &req, sizeof(int32_t)) != sizeof(int32_t)) {
                std::cerr << "ERROR: Failed to send close connection request to the server" << std::endl;
            }
            close(connfd);
            connfd = -1;
            is_connected = false;
            std::cout << "Successfully closed connection to the server" << std::endl;
        }
    }
}

void cThread::lock() {
    DBG3("cThread: Called lock");
    if (!lock_acquired) {
        vlock.lock();
        lock_acquired = true;
    }
}

void cThread::unlock() {
    DBG3("cThread: Called unlock");
    if (lock_acquired) {
        vlock.unlock();
        lock_acquired = false;
    }
}

int32_t cThread::getVfid() const { return vfid;};

int32_t cThread::getCtid() const { return ctid; };

pid_t  cThread::getHpid() const { return hpid; };

ibvQp* cThread::getQpair() const { return qpair.get(); }
	
void cThread::printDebug() const {
	std::cout << "-- STATISTICS - ID: cThread ID" << ctid << ", vFPGA ID" << vfid << std::endl;
	std::cout << "-----------------------------------------------" << std::endl;
    
    #ifdef EN_AVX
	if (fcnfg.en_avx) {
		std::cout << std::setw(35) << "Sent local reads: \t" <<  _mm256_extract_epi64(cnfg_reg_avx[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_0)], 0x0) << std::endl;
        std::cout << std::setw(35) << "Sent local writes: \t" <<  _mm256_extract_epi64(cnfg_reg_avx[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_0)], 0x1) << std::endl;
        std::cout << std::setw(35) << "Sent remote reads: \t" <<  _mm256_extract_epi64(cnfg_reg_avx[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_0)], 0x2) << std::endl;
        std::cout << std::setw(35) << "Sent remote writes: \t" <<  _mm256_extract_epi64(cnfg_reg_avx[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_0)], 0x3) << std::endl;
        
        std::cout << std::setw(35) << "Invalidations received: \t" <<  _mm256_extract_epi64(cnfg_reg_avx[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_1)], 0x0) << std::endl;
        std::cout << std::setw(35) << "Page faults received: \t" <<  _mm256_extract_epi64(cnfg_reg_avx[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_1)], 0x1) << std::endl;
        std::cout << std::setw(35) << "Notifications received: \t" <<  _mm256_extract_epi64(cnfg_reg_avx[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_1)], 0x2) << std::endl;
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
