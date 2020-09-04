#include <iostream>
#include <fcntl.h>
#include <unistd.h>
#include <fstream>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <time.h> 
#include <sys/time.h>  
#include <chrono>

#include "fDev.hpp"

/* Performance test */
#define PERF_RUN

/* AVX */
#define AVX_WIDTH 						8
#define PR_WIDTH 						2 * 1024 * 1024

/* Sleep */
#define POLL_SLEEP_NS 					100

#define LARGE_PAGE_SIZE 				2 * 1024 * 1024
#define LARGE_PAGE_SHIFT 				21UL
#define PAGE_SIZE 						4 * 1024
#define PAGE_SHIFT 						12UL

/* Clock */
#define CLK_NS 							4

/* MMAP */
#define MMAP_CTRL                       (0x0 << PAGE_SHIFT)
#define MMAP_CNFG                       (0x1 << PAGE_SHIFT)
#define MMAP_DATA                       (0x2 << PAGE_SHIFT)
#define MMAP_PREC                       (0x3 << PAGE_SHIFT)
#define MMAP_BUFF                       (0x200 << PAGE_SHIFT)
#define MMAP_CARD                       (0x400 << PAGE_SHIFT)
#define MMAP_CHAN_0                     (0x600 << PAGE_SHIFT)
#define MMAP_CHAN_1                     (0x800 << PAGE_SHIFT)

/* IOCTL */
#define IOCTL_ALLOC_HOST_MEM            _IOR('D', 1, unsigned long)
#define IOCTL_FREE_HOST_MEM             _IOR('D', 2, unsigned long)
#define IOCTL_ALLOC_CARD_MEM_STRIDE     _IOR('D', 3, unsigned long)
#define IOCTL_FREE_CARD_MEM_STRIDE      _IOR('D', 4, unsigned long)
#define IOCTL_READ_ENG_STATUS           _IOR('D', 5, unsigned long)
#define IOCTL_UNMAP_USER                _IOR('D', 6, unsigned long)
#define IOCTL_RECONFIG_LOCK             _IOR('D', 7, unsigned long)
#define IOCTL_RECONFIG_UNLOCK           _IOR('D', 8, unsigned long)
#define IOCTL_ALLOC_CARD_MEM_CHAN_0     _IOR('D', 9, unsigned long)
#define IOCTL_ALLOC_CARD_MEM_CHAN_1     _IOR('D', 10, unsigned long)
#define IOCTL_FREE_CARD_MEM_CHAN_0      _IOR('D', 11, unsigned long)
#define IOCTL_FREE_CARD_MEM_CHAN_1      _IOR('D', 12, unsigned long)
#define IOCTL_MAP_USER 					_IOR('D', 13, unsigned long)

/* Regions */
#define CTRL_REGION_SIZE        		64 * 1024
#define CNFG_REGION_SIZE        		64 * 1024
#define DATA_REGION_SIZE        		1 * 1024 * 1024
#define PREC_REGION_SIZE 				32 * 1024

/* Config regs */
#define CNFG_CTRL_REG 					0x0
#define CNFG_STATUS_REG 				0x1
#define CNFG_STATUS_DMA_RD_REG 			0x2
#define CNFG_STATUS_DMA_WR_REG 			0x3
#define CNFG_VADDR_RD_REG				0x4
#define CNFG_LEN_RD_REG					0x5
#define CNFG_VADDR_WR_REG				0x6
#define CNFG_LEN_WR_REG					0x7
#define CNFG_VADDR_MISS_REG 			0x8
#define CNFG_LEN_MISS_REG 				0x9
#define CNFG_DCPL_REG					0xA
#define CNFG_DP_REG						0xB
#define CNFG_TMR_STOP_REG				0xC
#define CNFG_TMR_RD_REG 				0xD
#define CNFG_TMR_WR_REG					0xE

#define CNFG_CTRL_START_RD 				0x1
#define CNFG_CTRL_START_WR 				0x2
#define CNFG_CTRL_START_TMR_RD 			0x8
#define CNFG_CTRL_START_TMR_WR 			0x10
#define CNFG_CTRL_CLR_STAT_RD			0x20
#define CNFG_CTRL_CLR_STAT_WR			0x40
#define CNFG_CTRL_START_CYC 			(CNFG_CTRL_START_RD | CNFG_CTRL_START_WR)
#define CNFG_CTRL_START_TMR_CYC 		(CNFG_CTRL_START_TMR_RD | CNFG_CTRL_START_TMR_WR)
#define CNFG_CTRL_CLR_STAT_CYC			(CNFG_CTRL_CLR_STAT_RD | CNFG_CTRL_CLR_STAT_WR)
#define CNFG_STATUS_READY_RD 			0x1
#define CNFG_STATUS_READY_WR 			0x2

using namespace std::chrono;

/* -- Obtain regions ---------------------------------------------------------------------------------- */

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

	regionAcquired = true;
	return true;
}

bool fDev::releaseRegion() {
	close(fd);

	regionAcquired = false;
	return true;
}

bool fDev::isRegionAcquired() {
	return regionAcquired;
}

bool fDev::mmapFpga() {
	cnfg_reg = (uint64_t*) mmap(NULL, CNFG_REGION_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_CNFG);
	if(cnfg_reg == MAP_FAILED) {
		releaseRegion();
		return false;
	}

	ctrl_reg = (uint64_t*) mmap(NULL, CTRL_REGION_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_CTRL);
	if(ctrl_reg == MAP_FAILED) {
		releaseRegion();
		return false;
	}

	data_reg = (__m256i*)  mmap(NULL, DATA_REGION_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_DATA);
	if(data_reg == MAP_FAILED) {
		releaseRegion();
		return false;
	}

	return true;
}

bool fDev::munmapFpga() {
	if(munmap(cnfg_reg, CNFG_REGION_SIZE) != 0) {
		releaseRegion();
		return false;
	}

	if(munmap(ctrl_reg, CTRL_REGION_SIZE) != 0) {
		releaseRegion();
		return false;
	}

	if(munmap(data_reg, DATA_REGION_SIZE) != 0) {
		releaseRegion();
		return false;
	}

	cnfg_reg = 0;
	ctrl_reg = 0;
	data_reg = 0;

	return true;
}

/* -- Memory management ------------------------------------------------------------------------------- */
uint64_t* fDev::getHostMem(uint64_t &n_pages) {
	uint64_t *hMem, *hMemAligned;

	ioctl(fd, IOCTL_ALLOC_HOST_MEM, &n_pages);
	hMem = (uint64_t*)mmap(NULL, (n_pages + 1) * LARGE_PAGE_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_BUFF);
	// alignment
	hMemAligned =  (uint64_t*)( ((((uint64_t)hMem + LARGE_PAGE_SIZE - 1) >> LARGE_PAGE_SHIFT)) << LARGE_PAGE_SHIFT);
	mapped_large[hMemAligned] = hMem;
	return hMemAligned;
}

void fDev::freeHostMem(uint64_t *vaddr, uint64_t &n_pages) {
	uint64_t* hMem;
	hMem = mapped_large[vaddr];
	munmap(hMem, (n_pages + 1) * LARGE_PAGE_SIZE);
	ioctl(fd, IOCTL_FREE_HOST_MEM, &vaddr);
}

uint64_t* fDev::getCardMem(uint64_t &n_pages, int channel) {
	uint64_t *cMem, *cMemAligned;
	if(channel == 0) {
		ioctl(fd, IOCTL_ALLOC_CARD_MEM_CHAN_0, &n_pages);
		cMem = (uint64_t*)mmap(NULL, (n_pages + 1) * LARGE_PAGE_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_CHAN_0);
	} else if(channel == 1) {
		ioctl(fd, IOCTL_ALLOC_CARD_MEM_CHAN_1, &n_pages);
		cMem = (uint64_t*)mmap(NULL, (n_pages + 1) * LARGE_PAGE_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_CHAN_1);
	}
	// alignment
	cMemAligned =  (uint64_t*)( ((((uint64_t)cMem + LARGE_PAGE_SIZE - 1) >> LARGE_PAGE_SHIFT)) << LARGE_PAGE_SHIFT);
	mapped_large[cMemAligned] = cMem;
	return cMemAligned;
}

void fDev::freeCardMem(uint64_t *vaddr, uint64_t &n_pages, int channel) {
	uint64_t* cMem;
	cMem = mapped_large[vaddr];
	munmap(cMem, (n_pages + 1) * LARGE_PAGE_SIZE);
	if(channel == 0)
		ioctl(fd, IOCTL_FREE_CARD_MEM_CHAN_0, &vaddr);
	else if(channel == 1)
		ioctl(fd, IOCTL_FREE_CARD_MEM_CHAN_1, &vaddr);
}

uint64_t* fDev::getCardMem(uint64_t &n_pages) {
	uint64_t *cMem;

	ioctl(fd, IOCTL_ALLOC_CARD_MEM_STRIDE, &n_pages);
	cMem = (uint64_t*)mmap(NULL, (2*n_pages) * PAGE_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, MMAP_CARD);
	// alignment
	return cMem;
}

void fDev::freeCardMem(uint64_t *vaddr, uint64_t &n_pages) {
	munmap(vaddr, (2*n_pages) * PAGE_SIZE);
	ioctl(fd, IOCTL_FREE_CARD_MEM_STRIDE, &vaddr);
}

void fDev::userMap(uint64_t *mem, uint64_t len) {
	uint64_t vdata [2];
	vdata[0] = (uint64_t)mem;
	vdata[1] = len;
	ioctl(fd, IOCTL_MAP_USER, &vdata);
}

void fDev::userUnmap(uint64_t *mem, uint64_t len) {
	uint64_t vdata [2];
	vdata[0] = (uint64_t)mem;
	vdata[1] = len;
	ioctl(fd, IOCTL_UNMAP_USER, &vdata);
}

/* -- Bulk transfers ---------------------------------------------------------------------------------- */

void fDev::readFrom(uint64_t* vaddr, uint32_t len, bool poll) {
	cnfg_reg[CNFG_VADDR_RD_REG] = (uint64_t)vaddr;
	cnfg_reg[CNFG_LEN_RD_REG] = len;
#ifndef PERF_RUN
	cnfg_reg[CNFG_CTRL_REG] = CNFG_CTRL_START_RD;
#else
	cnfg_reg[CNFG_CTRL_REG] = CNFG_CTRL_START_RD | CNFG_CTRL_START_TMR_RD | CNFG_CTRL_CLR_STAT_RD;
#endif

	if(poll) {
		while(checkBusyRead()) nanosleep((const struct timespec[]){{0, 100L}}, NULL);
	}
}

void fDev::writeTo(uint64_t* vaddr, uint32_t len, bool poll) {
	cnfg_reg[CNFG_VADDR_WR_REG] = (uint64_t)vaddr;
	cnfg_reg[CNFG_LEN_WR_REG] = len;
#ifndef PERF_RUN
	cnfg_reg[CNFG_CTRL_REG] = CNFG_CTRL_START_WR;
#else
	cnfg_reg[CNFG_CTRL_REG] = CNFG_CTRL_START_WR | CNFG_CTRL_START_TMR_WR | CNFG_CTRL_CLR_STAT_WR;
#endif
	
	if(poll) {
		while(checkBusyWrite()) nanosleep((const struct timespec[]){{0, 100L}}, NULL);
	}
}

void fDev::transferData(uint64_t* vaddr, uint32_t len, bool poll) {
	cnfg_reg[CNFG_VADDR_RD_REG] = (uint64_t)vaddr;
	cnfg_reg[CNFG_LEN_RD_REG] = len;
	cnfg_reg[CNFG_VADDR_WR_REG] = (uint64_t)vaddr;
	cnfg_reg[CNFG_LEN_WR_REG] = len;
#ifndef PERF_RUN
	cnfg_reg[CNFG_CTRL_REG] = CNFG_CTRL_START_WR | CNFG_CTRL_START_RD;
#else
	cnfg_reg[CNFG_CTRL_REG] = CNFG_CTRL_START_WR | CNFG_CTRL_START_RD | 
							  	CNFG_CTRL_START_TMR_WR | CNFG_CTRL_START_TMR_RD | 
								CNFG_CTRL_CLR_STAT_WR | CNFG_CTRL_CLR_STAT_RD;
#endif

	if(poll) {
		while(checkBusyWrite()) nanosleep((const struct timespec[]){{0, 100L}}, NULL);
	}
}

void fDev::transferData(uint64_t* vaddr_src, uint64_t* vaddr_dst, uint32_t len, bool poll) {
	cnfg_reg[CNFG_VADDR_RD_REG] = (uint64_t)vaddr_src;
	cnfg_reg[CNFG_LEN_RD_REG] = len;
	cnfg_reg[CNFG_VADDR_WR_REG] = (uint64_t)vaddr_dst;
	cnfg_reg[CNFG_LEN_WR_REG] = len;
#ifndef PERF_RUN
	cnfg_reg[CNFG_CTRL_REG] = CNFG_CTRL_START_RD;
	cnfg_reg[CNFG_CTRL_REG] = CNFG_CTRL_START_WR;
#else
	cnfg_reg[CNFG_CTRL_REG] = CNFG_CTRL_START_RD | CNFG_CTRL_START_TMR_RD | CNFG_CTRL_CLR_STAT_RD;
	cnfg_reg[CNFG_CTRL_REG] = CNFG_CTRL_START_WR | CNFG_CTRL_START_TMR_WR | CNFG_CTRL_CLR_STAT_WR;
#endif	

	if(poll) {
		while(checkBusyWrite()) nanosleep((const struct timespec[]){{0, 100L}}, NULL);
	}
}

void fDev::transferData(uint64_t* vaddr, uint32_t len_src, uint32_t len_dst, bool poll) {
	cnfg_reg[CNFG_VADDR_RD_REG] = (uint64_t)vaddr;
	cnfg_reg[CNFG_LEN_RD_REG] = len_src;
	cnfg_reg[CNFG_VADDR_WR_REG] = (uint64_t)vaddr;
	cnfg_reg[CNFG_LEN_WR_REG] = len_dst;
#ifndef PERF_RUN
	cnfg_reg[CNFG_CTRL_REG] = CNFG_CTRL_START_RD;
	cnfg_reg[CNFG_CTRL_REG] = CNFG_CTRL_START_WR;
#else
	cnfg_reg[CNFG_CTRL_REG] = CNFG_CTRL_START_RD | CNFG_CTRL_START_TMR_RD | CNFG_CTRL_CLR_STAT_RD;
	cnfg_reg[CNFG_CTRL_REG] = CNFG_CTRL_START_WR | CNFG_CTRL_START_TMR_WR | CNFG_CTRL_CLR_STAT_WR;
#endif

	if(poll) {
		while(checkBusyWrite()) nanosleep((const struct timespec[]){{0, 100L}}, NULL);
	}
}

void fDev::transferData(uint64_t* vaddr_src, uint64_t* vaddr_dst, uint32_t len_src, uint32_t len_dst, bool poll) {
	cnfg_reg[CNFG_VADDR_RD_REG] = (uint64_t)vaddr_src;
	cnfg_reg[CNFG_LEN_RD_REG] = len_src;
	cnfg_reg[CNFG_VADDR_WR_REG] = (uint64_t)vaddr_dst;
	cnfg_reg[CNFG_LEN_WR_REG] = len_dst;
#ifndef PERF_RUN
	cnfg_reg[CNFG_CTRL_REG] = CNFG_CTRL_START_RD;
	cnfg_reg[CNFG_CTRL_REG] = CNFG_CTRL_START_WR;
#else
	cnfg_reg[CNFG_CTRL_REG] = CNFG_CTRL_START_RD | CNFG_CTRL_START_TMR_RD | CNFG_CTRL_CLR_STAT_RD;
	cnfg_reg[CNFG_CTRL_REG] = CNFG_CTRL_START_WR | CNFG_CTRL_START_TMR_WR | CNFG_CTRL_CLR_STAT_WR;
#endif

	if(poll) {
		while(checkBusyWrite()) nanosleep((const struct timespec[]){{0, 100L}}, NULL);
	}
}

/* -- Polling  ---------------------------------------------------------------------------------------- */

bool fDev::checkBusyRead() {
	return !(cnfg_reg[CNFG_STATUS_DMA_RD_REG]);
}

bool fDev::checkBusyWrite() {
	return !(cnfg_reg[CNFG_STATUS_DMA_WR_REG]);
}

uint32_t fDev::checkCompletedRead() {
	return (cnfg_reg[CNFG_STATUS_DMA_RD_REG]);
}

uint32_t fDev::checkCompletedWrite() {
	return (cnfg_reg[CNFG_STATUS_DMA_WR_REG]);
}

bool fDev::checkReadyRead() {
	return cnfg_reg[CNFG_STATUS_REG] & CNFG_STATUS_READY_RD;
}

bool fDev::checkReadyWrite() {
	return cnfg_reg[CNFG_STATUS_REG] & CNFG_STATUS_READY_WR;
}

void fDev::clearCompleted(bool rd, bool wr) {
	cnfg_reg[CNFG_CTRL_REG] = (rd & CNFG_CTRL_CLR_STAT_RD) | (wr & CNFG_CTRL_CLR_STAT_WR);
}

/* -- Partial reconfiguration ------------------------------------------------------------------------- */
void fDev::addBitstream(std::string name, uint32_t op_id) {
	fBitStream* bstream = new fBitStream(name, op_id, this);
	if(bstream->openBitStream())
		bitstreams.insert({op_id, bstream});
}

void fDev::removeBitstream(uint32_t op_id) {
	bitstreams[op_id]->closeBitStream();
	bitstreams.erase(op_id);
}


uint8_t readByte(std::ifstream& fb) {
	char temp;
	fb.read(&temp, 1);
	return (uint8_t)temp;
}

uint32_t fDev::reconfigure(uint32_t op_id) {
	fBitStream *bstream = bitstreams[op_id];

	// Obtain the lock and decouple the design
	ioctl(fd, IOCTL_RECONFIG_LOCK, 0);

	high_resolution_clock::time_point begin = high_resolution_clock::now();

	for(uint i = 0; i < bstream->getFszM(); i++) {
		// Send the data
		readFrom((uint64_t*)(bstream->getSrc() + i*bstream->getBatchSize()/4), bstream->getBatchSize());
	}
	// Last batch
	if(bstream->getFszR() > 0) 
		readFrom((uint64_t*)(bstream->getSrc() + bstream->getFszM()*bstream->getBatchSize()/4), bstream->getFszR());

	high_resolution_clock::time_point end = high_resolution_clock::now();
	auto duration = duration_cast<microseconds>(end - begin).count();
    std::cout << std::dec << "PR completed in: " << duration << " us" << std::endl;

	// Free the lock and couple the design
	ioctl(fd, IOCTL_RECONFIG_UNLOCK, 0);

	return 0;
}

/* -- Timers ------------------------------------------------------------------------------------------ */
void fDev::setTimerStop(uint64_t tmr_stop) {
	cnfg_reg[CNFG_TMR_STOP_REG] = tmr_stop;
}

uint64_t fDev::getTimerStop() {
	return cnfg_reg[CNFG_TMR_STOP_REG];
}


uint64_t fDev::getReadTimer() {
	return cnfg_reg[CNFG_TMR_RD_REG];
}

uint64_t fDev::getWriteTimer() {
	return cnfg_reg[CNFG_TMR_WR_REG];
}

double fDev::getThroughputRd(uint32_t size) {
	return (double)((size / (1024.0 * 1024.0)) / (cnfg_reg[CNFG_TMR_RD_REG] * CLK_NS ) * 1000000000);
}

double fDev::getThroughputWr(uint32_t size) {
	return (double)((size / (1024.0 * 1024.0)) / (cnfg_reg[CNFG_TMR_WR_REG] * CLK_NS ) * 1000000000);
}

uint64_t fDev::getTimeRdNS() {
	return cnfg_reg[CNFG_TMR_RD_REG] * CLK_NS;
}

uint64_t fDev::getTimeWrNS() {
	return cnfg_reg[CNFG_TMR_WR_REG] * CLK_NS;
}
