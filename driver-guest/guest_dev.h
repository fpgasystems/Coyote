#ifndef __GUEST_DEV_H__
#define __GUEST_DEV_H__

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/cdev.h>
#include <linux/pci.h>
#include <linux/version.h>
#include <linux/hashtable.h>
#include <asm/cacheflush.h>
#include <linux/hugetlb.h>

#define GUEST_MODULE_AUTHOR "Paul Dahlke <paul.dahlke@inf.ethz.ch>"
#define GUEST_MODULE_LICENSE "GPL"
#define GUEST_MODULE_DESCRIPTION "Coyote hypervisor guest driver"
#define DRV_NAME "coyote-guest"

#define COYOTE_DEBUG 0
#define MAX_USER_WORDS 32
#define INVALID_CPID 0xffffffffffffffff
#define N_CPID_MAX 64

/* Hash */
#define USER_HASH_TABLE_ORDER 8

/* MMAP Regions */
#define MMAP_CTRL 0x0
#define MMAP_CNFG 0x1
#define MMAP_CNFG_AVX 0x2
#define MMAP_WB 0x3
#define MMAP_BUFF 0x200
#define MMAP_PR 0x400
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

#define IOCTL_ARP_LOOKUP _IOW('D', 10, unsigned long) // arp lookup
#define IOCTL_SET_IP_ADDRESS _IOW('D', 11, unsigned long)
#define IOCTL_SET_MAC_ADDRESS _IOW('D', 12, unsigned long)
#define IOCTL_WRITE_CTX _IOW('D', 13, unsigned long)    // qp context
#define IOCTL_WRITE_CONN _IOW('D', 14, unsigned long)   // qp connection
#define IOCTL_SET_TCP_OFFS _IOW('D', 15, unsigned long) // tcp mem offsets

#define IOCTL_READ_CNFG _IOR('D', 32, unsigned long)       // status cnfg
#define IOCTL_XDMA_STATS _IOR('D', 33, unsigned long)      // status xdma
#define IOCTL_NET_STATS _IOR('D', 34, unsigned long)       // status network
#define IOCTL_READ_ENG_STATUS _IOR('D', 35, unsigned long) // status engines

#define IOCTL_NET_DROP _IOW('D', 36, unsigned long) // net dropper
#define IOCTL_TEST_INTERRUPT _IO('D', 37)

/* BAR2 offsets */
#define REGISTER_PID_OFFSET 0x00
#define UNREGISTER_PID_OFFSET 0x08
#define MAP_USER_OFFSET 0x10
#define UNMAP_USER_OFFSET 0x18
#define READ_CNFG_OFFSET 0x20
#define PUT_ALL_USER_PAGES 0x28
#define TEST_INTERRUPT_OFFSET 0x30

/* Interrupts */
#define NUM_USER_INTERRUPTS 1

/* LTLB values */
// TODO: read the config from the device to popoulate those
#define LTLB_PAGE_SHIFT 21
#define LTLB_PAGE_SIZE (1 << LTLB_PAGE_SHIFT)

/* Obtain the 32 most significant (high) bits of a 32-bit or 64-bit address */
#define HIGH_32(addr) ((addr >> 16) >> 16)
/* Obtain the 32 least significant (low) bits of a 32-bit or 64-bit address */
#define LOW_32(addr) (addr & 0xffffffffUL)

#if (COYOTE_DEBUG == 0)
#define dbg_info(...)
#else
#define dbg_info(fmt, ...) pr_info("%s():" fmt, \
                                   __func__, ##__VA_ARGS__)
#endif

/* FPGA dynamic config reg map */
struct fpga_cnfg_regs
{
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
struct fpga_cnfg_regs_avx
{
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

/* vfpga device */
struct vfpga
{
    struct pci_dev *pdev;
    struct cdev cdev;
    struct device *dev;
    pid_t *pid_array;

    spinlock_t cpid_lock;
    spinlock_t lock;

    uint64_t curr_offset;
    uint64_t n_pages;

    struct
    {
        volatile void __iomem *bar0;
        volatile void __iomem *bar2;
        volatile void __iomem *bar4;

        resource_size_t bar0_start, bar0_end;
        resource_size_t bar2_start, bar2_end;
        resource_size_t bar4_start, bar4_end;
    } pci_resources;

    struct msix_entry irq_entry[32];

    // Control region
    uint64_t fpga_phys_addr_ctrl;
    uint64_t fpga_phys_addr_ctrl_avx;

    struct fpga_cnfg_regs *fpga_cnfg;         // config
    struct fpga_cnfg_regs_avx *fpga_cnfg_avx; // config AVX

    int en_avx;
};

struct user_pages
{
    struct hlist_node entry;
    uint64_t vaddr;
    uint64_t n_pages;
    int32_t cpid;
    struct page **hpages;
};

struct hypervisor_map_notifier
{
    uint64_t npages;
    uint64_t len;
    uint64_t gva;
    uint64_t cpid;
    uint64_t dirtied;
    uint64_t is_huge;
    uint64_t gpas[0];
};

extern struct hlist_head user_sbuff_map[1 << (USER_HASH_TABLE_ORDER)];

extern struct class *guest_class;
extern struct vfpga vfpga;
extern dev_t devt;
extern struct file_operations fops;

#endif