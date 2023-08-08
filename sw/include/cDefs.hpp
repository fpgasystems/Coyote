#pragma once

#include <cstdint>
#include <cstdio>
#include <string>
#include <mutex>
#include <atomic>
#include <tuple>
#include <chrono>

using namespace std::chrono_literals;

/* Globals */
namespace fpga {

// ======-------------------------------------------------------------------------------
// Macros
// ======-------------------------------------------------------------------------------
//#define VERBOSE_DEBUG_1 // Handle
#define VERBOSE_DEBUG_2 // Reconfig
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

#define EN_AVX

/* High low */
#define HIGH_32(data)                       ((data >> 16) >> 16)
#define LOW_32(data)                        (data & 0xffffffffUL)
#define HIGH_16(data)                       (data >> 16)
#define LOW_16(data)                        (data & 0xffff)

/* IOCTL */
#define IOCTL_ALLOC_HOST_USER_MEM       	_IOW('D', 1, unsigned long)
#define IOCTL_FREE_HOST_USER_MEM        	_IOW('D', 2, unsigned long)
#define IOCTL_ALLOC_HOST_PR_MEM         	_IOW('D', 3, unsigned long)
#define IOCTL_FREE_HOST_PR_MEM          	_IOW('D', 4, unsigned long)
#define IOCTL_MAP_USER                  	_IOW('D', 5, unsigned long)
#define IOCTL_UNMAP_USER                	_IOW('D', 6, unsigned long)
#define IOCTL_REGISTER_PID                  _IOW('D', 7, unsigned long)
#define IOCTL_UNREGISTER_PID                _IOW('D', 8, unsigned long)
#define IOCTL_RECONFIG_LOAD             	_IOW('D', 9, unsigned long)

#define IOCTL_ARP_LOOKUP                	_IOW('D', 10, unsigned long)
#define IOCTL_SET_IP_ADDRESS                _IOW('D', 11, unsigned long)
#define IOCTL_SET_MAC_ADDRESS               _IOW('D', 12, unsigned long)
#define IOCTL_WRITE_CTX                	    _IOW('D', 13, unsigned long)
#define IOCTL_WRITE_CONN                	_IOW('D', 14, unsigned long)
#define IOCTL_SET_TCP_OFFS              	_IOW('D', 15, unsigned long)
#define IOCTL_READ_NET_STATS             	_IOR('D', 33, unsigned long)

#define IOCTL_READ_CNFG                     _IOR('D', 32, unsigned long)
#define IOCTL_READ_ENG_STATUS           	_IOR('D', 35, unsigned long)

#define IOCTL_NET_DROP           	        _IOW('D', 36, unsigned long)

/* Control reg */
#define CTRL_START_RD 					    (1UL)
#define CTRL_START_WR 					    (1UL << 1)
#define CTRL_SYNC_RD					    (1UL << 2)
#define CTRL_SYNC_WR					    (1UL << 3)
#define CTRL_STREAM_RD					    (1UL << 4)
#define CTRL_STREAM_WR					    (1UL << 5)
#define CTRL_CLR_STAT_RD				    (1UL << 6)
#define CTRL_CLR_STAT_WR 				    (1UL << 7)
#define CTRL_CLR_IRQ_PENDING			    (1UL << 8)
#define CTRL_DEST_RD      				    9
#define CTRL_DEST_WR    				    13
#define CTRL_PID_RD     			        17
#define CTRL_PID_WR     			        23
#define CTRL_DEST_MASK                      0xf
#define CTRL_PID_MASK                       0x3f

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

enum class CoyoteOper {
    NOOP = 0,
    READ = 1,
    WRITE = 2,
    TRANSFER = 3,
    OFFLOAD = 4,
    SYNC = 5
};

enum class CoyoteAlloc {
    REG_4K = 0,
    HUGE_2M = 1,
    HOST_2M = 2,
    RCNFG_2M = 3
};

/* AVX regs */
enum class CnfgAvxRegs : uint32_t {
    CTRL_REG = 0,
    PF_REG = 1,
    DATAPATH_REG_SET = 2,
    DATAPATH_REG_CLR = 3,
    STAT_REG = 4,
    WBACK_REG = 5,
    RDMA_POST_REG = 16,
    RDMA_POST_REG_0 = 17,
    RDMA_POST_REG_1 = 18,
    RDMA_STAT_REG = 19,
    RDMA_CMPLT_REG = 20,
    TCP_OPEN_CON_REG = 32,
    TCP_OPEN_PORT_REG = 33,
    TCP_OPEN_CON_STS_REG = 34,
    TCP_OPEN_PORT_STS_REG = 35,
    TCP_CLOSE_CON_REG = 36,   
    STAT_DMA_REG = 64
};

/* Legacy regs */
enum class CnfgLegRegs : uint32_t {
    CTRL_REG = 0,
    VADDR_RD_REG = 1,
    LEN_RD_REG = 2,
    VADDR_WR_REG = 3,
    LEN_WR_REG = 4,
    VADDR_MISS_REG = 5,
    PID_LEN_MISS_REG = 6,
    DATAPATH_REG_SET = 7,
    DATAPATH_REG_CLR = 8,
    STAT_CMD_USED_RD_REG = 9,
    STAT_CMD_USED_WR_REG = 10,
    STAT_SENT_HOST_RD_REG = 11,
    STAT_SENT_HOST_WR_REG = 12,
    STAT_SENT_CARD_RD_REG = 13,
    STAT_SENT_CARD_WR_REG = 14,
    STAT_SENT_SYNC_RD_REG = 15,
    STAT_SENT_SYNC_WR_REG = 16,
    STAT_PFAULTS_REG = 17,
    WBACK_REG_0 = 18,
    WBACK_REG_1 = 19,
    WBACK_REG_2 = 20,
    WBACK_REG_3 = 21,
    RDMA_POST_REG = 32,
    RDMA_POST_REG_0 = 33,
    RDMA_POST_REG_1 = 34,
    RDMA_POST_REG_2 = 35,
    RDMA_POST_REG_3 = 36,
    RDMA_POST_REG_4 = 37,
    RDMA_POST_REG_5 = 38,
    RDMA_POST_REG_6 = 39,
    RDMA_POST_REG_7 = 40,
    RDMA_STAT_CMD_USED_REG = 41,
    RDMA_STAT_POSTED_REG = 42,
    RDMA_CMPLT_REG = 43,
    STAT_DMA_REG = 64,
    TCP_OPEN_CON_REG = 65,
    TCP_OPEN_PORT_REG = 66,
    TCP_OPEN_CON_STS_REG = 67,
    TCP_OPEN_PORT_STS_REG = 68,
    TCP_CLOSE_CON_REG = 69,
    STAT_RDMA_REG = 128
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
constexpr auto const pollSleepNs = 100;
constexpr auto const pageSize = (4 * 1024);
constexpr auto const hugePageSize = (2 * 1024 * 1024);
constexpr auto const pageShift = 12UL;
constexpr auto const hugePageShift = 21UL;

/* Internal */
constexpr auto const useHugePages = true;
constexpr auto const clocNs = 4;

/* Bits */
constexpr auto const pidBits = 6;
constexpr auto const pidMask = 0x3f;
constexpr auto const nRegBits = 4;
constexpr auto const nRegMask = 0xf;

/* FIFOs */
constexpr auto const cmdFifoDepth = 32;
constexpr auto const cmdFifoThr = 10;

/* Writeback size */
constexpr auto const nCpidMax = 64;
constexpr auto const nCpidBits = 6;

/* Regions */
constexpr auto const ctrlRegionSize = 64 * 1024;
constexpr auto const cnfgRegionSize = 64 * 1024;
constexpr auto const cnfgAvxRegionSize = 256 * 1024;
constexpr auto const wbackRegionSize = 4 * nCpidMax * sizeof(uint32_t);

/* MMAP */
constexpr auto const mmapCtrl = 0x0 << pageShift;
constexpr auto const mmapCnfg = 0x1 << pageShift;
constexpr auto const mmapCnfgAvx = 0x2 << pageShift;
constexpr auto const mmapWb = 0x3 << pageShift;
constexpr auto const mmapBuff = 0x200 << pageShift;
constexpr auto const mmapPr = 0x400 << pageShift;

/* Threading */
static constexpr struct timespec PAUSE {.tv_sec = 0, .tv_nsec = 1000};
static constexpr struct timespec MSPAUSE {.tv_sec = 0, .tv_nsec = 1000000};
constexpr auto const cmplTimeout = 5000ms;
constexpr auto const maxCqueueSize = 512;

/* AXI */
constexpr auto const axiDataWidth = 64;

/* Net regs */
constexpr auto const nNetRegs = 9;

/* QSFP regs offset */
constexpr auto const qsfpOffsAvx = 8;
constexpr auto const qsfpOffsLeg = 16;

constexpr auto const qpContextQpnOffs = 32;
constexpr auto const qpContextRpsnOffs = 0;
constexpr auto const qpContextLpsnOffs = 24;
constexpr auto const qpContextRkeyOffs = 0;
constexpr auto const qpContextVaddrOffs = 16;

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

/* Operations */
constexpr auto isRead(CoyoteOper oper) {
    return oper == CoyoteOper::READ || oper == CoyoteOper::OFFLOAD || oper == CoyoteOper::TRANSFER;
}

constexpr auto isWrite(CoyoteOper oper) {
    return oper == CoyoteOper::WRITE || oper == CoyoteOper::SYNC || oper == CoyoteOper::TRANSFER;
}

constexpr auto isSync(CoyoteOper oper) {
    return oper == CoyoteOper::OFFLOAD || oper == CoyoteOper::SYNC;
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

// ======-------------------------------------------------------------------------------
// Structs
// ======-------------------------------------------------------------------------------

/* Memory alloc */
struct csAlloc {
	// Type
	CoyoteAlloc alloc = { CoyoteAlloc::REG_4K };

	// Number of pages
	uint32_t n_pages = { 0 };
};

/* Invoke struct */
struct csInvokeAll {
	// Operation
	CoyoteOper oper = { CoyoteOper::NOOP };
	
	// Data
	void* src_addr = { nullptr }; 
	void* dst_addr = { nullptr };
	uint32_t src_len = { 0 };
	uint32_t dst_len = { 0 }; 

	// Flags
	bool clr_stat = true;
	bool poll = true;
	uint8_t dest = { 0 };
	bool stream = true;
};

/* Invoke struct with single src/dst location (simplification only) */
struct csInvoke {
	// Operation
	CoyoteOper oper = { CoyoteOper::NOOP };
	
	// Data
	void* addr = { nullptr }; 
	uint32_t len = { 0 };

	// Flags
	bool clr_stat = true;
	bool poll = true;
	uint8_t dest = { 0 };
	bool stream = true;
};

/* Board config */
struct fCnfg {
    bool en_avx = { false };
    bool en_bypass = { false };
    bool en_tlbf = { false };
    bool en_wb = { false };
    bool en_strm = { false };
    bool en_mem = { false };
    bool en_pr = { false };
    bool en_rdma_0 = { false };
    bool en_rdma_1 = { false };
    bool en_rdma = { false };
    bool en_tcp_0 = { false };
    bool en_tcp_1 = { false };
    bool en_tcp = { false };
    bool en_net_0 = { false };
    bool en_net_1 = { false };
    bool en_net = { false };
    int32_t n_fpga_chan = { 0 };
    int32_t n_fpga_reg = { 0 };
    uint32_t qsfp = { 0 };
    uint32_t qsfp_offs = { 0 };

    void parseCnfg(uint64_t cnfg) {
        en_avx = (cnfg >> 0) & 0x1;
        en_bypass = (cnfg >> 1) & 0x1;
        en_tlbf = (cnfg >> 2) & 0x1;
        en_wb = (cnfg >> 3) & 0x1;
        en_strm = (cnfg >> 4) & 0x1;
        en_mem = (cnfg >> 5) & 0x1;
        en_pr = (cnfg >> 6) & 0x1;
        en_rdma_0 = (cnfg >> 16) & 0x1;
        en_rdma_1 = (cnfg >> 17) & 0x1;
        en_tcp_0 = (cnfg >> 18) & 0x1;
        en_tcp_1 = (cnfg >> 19) & 0x1; 
        n_fpga_chan = (cnfg >> 32) & 0xff;
        n_fpga_reg = (cnfg >> 48) & 0xff;
        en_rdma = en_rdma_0 || en_rdma_1;
        en_tcp = en_tcp_0 || en_tcp_1;
        en_net_0 = en_rdma_0 || en_tcp_0;
        en_net_1 = en_rdma_1 || en_tcp_1;
        en_net = en_net_0 || en_net_1;
        qsfp = en_net_1;
        qsfp_offs =  en_net_1 ? (en_avx ? qsfpOffsAvx : qsfpOffsLeg) : 0; 
    }
};

// ======-------------------------------------------------------------------------------
// Alias
// ======-------------------------------------------------------------------------------

}
