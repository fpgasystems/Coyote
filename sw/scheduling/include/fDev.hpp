#ifndef __FDEV_HPP__
#define __FDEV_HPP__

#include <cstdint>
#include <cstdio>
#include <string>
#include <unordered_map> 
#include <x86intrin.h>
#include <smmintrin.h>
#include <immintrin.h>
#include <vector>
#include <iostream>

#include <fcntl.h>
#include <unistd.h>
#include <fstream>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <time.h> 
#include <sys/time.h>  
#include <chrono>

#define N_BSTREAM_PAGES     20
#define PR_WIDTH            2 * 1024 * 1024

using namespace std;

class fBitStream;

/**
 * Fpga device region 
 */
class fDev {

	/* Fpga device */
	int32_t fd = 0;
	bool regionAcquired = false;
	std::unordered_map<uint32_t, fBitStream*> bitstreams;

	/* Mmapped regions */
	uint64_t *cnfg_reg = 0;
	uint64_t *ctrl_reg = 0;
	__m256i  *data_reg = 0;

	/* Mapped large pages hash table */
	std::unordered_map<uint64_t*, uint64_t*> mapped_large;

	/* Utility */
	bool mmapFpga();
	bool munmapFpga();

protected:
	

public:

	fDev() {}
	~fDev() {}

	/**
	 * Obtain and release FPGA regions
	 */ 

	// Acquire an FPGA region with target ID
	bool acquireRegion(uint32_t rNum);
	// Release an acquired FPGA region
	bool releaseRegion();
	// Check whether region has been acquired
	bool isRegionAcquired();
	
	/**
	 * Control bus
	 */

	// Control status bus, AXI Lite
	inline void setCSR(uint64_t val, uint32_t offs) { ctrl_reg[offs] = val; }
	inline uint64_t getCSR(uint32_t offs) { return ctrl_reg[offs]; }

	/**
	 * Data bus (SIMD)
	 * TODO: Vector construction
	 */

	// Data AVX bus
	inline void setData(__m256i val, uint32_t offs) { data_reg[offs] = val; }
	inline __m256i getData(uint32_t offs) { return data_reg[offs]; }

	/**
	 * Explicit buffer management
	 * @param n_pages - number of 2MB pages to be allocated
	 */

	// Obtain host memory - pages 2M
	uint64_t* getHostMem(uint64_t &n_pages);
	// Obtain card memory - pages 2M
	uint64_t* getCardMem(uint64_t &n_pages, int channel); // No striding, explicit channel management
	// Obtain card memory - pages 4K - striding (hw needs to be compiled with stride enabled)
	uint64_t* getCardMem(uint64_t &n_pages); // Striding, TODO: Extend striding support for 2MB pages (now at 4K)
	// Free host memory
	void freeHostMem(uint64_t* vaddr, uint64_t &n_pages);
	// Free card memory
	void freeCardMem(uint64_t* vaddr, uint64_t &n_pages, int channel);
	// Free card memory (striding)
	void freeCardMem(uint64_t* vaddr, uint64_t &n_pages);
	
	// FPGA user space range mapping
	void userMap(uint64_t *vaddr, uint64_t len);
	// FPGA user space range unmapping (done auto on release)
	void userUnmap(uint64_t *vaddr, uint64_t len);


	/**
	 * Bulk transfers
	 * @param vaddr - data pointer
	 * @param len - transfer length
	 * @param poll - blocking vs non-blocking
	 */

	// Reads data from the pointer into the FPGA region (can be both host and card)
	void readFrom(uint64_t *vaddr, uint32_t len, bool poll = true);
	// Writes data from the FPGA region to the pointer 
	void writeTo(uint64_t *vaddr, uint32_t len, bool poll = true);
	// Transfer data (read + write)
	void transferData(uint64_t *vaddr, uint32_t len, bool poll = true);
	void transferData(uint64_t *vaddr_src, uint64_t* vaddr_dst, uint32_t len, bool poll = true);
	void transferData(uint64_t *vaddr, uint32_t len_src, uint32_t len_dst, bool poll = true);
	void transferData(uint64_t *vaddr_src, uint64_t* vaddr_dst, uint32_t len_src, uint32_t len_dst, bool poll = true);
	
	/**
	 * Check for completion
	 */

	// Check whether read engine is busy
	bool checkBusyRead();
	// Check whether write engine is busy
	bool checkBusyWrite();
	// Returns the number of completed reads
	uint32_t checkCompletedRead();
	// Returns the number of completed writes
	uint32_t checkCompletedWrite();
	// Clear all status
	void clearCompleted(bool rd, bool wr);
	
	/**
	 * Check whether engines are ready to accept transfers
	 */

	// Check whether read request queue is full
	bool checkReadyRead();
	// Check whether write request queue is full
	bool checkReadyWrite();

	/**
	 * Partial reconfiguration
	 */ 

	// Only function needed for PR, bitstream needs to be in binary format (.bin)
	uint32_t reconfigure(uint32_t op_id);
	// Add a bitstream
	void addBitstream(std::string name, uint32_t op_id);
	// Remove a bitstream
	void removeBitstream(uint32_t op_id);

	/**
	 * Performance tests
	 */
	void setTimerStop(uint64_t tmr_stop);
	uint64_t getTimerStop();
	uint64_t getReadTimer();
	uint64_t getWriteTimer();
	double getThroughputRd(uint32_t len);
	double getThroughputWr(uint32_t len);
	uint64_t getTimeRdNS();
	uint64_t getTimeWrNS();
};

/**
 * Bitstream object
 */
class fBitStream {
private:
    string name;
    uint32_t op_id;

    uint64_t fsz;
    uint64_t fsz_m;
    uint64_t fsz_r;
    uint64_t n_pages = N_BSTREAM_PAGES;
    uint64_t pr_batch = PR_WIDTH;
    
	bool opened;

    fDev* fdev;

    uint32_t* src;
    
public:
    fBitStream(string name, uint32_t op_id, fDev* fdev) {
        this->name = name;
        this->op_id = op_id;
        this->fdev = fdev;
		opened = false;
    }

    ~fBitStream() {
        closeBitStream();
    }

    uint64_t getFsz() {
        return fsz;
    }

    uint64_t getFszM() {
        return fsz_m;
    }

    uint64_t getFszR() {
        return fsz_r;
    }

    uint64_t getBatchSize() {
        return pr_batch;
    }

    uint32_t* getSrc() {
        return src;
    }

	bool isOpened() {
		return opened;
	}

    uint8_t readByte(ifstream& fb) {
        char temp;
        fb.read(&temp, 1);
        return (uint8_t)temp;
    }


    bool openBitStream() {
        ifstream f_bit(name, ios::ate | ios::binary);
        if(!f_bit) {
            cout << "Bitstream could not be opened" << endl;
            return false;
        }

        fsz = f_bit.tellg();
        f_bit.seekg(0);

        fsz_m = fsz / pr_batch;
	    fsz_r = fsz % pr_batch;

		cout << "Full: " << fsz_m << ", partial: " << fsz_r << endl;

        src = (uint32_t*) fdev->getHostMem(n_pages);

        for(uint i = 0; i < fsz/4; i++) {
            src[i] = 0;
            src[i] |= readByte(f_bit) << 24;
            src[i] |= readByte(f_bit) << 16;
            src[i] |= readByte(f_bit) << 8;
            src[i] |= readByte(f_bit);
        }

        cout << "Bitstream loaded, OP_ID: " << op_id << endl;

        f_bit.close();

        return true;
    }

    void closeBitStream() {
        fdev->freeHostMem((uint64_t*)src, n_pages);

        cout << "Bitstream removed, OP_ID: " << op_id << endl;
    }
};

#endif