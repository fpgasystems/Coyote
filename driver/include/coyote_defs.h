/*
 * Copyright (c) 2025,  Systems Group, ETH Zurich
 * All rights reserved.
 *
 * This file is part of the Coyote device driver for Linux.
 * Coyote can be found at: https://github.com/fpgasystems/Coyote
 *
 * This source code is free software; you can redistribute it and/or modify it
 * under the terms and conditions of the GNU General Public License,
 * version 2, as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 * The full GNU General Public License is included in this distribution in
 * the file called "COPYING". If not found, a copy of the GNU General Public  
 * License can be found <https://www.gnu.org/licenses/>.
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
#include <linux/dma-mapping.h>
#include <linux/netdevice.h>
#include <linux/etherdevice.h>
#include <linux/skbuff.h>
#include <linux/if_ether.h>
#include <linux/if_vlan.h>
#include <linux/ip.h>
#include <linux/tcp.h>
#include <linux/udp.h>
#include <linux/inet.h>
#include <linux/if_arp.h>
#include <linux/if_packet.h>
#include <rdma/ib_verbs.h>

// Driver arguments; see coyote_driver.c for details
#define MAX_FPGA_DEVICES 4
extern char *ip_addr[MAX_FPGA_DEVICES];
extern char *mac_addr[MAX_FPGA_DEVICES];
extern long int eost;
extern bool en_hmm;

//////////////////////////////////////////////
//                CONSTANTS                //
////////////////////////////////////////////

/*
 * The following are constants used in the Coyote driver.
 * Most of these are self-explanatory and their purpose can be derived from their name and usage
 * Therefore, there are few comments, but mostly for constants that are not obvious
 * and need to be derived from other sources (e.g., XDMA/QDMA specification)
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

// Bars; Coyote requests three PCIe bars (static, DMA regs, shell). These are 64-bit and therefore map to BAR0, BAR2 and BAR4 (per the XDMA/QDMA spec)
#define CYT_BARS 3
#define MAX_NUM_BARS 6

// XDMA channels and engines
#define XDMA_MAX_NUM_CHANNELS 3                             // At most 3 channels with the XDMA core; 
#define XDMA_MAX_NUM_ENGINES (XDMA_MAX_NUM_CHANNELS * 2)    // One engine per direction (H2C or C2H), hence 6 engines
#define XDMA_N_MAX_IRQ 16                                   // Set during hardware configuration; see cr_pci.tcl
#define XDMA_C2H_CHAN_OFFS 0x1000                           // Derived from Table 38 in XDMA specification [PG195 (v4.1)]
#define XDMA_H2C_CHAN_OFFS 0x0000                           // Derived from Table 38 in XDMA specification [PG195 (v4.1)]
#define XDMA_CHAN_RANGE 0x100                               // Derived from Table 38 in XDMA specification [PG195 (v4.1)]
#define XDMA_SGDMA_OFFSET_FROM_CHANNEL 0x4000               // Derived from Table 38 in XDMA specification [PG195 (v4.1)]

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

// QDMA constants
#define QDMA_N_QUEUES 512                             // Total number of queues (number may vary per device, but 512 is the absolute minimum on all devices)
#define QDMA_PR_QUEUE_IDX 0                           // Memory-mapped QDMA queue used for delivery of partial images during PR
#define QDMA_RD_QUEUE_START_IDX 1                     // Starting index of streaming queues for H2C operations; queues (QDMA_RD_QUEUE_START_IDX, QDMA_RD_QUEUE_START_IDX + QDMA_N_ACTIVE_QUEUES) can be used for reads
#define QDMA_WR_QUEUE_START_IDX (QDMA_N_QUEUES / 2)   // Starting index of streaming queues for C2H operations; queues (QDMA_WR_QUEUE_START_IDX, QDMA_WR_QUEUE_START_IDX + QDMA_N_ACTIVE_QUEUES) can be used for writes

// Number of enabled queues (per direction); QDMA_N_ACTIVE_QUEUES must be >= N_OUTSANDING * 3; otherwise, a write request will target an invalid queue
// Additionally, the maximum number of active C2H queues in bypass mode is 64, due to the limited number of prefetch tags (6 bits)
// Therefore, QDMA_N_ACTIVE_QUEUES cannot be set to more than 64
#define QDMA_N_ACTIVE_QUEUES 64

#define QDMA_N_MAX_IRQ 16   

// QDMA registers, see p301 of the QDMA specification from PG347 (v3.4) 
#define QDMA_CTX_CLR 0  
#define QDMA_CTX_WR 1
#define QDMA_CTX_RD 2
#define QDMA_CTX_INV 3

#define QDMA_CTX_CMD_REG 0x844
#define QDMA_CTX_N_DATA_REGS 8
#define QDMA_CTX_DATA_REG_START 0x804
#define QDMA_CTX_MASK_REG_START 0x824
#define QDMA_CXT_MASK_DEF_VAL 0xFFFFFFFF

#define QDMA_CTX_BUSY_VAL_DEAULT 0x00000000
#define QDMA_CTX_SEL_SHIFT 1
#define QDMA_CTX_SEL_MASK 0x0000000F
#define QDMA_CTX_OP_SHIFT 5
#define QDMA_CTX_OP_MASK 0x00000003
#define QDMA_CTX_QID_SHIFT 7
#define QDMA_CTX_QID_MASK 0x00001FFF

#define QDMA_CTXT_SELC_DEC_SW_C2H 0x0
#define QDMA_CTXT_SELC_DEC_SW_H2C 0x1
#define QDMA_CTXT_SELC_DEC_HW_C2H 0x2
#define QDMA_CTXT_SELC_DEC_HW_H2C 0x3
#define QDMA_CTXT_SELC_DEC_CR_C2H 0x4
#define QDMA_CTXT_SELC_DEC_CR_H2C 0x5
#define QDMA_CTXT_SELC_WRB 0x6
#define QDMA_CTXT_SELC_PFTCH 0x7
#define QDMA_CTXT_SELC_TIMER 0xb
#define QDMA_CTXT_SELC_HOST_PROFILE 0xa
#define QDMA_CTXT_SELC_FMAP 0xc

#define QDMA_H2C_MM_CTRL_REG 0x1204
#define QDMA_C2H_MM_CTRL_REG 0x1004

#define QDMA_C2H_PFCH_BYP_QID_REG 0x1408
#define QDMA_C2H_PFCH_BYP_TAG_REG 0x140c

#define QDMA_GLBL_VCH_HOST_PROFILE_REG 0x2c8
#define QDMA_GLBL_BRIDGE_HOST_PROFILE_REG 0x308
#define QDMA_DEFAULT_HOST_PROFILE_ID 0x0

/*
 * The mapping of control registers to BARs
 * Determined by the QDMA/XDMA specification
 * In Coyote, we use the following interfaces (naming per specification):
 *      - AXI4-Lite for static layer, configuration
 *      - PCIe to DMA Bypass (AXI4-Full) for shell configuration
 * Additionally, there is always a BAR for controlling the QDMA/XDMA core 
 */
#define BAR_STAT_CONFIG 0   
#define BAR_DMA_CONFIG 1  
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
#define N_STRM_AXI_MASK 0xfc
#define N_STRM_AXI_SHIFT 0x2
#define N_CARD_AXI_MASK 0x3f00
#define N_CARD_AXI_SHIFT 0x8
#define EN_BLOCK_MEM_MASK 0x4000
#define EN_BLOCK_MEM_SHIFT 0xe
#define EN_PR_MASK 0x1
#define EN_PR_SHIFT 0x0
#define EN_SHELL_PBLOCK_MASK 0x1
#define EN_SHELL_PBLOCK_SHIFT 0x0
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
#define FPGA_CNFG_CTRL_IRQ_CLR_PENDING 0x0001
#define FPGA_CNFG_CTRL_IRQ_PF_RD_SUCCESS 0x000a
#define FPGA_CNFG_CTRL_IRQ_PF_WR_SUCCESS 0x000c
#define FPGA_CNFG_CTRL_IRQ_PF_RD_DROP 0x0002
#define FPGA_CNFG_CTRL_IRQ_PF_WR_DROP 0x0004
#define FPGA_CNFG_CTRL_IRQ_INVLDT 0x0010
#define FPGA_CNFG_CTRL_IRQ_INVLDT_LAST 0x0030
#define FPGA_CNFG_CTRL_IRQ_LOCK 0x0050

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
#define MAX_N_REGIONS 16
#define BUFF_NEEDS_EXP_SYNC_RET_CODE 99

// Card memory constants
// On UltraScale+ devices, support up to 1024 * 1024 chunks of 4 KB
// accross the entire memory; i.e. 4 GB for regular and 4 GB for huge pages
// If more needed, change value and recompile driver. On UltraScale+ devices,
// there is no fine-grained control over the memory bank to which a buffer is
// allocated; that is N_MEM_BLOCKS is equal to 1
#ifdef PLATFORM_ULTRASCALE_PLUS
    #define N_MEM_BLOCKS 1
    #define MEM_BLOCK_SIZE 0    // doesn't matter; effectively unused in this case but needed to compile
    #define MEM_START (256UL * 1024UL * 1024UL)
    #define N_SMALL_CHUNKS (1024UL * 1024UL)
    #define N_LARGE_CHUNKS (1024UL * 1024UL)
#endif

// On Versal devices, users have fine-grained control over the HBM bank 
// to which a buffer is allocated; therefore N_SMALL_CHUNKS and N_LARGE_CHUNKS
// is per HBM pseudo-channel (PC). Currently, half of one PC port (256 MB) is allocated to
// regular pages and the other half of the PC port is allocated to huge pages.
// However, N_SMALL_CHUNKS and N_LARGE_CHUNKS can be changed as needed.
#ifdef PLATFORM_VERSAL
    #define N_MEM_BLOCKS 64                                 // 32 PCs with 2 ports each
    #define MEM_BLOCK_SIZE (512UL * 1024UL * 1024UL)        // 512 MB per port per PC
    #define MEM_START (256UL * 1024UL * 1024UL * 1024UL)
    #define N_SMALL_CHUNKS (64UL * 1024UL)
    #define N_LARGE_CHUNKS (64UL * 1024UL)
#endif

// Reconfiguration constants
#define RECONFIG_THRESHOLD 32
#define RECONFIG_MIN_SLEEP_CMD 10
#define RECONFIG_MAX_SLEEP_CMD 50

#define RECONFIG_CTRL_START_MIDDLE 0x1
#define RECONFIG_CTRL_START_LAST 0x7
#define RECONFIG_CTRL_IRQ_CLR_PENDING 0x4

#define MAX_RECONFIG_BUFF_NUM 128

// Use 2 MB "hugepages" for reconfiguration buffers
#define RECONFIG_BUFF_PAGE_SHIFT 21  
#define RECONFIG_BUFF_PAGE_SIZE (1UL << RECONFIG_BUFF_PAGE_SHIFT)

// IRQ types, in order of imporance; see vfpga_isr.c for more details
#define IRQ_DMA_OFFL 0
#define IRQ_DMA_SYNC 1
#define IRQ_INVLDT 2
#define IRQ_PFAULT 3
#define IRQ_NOTIFY 4
#define IRQ_RCNFG 5
#ifdef EN_SCENIC
#define IRQ_NET_PACKET_COALESCE 6
#endif

// Dynamic major numbers for the char devices
#define VFPGA_DEV_MAJOR 0
#define RECONFIG_DEV_MAJOR 0 

// Maximum number of character devices
#define MAX_CHAR_FDEV 32

// Offsets for memory-mapped regions
#define MMAP_WB 0x0
#define MMAP_CNFG 0x1
#define MMAP_CNFG_AVX 0x2
#define MMAP_CTRL 0x3
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
#define IOCTL_SHELL_HDMA_STATS _IOR('F', 16, unsigned long)
#define IOCTL_SHELL_NET_STATS _IOR('F', 17, unsigned long)
#define IOCTL_SET_NOTIFICATION_PROCESSED _IOR('F', 18, unsigned long)
#define IOCTL_GET_NOTIFICATION_VALUE _IOR('F', 19, unsigned long)

// Reconfiguration IOCTL calls; see reconfig_ops.c for more details
#define IOCTL_ALLOC_HOST_RECONFIG_MEM _IOW('P', 1, unsigned long)
#define IOCTL_FREE_HOST_RECONFIG_MEM _IOW('P', 2, unsigned long) 
#define IOCTL_RECONFIGURE_APP _IOW('P', 3, unsigned long) 
#define IOCTL_RECONFIGURE_SHELL _IOW('P', 4, unsigned long)
#define IOCTL_PR_CNFG _IOR('P', 5, unsigned long)
#define IOCTL_PR_WB_STATS _IOR('P', 6, unsigned long)

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
#define RD_WBACK 0
#define WR_WBACK 1

// Statistics registers
#define N_PR_WB_STAT_REGS 6             /* PR & WB host DMA channel statistics; implemented in pr_stats.sv */
#define N_HDMA_STAT_REGS 12             /* Shell (streaming data & sync/offload) host DMA channel statistics; implemented in dma_stats.sv */
#define N_HDMA_STAT_CH_REGS (N_HDMA_STAT_REGS / XDMA_MAX_NUM_CHANNELS)
#define N_NET_STAT_REGS 10              /* Network statistics */

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
    uint32_t hdma_debug[N_PR_WB_STAT_REGS];
    uint32_t qdma_pfch_tag;
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
    uint64_t shell_pblock_cnfg; 
    uint64_t rdma_cnfg;
    uint64_t tcp_cnfg; 
    uint64_t reconfig_dcpl_app_set;
    uint64_t reconfig_dcpl_app_clr;
    uint64_t reserved_0[21];
    uint64_t net_ip;
    uint64_t net_mac; 
    uint64_t tcp_offs; 
    uint64_t rdma_offs; 
    uint64_t reserved_2[28];
    uint64_t hdma_debug[N_HDMA_STAT_REGS];
    uint64_t reserved_3[32 - N_HDMA_STAT_REGS];
    uint64_t net_debug[N_NET_STAT_REGS];
    uint64_t reserved_4[32 - N_NET_STAT_REGS];
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

    // When writing to the ISR register, only the lower 16 bits are used for control
    // The upper 48 bits should remain unchanged when writing from the driver
    // These represent ISR metadata, such as ISR type, stream, RD/WR op etc.
    uint16_t isr_ctrl;
    uint16_t isr_meta_1;
    uint16_t isr_meta_2;
    uint16_t isr_meta_3;
    
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

/// QDMA queue struct; simply a placeholder for some values, so that these can be used later to release queues
struct qdma_queue {
    /// Queue ID
    int32_t qid;           

    // Queue state; set to true when initialized, false when removed
    bool running; 

    /// Direction: C2H (writes) set to 1, H2C (reads) set to 0
    bool c2h;     

    /// Memory mapped or streaming queue
    bool is_mm;

    /// Memory mapped channel for MM queues
    uint32_t mm_chn;
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

    /// Set to true if explicit synchronization (i.e. dma_sync_single_for_{device,cpu}) is needed for this buffer, false otherwise
    bool needs_explicit_sync;
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

    /// Array of physical addresses on the host, one for each page in the pages array
    uint64_t *hpages;
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

/// Table of Coyote thread IDs (CTIDs) mapped to host process IDs (hpid); per physical FPGA and vFPGA
extern struct hlist_head hpid_ctid_map[MAX_FPGA_DEVICES][MAX_N_REGIONS][1 << (PID_HASH_TABLE_ORDER)];

/// Table of buffers mapped to vFPGA TLBs; entries per physical FPGA, vFPGA and Coyote thread ID
extern struct hlist_head user_buff_map[MAX_FPGA_DEVICES][MAX_N_REGIONS][N_CTID_MAX][1 << (USER_HASH_TABLE_ORDER)];

/// Table of buffers used for reconfiguration; per physical FPGA
extern struct hlist_head reconfig_buffs_map[MAX_FPGA_DEVICES][1 << (RECONFIG_HASH_TABLE_ORDER)];

/// The associated eventfd contexts for user interrupts; one per physical FPGA, vFPGA and Coyote thread ID; see vfpga_uisr.c for more details
extern struct eventfd_ctx *user_notifier[MAX_FPGA_DEVICES][MAX_N_REGIONS][N_CTID_MAX];

/// Interrupt locks, ensuring that only one interrupt (per vFPGA and cThread) is processed at a time and that the user space can safely read/write to the eventfd context
extern struct mutex user_notifier_lock[MAX_FPGA_DEVICES][MAX_N_REGIONS][N_CTID_MAX];

/// Interrupt values used to pass values between vpfga_isr and vpfga_ops
extern int32_t interrupt_value[MAX_FPGA_DEVICES][MAX_N_REGIONS][N_CTID_MAX];

#ifdef HMM_KERNEL
extern struct list_head migrated_pages[MAX_FPGA_DEVICES][MAX_N_REGIONS][N_CTID_MAX];
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
 * @brief A partition of the card memory
 * For allocating card memory, this struct keeps track of the available memory,
 * allocated and free pages. On Versal platforms, users have fine-grained
 * control over the memory allocation, being able to specify what HBM "block" to store a buffer in
 * Therefore, on Versal devices, one instance of this struct is created for each HBM "block"
 * (pseudo-channel) is created. On UltraScale+, there is only instance of this struct, 
 * representing the entire memory 
 */
struct memory_partition {
    struct chunk *chunks;   /* Array of available chunks */
    struct chunk *alloc;    /* Array of allocated chunks */
    int32_t free_chunks;    /* Number of free chunks */
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

    /// Mutex for process management; ensures only one Coyote thread is registered at a time, hence atomic Coyote thread IDs
    struct mutex pid_lock;

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

    #ifdef EN_SCENIC
    // Pointer to the Linux network device structure
    struct net_device *ndev; 

    // NAPI structure for handling packet reception 
    struct napi_struct napi; 

    // For network device: Pointer to the config, control and writeback memory mapping 
    volatile uint64_t *vfpga_net_ctrl;
    volatile uint64_t *vfpga_net_cnfg;
    volatile uint32_t *vfpga_net_wb;

    // For network device: Counter of outstanding commands to not overflow the RX and TX queues in hardware
    uint64_t cmd_cnt; 

    // For network device: Pointer to the RX and TX buffer used for reception and transmission of packets 
    uint64_t vfpga_net_rx_buf_phys_addr;
    uint64_t *vfpga_net_rx_buf; 
    uint64_t vfpga_net_tx_buf_phys_addr; 
    uint64_t *vfpga_net_tx_buf; 

    // Global RX buffer index for state-keeping on the RX-polling path
    uint32_t rx_buf_head;

    // Counter for the number of times we circled around in the RX buffer 
    uint32_t rx_buf_cycle_cnt;

    // Indicator for which RX buffer location held the first packet for the current iperf server 
    uint32_t rx_buf_first_pkt_flag;

    // General counter for all iperf packets
    uint32_t iperf_pkt_cnt;

    // Indicator for which RX buffer location we get stuck on
    uint32_t rx_buf_stuck_flag;

    // TX ring indices: tx_head is the next slot to write into (mod TX_NUM_SLOTS),
    // tx_completed accumulates FPGA completion counts so slots can be safely recycled.
    uint32_t tx_head;
    uint32_t tx_completed;

    // Spinlock for synchronizing access to the transmit path
    spinlock_t tx_lock;

    // Network statistics
    struct rtnl_link_stats64 stats; 

    // Pointer to the one global scenic_rdma_device struct for RDMA operations
    struct scenic_rdma_device *scenic_rdma_dev;
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
 * such as the PCI device, QDMA/XDMA data, memory-mapped registers, vFPGA and reconfiguration devices, and other metadata.
 * This structure is the one that is first initialized when the driver is loaded and exists
 * until the driver is removed. When the driver is first loaded it is associated with the PCI device,
 * which ensures its state and accessability throughout the driver lifecycle. This occurs in
 * pci_xdma.c (or pci_qdma.c), in the pci_probe() function. Many of the attributes here are not specific to a single vFPGA
 * or reconfiguration device; instead these are used througout Coyote. 
 * Additionally, this structure holds some underlying bus (e.g., PCI, ECI) variables and metadata. In the past
 * Enzian (ECI) used to be supported, but has since been deprecated. 
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
    unsigned long bar_len[CYT_BARS];        /* Size (in bytes) of each BAR; determined by the QDMA/XDMA configuration; see cr_pci.tcl for more details */

    #ifdef PLATFORM_ULTRASCALE_PLUS
    // XDMA engines metadata
    int engines_num;                                    /* Number of XDMA engines in the device; typically 6 (3 C2H and 3 H2C); see pci_xdma.c for details */
    struct xdma_engine *engine_h2c[XDMA_MAX_NUM_CHANNELS];   /*  Host-to-card (H2C) engines; see pci_xdma.c for details */
    struct xdma_engine *engine_c2h[XDMA_MAX_NUM_CHANNELS];   /*  Card-to-host (C2H) engines; see pci_xdma.c for details */
    #endif

    #ifdef PLATFORM_VERSAL
    // QDMA queues metadata
    int num_queues;                                             /* Number of QDMA queues enabled */
    struct qdma_queue *queues[2 * QDMA_N_ACTIVE_QUEUES + 1];    /*  Array of enabled queues, both H2C and C2H */
    #endif
    
    // Shell configuration options; set before hardware synthesis; see cmake/FindCoyoeHW.cmake for details
    uint probe_stat;                        /* Static layer probe */
    uint probe_shell;                       /* Shell layer probe */
    int n_fpga_chan;                        /* Number of shell data/command channels */
    int n_fpga_reg;                         /* Number of vFPGA regions */
    int en_avx;                             /* Shell is built with AVX support */
    int en_wb;                              /* Shell is built with writeback support */
    int en_strm;                            /* Streaming interfaces from host are enabled */
    int en_mem;                             /* Memory interfaces from card are enabled */
    int n_host_axi;                         /* Number of host AXI interfaces */
    int n_card_axi;                         /* Number of card AXI interfaces */
    int en_block_mem;                       /* Versal only: HBM block implementation enabled */
    int en_pr;                              /* vFPGA partial reconfiguration is enabled */
    int en_shell_pblock;                    /* Shell dynamic reconfiguration is enabled */
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
     * such as the PCI device, the QDMA/XDMA data etc., memory-mapped registers etc. However, since this
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
    struct memory_partition *card_lblocks;   /* Available card memory blocks to store huge pages */
    struct memory_partition *card_sblocks;   /* Available card memory blocks to store regular pages */
    uint64_t card_huge_offs;                 /* Address offset on card memory for huge pages */
    uint64_t card_reg_offs;                  /* Address offset on card memory for regular pages */

    // ENZIAN --- DEPRECATED 
    // unsigned long io_phys_addr;
    // unsigned long io_len;

    #ifdef EN_SCENIC
    // RDMA device
    struct scenic_rdma_device *scenic_rdma_dev;
    #endif
};

#ifdef EN_SCENIC

#define SCENIC_NETDEV_VFPGA_ID 0

#define BUFFER_RING_SIZE 512
#define BUFFER_STRIDE 6144
#define RX_BUFF_SIZE BUFFER_RING_SIZE*BUFFER_STRIDE

#define TX_NUM_SLOTS 512
#define TX_BUFF_SIZE (TX_NUM_SLOTS * BUFFER_STRIDE)

/**
 * Coyote RDMA definitions
 */
#define SCENIC_MAX_NUM_QPS 500
#define SCENIC_MAX_NUM_CQS 8
#define SCENIC_MAX_NUM_WRS 16384
#define SCENIC_MAX_NUM_SGES 32

/** 
 * Copy over some constants from sw/include/cDefs.hpp for consistency while reimplementing parts of the controller logic for READ / WRITE ops 
*/

// Data source/destination stream in the vFPGA; e.g., axis_host_(recv|send). axis_card_(recv|send)
extern const unsigned long STRM_CARD;
extern const unsigned long STRM_HOST;
extern const unsigned long STRM_RDMA;
extern const unsigned long STRM_TCP;

// DMA and command constants
extern const int CMD_FIFO_DEPTH;
extern const int CMD_FIFO_THR;
extern const unsigned long MAX_TRANSFER_SIZE;

// AVX config registers, for more details see the HW implementation in cnfg_slave_avx.sv and struct vfpga_cnfg_regs
typedef enum {
    CTRL_REG = 0,
    ISR_REG = 4,
    STAT_REG_0 = 8,
    STAT_REG_1 = 12,
    WBACK_REG = 16,
    OFFLOAD_CTRL_REG = 20,
    OFFLOAD_STAT_REG = 24,
    SYNC_CTRL_REG = 28,
    SYNC_STAT_REG = 32,
    NET_ARP_REG = 36,
    RDMA_CTX_REG = 40,
    RDMA_CONN_REG = 44,
    TCP_OPEN_PORT_REG = 48,
    TCP_OPEN_PORT_STAT_REG = 52,
    TCP_OPEN_CONN_REG = 56,
    TCP_OPEN_CONN_STAT_REG = 60,
    STAT_DMA_REG = 64
} CnfgAvxRegs;

// Sleep time in nanoseconds for buszy wait loops; used while waiting for hardware to complete
extern const long SLEEP_TIME;

// Various Coyote operations that allow users to move data from/to host memory, FPGA memory and remote nodes
typedef enum {
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
} CoyoteOper;


// Various helper function to check the type of operation
static inline bool isLocalRead(CoyoteOper oper) { return oper == LOCAL_READ || oper == LOCAL_TRANSFER; }

static inline bool isLocalWrite(CoyoteOper oper) { return oper == LOCAL_WRITE || oper == LOCAL_TRANSFER; }

static inline bool isLocalSync(CoyoteOper oper) { return oper == LOCAL_OFFLOAD || oper == LOCAL_SYNC; }

static inline bool isRemoteRdma(CoyoteOper oper) { return oper == REMOTE_RDMA_WRITE || oper == REMOTE_RDMA_READ || oper == REMOTE_RDMA_SEND; }

static inline bool isRemoteRead(CoyoteOper oper) { return oper == REMOTE_RDMA_READ; }

static inline bool isRemoteWrite(CoyoteOper oper) { return oper == REMOTE_RDMA_WRITE; }

static inline bool isRemoteSend(CoyoteOper oper) { return oper == REMOTE_RDMA_SEND || oper == REMOTE_TCP_SEND; }

static inline bool isRemoteWriteOrSend(CoyoteOper oper) { return oper == REMOTE_RDMA_SEND || oper == REMOTE_RDMA_WRITE; }

static inline bool isRemoteTcp(CoyoteOper oper) { return oper == REMOTE_TCP_SEND; }


// Scatter-gather entry for sync and offload operations
struct syncSg {
    /// Buffer address to be synced/offloaded
    void* addr;

    /// Size of the buffer in bytes
    uint64_t len;
};
#define SYNC_SG_INIT ((struct syncSg){ .addr = NULL, .len = 0 })

// Scatter-gather entry for local operations (LOCAL_READ, LOCAL_WRITE, LOCAL_TRANSFER)
struct localSg {
    /// Buffer address
    void* addr;

    /// Buffer length in bytes
    uint32_t len;

    /// Buffer stream: HOST or CARD
    uint32_t stream;

    /// Target destination stream in the vFPGA; a value of i will use the to axis_(host|card)_(recv|send)[i] in the vFPGA
    uint32_t dest;
};
#define LOCAL_SG_INIT ((struct localSg){ .addr = NULL, .len = 0, .stream = STRM_HOST, .dest = 0 })

/** 
 * Scatter-gather entry for RDMA operations (REMOTE_READ, REMOTE_WRITE)
 * NOTE: No field for source/dest address, since these are defined when exchanging queue pair information
 * And, each cThread holds exactly one queue pair, so the source and destination addresses are always the same
 */
struct rdmaSg {
    /// Offset from the local buffer address; in case the buffer to be sent doesn't need to start from the exchanged virtual address
    uint64_t local_offs;

    /// Source buffer stream: HOST or CARD
    uint32_t local_stream;

    /// Target source stream in the vFPGA; a value of i will write pull data for the RDMA operation from axis_(host|card)_recv[i] in the vFPGA
    uint32_t local_dest;

    // Offset for the remote buffer to which the data is sent; in case the buffer to be sent doesn't need to start from the exchanged virtual address
    uint64_t remote_offs;

    /// Target destination stream; a value of i will write write data to axis_(host|card)_send[i] in the remote vFPGA
    uint32_t remote_dest;

    /// Lenght of the RDMA transfer, in bytes
    uint32_t len;
};
#define RDMA_SG_INIT ((struct rdmaSg){ .local_offs = 0, .local_stream = STRM_HOST, .local_dest = 0, .remote_offs = 0, .remote_dest = 0, .len = 0 })

// Scatter-gather entry for TCP operations (REMOTE_TCP_SEND)
struct tcpSg {
    // Session
    uint32_t stream;
    uint32_t dest;
    uint32_t len;
};
#define TCP_SG_INIT ((struct tcpSg){ .stream = STRM_TCP, .dest = 0, .len = 0 })

// Definitions for control register fields; used when posting commands to the vFPGA
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


/**
 * @brief Wrapper around the ib_device struct that allows to point back to the vFPGA device struct 
 * 
 * Wrapper class for the ib_device struct that allows to point back to the vFPGA device struct
 * This is useful when handling RDMA operations, as the ib_device struct is used extensively in
 * the RDMA verbs API
 */
struct vfpga_ib_device {
    // Actual ib_device struct 
    struct ib_device ib_dev;

    // Pointer back to the vFPGA device struct
    struct vfpga_dev *vfpga_dev;
}; 

/**
 * @brief Helper function that retrieves the vFPGA device struct from the ib_device struct
 */
static inline struct vfpga_dev *ibdev_to_vfpga_dev(struct ib_device *ib_dev) {
    struct vfpga_ib_device *vfpga_ib_dev = container_of(ib_dev, struct vfpga_ib_device, ib_dev);
    return vfpga_ib_dev->vfpga_dev;
}

/**
 * @brief Struct for a custom implementation of the RDMA memory region (MR). 
 */
struct vfpga_mr {
    // Underlying standard RDMA memory region 
    struct ib_mr ibmr;

    // Pointer to the vFPGA device associated with this MR
    uint32_t priv; 
};

// Struct that wraps around the ib_device struct for the RDMA driver
struct scenic_ib_device {
    // Actual ib_device struct
    struct ib_device ib_dev;
    // Pointer back to the scenic_rdma_device struct
    struct scenic_rdma_device *rdma_dev;
};

// New struct for the IB device (RDMA driver)
struct scenic_rdma_device {
    // Key: Contains the global ib_device struct (wrapper with return pointer to scenic_rdma_device)
    struct scenic_ib_device *scenic_ib_dev; 

    // Reference to the busdata struct
    struct bus_driver_data *bd_data;

    // Store the GUIDs in the scenic_rdma_device struct 
    uint64_t rdma_node_guid;
    uint64_t rdma_sys_image_guid;

    // Global tools for CQ management 
    struct ida cq_ida;  // Allocator for CQ Numbers
    spinlock_t global_cq_lock; // Global lock for CQ management

    // Global tools for QP management 
    struct ida qp_ida; // Allocator for QP Numbers
    spinlock_t global_qp_lock; // Global lock for QP management

    // List of all MRs created under this RDMA device, available to all QPs
    struct list_head mr_list;
}; 

// Helper function to get scenic_rdma_device from ib_device
static inline struct scenic_rdma_device *ibdev_to_scenic_rdma_dev(struct ib_device *ib_dev) {
    struct scenic_ib_device *scenic_ib_dev = container_of(ib_dev, struct scenic_ib_device, ib_dev);
    return scenic_ib_dev->rdma_dev;
}

// Struct that wraps around ib_qp struct for the RDMA driver
struct scenic_ib_qp {
    // Actual ib_qp struct
    struct ib_qp ibqp;
    // Pointer back to the scenic_rdma_device struct
    struct scenic_rdma_device *rdma_dev;
};

// Helper function to get scenic_rdma_device from ib_qp
static inline struct scenic_rdma_device *ibqp_to_scenic_rdma_dev(struct ib_qp *ibqp) {
    struct scenic_ib_qp *scenic_ib_qp = container_of(ibqp, struct scenic_ib_qp, ibqp);
    return scenic_ib_qp->rdma_dev;
}   

/**
 * @brief Struct for ib_ucontext 
 */
struct scenic_ucontext {
    // Underlying standard RDMA user context 
    struct ib_ucontext ibucontext;

    // Pointer to the vFPGA device associated with this user context
    struct list_head qp_list; 
    spinlock_t ctx_lock; 

    // FPGA virtualization hook 
    uint32_t hw_vmid; 
}; 

/**
 * @brief Helper function to cast between vfpga_ucontext and ib_ucontext structs
 */
static inline struct scenic_ucontext *ibucxt_to_scenic_ucontext(struct ib_ucontext *ibucontext) {
    return container_of(ibucontext, struct scenic_ucontext, ibucontext);
}

/**
 * @brief Struct for a custom implementation of the RDMA protection domain (PD). 
 */
struct scenic_pd {
    // Underlying standard RDMA protection domain 
    struct ib_pd ibpd;

    // Pointer to the vFPGA device associated with this PD
    uint32_t pdn; 
};

// Helper function to cast between scenic_pd and ib_pd structs
static inline struct scenic_pd *ibpd_to_scenic_pd(struct ib_pd *ibpd) {
    return container_of(ibpd, struct scenic_pd, ibpd);
}

/**
 * @brief Struct for a custom implementation of the RDMA completion queue (CQ). 
 */
struct scenic_cq {
    // Underlying standard RDMA completion queue 
    struct ib_cq ibcq; 

    // Just store the CQ number for easy access
    uint32_t cqn;
}; 

/**
 * @brief Helper function to cast between scenic_cq and ib_cq structs
 */
static inline struct scenic_cq *ibcq_to_scenic_cq(struct ib_cq *ibcq) {
    return container_of(ibcq, struct scenic_cq, ibcq);
}

/**
 * @brief Struct for a custom implementation of the RDMA queue pair (QP). 
 */
struct scenic_qp {
    // Underlying standard RDMA queue pair 
    struct ib_qp ibqp;

    // State of the QP
    enum ib_qp_state state;

    // Coyote thread ID associated with this QP
    uint32_t qpn;

    // Lock for protecting QP operations
    spinlock_t lock;
}; 

/**
 * @brief Helper function to cast between vfpga_qp and ib_qp structs
 */
static inline struct scenic_qp *ibqp_to_scenic_qp(struct ib_qp *ibqp) {
    return container_of(ibqp, struct scenic_qp, ibqp);
}

// Struct for a custom implementation of the RDMA memory region (MR).
struct scenic_mr {
    struct ib_mr ibmr;
    struct ib_umem *umem;
}; 

// Helper function to cast between scenic_mr and ib_mr structs
static inline struct scenic_mr *ibmr_to_scenic_mr(struct ib_mr *ibmr) {
    return container_of(ibmr, struct scenic_mr, ibmr);
}

// Helper function to get scenic_rdma_device from bus_driver_data
static inline struct scenic_rdma_device *bddata_to_scenic_rdma_dev(struct bus_driver_data *bd_data) {
    // Assuming scenic_rdma_device is stored in bd_data
    return bd_data->scenic_rdma_dev;
}

#endif


#endif // _COYOTE_DEFS_H_
