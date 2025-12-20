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

#ifndef _COYOTE_CDEFS_HPP_
#define _COYOTE_CDEFS_HPP_

#include <chrono> 
#include <cstring> 
#include <cstdint>
#include <iomanip>
#include <netdb.h>
#include <iostream>  
#include <sys/ioctl.h> 

using namespace std::chrono_literals;

namespace coyote {

///////////////////////////////////////////////////
//                  IOCTL CALLS                 //
//////////////////////////////////////////////////

// Register Coyote thread for a vFPGA
#define IOCTL_REGISTER_CTID                 _IOW('F', 1, unsigned long)

// Unregister a Coyote thread for a vFPGA
#define IOCTL_UNREGISTER_CTID               _IOW('F', 2, unsigned long)

// Register an event file descriptor (eventfd) to handle user interrupts (notifications)
#define IOCTL_REGISTER_EVENTFD              _IOW('F', 3, unsigned long)

// Unregister an event file descriptor (eventfd) which handles user interrupts (notifications)
#define IOCTL_UNREGISTER_EVENTFD            _IOW('F', 4, unsigned long)

// Map user memory into the TLBs
#define IOCTL_MAP_USER_MEM                  _IOW('F', 5, unsigned long)

// Unmap previously mapped memory from the TLBs
#define IOCTL_UNMAP_USER_MEM                _IOW('F', 6, unsigned long)

// Map a DMA buffer into the FPGA's address space (required for GPU DMA)
#define IOCTL_MAP_DMABUF                  	_IOW('F', 7, unsigned long)

// Unmap a DMA buffer from the FPGA's address space (required for GPU DMA)
#define IOCTL_UNMAP_DMABUF                	_IOW('F', 8, unsigned long)

// Offload data to the FPGA's memory (HBM/DDR)
#define IOCTL_OFFLOAD_REQ                 	_IOW('F', 9, unsigned long)

// Move data from FPGA's memory (HBM/DDR) to the host
#define IOCTL_SYNC_REQ                  	_IOW('F', 10, unsigned long)

// Set the FPGA's IP address
#define IOCTL_SET_IP_ADDRESS                _IOW('F', 11, unsigned long)

// Set the FPGA's MAC address
#define IOCTL_SET_MAC_ADDRESS               _IOW('F', 12, unsigned long)

// Get the FPGA's IP address
#define IOCTL_GET_IP_ADDRESS                _IOR('F', 13, unsigned long)

// Get the FPGA's MAC address
#define IOCTL_GET_MAC_ADDRESS               _IOR('F', 14, unsigned long)

// Read the shell configuration of the FPGA
#define IOCTL_READ_SHELL_CONFIG             _IOR('F', 15, unsigned long)

// Get statistics for XDMA (PCIe DMA engine)
#define IOCTL_XDMA_STATS                    _IOR('F', 16, unsigned long)

// Get network statistics for the FPGA
#define IOCTL_NET_STATS                     _IOR('F', 17, unsigned long)

// Mark a notification as processed in the FPGA driver
#define IOCTL_SET_NOTIFICATION_PROCESSED    _IOR('F', 18, unsigned long)
#define IOCTL_GET_NOTIFICATION_VALUE        _IOR('F', 19, unsigned long)

// Allocate memory for partial reconfiguration
#define IOCTL_ALLOC_HOST_RECONFIG_MEM       _IOW('P', 1, unsigned long)

// Free memory allocated used for partial reconfiguration
#define IOCTL_FREE_HOST_RECONFIG_MEM        _IOW('P', 2, unsigned long)

// Trigger reconfiguration of a vFPGA
#define IOCTL_RECONFIGURE_APP               _IOW('P', 3, unsigned long)

// Trigger reconfiguration of the entire shell
#define IOCTL_RECONFIGURE_SHELL             _IOW('P', 4, unsigned long)

// Retrieve the PR config (set before hardware synthesis)
#define IOCTL_PR_CNFG                       _IOR('P', 5, unsigned long)

// Retrieve static statistics for the XDMA core
#define IOCTL_STATIC_XDMA_STATS             _IOR('P', 6, unsigned long)

#define BUFF_NEEDS_EXP_SYNC_RET_CODE 99

///////////////////////////////////////////////////
//              CONTROL REGISTERS               //
//////////////////////////////////////////////////

/// @brief AVX config registers, for more details see the HW implementation in cnfg_slave_avx.sv and struct vfpga_cnfg_regs
enum class CnfgAvxRegs : uint32_t {
    CTRL_REG = 0,
    ISR_REG = 1,
    STAT_REG_0 = 2,
    STAT_REG_1 = 3,
    WBACK_REG = 4,
    OFFLOAD_CTRL_REG = 5,
    OFFLOAD_STAT_REG = 6,
    SYNC_CTRL_REG = 7,
    SYNC_STAT_REG = 8,
    NET_ARP_REG = 9,
    RDMA_CTX_REG = 10,
    RDMA_CONN_REG = 11,
    TCP_OPEN_PORT_REG = 12,
    TCP_OPEN_PORT_STAT_REG = 13,
    TCP_OPEN_CONN_REG = 14,
    TCP_OPEN_CONN_STAT_REG = 15,
    STAT_DMA_REG = 64
};

/// @brief Non-AVX config registers; used for legacy systems and Enzian 
enum class CnfgLegRegs : uint32_t {
    CTRL_REG = 0,
    VADDR_RD_REG = 1,
    CTRL_REG_2 = 2,
    VADDR_WR_REG = 3,
    ISR_REG = 4,
    ISR_PID_MISS_REG = 5,
    ISR_VADDR_MISS_REG = 6,
    ISR_LEN_MISS_REG = 7,
    STAT_REG_0 = 8,
    STAT_REG_1 = 9,
    STAT_REG_2 = 10,
    STAT_REG_3 = 11,
    STAT_REG_4 = 12,
    STAT_REG_5 = 13,
    STAT_REG_6 = 14, 
    STAT_REG_7 = 15, 
    WBACK_REG_0 = 16,
    WBACK_REG_1 = 17,
    WBACK_REG_2 = 18,
    WBACK_REG_3 = 19,
    OFFLOAD_CTRL_REG = 20,
    OFFLOAD_HOST_OFFS_REG = 21,
    OFFLOAD_CARD_OFFS_REG = 22,
    OFFLOAD_STAT_REG = 24,
    SYNC_CTRL_REG = 28,
    SYNC_HOST_OFFS_REG = 29,
    SYNC_CARD_OFFS_REG = 30,
    SYNC_STAT_REG = 32,
    NET_ARP_REG = 36,
    RDMA_CTX_REG_0 = 40,
    RDMA_CTX_REG_1 = 41,
    RDMA_CTX_REG_2 = 42,
    RDMA_CONN_REG_0 = 44,
    RDMA_CONN_REG_1 = 45,
    RDMA_CONN_REG_2 = 46,
    TCP_OPEN_PORT_REG = 48,
    TCP_OPEN_PORT_STAT_REG = 52,
    TCP_OPEN_CONN_REG = 56,
    TCP_OPEN_CONN_STAT_REG = 60,
    STAT_DMA_REG = 64,
    STAT_RDMA_REG = 128,
};

///////////////////////////////////////////////////
//                  CONSTANTS                   //
//////////////////////////////////////////////////

/*
 * The following are constants used in the Coyote SOFTWARE.
 * Most of these are self-explanatory and their purpose can be derived from their name and usage
 * Therefore, there are few comments, but mostly for constants that are not obvious
 */

// Masks, shifts & offsets for ensuring the correct value is written to/read from memory mapped registers 
#define CTRL_OPCODE_OFFS                    (0)
#define CTRL_STRM_OFFS                      (8)
#define CTRL_PID_OFFS                       (10)
#define CTRL_DEST_OFFS                      (16)
#define CTRL_LAST                           (1UL << 20)
#define CTRL_START                          (1UL << 21)
#define CTRL_CLR_STAT                       (1UL << 22)
#define CTRL_LEN_OFFS                       (32)

#define CTRL_OPCODE_MASK                    (0x1f)
#define CTRL_STRM_MASK                      (0x3)
#define CTRL_PID_MASK                       (0x3f)
#define CTRL_DEST_MASK                      (0xf)
#define CTRL_VFID_MASK                      (0xf)
#define CTRL_LEN_MASK                       (0xffffffff)

#define PID_BITS                            (6)
#define PID_MASK                            (0x3f)
#define N_REG_MASK                          (0xf)

#define REMOTE_OFFS_OPS                     (6)
#define QP_CONTEXT_QPN_OFFS                 (0)
#define QP_CONTEXT_RKEY_OFFS                (32)
#define QP_CONTEXT_LPSN_OFFS                (0)
#define QP_CONTEXT_RPSN_OFFS                (24)
#define QP_CONTEXT_VADDR_OFFS               (0)

#define CONN_CONTEXT_LQPN_OFFS              (0)
#define CONN_CONTEXT_RQPN_OFFS              (16)
#define CONN_CONTEXT_PORT_OFFS              (40)

// Numbers etc.
#define NaN std::numeric_limits<double>::quiet_NaN();

// DMA and command constants
constexpr int const CMD_FIFO_DEPTH = 32;
constexpr int const CMD_FIFO_THR = 10;
constexpr unsigned long const MAX_TRANSFER_SIZE = 128 * 1024 * 1024;

// Sleep time in nanoseconds for buszy wait loops; used while waiting for hardware to complete
constexpr long const SLEEP_TIME = 100L;

// Maximum number of user interrupts to process simultaneously
constexpr int const MAX_EVENTS = 1;

// Memory and page configuration --- TODO: Think about making these configurable at run-time based on the shell TLB config
constexpr unsigned long long const PAGE_SIZE = (4ULL * 1024ULL);
constexpr unsigned long long const HUGE_PAGE_SIZE = (2ULL * 1024ULL * 1024ULL);
constexpr unsigned long const PAGE_SHIFT = 12UL;
constexpr unsigned long const HUGE_PAGE_SHIFT = 21UL;

// Maximum number of Coyote threads per vFPGA
constexpr int const N_CTID_MAX = 64;

/**
 * Size and offset of memory mapped regions (vFPGA control regions):
 * vFPGA CSRs; accessed through getCSR and setCSR
 * vFPGA (AVX) config region; implemented in cnfg_slave(_avx).sv
 * Writeback region for checking completion counters 
 */
constexpr unsigned long const CTRL_REGION_SIZE = 64 * 1024;
constexpr unsigned long const CNFG_REGION_SIZE = 64 * 1024;
constexpr unsigned long const CNFG_AVX_REGION_SIZE = 256 * 1024;
constexpr unsigned long const WBACK_REGION_SIZE = 4 * N_CTID_MAX * sizeof(uint32_t);

constexpr unsigned long const MMAP_WB = 0x0 << PAGE_SHIFT;
constexpr unsigned long const MMAP_CNFG = 0x1 << PAGE_SHIFT;
constexpr unsigned long const MMAP_CNFG_AVX = 0x2 << PAGE_SHIFT;
constexpr unsigned long const MMAP_CTRL = 0x3 << PAGE_SHIFT;
constexpr unsigned long const MMAP_RECONFIG = 0x100 << PAGE_SHIFT;

// Writeback region constants; there are deidcated writebacks for reads, writes, remote reads and remote writes
constexpr unsigned long const N_WBACKS = 4;
constexpr unsigned long const RD_WBACK = 0;
constexpr unsigned long const WR_WBACK = 1;
constexpr unsigned long const RD_RDMA_WBACK = 2;
constexpr unsigned long const WR_RDMA_WBACK = 3;

// Maximum number of user arguments for IOCTL calls passed from the user space to the driver
constexpr auto const MAX_USER_ARGS = 32;

// Data source/destination stream in the vFPGA; e.g., axis_host_(recv|send). axis_card_(recv|send)
constexpr unsigned long const STRM_CARD = 0;
constexpr unsigned long const STRM_HOST = 1;
constexpr unsigned long const STRM_RDMA = 2;
constexpr unsigned long const STRM_TCP = 3;

// Default port for remote connections
constexpr unsigned long const DEF_PORT = 18488;

// Threading constants
// constexpr auto const CMPL_TIMEOUT = 5000ms;
// static constexpr struct timespec PAUSE {.tv_sec = 0, .tv_nsec = 1000};

// Background daemons
constexpr unsigned long const RECV_BUFF_SIZE = 1024;
constexpr unsigned long const DAEMON_CLEAN_CONNS_SLEEP = 500; // us
constexpr unsigned long const DAEMON_ACCEPT_CONN_SLEEP = 50; // us
constexpr unsigned long const DAEMON_PROCESS_REQUESTS_SLEEP = 10; // us
constexpr unsigned long const MAX_NUM_CLIENTS = 64;
constexpr unsigned long const DEF_OP_CLOSE_CONN = 0;
constexpr unsigned long const DEF_OP_SUBMIT_TASK = 1;
constexpr unsigned long const SLEEP_INTERVAL_CLIENT_CONN_MANAGER = 500; // us
static constexpr struct timeval SERVER_RECV_TIMEOUT = {.tv_sec = 0, .tv_usec = 5000}; 
static constexpr struct timeval CLIENT_RECV_TIMEOUT = {.tv_sec = 0, .tv_usec = 500}; 

/// @brief RDMA Queue (QP) --- keeps all the necessary information of a single node in RDMA connections
struct ibvQ {
    /// Node IP address
    uint32_t ip_addr;

    /// Queue Pair Number 
    uint32_t qpn; 

    /// Packet Serial Number
    uint32_t psn;
    
    /// Memory rkey
    uint32_t rkey;

    /// Buffer virtual address
    void *vaddr;

    /// Buffer size
    uint32_t size;

    /**
     * @brief Global ID for identifying a network interface in RDMA networks (InfiniBand or RoCE).
     * In Coyote, it's mostly a concatination of repeated IP-addresses
     */
    char gid[33] = { 0 };

    /// Converter GID to integer 
    uint32_t gidToUint(int idx) {
        if(idx > 24) {
            std::cerr << "Invalid index for gidToUint" << std::endl;
            return 0;
        }
        char tmp[9];
        memset(tmp, 0, 9);
        uint32_t v32 = 0;
        memcpy(tmp, gid+idx, 8);
        sscanf(tmp, "%x", &v32);
        return ntohl(v32);
    }

    /// Converter integer to GID 
    void uintToGid(int idx, uint32_t ip_addr) {
        std::ostringstream gidStream;
        gidStream << std::setfill('0') << std::setw(8) << std::hex << ip_addr;
        memcpy(gid+idx, gidStream.str().c_str(), 8);
    }

    /// Debug print
    void print(const char *name) {
        printf(
            "%s: QPN 0x%06x, PSN 0x%06x, VADDR %016lx, SIZE %08x, IP 0x%08x\n",
            name, qpn, psn, (uint64_t)vaddr, size, ip_addr
        );
    }
};

/// @brief RDMA Queue Pair (QP) --- a combination of a local and a remote ibvQ that uniquely identify an RDMA connection
struct ibvQp {
public:
    ibvQ local;
    ibvQ remote;

    ibvQp() {}
};

/**
 * @brief Shell configuration, as set in CMake for hardware synthesis
 * NOTE: The description of each variable can be found in cmake/FindCoyoteHW.cmake
 */
 struct fpgaCnfg {
    /// AVX enabled
    bool en_avx = { false };

    /// Writeback enabled
    bool en_wb = { false };

    /// Streams from host memory enabled
    bool en_strm = { false };

    /// Streams from FPGA memory (HBM/DDR) enabled
    bool en_mem = { false };

    /// Partial reconfiguration (2nd level, app) enabled
    bool en_pr = { false };

    /// RDMA enabled
    bool en_rdma = { false };

    /// TCP enabled
    bool en_tcp = { false };

    /// Set to true if either RDMA or TCP is enabled
    bool en_net = { false };
    
    /// Number of XDMA channels
    int32_t n_xdma_chan = { 0 };

    /// Number of vFPGAs
    int32_t n_fpga_reg = { 0 };

    void parseCnfg(uint64_t cnfg) {
        en_avx = (cnfg >> 0) & 0x1;
        en_wb = (cnfg >> 1) & 0x1;
        en_strm = (cnfg >> 2) & 0x1;
        en_mem = (cnfg >> 3) & 0x1;
        en_pr = (cnfg >> 4) & 0x1;
        en_rdma = (cnfg >> 16) & 0x1;
        en_tcp = (cnfg >> 17) & 0x1;
        n_xdma_chan = (cnfg >> 32) & 0xff;
        n_fpga_reg = (cnfg >> 48) & 0xff;
        en_net = en_rdma || en_tcp;
    }
};

///////////////////////////////////////////////////
//                  DEBUG MACROS                //
//////////////////////////////////////////////////

// Debug prints for local operations
#ifdef VERBOSE_DEBUG_1
#define DBG1(msg) do { std::cout << msg << std::endl; } while ( false )
#else
#define DBG1(msg) do { } while ( false )
#endif

// Debug prints for reconfigurations
#ifdef VERBOSE_DEBUG_2
#define DBG2(msg) do { std::cout << msg << std::endl; } while ( false )
#else
#define DBG2(msg) do { } while ( false )
#endif

// Debug prints for remote operations
#ifdef VERBOSE_DEBUG_3
#define DBG3(msg) do { std::cout << msg << std::endl; } while ( false )
#else
#define DBG3(msg) do { } while ( false )
#endif

// String formatted as title, in red and bold
#define HEADER(msg) std::cout << "\n-- \033[31m\e[1m" << msg << "\033[0m\e[0m" << std::endl << std::string(47, '-') << std::endl;

///////////////////////////////////////////////////
//                UTIL MACROS                   //
//////////////////////////////////////////////////
#define HIGH_32(data)                       ((data >> 16) >> 16)
#define LOW_32(data)                        (data & 0xffffffffUL)

#if __BYTE_ORDER == __LITTLE_ENDIAN
    #define ltohl(x)                         (x)
    #define ltohs(x)                         (x)
    #define htoll(x)                         (x)
    #define htols(x)                         (x)
#elif __BYTE_ORDER == __BIG_ENDIAN
    #define ltohl(x)                          __bswap_32(x)
    #define ltohs(x)                          __bswap_16(x)
    #define htoll(x)                          __bswap_32(x)
    #define htols(x)                          __bswap_16(x)
#endif

}

#endif // _COYOTE_CDEFS_HPP_