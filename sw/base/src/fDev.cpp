#include <iostream>
#include <fcntl.h>
#include <unistd.h>
#include <fstream>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <time.h> 
#include <sys/time.h>  
#include <chrono>
#include <iomanip>

#include "fDev.hpp"

/* Sleep */
#define POLL_SLEEP_NS 						100

#define LARGE_PAGE_SIZE 					2 * 1024 * 1024
#define LARGE_PAGE_SHIFT 					21UL
#define PAGE_SIZE 							4 * 1024
#define PAGE_SHIFT 							12UL

/* Clock */
#define CLK_NS 								4

/* IOCTL */
#define IOCTL_ALLOC_HOST_USER_MEM       	_IOR('D', 1, unsigned long)
#define IOCTL_FREE_HOST_USER_MEM        	_IOR('D', 2, unsigned long)
#define IOCTL_ALLOC_HOST_PR_MEM         	_IOR('D', 3, unsigned long)
#define IOCTL_FREE_HOST_PR_MEM          	_IOR('D', 4, unsigned long)
#define IOCTL_MAP_USER                  	_IOR('D', 5, unsigned long)
#define IOCTL_UNMAP_USER                	_IOR('D', 6, unsigned long)
#define IOCTL_RECONFIG_LOAD             	_IOR('D', 7, unsigned long)
#define IOCTL_ARP_LOOKUP                	_IOR('D', 8, unsigned long)
#define IOCTL_WRITE_CTX                 	_IOR('D', 9, unsigned long)
#define IOCTL_WRITE_CONN                	_IOR('D', 10, unsigned long)
#define IOCTL_RDMA_STAT                 	_IOR('D', 11, unsigned long)
#define IOCTL_READ_ENG_STATUS           	_IOR('D', 12, unsigned long)

/* MMAP */
#define MMAP_CTRL                       	(0x0 << PAGE_SHIFT)
#define MMAP_CNFG                       	(0x1 << PAGE_SHIFT)
#define MMAP_CNFG_AVX						(0x2 << PAGE_SHIFT)
#define MMAP_BUFF                       	(0x200 << PAGE_SHIFT)
#define MMAP_PR								(0x400 << PAGE_SHIFT)

/* Regions */
#define CTRL_REGION_SIZE        			64 * 1024
#define CNFG_REGION_SIZE        			64 * 1024
#define CNFG_AVX_REGION_SIZE				256 * 1024

#define N_RDMA_STAT_REGS 					24

/* Config regs */
#ifdef EN_AVX
	// Base
	#define CNFG_CTRL_REG 					0
	#define CNFG_PF_REG 					1
	#define CNFG_DATAPATH_REG_SET 			2
	#define CNFG_DATAPATH_REG_CLR 			3
	#define CNFG_TMR_STOP_REG 				4
	#define CNFG_TMR_REG 					5
	#define CNFG_STAT_REG 					6
	// RDMA
	#define CNFG_RDMA_POST_REG 				10
	#define CNFG_RDMA_STAT_CMD_USED_REG 	11
	#define CNFG_RDMA_QPN_REG				12

	#define CTRL_START_RD 					0x1
	#define CTRL_START_WR 					0x2
	#define CTRL_SYNC_RD					0x4
	#define CTRL_SYNC_WR					0x8
	#define CTRL_STREAM_RD					0x10
	#define CTRL_STREAM_WR					0x20
	#define CTRL_CLR_STAT_RD				0x40
	#define CTRL_CLR_STAT_WR 				0x80
	#define CTRL_CLR_IRQ_PENDING			0x100
	#define CTRL_DEST_RD					9
	#define CTRL_DEST_WR					13
#else
	// Base
	#define CNFG_CTRL_REG					0
	#define CNFG_VADDR_RD_REG				1
	#define CNFG_LEN_RD_REG					2
	#define CNFG_VADDR_WR_REG				3
	#define CNFG_LEN_WR_REG					4
	#define VADDR_MISS_REG					5
	#define LEN_MISS_REG					6
	#define CNFG_DATAPATH_REG_SET 			7
	#define CNFG_DATAPATH_REG_CLR			8
	#define CNFG_TMR_STOP_REG				9
	#define CNFG_TMR_RD_REG					10
	#define CNFG_TMR_WR_REG					11
	#define CNFG_STAT_CMD_USED_RD_REG		12
	#define CNFG_STAT_CMD_USED_WR_REG		13
	#define CNFG_STAT_DMA_RD_REG			14
	#define CNFG_STAT_DMA_WR_REG			15
	#define CNFG_STAT_SENT_RD_REG 			16
	#define CNFG_STAT_SENT_WR_REG			17
	#define CNFG_STAT_PFAULTS_REG			18
	// RDMA
	#define CNFG_RDMA_POST_REG_0			20
	#define CNFG_RDMA_POST_REG_1			21
	#define CNFG_RDMA_POST_REG_2			22
	#define CNFG_RDMA_POST_REG_3			23
	#define CNFG_RDMA_STAT_CMD_USED_REG		24
	#define CNFG_RDMA_QPN_REG 				25

	#define CTRL_START_RD 					0x1
	#define CTRL_START_WR 					0x2
	#define CTRL_SYNC_RD					0x4
	#define CTRL_SYNC_WR					0x8
	#define CTRL_CLR_STAT_RD				0x10
	#define CTRL_CLR_STAT_WR 				0x20
	#define CTRL_CLR_IRQ_PENDING			0x40
	#define CTRL_SEND_RDMA_REQ				0x80
	#define CTRL_SEND_QP_CTX				0x100
	#define CTRL_SEND_QP_CONN				0x200
#endif

using namespace std::chrono;

namespace fpga {

// -------------------------------------------------------------------------------
// -- Obtain regions
// -------------------------------------------------------------------------------

/**
 * Obtain vFPGA char devices
 * @param: rNum - region ID
 */
bool fDev::acquireRegion(uint32_t rNum) {
	std::string region = "/dev/fpga" + std::to_string(rNum);
	fd = open(region.c_str(), O_RDWR | O_SYNC);
	if(fd == -1) {
		std::cout << "ERR: Cannot acquire an FPGA region" << std::endl;
		return false;
	}

	if(!mmapFpga()) {
		std::cout << "ERR: Cannot mmap an FPGA region" << std::endl;
		return false;
	}

	return true;
}

/**
 * Release the vFPGA handle
 */
void fDev::releaseRegion() {
	close(fd);
}

/**
 * Memory map control
 */
bool fDev::mmapFpga() {
#ifdef EN_AVX
	cnfg_reg = (__m256i*) mmap(NULL, CNFG_AVX_REGION_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_CNFG_AVX);
	if(cnfg_reg == MAP_FAILED) {
		releaseRegion();
		return false;
	}
#else
	cnfg_reg = (uint64_t*) mmap(NULL, CNFG_REGION_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_CNFG);
	if(cnfg_reg == MAP_FAILED) {
		releaseRegion();
		return false;
	}
#endif

	ctrl_reg = (uint64_t*) mmap(NULL, CTRL_REGION_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_CTRL);
	if(ctrl_reg == MAP_FAILED) {
		releaseRegion();
		return false;
	}

	return true;
}

/**
 * Unmap
 */
bool fDev::munmapFpga() {
#ifdef EN_AVX
	if(munmap(cnfg_reg, CNFG_AVX_REGION_SIZE) != 0) {
		releaseRegion();
		return false;
	}
#else
	if(munmap(cnfg_reg, CNFG_REGION_SIZE) != 0) {
		releaseRegion();
		return false;
	}
#endif

	if(munmap(ctrl_reg, CTRL_REGION_SIZE) != 0) {
		releaseRegion();
		return false;
	}

	cnfg_reg = 0;
	ctrl_reg = 0;

	return true;
}

// -------------------------------------------------------------------------------
// -- Memory management
// -------------------------------------------------------------------------------

/**
 * Obtain huge pages on the host memory
 * @param: n_pages - number of requested large pages
 */
uint64_t* fDev::_getHostMem(uint32_t n_pages) {
	uint64_t *hMem, *hMemAligned;
	uint64_t n_pg = n_pages;

	ioctl(fd, IOCTL_ALLOC_HOST_USER_MEM, &n_pg);
	hMem = (uint64_t*)mmap(NULL, (n_pg + 1) * LARGE_PAGE_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_BUFF);
	// alignment
	hMemAligned =  (uint64_t*)( ((((uint64_t)hMem + LARGE_PAGE_SIZE - 1) >> LARGE_PAGE_SHIFT)) << LARGE_PAGE_SHIFT);
	mapped_large[hMemAligned] = hMem;
	return hMemAligned;
}

/**
 * Release huge pages on the host memory
 * @param: vaddr - memory pointer
 * @param: n_pages - number of obtained pages
 */
void fDev::_freeHostMem(uint64_t *vaddr, uint32_t n_pages) {
	uint64_t* hMem;
	uint64_t n_pg = n_pages;

	hMem = mapped_large[vaddr];
	munmap(hMem, (n_pg + 1) * LARGE_PAGE_SIZE);
	ioctl(fd, IOCTL_FREE_HOST_USER_MEM, &vaddr);
}

/**
 * Obtain huge pages allocated for the PR bitstreams
 * @param: n_pages - number of requested large pages
 */
uint64_t* fDev::getPrMem(uint64_t n_pages) {
	uint64_t *hMem, *hMemAligned;
	uint64_t n_pg = n_pages;

	ioctl(fd, IOCTL_ALLOC_HOST_PR_MEM, &n_pg);
	hMem = (uint64_t*)mmap(NULL, (n_pg + 1) * LARGE_PAGE_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_PR);
	// alignment
	hMemAligned =  (uint64_t*)( ((((uint64_t)hMem + LARGE_PAGE_SIZE - 1) >> LARGE_PAGE_SHIFT)) << LARGE_PAGE_SHIFT);
	mapped_large[hMemAligned] = hMem;
	return hMemAligned;
}

/**
 * Release huge pages on the host memory
 * @param: vaddr - memory pointer
 * @param: n_pages - number of obtained pages
 */
void fDev::freePrMem(uint64_t *vaddr, uint64_t n_pages) {
	uint64_t* hMem;
	uint64_t n_pg = n_pages;

	hMem = mapped_large[vaddr];
	munmap(hMem, (n_pg + 1) * LARGE_PAGE_SIZE);
	ioctl(fd, IOCTL_FREE_HOST_PR_MEM, &vaddr);
}

/**
 * Explicit TLB mapping
 * @param: mem - memory pointer
 * @param: len - length of the mapping
 */
void fDev::_userMap(uint64_t *mem, uint32_t len) {
	uint64_t vdata [2];
	vdata[0] = (uint64_t)mem;
	vdata[1] = len;
	ioctl(fd, IOCTL_MAP_USER, &vdata);
}

/**
 * TLB unmap
 * @param: mem - memory pointer
 * @param: len - length of the mapping
 */
void fDev::_userUnmap(uint64_t *mem, uint32_t len) {
	uint64_t vdata [2];
	vdata[0] = (uint64_t)mem;
	vdata[1] = len;
	ioctl(fd, IOCTL_UNMAP_USER, &vdata);
}

// -------------------------------------------------------------------------------
// -- PR
// -------------------------------------------------------------------------------

/**
 * Reconfiguration ioctl call
 * @param: vaddr - memory pointer of the PR stream
 * @param: len - length of the stream
 */
void fDev::reconfigure(uint64_t *vaddr, uint64_t len) {
	uint64_t vdata [2];
	vdata[0] = (uint64_t)vaddr;
	vdata[1] = len;
	ioctl(fd, IOCTL_RECONFIG_LOAD, &vdata);
}

#ifdef EN_AVX
	// -------------------------------------------------------------------------------
	// -- Bulk transfers
	// -------------------------------------------------------------------------------

	/**
	 * Read operation (read to FPGA user logic)
	 * @param: vaddr - memory pointer
	 * @param: len - length 
	 * @param: stream - stream from host memory
	 * @param: poll - blocking/non-blocking
	 * @param: clr_stat - prior status clear
	 */
	void fDev::_read(uint64_t* vaddr, uint32_t len, uint8_t dest, bool stream, bool clr_stat, bool poll) {
		// Check outstanding
		while (rd_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr)) {
			rd_cmd_cnt = _mm256_extract_epi64(cnfg_reg[CNFG_STAT_REG], 0) & 0xffffffff;
			if (rd_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr))
				nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}
		
		uint64_t len_cmd = len;
		uint64_t ctrl_cmd = CTRL_START_RD | (clr_stat ? CTRL_CLR_STAT_RD : 0x0) | (stream ? CTRL_STREAM_RD : 0x0) | ((dest & 0xf) << CTRL_DEST_RD);
		cnfg_reg[CNFG_CTRL_REG] = _mm256_set_epi64x(len_cmd, 0, (uint64_t)vaddr, ctrl_cmd);
		
		rd_cmd_cnt++;

		if(poll) {
			while(checkBusyRead()) nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}
	}

	/**
	 * Write operation (write from FPGA user logic)
	 * @param: vaddr - memory pointer
	 * @param: len - length 
	 * @param: stream - stream from host memory
	 * @param: poll - blocking/non-blocking
	 * @param: clr_stat - prior status clear
	 */
	void fDev::_write(uint64_t* vaddr, uint32_t len, uint8_t dest, bool stream, bool clr_stat, bool poll) {
		// Check outstanding
		while (wr_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr)) {
			wr_cmd_cnt = _mm256_extract_epi64(cnfg_reg[CNFG_STAT_REG], 0) >> 32;
			if (wr_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr))
				nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}

		uint64_t len_cmd = (uint64_t)len << 32;
		uint64_t ctrl_cmd = CTRL_START_WR | (clr_stat ? CTRL_CLR_STAT_WR : 0x0) | (stream ? CTRL_STREAM_WR : 0x0) | ((dest & 0xf) << CTRL_DEST_WR);
		cnfg_reg[CNFG_CTRL_REG] = _mm256_set_epi64x(len_cmd, (uint64_t)vaddr, 0, ctrl_cmd);

		wr_cmd_cnt++;
		
		if(poll) {
			while(checkBusyWrite()) nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}
	}

	/**
	 * transfer (read + write)
	 * @param: vaddr_src, _dst - memory pointer
	 * @param: len_src, _dst - length 
	 * @param: stream - stream from host memory
	 * @param: poll - blocking/non-blocking
	 * @param: clr_stat - prior status clear
	 */
	void fDev::_transfer(uint64_t* vaddr_src, uint64_t* vaddr_dst, uint32_t len_src, uint32_t len_dst, uint8_t dest_src, uint8_t dest_dst, bool stream, bool clr_stat, bool poll) {
		// Check outstanding read
		while (rd_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr)) {
			rd_cmd_cnt = _mm256_extract_epi64(cnfg_reg[CNFG_STAT_REG], 0) & 0xffffffff;
			if (rd_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr))
				nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}
		// Check outstanding write
		while (wr_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr)) {
			wr_cmd_cnt = _mm256_extract_epi64(cnfg_reg[CNFG_STAT_REG], 0) >> 32;
			if (wr_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr))
				nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}

		uint64_t len_cmd = ((uint64_t)len_dst << 32) | len_src;
		uint64_t ctrl_cmd = CTRL_START_WR | (clr_stat ? CTRL_CLR_STAT_WR : 0x0) | (stream ? CTRL_STREAM_WR : 0x0) | ((dest_src & 0xf) << CTRL_DEST_WR) |
							CTRL_START_RD | (clr_stat ? CTRL_CLR_STAT_RD : 0x0) | (stream ? CTRL_STREAM_RD : 0x0) | ((dest_dst & 0xf) << CTRL_DEST_RD);
			
		cnfg_reg[CNFG_CTRL_REG] = _mm256_set_epi64x(len_cmd, (uint64_t)vaddr_dst, (uint64_t)vaddr_src, ctrl_cmd);

		rd_cmd_cnt++;
		wr_cmd_cnt++;

		if(poll) {
			while(checkBusyWrite()) nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}
	}

#ifdef EN_DDR
 
	/**
	 * Offload to FPGA DDR (only with local FPGA memory)
	 * @param: vaddr - memory pointer
	 * @param: len - length 
	 * @param: poll - blocking/non-blocking
	 */
	void fDev::_offload(uint64_t* vaddr, uint32_t len, bool poll) {
		// Check outstanding
		while (rd_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr)) {
			rd_cmd_cnt = _mm256_extract_epi64(cnfg_reg[CNFG_STAT_REG], 0) & 0xffffffff;
			if (rd_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr))
				nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}
		
		uint64_t len_cmd = len;
		uint64_t ctrl_cmd = CTRL_START_RD | CTRL_CLR_STAT_RD | CTRL_SYNC_RD;
		cnfg_reg[CNFG_CTRL_REG] = _mm256_set_epi64x(len_cmd, 0, (uint64_t)vaddr, ctrl_cmd);

		rd_cmd_cnt++;

		if(poll) {
			while(checkBusyRead()) nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}
	}

	/**
	 * Sync with FPGA DDR (only with local FPGA memory)
	 * @param: vaddr - memory pointer
	 * @param: len - length 
	 * @param: poll - blocking/non-blocking
	 */
	void fDev::_sync(uint64_t* vaddr, uint32_t len, bool poll) {
		// Check outstanding
		while (wr_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr)) {
			wr_cmd_cnt = _mm256_extract_epi64(cnfg_reg[CNFG_STAT_REG], 0) >> 32;
			if (wr_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr))
				nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}

		wr_cmd_cnt++;

		uint64_t len_cmd = (uint64_t)len << 32;
		uint64_t ctrl_cmd = CTRL_START_WR | CTRL_CLR_STAT_WR | CTRL_SYNC_WR;
		cnfg_reg[CNFG_CTRL_REG] = _mm256_set_epi64x(len_cmd, (uint64_t)vaddr, 0, ctrl_cmd);
		
		if(poll) {
			while(checkBusyWrite()) nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}
	}

#endif

	// ------------------------------------------------------------------------------- 
	// -- Polling
	// -------------------------------------------------------------------------------
	
	/**
	 *  Check whether busy read
	 */
	bool fDev::checkBusyRead() {
		return !(_mm256_extract_epi64(cnfg_reg[CNFG_STAT_REG], 1) & 0xffffffff);
	}

	/**
	 *  Check whether busy write
	 */
	bool fDev::checkBusyWrite() {
		return !(_mm256_extract_epi64(cnfg_reg[CNFG_STAT_REG], 1) >> 32);
	}

	/**
	 *  Return read completed
	 */
	uint32_t fDev::checkCompletedRead() {
		return _mm256_extract_epi64(cnfg_reg[CNFG_STAT_REG], 1) & 0xffffffff;
	}

	/**
	 *  Return write completed
	 */
	uint32_t fDev::checkCompletedWrite() {
		return _mm256_extract_epi64(cnfg_reg[CNFG_STAT_REG], 1) >> 32;
	}

	/**
	 * Clear status
	 */
	void fDev::clearCompleted() {
		cnfg_reg[CNFG_CTRL_REG] = _mm256_set_epi64x(0, 0, 0, CTRL_CLR_STAT_RD | CTRL_CLR_STAT_WR);
	}

	// ------------------------------------------------------------------------------- 
	// -- Timers
	// ------------------------------------------------------------------------------- 

	/**
	 * Set timer stop at x number of completed transfers
	 * @param: tmr_stop_at - stop once completed reached
	 */
	void fDev::setTimerStopAt(uint64_t tmr_stop_at) {
		cnfg_reg[CNFG_TMR_STOP_REG] = _mm256_set_epi64x(0, 0, 0, tmr_stop_at);
	}

	/**
	 * Read timer
	 */
	uint64_t fDev::getReadTimer() {
		return _mm256_extract_epi64(cnfg_reg[CNFG_TMR_REG], 0);
	}

	/**
	 * Write timer
	 */
	uint64_t fDev::getWriteTimer() {
		return _mm256_extract_epi64(cnfg_reg[CNFG_TMR_REG], 1);
	}

	// ------------------------------------------------------------------------------- 
	// -- Debug XDMA
	// ------------------------------------------------------------------------------- 

	/**
	 * XDMA debug
	 */
	void fDev::printDebugXDMA() // TODO
	{
		std::cout << "-- XDMA STATISTICS ----------------------------" << std::endl;
		std::cout << std::setw(35) << "Read command FIFO used: \t" <<  _mm256_extract_epi32(cnfg_reg[CNFG_STAT_REG], 0x0) << std::endl;
		std::cout << std::setw(35) << "Write command FIFO used: \t" <<  _mm256_extract_epi32(cnfg_reg[CNFG_STAT_REG], 0x1) << std::endl; 
		std::cout << std::setw(35) << "Reads completed: \t" <<  _mm256_extract_epi32(cnfg_reg[CNFG_STAT_REG], 0x2) << std::endl; 
		std::cout << std::setw(35) << "Writes completed: \t" <<  _mm256_extract_epi32(cnfg_reg[CNFG_STAT_REG], 0x3) << std::endl; 
		std::cout << std::setw(35) << "Read requests sent: \t" <<  _mm256_extract_epi32(cnfg_reg[CNFG_STAT_REG], 0x4) << std::endl; 
		std::cout << std::setw(35) << "Write requests sent: \t" <<  _mm256_extract_epi32(cnfg_reg[CNFG_STAT_REG], 0x5) << std::endl; 
		std::cout << std::setw(35) << "Page faults: \t" <<  _mm256_extract_epi32(cnfg_reg[CNFG_STAT_REG], 0x6) << std::endl; 
		std::cout << "-----------------------------------------------" << std::endl; 
	} 
	
#else

	/**
	 * Read operation (read to FPGA user logic)
	 * @param: vaddr - memory pointer
	 * @param: len - length 
	 * @param: poll - blocking/non-blocking
	 * @param: clr_stat - prior status clear
	 */
	void fDev::read(uint64_t* vaddr, uint32_t len, bool clr_stat, bool poll) {
		// Check outstanding
		while (rd_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr)) {
			rd_cmd_cnt = cnfg_reg[CNFG_STAT_CMD_USED_RD_REG];
			if (rd_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr))
				nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}

		cnfg_reg[CNFG_VADDR_RD_REG] = (uint64_t)vaddr;
		cnfg_reg[CNFG_LEN_RD_REG] = len;

		cnfg_reg[CNFG_CTRL_REG] = CTRL_START_RD | (clr_stat ? CTRL_CLR_STAT_RD : 0x0);

		rd_cmd_cnt++;

		if(poll) {
			while(checkBusyRead()) nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}
	}

	/**
	 * Write operation (write from FPGA user logic)
	 * @param: vaddr - memory pointer
	 * @param: len - length 
	 * @param: poll - blocking/non-blocking
	 * @param: clr_stat - prior status clear
	 */
	void fDev::write(uint64_t* vaddr, uint32_t len, bool clr_stat, bool poll) {
		// Check outstanding
		while (wr_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr)) {
			wr_cmd_cnt = cnfg_reg[CNFG_STAT_CMD_USED_WR_REG];
			if (wr_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr))
				nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}
		
		cnfg_reg[CNFG_VADDR_WR_REG] = (uint64_t)vaddr;
		cnfg_reg[CNFG_LEN_WR_REG] = len;

		cnfg_reg[CNFG_CTRL_REG] = CTRL_START_WR | (clr_stat ? CTRL_CLR_STAT_WR : 0x0);

		wr_cmd_cnt++;
		
		if(poll) {
			while(checkBusyWrite()) nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}
	}

	/**
	 * transfer (read + write)
	 * @param: vaddr_src, _dst - memory pointer
	 * @param: len_src, _dst - length 
	 * @param: poll - blocking/non-blocking
	 * @param: clr_stat - prior status clear
	 */
	void fDev::transfer(uint64_t* vaddr_src, uint64_t* vaddr_dst, uint32_t len_src, uint32_t len_dst, bool clr_stat, bool poll) {
		// Check outstanding
		while (rd_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr)) {
			rd_cmd_cnt = cnfg_reg[CNFG_STAT_CMD_USED_RD_REG];
			if (rd_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr))
				nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}

		// Check outstanding
		while (wr_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr)) {
			wr_cmd_cnt = cnfg_reg[CNFG_STAT_CMD_USED_WR_REG];
			if (wr_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr))
				nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}
		
		cnfg_reg[CNFG_VADDR_RD_REG] = (uint64_t)vaddr_src;
		cnfg_reg[CNFG_LEN_RD_REG] = len_src;
		cnfg_reg[CNFG_VADDR_WR_REG] = (uint64_t)vaddr_dst;
		cnfg_reg[CNFG_LEN_WR_REG] = len_dst;

		cnfg_reg[CNFG_CTRL_REG] = CTRL_START_RD | (clr_stat ? CTRL_CLR_STAT_RD : 0x0);
		cnfg_reg[CNFG_CTRL_REG] = CTRL_START_WR | (clr_stat ? CTRL_CLR_STAT_WR : 0x0);

		rd_cmd_cnt++;
		wr_cmd_cnt++;

		if(poll) {
			while(checkBusyWrite()) nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}
	}

#ifdef EN_DDR

	/**
	 * Offload to FPGA DDR (only with local FPGA memory)
	 * @param: vaddr - memory pointer
	 * @param: len - length 
	 * @param: poll - blocking/non-blocking
	 */
	void fDev::offload(uint64_t* vaddr, uint32_t len, bool poll) {
		cnfg_reg[CNFG_VADDR_RD_REG] = (uint64_t)vaddr;
		cnfg_reg[CNFG_LEN_RD_REG] = len;

		cnfg_reg[CNFG_CTRL_REG] = CTRL_SYNC_RD | CTRL_START_RD | CTRL_CLR_STAT_RD;

		rd_cmd_cnt++;

		if(poll) {
			while(checkBusyRead()) nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}
	}

	/**
	 * Sync with FPGA DDR (only with local FPGA memory)
	 * @param: vaddr - memory pointer
	 * @param: len - length 
	 * @param: poll - blocking/non-blocking
	 */
	void fDev::sync(uint64_t* vaddr, uint32_t len, bool poll) {
		cnfg_reg[CNFG_VADDR_WR_REG] = (uint64_t)vaddr;
		cnfg_reg[CNFG_LEN_WR_REG] = len;

		cnfg_reg[CNFG_CTRL_REG] = CTRL_SYNC_WR | CTRL_START_WR | CTRL_CLR_STAT_WR;

		wr_cmd_cnt++;
		
		if(poll) {
			while(checkBusyWrite()) nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}
	}

#endif

	/**
	 * XDMA debug
	 */
	void fDev::printDebugXDMA() // TODO
	{
		std::cout << "-- XDMA STATISTICS ----------------------------" << std::endl;
		std::cout << "-----------------------------------------------" << std::endl;
	}

	// ------------------------------------------------------------------------------- 
	// -- Polling
	// -------------------------------------------------------------------------------
	bool fDev::checkBusyRead() {
		return !(cnfg_reg[CNFG_STAT_DMA_RD_REG]);
	}

	bool fDev::checkBusyWrite() {
		return !(cnfg_reg[CNFG_STAT_DMA_WR_REG]);
	}

	uint32_t fDev::checkCompletedRead() {
		return (cnfg_reg[CNFG_STAT_DMA_RD_REG]);
	}

	uint32_t fDev::checkCompletedWrite() {
		return (cnfg_reg[CNFG_STAT_DMA_WR_REG]);
	}

	void fDev::clearCompleted() {
		cnfg_reg[CNFG_CTRL_REG] = CTRL_CLR_STAT_RD | CTRL_CLR_STAT_WR;
	}

	// ------------------------------------------------------------------------------- 
	// -- Timers
	// ------------------------------------------------------------------------------- 

	/**
	 * Set timer stop at x number of completed transfers
	 * @param: tmr_stop_at - stop once completed reached
	 */
	void fDev::setTimerStopAt(uint64_t tmr_stop_at) {
		cnfg_reg[CNFG_TMR_STOP_REG] = tmr_stop_at;
	}

	/**
	 * Read timer
	 */
	uint64_t fDev::getReadTimer() {
		return cnfg_reg[CNFG_TMR_RD_REG];
	}

	/**
	 * Write timer
	 */
	uint64_t fDev::getWriteTimer() {
		return cnfg_reg[CNFG_TMR_WR_REG];
	}

#endif

// -------------------------------------------------------------------------------
// -- Network static
// -------------------------------------------------------------------------------

#ifdef EN_RDMA

/**
 * ARP lookup
 */
bool fDev::doArpLookup() {
	ioctl(fd, IOCTL_ARP_LOOKUP, 0);
	return true;
}

/**
 * Write QP context 
 * @param: pair - target queue pair
 */
void fDev::writeContext(fQPair *pair) {
	uint64_t offs[3]; 
	offs[0] = (((uint64_t)pair->remote.psn & 0xffffff) << 31) | (((uint64_t)pair->local.qpn & 0xffffff) << 7) | (((uint64_t)pair->local.region & 0xf) << 3);
	offs[1] = (((uint64_t)pair->remote.rkey & 0xffffff) << 24) | ((uint64_t)pair->local.psn & 0xffffff); 
	offs[2] = (uint64_t)pair->remote.vaddr;
	ioctl(fd, IOCTL_WRITE_CTX, &offs);
}

/**
 * Write QP connection 
 * @param: pair - target queue pair
 */
void fDev::writeConnection(fQPair *pair, uint32_t port) {
	uint64_t offs[3];
	offs[0] = (((uint64_t)port & 0xffff) << 40) | (((uint64_t)pair->remote.qpn & 0xffffff) << 16) | ((pair->local.qpn) & 0xffff);
	offs[1] = ((htols((uint64_t)pair->remote.gidToUint(8)) & 0xffffffff) << 32) | (htols((uint64_t)pair->remote.gidToUint(0)) & 0xffffffff);
	offs[2] = ((htols((uint64_t)pair->remote.gidToUint(24)) & 0xffffffff) << 32) | (htols((uint64_t)pair->remote.gidToUint(16)) & 0xffffffff);
	ioctl(fd, IOCTL_WRITE_CONN, &offs);
}

	// -------------------------------------------------------------------------------
	// -- Network
	// -------------------------------------------------------------------------------

#ifdef EN_AVX

	/**
	 * RDMA write
	 * @param: l_addr - local virtual address
	 * @param: r_addr - remote virtual address
	 * @param: size - transfer size
	 */
	bool fDev::postWrite(fQPair *pair, uint64_t l_offs, uint64_t r_offs, uint32_t size) {
		uint64_t l_addr = pair->local.vaddr + l_offs;
		uint64_t r_addr = pair->remote.vaddr + r_offs;

		uint64_t offs_0 = (((uint64_t)pair->local.qpn & 0xffffff) << 5) | ((uint64_t)opCode::WRITE & 0x1f);
		uint64_t offs_1 = (((uint64_t)r_addr & 0xffff) << 48) | ((uint64_t)l_addr & 0xffffffffffff);
		uint64_t offs_2 = ((uint64_t)size << 32) | (((uint64_t)r_addr >> 16) & 0xffffffff);
		uint64_t offs_3 = 0;

		postCmd(offs_3, offs_2, offs_1, offs_0);

		return 0;
	}

	/**
	 * RDMA read
	 * @param: l_addr - local virtual address
	 * @param: r_addr - remote virtual address
	 * @param: size - transfer size
	 */
	bool fDev::postRead(fQPair *pair, uint64_t l_offs, uint64_t r_offs, uint32_t size) {
		uint64_t l_addr = pair->local.vaddr + l_offs;
		uint64_t r_addr = pair->remote.vaddr + r_offs;

		uint64_t offs_0 = (((uint64_t)pair->local.qpn & 0xffffff) << 5) | ((uint64_t)opCode::READ & 0x1f);
		uint64_t offs_1 = (((uint64_t)r_addr & 0xffff) << 48) | ((uint64_t)l_addr & 0xffffffffffff);
		uint64_t offs_2 = ((uint64_t)size << 32) | (((uint64_t)r_addr >> 16) & 0xffffffff);
		uint64_t offs_3 = 0;

		postCmd(offs_3, offs_2, offs_1, offs_0);

		return 0;
	}

	/**
	 * RDMA RPC
	 * @param: offs_3, _2, _1 - parameters
	 */
	bool fDev::postFarview(fQPair *pair, uint64_t l_offs, uint64_t r_offs, uint32_t size, uint64_t params) {
		uint64_t l_addr = pair->local.vaddr + l_offs;
		uint64_t r_addr = pair->remote.vaddr + r_offs;

		uint64_t offs_0 = (((uint64_t)pair->local.qpn & 0xffffff) << 5) | ((uint64_t)opCode::FV & 0x1f);
		uint64_t offs_1 = (((uint64_t)r_addr & 0xffff) << 48) | ((uint64_t)l_addr & 0xffffffffffff);
		uint64_t offs_2 = ((uint64_t)size << 32) | (((uint64_t)r_addr >> 16) & 0xffffffff);
		uint64_t offs_3 = params;

		postCmd(offs_3, offs_2, offs_1, offs_0);

		return 0;
	}

	/** 
	 * Base post
	 */
	void fDev::postCmd(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0) {
		// Check outstanding
		while (rdma_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr)) {
			rdma_cmd_cnt = _mm256_extract_epi64(cnfg_reg[CNFG_RDMA_STAT_CMD_USED_REG], 0) & 0xffffffff;
			if (rdma_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr))
				nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}

		cnfg_reg[CNFG_RDMA_POST_REG] = _mm256_set_epi64x(offs_3, offs_2, offs_1, offs_0);

		rdma_cmd_cnt++;
	}

#else

	// -------------------------------------------------------------------------------
	// -- Network
	// -------------------------------------------------------------------------------

	/**
	 * RDMA write
	 * @param: l_addr - local virtual address
	 * @param: r_addr - remote virtual address
	 * @param: size - transfer size
	 */
	bool fDev::postWrite(rQPair *pair, uint64_t *l_addr, uint64_t *r_addr, uint32_t size) {
		if(qpn_attached)
			postCmd(opCode::WRITE, pair, l_addr, r_addr, size);
		else 
			return 1;
		
		return 0;
	}
	
	/**
	 * RDMA read
	 * @param: l_addr - local virtual address
	 * @param: r_addr - remote virtual address
	 * @param: size - transfer size
	 */
	bool fDev::postRead(rQPair *pair, uint64_t *l_addr, uint64_t *r_addr, uint32_t size) {
		if(qpn_attached) 
			postCmd(opCode::READ, pair, l_addr, r_addr, size);
		else 
			return 1;

		return 0;
	}

	/**
	 * Base post
	 * TODO: Change to new config
	 */
	void fDev::postCmd(opCode op, rQPair *pair, uint64_t *l_addr, uint64_t *r_addr, uint32_t size) {
	#ifdef VERBOSE_DEBUG
		std::cout << "Post, queue pair l: " << pair->local.qpn << ", r: " << pair->remote.qpn << std::endl;
	#endif

		// Check outstanding
		while (rdma_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr)) {
			rdma_cmd_cnt = cnfg_reg[CNFG_RDMA_STAT_CMD_USED_REG];
			if (rdma_cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr))
				nanosleep((const struct timespec[]){{0, 100L}}, NULL);
		}

		cnfg_reg[CNFG_RDMA_POST_REG_0] = (((uint64_t)size << 27)) | (((uint64_t)pair->local.qpn & 0xffffff) << 3) | (((uint64_t)op & 0x3));
		cnfg_reg[CNFG_RDMA_POST_REG_1] = (uint64_t)l_addr;
		cnfg_reg[CNFG_RDMA_POST_REG_2] = (uint64_t)r_addr;
		cnfg_reg[CNFG_RDMA_POST_REG_3] = 0;
		
		rdma_cmd_cnt++;
	}

#endif 
#endif

}
