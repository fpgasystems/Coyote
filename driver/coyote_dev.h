/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
  * All rights reserved.
  *
  * Redistribution and use in source and binary forms, with or without modification,
  * are permitted provided that the following conditions are met:
  *
  * 1. Redistributions of source code must retain the above copyright notice,
  * this list of conditions and the following disclaimer.
  * 2. Redistributions in binary form must reproduce the above copyright notice,
  * this list of conditions and the following disclaimer in the documentation
  * and/or other materials provided with the distribution.
  * 3. Neither the name of the copyright holder nor the names of its contributors
  * may be used to endorse or promote products derived from this software
  * without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  */

#ifndef __COYOTE_DEV_H__
#define __COYOTE_DEV_H__

#include <asm/io.h>
#include <linux/clk.h>
#include <linux/device.h>
#include <linux/hrtimer.h>
#include <linux/init.h>
#include <linux/interrupt.h>
#include <linux/irq.h>
#include <linux/irqchip/chained_irq.h>
#include <linux/irqdomain.h>
#include <linux/ioport.h>
#include <linux/kernel.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/scatterlist.h>
#include <linux/sched.h>
#include <linux/types.h>
#include <linux/cdev.h>
#include <linux/pagemap.h>
#include <linux/vmalloc.h>
#include <linux/mm.h>
#include <linux/version.h>
#include <linux/ioctl.h>
#include <linux/compiler.h>
#include <linux/msi.h>
#include <linux/poll.h>
#include <linux/sched.h>
#include <asm/delay.h>
#include <asm/set_memory.h>
#include <linux/hashtable.h>
#include <linux/moduleparam.h>
#include <linux/stat.h>
#include <linux/sysfs.h>
#include <linux/kobject.h>

/**
 * @brief Args
 * 
 */

#define CYT_ARCH_PCI 0
#define CYT_ARCH_ECI 1

extern int cyt_arch; 
extern char *ip_addr_q0;
extern char *ip_addr_q1;
extern char *mac_addr_q0;
extern char *mac_addr_q1;
extern long int eost;

/**
 * @brief Info
 * 
 */

/* Driver info */
#define DRV_NAME "coyote_driver"
#define DEV_NAME "fpga"

/**
 * @brief Util
 * 
 */

/* Debug print */
#define COYOTE_DEBUG 1

#if (COYOTE_DEBUG == 0)
    #define dbg_info(...)
#else
    #define dbg_info(fmt, ...) pr_info("%s():" fmt, \
        __func__, ##__VA_ARGS__)
#endif

/* Obtain the 32 most significant (high) bits of a 32-bit or 64-bit address */
#define HIGH_32(addr) ((addr >> 16) >> 16)
/* Obtain the 32 least significant (low) bits of a 32-bit or 64-bit address */
#define LOW_32(addr) (addr & 0xffffffffUL)

/**
 * @brief Bus
 * 
 */

/* XDMA info */
#define MAX_NUM_BARS 3
#define MAX_NUM_CHANNELS 4
#define MAX_NUM_ENGINES (MAX_NUM_CHANNELS * 2)
#define MAX_USER_IRQS 16
#define C2H_CHAN_OFFS 0x1000
#define H2C_CHAN_OFFS 0x0000
#define CHAN_RANGE 0x100
#define SGDMA_OFFSET_FROM_CHANNEL 0x4000

/* Engine IDs */
#define XDMA_ID_H2C 0x1fc0U
#define XDMA_ID_C2H 0x1fc1U

/* Engine regs */
#define XDMA_ENG_IRQ_NUM (1)
#define XDMA_OFS_INT_CTRL (0x2000UL)
#define XDMA_OFS_CONFIG (0x3000UL)

/* Bits of the SG DMA control register */
#define XDMA_CTRL_RUN_STOP (1UL << 0)
#define XDMA_CTRL_IE_DESC_STOPPED (1UL << 1)
#define XDMA_CTRL_IE_DESC_COMPLETED (1UL << 2)
#define XDMA_CTRL_IE_DESC_ALIGN_MISMATCH (1UL << 3)
#define XDMA_CTRL_IE_MAGIC_STOPPED (1UL << 4)
#define XDMA_CTRL_IE_IDLE_STOPPED (1UL << 6)
#define XDMA_CTRL_IE_READ_ERROR (0x1FUL << 9)
#define XDMA_CTRL_IE_DESC_ERROR (0x1FUL << 19)
#define XDMA_CTRL_NON_INCR_ADDR (1UL << 25)
#define XDMA_CTRL_POLL_MODE_WB (1UL << 26)

/* Bits of the SG DMA status register */
#define XDMA_STAT_BUSY (1UL << 0)
#define XDMA_STAT_DESC_STOPPED (1UL << 1)
#define XDMA_STAT_DESC_COMPLETED (1UL << 2)
#define XDMA_STAT_ALIGN_MISMATCH (1UL << 3)
#define XDMA_STAT_MAGIC_STOPPED (1UL << 4)
#define XDMA_STAT_FETCH_STOPPED (1UL << 5)
#define XDMA_STAT_IDLE_STOPPED (1UL << 6)
#define XDMA_STAT_READ_ERROR (0x1FUL << 9)
#define XDMA_STAT_DESC_ERROR (0x1FUL << 19)

/* Bits of the performance control register */
#define XDMA_PERF_RUN (1UL << 0)
#define XDMA_PERF_CLEAR (1UL << 1)
#define XDMA_PERF_AUTO (1UL << 2)

/* Polling */
#define WB_COUNT_MASK 0x00ffffffUL
#define WB_ERR_MASK (1UL << 31)
#define POLL_TIMEOUT_SECONDS 10
#define NUM_POLLS_PER_SCHED 100

/* Physical address (ECI) */
#define IO_PHYS_ADDR 0x900000000000UL

/* XDMA debug */
#define N_STAT_REGS 32
#define N_XDMA_STAT_REGS 12
#define N_XDMA_STAT_CH_REGS (N_XDMA_STAT_REGS / MAX_NUM_CHANNELS)

/**
 * @brief Static layer
 * 
 */

#define BAR_XDMA_CONFIG 0
#define BAR_FPGA_CONFIG 1

/* FPGA static config */
#define FPGA_STAT_CNFG_OFFS 0x0
#define FPGA_STAT_CNFG_SIZE 32 * 1024

#define EN_AVX_MASK 0x1
#define EN_AVX_SHFT 0x0
#define EN_BPSS_MASK 0x2
#define EN_BPSS_SHFT 0x1
#define EN_TLBF_MASK 0x4
#define EN_TLBF_SHFT 0x2
#define EN_WB_MASK 0x8
#define EN_WB_SHFT 0x3
#define TLB_S_ORDER_MASK 0xf0
#define TLB_S_ORDER_SHFT 0x4
#define TLB_S_ASSOC_MASK 0xf00
#define TLB_S_ASSOC_SHFT 0x8
#define TLB_L_ORDER_MASK 0xf000
#define TLB_L_ORDER_SHFT 0xc
#define TLB_L_ASSOC_MASK 0xf0000
#define TLB_L_ASSOC_SHFT 0x10
#define TLB_S_PG_SHFT_MASK 0x3f00000
#define TLB_S_PG_SHFT_SHFT 0x14
#define TLB_L_PG_SHFT_MASK 0xfc000000
#define TLB_L_PG_SHFT_SHFT 0x1a

#define EN_STRM_MASK 0x1
#define EN_STRM_SHFT 0x0
#define EN_MEM_MASK 0x2
#define EN_MEM_SHFT 0x1
#define EN_RDMA_0_MASK 0x1
#define EN_RDMA_1_MASK 0x2
#define EN_PR_MASK 0x1
#define EN_PR_SHFT 0x0
#define EN_RDMA_0_MASK 0x1
#define EN_RDMA_0_SHFT 0x0
#define EN_RDMA_1_MASK 0x2
#define EN_RDMA_1_SHFT 0x1
#define EN_TCP_0_MASK 0x1
#define EN_TCP_0_SHFT 0x0
#define EN_TCP_1_MASK 0x2
#define EN_TCP_1_SHFT 0x1

/**
 * @brief Dynamic layer
 * 
 */

/* FPGA control regions */
#define FPGA_CTRL_SIZE 256 * 1024
#define FPGA_CTRL_OFFS 0x100000
#define FPGA_CTRL_LTLB_SIZE FPGA_CTRL_SIZE / 4
#define FPGA_CTRL_LTLB_OFFS 0x0
#define FPGA_CTRL_STLB_SIZE FPGA_CTRL_SIZE / 4
#define FPGA_CTRL_STLB_OFFS 0x10000
#define FPGA_CTRL_USER_SIZE FPGA_CTRL_SIZE / 4
#define FPGA_CTRL_USER_OFFS 0x20000
#define FPGA_CTRL_CNFG_SIZE FPGA_CTRL_SIZE / 4
#define FPGA_CTRL_CNFG_OFFS 0x30000

#define FPGA_CTRL_CNFG_AVX_SIZE 256 * 1024
#define FPGA_CTRL_CNFG_AVX_OFFS 0x1000000

/* FPGA dynamic control config */
#define FPGA_CNFG_CTRL_IRQ_RESTART 0x100

/* Maximum transfer size */
#define TRANSFER_MAX_BYTES (8 * 1024 * 1024)

/* TLB */
#define TLB_VADDR_RANGE 48
#define TLB_PADDR_RANGE 40
#define PID_SIZE 6
#define MAX_MAP_AXIL_PAGES 64

#define LTLB_PAGE_BITS 21
#define STLB_PAGE_BITS 12
#define LTLB_PADDR_SIZE (TLB_PADDR_RANGE - LTLB_PAGE_BITS)
#define STLB_PADDR_SIZE (TLB_PADDR_RANGE - STLB_PAGE_BITS)

#define TLBF_CTRL_START 0x7
#define TLBF_CTRL_ID_MASK 0xff
#define TLBF_CTRL_ID_SHFT 0x3
#define TLBF_STAT_DONE 0x1

/* Memory allocation */
#define MAX_BUFF_NUM 64    // maximum number of huge pages allowed
#define MAX_PR_BUFF_NUM 64 // maximum number of huge pages allowed
#define MAX_N_MAP_PAGES 128             // TODO: link to params, max no pfault 1M
#define MAX_N_MAP_HUGE_PAGES (16 * 512) // max no pfault 32M

/* Max card pages */
#define N_LARGE_CHUNKS 512
#define N_SMALL_CHUNKS (256 * 1024)
#define MEM_SEP (N_SMALL_CHUNKS * (4 * 1024))
#define MAX_N_REGIONS 16
#define SMALL_CHUNK_ALLOC 0
#define LARGE_CHUNK_ALLOC 1

/* PR */
#define PR_CTRL_START_MIDDLE 0x1
#define PR_CTRL_START_LAST 0x7
#define PR_STAT_DONE 0x1

/**
 * @brief Cdev
 * 
 */

/* Major number */
#define FPGA_MAJOR 0 // dynamic

/* MMAP */
#define MMAP_CTRL 0x0
#define MMAP_CNFG 0x1
#define MMAP_CNFG_AVX 0x2
#define MMAP_WB 0x3
#define MMAP_BUFF 0x200
#define MMAP_PR 0x400

/* IOCTL */
#define IOCTL_ALLOC_HOST_USER_MEM _IOW('D', 1, unsigned long) // large pages (no hugepage support)
#define IOCTL_FREE_HOST_USER_MEM _IOW('D', 2, unsigned long)
#define IOCTL_ALLOC_HOST_PR_MEM _IOW('D', 3, unsigned long) // pr pages
#define IOCTL_FREE_HOST_PR_MEM _IOW('D', 4, unsigned long)
#define IOCTL_MAP_USER _IOW('D', 5, unsigned long) // map
#define IOCTL_UNMAP_USER _IOW('D', 6, unsigned long)
#define IOCTL_REGISTER_PID _IOW('D', 7, unsigned long) // register pid
#define IOCTL_UNREGISTER_PID _IOW('D', 8, unsigned long)
#define IOCTL_RECONFIG_LOAD _IOW('D', 9, unsigned long) // reconfiguration

#define IOCTL_ARP_LOOKUP _IOW('D', 10, unsigned long)    // arp lookup
#define IOCTL_SET_IP_ADDRESS _IOW('D', 11, unsigned long)
#define IOCTL_SET_MAC_ADDRESS _IOW('D', 12, unsigned long)
#define IOCTL_WRITE_CTX _IOW('D', 13, unsigned long)     // qp context
#define IOCTL_WRITE_CONN _IOW('D', 14, unsigned long)   // qp connection
#define IOCTL_SET_TCP_OFFS _IOW('D', 15, unsigned long) // tcp mem offsets

#define IOCTL_READ_CNFG _IOR('D', 32, unsigned long)       // status cnfg
#define IOCTL_XDMA_STATS _IOR('D', 33, unsigned long)        // status xdma
#define IOCTL_NET_STATS _IOR('D', 34, unsigned long)        // status network
#define IOCTL_READ_ENG_STATUS _IOR('D', 35, unsigned long) // status engines

#define IOCTL_NET_DROP _IOW('D', 36, unsigned long) // net dropper

/* Hash */
#define PR_HASH_TABLE_ORDER 8
#define PR_BATCH_SIZE (2 * 1024 * 1024)

#define USER_HASH_TABLE_ORDER 8
#define PID_HASH_TABLE_ORDER 8

/* PID */
#define N_CPID_MAX 64
#define WB_BLOCKS 4
#define WB_SIZE (WB_BLOCKS * N_CPID_MAX * sizeof(uint32_t))
#define N_WB_PAGES ((WB_SIZE + PAGE_SIZE - 1) / PAGE_SIZE)

/* Network */
#define EN_LOWSPEED 0x5
#define N_NET_STAT_REGS 10

/* Copy */
#define MAX_USER_WORDS 32

/**
 * @brief Reg maps
 * 
 */

/* DMA engine reg map */
struct engine_regs {
    uint32_t id;
    uint32_t ctrl;
    uint32_t ctrl_w1s;
    uint32_t ctrl_w1c;
    uint32_t rsrvd_1[12];

    uint32_t status;
    uint32_t status_rc;
    uint32_t completed_desc_count;
    uint32_t alignments;
    uint32_t rsrvd_2[14]; // padding

    uint32_t poll_mode_wb_lo;
    uint32_t poll_mode_wb_hi;
    uint32_t interrupt_enable_mask;
    uint32_t interrupt_enable_mask_w1s;
    uint32_t interrupt_enable_mask_w1c;
    uint32_t rsrvd_3[9]; // padding

    uint32_t perf_ctrl;
    uint32_t perf_cyc_lo;
    uint32_t perf_cyc_hi;
    uint32_t perf_dat_lo;
    uint32_t perf_dat_hi;
    uint32_t perf_pnd_lo;
    uint32_t perf_pnd_hi;
} __packed;

/* Interrupt reg map */
struct interrupt_regs {
    uint32_t id;
    uint32_t user_int_enable;
    uint32_t user_int_enable_w1s;
    uint32_t user_int_enable_w1c;
    uint32_t channel_int_enable;
    uint32_t channel_int_enable_w1s;
    uint32_t channel_int_enable_w1c;
    uint32_t reserved_1[9]; // padding

    uint32_t user_int_request;
    uint32_t channel_int_request;
    uint32_t user_int_pending;
    uint32_t channel_int_pending;
    uint32_t reserved_2[12]; // padding

    uint32_t user_msi_vector[8];
    uint32_t channel_msi_vector[8];
} __packed;

/* Polled mode descriptors struct */
struct xdma_poll_wb {
    uint32_t completed_desc_count;
    uint32_t reserved_1[7];
} __packed;

/* FPGA static config reg map */
struct fpga_stat_cnfg_regs {
    uint64_t probe; // 0
    uint64_t n_chan; // 1
    uint64_t n_regions; // 2
    uint64_t ctrl_cnfg; // 3
    uint64_t mem_cnfg; // 4
    uint64_t pr_cnfg; // 5
    uint64_t rdma_cnfg; // 6
    uint64_t tcp_cnfg; // 7
    uint64_t lspeed_cnfg; // 8
    uint64_t reserved_0[1]; // 9
    uint64_t pr_ctrl; // 10
    uint64_t pr_stat; // 11
    uint64_t pr_addr; // 12
    uint64_t pr_len; // 13
    uint64_t pr_eost; // 14
    uint64_t tlb_ctrl; // 15
    uint64_t tlb_stat; // 16
    uint64_t tlb_addr; // 17
    uint64_t tlb_len; // 18
    uint64_t reserved_1[1]; // 19
    uint64_t net_0_ip; // 20
    uint64_t net_0_mac; // 21 
    uint64_t net_0_arp; // 22
    uint64_t net_1_ip; // 23
    uint64_t net_1_mac; // 24
    uint64_t net_1_arp; // 25
    uint64_t tcp_0_offs[2]; // 26-27
    uint64_t rdma_0_qp_ctx[3]; // 28-30
    uint64_t rdma_0_qp_conn[3]; // 31-33
    uint64_t tcp_1_offs[2]; // 34-35
    uint64_t rdma_1_qp_ctx[3]; // 36-38
    uint64_t rdma_1_qp_conn[3]; // 39-41
    uint64_t net_drop_0[2]; // 42-43
    uint64_t net_drop_clr_0; // 44
    uint64_t net_drop_1[2]; // 45-46
    uint64_t net_drop_clr_1; // 47
    uint64_t reserved_2[16]; // 48-63
    uint64_t xdma_debug[N_STAT_REGS]; // 64-96
    uint64_t net_0_debug[N_STAT_REGS]; // 96-128
    uint64_t net_1_debug[N_STAT_REGS]; // 128-160
} __packed;

/* FPGA dynamic config reg map */
struct fpga_cnfg_regs {
    uint64_t ctrl;
    uint64_t vaddr_rd;
    uint64_t len_rd;
    uint64_t vaddr_wr;
    uint64_t len_wr;
    uint64_t vaddr_miss;
    uint64_t len_miss;
    uint64_t datapath_set;
    uint64_t datapath_clr;
    uint64_t stat_cmd_used_rd;
    uint64_t stat_cmd_used_wr;
    uint64_t stat_sent[6];
    uint64_t stat_pfaults;
    uint64_t wback[4];
    // Rest of regs not used in the driver
} __packed;

/* FPGA dynamic config reg map */
struct fpga_cnfg_regs_avx {
    uint64_t ctrl[4];
    uint64_t vaddr_miss;
    uint64_t len_miss;
    uint64_t pf[2];
    uint64_t datapath_set[4];
    uint64_t datapath_clr[4];
    uint64_t stat[4];
    uint64_t wback[4];
    // Rest not used in the driver
} __packed;

/**
 * @brief Engine structs
 * 
 */

/* Engine descriptors */
struct xdma_sgdma_regs {
    uint32_t identifier;
    uint32_t reserved_1[31]; /* padding */

    /* bus address to first descriptor in Root Complex Memory */
    uint32_t first_desc_lo;
    uint32_t first_desc_hi;
    /* number of adjacent descriptors at first_desc */
    uint32_t first_desc_adjacent;
    uint32_t credits;
} __packed;

/* Engine struct */
struct xdma_engine {
    int channel;            // egnine channel
    char *name;             // engine name
    struct bus_drvdata *pd; // PCI device

    struct engine_regs *regs;             // HW regs, control and status
    struct engine_sgdma_regs *sgdma_regs; // SGDMA reg BAR offset

    // Config
    int running; // engine state
    int c2h;     // c2h(write) or h2c(read)
    uint32_t status;

    int addr_align;      // source/dest alignment in bytes
    int len_granularity; // transfer length multiple
    int addr_bits;       // HW datapath address width

    /* Members associated with polled mode support */
    uint8_t *poll_mode_addr_virt; /* virt addr for descriptor writeback */
    uint64_t poll_mode_phys_addr; /* bus addr for descriptor writeback */
};

/**
 * @brief Hash maps
 * 
 */

/* Inode */
struct cid_entry {
    struct hlist_node entry;
    pid_t pid;
    int32_t cpid;
};

/* Mapped user pages */
struct user_pages {
    struct hlist_node entry;
    uint64_t vaddr;
    bool huge;
    int32_t cpid;
    uint64_t n_hpages;
    uint64_t n_pages;
    struct page **hpages;
    uint64_t *cpages;
};

/* Mapped large PR pages */
struct pr_pages {
    struct hlist_node entry;
    int reg_id;
    uint64_t vaddr;
    uint64_t n_pages;
    struct page **pages;
};

/* PID tables */
extern struct hlist_head pid_cpid_map[MAX_N_REGIONS][1 << (PID_HASH_TABLE_ORDER)];

/* User tables */
extern struct hlist_head user_lbuff_map[MAX_N_REGIONS][1 << (USER_HASH_TABLE_ORDER)]; // large alloc
extern struct hlist_head user_sbuff_map[MAX_N_REGIONS][1 << (USER_HASH_TABLE_ORDER)]; // main alloc

/* PR table */
extern struct hlist_head pr_buff_map[1 << (PR_HASH_TABLE_ORDER)];

/**
 * @brief Mem
 * 
 */

/* Pool chunks */
struct chunk {
    bool used;
    uint32_t id;
    struct chunk *next;
};

/* TLB order */
struct tlb_order {
    bool hugepage;
    uint64_t page_shift;
    uint64_t page_size;
    uint64_t page_mask;
    int assoc;
    
    int key_mask;
    int key_size;
    int tag_mask;
    int tag_size;
    int phy_mask;
    int phy_size;
};

/**
 * @brief Dev structs
 * 
 */

/* PR controller */
struct pr_ctrl {
    struct bus_drvdata *pd; // PCI device
    spinlock_t lock;

    // Engines
    struct xdma_engine *engine_h2c; // h2c engine
    struct xdma_engine *engine_c2h; // c2h engine

    // Allocated buffers
    struct pr_pages curr_buff;
};

/* Virtual FPGA device */
struct fpga_dev {
    int id; // identifier
    struct cdev cdev; // char device
    struct bus_drvdata *pd; // PCI device
    struct pr_ctrl *prc; // PR controller
    
    // Control region
    uint64_t fpga_phys_addr_ctrl;
    uint64_t fpga_phys_addr_ctrl_avx;

    // Writeback
    uint32_t *wb_addr_virt;
    uint64_t wb_phys_addr;

    // TLBs
    uint64_t *fpga_lTlb; // large page TLB
    uint64_t *fpga_sTlb; // small page TLB
    struct fpga_cnfg_regs *fpga_cnfg; // config
    struct fpga_cnfg_regs_avx *fpga_cnfg_avx; // config AVX

    // PIDs
    spinlock_t card_pid_lock;
    struct chunk *pid_chunks;
    pid_t *pid_array;
    int num_free_pid_chunks;
    struct chunk *pid_alloc;

    // Engines
    struct xdma_engine *engine_h2c; // h2c engine
    struct xdma_engine *engine_c2h; // c2h engine

    // In use
    atomic_t in_use; // busy flag

    // Lock
    spinlock_t lock; // protects concurrent accesses

    // Allocated buffers
    struct user_pages curr_user_buff;
};

/* PCI driver data */
struct bus_drvdata {

// PCI
    struct pci_dev *pci_dev;
    
    // BARs
    int regions_in_use;
    int got_regions;
    void *__iomem bar[MAX_NUM_BARS];
    unsigned long bar_phys_addr[MAX_NUM_BARS];
    unsigned long bar_len[MAX_NUM_BARS];

    // Engines
    int engines_num;

// ECI
    // I/O
    unsigned long io_phys_addr;
    unsigned long io_len;

    // Sysfs
    struct kobject cyt_kobj;

    // FPGA static config
    uint probe;
    int n_fpga_chan;
    int n_fpga_reg;
    int en_avx;
    int en_bypass;
    int en_tlbf;
    int en_wb;
    int en_strm;
    int en_mem;
    int en_pr;
    int en_rdma_0;
    int en_rdma_1;
    int en_tcp_0;
    int en_tcp_1;
    int en_net_0;
    int en_net_1;
    uint32_t net_0_ip_addr;
    uint64_t net_0_mac_addr;
    uint32_t net_1_ip_addr;
    uint64_t net_1_mac_addr;
    uint64_t eost;
    volatile struct fpga_stat_cnfg_regs *fpga_stat_cnfg;
    struct fpga_dev *fpga_dev;

    // PR control
    struct pr_ctrl prc;

    // TLB order
    struct tlb_order *stlb_order;
    struct tlb_order *ltlb_order;

    // Locks
    spinlock_t stat_lock;
    spinlock_t prc_lock;
    spinlock_t tlb_lock;

    // IRQ
    int irq_count;
    int irq_line;
    int msix_enabled;
    struct msix_entry irq_entry[32];

    // Card memory
    spinlock_t card_l_lock;
    struct chunk *lchunks;
    int num_free_lchunks;
    struct chunk *lalloc;

    spinlock_t card_s_lock;
    struct chunk *schunks;
    int num_free_schunks;
    struct chunk *salloc;
};


#endif // Coyote device

