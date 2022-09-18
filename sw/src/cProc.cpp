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

#include "cProc.hpp"

using namespace std::chrono;

namespace fpga {

// -------------------------------------------------------------------------------
// cProc management
// -------------------------------------------------------------------------------

/**
 * Ctor
 * Obtain cProc char devices
 */
cProc::cProc(int32_t vfid, pid_t pid) : vfid(vfid), pid(pid), plock(open_or_create, "vpga_mtx_user_" + vfid), dlock(open_or_create, "vfpga_mtx_" + vfid) {
	DBG2("Acquiring cProc: " << vfid);
	// Open
	std::string region = "/dev/fpga" + std::to_string(vfid);
	fd = open(region.c_str(), O_RDWR | O_SYNC); 
	if(fd == -1)
		throw std::runtime_error("cProc could not be obtained, vfid: " + to_string(vfid));

	// Registration
	uint64_t tmp[2];
	tmp[0] = pid;
	
	// register pid
	if(ioctl(fd, IOCTL_REGISTER_PID, &tmp))
		throw std::runtime_error("ioctl_register_pid failed");

	DBG2("Registered pid: " << pid << ", cpid: " << tmp[1]);
	cpid = tmp[1];

	// Cnfg
	if(ioctl(fd, IOCTL_READ_CNFG, &tmp)) 
		throw std::runtime_error("ioctl_read_cnfg failed");

	fcnfg.parseCnfg(tmp[0]);
	DBG2("-- CONFIG -------------------------------------");
	DBG2("-----------------------------------------------");
	DBG2("Enabled AVX: " << fcnfg.en_avx);
	DBG2("Enabled BPSS: " << fcnfg.en_bypass);
	DBG2("Enabled TLBF: " << fcnfg.en_tlbf);
	DBG2("Enabled WBACK: " << fcnfg.en_wb);
	DBG2("Enabled STRM: " << fcnfg.en_strm);
	DBG2("Enabled MEM: " << fcnfg.en_mem);
	DBG2("Enabled PR: " << fcnfg.en_pr);
	if(fcnfg.en_net) {
		DBG2("Enabled RDMA: " << fcnfg.en_rdma);
		DBG2("Enabled TCP: " << fcnfg.en_tcp);
		DBG2("QSFP port: " << fcnfg.qsfp);
	}
	DBG2("Number of channels: " << fcnfg.n_fpga_chan);
	DBG2("Number of vFPGAs: " << fcnfg.n_fpga_reg);

	// Mmap
	mmapFpga();

	// Clear
	clearCompleted();
}

/**
 * Dtor
 * Release the cProc handle
 */
cProc::~cProc() {
	DBG2("Removing cProc: " << vfid);
	
	uint64_t tmp = cpid;

	ioctl(fd, IOCTL_UNREGISTER_PID, &tmp);
	
	// Manage TLB
	for(auto& it: mapped_upages) {
		userUnmap(it);
	}

	for(auto& it: mapped_pages) {
		freeMem(it.first);
	}

	munmapFpga();

	named_mutex::remove("vfpga_mtx_" + vfid);

	close(fd);
}

/**
 * Memory map control
 */
void cProc::mmapFpga() {
	// Config 
#ifdef EN_AVX
	if(fcnfg.en_avx) {
		cnfg_reg_avx = (__m256i*) mmap(NULL, cnfgAvxRegionSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapCnfgAvx);
		if(cnfg_reg_avx == MAP_FAILED)
		 	throw std::runtime_error("cnfg_reg_avx mmap failed");

		DBG2("Mapped cnfg_reg_avx at: " << std::hex << reinterpret_cast<uint64_t>(cnfg_reg_avx) << std::dec);
	} else {
#endif
		cnfg_reg = (uint64_t*) mmap(NULL, cnfgRegionSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapCnfg);
		if(cnfg_reg == MAP_FAILED)
			throw std::runtime_error("cnfg_reg mmap failed");
		
		DBG2("Mapped cnfg_reg at: " << std::hex << reinterpret_cast<uint64_t>(cnfg_reg) << std::dec);
#ifdef EN_AVX
	}
#endif

	// Control
	ctrl_reg = (uint64_t*) mmap(NULL, ctrlRegionSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapCtrl);
	if(ctrl_reg == MAP_FAILED) 
		throw std::runtime_error("ctrl_reg mmap failed");
	
	DBG2("Mapped ctrl_reg at: " << std::hex << reinterpret_cast<uint64_t>(ctrl_reg) << std::dec);

	// Writeback
	if(fcnfg.en_wb) {
		wback = (uint32_t*) mmap(NULL, wbackRegionSize, PROT_READ, MAP_SHARED, fd, mmapWb);
		if(wback == MAP_FAILED) 
			throw std::runtime_error("wback mmap failed");

		DBG2("Mapped writeback regions at: " << std::hex << reinterpret_cast<uint64_t>(wback) << std::dec);
	}
}

/**
 * Unmap
 */
void cProc::munmapFpga() {
	
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

// -------------------------------------------------------------------------------
// Memory management
// -------------------------------------------------------------------------------

/**
 * Explicit TLB mapping
 */
void cProc::userMap(void *vaddr, uint32_t len) {
	uint64_t tmp[3];
	tmp[0] = reinterpret_cast<uint64_t>(vaddr);
	tmp[1] = static_cast<uint64_t>(len);
	tmp[2] = static_cast<uint64_t>(cpid);

	if(ioctl(fd, IOCTL_MAP_USER, &tmp))
		throw std::runtime_error("ioctl_map_user failed");

	mapped_upages.emplace(vaddr);
	DBG3("Explicit map user mem at: " << std::hex << reinterpret_cast<uint64_t>(vaddr) << std::dec);
}

/**
 * TLB unmap
 */
void cProc::userUnmap(void *vaddr) {
	uint64_t tmp[2];
	tmp[0] = reinterpret_cast<uint64_t>(vaddr);
	tmp[1] = static_cast<uint64_t>(cpid);

	if(mapped_upages.find(vaddr) != mapped_upages.end()) {
		if(ioctl(fd, IOCTL_UNMAP_USER, &tmp)) 
			throw std::runtime_error("ioctl_unmap_user failed");

		mapped_upages.erase(vaddr);
	}	
}

/**
 * Memory allocation
 */
void* cProc::getMem(const csAlloc& cs_alloc) {
	void *mem = nullptr;
	void *memNonAligned = nullptr;
	uint64_t tmp[2];
	uint32_t size;

	if(cs_alloc.n_pages > 0) {
		tmp[0] = static_cast<uint64_t>(cs_alloc.n_pages);
		tmp[1] = static_cast<uint64_t>(cpid);

		switch (cs_alloc.alloc) {
			case CoyoteAlloc::REG_4K :
				size = cs_alloc.n_pages * (1 << pageShift);
				mem = memalign(axiDataWidth, size);
				userMap(mem, size);
				
				break;

			case CoyoteAlloc::HUGE_2M :
				size = cs_alloc.n_pages * (1 << hugePageShift);
				mem = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
				userMap(mem, size);
				
				break;

			case CoyoteAlloc::HOST_2M :
				if(ioctl(fd, IOCTL_ALLOC_HOST_USER_MEM, &tmp))
					throw std::runtime_error("ioctl_alloc_host_user_mem failed");

				memNonAligned = mmap(NULL, (cs_alloc.n_pages + 1) * hugePageSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapBuff);
				if(memNonAligned == MAP_FAILED) 
					throw std::runtime_error("get_host_mem mmap failed");

				mem =  (void*)( (((reinterpret_cast<uint64_t>(memNonAligned) + hugePageSize - 1) >> hugePageShift)) << hugePageShift);
				

				break;

			case CoyoteAlloc::RCNFG_2M :
				if(ioctl(fd, IOCTL_ALLOC_HOST_PR_MEM, &tmp)) 
					throw std::runtime_error("ioctl_alloc_host_pr_mem mapping failed");
				
				memNonAligned = mmap(NULL, (cs_alloc.n_pages + 1) * hugePageSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapPr);
				if(memNonAligned == MAP_FAILED)
					throw std::runtime_error("get_pr_mem mmap failed");

				mem =  (void*)( (((reinterpret_cast<uint64_t>(memNonAligned) + hugePageSize - 1) >> hugePageShift)) << hugePageShift);

				break;

			default:
				break;
		}

		mapped_pages.emplace(mem, std::make_pair(cs_alloc, memNonAligned));
		DBG2("Mapped mem at: " << std::hex << reinterpret_cast<uint64_t>(mem) << std::dec);
	}

	return mem;
}

/**
 * Free memory
 */
void cProc::freeMem(void* vaddr) {
	uint64_t tmp[2];
	uint32_t size;

	tmp[0] = reinterpret_cast<uint64_t>(vaddr);
	tmp[1] = static_cast<int32_t>(cpid);

	if(mapped_pages.find(vaddr) != mapped_pages.end()) {
		auto mapped = mapped_pages[vaddr];
		
		switch (mapped.first.alloc) {
		case CoyoteAlloc::REG_4K :
			size = mapped.first.n_pages * (1 << pageShift);
			userUnmap(vaddr);
			free(vaddr);

			break;

		case CoyoteAlloc::HUGE_2M :
			size = mapped.first.n_pages * (1 << hugePageShift);
			userUnmap(vaddr);
			munmap(vaddr, size);

			break;

		case CoyoteAlloc::HOST_2M :
			if(munmap(mapped.second, (mapped.first.n_pages + 1) * hugePageSize) != 0) 
				throw std::runtime_error("free_host_mem munmap failed");

			if(ioctl(fd, IOCTL_FREE_HOST_USER_MEM, &tmp))
				throw std::runtime_error("ioctl_free_host_user_mem failed");

			break;

		case CoyoteAlloc::RCNFG_2M :
			if(munmap(mapped.second, (mapped.first.n_pages + 1) * hugePageSize) != 0) 
				throw std::runtime_error("free_pr_mem munmap failed");
			
			if(ioctl(fd, IOCTL_FREE_HOST_PR_MEM, &vaddr)) 
				throw std::runtime_error("ioctl_free_host_pr_mem failed");

			break;

		default:
			break;
		}

		mapped_pages.erase(vaddr);
	}
}

// -------------------------------------------------------------------------------
// Bulk transfers
// -------------------------------------------------------------------------------

/**
 * Main Coyote invoke operation
 */
void cProc::invoke(const csInvokeAll& cs_invoke) {
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
			(cs_invoke.oper == CoyoteOper::SYNC ? CTRL_SYNC_WR : 0x0) |
			(isWrite(cs_invoke.oper) ? CTRL_START_WR : 0x0) | 	
			(cs_invoke.clr_stat ? CTRL_CLR_STAT_WR : 0x0) | 
			(cs_invoke.stream ? CTRL_STREAM_WR : 0x0) | 
			((cpid & CTRL_PID_MASK) << CTRL_PID_WR) |
			(cs_invoke.oper == CoyoteOper::OFFLOAD ? CTRL_SYNC_RD : 0x0);
			
			
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
			(cs_invoke.oper == CoyoteOper::SYNC ? CTRL_SYNC_WR : 0x0);


		cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::VADDR_WR_REG)] = reinterpret_cast<uint64_t>(cs_invoke.dst_addr);
		cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::LEN_WR_REG)] = cs_invoke.dst_len;
		cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)] = 
			(isWrite(cs_invoke.oper) ? CTRL_START_WR : 0x0) |
			(cs_invoke.clr_stat ? CTRL_CLR_STAT_WR : 0x0) |
			(cs_invoke.stream ? CTRL_STREAM_WR : 0x0) | 
			((cpid & CTRL_PID_MASK) << CTRL_PID_WR) |
			(cs_invoke.oper == CoyoteOper::OFFLOAD ? CTRL_SYNC_RD : 0x0);
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
 * Invoke overload for single direction transactions (read, write)
 */
void cProc::invoke(const csInvoke& cs_invoke) {
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

// ------------------------------------------------------------------------------- 
// Polling
// -------------------------------------------------------------------------------

/**
 * Return read completed
 */
uint32_t cProc::checkCompleted(CoyoteOper coper) {
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
 * Clear completion counters
 */
void cProc::clearCompleted() {
#ifdef EN_AVX
	if(fcnfg.en_avx)
		cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::CTRL_REG)] = _mm256_set_epi64x(0, 0, 0, CTRL_CLR_STAT_RD | CTRL_CLR_STAT_WR | 
			((cpid & CTRL_PID_MASK) << CTRL_PID_RD) | ((cpid & CTRL_PID_MASK) << CTRL_PID_WR));
	else
#endif
		cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)] = CTRL_CLR_STAT_RD | CTRL_CLR_STAT_WR | ((cpid & CTRL_PID_MASK) << CTRL_PID_RD) | ((cpid & CTRL_PID_MASK) << CTRL_PID_WR);
}

// -------------------------------------------------------------------------------
// Reconfiguration
// -------------------------------------------------------------------------------

/**
 * Reconfiguration ioctl call (low level, should not be exposed as public)
 */
void cProc::reconfigure(void *vaddr, uint32_t len) {
	if(fcnfg.en_pr) {
		uint64_t tmp[2];
		tmp[0] = reinterpret_cast<uint64_t>(vaddr);
		tmp[1] = static_cast<uint64_t>(len);
		if(ioctl(fd, IOCTL_RECONFIG_LOAD, &tmp)) // Blocking
			throw std::runtime_error("ioctl_reconfig_load failed");

		DBG2("Reconfiguration completed");
	}
}

/**
 * Reconfiguration abstraction call (used by scheduler)
 */
void cProc::reconfigure(int32_t oid) {
	if(bstreams.find(oid) != bstreams.end()) {
		DBG2("Bitstream present, initiating reconfiguration");
		auto bstream = bstreams[oid];
		reconfigure(bstream.first, bstream.second);
	}
}

// Util
uint8_t cProc::readByte(ifstream& fb) {
	char temp;
	fb.read(&temp, 1);
	return (uint8_t)temp;
}

/**
 * Add a bitstream to the map
 */
void cProc::addBitstream(std::string name, int32_t oid) {
	if(bstreams.find(oid) == bstreams.end()) {
		// Stream
		ifstream f_bit(name, ios::ate | ios::binary);
		if(!f_bit) 
			throw std::runtime_error("Bitstream could not be opened");

		// Size
		uint32_t len = f_bit.tellg();
		f_bit.seekg(0);
		uint32_t n_pages = (len + hugePageSize - 1) / hugePageSize;
		
		// Get mem
		void* vaddr = getMem({CoyoteAlloc::RCNFG_2M, n_pages});
		uint32_t* vaddr_32 = reinterpret_cast<uint32_t*>(vaddr);

		// Read in
		for(uint32_t i = 0; i < len/4; i++) {
			vaddr_32[i] = 0;
			vaddr_32[i] |= readByte(f_bit) << 24;
			vaddr_32[i] |= readByte(f_bit) << 16;
			vaddr_32[i] |= readByte(f_bit) << 8;
			vaddr_32[i] |= readByte(f_bit);
		}

		DBG2("Bitstream loaded, oid: " << oid);
		f_bit.close();

		bstreams.insert({oid, std::make_pair(vaddr, len)});	
		return;
	}
		
	throw std::runtime_error("bitstream with same operation ID already present");
}

/**
 * Remove a bitstream from the map
 * @param: oid - Operator ID
 */
void cProc::removeBitstream(int32_t oid) {
	if(bstreams.find(oid) != bstreams.end()) {
		auto bstream = bstreams[oid];
		freeMem(bstream.first);
		bstreams.erase(oid);
	}
}

// -------------------------------------------------------------------------------
// IB verbs
// -------------------------------------------------------------------------------

/**
 * Post ibv
 */
void cProc::ibvPostSend(ibvQp *qp, ibvSendWr *wr) {
    if(fcnfg.en_rdma) {
        if(qp->local.ip_addr == qp->remote.ip_addr) {
            for(int i = 0; i < wr->num_sge; i++) {
                void *local_addr = (void*)(qp->local.vaddr + wr->sg_list[i].type.rdma.local_offs);
                void *remote_addr = (void*)(qp->remote.vaddr + wr->sg_list[i].type.rdma.remote_offs);

                memcpy(remote_addr, local_addr, wr->sg_list[i].type.rdma.len);
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
            
            if(wr->isRDMA()) { // RDMA
                for(int i = 0; i < wr->num_sge; i++) {
					offs_1 = static_cast<uint64_t>(qp->local.vaddr + wr->sg_list[i].type.rdma.local_offs); 
					offs_2 = static_cast<uint64_t>(qp->remote.vaddr + wr->sg_list[i].type.rdma.remote_offs); 
					offs_3 = static_cast<uint64_t>(wr->sg_list[i].type.rdma.len);

                    postCmd(offs_3, offs_2, offs_1, offs_0);
                }
            } else if(wr->isSEND()) { // SEND
                for(int i = 0; i < wr->num_sge; i++) {
					offs_1 = static_cast<uint64_t>(wr->sg_list[i].type.send.local_addr);
					offs_2 = static_cast<uint64_t>(wr->sg_list[i].type.send.len);
					offs_3 = 0;

                    postCmd(offs_3, offs_2, offs_1, offs_0);
                }
            } else { // IMMED
				for(int i = 0; i < wr->num_sge; i++) {
					uint64_t *params;
					if(wr->opcode == IBV_WR_IMMED_HIGH) params = wr->sg_list[i].type.immed_high.params;
					else if(wr->opcode == IBV_WR_IMMED_MID) params = wr->sg_list[i].type.immed_mid.params;
					else params = wr->sg_list[i].type.immed_low.params;

					// High
					if (wr->opcode == IBV_WR_IMMED_HIGH) {
						postPrep(0, 0, 0, params[7], ibvImmedHigh);
					}
					// Mid
					if (wr->opcode == IBV_WR_IMMED_HIGH || wr->opcode == IBV_WR_IMMED_MID) {
						postPrep(params[6], params[5], params[4], params[3], ibvImmedMid);
					}
					// Low
					postCmd(params[2], params[1], params[0], offs_0);
				}
			}
        }

		last_qp = qp->getId();
    }
}

void cProc::postPrep(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0, uint8_t offs_reg) {
	 // Prep
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
}

/**
 * Return number of IBV acks
 */
uint32_t cProc::checkIbvAcks() {
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
 * Clear number of IBV acks
 */

void cProc::clearIbvAcks() {
#ifdef EN_AVX
	if(fcnfg.en_avx)
		cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_POST_REG)] = _mm256_set_epi64x(0, 0, 0, ((cpid & RDMA_PID_MASK) << RDMA_PID_OFFS) | (0x1 << RDMA_CLR_OFFS));
	else
#endif
		cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_POST_REG)] = ((cpid & RDMA_PID_MASK) << RDMA_PID_OFFS) | (0x1 << RDMA_CLR_OFFS);
}

/**
 * Post command
 */
void cProc::postCmd(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0) {
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

// -------------------------------------------------------------------------------
// Network management
// -------------------------------------------------------------------------------

/**
 * Arp lookup
 */
void cProc::doArpLookup(uint32_t ip_addr) {
	uint64_t tmp[2];
	tmp[0] = fcnfg.qsfp;
	tmp[1] = ip_addr;

	if(ioctl(fd, IOCTL_ARP_LOOKUP, &tmp))
		throw std::runtime_error("ioctl_arp_lookup failed");

	usleep(arpSleepTime);
}

/**
 * Change the IP address
 */
void cProc::changeIpAddress(uint32_t ip_addr) {
    uint64_t tmp[2];
	tmp[0] = fcnfg.qsfp;
	tmp[1] = ip_addr;

    if(ioctl(fd, IOCTL_SET_IP_ADDRESS, &tmp))
		throw std::runtime_error("ioctl_set_ip_address failed");
}

/**
 * Change the board number
 */
void cProc::changeBoardNumber(uint32_t board_num) {
    uint64_t tmp[2];
	tmp[0] = fcnfg.qsfp;
	tmp[1] = board_num;
	
    if(ioctl(fd, IOCTL_SET_BOARD_NUM, &tmp))
		throw std::runtime_error("ioctl_set_board_num failed");
}

/**
 * Write qp context 
 * TODO: Switch to struct, clean this up
 */

void cProc::writeQpContext(ibvQp *qp) {
    if(fcnfg.en_rdma) {
        uint64_t offs[4]; 
		offs[0] = fcnfg.qsfp;

        offs[1] = ((static_cast<uint64_t>(qp->remote.psn) & 0xffffff) << qpContextRpsnOffs) | 
				  ((static_cast<uint64_t>(qp->local.qpn) & 0x3ff) << qpContextQpnOffs);

        offs[2] = ((static_cast<uint64_t>(qp->remote.rkey) & 0xffffff) << qpContextRkeyOffs) | 
				  ((static_cast<uint64_t>(qp->local.psn) & 0xffffff) << qpContextLpsnOffs); 

        offs[3] = static_cast<uint64_t>(qp->remote.vaddr);
		
		// Lock
    	dlock.lock();

        if(ioctl(fd, IOCTL_WRITE_CTX, &offs))
			throw std::runtime_error("ioctl_write_ctx failed");

		// Lock
    	dlock.unlock();
    }
}

/**
 * Write connection context
 * TODO: Switch to struct, clean this up
 */
void cProc::writeConnContext(ibvQp *qp, uint32_t port) {
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

		// Lock
    	dlock.lock();

        if(ioctl(fd, IOCTL_WRITE_CONN, &offs))
			throw std::runtime_error("ioctl_write_conn failed");

		// Lock
    	dlock.unlock();
    }
}

// ------------------------------------------------------------------------------- 
// Debug
// ------------------------------------------------------------------------------- 

/**
 * Debug
 */
void cProc::printDebug()
{
	std::cout << "-- STATISTICS - ID: " << getVfid() << " -------------------------" << std::endl;
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
	std::cout << "-----------------------------------------------" << std::endl;
} 

/**
 * Debug net
 */
void cProc::printNetDebug() {
	// Stats
	uint64_t tmp[nNetRegs];
	tmp[0] = fcnfg.qsfp;
	
	if(ioctl(fd, IOCTL_READ_NET_STATS, &tmp))
		throw std::runtime_error("ioctl_read_net_stats failed");

	std::cout << "-- NETSTATS -----------------------------------" << std::endl;
	std::cout << "-----------------------------------------------" << std::endl;
	std::cout << std::setw(35) << "RX word count: \t" << LOW_32(tmp[0]) << std::endl;
	std::cout << std::setw(35) << "RX package count: \t" << HIGH_32(tmp[0]) << std::endl;
	std::cout << std::setw(35) << "TX word count: \t" << LOW_32(tmp[1]) << std::endl;
	std::cout << std::setw(35) << "TX package count: \t" << HIGH_32(tmp[1]) << std::endl;
	std::cout << std::setw(35) << "ARP RX package count: \t" << LOW_32(tmp[2]) << std::endl;
	std::cout << std::setw(35) << "ARP TX package count: \t" << HIGH_32(tmp[2]) << std::endl;
	std::cout << std::setw(35) << "ICMP RX package count: \t" << LOW_32(tmp[3]) << std::endl;
	std::cout << std::setw(35) << "ICMP TX package count: \t" << HIGH_32(tmp[3]) << std::endl;
	std::cout << std::setw(35) << "TCP RX package count: \t" << LOW_32(tmp[4]) << std::endl;
	std::cout << std::setw(35) << "TCP TX package count: \t" << HIGH_32(tmp[4]) << std::endl;
	std::cout << std::setw(35) << "RDMA RX package count: \t" << LOW_32(tmp[5]) << std::endl;
	std::cout << std::setw(35) << "RDMA TX package count: \t" << HIGH_32(tmp[5]) << std::endl;
	std::cout << std::setw(35) << "RDMA CRC drop count: \t" << LOW_32(tmp[6]) << std::endl;
	std::cout << std::setw(35) << "RDMA PSN drop count: \t" << HIGH_32(tmp[6]) << std::endl;
	std::cout << std::setw(35) << "TCP session count: \t" << LOW_32(tmp[7]) << std::endl;
	std::cout << std::setw(35) << "Stream down count: \t" << LOW_32(tmp[8]) << std::endl;
	std::cout << std::setw(35) << "Stream status: \t" << HIGH_32(tmp[8]) << std::endl;
	std::cout << "-----------------------------------------------" << std::endl;
}

}
