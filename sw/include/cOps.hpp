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

#ifndef _COYOTE_COPS_HPP_
#define _COYOTE_COPS_HPP_

#include "cDefs.hpp"

namespace coyote {

///////////////////////////////////////////////////
//              COYOTE OPERATIONS               //
//////////////////////////////////////////////////

/// @brief Various Coyote operations that allow users to move data from/to host memory, FPGA memory and remote nodes
enum class CoyoteOper {
    /// No operation
    NOOP = 0,

    /// Transfers data from CPU or FPGA memory to the vFPGA stream (axis_(host|card)_recv[i]), depending on sgEntry.local.src_stream
    LOCAL_READ = 1, 
    
    /// Transfers data from a vFPGA stream (axis_(host|card)_send[i]) to CPU or FPGA memory, depending on sgEntry.local.src_stream
    LOCAL_WRITE = 2,      
    
    /// LOCAL_READ and LOCAL_WRITE in parallel; dataflow is (CPU or FPGA) memory => vFPGA => (CPU or FPGA) memory
    LOCAL_TRANSFER = 3,   

    /// Migrates data from CPU memory to FPGA memory (HBM/DDR)
    LOCAL_OFFLOAD = 4,  

    /// Migrates data from FPGA memory (HBM/DDR) to CPU memory
    LOCAL_SYNC = 5,      
    
    /// One-side RDMA read operation
    REMOTE_RDMA_READ = 6, 
    
    /// One-sided RDMA write operation
    REMOTE_RDMA_WRITE = 7, 
    
    /// Two-sided RDMA send operation
    REMOTE_RDMA_SEND = 8, 
    
    /// TCP send operation; NOTE: Currently unsupported due to bugs; to be brought back in future releases of Coyote
    REMOTE_TCP_SEND = 9  
};

/*
 * Various helper function to check the type of operation
 */

inline constexpr bool isLocalRead(CoyoteOper oper) { return oper == CoyoteOper::LOCAL_READ || oper == CoyoteOper::LOCAL_TRANSFER; }

inline constexpr bool isLocalWrite(CoyoteOper oper) { return oper == CoyoteOper::LOCAL_WRITE || oper == CoyoteOper::LOCAL_TRANSFER; }

inline constexpr bool isLocalSync(CoyoteOper oper) { return oper == CoyoteOper::LOCAL_OFFLOAD || oper == CoyoteOper::LOCAL_SYNC; }

inline constexpr bool isRemoteRdma(CoyoteOper oper) { return oper == CoyoteOper::REMOTE_RDMA_WRITE || oper == CoyoteOper::REMOTE_RDMA_READ || oper == CoyoteOper::REMOTE_RDMA_SEND; }

inline constexpr bool isRemoteRead(CoyoteOper oper) { return oper == CoyoteOper::REMOTE_RDMA_READ; }

inline constexpr bool isRemoteWrite(CoyoteOper oper) { return oper == CoyoteOper::REMOTE_RDMA_WRITE; }

inline constexpr bool isRemoteSend(CoyoteOper oper) { return oper == CoyoteOper::REMOTE_RDMA_SEND || oper == CoyoteOper::REMOTE_TCP_SEND; }

inline constexpr bool isRemoteWriteOrSend(CoyoteOper oper) { return oper == CoyoteOper::REMOTE_RDMA_SEND || oper == CoyoteOper::REMOTE_RDMA_WRITE; }

inline constexpr bool isRemoteTcp(CoyoteOper oper) { return oper == CoyoteOper::REMOTE_TCP_SEND; }

///////////////////////////////////////////////////
//                 COYOTE MEMORY                //
//////////////////////////////////////////////////

/// @brief Different types of memory allocation that can be used in Coyote
enum class CoyoteAllocType {
    /// Regular pages (typically 4KB on Linux)
    REG = 0,

    /// Transparent huge pages (THP); obtained by allocating consecutve regular pages; 
    /// NOTE: Users should use HPF where possible; THP should be used if the system doesn't natively support huge pages
    THP = 1,

    /// Huge pages (HPF) (typically 2MB on Linux)
    HPF = 2,

    /// Partial reconfiguration memory, used for storing reconfiguration bitstreams
    PRM = 3,

    /// Memory on the GPU (for GPU-FPGA DMA)
    GPU = 4 
};

struct CoyoteAlloc {
	/// Type of allocated memory
	CoyoteAllocType alloc = { CoyoteAllocType::REG };

	/// Size of the allocated memory 
	uint32_t size = { 0 };

    /// Is this buffer used for remote operations?
    bool remote = { false };

    /// GPU device ID (when alloc == CoyoteAllocType::GPU)
    uint32_t gpu_dev_id = { 0 };

    /// File descriptor for the DMABuff used for GPU memory
    int32_t gpu_dmabuf_fd = { 0 };

    /// Pointer to the allocated memory; the struct keeps track of it so that it can be freed automatically after use
    void *mem = { nullptr };
};

///////////////////////////////////////////////////
//             COYOTE SG ENTRIES                //
//////////////////////////////////////////////////

/*
 * Various helper structs for scatter-gather (SG) entries, for various types of data movement
 * These describe a data movement, but depending on the operation, each will need different parameters
 */

/// @brief Scatter-gather entry for sync and offload operations
struct syncSg {
    /// Buffer address to be synced/offloaded
    void* addr = { nullptr };

    /// Size of the buffer in bytes
    uint64_t len = { 0 };
};

/// @brief Scatter-gather entry for local operations (LOCAL_READ, LOCAL_WRITE, LOCAL_TRANSFER)
struct localSg {
    /// Buffer address
    void* addr = { nullptr };

    /// Buffer length in bytes
    uint32_t len = { 0 };

    /// Buffer stream: HOST or CARD
    uint32_t stream = { STRM_HOST };

    /// Target AXI4 destination stream in the vFPGA; a value of i will use the to axis_(host|card)_(recv|send)[i] in the vFPGA
    uint32_t dest = { 0 };
};

/** 
 * @brief Scatter-gather entry for RDMA operations (REMOTE_READ, REMOTE_WRITE)
 * NOTE: No field for source/dest address, since these are defined when exchanging queue pair information
 * And, each cThread holds exactly one queue pair, so the source and destination addresses are always the same
 */
struct rdmaSg {
    /// Offset from the local buffer address; in case the buffer to be sent doesn't need to start from the exchanged virtual address
    uint64_t local_offs = { 0 };

    /// Source buffer stream: HOST or CARD
    uint32_t local_stream = { STRM_HOST };

    /// Target AXI4 source stream in the vFPGA; a value of i will write pull data for the RDMA operation from axis_(host|card)_recv[i] in the vFPGA
    uint32_t local_dest = { 0 };

    // Offset for the remote buffer to which the data is sent; in case the buffer to be sent doesn't need to start from the exchanged virtual address
    uint64_t remote_offs = { 0 };
    
    /// Target AXI4 destination stream; a value of i will write write data to axis_(host|card)_send[i] in the remote vFPGA
    uint32_t remote_dest = { 0 };

    /// Lenght of the RDMA transfer, in bytes
    uint32_t len = { 0 };
};

/// @brief Scatter-gather entry for TCP operations (REMOTE_TCP_SEND)
struct tcpSg {
    uint32_t stream = { STRM_TCP };
    uint32_t dest = { 0 };
    uint32_t len = { 0 };
};


}

#endif // _COYOTE_COPS_HPP_