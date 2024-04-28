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
#include <linux/ktime.h>
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
#include <linux/swap.h>
#include <linux/swapops.h>
#include <linux/types.h>
#include <linux/cdev.h>
#include <linux/rmap.h>
#include <linux/pagemap.h>
#include <linux/vmalloc.h>
#include <linux/mm.h>
#include <linux/memremap.h>
#include <linux/sched/mm.h>
#include <linux/highmem.h>
#include <linux/version.h>
#include <linux/slab.h>
#include <linux/ioctl.h>
#include <linux/compiler.h>
#include <linux/msi.h>
#include <linux/poll.h>
#include <asm/delay.h>
#include <linux/mutex.h>
#include <linux/rwsem.h>
#include <asm/set_memory.h>
#include <linux/hashtable.h>
#include <linux/moduleparam.h>
#include <linux/stat.h>
#include <linux/sysfs.h>
#include <linux/fs.h>
#include <linux/kobject.h>
#include <linux/list.h>
#include <linux/mdev.h>
#include <linux/vfio.h>
#include <linux/kvm_host.h>
#include <linux/mmu_notifier.h>
#include <linux/hmm.h>
#include <linux/delay.h>
#include <linux/pagewalk.h>
#include <asm/page.h>
#include <linux/migrate.h>
#include <linux/uaccess.h>
#include <linux/dma-buf.h>
#include <linux/dma-direct.h>
#include <linux/dma-resv.h>

/*
 ██████╗ ██████╗ ██╗   ██╗ ██████╗ ████████╗███████╗
██╔════╝██╔═══██╗╚██╗ ██╔╝██╔═══██╗╚══██╔══╝██╔════╝
██║     ██║   ██║ ╚████╔╝ ██║   ██║   ██║   █████╗  
██║     ██║   ██║  ╚██╔╝  ██║   ██║   ██║   ██╔══╝  
╚██████╗╚██████╔╝   ██║   ╚██████╔╝   ██║   ███████╗
 ╚═════╝ ╚═════╝    ╚═╝    ╚═════╝    ╚═╝   ╚══════╝
*/    

/**
 * @brief Args
 * 
 */

#define CYT_ARCH_PCI 0
#define CYT_ARCH_ECI 1

extern int cyt_arch; 
extern char *ip_addr;
extern char *mac_addr;
extern long int eost;
extern bool en_hmm;
extern char *config_fname;

/**
 * @brief Info
 * 
 */

/* Driver info */
#define DRV_NAME "coyote_driver"
#define DEV_FPGA_NAME "fpga" // "cyt_fpga"

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

/* Obtain the 32 most significant (high) bits of a 64-bit address */
#define HIGH_32(addr) ((addr >> 16) >> 16)
/* Obtain the 32 least significant (low) bits of a 64-bit address */
#define LOW_32(addr) (addr & 0xffffffffUL)

/* Obtain the 16 most significant (high) bits of a 32-bit address */
#define HIGH_16(addr) (addr >> 16)
/* Obtain the 16 least significant (low) bits of a 32-bit address */
#define LOW_16(addr) (addr & 0xffff)

//#define HMM_KERNEL

/**
 * @brief Bus
 * 
 */

/* Mult FPGAs */
#define MAX_DEVICES 16
#define MAX_CONFIG_LINE_LENGTH 32

/* XDMA info */
#define MAX_NUM_BARS 6
#define CYT_BARS 3
#define MAX_NUM_CHANNELS 3
#define MAX_NUM_ENGINES (MAX_NUM_CHANNELS * 2)
#define MAX_USER_IRQS 16
#define C2H_CHAN_OFFS 0x1000
#define H2C_CHAN_OFFS 0x0000
#define CHAN_RANGE 0x100
#define SGDMA_OFFSET_FROM_CHANNEL 0x4000
#define CHAN_IRQ_OFFS 16

/* Line */
#define MAX_LINE_LENGTH 1024

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
 * @brief Static and shell layers
 * 
 */

#define BAR_STAT_CONFIG 0
#define BAR_XDMA_CONFIG 1
#define BAR_SHELL_CONFIG 2

/* FPGA static config */
#define FPGA_STAT_CNFG_OFFS 0x0
#define FPGA_STAT_CNFG_SIZE (32UL * 1024UL)

/* FPGA shell config */
#define FPGA_SHELL_CNFG_OFFS 0x0
#define FPGA_SHELL_CNFG_SIZE (32UL * 1024UL)

#define EN_AVX_MASK 0x1
#define EN_AVX_SHFT 0x0
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
#define EN_PR_MASK 0x1
#define EN_PR_SHFT 0x0
#define EN_RDMA_MASK 0x1
#define EN_RDMA_SHFT 0x0
#define EN_TCP_MASK 0x1
#define EN_TCP_SHFT 0x0
#define QSFP_MASK 0x2
#define QSFP_SHFT 0x1

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

/* IRQ control */
#define FPGA_CNFG_CTRL_IRQ_CLR_PENDING 0x1
#define FPGA_CNFG_CTRL_IRQ_PF_RD_SUCCESS 0xa
#define FPGA_CNFG_CTRL_IRQ_PF_WR_SUCCESS 0xc
#define FPGA_CNFG_CTRL_IRQ_PF_RD_DROP 0x2
#define FPGA_CNFG_CTRL_IRQ_PF_WR_DROP 0x4
#define FPGA_CNFG_CTRL_IRQ_INVLDT 0x10
#define FPGA_CNFG_CTRL_IRQ_INVLDT_LAST 0x30
#define FPGA_CNFG_CTRL_IRQ_LOCK 0x50

/* IRQ vector */
#define FPGA_PR_IRQ_VECTOR 15
#define FPGA_PR_IRQ_MASK 0x8000
#define FPGA_USER_IRQ_MASK 0x7fff

/* DMA */
#define TRANSFER_MAX_BYTES (8 * 1024 * 1024)
#define DMA_THRSH 32
#define DMA_MIN_SLEEP_CMD 10
#define DMA_MAX_SLEEP_CMD 50

#define DMA_CTRL_START_MIDDLE 0x1
#define DMA_CTRL_START_LAST 0x7
#define DMA_STAT_DONE 0x1

/* TLB */
#define TLB_VADDR_RANGE 48
#define TLB_PADDR_RANGE 44
#define PID_SIZE 6
#define STRM_SIZE 2

#define TLBF_CTRL_START 0x7
#define TLBF_CTRL_ID_MASK 0xff
#define TLBF_CTRL_ID_SHFT 0x3
#define TLBF_STAT_DONE 0x1

/* Delay */
#define TLBF_DELAY 1 // us
#define PR_DELAY 1 // us

/* Memory mapping */
#define MAX_N_MAP_PAGES 256  
#define MAX_N_MAP_HUGE_PAGES 256
#define MAX_SINGLE_DMA_SYNC 4 // pages

/* Max card pages */
#define MEM_START (256UL * 1024UL * 1024UL)
#define MEM_START_CHUNKS (MEM_START / (4UL * 1024UL))
#define N_SMALL_CHUNKS ((256UL * 1024UL) - MEM_START_CHUNKS)
#define N_LARGE_CHUNKS (1024UL * 1024UL)
#define MEM_SEP ((MEM_START_CHUNKS + N_SMALL_CHUNKS) * (4UL * 1024UL))
#define MAX_N_REGIONS 16
#define SMALL_CHUNK_ALLOC 0
#define LARGE_CHUNK_ALLOC 1

/* Memory offsets */
#define NET_REGION_OFFS 0x20000000 // 512 MB net regions

/* PR */
#define PR_THRSH 32
#define PR_MIN_SLEEP_CMD 10
#define PR_MAX_SLEEP_CMD 50

#define PR_CTRL_START_MIDDLE 0x1
#define PR_CTRL_START_LAST 0x7
#define PR_CTRL_IRQ_CLR_PENDING 0x4
#define PR_STAT_DONE 0x1

#define MAX_PR_BUFF_NUM 128

/* IRQ types */
#define IRQ_DMA_OFFL 0
#define IRQ_DMA_SYNC 1
#define IRQ_INVLDT 2
#define IRQ_PFAULT 3
#define IRQ_NOTIFY 4
#define IRQ_RCNFG 5

/**
 * @brief Cdev
 * 
 */

/* Major number */
#define FPGA_MAJOR 0 // dynamic
#define PR_MAJOR 0 // dynamic

/* Name char */
#define MAX_CHAR_FDEV 32

/* MMAP */
#define MMAP_CTRL 0x0
#define MMAP_CNFG 0x1
#define MMAP_CNFG_AVX 0x2
#define MMAP_WB 0x3
#define MMAP_PR 0x100

/* IOCTL */
#define IOCTL_REGISTER_CPID _IOW('F', 1, unsigned long) // register pid
#define IOCTL_UNREGISTER_CPID _IOW('F', 2, unsigned long)
#define IOCTL_REGISTER_EVENTFD _IOW('F', 3, unsigned long) // register notify
#define IOCTL_UNREGISTER_EVENTFD _IOW('F', 4, unsigned long)
#define IOCTL_MAP_USER _IOW('F', 5, unsigned long) // map
#define IOCTL_UNMAP_USER _IOW('F', 6, unsigned long)
#define IOCTL_MAP_DMABUF _IOW('F', 7, unsigned long) // map
#define IOCTL_UNMAP_DMABUF _IOW('F', 8, unsigned long)
#define IOCTL_OFFLOAD_REQ _IOW('F', 9, unsigned long) // map
#define IOCTL_SYNC_REQ _IOW('F', 10, unsigned long)


#define IOCTL_SET_IP_ADDRESS _IOW('F', 11, unsigned long)
#define IOCTL_SET_MAC_ADDRESS _IOW('F', 12, unsigned long)
#define IOCTL_GET_IP_ADDRESS _IOR('F', 13, unsigned long)
#define IOCTL_GET_MAC_ADDRESS _IOR('F', 14, unsigned long)

#define IOCTL_READ_CNFG _IOR('F', 15, unsigned long) // cnfg
#define IOCTL_SHELL_XDMA_STATS _IOR('F', 16, unsigned long) // status xdma
#define IOCTL_SHELL_NET_STATS _IOR('F', 17, unsigned long) // status network

#define IOCTL_ALLOC_HOST_PR_MEM _IOW('P', 1, unsigned long) // pr alloc
#define IOCTL_FREE_HOST_PR_MEM _IOW('P', 2, unsigned long) //
#define IOCTL_RECONFIGURE_APP _IOW('P', 3, unsigned long) // reconfig app
#define IOCTL_RECONFIGURE_SHELL _IOW('P', 4, unsigned long) // reconfig shell
#define IOCTL_PR_CNFG _IOR('P', 5, unsigned long) // status xdma
#define IOCTL_STATIC_XDMA_STATS _IOR('P', 6, unsigned long) // status xdma

/* Hash */
#define USER_HASH_TABLE_ORDER 8
#define PID_HASH_TABLE_ORDER 8
#define PR_HASH_TABLE_ORDER 8
#define HMM_HASH_TABLE_ORDER 8

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

/* Signal notify */
#define SIGNTFY 23

/* Atomic flags */
#define FLAG_SET 1
#define FLAG_CLR 0

/* Stream flags */
#define CARD_ACCESS 0
#define HOST_ACCESS 1

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
    uint32_t probe; // 0
    uint32_t pr_ctrl; // 1
    uint32_t pr_stat; // 2
    uint32_t pr_cnt; // 3
    uint32_t pr_addr_low; // 4
    uint32_t pr_addr_high; // 5
    uint32_t pr_len; // 6
    uint32_t pr_eost; // 7
    uint32_t pr_eost_reset; // 8
    uint32_t pr_dcpl_set; // 9
    uint32_t pr_dcpl_clr; // 10
    uint32_t xdma_debug[N_STAT_REGS]; // 11+:
} __packed;

struct fpga_shell_cnfg_regs {
    uint64_t probe; // 0
    uint64_t n_chan; // 1
    uint64_t n_regions; // 2
    uint64_t ctrl_cnfg; // 3
    uint64_t mem_cnfg; // 4
    uint64_t pr_cnfg; // 5
    uint64_t rdma_cnfg; // 6
    uint64_t tcp_cnfg; // 7
    uint64_t pr_dcpl_app_set; // 8
    uint64_t pr_dcpl_app_clr; // 9
    uint64_t reserved_0[22];
    uint64_t net_ip; // 32
    uint64_t net_mac; // 33 
    uint64_t tcp_offs; // 34
    uint64_t rdma_offs; // 35
    uint64_t reserved_2[28];
    uint64_t xdma_debug[N_STAT_REGS]; // 64-96
    uint64_t net_debug[N_STAT_REGS]; // 96-128
} __packed;

/* FPGA dynamic config reg map */
struct fpga_cnfg_regs {
    uint64_t ctrl;
    uint64_t vaddr_rd;
    uint64_t ctrl_2;
    uint64_t vaddr_wr;
    uint64_t isr;
    uint64_t isr_pid;
    uint64_t isr_vaddr;
    uint64_t isr_len;
    uint64_t stat_sent[4];
    uint64_t stat_irq[4];
    uint64_t wback[4];
    uint64_t offl_ctrl;
    uint64_t offl_host_offs;
    uint64_t offl_card_offs;
    uint64_t offl_len;
    uint64_t offl_stat;
    uint64_t rsrvd_0[3];
    uint64_t sync_ctrl;
    uint64_t sync_host_offs;
    uint64_t sync_card_offs;
    uint64_t sync_len;
    uint64_t sync_stat;
    // Rest is user space
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

/* PID map */
struct cpid_entry {
     struct list_head list;
     int32_t cpid;
};

#ifdef HMM_KERNEL

/* HMM */
struct hpid_cpid_pages {
    struct hlist_node entry;
    struct list_head cpid_list;
    pid_t hpid;
    struct mmu_interval_notifier mmu_not;
    struct fpga_dev *d;
};

struct hmm_prvt_chunk {
	struct list_head list;
	struct resource *resource;
	struct dev_pagemap pagemap;
    struct fpga_dev *d;
};

struct hmm_prvt_info {
    struct list_head entry;
    int32_t cpid;
    bool huge;
    uint64_t card_address;
};

struct cyt_migrate {
    uint64_t vaddr;
    uint32_t n_pages;
    bool hugepages;
    int32_t cpid;
    pid_t hpid;
    struct vm_area_struct *vma;
};

#else

/* GUP */
struct hpid_cpid_pages {
    struct hlist_node entry;
    struct list_head cpid_list;
    pid_t hpid;
};

#endif

/* Mappings GUP */
struct user_pages {
    struct hlist_node entry;
    uint64_t vaddr;
    uint64_t n_pages;
    int32_t cpid;
    bool huge;
    int32_t host;
    
    // gup
    struct page **pages;

    // phys
    uint64_t *cpages;
    uint64_t *hpages;
};

struct desc_aligned {
    uint64_t vaddr;
    uint32_t n_pages;
    int32_t cpid;
    bool hugepages;
};

/* Reconfig pages */
struct pr_pages {
    struct hlist_node entry;
    uint64_t vaddr;
    pid_t pid;
    uint32_t crid;
    uint32_t n_pages;
    struct page **pages;
};

/* PID table */
extern struct hlist_head hpid_cpid_map[MAX_N_REGIONS][1 << (PID_HASH_TABLE_ORDER)];

/* User table */
extern struct hlist_head user_buff_map[MAX_N_REGIONS][N_CPID_MAX][1 << (USER_HASH_TABLE_ORDER)]; // main alloc

/* PR table */
extern struct hlist_head pr_buff_map[1 << (PR_HASH_TABLE_ORDER)];

/* Event Table */
extern struct eventfd_ctx *user_notifier[MAX_N_REGIONS][N_CPID_MAX];

/* HMM list */
#ifdef HMM_KERNEL
extern struct list_head migrated_pages[MAX_N_REGIONS][N_CPID_MAX];
#endif

/**
 * @brief Dev maps
 * 
 */
struct device_mapping {
    int device_id;
    unsigned int bus;
    unsigned int slot;
    struct list_head list;
};

/**
 * @brief Mem
 * 
 */

/* Pool chunks */
struct chunk {
    uint32_t id;
    bool used;
    struct chunk *next;
};


/* TLB order */
struct tlb_order {
    bool hugepage;
    uint64_t page_shift;
    uint64_t page_size;
    uint64_t page_mask;
    int assoc;
    
    uint64_t key_mask;
    uint64_t key_size;
    uint64_t tag_mask;
    uint64_t tag_size;
    uint64_t phy_mask;
    uint64_t phy_size;
};

/**
 * @brief page fault ISR struct
 * 
 */
struct fpga_irq_pfault {
    struct fpga_dev *d;
    uint64_t vaddr;
    uint32_t len;
    int32_t cpid;
    int32_t stream;
    bool wr;
    struct work_struct work_pfault;
};


/**
 * @brief User logic notify struct
 * 
 */
struct fpga_irq_notify {
    struct fpga_dev *d;
    int32_t cpid;
    int32_t notval;
    struct work_struct work_notify;
};

/**
 * @brief Dev structs
 * 
 */

/* Virtual FPGA device */
struct fpga_dev {
    int id; // identifier
    struct cdev cdev; // char device
    struct bus_drvdata *pd; // PCI device
    uint32_t ref_cnt;
    
    // Control region
    uint64_t fpga_phys_addr_ctrl;
    uint64_t fpga_phys_addr_ctrl_avx;

    // Writeback
    uint32_t *wb_addr_virt;
    uint64_t wb_phys_addr;

    // TLBs
    volatile uint64_t *fpga_lTlb; // large page TLB
    volatile uint64_t *fpga_sTlb; // small page TLB
    volatile struct fpga_cnfg_regs *fpga_cnfg; // config

    // IRQ
    spinlock_t irq_lock; 

    // PIDs
    spinlock_t pid_lock; 
    pid_t *pid_array;
    struct chunk *pid_chunks;
    int num_free_pid_chunks;
    struct chunk *pid_alloc;

    // MMU locks
    struct mutex mmu_lock;
    struct mutex offload_lock;
    struct mutex sync_lock;

    // Work queues
    //struct work_struct work_pfault;
    struct workqueue_struct *wqueue_pfault;
    //struct work_struct work_notify;
    struct workqueue_struct *wqueue_notify;

    // Waitqueues
    wait_queue_head_t waitqueue_invldt;
	wait_queue_head_t waitqueue_offload;
	wait_queue_head_t waitqueue_sync;
	atomic_t wait_invldt;
	atomic_t wait_offload;
    atomic_t wait_sync;

    // SVM memory
    spinlock_t sections_lock;
    struct list_head mem_sections;

    spinlock_t page_lock;
    struct page *free_pages;

    uint32_t n_pfaults;
};

/* Reconfiguration device */
struct pr_dev {
    struct cdev cdev; // char device
    struct bus_drvdata *pd; // PCI device

    // Locks
    spinlock_t irq_lock; 
    struct mutex rcnfg_lock;
    spinlock_t mem_lock;

    // Waitqueues
    wait_queue_head_t waitqueue_rcnfg;
	atomic_t wait_rcnfg;

    // Allocated buffers
    struct pr_pages curr_buff;
};

static const struct kobject cyt_kobj_empty;

/* PCI driver data */
struct bus_drvdata {

// PCI
    int dev_id;
    struct pci_dev *pci_dev;
    char vf_dev_name[MAX_CHAR_FDEV];
    char pr_dev_name[MAX_CHAR_FDEV];

    struct class *fpga_class;
    struct class *pr_class;
    int fpga_major;
    int pr_major;
    
    // BARs
    int regions_in_use;
    int got_regions;
    void *__iomem bar[CYT_BARS];
    unsigned long bar_phys_addr[CYT_BARS];
    unsigned long bar_len[CYT_BARS];

    // Engines
    int engines_num;
    struct xdma_engine *engine_h2c[MAX_NUM_CHANNELS]; // h2c engine
    struct xdma_engine *engine_c2h[MAX_NUM_CHANNELS]; // c2h engine

// ECI
    // I/O
    unsigned long io_phys_addr;
    unsigned long io_len;

    // FPGA device
    uint probe_stat;
    uint probe_shell;
    int n_fpga_chan;
    int n_fpga_reg;
    int en_avx;
    int en_wb;
    int en_strm;
    int en_mem;
    int en_pr;
    int en_rdma;
    int en_tcp;
    int en_net;
    int qsfp;
    uint32_t net_ip_addr;
    uint64_t net_mac_addr;
    uint64_t eost;
    volatile struct fpga_stat_cnfg_regs *fpga_stat_cnfg;
    volatile struct fpga_shell_cnfg_regs *fpga_shell_cnfg;
    struct fpga_dev *fpga_dev;

    // PR device
    struct pr_dev *pr_dev;

    // Sysfs
    struct kobject cyt_kobj;

    // TLB order
    struct tlb_order *stlb_order;
    struct tlb_order *ltlb_order;
    int32_t dif_order_page_shift;
    int32_t dif_order_page_size;
    int32_t dif_order_page_mask;
    int32_t n_pages_in_huge;

    // Locks
    spinlock_t stat_lock;
    spinlock_t card_lock;

    // IRQ
    int irq_count;
    int irq_line;
    int msix_enabled;
    struct msix_entry irq_entry[32];

    // Card memory
    struct chunk *lchunks;
    int num_free_lchunks;
    struct chunk *lalloc;

    struct chunk *schunks;
    int num_free_schunks;
    struct chunk *salloc;

    uint64_t card_huge_offs;
    uint64_t card_reg_offs;
};


#endif // Coyote device

