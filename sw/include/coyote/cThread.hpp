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

#ifndef _COYOTE_CTHREAD_HPP_
#define _COYOTE_CTHREAD_HPP_

#include <thread>
#include <chrono>
#include <string>
#include <random>
#include <fstream>
#include <iostream>
#include <functional>
#include <unordered_map> 

#include <fcntl.h>
#include <netdb.h>
#include <syslog.h>
#include <unistd.h>

#include <sys/mman.h>
#include <sys/ioctl.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <linux/mman.h>

#include <boost/interprocess/sync/named_mutex.hpp>

#ifdef EN_AVX
#include <x86intrin.h>
#include <smmintrin.h>
#include <immintrin.h>
#endif

#include <coyote/cDefs.hpp>
#include <coyote/cOps.hpp>
#include <coyote/cGpu.hpp>

namespace coyote {

/**
 * @brief The cThread class is the core component of Coyote for interacting with vFPGAs
 *
 * This class provides methods for memory management, data transfer operations, and synchronization
 * with the vFPGA device. It also handles user interrupts and out-of-band set-up for RDMA operations.
 * It abstracts the interaction with the char vfpga_device in the driver, providing
 * a high-level interface for Coyote operations.
 */
class cThread {
protected: 
	/// vFPGA device file descriptor
	int32_t fd = { 0 };

	/// vFPGA virtual ID
	int32_t vfid = { -1 };
	
	/// Coyote thread ID
	int32_t ctid = { -1 }; 
	
	/// Host process ID
	pid_t hpid = { 0 };
	
	/// Shell configuration, as set by the user in CMake config
	fpgaCnfg fcnfg; 

	/// RDMA queue pair
    std::unique_ptr<ibvQp> qpair; 

	/// Number data transfer commands sent to the vFPGA
	uint32_t cmd_cnt = { 0 };

	/// User interrupt file descriptor
	int32_t efd = { -1 };

	/// Termination event file descriptor for stopping the user interrupt thread
	int32_t terminate_efd = { -1 };

	/// Dedicated thread for handling user interrupts
	std::thread event_thread;

	/// vFPGA config registers, if AVX is enabled, as implemented in cnfg_slave_avx.sv; used mainly for starting DMA commands
	#ifdef EN_AVX
	volatile __m256i *cnfg_reg_avx = { 0 };
	#endif

	/// vFPGA config registers, if AVX is disabled, as implemented in cnfg_slave.sv; used mainly for starting DMA commands
	volatile uint64_t *cnfg_reg = { 0 };
	
	/// User-defined control registers, which can be parsed using axi_ctrl in the vFPGA
	volatile uint64_t *ctrl_reg = { 0 };

	/// Pointer to writeback region, if enabled
	volatile uint32_t *wback = { 0 };

	/// A map of all the pages that have been allocated and mapped for this thread
	std::unordered_map<void*, CoyoteAlloc> mapped_pages;

	/** 
	 * Out-of-band connection file descriptor to a remote node
	 * This connection is primarily used for exchanging of QPs and syncing (barriers) between operations
	 */
	int connfd = { -1 };

	/**
	 * Out-of-band socket file descriptor for the cThread
	 * This socket is initially used to establish an out-of-band connection (connfd) to a remote node
	 * for exchanging QP information and for sending/receiving acknowledgments.
	 */
	int sockfd = { -1 };

	/// Set to true if there is an active out-of-band connection to a remote node for this cThread
	bool is_connected;

	/// Inter-process vFPGA lock, see lock() and unlock() functions for more details
	boost::interprocess::named_mutex vlock;

	/// Set to true if the vFPGA lock is acquired by this cThread; used to release the lock in the destructor
	bool lock_acquired = { false };
	
	/// Utility function, memory mapping all the vFPGA control registers and writeback regions
	void mmapFpga();

	/// Utility function, unmapping all the vFPGA control registers and writeback regions
	void munmapFpga();

	/**
	 * @brief Posts a DMA command to the vFPGA
	 *
	 * This function triggers a DMA command by writing the provided offsets to the appropriate control registers.
	 * @param offs_3 Destination address
	 * @param offs_2 Destination control signals (e.g., size, offset, stream etc.)
	 * @param offs_1 Source address
	 * @param offs_0 Source control signals (e.g., size, offset, stream etc.)

	 */
	void postCmd(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0);

	/**
	 * @brief Sends an ack to the connected remote node via the out-of-band channel
	 *
	 * @param ack Acknowledgment value to be sent
	 * @note Utility function, primarily used for syncing clients and servers between benchmarks and operations
	 */
	void sendAck(uint32_t ack);

	/**
	 * @brief Reads an ack from the connected remote node via the out-of-band channel
	 *
	 * @return Acknowledgment value received from the remote node
	 * @note Utility function, primarily used for syncing clients and servers between benchmarks and operations 
	 * This function works in conjunction with sendAck() to synchronize operations between the client and server.
	 */
    uint32_t readAck();

	public:
	/**
	 * @brief Writes an IP address to a config register so it can be used for ARP lookup
	 * @param ip_addr IP address to be looked up
	 */
    void doArpLookup(uint32_t ip_addr);
	
	/**
	 * @brief Writes the exchanged QP information to the vFPGA config registers
	 * @param ip_addr IP address to be looked up
	 */
	void writeQpContext(uint32_t port);
	

	/**
	 * @brief Default constructor for the cThread
	 * @param vfid Virtual FPGA ID
	 * @param hpid Host process ID
	 * @param device Device number, for systems with multiple vFPGAs
	 * @param uisr User interrupt (notifications) service routine, called when an interrupt from the vFPGA is received
	 */
	cThread(int32_t vfid, pid_t hpid, uint32_t device = 0, std::function<void(int)> uisr = nullptr);
	
	/**
	 * @brief Default destructor for the cThread
	 * 
	 * Cleans up the resources used by the cThread, including memory and file descriptors.
	 */
	~cThread();

	/**
	 * @brief Maps a buffer to the vFPGAs TLB
	 *
	 * @param vaddr Virtual address of the buffer
	 * @param len Length of the buffer, in bytes
	 */
	void userMap(void *vaddr, uint32_t len);

	/**
	 * @brief Unmaps a buffer from the the vFPGAs TLB
	 *
	 * @param vaddr Virtual address of the buffer
	 */
	void userUnmap(void *vaddr);

	/**
	 * @brief Allocates memory for this cThread and maps it into the vFPGA's TLB
	 *
	 * @param alloc CoyoteAlloc object containing the allocation parameters, including size, type (e.g., hugepage, GPU) etc.
	 * @return Pointer to the alocated memory
	 */
    void* getMem(CoyoteAlloc&& alloc);
	
	/**
	 * @brief Frees and unmaps previously allocated memory
	 *
	 * @param vaddr Virtual address of the buffer to be freed
	 */
	void freeMem(void* vaddr);

	/**
	 * @brief Sets a control register in the vFPGA at the specified offset
	 *
	 * @param val Register value to be set
	 * @param offs Offset of the control register to be set
	 */
	void setCSR(uint64_t val, uint32_t offs);

	/**
	 * @brief Reads from a register in the vFPGA at the specified offset
	 *
	 * @param offs Offset of the register to be read
	 * @return Value of the register at the specified offset
	 */
	uint64_t getCSR(uint32_t offs) const ;
	
	// The following functions are various implementation of the invoke function, which are used to trigger data movement operations
	// There are different implementation for the different types of operations (sync, local, rdma, tcp) to ensure type safety at compile-time
	
	/**
	 * @brief Invokes a Coyote sync or offload operation with the specified scatter-gather list (sg)
	 *
	 * @param oper Operation be invoked, in this case must be either CoyoteOper::LOCAL_SYNC or CoyoteOper::LOCAL_OFFLOAD
	 * @param sg Scatter-gather entry, specifying the memory address and length for the operation
	 *
	 * @note Syncs and off-loads are blocking (synchronous) by design
	 */
	void invoke(CoyoteOper oper, syncSg sg);

	/**
	 * @brief Invokes a one-sided local Coyote operation with the specified scatter-gather list (sg)
	 *
	 * @param oper Operation be invoked, in this case must be either CoyoteOper::LOCAL_READ or CoyoteOper::LOCAL_WRITE
	 * @param sg Scatter-gather entry, specifying the memory address, length and stream for the operation
	 * @param last Indicates whether this is the last operation in a sequence (default: true)
	 *
 	 * @note Local operations are non-blocking (asynchronous) by design, so users should poll for completion using checkCompleted()
	 * @note Whenever last is passed as true, the completion counter for the operation is incremented by 1 and an acknowledgement is sent on the hardware-side cq_* interface of the vFPGA with ack_t.host = 1; otherwise it is not
	 */
	void invoke(CoyoteOper oper, localSg sg, bool last = true);

	/**
	 * @brief Invokes a two-sided local Coyote operation with the specified scatter-gather list (sg)
	 *
	 * @param oper Operation be invoked, in this case must be CoyoteOper::LOCAL_TRANSFER
	 * @param src_sg Source scatter-gather entry, specifying the memory address, length and stream
	 * @param dst_sg Destination scatter-gather entry, specifying the memory address, length and stream
	 * @param last Indicates whether this is the last operation in a sequence (default: true)
	 *
 	 * @note Local operations are non-blocking (asynchronous) by design, so users should poll for completion using checkCompleted()
	 * @note Whenever last is passed as true, the completion counter for the operation is incremented by 1 and an acknowledgement is sent on the hardware-side cq_* interface of the vFPGA with ack_t.host = 1; otherwise it is not
	 */
	void invoke(CoyoteOper oper, localSg src_sg, localSg dst_sg, bool last = true);

	/**
	 * @brief Invokes an RDMA operation with the specified scatter-gather list (sg)
	 *
	 * @param oper Operation be invoked, in this case must be CoyoteOper::RDMA_WRITE or CoyoteOper::RDMA_READ
	 * @param sg Scatter-gather entry, specifying the RDMA operation parameters 
	 * @param last Indicates whether this is the last operation in a sequence (default: true)
	 *
 	 * @note Remote oeprations are non-blocking (asynchronous) by design, so users should poll for completion using checkCompleted()
	 * @note Whenever last is passed as true, the completion counter for the operation is incremented by 1 and an acknowledgement is sent on the hardware-side cq_* interface of the vFPGA with ack_t.host = 1; otherwise it is not
	 */
	void invoke(CoyoteOper oper, rdmaSg sg, bool last = true);

	/**
	 * @brief Invokes a TCP operation with the specified scatter-gather list (sg)
	 *
	 * @param oper Operation be invoked, in this case must be CoyoteOper::TCP_SEND
	 * @param sg Scatter-gather entry, specifying the TCP operation parameters 
	 * @param last Indicates whether this is the last operation in a sequence (default: true)
	 *
	 * @note TCP operations aren't fully stable in Coyote 0.2.1, to be updated in the future
	 */
	void invoke(CoyoteOper oper, tcpSg sg, bool last = true);

	/**
	 * @brief Returns the number of completed operations for a given Coyote operation type
	 *
	 * @param oper Operation to be queried 
	 * @return Cumulative number of completed operations for the specified operation type, since the last clearCompleted() call
	 */
	uint32_t checkCompleted(CoyoteOper oper) const;

	/**
	 * @brief Clears all the completion counters (for all operations)
	 */
	void clearCompleted();

	/** 
	 * @brief Synchronizes the connection between the client and server
	 * @param client If true, this cThread acts as a client; otherwise, it acts as a server
	 */
    void connSync(bool client);

	/**
	 * @brief Sets up the cThread for RDMA operations
	 *
	 * This function creates an out-of-band connection to the server,
	 * which is used to exchange the queue pair (QP) between the nodes.
	 * Additionally, it allocates a buffer for the RDMA operations
	 * and returns a pointer to the allocated buffer.
	 * 
	 * @param buffer_size Size of the buffer to be allocated for RDMA operations
	 * @param port Port number to be used for the out-of-band connection
	 * @param server_address Optional server address to connect to; if not provided, this cThread acts as the server
	 */
	void* initRDMA(uint32_t buffer_size, uint16_t port, const char* server_address = nullptr);
	
	/**
	 * @brief Opposite of initRDMA; releases the the out-of-band connection which was used to exchange QP
	 */
	void closeConn();

	/**
	 * @brief Locks the vFPGA for exclusive access by this cThread
	 *
	 * Locking ensures no other operation (even from other processes) is performed on the vFPGA concurrently.
	 * However, this may not always be desirable, as shown in Example 8 multi-threading.
	 * Generally, this method is typically not required and may mainly be needed when there are multiple
	 * software processes/threads targetting the same vFPGA simultaneously which can lead to undefined behaviour
	 */
	void lock();

	/**
	 * @brief Unlocks the vFPGA for exclusive access by this cThread
	 */
	void unlock();

	/// Getter: vFPGA ID (vfid)
	int32_t getVfid() const;

	/// Getter: Coyote thread ID (ctid)
	int32_t getCtid() const;

	/// Getter: Host process ID (hpid)
	pid_t getHpid() const;

	/// Getter: queue pair (QP)
	ibvQp* getQpair() const;
	
	/// Utility function, prints stats about this cThread including the number of commands invalidations etc.
	void printDebug() const;

private:
    // We use this "pointer to implementation" pattern here to be able to attach additional state to
    // the cThread in the simulation implementation of cThread. Before doing this, we had to use 
    // global variables which caused issues with order of destruction potentially destroying the 
    // simulation threads before they were joined. This is the minimally invasive way of doing this
    // to be able to have a second implementation of cThread without duplicating the cThread 
    // header.
    class AdditionalState;
    std::unique_ptr<AdditionalState> additional_state;
};

}

#endif // _COYOTE_CTHREAD_HPP_
