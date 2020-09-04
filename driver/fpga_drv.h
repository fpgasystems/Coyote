#ifndef LYNX_DRV_H
#define LYNX_DRV_H

#include <linux/ioctl.h>
#include <linux/cdev.h>
#include <linux/pci.h>
#include <linux/types.h>
#include <linux/compiler.h>
#include <linux/hashtable.h>

/* Driver debug */
#define LYNX_DEBUG                              1    

/* Network setup */
#define BASE_IP_ADDR                            0x0B01D4D1
#define NODE_ID                                 0
#define N_TOTAL_NODES                           2

/* Debug print */
#if (LYNX_DEBUG == 0)
    #define dbg_info(...)
#else
    #define dbg_info(fmt, ...) pr_info("%s():" fmt, \
        __func__, ##__VA_ARGS__)
#endif

/* obtain the 32 most significant (high) bits of a 32-bit or 64-bit address */
#define PCI_DMA_H(addr)                 ((addr >> 16) >> 16)
/* obtain the 32 least significant (low) bits of a 32-bit or 64-bit address */
#define PCI_DMA_L(addr)                 (addr & 0xffffffffUL)

/* Driver info */
#define DRV_NAME                                "lynx_driver"
#define DEV_NAME                                "fpga"

/**
 * XDMA info
 */
#define MAX_NUM_BARS                            3
#define MAX_NUM_CHANNELS                        4
#define MAX_NUM_ENGINES                         (MAX_NUM_CHANNELS * 2)
#define MAX_USER_IRQS                           16
#define C2H_CHAN_OFFS                           0x1000
#define H2C_CHAN_OFFS                           0x0000
#define CHAN_RANGE                              0x100
#define SGDMA_OFFSET_FROM_CHANNEL               0x4000

/* Engine IDs */
#define XDMA_ID_H2C                             0x1fc0U
#define XDMA_ID_C2H                             0x1fc1U

/* Engine regs */
#define XDMA_ENG_IRQ_NUM                        (1)
#define XDMA_OFS_INT_CTRL                       (0x2000UL)
#define XDMA_OFS_CONFIG                         (0x3000UL)

/* Bits of the SG DMA control register */
#define XDMA_CTRL_RUN_STOP                      (1UL << 0)
#define XDMA_CTRL_IE_DESC_STOPPED               (1UL << 1)
#define XDMA_CTRL_IE_DESC_COMPLETED             (1UL << 2)
#define XDMA_CTRL_IE_DESC_ALIGN_MISMATCH        (1UL << 3)
#define XDMA_CTRL_IE_MAGIC_STOPPED              (1UL << 4)
#define XDMA_CTRL_IE_IDLE_STOPPED               (1UL << 6)
#define XDMA_CTRL_IE_READ_ERROR                 (0x1FUL << 9)
#define XDMA_CTRL_IE_DESC_ERROR                 (0x1FUL << 19)
#define XDMA_CTRL_NON_INCR_ADDR                 (1UL << 25)
#define XDMA_CTRL_POLL_MODE_WB                  (1UL << 26)

/* Bits of the SG DMA status register */
#define XDMA_STAT_BUSY                          (1UL << 0)
#define XDMA_STAT_DESC_STOPPED                  (1UL << 1)
#define XDMA_STAT_DESC_COMPLETED                (1UL << 2)
#define XDMA_STAT_ALIGN_MISMATCH                (1UL << 3)
#define XDMA_STAT_MAGIC_STOPPED                 (1UL << 4)
#define XDMA_STAT_FETCH_STOPPED                 (1UL << 5)
#define XDMA_STAT_IDLE_STOPPED                  (1UL << 6)
#define XDMA_STAT_READ_ERROR                    (0x1FUL << 9)
#define XDMA_STAT_DESC_ERROR                    (0x1FUL << 19)

/* Bits of the performance control register */
#define XDMA_PERF_RUN                           (1UL << 0)
#define XDMA_PERF_CLEAR                         (1UL << 1)
#define XDMA_PERF_AUTO                          (1UL << 2)

/* Polling */
#define WB_COUNT_MASK                           0x00ffffffUL
#define WB_ERR_MASK                             (1UL << 31)
#define POLL_TIMEOUT_SECONDS                    10
#define NUM_POLLS_PER_SCHED                     100

/**
 * Static layer
 */
#define BAR_XDMA_CONFIG                         0
#define BAR_FPGA_CONFIG                         1

/* FPGA static config */
#define FPGA_STAT_CNFG_OFFS                     0x0
#define FPGA_STAT_CNFG_SIZE                     32 * 1024   
#define EN_AVX_MASK                             0x1
#define EN_BYPASS_MASK                          0x2
#define EN_DDR_MASK                             0x1
#define N_DDR_CHAN_MASK                         0x3e

/**
 * Dynamic layer
 */

/* FPGA control regions */
#define FPGA_CTRL_SIZE                          256 * 1024
#define FPGA_CTRL_OFFS                          0x100000 
#define FPGA_CTRL_LTLB_SIZE                     FPGA_CTRL_SIZE / 4
#define FPGA_CTRL_LTLB_OFFS                     0x0
#define FPGA_CTRL_STLB_SIZE                     FPGA_CTRL_SIZE / 4
#define FPGA_CTRL_STLB_OFFS                     0x10000
#define FPGA_CTRL_USER_SIZE                     FPGA_CTRL_SIZE / 4
#define FPGA_CTRL_USER_OFFS                     0x20000
#define FPGA_CTRL_CNFG_SIZE                     FPGA_CTRL_SIZE / 4
#define FPGA_CTRL_CNFG_OFFS                     0x30000

#define FPGA_CTRL_CNFG_AVX_SIZE                 256 * 1024
#define FPGA_CTRL_CNFG_AVX_OFFS                 0x1000000

/* FPGA dynamic control config */
#define FPGA_CNFG_CTRL_IRQ_RESTART              0x100      

/* TODO: Maximum transfer size */
#define XDMA_TRANSFER_MAX_BYTES                 (8 * 1024 * 1024)

/* TLB */
#define TLB_VALID_MASK                          (1UL << 63)
#define TLB_CARD_MASK                           (1UL << 62)
#define TLB_VADDR_RANGE                         48
#define TLB_PADDR_RANGE                         40
#define TLB_VADDR_TAG_MASK                      0x3ffffffUL  

#define LTLB_ORDER                              6
#define STLB_ORDER                              10
#define LTLB_MAX_KEYS                           (1UL << LTLB_ORDER)
#define STLB_MAX_KEYS                           (1UL << STLB_ORDER)
#define LTLB_OFFS                               LTLB_MAX_KEYS // TODO:
#define STLB_OFFS                               STLB_MAX_KEYS // TODO:
#define LTLB_HASH_MASK                          ((1UL << LTLB_ORDER) - 1)
#define STLB_HASH_MASK                          ((1UL << STLB_ORDER) - 1)
#define LTLB_ASSOC_ENTRIES                      2
#define STLB_ASSOC_ENTRIES                      4
#define LTLB_PAGE_BITS                          21
#define STLB_PAGE_BITS                          12
#define LTLB_PADDR_SIZE                         (TLB_PADDR_RANGE - LTLB_PAGE_BITS)
#define STLB_PADDR_SIZE                         (TLB_PADDR_RANGE - STLB_PAGE_BITS)
#define LTLB_PADDR_MASK                         ((1UL << LTLB_PADDR_SIZE) - 1)
#define STLB_PADDR_MASK                         ((1UL << STLB_PADDR_SIZE) - 1)
#define LTLB_TAG_SIZE                           (TLB_VADDR_RANGE - LTLB_ORDER - LTLB_PAGE_BITS)
#define STLB_TAG_SIZE                           (TLB_VADDR_RANGE - STLB_ORDER - STLB_PAGE_BITS)
#define LTLB_TAG_MASK                           ((1UL << LTLB_TAG_SIZE) - 1)
#define STLB_TAG_MASK                           ((1UL << STLB_TAG_SIZE) - 1)

/* FPGA config commands */

/**
 * Cdev
 */

/* Major number */
#define FPGA_MAJOR                              0 // dynamic

/* Memory allocation */
#define LARGE_PAGE_ORDER                        9 // 2MB pages
#define LARGE_PAGE_SHIFT                        (LARGE_PAGE_ORDER + PAGE_SHIFT)
#define LARGE_PAGE_SIZE                         (PAGE_SIZE << LARGE_PAGE_ORDER)
#define MAX_BUFF_NUM                            1024 // Maximum number of huge pages on the host system
#define MAX_PR_BUFF_NUM                         1024 // Maximum number of huge pages on the host system
#define NUM_LARGE_CARD_PAGES                    4 * 1024

#define MAX_N_MAP_PAGES                         128

/* MMAP */
#define MMAP_CTRL                               0x0
#define MMAP_CNFG                               0x1
#define MMAP_CNFG_AVX                           0x2
#define MMAP_BUFF                               0x200
#define MMAP_PR                                 0x400

/* IOCTL */
#define IOCTL_ALLOC_HOST_USER_MEM               _IOR('D', 1, unsigned long)
#define IOCTL_FREE_HOST_USER_MEM                _IOR('D', 2, unsigned long)
#define IOCTL_ALLOC_HOST_PR_MEM                 _IOR('D', 3, unsigned long)
#define IOCTL_FREE_HOST_PR_MEM                  _IOR('D', 4, unsigned long)
#define IOCTL_MAP_USER                          _IOR('D', 5, unsigned long)
#define IOCTL_UNMAP_USER                        _IOR('D', 6, unsigned long)
#define IOCTL_RECONFIG_LOAD                     _IOR('D', 7, unsigned long)
#define IOCTL_ARP_LOOKUP                        _IOR('D', 8, unsigned long)
#define IOCTL_WRITE_CTX                         _IOR('D', 9, unsigned long)
#define IOCTL_WRITE_CONN                        _IOR('D', 10, unsigned long)
#define IOCTL_RDMA_STAT                         _IOR('D', 11, unsigned long)
#define IOCTL_READ_ENG_STATUS                   _IOR('D', 12, unsigned long)

/* Hash */
#define PR_HASH_TABLE_ORDER                     8
#define PR_BATCH_SIZE                           (2 * 1024 * 1024)

#define USER_HASH_TABLE_ORDER                   8

/* Max card pages */
#define N_LARGE_CHUNKS                          1024
#define N_SMALL_CHUNKS                          1024
#define MAX_N_REGIONS                           16
#define SMALL_CHUNK_ALLOC                       0
#define LARGE_CHUNK_ALLOC                       1
#define MEM_SEP                                 0x40000000

/* RDMA */
#define N_RDMA_STAT_REGS                        24

/**
 * Reg maps
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
    uint32_t rsrvd_3[9];  // padding

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
    uint32_t reserved_1[9];  // padding

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
    uint64_t probe;
    uint64_t n_chan;
    uint64_t n_regions;
    uint64_t ctrl_cnfg;
    uint64_t on_board;
    uint64_t pr;
    uint64_t rdma;
    uint64_t reserved_0[3];
    uint64_t pr_ctrl;
    uint64_t pr_stat;
    uint64_t pr_addr;
    uint64_t pr_len;
    uint64_t reserved_1[6];
    uint64_t rdma_ip;
    uint64_t rdma_boardnum;
    uint64_t rdma_arp;
    uint64_t qp_ctx[3];
    uint64_t qp_conn[3];
    uint64_t reserved_2[1];
    uint64_t rdma_debug[24];
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
    uint64_t tmr_stop;
    uint64_t tmr_rd;
    uint64_t tmr_wr;
    uint64_t stat_cmd_used_rd;
    uint64_t stat_cmd_used_wr;
    uint64_t stat_dma_rd;
    uint64_t stat_dma_wr;
    uint64_t stat_sent_rd;
    uint64_t stat_sent_wr;
    uint64_t stat_pfaults;
    // RDMA regs not used in the driver
} __packed;

/* FPGA dynamic config reg map */
struct fpga_cnfg_regs_avx {
    uint64_t ctrl[4];
    uint64_t vaddr_miss;
    uint64_t len_miss;
    uint64_t pf[2];
    uint64_t datapath_set[4];
    uint64_t datapath_clr[4];
    uint64_t tmr_stop[4];
    uint64_t tmr[4];
    uint64_t stat[4];
    // RDMA regs not used in the driver
} __packed;

/**
 * Structs 
 */

/* Engine descriptors */
struct xdma_sgdma_regs {
	uint32_t identifier;
	uint32_t reserved_1[31];	/* padding */

	/* bus address to first descriptor in Root Complex Memory */
	uint32_t first_desc_lo;
	uint32_t first_desc_hi;
	/* number of adjacent descriptors at first_desc */
	uint32_t first_desc_adjacent;
	uint32_t credits;
} __packed;


/* Engine struct */
struct xdma_engine {
    int channel; // egnine channel
    char *name; // engine name
    struct pci_drvdata *pd; // PCI device

    struct engine_regs *regs; // HW regs, control and status
    struct engine_sgdma_regs *sgdma_regs;	// SGDMA reg BAR offset

    // Config
    int running; // engine state
    int c2h; // c2h(write) or h2c(read)
    uint32_t status;
    
    int addr_align; // source/dest alignment in bytes 
    int len_granularity; // transfer length multiple 
    int addr_bits; // HW datapath address width 

    /* Members associated with polled mode support */
	uint8_t *poll_mode_addr_virt;	/* virt addr for descriptor writeback */
	uint64_t poll_mode_phys_addr;	/* bus addr for descriptor writeback */
};

/* Mapped user pages */
struct user_pages {
    struct hlist_node entry;
    uint64_t vaddr;
    uint64_t n_pages;
    struct page **hpages;
    uint64_t *cpages;
};
/* User tables */
struct hlist_head user_lbuff_map[MAX_N_REGIONS][1 << (USER_HASH_TABLE_ORDER)];
struct hlist_head user_sbuff_map[MAX_N_REGIONS][1 << (USER_HASH_TABLE_ORDER)];

/* Mapped large PR pages */
struct pr_pages {
    struct hlist_node entry;
    int reg_id;
    uint64_t vaddr;
    uint64_t n_pages;
    struct page **pages;
};
/* PR table */
struct hlist_head pr_buff_map[1 << (PR_HASH_TABLE_ORDER)];

/* Card chunks */
struct small_chunk {
    uint32_t id;
    struct small_chunk *next;
};

struct large_chunk {
    uint32_t id;
    struct large_chunk *next;
};


/* Virtual FPGA device */
struct fpga_dev {
    int id; // identifier
    int chan_id; // channel id
    struct cdev cdev; // char device
    struct pci_drvdata *pd; // PCI device
    struct pr_ctrl *prc;

    // Current task
    struct task_struct *curr_task;
    struct mm_struct *curr_mm;

    // Control region
    uint64_t fpga_phys_addr_ctrl; 
    uint64_t fpga_phys_addr_ctrl_avx;

    uint64_t *fpga_lTlb; // large page TLB
    uint64_t *fpga_sTlb; // small page TLB
    struct fpga_cnfg_regs *fpga_cnfg; // config
    struct fpga_cnfg_regs_avx *fpga_cnfg_avx; // config AVX

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

/* PR controller */
struct pr_ctrl {
    struct pci_drvdata *pd; // PCI device
    spinlock_t lock;

    // Engines
    struct xdma_engine *engine_h2c; // h2c engine
    struct xdma_engine *engine_c2h; // c2h engine

    // Allocated buffers
    struct pr_pages curr_buff;
};

/* PCI driver data */
struct pci_drvdata {
    struct pci_dev *pci_dev;

    // BARs
    int regions_in_use;
    int got_regions;
    void *__iomem bar[MAX_NUM_BARS];
    unsigned long bar_phys_addr[MAX_NUM_BARS];
    unsigned long bar_len[MAX_NUM_BARS];

    // Engines
    int engines_num;

    // FPGA static config
    int n_fpga_chan;
    int n_fpga_reg;
    int n_fpga_tot_reg;
    int en_avx;
    int en_bypass;
    int on_board;
    int pr_flow;
    int en_ddr;
    int n_ddr_chan;
    int en_rdma;
    struct fpga_stat_cnfg_regs *fpga_stat_cnfg;
    struct fpga_dev *fpga_dev; 
    spinlock_t stat_lock;

    // PR control
    struct pr_ctrl prc;

    // IRQ
    int irq_count;
    int irq_line;
    int msix_enabled;
    struct msix_entry irq_entry[32];

    // Card memory
    spinlock_t card_l_lock;
    struct large_chunk lchunks[N_LARGE_CHUNKS];
    int num_free_lchunks;
    struct large_chunk *lalloc;

    spinlock_t card_s_lock;
    struct small_chunk schunks[N_SMALL_CHUNKS];
    int num_free_schunks;
    struct small_chunk *salloc;
};

#endif