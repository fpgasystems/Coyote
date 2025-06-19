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

#ifndef _COYOTE_DEFS_H_
#define _COYOTE_DEFS_H_

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

// Driver arguments; see coyote_driver.c for details
extern char *ip_addr;
extern char *mac_addr;
extern long int eost;
extern bool en_hmm;

//////////////////////////////////////////////
//                CONSTANTS                //
////////////////////////////////////////////

/*
 * The following are constants used in the Coyote driver.
 * Most of these are self-explanatory and their purpose can be derived from their name and usage
 * Therefore, there are few comments, but mostly for constants that are not obvious
 * and need to be derived from other sources (e.g., XDMA specification)
 */

// Driver constants
#define COYOTE_DRIVER_NAME "coyote_driver"
#define DEV_FPGA_NAME "coyote_fpga"

// Debug prints
#define COYOTE_DEBUG 1
#if (COYOTE_DEBUG == 0)
    #define dbg_info(...)
#else
    #define dbg_info(fmt, ...) pr_info("%s():" fmt, __func__, ##__VA_ARGS__)
#endif

// Obtain the 32 most significant (high) bits of a 64-bit address
#define HIGH_32(addr) ((addr >> 16) >> 16)

// Obtain the 32 least significant (low) bits of a 64-bit address
#define LOW_32(addr) (addr & 0xffffffffUL)

// Obtain the 16 most significant (high) bits of a 32-bit address
#define HIGH_16(addr) (addr >> 16)

// Obtain the 16 least significant (low) bits of a 32-bit address */
#define LOW_16(addr) (addr & 0xffff)

// XDMA bars and engines
#define MAX_NUM_BARS 6
#define CYT_BARS 3                              // The XDMA can have up to 3 BARs, depending on interfaces (Table 3 in XDMA spec)
#define MAX_NUM_CHANNELS 3                      // At most 3 channels with the XDMA core; 
#define MAX_NUM_ENGINES (MAX_NUM_CHANNELS * 2)  // One engine per direction (H2C or C2H), hence 6 engines
#define MAX_USER_IRQS 16                        // Set during hardware configuration; see cr_pci.tcl
#define C2H_CHAN_OFFS 0x1000                    // Derived from Table 38 in XDMA specification [PG195 (v4.1)]
#define H2C_CHAN_OFFS 0x0000                    // Derived from Table 38 in XDMA specification [PG195 (v4.1)]
#define CHAN_RANGE 0x100                        // Derived from Table 38 in XDMA specification [PG195 (v4.1)]
#define SGDMA_OFFSET_FROM_CHANNEL 0x4000        // Derived from Table 38 in XDMA specification [PG195 (v4.1)]

/* 
 * H2C and C2H engine have unique IDs, which can be read from XDMA registers
 * However, these IDs should not change and are defined in the XDMA specification
 * Therefore, we define them here as constants and read the registers at driver
 * initialization, to ensure these indeed match. Values derived from
 * Tables 41 and 60 in the XDMA specification [PG195 (v4.1)] 
*/
#define XDMA_ID_H2C 0x1fc0U
#define XDMA_ID_C2H 0x1fc1U

/*
 * The memory offset for registers controlling interrupts
 * Address is derived from the XDMA specification [PG195 (v4.1)], Table 37 & 38
 */
#define XDMA_OFS_INT_CTRL (0x2000UL)

// XDMA control regisers; see Tables 42 and 61 in the XDMA specification [PG195 (v4.1)]
#define XDMA_CTRL_RUN_STOP (1UL << 0)
#define XDMA_CTRL_IE_DESC_STOPPED (1UL << 1)
#define XDMA_CTRL_IE_DESC_COMPLETED (1UL << 2)
#define XDMA_CTRL_NON_INCR_ADDR (1UL << 25)
#define XDMA_CTRL_POLL_MODE_WB (1UL << 26)

// XDMA statistic registers; used for debugging and can be queried using sysfs
#define N_STAT_REGS 32
#define N_XDMA_STAT_REGS 12
#define N_XDMA_STAT_CH_REGS (N_XDMA_STAT_REGS / MAX_NUM_CHANNELS)

/*
 * The mapping of control registers to BARs
 * Determined by the XDMA specification [PG195 (v4.1)], Table 3
 * In Coyote, we use the followinf interfaces (naming per specification):
 *      - AXI4-Lite for static layer, configuration
 *      - PCIe to DMA Bypass (AXI4-Full) for shell configuration
 * Additionally, there is always a BAR for controlling the XDMA core 
 * Hence, the BARs mapping in our case is determined per the 3rd in Table 3
 * For more details, refer to the static layer in hardware
 */
#define BAR_STAT_CONFIG 0   
#define BAR_XDMA_CONFIG 1  
#define BAR_SHELL_CONFIG 2 

// Static and shell config registers, offset and size
#define FPGA_STAT_CNFG_OFFS 0x0
#define FPGA_STAT_CNFG_SIZE (32UL * 1024UL)
#define FPGA_SHELL_CNFG_OFFS 0x0
#define FPGA_SHELL_CNFG_SIZE (32UL * 1024UL)

// Various masks to ensure the correct bits of a integer are written to a register with potentially smaller bit-width
#define EN_AVX_MASK 0x1
#define EN_AVX_SHIFT 0x0
#define EN_WB_MASK 0x8
#define EN_WB_SHIFT 0x3
#define TLB_S_ORDER_MASK 0xf0
#define TLB_S_ORDER_SHIFT 0x4
#define TLB_S_ASSOC_MASK 0xf00
#define TLB_S_ASSOC_SHIFT 0x8
#define TLB_L_ORDER_MASK 0xf000
#define TLB_L_ORDER_SHIFT 0xc
#define TLB_L_ASSOC_MASK 0xf0000
#define TLB_L_ASSOC_SHIFT 0x10
#define TLB_S_PG_SHFT_MASK 0x3f00000
#define TLB_S_PG_SHIFT_SHIFT 0x14
#define TLB_L_PG_SHFT_MASK 0xfc000000
#define TLB_L_PG_SHIFT_SHIFT 0x1a

#define EN_STRM_MASK 0x1
#define EN_STRM_SHIFT 0x0
#define EN_MEM_MASK 0x2
#define EN_MEM_SHIFT 0x1
#define EN_PR_MASK 0x1
#define EN_PR_SHIFT 0x0
#define EN_RDMA_MASK 0x1
#define EN_RDMA_SHIFT 0x0
#define EN_TCP_MASK 0x1
#define EN_TCP_SHIFT 0x0
#define QSFP_MASK 0x2
#define QSFP_SHIFT 0x1

// Total size of vFPGFA control region and its offset
#define VFPGA_CTRL_SIZE 256 * 1024
#define VFPGA_CTRL_OFFS 0x100000

// vFPGA large TLB registers
#define VFPGA_CTRL_LTLB_SIZE VFPGA_CTRL_SIZE / 4
#define VFPGA_CTRL_LTLB_OFFS 0x0

// vFPGA small TLB registers
#define VFPGA_CTRL_STLB_SIZE VFPGA_CTRL_SIZE / 4
#define VFPGA_CTRL_STLB_OFFS 0x10000

// vFPGA user registers (CSR), that can be parsed using the AXI4-Lite axi_crtl interface in the vFPGA
#define VFPGA_CTRL_USER_SIZE VFPGA_CTRL_SIZE / 4
#define VFPGA_CTRL_USER_OFFS 0x20000

// vFPGA config registers, as implemented in cnfg_slave.sv and cnfg_slave_avx.sv, respectively
#define VFPGA_CTRL_CNFG_SIZE VFPGA_CTRL_SIZE / 4
#define VFPGA_CTRL_CNFG_OFFS 0x30000

#define VFPGA_CTRL_CNFG_AVX_SIZE 256 * 1024
#define VFPGA_CTRL_CNFG_AVX_OFFS 0x1000000

/*
 * Various values that can be written to the above control registers
 * These values can be used to clear an interrupt, mark a page fault as completed etc.
 * For their use, more details can be found in cnfg_slave.sv and cnfg_slave_avx.sv
 */
#define FPGA_CNFG_CTRL_IRQ_CLR_PENDING 0x1
#define FPGA_CNFG_CTRL_IRQ_PF_RD_SUCCESS 0xa
#define FPGA_CNFG_CTRL_IRQ_PF_WR_SUCCESS 0xc
#define FPGA_CNFG_CTRL_IRQ_PF_RD_DROP 0x2
#define FPGA_CNFG_CTRL_IRQ_PF_WR_DROP 0x4
#define FPGA_CNFG_CTRL_IRQ_INVLDT 0x10
#define FPGA_CNFG_CTRL_IRQ_INVLDT_LAST 0x30
#define FPGA_CNFG_CTRL_IRQ_LOCK 0x50

// Interrupt vectors and constants
#define FPGA_RECONFIG_IRQ_VECTOR 15
#define FPGA_RECONFIG_IRQ_MASK 0x8000
#define FPGA_USER_IRQ_MASK 0x7fff

// DMA constants
#define DMA_THRSH 32
#define DMA_MIN_SLEEP_CMD 10
#define DMA_MAX_SLEEP_CMD 50
#define DMA_CTRL_START_MIDDLE 0x1
#define DMA_CTRL_START_LAST 0x7

// TLB constants
#define TLB_VADDR_RANGE 48
#define TLB_PADDR_RANGE 44
#define PID_SIZE 6
#define STRM_SIZE 2
#define MAX_N_MAP_PAGES 256  
#define MAX_N_MAP_HUGE_PAGES 256
#define MAX_SINGLE_DMA_SYNC 4   // 4 pages

// Card memory constants
#define MEM_START (256UL * 1024UL * 1024UL)
#define MEM_START_CHUNKS (MEM_START / (4UL * 1024UL))
#define N_SMALL_CHUNKS ((256UL * 1024UL) - MEM_START_CHUNKS)
#define N_LARGE_CHUNKS (1024UL * 1024UL)
#define MEM_SEP ((MEM_START_CHUNKS + N_SMALL_CHUNKS) * (4UL * 1024UL))
#define MAX_N_REGIONS 16

// Reconfiguration constants
#define RECONFIG_THRESHOLD 32
#define RECONFIG_MIN_SLEEP_CMD 10
#define RECONFIG_MAX_SLEEP_CMD 50

#define RECONFIG_CTRL_START_MIDDLE 0x1
#define RECONFIG_CTRL_START_LAST 0x7
#define RECONFIG_CTRL_IRQ_CLR_PENDING 0x4

#define MAX_RECONFIG_BUFF_NUM 128

// IRQ types, in order of imporance; see vfpga_isr.c for more details
#define IRQ_DMA_OFFL 0
#define IRQ_DMA_SYNC 1
#define IRQ_INVLDT 2
#define IRQ_PFAULT 3
#define IRQ_NOTIFY 4
#define IRQ_RCNFG 5

// Dynamic major numbers for the char devices
#define VFPGA_DEV_MAJOR 0
#define RECONFIG_DEV_MAJOR 0 

// Maximum number of character devices
#define MAX_CHAR_FDEV 32

// Offsets for memory-mapped regions
#define MMAP_CTRL 0x0
#define MMAP_CNFG 0x1
#define MMAP_CNFG_AVX 0x2
#define MMAP_WB 0x3
#define MMAP_RECONFIG 0x100

// vFPGA IOCTL calls; see vfpga_ops.c for more details
#define IOCTL_REGISTER_CTID _IOW('F', 1, unsigned long) 
#define IOCTL_UNREGISTER_CTID _IOW('F', 2, unsigned long)
#define IOCTL_REGISTER_EVENTFD _IOW('F', 3, unsigned long)
#define IOCTL_UNREGISTER_EVENTFD _IOW('F', 4, unsigned long)
#define IOCTL_MAP_USER_MEM _IOW('F', 5, unsigned long)
#define IOCTL_UNMAP_USER_MEM _IOW('F', 6, unsigned long)
#define IOCTL_MAP_DMABUF _IOW('F', 7, unsigned long)
#define IOCTL_UNMAP_DMABUF _IOW('F', 8, unsigned long)
#define IOCTL_OFFLOAD_REQ _IOW('F', 9, unsigned long)
#define IOCTL_SYNC_REQ _IOW('F', 10, unsigned long)
#define IOCTL_SET_IP_ADDRESS _IOW('F', 11, unsigned long)
#define IOCTL_SET_MAC_ADDRESS _IOW('F', 12, unsigned long)
#define IOCTL_GET_IP_ADDRESS _IOR('F', 13, unsigned long)
#define IOCTL_GET_MAC_ADDRESS _IOR('F', 14, unsigned long)
#define IOCTL_READ_SHELL_CONFIG _IOR('F', 15, unsigned long)
#define IOCTL_SHELL_XDMA_STATS _IOR('F', 16, unsigned long)
#define IOCTL_SHELL_NET_STATS _IOR('F', 17, unsigned long)
#define IOCTL_SET_NOTIFICATION_PROCESSED _IOR('F', 18, unsigned long)
#define IOCTL_GET_NOTIFICATION_VALUE _IOR('F', 19, unsigned long)

// Reconfiguration IOCTL calls; see reconfig_ops.c for more details
#define IOCTL_ALLOC_HOST_RECONFIG_MEM _IOW('P', 1, unsigned long)
#define IOCTL_FREE_HOST_RECONFIG_MEM _IOW('P', 2, unsigned long) 
#define IOCTL_RECONFIGURE_APP _IOW('P', 3, unsigned long) 
#define IOCTL_RECONFIGURE_SHELL _IOW('P', 4, unsigned long)
#define IOCTL_PR_CNFG _IOR('P', 5, unsigned long)
#define IOCTL_STATIC_XDMA_STATS _IOR('P', 6, unsigned long)

// Sizes of hash tables
#define USER_HASH_TABLE_ORDER 8
#define PID_HASH_TABLE_ORDER 8
#define RECONFIG_HASH_TABLE_ORDER 8
#define HMM_HASH_TABLE_ORDER 8

// Writeback buffer configuration
#define N_CTID_MAX 64
#define WB_BLOCKS 4
#define WB_SIZE (WB_BLOCKS * N_CTID_MAX * sizeof(uint32_t))
#define N_WB_PAGES ((WB_SIZE + PAGE_SIZE - 1) / PAGE_SIZE)

// Network statistics registers; can be queried for debugging using sysfs
#define N_NET_STAT_REGS 10

// Maximum number of user arguments for IOCTL calls passed from the user space
#define MAX_USER_ARGS 32

// Atomic flags (rather self-explanatory)
#define FLAG_SET 1
#define FLAG_CLR 0

// Streaming flags, analogous to the definition in the software; HOST = 1, CARD = 0
#define CARD_ACCESS 0
#define HOST_ACCESS 1

//////////////////////////////////////////////
//              REGISTERS MAPS             //
////////////////////////////////////////////

/*
 * The following structs refer to various register in hardware,
 * which are used in the driver to control the shell and the XDMA core
 * These registers are memory-mapped during driver set-up
 */

/// XDMA C2H and H2C engine registers; see Tables 40 and 59 in the XDMA specification [PG195 (v4.1)]
struct xdma_engine_regs {
    uint32_t id;
    uint32_t ctrl;
    uint32_t ctrl_w1s;
    uint32_t ctrl_w1c;
    uint32_t rsrvd_1[12];   // Padding based on the offset in the XDMA specification [PG195 (v4.1)]

    uint32_t status;
    uint32_t status_rc;
    uint32_t completed_desc_count;
    uint32_t alignments;
    uint32_t rsrvd_2[14];   // Padding based on the offset in the XDMA specification [PG195 (v4.1)]

    uint32_t poll_mode_wb_lo;
    uint32_t poll_mode_wb_hi;
    uint32_t interrupt_enable_mask;
    uint32_t interrupt_enable_mask_w1s;
    uint32_t interrupt_enable_mask_w1c;
    uint32_t rsrvd_3[9];   // Padding based on the offset in the XDMA specification [PG195 (v4.1)]

    uint32_t perf_ctrl;
    uint32_t perf_cyc_lo;
    uint32_t perf_cyc_hi;
    uint32_t perf_dat_lo;
    uint32_t perf_dat_hi;
    uint32_t perf_pnd_lo;
    uint32_t perf_pnd_hi;
} __packed;

/// XDMA interrupt registers; see Tables 78 in the XDMA specification [PG195 (v4.1)]
struct xdma_interrupt_regs {
    uint32_t id;
    uint32_t user_int_enable;
    uint32_t user_int_enable_w1s;
    uint32_t user_int_enable_w1c;
    uint32_t channel_int_enable;
    uint32_t channel_int_enable_w1s;
    uint32_t channel_int_enable_w1c;
    uint32_t reserved_1[9];  // Padding based on the offset in the XDMA specification [PG195 (v4.1)]

    uint32_t user_int_request;
    uint32_t channel_int_request;
    uint32_t user_int_pending;
    uint32_t channel_int_pending;
    uint32_t reserved_2[12];  // Padding based on the offset in the XDMA specification [PG195 (v4.1)]

    uint32_t user_msi_vector[8];
    uint32_t channel_msi_vector[8];
} __packed;

/// Static layer configuration registers; see static_slave.sv for more details
struct cyt_stat_cnfg_regs {
    uint32_t probe;
    uint32_t reconfig_ctrl;
    uint32_t reconfig_stat;
    uint32_t reconfig_cnt;
    uint32_t reconfig_addr_low;
    uint32_t reconfig_addr_high;
    uint32_t reconfig_len;
    uint32_t reconfig_eost;
    uint32_t reconfig_eost_reset;
    uint32_t reconfig_dcpl_set;
    uint32_t reconfig_dcpl_clr; 
    uint32_t xdma_debug[N_STAT_REGS];
} __packed;

/**
 * @brief Shell configuration registers; see shell_slave.sv for more details
 * These registers are not really used during run-time; instead these hold parameters
 * that were set during the hardware synthesis or driver insertion; e.g.,
 * the number of channels, regions, IP and MAC address etc., 
 * These are mostly used for debugging purposes using the sysfs functionality in the driver
 * Though the IP and MAC addresses can be set using the IOCTL calls
 */
struct cyt_shell_cnfg_regs {
    uint64_t probe;
    uint64_t n_chan;
    uint64_t n_regions;
    uint64_t ctrl_cnfg;
    uint64_t mem_cnfg;
    uint64_t pr_cnfg; 
    uint64_t rdma_cnfg;
    uint64_t tcp_cnfg; 
    uint64_t reconfig_dcpl_app_set;
    uint64_t reconfig_dcpl_app_clr;
    uint64_t reserved_0[22];
    uint64_t net_ip;
    uint64_t net_mac; 
    uint64_t tcp_offs; 
    uint64_t rdma_offs; 
    uint64_t reserved_2[28];
    uint64_t xdma_debug[N_STAT_REGS];
    uint64_t net_debug[N_STAT_REGS];
} __packed;

/**
 * @brief vFPGA control registers; see cnfg_slave.sv and cnfg_slave.avx for more details and register descriptions
 * These registers are heavily used in the driver to control individual vFPGAs
 * These drivers can be read from (e.g., reading from isr to determine the interrupt type)
 * or written to (e.g., to off_len, spefifying the length of the offload transfer)
 * These can also be used to set or clear certain control registers, e.g., once an interrupt is processed.
 */
struct vfpga_cnfg_regs {
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


//////////////////////////////////////////////
//                STRUCTS                  //
////////////////////////////////////////////

/*
 * The following structs abstract various components of the Coyote driver,
 * such as the bus driver data, the vFPGA device, the XDMA engine, and others.
 */

//// XDMA engine struct; abstracts a single XDMA engine in hardware with its registers, direction and status
struct xdma_engine {
    /// Channel ID: 0, 1, or 2 (XDMA supports up to 3 channels)
    int channel;           

    /// Engine name
    char *name;  

    /// Associated device structure, which can be used to obtain other Coyote variables
    struct bus_driver_data *bd_data; 

    /// Memory mapped registers; see definitions above
    struct xdma_engine_regs *regs;

    /// SGDMA registers; per XDMA specification [PG195 (v4.1)] --- SET, BUT UNUSED FOR NOW
    struct engine_sgdma_regs *sgdma_regs;

    // Engine state; set to true when initialized, false when removed
    int running; 

    /// Direction: C2H (writes) set to 1, H2C (reads) set to 0
    int c2h;     

    /// Source & destination address alignment in bytes --- SET, BUT UNUSED FOR NOW
    int addr_align;     

    /// Granularity of PCI transfers --- SET, BUT UNUSED FOR NOW
    int len_granularity;

    /// Hardware datapath address width --- SET, BUT UNUSED FOR NOW
    int addr_bits; 
};

struct ctid_entry {
    struct list_head list;
    int32_t ctid;
};

#ifdef HMM_KERNEL
struct hpid_ctid_pages {
    struct hlist_node entry;
    struct list_head ctid_list;
    pid_t hpid;
    struct mmu_interval_notifier mmu_not;
    struct vfpga_dev *d;
};

struct hmm_prvt_chunk {
	struct list_head list;
	struct resource *resource;
	struct dev_pagemap pagemap;
    struct vfpga_dev *d;
};

struct hmm_prvt_info {
    struct list_head entry;
    int32_t ctid;
    bool huge;
    uint64_t card_address;
};

struct cyt_migrate {
    uint64_t vaddr;
    uint32_t n_pages;
    bool hugepages;
    int32_t ctid;
    pid_t hpid;
    struct vm_area_struct *vma;
};

#else

/// Util struct, holds a list of Coyote thread IDs (CTIDs) associated with a host process ID (hpid)
struct hpid_ctid_pages {
    struct hlist_node entry;
    struct list_head ctid_list;
    pid_t hpid;
};

#endif

/**
 * @brief User pages struct
 *
 * Struct abstracting user pages (buffers) in the driver, containing the virtual address, number of pages, 
 * and other metadata as well as the pages themselves and physical addresses.
 * This struct is used throughout the driver to manage user buffers,
 * including mapping, unmapping, and migrating pages between host and card memory.
 */
struct user_pages {
    /// Hast table entry of this struct for easy lookups of user_buff_map in vfpga_gup.c
    struct hlist_node entry;

    /// Buffer starting virtual address
    uint64_t vaddr;

    /// Number of pages in the buffer
    uint64_t n_pages;

    /// Coyote thread ID associated with the buffer
    int32_t ctid;

    /// Set to true if the buffer is using huge pages (or can be coalesced to a huge page), false otherwise
    bool huge;

    /// Set to true if the buffer is currently residing on the host, false if not
    int32_t host;
    
    /// The actual pages holding the buffer
    struct page **pages;

    /** 
     * dma_buf represents a shared DMA buffer; acting as a reference to the memory that is shared between multiple devices
     * The buffer is allocated by a producer device (GPU) and exported for other devices to access (FPGA)
     */
    struct dma_buf *buf;

    /// dma_buf_attachment represents a device's (FPGA) attachment to some dma_buf
    struct dma_buf_attachment *dma_attach;

    /// scatter-gather table, which describes the physical memory layout of the dma buffer. 
    struct sg_table *sgt;

    /// Array of physical addresses on the card, one for each page in the pages array
    uint64_t *cpages;

    /// Array of physical addresses on the host, one for each page in the pages array, simply obtained by calling page_to_phys on each page
    uint64_t *hpages;
};

/**
 * @brief Aligned page fault descriptor
 *
 * Struct abstracting page fault information, including the virtual address, number of pages,
 * Coyote thread ID, and whether the pages are huge pages or not.
 * The virtual address is always aligned to the next page boundary.
 */
struct pf_aligned_desc {
    /// Aligned virtual address for which the page fault occurred
    uint64_t vaddr;

    /// Number of pages to be mapped in the page fault
    uint32_t n_pages;

    /// Associated Coyote thread ID
    int32_t ctid;

    /// True if the page-faulting buffer is using huge pages, false otherwise
    bool hugepages;
};

/**
 * @brief Reconfiguration buffer metadata
 *
 * Holds all the information needed to perform reconfiguration with this buffer,
 * where the buffer holds the partial bitstream to be loaded
 */
struct reconfig_buff_metadata {
    /// Hash table entry for easy lookups in reconfig_buffs_map
    struct hlist_node entry;

    /// Buffer starting virtual address
    uint64_t vaddr;

    /// Host process ID (PID) of the process that owns this buffer and triggers reconfiguration
    pid_t pid;

    /// Unique reconfiguration ID, as passed by the user from the software stack
    uint32_t crid;

    /// Number of pages in the buffer
    uint32_t n_pages;

    /// The actual pages holding the buffer
    struct page **pages;
};

/**
 * @brief DMABuff move notify struct
 *
 * Holds some meta-data about the attached DMA Buffer, such as its starting virtual address,
 * the Coyote thread ID (CTID) of the process that owns it, and the associated vFPGA device.
 */
struct dma_buf_move_notify_private {
    /// vFPGA device associated with this DMA buffer
    struct vfpga_dev *device;

    /// Buffer starting virtual address
    uint64_t vaddr;

    /// Associated Coyote thread ID (CTID)
    int ctid;
};

/// Table of Coyote thread IDs (CTIDs) mapped to host process IDs (hpid); per vFPGA
extern struct hlist_head hpid_ctid_map[MAX_N_REGIONS][1 << (PID_HASH_TABLE_ORDER)];

/// Table of buffers mapped to vFPGA TLBs; entries per vFPGA and Coyote thread ID
extern struct hlist_head user_buff_map[MAX_N_REGIONS][N_CTID_MAX][1 << (USER_HASH_TABLE_ORDER)]; 

/// Table of buffers used for reconfiguration
extern struct hlist_head reconfig_buffs_map[1 << (RECONFIG_HASH_TABLE_ORDER)];

/// The associated eventfd contexts for user interrupts; one per vFPGA and Coyote thread ID; see vfpga_uisr.c for more details
extern struct eventfd_ctx *user_notifier[MAX_N_REGIONS][N_CTID_MAX];

/// Interrupt locks, ensuring that only one interrupt (per vFPGA and cThread) is processed at a time and that the user space can safely read/write to the eventfd context
extern struct mutex user_notifier_lock[MAX_N_REGIONS][N_CTID_MAX];

/// Interrupt values used to pass values between vpfga_isr and vpfga_ops
extern int32_t interrupt_value[MAX_N_REGIONS][N_CTID_MAX];

#ifdef HMM_KERNEL
extern struct list_head migrated_pages[MAX_N_REGIONS][N_CTID_MAX];
#endif

/**
 * @brief Chunk struct
 * A utility struct that is used for list-like structures, each entry can have additonal information such as its unique ID and whether it is used or not
 * This is used to keep track of Coyote thread IDs (CTIDs) and PIDs in the driver, as well as for other purposes such as memory buffers
 */
 struct chunk {
    uint32_t id;
    bool used;
    struct chunk *next;
};

/**
 * @brief TLB metadata struct
 *
 * Holds all the information needed to maps a buffer to the vFPGA TLB,
 * including the page size and shift, associativity, and key/tag sizes etc.
 */
struct tlb_metadata {
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

/// A struct abstracting the page fault interrupt information from a vFPGA 
struct vfpga_irq_pfault {
    /// Corresponding vFPGA device
    struct vfpga_dev *device;

    /// Virtual address for which the page fault was issued
    uint64_t vaddr;

    /// Page fault buffer length
    uint32_t len;

    /// Coyote thread ID
    int32_t ctid;

    /// Stream: HOST (1) or CARD (0) memory
    int32_t stream;

    /// The page faulting operation: write (1) or read (0)
    bool wr;

    /// Asynchronous work struct
    struct work_struct work_pfault;
};

/// A struct abstracting the user interrupt (notification) interrupt information from a vFPGA 
struct vfpga_irq_notify {
    /// Corresponding vFPGA device
    struct vfpga_dev *device;
    
    /// Coyote thread ID
    int32_t ctid;
    
    /// Notification value, can be used to distinguish different types of user interrupts
    int32_t notification_value;
    
    /// Asynchronous work struct
    struct work_struct work_notify;
};

/**
 * @brief Virtual FPGA (vFPGA) char device structure
 *
 * Abstracts a single vFPGA device, holding information about the device ID,
 * control registers, memory, writeback regions etc.
 */
struct vfpga_dev {
    /// Unique ID of the vFPGA device
    int id;

    /// Associated character device structure for the vFPGA
    struct cdev cdev;

    /// Pointer to the bus driver data structure, which holds many low-level details about the shell (see below)
    struct bus_driver_data *bd_data;

    /// Number of times this vFPGA device has been opened; typically equal to the number of active Coyote threads associated with this vFPGA
    uint32_t ref_cnt;
    
    /// Physical address of the control region (vfpga_cnfg_regs) in the vFPGA 
    uint64_t vfpga_cnfg_phys_addr;

    /// Physical address of the AVX control region (vfpga_cnfg_regs) in the vFPGA 
    uint64_t vfpga_cnfg_avx_phys_addr;

    /// Virtual address of the writeback region
    uint32_t *wb_addr_virt;

    /// Physical address of the writeback region
    uint64_t wb_phys_addr;

    /// Pointer to the large page TLB registers in the vFPGA; memory mapped during driver initialization
    volatile uint64_t *fpga_lTlb;
    
    /// Pointer to the small page TLB registers in the vFPGA; memory mapped during driver initialization
    volatile uint64_t *fpga_sTlb;
    
    /// Pointer to the configuration registers in the FPGA; memory mapped during driver initialization
    volatile struct vfpga_cnfg_regs *cnfg_regs;

    /// Spinlock for IRQ handling; prevents multiple interrupts being processed simultaneously
    spinlock_t irq_lock; 

    /// Spinlock for process management; ensures only one Coyote thread is registered at a time, hence atomic Coyote thread IDs
    spinlock_t pid_lock; 

    /// Array that maps each Coyote thread ID (CTID) to a host process ID (hpid)
    pid_t *pid_array;

    /// Pointer to chunks used for Coyote threads; just an abstraction to keep track of active Coyote threads
    struct chunk *ctid_chunks;

    /// Number of free Coyote threads; for practical reasons there is a limit to the number of cThreads that can be registered for a vFPGA (N_CTID_MAX)
    int num_free_ctid_chunks;

    /// Pointer to chunks used for PID allocation; used in conjuction with the list of Coyote threads
    struct chunk *pid_alloc;

    /// Mutex for MMU operations (TLB mapping, unmapping, DMA Buff operations), ensuring atomic operations
    struct mutex mmu_lock;
    
    /// Mutex for off-load operations, ensuring atomic data movement between host and card memory
    struct mutex offload_lock;
    
    /// Mutex for sync operations, ensuring atomic data movement between host and card memory
    struct mutex sync_lock;

    /// Workqueue for handling page faults; allows for asynchronous processing of page faults
    struct workqueue_struct *wqueue_pfault;
    
    /// Workqueue for handling user notifications; allows for asynchronous processing of user interrupts (notifications)
    struct workqueue_struct *wqueue_notify;

    /// Waitqueue for TLB invalidation
    wait_queue_head_t waitqueue_invldt;
    
    /// Waitqueue for offload operations
    wait_queue_head_t waitqueue_offload;
    
    /// Waitqueue for synchronization operations
    wait_queue_head_t waitqueue_sync;

    /// Atomic flag when waiting for TLB invalidation to complete; cleared once invalidation is done
    atomic_t wait_invldt;
    
    /// Atomic flag when waiting for off-load to complete; cleared once off-load is done
    atomic_t wait_offload;

    /// Atomic flag when waiting for sync to complete; cleared once sync is done
    atomic_t wait_sync;

    #ifdef HMM_KERNEL
        spinlock_t sections_lock;
        struct list_head mem_sections;
        spinlock_t page_lock;
        struct page *free_pages;
    #endif 
};

/**
 * @brief Reconfig char device structure
 *
 * Abstracts the "reconfiguration" device, holding state variables, locks, and metadata
 * While there is no analogy in hardware (like there is with the vFPGA device),
 * the dynamic reconfiguration process is largel centered around this structure,
 * as it can be conviniently abstracted by typical chareacted device operations
 * that can then be called from the user space (cRcnfg.cpp).
 */
struct reconfig_dev {
    /// Associated character device structure for the reconfiguration device
    struct cdev cdev;

    /// Pointer to the bus driver data structure, which holds many low-level details about the shell (see below)
    struct bus_driver_data *bd_data; 

    /// Spinlock for IRQ handling; prevents multiple interrupts being processed simultaneously
    spinlock_t irq_lock; 

    /// Reconfiguration mutex, ensuring there is only ever one reconfiguration happening at a time
    struct mutex rcnfg_lock;

    /// Memory lock, ensuring no conditions occur when allocating buffers for reconfiguration
    spinlock_t mem_lock;

    /// Waitqueue for the reconfiguration
    wait_queue_head_t waitqueue_rcnfg;

    /// Atomic flag when waiting for reconfiguration to complete; cleared once reconfiguration is done
    atomic_t wait_rcnfg;

    /// The buffer (holding the partial bitstream) currently being used for dynamic reconfiguration
    struct reconfig_buff_metadata curr_buff;
};

/// Placeholder for an empty kobject, used to avoid NULL pointer dereferences when removing the sysfs
static const struct kobject cyt_kobj_empty;

/**
 * @brief Bus and driver data structure
 *
 * Holds low-level information about the Coyote driver and the underlying platform/hardware,
 * such as the PCI device, XDMA engines, memory-mapped registers, vFPGA and reconfiguration devices, and other metadata.
 * This structure is the one that is first initialized when the driver is loaded and exists
 * until the driver is removed. When the driver is first loaded it is associated with the PCI device,
 * which ensures its state and accessability throughout the driver lifecycle. This occurs in
 * pci_xdma.c, in the pci_probe() function. Many of the attributes here are not specific to a single vFPGA
 * or reconfiguration device; instead these are used througout Coyote. 
 * Additionally, this structure holds some underlying bus (e.g., PCI, ECI) variables and metadata. In the past
 * Enzian (ECI) used to be supported, but has since been depracated. 
 */
struct bus_driver_data {
    /// PCI device
    int dev_id;                             /* PCI device ID */
    struct pci_dev *pci_dev;                /* Associated PCI device structure */
    
    // Char devices metadata
    char vfpga_dev_name[MAX_CHAR_FDEV];     /* Template for vFPGA device names; each vFPGA device will have a unique name based on this template */
    char reconfig_dev_name[MAX_CHAR_FDEV];  /* Reconfiguration device name; used to create the reconfiguration character device */
    struct class *vfpga_class;              /* Class associated with the vFPGA devices (in this case vfpga_dev) */
    struct class *reconfig_class;           /* Class associated with the reconfig device (in this case reconfig_dev) */
    int vfpga_major;                        /* Major number for the vFPGA character device */
    int reconfig_major;                     /* Major number for the vFPGA character device */
    
    // Base address registers (BARs) variables
    int regions_in_use;                     /* Number of PCI regions in use; if 1 the driver is busy */
    int got_regions;                        /* Set to true if PCI regions could be obtained to be mapped */
    void *__iomem bar[CYT_BARS];            /* The BARs that are mapped to the kernel space*/
    unsigned long bar_phys_addr[CYT_BARS];  /* Physical address of each BAR */
    unsigned long bar_len[CYT_BARS];        /* Size (in bytes) of each BAR; determined by the XDMA configuration; see cr_pci.tcl for more details */

    // XDMA engines metadata
    int engines_num;                                    /* Number of XDMA engines in the device; typically 6 (3 C2H and 3 H2C); see pci_xdma.c for details */
    struct xdma_engine *engine_h2c[MAX_NUM_CHANNELS];   /*  Host-to-card (H2C) engines; see pci_xdma.c for details */
    struct xdma_engine *engine_c2h[MAX_NUM_CHANNELS];   /*  Card-to-host (C2H) engines; see pci_xdma.c for details */

    // Shell configuration options; set before hardware synthesis; see cmake/FindCoyoeHW.cmake for details
    uint probe_stat;                        /* Static layer probe */
    uint probe_shell;                       /* Shell layer probe */
    int n_fpga_chan;                        /* Number of XDMA channels */
    int n_fpga_reg;                         /* Number of vFPGA regions */
    int en_avx;                             /* Shell is built with AVX support */
    int en_wb;                              /* Shell is built with writeback support */
    int en_strm;                            /* Streaming interfaces from host are enabled */
    int en_mem;                             /* Memory interfaces from card are enabled */
    int en_pr;                              /* Partial reconfiguration (2nd level, app) is enabled */
    int en_rdma;                            /* Shell is built with RDMA support */
    int en_tcp;                             /* Shell is built with TCP/IP support */
    int en_net;                             /* True if either en_rdma or en_tcp is true */
    int qsfp;                               /* True if either en_rdma or en_tcp is true */
    uint32_t net_ip_addr;                   /* The FPGA's IP address */
    uint64_t net_mac_addr;                  /* The FPGA's MAC address */
    uint64_t eost;                          /* End of start-up time; see coyote_driver.c for details */

    /// Pointer to the static layer configuration registers; memory mapped during driver initialization
    volatile struct cyt_stat_cnfg_regs *stat_cnfg;

    /// Pointer to the shell configuration registers; memory mapped during driver initialization
    volatile struct cyt_shell_cnfg_regs *shell_cnfg;
    
    /*
     * The following are pointers to the vFPGA and reconfiguration devices.
     * While this may seem odd, since the vFPGA and reconfiguration devices
     * also hold a pointer to the bus driver data structure (cyclic reference)
     * However, they are for distinct purposes. The bus driver data structure is the one 
     * that is first set during the driver initialization and that exists while the driver is loaded.
     * Its primary purpose is to hold lower-level details and variables to control the hardware,
     * such as the PCI device, the XDMA engines etc, memory-mapped registers etc. However, since this
     * structure exists throughout the driver lifecycle, it is also used to hold pointers to the vFPGA and reconfiguration devices.
     * These devices are first initialized during the probe phase of the driver, and then released when the driver is removed.
     * On the other hand, the vFPGA and reconfiguration devices are used to hold higher-level details about the vFPGA and reconfiguration processes,
     * and are used to implement their respective file and memory operations; however, sometimes these may require access to the lower-level details
     * in the bus driver data structure, hence, the cyclic reference.
     */
    struct vfpga_dev *vfpga_dev;            /* Pointer to the associated vFPGA device(s) */
    struct reconfig_dev *reconfig_dev;      /* Pointer to the associated reconfiguration device */

    /// Sysfs; see coyote_sysfs.c for details
    struct kobject cyt_kobj;

    // TLB metatada
    struct tlb_metadata *stlb_meta;          /* Small TLB metadata */
    struct tlb_metadata *ltlb_meta;          /* Large TLB metadata */
    int32_t dif_order_page_shift;            /* Difference between lTlb and sTlb page shift */
    int32_t dif_order_page_size;             /* Difference between lTlb and sTlb page size */
    int32_t dif_order_page_mask;             /* Difference between lTlb and sTlb page mask */
    int32_t n_pages_in_huge;                 /* Number of (regular) pages in a huge page; e.g., 2MB huge page has 512 reg. pages */

    // Locks
    spinlock_t stat_lock;                    /* Static layer spinlock, ensuring atomic setting of IP and MAC address */
    spinlock_t card_lock;                    /* Card memory spinlock, ensuring atomic allocation of card memory */

    // IRQ
    int msix_enabled;                        /* True if MSI-X interrupts are supported on the target platform */
    struct msix_entry irq_entry[32];         /* MSI-X vectors */

    // Card memory
    struct chunk *lchunks;                   /* Array of available huge-page chunks */
    struct chunk *lalloc;                    /* Array of allocated huge-page chunks */
    int num_free_lchunks;                    /* Number of free huge-page chunks */

    struct chunk *schunks;                   /* Array of available regular-page chunks */
    struct chunk *salloc;                    /* Array of allocated regular-page chunks */
    int num_free_schunks;                    /* Number of free regular-page chunks */    

    uint64_t card_huge_offs;                 /* Address offset on card memory for huge pages */
    uint64_t card_reg_offs;                  /* Address offset on card memory for regular pages */

    // ENZIAN --- DEPRACATED 
    unsigned long io_phys_addr;
    unsigned long io_len;
};

#endif // _COYOTE_DEFS_H_
