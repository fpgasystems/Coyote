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

#include "cProcess.hpp"

using namespace std::chrono;

namespace fpga {

// ======-------------------------------------------------------------------------------
// cProcess management
// ======-------------------------------------------------------------------------------

/**
 * @brief Construct a new cProces
 * 
 * @param vfid - vFPGA id
 * @param pid - host process id
 */
cProcess::cProcess(int32_t vfid, pid_t pid, cSched *csched) : vfid(vfid), pid(pid), csched(csched),
		plock(open_or_create, "vpga_mtx_user_" + vfid), 
		dlock(open_or_create, "vfpga_mtx_data_" + vfid), 
		mlock(open_or_create, "vpga_mtx_mem_" + vfid) 
{
	DBG3("cProcess:  acquiring vfid " << vfid);
    
	// Open
	std::string region = "/dev/fpga" + std::to_string(vfid);
	fd = open(region.c_str(), O_RDWR | O_SYNC); 
	if(fd == -1)
		throw std::runtime_error("cProcess could not be obtained, vfid: " + to_string(vfid));

	// Registration
	uint64_t tmp[2];
	tmp[0] = pid;
	
	// register pid
	if(ioctl(fd, IOCTL_REGISTER_PID, &tmp))
		throw std::runtime_error("ioctl_register_pid() failed");

	DBG3("cProcess:  registered pid: " << pid << ", cpid: " << tmp[1]);
	cpid = tmp[1];

	// Cnfg
	if(ioctl(fd, IOCTL_READ_CNFG, &tmp)) 
		throw std::runtime_error("ioctl_read_cnfg() failed");

	fcnfg.parseCnfg(tmp[0]);
	DBG3("-- CONFIG -------------------------------------");
	DBG3("-----------------------------------------------");
	DBG3("Enabled AVX: " << fcnfg.en_avx);
	DBG3("Enabled BPSS: " << fcnfg.en_bypass);
	DBG3("Enabled TLBF: " << fcnfg.en_tlbf);
	DBG3("Enabled WBACK: " << fcnfg.en_wb);
	DBG3("Enabled STRM: " << fcnfg.en_strm);
	DBG3("Enabled MEM: " << fcnfg.en_mem);
	DBG3("Enabled PR: " << fcnfg.en_pr);
	DBG3("Enabled RDMA: " << fcnfg.en_rdma);
	DBG3("Enabled TCP: " << fcnfg.en_tcp);
	DBG3("QSFP port: " << fcnfg.qsfp);
	DBG3("Number of channels: " << fcnfg.n_fpga_chan);
	DBG3("Number of vFPGAs: " << fcnfg.n_fpga_reg);

	// Mmap
	mmapFpga();

	// Clear
	clearCompleted();
}

/**
 * @brief Destroy the cProcess
 * 
 */
cProcess::~cProcess() {
	DBG3("Releasing cProcess: " << vfid);
	
	uint64_t tmp = cpid;

	ioctl(fd, IOCTL_UNREGISTER_PID, &tmp);
	
	// Manage TLB
	for(auto& it: mapped_upages) {
		userUnmap(it);
	}
	mapped_upages.clear();

	for(auto& it: mapped_pages) {
		freeMem(it.first);
	}
	mapped_pages.clear();

	munmapFpga();

	named_mutex::remove("vfpga_mtx_user_" + vfid);
	named_mutex::remove("vfpga_mtx_data_" + vfid);
	named_mutex::remove("vfpga_mtx_mem_" + vfid);

	close(fd);
}

/**
 * @brief MMap vFPGA control plane
 * 
 */
void cProcess::mmapFpga() {
	// Config 
#ifdef EN_AVX
	if(fcnfg.en_avx) {
		cnfg_reg_avx = (__m256i*) mmap(NULL, cnfgAvxRegionSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapCnfgAvx);
		if(cnfg_reg_avx == MAP_FAILED)
		 	throw std::runtime_error("cnfg_reg_avx mmap failed");

		DBG3("cProcess::  mapped cnfg_reg_avx at: " << std::hex << reinterpret_cast<uint64_t>(cnfg_reg_avx) << std::dec);
	} else {
#endif
		cnfg_reg = (uint64_t*) mmap(NULL, cnfgRegionSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapCnfg);
		if(cnfg_reg == MAP_FAILED)
			throw std::runtime_error("cnfg_reg mmap failed");
		
		DBG3("cProcess:  mapped cnfg_reg at: " << std::hex << reinterpret_cast<uint64_t>(cnfg_reg) << std::dec);
#ifdef EN_AVX
	}
#endif

	// Control
	ctrl_reg = (uint64_t*) mmap(NULL, ctrlRegionSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapCtrl);
	if(ctrl_reg == MAP_FAILED) 
		throw std::runtime_error("ctrl_reg mmap failed");
	
	DBG3("cProcess:  mapped ctrl_reg at: " << std::hex << reinterpret_cast<uint64_t>(ctrl_reg) << std::dec);

	// Writeback
	if(fcnfg.en_wb) {
		wback = (uint32_t*) mmap(NULL, wbackRegionSize, PROT_READ, MAP_SHARED, fd, mmapWb);
		if(wback == MAP_FAILED) 
			throw std::runtime_error("wback mmap failed");

		DBG3("cProcess:  mapped writeback regions at: " << std::hex << reinterpret_cast<uint64_t>(wback) << std::dec);
	}
}

/**
 * @brief Munmap vFPGA control plane
 * 
 */
void cProcess::munmapFpga() {
	
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
// Memory management
// ======-------------------------------------------------------------------------------

/**
 * @brief Explicit TLB mapping
 * 
 * @param vaddr - user space address
 * @param len - length 
 */
void cProcess::userMap(void *vaddr, uint32_t len) {
	uint64_t tmp[3];
	tmp[0] = reinterpret_cast<uint64_t>(vaddr);
	tmp[1] = static_cast<uint64_t>(len);
	tmp[2] = static_cast<uint64_t>(cpid);

	if(ioctl(fd, IOCTL_MAP_USER, &tmp))
		throw std::runtime_error("ioctl_map_user() failed");

	mapped_upages.emplace(vaddr);
	DBG3("Explicit map user mem at: " << std::hex << reinterpret_cast<uint64_t>(vaddr) << std::dec);
}

/**
 * @brief TLB unmap
 * 
 * @param vaddr - user space address
 */
void cProcess::userUnmap(void *vaddr) {
	uint64_t tmp[2];
	tmp[0] = reinterpret_cast<uint64_t>(vaddr);
	tmp[1] = static_cast<uint64_t>(cpid);

	if(mapped_upages.find(vaddr) != mapped_upages.end()) {
		if(ioctl(fd, IOCTL_UNMAP_USER, &tmp)) 
			throw std::runtime_error("ioctl_unmap_user() failed");

	//	mapped_upages.erase(vaddr);
	}	
}

/**
 * @brief Memory allocation
 * 
 * @param cs_alloc - Coyote allocation struct
 * @return void* - pointer to the allocated memory
 */
void* cProcess::getMem(const csAlloc& cs_alloc) {
	void *mem = nullptr;
	void *memNonAligned = nullptr;
	uint64_t tmp[2];
	uint32_t size;

	if(cs_alloc.n_pages > 0) {
		tmp[0] = static_cast<uint64_t>(cs_alloc.n_pages);
		tmp[1] = static_cast<uint64_t>(cpid);

		switch (cs_alloc.alloc) {
			case CoyoteAlloc::REG_4K : // drv lock
				size = cs_alloc.n_pages * (1 << pageShift);
				mem = memalign(axiDataWidth, size);
				userMap(mem, size);
				
				break;

			case CoyoteAlloc::HUGE_2M : // drv lock
				size = cs_alloc.n_pages * (1 << hugePageShift);
				mem = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
				userMap(mem, size);
				
				break;

			case CoyoteAlloc::HOST_2M : // m lock

				mLock();

				if(ioctl(fd, IOCTL_ALLOC_HOST_USER_MEM, &tmp)) {
					mUnlock();
					throw std::runtime_error("ioctl_alloc_host_user_mem() failed");
				}
					
				memNonAligned = mmap(NULL, (cs_alloc.n_pages + 1) * hugePageSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapBuff);
				if(memNonAligned == MAP_FAILED) {
					mUnlock();
					throw std::runtime_error("get_host_mem mmap failed");
				}

				mUnlock();
					
				mem =  (void*)( (((reinterpret_cast<uint64_t>(memNonAligned) + hugePageSize - 1) >> hugePageShift)) << hugePageShift);

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
void cProcess::freeMem(void* vaddr) {
	uint64_t tmp[2];
	uint32_t size;

	tmp[0] = reinterpret_cast<uint64_t>(vaddr);
	tmp[1] = static_cast<int32_t>(cpid);

	if(mapped_pages.find(vaddr) != mapped_pages.end()) {
		auto mapped = mapped_pages[vaddr];
		
		switch (mapped.first.alloc) {
		case CoyoteAlloc::REG_4K : // drv lock
			size = mapped.first.n_pages * (1 << pageShift);
			userUnmap(vaddr);
			free(vaddr);

			break;

		case CoyoteAlloc::HUGE_2M : // drv lock
			size = mapped.first.n_pages * (1 << hugePageShift);
			userUnmap(vaddr);
			munmap(vaddr, size);

			break;

		case CoyoteAlloc::HOST_2M : // m lock
			mLock();

			if(munmap(mapped.second, (mapped.first.n_pages + 1) * hugePageSize) != 0) {
				mUnlock();
				throw std::runtime_error("free_host_mem munmap failed");
			}

			if(ioctl(fd, IOCTL_FREE_HOST_USER_MEM, &tmp)) {
				mUnlock();
				throw std::runtime_error("ioctl_free_host_user_mem() failed");
			}
				
			mUnlock();

			break;

		default:
			break;
		}

	//	mapped_pages.erase(vaddr);
	}
}

// ======-------------------------------------------------------------------------------
// Scheduling
// ======-------------------------------------------------------------------------------

/**
 * @brief Obtain vFPGA lock (if scheduler is not present obtain system lock)
 * 
 * @param oid - operator id
 * @param priority - priority
 */
void cProcess::pLock(int32_t oid, uint32_t priority) 
{
    if(csched != nullptr) {
        csched->pLock(cpid, oid, priority); 
    } else {
        plock.lock();
    }
}

void cProcess::pUnlock() 
{
    if(csched != nullptr) {
        csched->pUnlock(cpid); 
    } else {
        plock.unlock();
    }
}

// ======-------------------------------------------------------------------------------
// Bulk transfers
// ======-------------------------------------------------------------------------------

/**
 * @brief Inovoke data transfers
 * 
 * @param cs_invoke - Coyote invoke struct
 */
void cProcess::invoke(const csInvokeAll& cs_invoke) {
	if(isSync(cs_invoke.oper)) if(!fcnfg.en_mem) return;
	if(cs_invoke.oper == CoyoteOper::NOOP) return;

	// Lock
	dlock.lock();
	
	// Check outstanding read
	if(isRead(cs_invoke.oper)) {
		while (rd_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr)) {
#ifdef EN_AVX
			rd_cmd_cnt = fcnfg.en_avx ? LOW_16(_mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_REG)], 0x0)) :
										cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_CMD_USED_RD_REG)];
#else
			rd_cmd_cnt = cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_CMD_USED_RD_REG)];
#endif
			if (rd_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr))
				nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}
	}

	// Check outstanding write
	if(isWrite(cs_invoke.oper)) {
		while (wr_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr)) {
#ifdef EN_AVX
			wr_cmd_cnt = fcnfg.en_avx ? HIGH_16(_mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_REG)], 0x0)) : 
										cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_CMD_USED_WR_REG)];
#else
			wr_cmd_cnt = cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_CMD_USED_WR_REG)];
#endif
			if (wr_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr))
				nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}
	}

	// Send
#ifdef EN_AVX
	if(fcnfg.en_avx) {
		uint64_t len_cmd = (static_cast<uint64_t>(cs_invoke.dst_len) << 32) | cs_invoke.src_len;
		uint64_t ctrl_cmd = 
			(isRead(cs_invoke.oper) ? CTRL_START_RD : 0x0) | 
			(cs_invoke.clr_stat ? CTRL_CLR_STAT_RD : 0x0) | 
			(cs_invoke.stream ? CTRL_STREAM_RD : 0x0) | 
			((cs_invoke.dest & CTRL_DEST_MASK) << CTRL_DEST_RD) |
			((cpid & CTRL_PID_MASK) << CTRL_PID_RD) |
			(cs_invoke.oper == CoyoteOper::OFFLOAD ? CTRL_SYNC_RD : 0x0) |
			(isWrite(cs_invoke.oper) ? CTRL_START_WR : 0x0) | 	
			(cs_invoke.clr_stat ? CTRL_CLR_STAT_WR : 0x0) | 
			(cs_invoke.stream ? CTRL_STREAM_WR : 0x0) | 
			((cpid & CTRL_PID_MASK) << CTRL_PID_WR) |
			(cs_invoke.oper == CoyoteOper::SYNC ? CTRL_SYNC_WR : 0x0);
			
			
		cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::CTRL_REG)] = 
			_mm256_set_epi64x(len_cmd, reinterpret_cast<uint64_t>(cs_invoke.dst_addr), reinterpret_cast<uint64_t>(cs_invoke.src_addr), ctrl_cmd);
	} else {
#endif
		cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::VADDR_RD_REG)] = reinterpret_cast<uint64_t>(cs_invoke.src_addr);
		cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::LEN_RD_REG)] = cs_invoke.src_len;
		cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)] = 
			(isRead(cs_invoke.oper) ? CTRL_START_RD : 0x0) | 
			(cs_invoke.clr_stat ? CTRL_CLR_STAT_RD : 0x0) |
			(cs_invoke.stream ? CTRL_STREAM_RD : 0x0) | 
			((cs_invoke.dest & CTRL_DEST_MASK) << CTRL_DEST_RD) |
			((cpid & CTRL_PID_MASK) << CTRL_PID_RD) |
			(cs_invoke.oper == CoyoteOper::OFFLOAD ? CTRL_SYNC_RD : 0x0);


		cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::VADDR_WR_REG)] = reinterpret_cast<uint64_t>(cs_invoke.dst_addr);
		cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::LEN_WR_REG)] = cs_invoke.dst_len;
		cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)] = 
			(isWrite(cs_invoke.oper) ? CTRL_START_WR : 0x0) |
			(cs_invoke.clr_stat ? CTRL_CLR_STAT_WR : 0x0) |
			(cs_invoke.stream ? CTRL_STREAM_WR : 0x0) | 
			((cpid & CTRL_PID_MASK) << CTRL_PID_WR) |
			(cs_invoke.oper == CoyoteOper::SYNC ? CTRL_SYNC_WR : 0x0);
#ifdef EN_AVX
	}
#endif

	// Inc
	rd_cmd_cnt++;
	wr_cmd_cnt++;

	// Unlock
	dlock.unlock();	

	// Polling
	if(cs_invoke.poll) {
		while(!checkCompleted(cs_invoke.oper)) nanosleep((const struct timespec[]){{0, 100L}}, NULL);
	}
}

/**
 * @brief Invoke overload 
 * 
 * @param cs_invoke - Coyote invoke struct
 */
void cProcess::invoke(const csInvoke& cs_invoke) {
	csInvokeAll cs_invoke_all;
	cs_invoke_all.oper = cs_invoke.oper;	
	if(isRead(cs_invoke.oper)) {
		cs_invoke_all.src_addr = cs_invoke.addr;
		cs_invoke_all.src_len = cs_invoke.len;
	}
	if(isWrite(cs_invoke.oper)) {
		cs_invoke_all.dst_addr = cs_invoke.addr;
		cs_invoke_all.dst_len = cs_invoke.len;
	}
	cs_invoke_all.clr_stat = cs_invoke.clr_stat;
	cs_invoke_all.poll = cs_invoke.poll;
	cs_invoke_all.stream = cs_invoke.stream;
	cs_invoke_all.dest = cs_invoke.dest;

	invoke(cs_invoke_all);
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
uint32_t cProcess::checkCompleted(CoyoteOper coper) {
	if(isWrite(coper)) {
		if(fcnfg.en_wb) {
			return wback[cpid + nCpidMax];
		} else {
#ifdef EN_AVX
			if(fcnfg.en_avx) 
				return _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + cpid], 1);
			else
#endif
				return (HIGH_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_DMA_REG) + cpid]));
		}
	} else {
		if(fcnfg.en_wb) {
			return wback[cpid];
		} else {
#ifdef EN_AVX
			if(fcnfg.en_avx) 
				return _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + cpid], 0);
			else 
#endif
				return (LOW_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_DMA_REG) + cpid]));
		}
	}
}

/**
 * @brief Clear completion counters
 * 
 */
void cProcess::clearCompleted() {
#ifdef EN_AVX
	if(fcnfg.en_avx)
		cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::CTRL_REG)] = _mm256_set_epi64x(0, 0, 0, CTRL_CLR_STAT_RD | CTRL_CLR_STAT_WR | 
			((cpid & CTRL_PID_MASK) << CTRL_PID_RD) | ((cpid & CTRL_PID_MASK) << CTRL_PID_WR));
	else
#endif
		cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)] = CTRL_CLR_STAT_RD | CTRL_CLR_STAT_WR | ((cpid & CTRL_PID_MASK) << CTRL_PID_RD) | ((cpid & CTRL_PID_MASK) << CTRL_PID_WR);
}

// ======-------------------------------------------------------------------------------
// Network
// ======-------------------------------------------------------------------------------

/**
 * @brief Check number of completed RDMA operations
 * 
 * @param cpid - Coyote operation struct
 * @return uint32_t - number of completed operations
 */
uint32_t cProcess::ibvCheckAcks() {
    if(fcnfg.en_wb) {
        return wback[cpid + ((fcnfg.qsfp ? 3 : 2) * nCpidMax)];
    } else {
#ifdef EN_AVX
        if(fcnfg.en_avx) 
            return fcnfg.qsfp ? _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + cpid], 3) :
                                _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + cpid], 2);
        else
#endif
            return (fcnfg.qsfp ? (HIGH_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_RDMA_REG) + cpid])) : 
                                 ( LOW_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_RDMA_REG) + cpid])));
    }
}

/**
 * @brief Check completion queue
 * 
 * @param cmplt_cpid - Coyote pid
 * @return int32_t - ssn 
 */
int32_t cProcess::ibvGetCompleted(int32_t &cpid) {
    uint64_t cmplt_meta;
#ifdef EN_AVX
    if(fcnfg.en_avx) 
        cmplt_meta = _mm256_extract_epi64(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_CMPLT_REG)], 0);
    else
#endif
        cmplt_meta = cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CMPLT_REG)];

    if(cmplt_meta & 0x1) {
        cpid = (cmplt_meta >> 16) & 0x3f;
        return HIGH_32(cmplt_meta);
    } else {
        return -1;
    }
}

/**
 * @brief Post an IB operation
 * 
 * @param qp - queue pair struct
 * @param wr - operation struct
 */
void cProcess::ibvPostSend(ibvQp *qp, ibvSendWr *wr) {
    if(fcnfg.en_rdma) {
        if(qp->local.ip_addr == qp->remote.ip_addr) {
            for(int i = 0; i < wr->num_sge; i++) {
                void *local_addr = (void*)((uint64_t)qp->local.vaddr + wr->sg_list[i].local_offs);
                void *remote_addr = (void*)((uint64_t)qp->remote.vaddr + wr->sg_list[i].remote_offs);

                memcpy(remote_addr, local_addr, wr->sg_list[i].len);
            }
        } else {
            uint64_t offs_0 = (
				(0x1 << RDMA_POST_OFFS) |
				((static_cast<uint64_t>(wr->opcode) & RDMA_OPCODE_MASK) << RDMA_OPCODE_OFFS) |
				((static_cast<uint64_t>(qp->local.qpn) & RDMA_PID_MASK) << RDMA_PID_OFFS) | 
				(((static_cast<uint64_t>(qp->local.qpn) >> 6) & RDMA_VFID_MASK) << RDMA_VFID_OFFS) | 
				((static_cast<uint64_t>(wr->send_flags.host) & 0x1) << RDMA_HOST_OFFS) | 
				((static_cast<uint64_t>(wr->send_flags.mode) & 0x1) << RDMA_MODE_OFFS) | 
				((static_cast<uint64_t>(wr->send_flags.last) & 0x1) << RDMA_LAST_OFFS) |
				((static_cast<uint64_t>(wr->send_flags.clr) & 0x1) << RDMA_CLR_OFFS)); 
				
            uint64_t offs_1, offs_2, offs_3;

            for(int i = 0; i < wr->num_sge; i++) {
                offs_1 = static_cast<uint64_t>((uint64_t)qp->local.vaddr + wr->sg_list[i].local_offs); 
                offs_2 = wr->isRDMA() ? (static_cast<uint64_t>((uint64_t)qp->remote.vaddr + wr->sg_list[i].remote_offs)) : 0; 
                offs_3 = static_cast<uint64_t>(wr->sg_list[i].len);

                postCmd(offs_3, offs_2, offs_1, offs_0);
            }
        }

		last_qp = qp->getId();
    }
}

/**
 * @brief Util post
 * 
 * @param offs_3 - AVX offsets
 * @param offs_2 
 * @param offs_1 
 * @param offs_0 
 * @param offs_reg - Immed reg offset
 */
void cProcess::postPrep(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0, uint8_t offs_reg) {
	 // Lock
    dlock.lock();

#ifdef EN_AVX
    if(fcnfg.en_avx) {
        cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_POST_REG_0) + fcnfg.qsfp_offs + offs_reg] = 
			_mm256_set_epi64x(offs_3, offs_2, offs_1, offs_0);
    } else {
#endif
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_POST_REG_0) + fcnfg.qsfp_offs + offs_reg*4] = offs_0;
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_POST_REG_1) + fcnfg.qsfp_offs + offs_reg*4] = offs_1;
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_POST_REG_2) + fcnfg.qsfp_offs + offs_reg*4] = offs_2;
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_POST_REG_3) + fcnfg.qsfp_offs + offs_reg*4] = offs_3;
#ifdef EN_AVX
    }
#endif

	// Unlock
    dlock.unlock();	
}

/**
 * @brief Check IB acks
 * 
 * @return uint32_t - number of acks received
 */
uint32_t cProcess::checkIbvAcks() {
	if(fcnfg.en_wb) {
		return wback[cpid + (fcnfg.qsfp*nCpidMax) + 2*nCpidMax];
	} else {
#ifdef EN_AVX
		if(fcnfg.en_avx) 
			return  fcnfg.qsfp ? _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + cpid], 3) :
								 _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + cpid], 2);
		else
#endif
			return fcnfg.qsfp ? (HIGH_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_DMA_REG) + cpid + nCpidMax])) : (LOW_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_DMA_REG) + cpid + nCpidMax])); 
	}
}

/**
 * @brief Clear IB acks
 * 
 */
void cProcess::clearIbvAcks() {
#ifdef EN_AVX
	if(fcnfg.en_avx)
		cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_POST_REG)] = _mm256_set_epi64x(0, 0, 0, ((cpid & RDMA_PID_MASK) << RDMA_PID_OFFS) | (0x1 << RDMA_CLR_OFFS));
	else
#endif
		cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_POST_REG)] = ((cpid & RDMA_PID_MASK) << RDMA_PID_OFFS) | (0x1 << RDMA_CLR_OFFS);
}

/**
 * @brief Post IB command
 * 
 * @param offs_3 - AVX offsets
 * @param offs_2 
 * @param offs_1 
 * @param offs_0 
 */
void cProcess::postCmd(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0) {
    // Lock
    dlock.lock();
    
    // Check outstanding
    while (rdma_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr)) {
#ifdef EN_AVX
        rdma_cmd_cnt = fcnfg.en_avx ? _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_STAT_REG) + fcnfg.qsfp_offs], 0x0) : 
                                      cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_STAT_CMD_USED_REG) + fcnfg.qsfp_offs];
#else
        rdma_cmd_cnt = cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_STAT_CMD_USED_REG) + fcnfg.qsfp_offs];
#endif
        if (rdma_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr))
            nanosleep((const struct timespec[]){{0, 100L}}, NULL);
    }

    // Send
#ifdef EN_AVX
    if(fcnfg.en_avx) {
        cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_POST_REG) + fcnfg.qsfp_offs] = _mm256_set_epi64x(offs_3, offs_2, offs_1, offs_0);

		// Inc
    	rdma_cmd_cnt++;
    } else {
#endif
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_POST_REG_0) + fcnfg.qsfp_offs] = offs_0;
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_POST_REG_1) + fcnfg.qsfp_offs] = offs_1;
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_POST_REG_2) + fcnfg.qsfp_offs] = offs_2;
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_POST_REG_3) + fcnfg.qsfp_offs] = offs_3;
		cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_POST_REG) + fcnfg.qsfp_offs] = 0x1;
			
		// Inc
    	rdma_cmd_cnt++;
		
#ifdef EN_AVX
    }
#endif

    // Unlock
    dlock.unlock();	
}

// ======-------------------------------------------------------------------------------
// Network management
// ======-------------------------------------------------------------------------------

/**
 * @brief ARP lookup request
 * 
 * @param ip_addr - target IP address
 */
void cProcess::doArpLookup(uint32_t ip_addr) {
	uint64_t tmp[2];
	tmp[0] = fcnfg.qsfp;
	tmp[1] = ip_addr;

	if(ioctl(fd, IOCTL_ARP_LOOKUP, &tmp))
		throw std::runtime_error("ioctl_arp_lookup() failed");

	usleep(arpSleepTime);
}

/**
 * @brief Write queue pair context
 * 
 * @param qp - queue pair struct
 */
void cProcess::writeQpContext(ibvQp *qp) {
    if(fcnfg.en_rdma) {
        uint64_t offs[4]; 
		offs[0] = fcnfg.qsfp;

		offs[1] = (static_cast<uint64_t>(qp->local.qpn) & 0x3ff) << qpContextQpnOffs;

		offs[2] = ((static_cast<uint64_t>(qp->local.psn) & 0xffffff) << qpContextLpsnOffs) | 
				  ((static_cast<uint64_t>(qp->remote.psn) & 0xffffff) << qpContextRpsnOffs);

		offs[3] = ((static_cast<uint64_t>((uint64_t)qp->remote.vaddr) & 0xffffffffffff) << qpContextVaddrOffs) | 
				  ((static_cast<uint64_t>(qp->remote.rkey) & 0xffff) << qpContextRkeyOffs);

        if(ioctl(fd, IOCTL_WRITE_CTX, &offs))
			throw std::runtime_error("ioctl_write_ctx() failed");
    }
}

/**
 * @brief Write connection context
 * 
 * @param qp - queue pair struct
 * @param port 
 */
void cProcess::writeConnContext(ibvQp *qp, uint32_t port) {
    if(fcnfg.en_rdma) {
        uint64_t offs[4];

		offs[0] = fcnfg.qsfp;

        offs[1] = ((static_cast<uint64_t>(port) & 0xffff) << connContextPortOffs) | 
				  ((static_cast<uint64_t>(qp->remote.qpn) & 0xffffff) << connContextRqpnOffs) | 
				  ((static_cast<uint64_t>(qp->local.qpn) & 0xffff) << connContextLqpnOffs);

        offs[2] = (htols(static_cast<uint64_t>(qp->remote.gidToUint(8)) & 0xffffffff) << 32) |
		 		  (htols(static_cast<uint64_t>(qp->remote.gidToUint(0)) & 0xffffffff) << 0);

        offs[3] = (htols(static_cast<uint64_t>(qp->remote.gidToUint(24)) & 0xffffffff) << 32) | 
		 		  (htols(static_cast<uint64_t>(qp->remote.gidToUint(16)) & 0xffffffff) << 0);

        if(ioctl(fd, IOCTL_WRITE_CONN, &offs))
			throw std::runtime_error("ioctl_write_conn() failed");
    }
}

/**
* @brief TCP Open Connection
*/

bool cProcess::tcpOpenCon(uint32_t ip, uint32_t port, uint32_t* session){
	// open connection
    uint64_t open_con_req;
    uint64_t open_con_sts = 0; 
    uint32_t success = 0;
    uint32_t sts_ip, dst_ip;
    uint32_t sts_port, dst_port;
    uint32_t sts_valid;

    dst_ip = ip;
    dst_port = port;
    open_con_req = (uint32_t)dst_ip | ((uint64_t)dst_port << 32);
    printf("open con req: %lx, dst ip:%x, dst port:%x\n", open_con_req, dst_ip, dst_port);
    fflush(stdout);

    success = 0;
    double timeoutMs = 5000.0;
    double durationMs = 0.0;
    auto start = std::chrono::high_resolution_clock::now();
	if(fcnfg.en_avx) {
        cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::TCP_OPEN_CON_REG) + fcnfg.qsfp_offs] = _mm256_set_epi64x(0, 0, 0, open_con_req);
	} else {
		cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::TCP_OPEN_CON_REG) + fcnfg.qsfp_offs] = open_con_req;
	}
    while (success == 0 && durationMs < timeoutMs)
    {
        std::this_thread::sleep_for(1000ms);

		if(fcnfg.en_avx) {
			open_con_sts = _mm256_extract_epi64(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::TCP_OPEN_CON_STS_REG) + fcnfg.qsfp_offs], 0x0);
		} else {
			open_con_sts = cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::TCP_OPEN_CON_STS_REG) + fcnfg.qsfp_offs];
		}
        *session = open_con_sts & 0x0000000000007FFF;
        sts_valid = (open_con_sts & 0x0000000000008000) >> 15;
        sts_ip = (open_con_sts & 0x0000FFFFFFFF0000) >> 16;
        sts_port = (open_con_sts >> 48); 
        if ((sts_valid == 1) && (sts_ip == ip) && (sts_port == port))
        {
            success = 1;
        }
        else 
            success = 0;
        auto end = std::chrono::high_resolution_clock::now();
        durationMs = (std::chrono::duration_cast<std::chrono::nanoseconds>(end-start).count() / 1000000.0);
    }
    printf("open con sts session:%x, success:%x, sts_ip:%x, sts_port:%x, duration[ms]:%f\n", *session, success, sts_ip, sts_port, durationMs);
    fflush(stdout);

    return success;

}

/**
* @brief TCP Open Port
*/

bool cProcess::tcpOpenPort(uint32_t port){
	uint64_t open_port_status;
    uint64_t open_port = port;
	if(fcnfg.en_avx) {
        cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::TCP_OPEN_PORT_REG) + fcnfg.qsfp_offs] = _mm256_set_epi64x(0, 0, 0, open_port);
	} else {
		cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::TCP_OPEN_PORT_REG) + fcnfg.qsfp_offs] = open_port;
	}
	
    std::this_thread::sleep_for(10ms);
	if(fcnfg.en_avx) {
		open_port_status = _mm256_extract_epi64(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::TCP_OPEN_PORT_STS_REG) + fcnfg.qsfp_offs], 0x0);
	} else {
		open_port_status = cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::TCP_OPEN_PORT_STS_REG) + fcnfg.qsfp_offs];
	}

    printf("open port: %lu, status: %lx\n", open_port, open_port_status);
    fflush(stdout);

	return (bool)open_port_status;
}

/**
* @brief TCP Close Connection
*/

void cProcess::tcpCloseCon(uint32_t session){
	// todo
}

/**
 * @brief Network dropper
 * 
 */
void cProcess::netDrop(bool clr, bool dir, uint32_t packet_id) {
	uint64_t offs[4];

	offs[0] = fcnfg.qsfp;
	offs[1] = clr;
	offs[2] = dir;
	offs[3] = packet_id;

	std::cout << "Sending a drop" << std::endl;
	if(ioctl(fd, IOCTL_NET_DROP, &offs))
			throw std::runtime_error("ioctl_net_drop() failed");
}

// ======-------------------------------------------------------------------------------
// DEBUG
// ======-------------------------------------------------------------------------------

/**
 * Debug
 * 
 */
void cProcess::printDebug()
{
	std::cout << "-- STATISTICS - ID: " << getVfid() << std::endl;
	std::cout << "-----------------------------------------------" << std::endl;
#ifdef EN_AVX
	if(fcnfg.en_avx) {
		std::cout << std::setw(35) << "Read command FIFO used: \t" <<  LOW_16(_mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_REG)], 0x0)) << std::endl;
		std::cout << std::setw(35) << "Write command FIFO used: \t" <<  HIGH_16(_mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_REG)], 0x0)) << std::endl; 
		std::cout << std::setw(35) << "Host reads sent: \t" <<  _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_REG)], 0x1) << std::endl; 
		std::cout << std::setw(35) << "Host writes sent: \t" <<  _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_REG)], 0x2) << std::endl; 
		std::cout << std::setw(35) << "Card reads sent: \t" <<  _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_REG)], 0x3) << std::endl; 
		std::cout << std::setw(35) << "Card writes sent: \t" <<  _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_REG)], 0x4) << std::endl; 
		std::cout << std::setw(35) << "Sync reads sent: \t" <<  _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_REG)], 0x5) << std::endl; 
		std::cout << std::setw(35) << "Sync writes sent: \t" <<  _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_REG)], 0x6) << std::endl; 
		std::cout << std::setw(35) << "Page faults: \t" <<  _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_REG)], 0x7) << std::endl; 
	} else {
#endif
		std::cout << std::setw(35) << "Read command FIFO used: \t" <<  cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_CMD_USED_RD_REG)] << std::endl;
		std::cout << std::setw(35) << "Write command FIFO used: \t" <<  cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_CMD_USED_WR_REG)] << std::endl; 
		std::cout << std::setw(35) << "Host read requests sent: \t" <<  cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_SENT_HOST_RD_REG)] << std::endl; 
		std::cout << std::setw(35) << "Host write requests sent: \t" <<  cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_SENT_HOST_WR_REG)]  << std::endl; 
		std::cout << std::setw(35) << "Card read requests sent: \t" <<  cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_SENT_CARD_RD_REG)] << std::endl; 
		std::cout << std::setw(35) << "Card write requests sent: \t" <<  cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_SENT_CARD_WR_REG)]  << std::endl; 
		std::cout << std::setw(35) << "Sync read requests sent: \t" <<  cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_SENT_SYNC_RD_REG)] << std::endl; 
		std::cout << std::setw(35) << "Sync write requests sent: \t" <<  cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_SENT_SYNC_WR_REG)]  << std::endl; 
		std::cout << std::setw(35) << "Page faults: \t" <<  cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_PFAULTS_REG)] << std::endl; 	
#ifdef EN_AVX
	}
#endif
	std::cout << std::endl;
} 

}
