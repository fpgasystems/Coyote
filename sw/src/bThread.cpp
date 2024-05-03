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
#include <syslog.h>
#include <random>

#include "bThread.hpp"

using namespace std::chrono;

namespace fpga {

// ======-------------------------------------------------------------------------------
// Notification handler
// ======-------------------------------------------------------------------------------

int eventHandler(int efd, int terminate_efd, void(*uisr)(int)) {
	struct epoll_event event, events[maxEvents];
	int epoll_fd = epoll_create1(0);
	int running = 1;

	if (epoll_fd == -1) {
		throw new std::runtime_error("failed to create epoll file\n");
	}
	event.events = EPOLLIN;
	event.data.fd = efd;

	if (epoll_ctl(epoll_fd, EPOLL_CTL_ADD, efd, &event)) {
		throw new std::runtime_error("failed to add event to epoll");
	}
	event.events = EPOLLIN;
	event.data.fd = terminate_efd;
	
	if (epoll_ctl(epoll_fd, EPOLL_CTL_ADD, efd, &event)) {
		throw new std::runtime_error("failed to add event to epoll");
	}

	while (running) {
		int event_count = epoll_wait(epoll_fd, events, maxEvents, -1);
		eventfd_t val;
		for (int i = 0; i < event_count; i++) {
			if (events[i].data.fd == efd) {
				eventfd_read(efd, &val);
				uisr(val);
			}
			else if (events[i].data.fd == terminate_efd) {
				running = 0;
			}
		}
	}

	if (close(epoll_fd))  {
		DBG3("Failed to close epoll file!");
	}

	return 0;
}

// ======-------------------------------------------------------------------------------
// bThread management
// ======-------------------------------------------------------------------------------

static unsigned seed = std::chrono::system_clock::now().time_since_epoch().count();

/**
 * @brief Construct a new bThread
 * 
 * @param vfid - vFPGA id
 * @param pid - host process id
 */
bThread::bThread(int32_t vfid, pid_t hpid, uint32_t dev, cSched *csched, void (*uisr)(int)) : vfid(vfid), csched(csched),
		plock(open_or_create, ("vpga_mtx_user_" + std::to_string(vfid)).c_str())
{
	DBG3("bThread:  opening vFPGA-" << vfid << ", hpid " << hpid);
    
	// Open
	std::string region = "/dev/fpga_" + std::to_string(dev) + "_v" + std::to_string(vfid);
	fd = open(region.c_str(), O_RDWR | O_SYNC); 
	if(fd == -1)
		throw std::runtime_error("bThread could not be obtained, vfid: " + to_string(vfid));

	// Registration
	uint64_t tmp[maxUserCopyVals];
    tmp[0] = hpid;
	
	// Register host pid
	if(ioctl(fd, IOCTL_REGISTER_PID, &tmp))
		throw std::runtime_error("ioctl_register_pid() failed");

	DBG2("bThread:  ctor, ctid: " << tmp[1] << ", vfid: " << vfid <<  ", hpid: " << hpid);
	ctid = tmp[1];

	// Cnfg
	if(ioctl(fd, IOCTL_READ_CNFG, &tmp)) 
		throw std::runtime_error("ioctl_read_cnfg() failed");

	fcnfg.parseCnfg(tmp[0]);

    // Events
    if (uisr) {
		tmp[0] = ctid;
		efd = eventfd(0, 0);
		if (efd == -1)
			throw std::runtime_error("bThread could not create eventfd");

		terminate_efd = eventfd(0, 0);
		if (terminate_efd == -1)
			throw std::runtime_error("bThread could not create eventfd");
		
		tmp[1] = efd;
		
		event_thread = std::thread(eventHandler, efd, terminate_efd, uisr);

		if (ioctl(fd, IOCTL_REGISTER_EVENTFD, &tmp))
			throw std::runtime_error("ioctl_eventfd_register() failed");
	}

    // Remote
    qpair = std::make_unique<ibvQp>();

    if(fcnfg.en_rdma) {
        std::default_random_engine rand_gen(seed);
        std::uniform_int_distribution<int> distr(0, std::numeric_limits<std::uint32_t>::max());

        // IP
        if (ioctl(fd, IOCTL_GET_IP_ADDRESS, &tmp))
			throw std::runtime_error("ioctl_get_ip_address() failed");

        uint32_t ibv_ip_addr = (uint32_t) tmp[0];// convert(tmp[0]);
        qpair->local.ip_addr = ibv_ip_addr;
        qpair->local.uintToGid(0, ibv_ip_addr);
        qpair->local.uintToGid(8, ibv_ip_addr);
        qpair->local.uintToGid(16, ibv_ip_addr);
        qpair->local.uintToGid(24, ibv_ip_addr);

        // qpn and psn
        qpair->local.qpn = ((vfid & nRegMask) << pidBits) || (ctid & pidMask);
        if(qpair->local.qpn == -1) 
            throw std::runtime_error("Coyote PID incorrect, vfid: " + std::to_string(vfid));
        qpair->local.psn = distr(rand_gen) & 0xFFFFFF;
        qpair->local.rkey = 0;
    }

	// Mmap
	mmapFpga();

	// Clear
	clearCompleted();

    DBG3("bThread:  ctor finished");
}

/**
 * @brief Destroy the bThread
 * 
 */
bThread::~bThread() {
	DBG2("bThread:   dtor, ctid: " << ctid << ", vfid: " << vfid << ", hpid: " << hpid);
	
	uint64_t tmp[maxUserCopyVals];
    tmp[0] = ctid;

	// Memory
	for(auto& it: mapped_pages) {
		freeMem(it.first);
	}
	mapped_pages.clear();

	munmapFpga();

	ioctl(fd, IOCTL_UNREGISTER_PID, &tmp);

    if (efd != -1) {
		ioctl(fd, IOCTL_UNREGISTER_EVENTFD, &tmp);

		/* Terminate the eventfd thread */
		eventfd_write(terminate_efd, 1);

		/* Wait for termination */
		event_thread.join();

		/* Close file descriptors */
		close(efd);
		close(terminate_efd);
	}

	named_mutex::remove(("vpga_mtx_user_" + std::to_string(vfid)).c_str());

	close(fd);
}

/**
 * @brief MMap vFPGA control plane
 * 
 */
void bThread::mmapFpga() {
	// Config 
#ifdef EN_AVX
	if(fcnfg.en_avx) {
		cnfg_reg_avx = (__m256i*) mmap(NULL, cnfgAvxRegionSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapCnfgAvx);
		if(cnfg_reg_avx == MAP_FAILED)
		 	throw std::runtime_error("cnfg_reg_avx mmap failed");

		DBG3("bThread:  mapped cnfg_reg_avx at: " << std::hex << reinterpret_cast<uint64_t>(cnfg_reg_avx) << std::dec);
	} else {
#endif
		cnfg_reg = (uint64_t*) mmap(NULL, cnfgRegionSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapCnfg);
		if(cnfg_reg == MAP_FAILED)
			throw std::runtime_error("cnfg_reg mmap failed");
		
		DBG3("bThread:  mapped cnfg_reg at: " << std::hex << reinterpret_cast<uint64_t>(cnfg_reg) << std::dec);
#ifdef EN_AVX
	}
#endif

	// Control
	ctrl_reg = (uint64_t*) mmap(NULL, ctrlRegionSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapCtrl);
	if(ctrl_reg == MAP_FAILED) 
		throw std::runtime_error("ctrl_reg mmap failed");
	
	DBG3("bThread:  mapped ctrl_reg at: " << std::hex << reinterpret_cast<uint64_t>(ctrl_reg) << std::dec);

	// Writeback
	if(fcnfg.en_wb) {
		wback = (uint32_t*) mmap(NULL, wbackRegionSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapWb);
		if(wback == MAP_FAILED) 
			throw std::runtime_error("wback mmap failed");

		DBG3("bThread:  mapped writeback regions at: " << std::hex << reinterpret_cast<uint64_t>(wback) << std::dec);
	}
}

/**
 * @brief Munmap vFPGA control plane
 * 
 */
void bThread::munmapFpga() {
	
	// Config
#ifdef EN_AVX
	if(fcnfg.en_avx) {
		if(munmap((void*)cnfg_reg_avx, cnfgAvxRegionSize) != 0) 
			throw std::runtime_error("cnfg_reg_avx munmap failed");
	} else {
#endif
		if(munmap((void*)cnfg_reg, cnfgRegionSize) != 0) 
			throw std::runtime_error("cnfg_reg munmap failed");
#ifdef EN_AVX
	}
#endif

	// Control
	if(munmap((void*)ctrl_reg, ctrlRegionSize) != 0)
		throw std::runtime_error("ctrl_reg munmap failed");

	// Writeback
	if(fcnfg.en_wb) {
		if(munmap((void*)wback, wbackRegionSize) != 0)
			throw std::runtime_error("wback munmap failed");
	}

#ifdef EN_AVX
	cnfg_reg_avx = 0;
#endif
	cnfg_reg = 0;
	ctrl_reg = 0;
	wback = 0;
}

// ======-------------------------------------------------------------------------------
// Schedule threads
// ======-------------------------------------------------------------------------------

/**
 * @brief Obtain vFPGA lock (if scheduler is not present obtain system lock)
 * 
 * @param oid - operator id
 * @param priority - priority
 */
void bThread::pLock(int32_t oid, uint32_t priority) 
{
    if(csched != nullptr) {
        csched->pLock(ctid, oid, priority); 
    } else {
        plock.lock();
    }
}

void bThread::pUnlock() 
{
    if(csched != nullptr) {
        csched->pUnlock(ctid); 
    } else {
        plock.unlock();
    }
}

// ======-------------------------------------------------------------------------------
// Memory management
// ======-------------------------------------------------------------------------------

/**
 * @brief Explicit TLB mapping
 * 
 * @param vaddr - user space address
 * @param len - length 
 */
void bThread::userMap(void *vaddr, uint32_t len, bool remote) {
	uint64_t tmp[maxUserCopyVals];
	tmp[0] = reinterpret_cast<uint64_t>(vaddr);
	tmp[1] = static_cast<uint64_t>(len);
	tmp[2] = static_cast<uint64_t>(ctid);

	if(ioctl(fd, IOCTL_MAP_USER, &tmp))
		throw std::runtime_error("ioctl_map_user() failed");

    if(remote) {
        qpair->local.vaddr = vaddr;
        qpair->local.size = len;

        is_buff_attached = true;
    }
}

/**
 * @brief TLB unmap
 * 
 * @param vaddr - user space address
 */
void bThread::userUnmap(void *vaddr) {
	uint64_t tmp[maxUserCopyVals];
	tmp[0] = reinterpret_cast<uint64_t>(vaddr);
	tmp[1] = static_cast<uint64_t>(ctid);

    if(ioctl(fd, IOCTL_UNMAP_USER, &tmp)) 
        throw std::runtime_error("ioctl_unmap_user() failed");
}

/**
 * @brief Memory allocation
 * 
 * @param cs_alloc - Coyote allocation struct
 * @return void* - pointer to the allocated memory
 */
void* bThread::getMem(csAlloc&& cs_alloc) {
	void *mem = nullptr;
	void *memNonAligned = nullptr;
    int mem_err;
	uint64_t tmp[maxUserCopyVals];

	if(cs_alloc.size > 0) {
		tmp[0] = static_cast<uint64_t>(cs_alloc.size);

		switch (cs_alloc.alloc) 
        {
			case CoyoteAlloc::REG : { // drv lock
				mem = memalign(axiDataWidth, cs_alloc.size);
				userMap(mem, cs_alloc.size);
				
				break;
            }
			case CoyoteAlloc::THP : { // drv lock
                mem_err = posix_memalign(&mem, hugePageSize, cs_alloc.size);
                if(mem_err != 0) {
                    DBG1("ERR:  Failed to allocate transparent hugepages!");
                    return nullptr;
                }
                userMap(mem, cs_alloc.size);

                break;
            }
            case CoyoteAlloc::HPF : { // drv lock
                mem = mmap(NULL, cs_alloc.size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
                userMap(mem, cs_alloc.size);
				
			    break;
            }

			default:
				break;
		}
        
        mapped_pages.emplace(mem, cs_alloc);
		DBG3("Mapped mem at: " << std::hex << reinterpret_cast<uint64_t>(mem) << std::dec);

        if(cs_alloc.remote) {
            qpair->local.vaddr = mem;
            qpair->local.size =  cs_alloc.size;  

            is_buff_attached = true;
        }

	}

	return mem;
}

/**
 * @brief Memory deallocation
 * 
 * @param vaddr - pointer to the allocated memory
 */
void bThread::freeMem(void* vaddr) {
	uint64_t tmp[maxUserCopyVals];
    uint32_t n_pages;
	uint32_t size;

	if(mapped_pages.find(vaddr) != mapped_pages.end()) {
		auto mapped = mapped_pages[vaddr];
		
		switch (mapped.alloc) 
        {
            case CoyoteAlloc::REG : { // drv lock
                userUnmap(vaddr);
                free(vaddr);

                break;
            }
            case CoyoteAlloc::THP : { // drv lock
                //size = mapped.size * (1 << hugePageShift);
                userUnmap(vaddr);
                free(vaddr);

                break;
            }
            case CoyoteAlloc::HPF : { // drv lock
                //size = mapped.size * (1 << hugePageShift);
                userUnmap(vaddr);
                munmap(vaddr, mapped.size);

                break;
            }
            default:
                break;
		}

	    // mapped_pages.erase(vaddr);

        if(mapped.remote) {
            qpair->local.vaddr = 0;
            qpair->local.size =  0;  

            is_buff_attached = false;
        }
	}
}

// ======-------------------------------------------------------------------------------
// Bulk transfers
// ======-------------------------------------------------------------------------------

void bThread::postCmd(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0) {
    //
    // Check outstanding commands
    //
    while (cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr)) {
#ifdef EN_AVX
        cmd_cnt = fcnfg.en_avx ? LOW_32(_mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::CTRL_REG)], 0x0)) :
                                    cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)];
#else
        cmd_cnt = cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)];
#endif
        if (cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr)) 
            std::this_thread::sleep_for(std::chrono::nanoseconds(sleepTime));
    }

    //
    // Send commands
    //
#ifdef EN_AVX
    if(fcnfg.en_avx) {
        // Fire AVX
        cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::CTRL_REG)] = 
            _mm256_set_epi64x(offs_3, offs_2, offs_1, offs_0);
    } else {
#endif
        // Fire legacy
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::VADDR_WR_REG)] = offs_3;
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG_2)] = offs_2;
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::VADDR_RD_REG)] = offs_1;
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)] = offs_0;
#ifdef EN_AVX
    }
#endif

    // Inc
    cmd_cnt++;
}

/**
 * @brief Inovoke data transfers (local)    
 * 
 * @param coper - operation
 * @param sg_list - scatter/gather list
 * @param sg_flags - completion flags
 * @param n_st - number of sg entries
 */
void bThread::invoke(CoyoteOper coper, sgEntry *sg_list, sgFlags sg_flags, uint32_t n_sg) {
	if(isLocalSync(coper)) if(!fcnfg.en_mem) return;
    if(isRemoteRdma(coper)) if(!fcnfg.en_rdma) return;
    if(isRemoteTcp(coper)) if(!fcnfg.en_tcp) return;
	if(coper == CoyoteOper::NOOP) return;

    if(isLocalSync(coper)) { 
        //
        // Sync mem ops
        //

        uint64_t tmp[maxUserCopyVals];
        tmp[1] = ctid;

        if(coper == CoyoteOper::LOCAL_OFFLOAD) {
            // Offload
            for(int i = 0; i < n_sg; i++) {
                tmp[0] = reinterpret_cast<uint64_t>(sg_list[i].sync.addr);
                if(ioctl(fd, IOCTL_OFFLOAD_REQ, &tmp))
		            throw std::runtime_error("ioctl_offload_req() failed");
            }  
        }
        else if (coper == CoyoteOper::LOCAL_SYNC) {
            // Sync
            for(int i = 0; i < n_sg; i++) {
                tmp[0] = reinterpret_cast<uint64_t>(sg_list[i].sync.addr);
                if(ioctl(fd, IOCTL_SYNC_REQ, &tmp))
                    throw std::runtime_error("ioctl_sync_req() failed");
            }
        }
    } else { 
        //
        // Local and remote ops
        //

        uint64_t addr_cmd_src[n_sg], addr_cmd_dst[n_sg];
        uint64_t ctrl_cmd_src[n_sg], ctrl_cmd_dst[n_sg];
        uint64_t addr_cmd_r, addr_cmd_l;
        uint64_t ctrl_cmd_r, ctrl_cmd_l;

        // Clear
        if(sg_flags.clr && fcnfg.en_wb) {
            for(int i = 0; i < nWbacks; i++) {
                wback[ctid + i*nCtidMax] = 0;
            }
        }

        // SG traverse
        for(int i = 0; i < n_sg; i++) {

            //
            // Construct the post cmd
            //
            if(isRemoteTcp(coper)) {
                // TCP
                ctrl_cmd_src[i] = 0;
                addr_cmd_src[i] = 0;
                ctrl_cmd_dst[i] = 
                    ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
                    ((sg_list[i].tcp.stream & CTRL_STRM_MASK) << CTRL_STRM_OFFS) | 
                    ((sg_list[i].tcp.dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
                    ((i == (n_sg-1) ? ((sg_flags.last) ? CTRL_LAST : 0x0) : 0x0)) |
                    (CTRL_START) |
                    (static_cast<uint64_t>(sg_list[i].tcp.len) << CTRL_LEN_OFFS);

                addr_cmd_dst[i] = 0;

           } else if(isRemoteRdma(coper)) {
                // RDMA
                if(qpair->local.ip_addr == qpair->remote.ip_addr) {
                    for(int i = 0; i < n_sg; i++) {
                        void *local_addr = (void*)((uint64_t)qpair->local.vaddr + sg_list[i].rdma.local_offs);
                        void *remote_addr = (void*)((uint64_t)qpair->remote.vaddr + sg_list[i].rdma.remote_offs);

                        memcpy(remote_addr, local_addr, sg_list[i].rdma.len);
                        continue;
                    }
                } else {
                    // Local
                    ctrl_cmd_l =
                        // Cmd l
                        (((static_cast<uint64_t>(coper) - remoteOffsOps) & CTRL_OPCODE_MASK) << CTRL_OPCODE_OFFS) |
                        ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
                        ((sg_list[i].rdma.local_dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
                        ((i == (n_sg-1) ? ((sg_flags.last) ? CTRL_LAST : 0x0) : 0x0)) |
                        ((sg_list[i].rdma.local_stream & CTRL_STRM_MASK) << CTRL_STRM_OFFS) | 
                        (sg_flags.clr ? CTRL_CLR_STAT : 0x0) | 
                        (static_cast<uint64_t>(sg_list[i].rdma.len) << CTRL_LEN_OFFS);
                    
                    addr_cmd_l = static_cast<uint64_t>((uint64_t)qpair->local.vaddr + sg_list[i].rdma.local_offs);

                    // Remote
                    ctrl_cmd_r =                    
                        // Cmd l
                        (((static_cast<uint64_t>(coper) - remoteOffsOps) & CTRL_OPCODE_MASK) << CTRL_OPCODE_OFFS) |
                        ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
                        ((sg_list[i].rdma.remote_dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
                        ((i == (n_sg-1) ? ((sg_flags.last) ? CTRL_LAST : 0x0) : 0x0)) |
                        ((strmRdma & CTRL_STRM_MASK) << CTRL_STRM_OFFS) | 
                        (CTRL_START) |
                        (sg_flags.clr ? CTRL_CLR_STAT : 0x0) | 
                        (static_cast<uint64_t>(sg_list[i].rdma.len) << CTRL_LEN_OFFS);

                    addr_cmd_r = static_cast<uint64_t>((uint64_t)qpair->remote.vaddr + sg_list[i].rdma.remote_offs);  

                    // Order
                    ctrl_cmd_src[i] = isRemoteRead(coper) ? ctrl_cmd_r : ctrl_cmd_l;
                    addr_cmd_src[i] = isRemoteRead(coper) ? addr_cmd_r : addr_cmd_l;
                    ctrl_cmd_dst[i] = isRemoteRead(coper) ? ctrl_cmd_l : ctrl_cmd_r;
                    addr_cmd_dst[i] = isRemoteRead(coper) ? addr_cmd_l : addr_cmd_r;
                }

            } else {
                // Local
                ctrl_cmd_src[i] =
                    // RD
                    ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
                    ((sg_list[i].local.src_dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
                    ((i == (n_sg-1) ? ((sg_flags.last) ? CTRL_LAST : 0x0) : 0x0)) |
                    ((sg_list[i].local.src_stream & CTRL_STRM_MASK) << CTRL_STRM_OFFS) | 
                    (isLocalRead(coper) ? CTRL_START : 0x0) | 
                    (sg_flags.clr ? CTRL_CLR_STAT : 0x0) | 
                    (static_cast<uint64_t>(sg_list[i].local.src_len) << CTRL_LEN_OFFS);

                addr_cmd_src[i] = reinterpret_cast<uint64_t>(sg_list[i].local.src_addr);

                ctrl_cmd_dst[i] =
                    // WR
                    ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
                    ((sg_list[i].local.dst_dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
                    ((i == (n_sg-1) ? ((sg_flags.last) ? CTRL_LAST : 0x0) : 0x0)) |
                    ((sg_list[i].local.dst_stream & CTRL_STRM_MASK) << CTRL_STRM_OFFS) | 
                    (isLocalWrite(coper) ? CTRL_START : 0x0) | 
                    (sg_flags.clr ? CTRL_CLR_STAT : 0x0) | 
                    (static_cast<uint64_t>(sg_list[i].local.dst_len) << CTRL_LEN_OFFS);

                addr_cmd_dst[i] = reinterpret_cast<uint64_t>(sg_list[i].local.dst_addr);
            }

            postCmd(addr_cmd_dst[i], ctrl_cmd_dst[i], addr_cmd_src[i], ctrl_cmd_src[i]);
        }

        // Polling
        if(sg_flags.poll) {
            while(!checkCompleted(coper))
                std::this_thread::sleep_for(std::chrono::nanoseconds(sleepTime)); 
        }
  
    }
}

// ======-------------------------------------------------------------------------------
// Polling
// ======-------------------------------------------------------------------------------

/**
 * @brief Check number of completed operations
 * 
 * @param coper - Coyote operation struct
 * @return uint32_t - number of completed operations
 */
uint32_t bThread::checkCompleted(CoyoteOper coper) {
	if(isCompletedLocalRead(coper)) {
		if(fcnfg.en_wb) {
			return wback[ctid + rdWback*nCtidMax];
		} else {
#ifdef EN_AVX
			if(fcnfg.en_avx) 
				return _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + ctid], 0);
			else 
#endif
				return (LOW_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_DMA_REG) + ctid]));
		}
	}
    else if(isCompletedLocalWrite(coper)) {
		if(fcnfg.en_wb) {
            return wback[ctid + wrWback*nCtidMax];
		} else {
#ifdef EN_AVX
			if(fcnfg.en_avx) 
				return _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + ctid], 1);
			else
#endif
				return (HIGH_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_DMA_REG) + ctid]));
		}
	} else if(isRemoteRead(coper)) {
		if(fcnfg.en_wb) {
			return wback[ctid + rdRdmaWback*nCtidMax];
		} else {
#ifdef EN_AVX
			if(fcnfg.en_avx) 
				return _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + ctid], 2);
			else 
#endif
				return (LOW_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_RDMA_REG) + ctid]));
		}
	} else if(isRemoteWriteOrSend(coper)) {
        if(fcnfg.en_wb) {
            return wback[ctid + wrRdmaWback*nCtidMax];
        } else {
#ifdef EN_AVX
            if(fcnfg.en_avx) 
                return _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + ctid], 3);
            else
#endif
                return (HIGH_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_RDMA_REG) + ctid]));  
        }
    } else {
        return 0;
    }
}

/**
 * @brief Clear completion counters
 * 
 */
void bThread::clearCompleted() {
    if(fcnfg.en_wb) {
        for(int i = 0; i < nWbacks; i++) {
            wback[ctid + i*nCtidMax] = 0;
        }
    }

#ifdef EN_AVX
	if(fcnfg.en_avx) {
		cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::CTRL_REG)] = _mm256_set_epi64x(0, CTRL_CLR_STAT | ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS), 0, CTRL_CLR_STAT | ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS));
    } else 
#endif
    {
		cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG_2)] = CTRL_CLR_STAT | ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS);
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)] = CTRL_CLR_STAT | ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS);
    }
}

// ======-------------------------------------------------------------------------------
// Network management
// ======-------------------------------------------------------------------------------

/**
 * @brief ARP lookup request
 * 
 * @param ip_addr - target IP address
 */
bool bThread::doArpLookup(uint32_t ip_addr) {
#ifdef EN_AVX
	if(fcnfg.en_avx) {
        if(_mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::NET_ARP_REG)], 0))
            cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::NET_ARP_REG)] = _mm256_set_epi64x(0, 0, 0, ip_addr);
        else
            return false;
    } else {
#endif
        if((LOW_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::NET_ARP_REG)])))
            cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::NET_ARP_REG)] = ip_addr;
        else
            return false;
    }

	usleep(arpSleepTime);

    return true;
}

/**
 * @brief Write queue pair context
 * 
 * @param qp - queue pair struct
 */
bool bThread::writeQpContext(uint32_t port) {
    uint64_t offs[3];

    if(fcnfg.en_rdma) {
        // Write QP context
        offs[0] = ((static_cast<uint64_t>(qpair->local.qpn) & 0xffffff) << qpContextQpnOffs) |
                  ((static_cast<uint64_t>(qpair->remote.rkey) & 0xffffffff) << qpContextRkeyOffs) ;

        offs[1] = ((static_cast<uint64_t>(qpair->local.psn) & 0xffffff) << qpContextLpsnOffs) | 
                ((static_cast<uint64_t>(qpair->remote.psn) & 0xffffff) << qpContextRpsnOffs);

        offs[2] = ((static_cast<uint64_t>((uint64_t)qpair->remote.vaddr) & 0xffffffffffff) << qpContextVaddrOffs);

#ifdef EN_AVX
        if(fcnfg.en_avx) {
            if(_mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_CTX_REG)], 0))
                cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_CTX_REG)] = _mm256_set_epi64x(0, offs[2], offs[1], offs[0]);
            else
                return false;
        } else
#endif
        {
            if((LOW_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CTX_REG_2)]))) {
                cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CTX_REG_0)] = offs[0];
                cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CTX_REG_1)] = offs[1];
                cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CTX_REG_2)] = offs[2];
            } else
                return false;
        }

        // Write Conn context
        offs[0] = ((static_cast<uint64_t>(port) & 0xffff) << connContextPortOffs) | 
                ((static_cast<uint64_t>(qpair->remote.qpn) & 0xffffff) << connContextRqpnOffs) | 
                ((static_cast<uint64_t>(qpair->local.qpn) & 0xffff) << connContextLqpnOffs);

        offs[1] = (htols(static_cast<uint64_t>(qpair->remote.gidToUint(8)) & 0xffffffff) << 32) |
                    (htols(static_cast<uint64_t>(qpair->remote.gidToUint(0)) & 0xffffffff) << 0);

        offs[2] = (htols(static_cast<uint64_t>(qpair->remote.gidToUint(24)) & 0xffffffff) << 32) | 
                    (htols(static_cast<uint64_t>(qpair->remote.gidToUint(16)) & 0xffffffff) << 0);

#ifdef EN_AVX
        if(fcnfg.en_avx) {
            if(_mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_CONN_REG)], 0))
                cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_CONN_REG)] = _mm256_set_epi64x(0, offs[2], offs[1], offs[0]);
            else
                return false;
        } else
#endif
        {
            if((LOW_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CONN_REG_2)]))) {
                cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CONN_REG_0)] = offs[0];
                cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CONN_REG_1)] = offs[1];
                cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CONN_REG_2)] = offs[2];
            } else
                return false;
        }

        return true;
    }

    return false;
}

/**
 * @brief Set connection
 */
void bThread::setConnection(int connection) {
    this->connection = connection;
    is_connected = true;
}

/**
 * @brief Close connection
*/
void bThread::closeConnection() {
    if(isConnected()) {
        close(connection);
        is_connected = false;
    }
}

/**
 * Sync with remote
 */
uint32_t bThread::readAck() {
    uint32_t ack;
   
    if (::read(connection, &ack, sizeof(uint32_t)) != sizeof(uint32_t)) {
        ::close(connection);
        throw std::runtime_error("Could not read ack\n");
    }

    return ack;
}

/**
 * Sync with remote
 * @param: ack - acknowledge message
 */
void bThread::sendAck(uint32_t ack) {
    if(::write(connection, &ack, sizeof(uint32_t)) != sizeof(uint32_t))  {
        ::close(connection);
        throw std::runtime_error("Could not send ack\n");
    }
}

/**
 * Wait on close remote
 */
void bThread::closeAck() {
    uint32_t ack;
    
    if (::read(connection, &ack, sizeof(uint32_t)) == 0) {
        ::close(connection);
    }
}

/**
 * Sync with remote
 */
void bThread::connSync(bool client) {
    if(client) {
        sendAck(0);
        readAck();
    } else {
        readAck();
        sendAck(0);
    }
}

/**
 * Close connections
 */
void bThread::connClose(bool client) {
    if(client) {
        sendAck(1);
        closeAck();
    } else {
        readAck();
        closeConnection();
    }
}

// ======-------------------------------------------------------------------------------
// DEBUG
// ======-------------------------------------------------------------------------------

/**
 * Debug
 * 
 */
void bThread::printDebug()
{
	std::cout << "-- STATISTICS - ID: " << getVfid() << std::endl;
	std::cout << "-----------------------------------------------" << std::endl;
#ifdef EN_AVX
	if(fcnfg.en_avx) {
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

}
