#pragma once

#include <cstdint>
#include <cstdio>
#include <string>
#include <mutex>
#include <atomic>
#include <tuple>
#include <chrono>
#include <netdb.h>
#include <iostream>
#include <sstream>
#include <fstream>
#include <cstring>
#include <iomanip>

using namespace std::chrono_literals;

/* Globals */
namespace fpga {

// ======-------------------------------------------------------------------------------
// Macros
// ======-------------------------------------------------------------------------------
//#define VERBOSE_DEBUG_1 // Handle
//#define VERBOSE_DEBUG_2 // Reconfig
//#define VERBOSE_DEBUG_3 // Perf

#ifdef VERBOSE_DEBUG_3
#define VERBOSE_DEBUG_2
#endif

#ifdef VERBOSE_DEBUG_2
#define VERBOSE_DEBUG_1
#endif

#ifdef VERBOSE_DEBUG_1
#define DBG1(msg) do { std::cout << msg << std::endl; } while ( false )
#else
#define DBG1(msg) do { } while ( false )
#endif

#ifdef VERBOSE_DEBUG_2
#define DBG2(msg) do { std::cout << msg << std::endl; } while ( false )
#else
#define DBG2(msg) do { } while ( false )
#endif

#ifdef VERBOSE_DEBUG_3
#define DBG3(msg) do { std::cout << msg << std::endl; } while ( false )
#else
#define DBG3(msg) do { } while ( false )
#endif

#define ERR(msg) do { std::cout << "ERROR: " << msg << std::endl; } while ( false )

#define PR_HEADER(msg) std::cout << "\n-- \033[31m\e[1m" << msg << "\033[0m\e[0m" << std::endl << std::string(47, '-') << std::endl;

/* High low */
#define HIGH_32(data)                       ((data >> 16) >> 16)
#define LOW_32(data)                        (data & 0xffffffffUL)
#define HIGH_16(data)                       (data >> 16)
#define LOW_16(data)                        (data & 0xffff)

/* IOCTL */
#define IOCTL_REGISTER_PID                  _IOW('F', 1, unsigned long)
#define IOCTL_UNREGISTER_PID                _IOW('F', 2, unsigned long)
#define IOCTL_REGISTER_EVENTFD              _IOW('F', 3, unsigned long)
#define IOCTL_UNREGISTER_EVENTFD            _IOW('F', 4, unsigned long)
#define IOCTL_MAP_USER                  	_IOW('F', 5, unsigned long)
#define IOCTL_UNMAP_USER                	_IOW('F', 6, unsigned long)
#define IOCTL_MAP_DMABUF                  	_IOW('F', 7, unsigned long)
#define IOCTL_UNMAP_DMABUF                	_IOW('F', 8, unsigned long)
#define IOCTL_OFFLOAD_REQ                 	_IOW('F', 9, unsigned long)
#define IOCTL_SYNC_REQ                  	_IOW('F', 10, unsigned long)

#define IOCTL_SET_IP_ADDRESS                _IOW('F', 11, unsigned long)
#define IOCTL_SET_MAC_ADDRESS               _IOW('F', 12, unsigned long)
#define IOCTL_GET_IP_ADDRESS                _IOR('F', 13, unsigned long)
#define IOCTL_GET_MAC_ADDRESS               _IOR('F', 14, unsigned long)

#define IOCTL_READ_CNFG                     _IOR('F', 15, unsigned long)
#define IOCTL_XDMA_STATS                    _IOR('F', 16, unsigned long)
#define IOCTL_NET_STATS                     _IOR('F', 17, unsigned long)

#define IOCTL_ALLOC_PR_MEM         	        _IOW('P', 1, unsigned long)
#define IOCTL_FREE_PR_MEM          	        _IOW('P', 2, unsigned long)
#define IOCTL_RECONFIGURE_APP               _IOW('P', 3, unsigned long)
#define IOCTL_RECONFIGURE_SHELL             _IOW('P', 4, unsigned long)
#define IOCTL_PR_CNFG                       _IOR('P', 5, unsigned long)
#define IOCTL_STATIC_XDMA_STATS             _IOR('P', 6, unsigned long)

/* Control reg */
#define CTRL_OPCODE_OFFS                    (0)
#define CTRL_MODE                           (1UL << 5)
#define CTRL_RDMA                           (1UL << 6)
#define CTRL_REMOTE                         (1UL << 7)
#define CTRL_STRM_OFFS                      (8)
#define CTRL_PID_OFFS                       (10)
#define CTRL_DEST_OFFS                      (16)
#define CTRL_LAST                           (1UL << 20)
#define CTRL_START                          (1UL << 21)
#define CTRL_CLR_STAT                       (1UL << 22)
#define CTRL_LEN_OFFS                       (32)

#define CTRL_OPCODE_MASK                    0x1f
#define CTRL_STRM_MASK                      0x3
#define CTRL_DEST_MASK                      0xf
#define CTRL_PID_MASK                       0x3f
#define CTRL_VFID_MASK                      0xf
#define CTRL_LEN_MASK                       0xffffffff

#define PID_BITS                            6
#define VFID_BITS                           4

/* RDMA post */
#define RDMA_POST_OFFS                      0x0
#define RDMA_OPCODE_OFFS                    1
#define RDMA_OPCODE_MASK                    0x1f
#define RDMA_PID_OFFS                       6
#define RDMA_PID_MASK                       0x3f
#define RDMA_VFID_OFFS                      12
#define RDMA_VFID_MASK                      0xf
#define RDMA_HOST_OFFS                      16
#define RDMA_MODE_OFFS                      17
#define RDMA_LAST_OFFS                      18
#define RDMA_CLR_OFFS                       19

/* ltoh: little to host */
/* htol: little to host */
#if __BYTE_ORDER == __LITTLE_ENDIAN
#  define ltohl(x)                          (x)
#  define ltohs(x)                          (x)
#  define htoll(x)                          (x)
#  define htols(x)                          (x)
#elif __BYTE_ORDER == __BIG_ENDIAN
#  define ltohl(x)                          __bswap_32(x)
#  define ltohs(x)                          __bswap_16(x)
#  define htoll(x)                          __bswap_32(x)
#  define htols(x)                          __bswap_16(x)
#endif


// ======-------------------------------------------------------------------------------
// Enum
// ======-------------------------------------------------------------------------------

enum class CoyoteOperNew {
    NOOP = 0,
    LOCAL_READ_FROM_HOST = 1,
    LOCAL_READ_FROM_CARD = 2,
    LOCAL_WRITE_TO_HOST = 3,
    LOCAL_WRITE_TO_CARD = 4,
    LOCAL_MOVE_HOST_TO_CARD = 5,
    LOCAL_MOVE_HOST_TO_HOST = 6,
    LOCAL_MOVE_CARD_TO_HOST = 7,
    LOCAL_MOVE_CARD_TO_CARD = 8,
    LOCAL_OFFLOAD = 9,
    LOCAL_SYNC = 10,
    REMOTE_RDMA_READ_TO_HOST = 11,
    REMOTE_RDMA_READ_TO_CARD = 11,
    REMOTE_RDMA_WRITE_FROM_HOST = 11,
    REMOTE_RDMA_WRITE_FROM_CARD = 11,
    REMOTE_RDMA_SEND_FROM_HOST = 11,
    REMOTE_RDMA_SEND_FROM_CARD = 11,
    REMOTE_TCP_SEND_FROM_HOST = 11,
    REMOTE_TCP_SEND_FROM_CARD = 11
};


enum class CoyoteOper {
    NOOP = 0,
    LOCAL_READ = 1,        // Transfer data from CPU or FPGA memory to FPGA stream (depending on sgEntry.local.src_stream)
    LOCAL_WRITE = 2,       // Transfer data from FPGA stream to CPU or FPGA memory (depending on sgEntry.local.dst_stream)
    LOCAL_TRANSFER = 3,    // LOCAL_READ and LOCAL_WRITE in parallel
    LOCAL_OFFLOAD = 4,     // Transfer data from CPU memory to FPGA memory
    LOCAL_SYNC = 5,        // Transfer data from FPGA memory to CPU memory
    REMOTE_RDMA_READ = 6,
    REMOTE_RDMA_WRITE = 7,
    REMOTE_RDMA_SEND = 8,
    REMOTE_TCP_SEND = 9
};

enum class CoyoteAlloc {
    REG = 0,
    THP = 1,
    HPF = 2,
    PRM = 3,
    GPU = 4
};

/* AVX regs */
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

/* Legacy regs */
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

/**
 * Supported ops
 */
enum ibvOpcode { 
    IBV_WR_RDMA_READ, 
    IBV_WR_RDMA_WRITE, 
    IBV_WR_SEND
};

// ======-------------------------------------------------------------------------------
// Consts
// ======-------------------------------------------------------------------------------

/* Sleep */
constexpr auto const sleepTime = 100L;

/* Events */
constexpr auto const maxEvents = 1;

/* Sleep */
constexpr auto const pollSleepNs = 100;
constexpr auto const pageSize = (4ULL * 1024ULL);
constexpr auto const hugePageSize = (2ULL * 1024ULL * 1024ULL);
constexpr auto const pageShift = 12UL;
constexpr auto const hugePageShift = 21UL;

/* Internal */
constexpr auto const useHugePages = true;
constexpr auto const clocNs = 4;

/* Remote offs ops */
constexpr auto const remoteOffsOps = 6;

/* Bits */
constexpr auto const pidBits = 6;
constexpr auto const pidMask = 0x3f;
constexpr auto const nRegBits = 4;
constexpr auto const nRegMask = 0xf;

/* FIFOs */
constexpr auto const cmdFifoDepth = 32;
constexpr auto const cmdFifoThr = 10;

/* Writeback size */
constexpr auto const nCtidMax = 64;
constexpr auto const nCpidBits = 6;

/* Regions */
constexpr auto const ctrlRegionSize = 64 * 1024;
constexpr auto const cnfgRegionSize = 64 * 1024;
constexpr auto const cnfgAvxRegionSize = 256 * 1024;
constexpr auto const wbackRegionSize = 4 * nCtidMax * sizeof(uint32_t);

/* MMAP */
constexpr auto const mmapCtrl = 0x0 << pageShift;
constexpr auto const mmapCnfg = 0x1 << pageShift;
constexpr auto const mmapCnfgAvx = 0x2 << pageShift;
constexpr auto const mmapWb = 0x3 << pageShift;
constexpr auto const mmapPr = 0x100 << pageShift;

/* Threading */
static constexpr struct timespec PAUSE {.tv_sec = 0, .tv_nsec = 1000};
static constexpr struct timespec MSPAUSE {.tv_sec = 0, .tv_nsec = 1000000};
constexpr auto const cmplTimeout = 5000ms;
constexpr auto const maxCqueueSize = 512;

/* AXI */
constexpr auto const axiDataWidth = 64;

/* Max copy */
constexpr auto const maxUserCopyVals = 16;

/* Wbacks */
constexpr auto const nWbacks = 4;
constexpr auto const rdWback = 0;
constexpr auto const wrWback = 1;
constexpr auto const rdRdmaWback = 2;
constexpr auto const wrRdmaWback = 3;

/* Streams */
constexpr auto const strmCard = 0;
constexpr auto const strmHost = 1;
constexpr auto const strmRdma = 2;
constexpr auto const strmTcp = 3;

/* Net regs */
constexpr auto const nNetRegs = 9;

/* QSFP regs offset */
constexpr auto const qsfpOffsAvx = 8;
constexpr auto const qsfpOffsLeg = 16;

constexpr auto const qpContextQpnOffs = 0;
constexpr auto const qpContextRkeyOffs = 32;
constexpr auto const qpContextLpsnOffs = 0;
constexpr auto const qpContextRpsnOffs = 24;
constexpr auto const qpContextVaddrOffs = 0;

constexpr auto const connContextLqpnOffs = 0;
constexpr auto const connContextRqpnOffs = 16;
constexpr auto const connContextPortOffs = 40;

constexpr auto const rdmaContextLvaddrLowOffs = 0;
constexpr auto const rdmaContextLvaddrHighOffs = 0;
constexpr auto const rdmaContextRvaddrLowOffs = 48;
constexpr auto const rdmaContextRvaddrHighOffs = 48;
constexpr auto const rdmaContextLenOffs = 32;

/* Immed prep */
constexpr auto const ibvImmedHigh = 1;
constexpr auto const ibvImmedMid = 0;

constexpr auto const immedLowParams = 3;
constexpr auto const immedMedParams = 7;
constexpr auto const immedHighParams = 8;

/* ARP sleep */
constexpr auto const arpSleepTime = 100;

/* Default port */
constexpr auto const defPort = 18488;

/* Agents */
constexpr auto const agentMaxNameSize = 64;

/* Operations */
constexpr auto isLocal(CoyoteOper oper) {
    return oper == CoyoteOper::LOCAL_READ || oper == CoyoteOper::LOCAL_TRANSFER || oper == CoyoteOper::LOCAL_WRITE ||
        oper == CoyoteOper::LOCAL_OFFLOAD || oper == CoyoteOper::LOCAL_SYNC;
}

constexpr auto isRemote(CoyoteOper oper) {
    return oper == CoyoteOper::REMOTE_RDMA_WRITE || oper == CoyoteOper::REMOTE_RDMA_READ || oper == CoyoteOper::REMOTE_RDMA_SEND ||
        oper == CoyoteOper::REMOTE_TCP_SEND;
}

constexpr auto isLocalRead(CoyoteOper oper) {
    return oper == CoyoteOper::LOCAL_READ || oper == CoyoteOper::LOCAL_TRANSFER;
}

constexpr auto isLocalWrite(CoyoteOper oper) {
    return oper == CoyoteOper::LOCAL_WRITE || oper == CoyoteOper::LOCAL_TRANSFER;
}

constexpr auto isLocalSync(CoyoteOper oper) {
    return oper == CoyoteOper::LOCAL_OFFLOAD || oper == CoyoteOper::LOCAL_SYNC;
}

constexpr auto isRemoteRdma(CoyoteOper oper) {
    return oper == CoyoteOper::REMOTE_RDMA_WRITE || oper == CoyoteOper::REMOTE_RDMA_READ || oper == CoyoteOper::REMOTE_RDMA_SEND;
}

constexpr auto isRemoteRead(CoyoteOper oper) {
    return oper == CoyoteOper::REMOTE_RDMA_READ;
}

constexpr auto isRemoteWrite(CoyoteOper oper) {
    return oper == CoyoteOper::REMOTE_RDMA_WRITE;
}

constexpr auto isRemoteSend(CoyoteOper oper) {
    return oper == CoyoteOper::REMOTE_RDMA_SEND || oper == CoyoteOper::REMOTE_TCP_SEND;
}

constexpr auto isRemoteWriteOrSend(CoyoteOper oper) {
    return oper == CoyoteOper::REMOTE_RDMA_SEND || oper == CoyoteOper::REMOTE_RDMA_WRITE;
}

constexpr auto isRemoteTcp(CoyoteOper oper) {
    return oper == CoyoteOper::REMOTE_TCP_SEND;
}

constexpr auto isCompletedLocalRead(CoyoteOper oper) {
    return oper == CoyoteOper::LOCAL_READ;
}

constexpr auto isCompletedLocalWrite(CoyoteOper oper) {
    return oper == CoyoteOper::LOCAL_WRITE || oper == CoyoteOper::LOCAL_TRANSFER;
}


/* Hugepages */
constexpr auto isAllocHuge(CoyoteAlloc calloc) {
    return calloc == CoyoteAlloc::HPF || calloc == CoyoteAlloc::THP;
}

/* Daemon */
constexpr auto const recvBuffSize   = 1024;
constexpr auto const sleepIntervalDaemon = 5000L;
constexpr auto const sleepIntervalRequests = 5000L;
constexpr auto const sleepIntervalCompletion = 2000L;
constexpr auto const aesOpId = 0;
constexpr auto const opPrio = 0;
constexpr auto const maxNumClients = 64;
constexpr auto const defOpClose = 0;
constexpr auto const defOpTask = 1;

// ======-------------------------------------------------------------------------------
// Structs
// ======-------------------------------------------------------------------------------

/**
 *  Memory alloc 
 */
struct csAlloc {
	// Type
	CoyoteAlloc alloc = { CoyoteAlloc::REG };

	// Size
	uint32_t size = { 0 };

    // RDMA
    bool remote = { false };

    // Dmabuf
    uint32_t dev = { 0 };
    int32_t fd = { 0 };

    // Mem internal
    void *mem = { nullptr };
};

/**
 * Queue pairs
 */
struct ibvQ {
    // Node
    uint32_t ip_addr;

    // Queue
    uint32_t qpn;
    uint32_t psn;  
    uint32_t rkey;

    // Buffer
    void *vaddr; 
    uint32_t size;
    
    // Global ID
    char gid[33] = { 0 };

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

    void uintToGid(int idx, uint32_t ip_addr) {
        std::ostringstream gidStream;
        gidStream << std::setfill('0') << std::setw(8) << std::hex << ip_addr;
        memcpy(gid+idx, gidStream.str().c_str(), 8);
    }

    void print(const char *name) {
        printf("%s: QPN 0x%06x, PSN 0x%06x, VADDR %016lx, SIZE %08x, IP 0x%08x\n",
            name, qpn, psn, (uint64_t)vaddr, size, ip_addr);
    }
};

/**
 * Queue pair
 */
struct ibvQp {
public:
    ibvQ local;
    ibvQ remote;

    ibvQp() {}
};

/**
 * SG list
 * 
 */
struct syncSg {
    // Buffer
    void* addr = { nullptr };
};

struct localSg {
    // Src
    void* src_addr = { nullptr };
    uint32_t src_len = { 0 };
    uint32_t src_stream = { strmHost };
    uint32_t src_dest = { 0 };

    // Dst
    void* dst_addr = { nullptr };
    uint32_t dst_len = { 0 };
    uint32_t dst_stream = { strmHost };
    uint32_t dst_dest = { 0 };
};

struct rdmaSg {
    // Local
    uint64_t local_offs = { 0 };
    uint32_t local_stream = { strmHost };
    uint32_t local_dest = { 0 };

    // Remote
    uint64_t remote_offs = {0 };
    uint32_t remote_dest = { 0 };

    uint32_t len = { 0 };
};

struct tcpSg {
    // Session
    uint32_t stream = { strmTcp };
    uint32_t dest = { 0 };
    uint32_t len = { 0 };
};

union sgEntry {
    localSg local;
    syncSg sync;
    rdmaSg rdma;
    tcpSg tcp;

    sgEntry() {}
    ~sgEntry() {}
};

struct sgFlags {
    bool last = { true };
    bool clr = { false };
    bool poll = { false };
};

/* Board config */
struct fCnfg {
    bool en_avx = { false };
    bool en_wb = { false };
    bool en_strm = { false };
    bool en_mem = { false };
    bool en_pr = { false };
    bool en_rdma = { false };
    bool en_tcp = { false };
    bool en_net = { false };
    int32_t n_fpga_chan = { 0 };
    int32_t n_fpga_reg = { 0 };

    void parseCnfg(uint64_t cnfg) {
        en_avx = (cnfg >> 0) & 0x1;
        en_wb = (cnfg >> 1) & 0x1;
        en_strm = (cnfg >> 2) & 0x1;
        en_mem = (cnfg >> 3) & 0x1;
        en_pr = (cnfg >> 4) & 0x1;
        en_rdma = (cnfg >> 16) & 0x1;
        en_tcp = (cnfg >> 17) & 0x1;
        n_fpga_chan = (cnfg >> 32) & 0xff;
        n_fpga_reg = (cnfg >> 48) & 0xff;
        en_net = en_rdma || en_tcp;
    }
};

// ======-------------------------------------------------------------------------------
// Util
// ======-------------------------------------------------------------------------------

static uint32_t convert( const std::string& ipv4Str ) {
    std::istringstream iss( ipv4Str );
    
    uint32_t ipv4 = 0;
    
    for( uint32_t i = 0; i < 4; ++i ) {
        uint32_t part;
        iss >> part;
        if ( iss.fail() || part > 255 )
            throw std::runtime_error( "Invalid IP address - Expected [0, 255]" );
        
        // LSHIFT and OR all parts together with the first part as the MSB
        ipv4 |= part << ( 8 * ( 3 - i ) );

        // Check for delimiter except on last iteration
        if ( i != 3 ) {
            char delimiter;
            iss >> delimiter;
            if ( iss.fail() || delimiter != '.' ) 
                throw std::runtime_error( "Invalid IP address - Expected '.' delimiter" );
        }
    }
    
    return ipv4;
}

// ======-------------------------------------------------------------------------------
// Alias
// ======-------------------------------------------------------------------------------

}
