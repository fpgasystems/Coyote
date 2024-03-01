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

#include "cThread.hpp"

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
// cThread management
// ======-------------------------------------------------------------------------------

/**
 * @brief Construct a new cThread
 * 
 * @param vfid - vFPGA id
 * @param pid - host process id
 */
cThread::cThread(int32_t vfid, pid_t hpid, csDev dev, cSched *csched, bool run, void (*uisr)(int)) : vfid(vfid), csched(csched),
		plock(open_or_create, "vpga_mtx_user_" + vfid)
{
	DBG3("cThread:  opening vFPGA-" << vfid << ", hpid " << hpid);
    
	// Open
	std::string region = "/dev/fpga_" + dev.bus + "_" + dev.slot + "_v" + std::to_string(vfid);
	fd = open(region.c_str(), O_RDWR | O_SYNC); 
	if(fd == -1)
		throw std::runtime_error("cThread could not be obtained, vfid: " + to_string(vfid));

	// Registration
	uint64_t tmp[2];
    tmp[0] = hpid;
	
	// Register host pid
	if(ioctl(fd, IOCTL_REGISTER_PID, &tmp))
		throw std::runtime_error("ioctl_register_pid() failed");

	DBG2("cThread:  ctor, ctid: " << tmp[1] << ", vfid: " << vfid <<  ", hpid: " << hpid);
	ctid = tmp[1];

    // Events
    if (uisr) {
		tmp[0] = ctid;
		efd = eventfd(0, 0);
		if (efd == -1)
			throw std::runtime_error("cThread could not create eventfd");

		terminate_efd = eventfd(0, 0);
		if (terminate_efd == -1)
			throw std::runtime_error("cThread could not create eventfd");
		
		tmp[1] = efd;
		
		event_thread = std::thread(eventHandler, efd, terminate_efd, uisr);

		if (ioctl(fd, IOCTL_REGISTER_EVENTFD, &tmp))
			throw std::runtime_error("ioctl_eventfd_register() failed");
	}

	// Cnfg
	if(ioctl(fd, IOCTL_READ_CNFG, &tmp)) 
		throw std::runtime_error("ioctl_read_cnfg() failed");

	fcnfg.parseCnfg(tmp[0]);
	//fcnfg.en_wb = 0;

	// Mmap
	mmapFpga();

	// Clear
	clearCompleted();

    // Start the thread
    if(run) {
        unique_lock<mutex> lck(mtx_task);
        DBG3("cThread:  initial lock");

        c_thread = thread(&cThread::processTasks, this);
        DBG3("cThread:  thread started");

        cv_task.wait(lck);
    }

    DBG3("cThread:  ctor finished");
}

/**
 * @brief Destroy the cThread
 * 
 */
cThread::~cThread() {
	DBG2("cThread:   dtor, ctid: " << ctid << ", vfid: " << vfid << ", hpid: " << hpid);
	
	uint64_t tmp = ctid;

    if(run) {
        run = false;

        DBG3("cThread:  joining");
        c_thread.join();
    }

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

	named_mutex::remove("vfpga_mtx_user_" + vfid);

	close(fd);
}

/**
 * @brief MMap vFPGA control plane
 * 
 */
void cThread::mmapFpga() {
	// Config 
#ifdef EN_AVX
	if(fcnfg.en_avx) {
		cnfg_reg_avx = (__m256i*) mmap(NULL, cnfgAvxRegionSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapCnfgAvx);
		if(cnfg_reg_avx == MAP_FAILED)
		 	throw std::runtime_error("cnfg_reg_avx mmap failed");

		DBG3("cThread::  mapped cnfg_reg_avx at: " << std::hex << reinterpret_cast<uint64_t>(cnfg_reg_avx) << std::dec);
	} else {
#endif
		cnfg_reg = (uint64_t*) mmap(NULL, cnfgRegionSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapCnfg);
		if(cnfg_reg == MAP_FAILED)
			throw std::runtime_error("cnfg_reg mmap failed");
		
		DBG3("cThread:  mapped cnfg_reg at: " << std::hex << reinterpret_cast<uint64_t>(cnfg_reg) << std::dec);
#ifdef EN_AVX
	}
#endif

	// Control
	ctrl_reg = (uint64_t*) mmap(NULL, ctrlRegionSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapCtrl);
	if(ctrl_reg == MAP_FAILED) 
		throw std::runtime_error("ctrl_reg mmap failed");
	
	DBG3("cThread:  mapped ctrl_reg at: " << std::hex << reinterpret_cast<uint64_t>(ctrl_reg) << std::dec);

	// Writeback
	if(fcnfg.en_wb) {
		wback = (uint32_t*) mmap(NULL, wbackRegionSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapWb);
		if(wback == MAP_FAILED) 
			throw std::runtime_error("wback mmap failed");

		DBG3("cThread:  mapped writeback regions at: " << std::hex << reinterpret_cast<uint64_t>(wback) << std::dec);
	}
}

/**
 * @brief Munmap vFPGA control plane
 * 
 */
void cThread::munmapFpga() {
	
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
// Thread management
// ======-------------------------------------------------------------------------------

void cThread::processTasks() {
    cmplVal cmpl_code;
    unique_lock<mutex> lck(mtx_task);
    run = true;
    lck.unlock();
    cv_task.notify_one();

    while(run || !task_queue.empty()) {
        lck.lock();
        if(!task_queue.empty()) {
            if(task_queue.front() != nullptr) {
                
                // Remove next task from the queue
                auto curr_task = std::move(const_cast<std::unique_ptr<bTask>&>(task_queue.front()));
                task_queue.pop();
                lck.unlock();

                DBG3("Process task: vfid: " <<  getVfid() << ", tid: " << curr_task->getTid() 
                    << ", oid: " << curr_task->getOid() << ", prio: " << curr_task->getPriority());

                // Run the task                
                cmpl_code = curr_task->run(this);

                // Completion
                cnt_cmpl++;
                mtx_cmpl.lock();
                cmpl_queue.push({curr_task->getTid(), cmpl_code});
                mtx_cmpl.unlock();
                 
            } else {
                task_queue.pop();
                lck.unlock();
            }
        } else {
            lck.unlock();
        }

        nanosleep(&PAUSE, NULL);
    }
}

// ======-------------------------------------------------------------------------------
// Schedule tasks
// ======-------------------------------------------------------------------------------

cmplEv cThread::getTaskCompletedNext() {
    if(!cmpl_queue.empty()) {
        lock_guard<mutex> lck(mtx_cmpl);
        cmplEv cmpl_ev = cmpl_queue.front();
        cmpl_queue.pop();
        return cmpl_ev;
    } 
    return {-1, {0}};
}

void cThread::scheduleTask(std::unique_ptr<bTask> ctask) {
    lock_guard<mutex> lck2(mtx_task);
    task_queue.emplace(std::move(ctask));
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
void cThread::pLock(int32_t oid, uint32_t priority) 
{
    if(csched != nullptr) {
        csched->pLock(ctid, oid, priority); 
    } else {
        plock.lock();
    }
}

void cThread::pUnlock() 
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
void cThread::userMap(void *vaddr, uint32_t len) {
	uint64_t tmp[3];
	tmp[0] = reinterpret_cast<uint64_t>(vaddr);
	tmp[1] = static_cast<uint64_t>(len);
	tmp[2] = static_cast<uint64_t>(ctid);

	if(ioctl(fd, IOCTL_MAP_USER, &tmp))
		throw std::runtime_error("ioctl_map_user() failed");
}

/**
 * @brief TLB unmap
 * 
 * @param vaddr - user space address
 */
void cThread::userUnmap(void *vaddr) {
	uint64_t tmp[2];
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
void* cThread::getMem(const csAlloc& cs_alloc) {
	void *mem = nullptr;
	void *memNonAligned = nullptr;
    int mem_err;
	uint64_t tmp[2];
	uint32_t size;

	if(cs_alloc.n_pages > 0) {
		tmp[0] = static_cast<uint64_t>(cs_alloc.n_pages);
		tmp[1] = static_cast<uint64_t>(ctid);

		switch (cs_alloc.alloc) {
			case CoyoteAlloc::REG : // drv lock
				size = cs_alloc.n_pages * (1 << pageShift);
				mem = memalign(axiDataWidth, size);
				userMap(mem, size);
				
				break;

			case CoyoteAlloc::THP : // drv lock
                size = cs_alloc.n_pages * (1 << hugePageShift);
                mem_err = posix_memalign(&mem, hugePageSize, size);
                if(mem_err != 0) {
                    DBG1("ERR:  Failed to allocate transparent hugepages!");
                    return nullptr;
                }
                userMap(mem, size);

                break;

            case CoyoteAlloc::HPF : // drv lock
                size = cs_alloc.n_pages * (1 << hugePageShift);
                mem = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
                userMap(mem, size);
				
			    break;

			default:
				break;
		}

        mapped_pages.emplace(mem, std::make_pair(cs_alloc, memNonAligned));
		DBG3("Mapped mem at: " << std::hex << reinterpret_cast<uint64_t>(mem) << std::dec);
	}

	return mem;
}

/**
 * @brief Memory deallocation
 * 
 * @param vaddr - pointer to the allocated memory
 */
void cThread::freeMem(void* vaddr) {
	uint64_t tmp[2];
	uint32_t size;

	tmp[0] = reinterpret_cast<uint64_t>(vaddr);
	tmp[1] = static_cast<int32_t>(ctid);

	if(mapped_pages.find(vaddr) != mapped_pages.end()) {
		auto mapped = mapped_pages[vaddr];
		
		switch (mapped.first.alloc) {
		case CoyoteAlloc::REG : // drv lock
			userUnmap(vaddr);
			free(vaddr);

			break;

        case CoyoteAlloc::THP : // drv lock
			size = mapped.first.n_pages * (1 << hugePageShift);
			userUnmap(vaddr);
			free(vaddr);

			break;

		case CoyoteAlloc::HPF : // drv lock
			size = mapped.first.n_pages * (1 << hugePageShift);
			userUnmap(vaddr);
			munmap(vaddr, size);

			break;

		default:
			break;
		}

	    // mapped_pages.erase(vaddr);
	}
}

// ======-------------------------------------------------------------------------------
// Bulk transfers
// ======-------------------------------------------------------------------------------

void cThread::postCmd(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0) {
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
            nanosleep((const struct timespec[]){{0, sleepTime}}, NULL);
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
 * @param cs_invoke - Coyote invoke struct
 */
void cThread::invoke(const csInvoke& cs_invoke) {
	if(isLocalSync(cs_invoke.oper)) if(!fcnfg.en_mem) return;
    if(isRemoteRdma(cs_invoke.oper)) return;
    if(isRemoteTcp(cs_invoke.oper)) if(!fcnfg.en_tcp) return;
	if(cs_invoke.oper == CoyoteOper::NOOP) return;

    if(isLocalSync(cs_invoke.oper)) { 
        //
        // Sync mem ops
        //

        uint64_t tmp[2];
        tmp[1] = ctid;

        if(cs_invoke.oper == CoyoteOper::LOCAL_OFFLOAD) {
            // Offload
            for(int i = 0; i < cs_invoke.num_sge; i++) {
                tmp[0] = reinterpret_cast<uint64_t>(cs_invoke.sg_list[i].sync.addr);
                if(ioctl(fd, IOCTL_OFFLOAD_REQ, &tmp))
		            throw std::runtime_error("ioctl_offload_req() failed");
            }  
        }
        else if (cs_invoke.oper == CoyoteOper::LOCAL_SYNC) {
            // Sync
            for(int i = 0; i < cs_invoke.num_sge; i++) {
                tmp[0] = reinterpret_cast<uint64_t>(cs_invoke.sg_list[i].sync.addr);
                if(ioctl(fd, IOCTL_SYNC_REQ, &tmp))
                    throw std::runtime_error("ioctl_sync_req() failed");
            }
        }
    } else { 
        //
        // Local and remote ops
        //

        uint64_t addr_cmd_src[cs_invoke.num_sge], addr_cmd_dst[cs_invoke.num_sge];
        uint64_t ctrl_cmd_src[cs_invoke.num_sge], ctrl_cmd_dst[cs_invoke.num_sge];

        for(int i = 0; i < cs_invoke.num_sge; i++) {

            //
            // Construct the post cmd
            //
            if(isRemoteTcp(cs_invoke.oper)) {
                // TCP
                ctrl_cmd_src[i] = 
                    ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
                    ((cs_invoke.sg_list[i].tcp.dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
                    ((i == (cs_invoke.num_sge-1) ? ((cs_invoke.sg_flags.last) ? CTRL_LAST : 0x0) : 0x0)) |
                    (CTRL_START) |
                    (static_cast<uint64_t>(cs_invoke.sg_list[i].tcp.len) << CTRL_LEN_OFFS);
                
                addr_cmd_src[i] = 0;
                ctrl_cmd_dst[i] = 0;
                addr_cmd_dst[i] = 0;
            } else {
                if(cs_invoke.sg_flags.clr && fcnfg.en_wb) {
                    for(int i = 0; i < nWbacks; i++) {
                        wback[ctid + i*nCtidMax] = 0;
                    }
                }

                // Local
                ctrl_cmd_src[i] =
                    // RD
                    ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
                    ((cs_invoke.sg_list[i].local.src_dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
                    ((i == (cs_invoke.num_sge-1) ? ((cs_invoke.sg_flags.last) ? CTRL_LAST : 0x0) : 0x0)) |
                    (cs_invoke.sg_list[i].local.src_stream ? CTRL_STREAM : 0x0) | 
                    (isLocalRead(cs_invoke.oper) ? CTRL_START : 0x0) | 
                    (cs_invoke.sg_flags.clr ? CTRL_CLR_STAT : 0x0) | 
                    (static_cast<uint64_t>(cs_invoke.sg_list[i].local.src_len) << CTRL_LEN_OFFS);

                addr_cmd_src[i] = reinterpret_cast<uint64_t>(cs_invoke.sg_list[i].local.src_addr);

                ctrl_cmd_dst[i] =
                    // WR
                    ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
                    ((cs_invoke.sg_list[i].local.dst_dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
                    ((i == (cs_invoke.num_sge-1) ? ((cs_invoke.sg_flags.last) ? CTRL_LAST : 0x0) : 0x0)) |
                    (cs_invoke.sg_list[i].local.dst_stream ? CTRL_STREAM : 0x0) | 
                    (isLocalWrite(cs_invoke.oper) ? CTRL_START : 0x0) | 
                    (cs_invoke.sg_flags.clr ? CTRL_CLR_STAT : 0x0) | 
                    (static_cast<uint64_t>(cs_invoke.sg_list[i].local.dst_len) << CTRL_LEN_OFFS);

                addr_cmd_dst[i] = reinterpret_cast<uint64_t>(cs_invoke.sg_list[i].local.dst_addr);
            }

            postCmd(addr_cmd_dst[i], ctrl_cmd_dst[i], addr_cmd_src[i], ctrl_cmd_src[i]);         
        }

        // Polling
        if(cs_invoke.sg_flags.poll) {
            while(!checkCompleted(cs_invoke.oper)) nanosleep((const struct timespec[]){{0, sleepTime}}, NULL);
        }
  
    }
}

/**
 * @brief Inovoke data transfers (local)
 * 
 * @param cs_invoke - Coyote invoke struct
 */
void cThread::invoke(const csInvoke& cs_invoke, ibvQp *qpair) {
	if(isLocal(cs_invoke.oper)) return;
    if(isRemoteRdma(cs_invoke.oper)) if(!fcnfg.en_rdma) return;
    if(isRemoteTcp(cs_invoke.oper)) return;
	if(cs_invoke.oper == CoyoteOper::NOOP) return;

    //
    // Local and remote ops
    //

    uint64_t addr_cmd_src[cs_invoke.num_sge], addr_cmd_dst[cs_invoke.num_sge];
    uint64_t ctrl_cmd_src[cs_invoke.num_sge], ctrl_cmd_dst[cs_invoke.num_sge];

    for(int i = 0; i < cs_invoke.num_sge; i++) {

        //
        // Construct the post cmd
        //
        if(qpair->local.ip_addr == qpair->remote.ip_addr) {
            for(int i = 0; i < cs_invoke.num_sge; i++) {
                void *local_addr = (void*)((uint64_t)qpair->local.vaddr + cs_invoke.sg_list[i].rdma.local_offs);
                void *remote_addr = (void*)((uint64_t)qpair->remote.vaddr + cs_invoke.sg_list[i].rdma.remote_offs);

                memcpy(remote_addr, local_addr, cs_invoke.sg_list[i].rdma.len);
                continue;
            }
        } else {
            //
            ctrl_cmd_src[i] =                    
                // Local
                ((static_cast<uint64_t>(cs_invoke.oper) & CTRL_OPCODE_MASK) << CTRL_OPCODE_OFFS) |
                (CTRL_MODE) |
                (CTRL_RDMA) |
                (CTRL_REMOTE) |

                ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
                ((cs_invoke.sg_list[i].rdma.local_dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
                ((i == (cs_invoke.num_sge-1) ? ((cs_invoke.sg_flags.last) ? CTRL_LAST : 0x0) : 0x0)) |
                (cs_invoke.sg_list[i].rdma.local_stream ? CTRL_STREAM : 0x0) | 
                (CTRL_START) |
                (cs_invoke.sg_flags.clr ? CTRL_CLR_STAT : 0x0) | 
                ((static_cast<uint64_t>(qpair->local.qpn) & CTRL_SID_MASK) << CTRL_SID_OFFS) | 
                (static_cast<uint64_t>(cs_invoke.sg_list[i].rdma.len) << CTRL_LEN_OFFS);

            addr_cmd_src[i] = static_cast<uint64_t>((uint64_t)qpair->local.vaddr + cs_invoke.sg_list[i].rdma.local_offs);

            ctrl_cmd_dst[i] =
                // Remote
                ((static_cast<uint64_t>(cs_invoke.sg_list[i].rdma.remote_dest) & CTRL_DEST_MASK) << CTRL_DEST_OFFS) | 
                (static_cast<uint64_t>(cs_invoke.sg_list[i].rdma.remote_stream) ? CTRL_STREAM : 0x0) | 
                (cs_invoke.sg_flags.clr ? CTRL_CLR_STAT : 0x0);

            addr_cmd_dst[i] = static_cast<uint64_t>((uint64_t)qpair->remote.vaddr + cs_invoke.sg_list[i].rdma.remote_offs);
        }

        postCmd(addr_cmd_dst[i], ctrl_cmd_dst[i], addr_cmd_src[i], ctrl_cmd_src[i]);            
    }

    // Polling
    if(cs_invoke.sg_flags.poll) {
        while(!checkCompleted(cs_invoke.oper)) nanosleep((const struct timespec[]){{0, sleepTime}}, NULL);
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
uint32_t cThread::checkCompleted(CoyoteOper coper) {
	if(isLocalRead(coper)) {
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
    else if(isLocalWrite(coper)) {
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
void cThread::clearCompleted() {
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
bool cThread::doArpLookup(uint32_t ip_addr) {
#ifdef EN_AVX
	if(fcnfg.en_avx) {
        if(_mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::NET_ARP_REG)], 0))
            cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::NET_ARP_REG)] = _mm256_set_epi64x(0, 0, 0, ip_addr);
        else
            return false;
    } else {
#endif
        if((LOW_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::NET_ARP_REG)])))
            cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)] = CTRL_CLR_STAT | CTRL_REMOTE | ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS);
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
bool cThread::writeQpContext(ibvQp *qp) {
    uint64_t offs[3];

    offs[0] = (static_cast<uint64_t>(qp->local.qpn) & 0xffffff) << qpContextQpnOffs;

    offs[1] = ((static_cast<uint64_t>(qp->local.psn) & 0xffffff) << qpContextLpsnOffs) | 
              ((static_cast<uint64_t>(qp->remote.psn) & 0xffffff) << qpContextRpsnOffs);

    offs[2] = ((static_cast<uint64_t>((uint64_t)qp->remote.vaddr) & 0xffffffffffff) << qpContextVaddrOffs) | 
                ((static_cast<uint64_t>(qp->remote.rkey) & 0xffff) << qpContextRkeyOffs);

    if(fcnfg.en_rdma) {
#ifdef EN_AVX
        if(fcnfg.en_avx) {
            if(_mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_CTX_REG)], 0))
                cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_CTX_REG)] = _mm256_set_epi64x(0, offs[2], offs[1], offs[0]);
            else
                return false;
        } else {
#endif
            if((LOW_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CTX_REG_2)]))) {
                cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CTX_REG_0)] = offs[0];
                cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CTX_REG_1)] = offs[1];
                cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CTX_REG_2)] = offs[2];
            } else
                return false;
        }

        return true;
    }

    return false;
}

/**
 * @brief Write connection context
 * 
 * @param qp - queue pair struct
 * @param port 
 */
bool cThread::writeConnContext(ibvQp *qp, uint32_t port) {
    uint64_t offs[3];

    offs[0] = ((static_cast<uint64_t>(port) & 0xffff) << connContextPortOffs) | 
                ((static_cast<uint64_t>(qp->remote.qpn) & 0xffffff) << connContextRqpnOffs) | 
                ((static_cast<uint64_t>(qp->local.qpn) & 0xffff) << connContextLqpnOffs);

    offs[1] = (htols(static_cast<uint64_t>(qp->remote.gidToUint(8)) & 0xffffffff) << 32) |
                (htols(static_cast<uint64_t>(qp->remote.gidToUint(0)) & 0xffffffff) << 0);

    offs[2] = (htols(static_cast<uint64_t>(qp->remote.gidToUint(24)) & 0xffffffff) << 32) | 
                (htols(static_cast<uint64_t>(qp->remote.gidToUint(16)) & 0xffffffff) << 0);

    if(fcnfg.en_rdma) {
#ifdef EN_AVX
        if(fcnfg.en_avx) {
            if(_mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_CONN_REG)], 0))
                cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_CONN_REG)] = _mm256_set_epi64x(0, offs[2], offs[1], offs[0]);
            else
                return false;
        } else {
#endif
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

// ======-------------------------------------------------------------------------------
// DEBUG
// ======-------------------------------------------------------------------------------

/**
 * Debug
 * 
 */
void cThread::printDebug()
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
