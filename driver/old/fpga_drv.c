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
//#include <linux/delay.h> /* usleep_range */

#include "fpga_drv.h"

/*
 ____       _
|  _ \ _ __(_)_   _____ _ __
| | | | '__| \ \ / / _ \ '__|
| |_| | |  | |\ V /  __/ |
|____/|_|  |_| \_/ \___|_|
*/

static int fpga_major = FPGA_MAJOR;
static struct class *fpga_class = NULL;

/*
 _   _ _   _ _
| | | | |_(_) |
| | | | __| | |
| |_| | |_| | |
 \___/ \__|_|_|
*/

static inline uint32_t build_u32(uint32_t hi, uint32_t lo) {
    return ((hi & 0xFFFFUL) << 16) | (lo & 0xFFFFUL);
}

static inline uint64_t build_u64(uint64_t hi, uint64_t lo) {
    return ((hi & 0xFFFFFFFULL) << 32) | (lo & 0xFFFFFFFFULL);
}

/* -- Declarations ----------------------------------------------------------------------- */

// fops
static int fpga_open(struct inode *inode, struct file *file);
static int fpga_release(struct inode *inode, struct file *file);
static int fpga_mmap(struct file *file, struct vm_area_struct *vma);
static long fpga_ioctl(struct file *file, unsigned int cmd, unsigned long arg);

// pid
int32_t register_pid(struct fpga_dev *d, pid_t pid);
static int unregister_pid(struct fpga_dev *d, int32_t cpid);

// dynamic reconfiguration
static int reconfigure(struct fpga_dev *d, uint64_t vaddr, uint64_t len);
static int alloc_pr_buffers(struct fpga_dev *d, unsigned long n_pages);
static int free_pr_buffers(struct fpga_dev *d, uint64_t vaddr);

// buffer allocation
static int card_alloc(struct fpga_dev *d, uint64_t *card_paddr, uint64_t n_pages, int type);
static void card_free(struct fpga_dev *d, uint64_t *card_paddr, uint64_t n_pages, int type);
static int alloc_user_buffers(struct fpga_dev *d, unsigned long n_pages, int32_t cpid);
static int free_user_buffers(struct fpga_dev *d, uint64_t vaddr, int32_t cpid);

// tlb operations
static void tlb_create_map(struct tlb_order *tlb_ord, uint64_t vaddr, uint64_t paddr_host, uint64_t paddr_card, int32_t cpid, uint64_t *entry);
static void tlb_create_unmap(struct tlb_order *tlb_ord, uint64_t vaddr, int32_t cpid, uint64_t *entry);
static void tlb_service_dev(struct fpga_dev *d, struct tlb_order *tlb_ord, uint64_t *entry, uint32_t n_pages);
static int tlb_get_user_pages(struct fpga_dev *d, uint64_t start, size_t count, int32_t cpid, pid_t pid);
static int tlb_put_user_pages(struct fpga_dev *d, uint64_t vaddr, int32_t cpid, int dirtied);
static int tlb_put_user_pages_all(struct fpga_dev *d, int dirtied);

// engine
static uint32_t get_engine_channel_id(struct engine_regs *regs);
static uint32_t get_engine_id(struct engine_regs *regs);
//static void engine_writeback_teardown(struct pci_drvdata *d, struct xdma_engine *engine);
static void engine_destroy(struct pci_drvdata *d, struct xdma_engine *engine);
static void remove_engines(struct pci_drvdata *d);
static void engine_alignments(struct xdma_engine *engine);
//static int engine_writeback_setup(struct pci_drvdata *d, struct xdma_engine *engine);
static struct xdma_engine *engine_create(struct pci_drvdata *d, int offs, int c2h, int channel);
static int probe_for_engine(struct pci_drvdata *d, int c2h, int channel);
static int probe_engines(struct pci_drvdata *d);
static uint32_t engine_status_read(struct xdma_engine *engine);

// interrupts
static irqreturn_t fpga_tlb_miss_isr(int irq, void *dev_id);
static void user_interrupts_enable(struct pci_drvdata *d, uint32_t mask);
static void user_interrupts_disable(struct pci_drvdata *d, uint32_t mask);
static uint32_t read_interrupts(struct pci_drvdata *d);
static uint32_t build_vector_reg(uint32_t a, uint32_t b, uint32_t c, uint32_t d);
static void write_msix_vectors(struct pci_drvdata *d);
static int msix_irq_setup(struct pci_drvdata *d);
static int irq_setup(struct pci_drvdata *d, struct pci_dev *pdev);
static void irq_teardown(struct pci_drvdata *d);
static int msix_capable(struct pci_dev *pdev, int type);
static int pci_check_msix(struct pci_drvdata *d, struct pci_dev *pdev);

// BARs
static int map_single_bar(struct pci_drvdata *d, struct pci_dev *pdev, int idx, int curr_idx);
static void unmap_bars(struct pci_drvdata *d, struct pci_dev *pdev);
static int map_bars(struct pci_drvdata *d, struct pci_dev *pdev);

// regions
static int request_regions(struct pci_drvdata *d, struct pci_dev *pdev);

// probe
static int pci_probe(struct pci_dev *pdev, const struct pci_device_id *id);
static void pci_remove(struct pci_dev *pdev);

/* -- Definitions ------------------------------------------------------------------------ */

/*
 _____
|  ___|__  _ __  ___
| |_ / _ \| '_ \/ __|
|  _| (_) | |_) \__ \
|_|  \___/| .__/|___/
          |_|
*/

/**
 * OPEN: Acquire a region
 */
static int fpga_open(struct inode *inode, struct file *file)
{
    int minor = iminor(inode);

    struct fpga_dev *d = container_of(inode->i_cdev, struct fpga_dev, cdev);
    BUG_ON(!d);

    dbg_info("fpga device %d acquired\n", minor);

    // set private data
    file->private_data = (void *)d;

    return 0;
}

/**
 * RELEASE: Release a region
 */
static int fpga_release(struct inode *inode, struct file *file)
{
    int minor = iminor(inode);

    struct fpga_dev *d = container_of(inode->i_cdev, struct fpga_dev, cdev);
    BUG_ON(!d);

    // unamp all user pages
    tlb_put_user_pages_all(d, 1);

    dbg_info("fpga device %d released\n", minor);

    return 0;
}

/**
 * MMAP: Control and buffers
 */
static int fpga_mmap(struct file *file, struct vm_area_struct *vma)
{
    int i;
    unsigned long vaddr;
    unsigned long vaddr_tmp;
    struct fpga_dev *d;
    struct pr_ctrl *prc;
    struct user_pages *new_user_buff;
    struct pr_pages *new_pr_buff;
    struct pci_drvdata *pd;
    uint64_t *map_array;

   
    d = (struct fpga_dev *)file->private_data;
    BUG_ON(!d);
    prc = d->prc;
    BUG_ON(!prc);
    pd = d->pd;
    BUG_ON(!pd);

    vaddr = vma->vm_start;

    vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);

    // map user ctrl region
    if (vma->vm_pgoff == MMAP_CTRL) {
        dbg_info("fpga dev. %d, memory mapping user ctrl region at %llx of size %x\n",
                 d->id, d->fpga_phys_addr_ctrl + FPGA_CTRL_USER_OFFS, FPGA_CTRL_USER_SIZE);
        if (remap_pfn_range(vma, vma->vm_start, (d->fpga_phys_addr_ctrl + FPGA_CTRL_USER_OFFS) >> PAGE_SHIFT,
                            FPGA_CTRL_USER_SIZE, vma->vm_page_prot)) {
            return -EIO;
        }
        return 0;
    }

    // map cnfg region
    if (vma->vm_pgoff == MMAP_CNFG) {
        dbg_info("fpga dev. %d, memory mapping config region at %llx of size %x\n",
                 d->id, d->fpga_phys_addr_ctrl + FPGA_CTRL_CNFG_OFFS, FPGA_CTRL_CNFG_SIZE);
        if (remap_pfn_range(vma, vma->vm_start, (d->fpga_phys_addr_ctrl + FPGA_CTRL_CNFG_OFFS) >> PAGE_SHIFT,
                            FPGA_CTRL_CNFG_SIZE, vma->vm_page_prot)) {
            return -EIO;
        }
        return 0;
    }

    // map cnfg AVX region
    if (vma->vm_pgoff == MMAP_CNFG_AVX) {
        dbg_info("fpga dev. %d, memory mapping config AVX region at %llx of size %x\n",
                 d->id, d->fpga_phys_addr_ctrl_avx, FPGA_CTRL_CNFG_AVX_SIZE);
        if (remap_pfn_range(vma, vma->vm_start, d->fpga_phys_addr_ctrl_avx >> PAGE_SHIFT,
                            FPGA_CTRL_CNFG_AVX_SIZE, vma->vm_page_prot)) {
            return -EIO;
        }
        return 0;
    }

    // map writeback
    if (vma->vm_pgoff == MMAP_WB) {
        set_memory_uc((uint64_t)d->wb_addr_virt, N_WB_PAGES);
        dbg_info("fpga dev. %d, memory mapping writeback regions at %llx of size %lx\n",
                 d->id, d->wb_phys_addr, WB_SIZE);
        if (remap_pfn_range(vma, vma->vm_start, (d->wb_phys_addr) >> PAGE_SHIFT,
                            WB_SIZE, vma->vm_page_prot)) {
            return -EIO;
        }
        return 0;
    }


    // map user buffers
    if (vma->vm_pgoff == MMAP_BUFF) {
        dbg_info("fpga dev. %d, memory mapping buffer\n", d->id);

        // aligned page virtual address
        vaddr = ((vma->vm_start + pd->ltlb_order->page_size - 1) >> pd->ltlb_order->page_shift) << pd->ltlb_order->page_shift;
        vaddr_tmp = vaddr;

        if (d->curr_user_buff.n_hpages != 0) {

            new_user_buff = kzalloc(sizeof(struct user_pages), GFP_KERNEL);
            BUG_ON(!new_user_buff);

            // Map entry
            new_user_buff->vaddr = vaddr;
            new_user_buff->huge = d->curr_user_buff.huge;
            new_user_buff->cpid = d->curr_user_buff.cpid;
            new_user_buff->n_hpages = d->curr_user_buff.n_hpages;
            new_user_buff->n_pages = d->curr_user_buff.n_pages;
            new_user_buff->hpages = d->curr_user_buff.hpages;
            new_user_buff->cpages = d->curr_user_buff.cpages;

            hash_add(user_lbuff_map[d->id], &new_user_buff->entry, vaddr);

            for (i = 0; i < d->curr_user_buff.n_hpages; i++) {
                // map to user space
                if (remap_pfn_range(vma, vaddr_tmp, page_to_pfn(d->curr_user_buff.hpages[i]),
                                    pd->ltlb_order->page_size, vma->vm_page_prot)) {
                    return -EIO;
                }
                vaddr_tmp += pd->ltlb_order->page_size;
            }

            // reset
            vaddr_tmp = vaddr;

             // map array
            map_array = (uint64_t *)kzalloc(d->curr_user_buff.n_hpages * 2 * sizeof(uint64_t), GFP_KERNEL);
            if (map_array == NULL) {
                dbg_info("map buffers could not be allocated\n");
                return -ENOMEM;
            }

            // fill mappings
            for (i = 0; i < d->curr_user_buff.n_hpages; i++) {
                tlb_create_map(pd->ltlb_order, vaddr_tmp, page_to_phys(d->curr_user_buff.hpages[i]), (pd->en_mem ? d->curr_user_buff.cpages[i] : 0), d->curr_user_buff.cpid, &map_array[2*i]);
                vaddr_tmp += pd->ltlb_order->page_size;
            }

            // fire
            tlb_service_dev(d, pd->ltlb_order, map_array, d->curr_user_buff.n_hpages);

            // free
            kfree((void *)map_array);

            // Current host buff empty
            d->curr_user_buff.n_hpages = 0;

            return 0;
        }
    }

    // map PR buffers
    if (vma->vm_pgoff == MMAP_PR)
    {
        dbg_info("fpga dev. %d, memory mapping PR buffer\n", d->id);

        // aligned page virtual address
        vaddr = ((vma->vm_start + pd->ltlb_order->page_size - 1) >> pd->ltlb_order->page_shift) << pd->ltlb_order->page_shift;
        vaddr_tmp = vaddr;

        if (prc->curr_buff.n_pages != 0) {
            // obtain PR lock
            spin_lock(&prc->lock);

            new_pr_buff = kzalloc(sizeof(struct pr_pages), GFP_KERNEL);
            BUG_ON(!new_pr_buff);

            // Map entry
            new_pr_buff->vaddr = vaddr;
            new_pr_buff->reg_id = d->id;
            new_pr_buff->n_pages = prc->curr_buff.n_pages;
            new_pr_buff->pages = prc->curr_buff.pages;

            hash_add(pr_buff_map, &new_pr_buff->entry, vaddr);

            for (i = 0; i < prc->curr_buff.n_pages; i++) {
                // map to user space
                if (remap_pfn_range(vma, vaddr_tmp, page_to_pfn(prc->curr_buff.pages[i]),
                                    pd->ltlb_order->page_size, vma->vm_page_prot)) {
                    return -EIO;
                }
                // next page vaddr
                vaddr_tmp += pd->ltlb_order->page_size;
            }

            // Current host buff empty
            prc->curr_buff.n_pages = 0;

            // release PR lock
            spin_unlock(&prc->lock);

            return 0;
        }
    }

    return -EINVAL;
}

/**
 * IOCTL: control and status
 */
static long fpga_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
    int ret_val, i;
    uint64_t tmp[MAX_USER_WORDS];
    uint64_t cpid;

    struct fpga_dev *d = (struct fpga_dev *)file->private_data;
    struct pci_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    switch (cmd) {

    // allocate host memory (2MB pages) - no hugepages support
    case IOCTL_ALLOC_HOST_USER_MEM:
        // read n_pages + cpid
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, 2 * sizeof(unsigned long));
        if (ret_val != 0) {
            pr_info("user data could not be coppied, return %d\n", ret_val);
        }
        else {
            ret_val = alloc_user_buffers(d, tmp[0], (uint32_t)tmp[1]);
            dbg_info("buff_num %lld, arg %lx\n", d->curr_user_buff.n_hpages, arg);
            if (ret_val != 0) {
                pr_info("user buffers could not be allocated\n");
            }
        }
        break;

    // free host memory (2MB pages) - no hugepages support
    case IOCTL_FREE_HOST_USER_MEM:
        // read vaddr + cpid
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, 2 * sizeof(unsigned long));
        if (ret_val != 0) {
            pr_info("user data could not be coppied, return %d\n", ret_val);
        }
        else {
            ret_val = free_user_buffers(d, tmp[0], (uint32_t)tmp[1]);
            dbg_info("user buffers freed\n");
        }
        break;

    // allocate host memory (2MB pages) - bitstream memory
    case IOCTL_ALLOC_HOST_PR_MEM:
        // read n_pages
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, sizeof(unsigned long));
        if (ret_val != 0) {
            pr_info("user data could not be coppied, return %d\n", ret_val);
        }
        else {
            ret_val = alloc_pr_buffers(d, tmp[0]);
            dbg_info("buff_num %lld, arg %lx\n", d->prc->curr_buff.n_pages, arg);
            if (ret_val != 0) {
                pr_info("PR buffers could not be allocated\n");
            }
        }
        break;

    // free host memory (2MB pages) - bitstream memory
    case IOCTL_FREE_HOST_PR_MEM:
        // read vaddr
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, sizeof(unsigned long));
        if (ret_val != 0) {
            pr_info("user data could not be coppied, return %d\n", ret_val);
        }
        else {
            ret_val = free_pr_buffers(d, tmp[0]);
            dbg_info("PR buffers freed\n");
        }
        break;

    // explicit mapping
    case IOCTL_MAP_USER:
        // read vaddr + len + cpid
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, 3 * sizeof(unsigned long));
        if (ret_val != 0) {
            pr_info("user data could not be coppied, return %d\n", ret_val);
        } else {
            cpid = (uint32_t)tmp[2];
            tlb_get_user_pages(d, tmp[0], tmp[1], (int32_t)tmp[2], d->pid_array[cpid]);
        }
        break;

    // explicit unmapping
    case IOCTL_UNMAP_USER:
        // read vaddr + cpid
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, 2 * sizeof(unsigned long));
        if (ret_val != 0) {
            pr_info("user data could not be coppied, return %d\n", ret_val);
        } else {
            dbg_info("unmapping user pages\n");
            tlb_put_user_pages(d, tmp[0], (int32_t)tmp[1], 1);
        }
        break;

    // register pid
    case IOCTL_REGISTER_PID:
        // read pid
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, sizeof(unsigned long));
        if (ret_val != 0) {
            pr_info("user data could not be coppied, return %d\n", ret_val);
        }
        else {
            spin_lock(&pd->stat_lock);

            cpid = (uint64_t)register_pid(d, tmp[0]);
            if (cpid == -1)
            {
                dbg_info("registration failed pid %lld\n", tmp[0]);
                return -1;
            }

            dbg_info("registration succeeded pid %lld, cpid %lld\n", tmp[0], cpid);
            ret_val = copy_to_user((unsigned long *)arg + 1, &cpid, sizeof(unsigned long));

            spin_unlock(&pd->stat_lock);
        }
        break;

    // unregister pid
    case IOCTL_UNREGISTER_PID:
        // read cpid
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, sizeof(unsigned long));
        if (ret_val != 0) {
            pr_info("user data could not be coppied, return %d\n", ret_val);
        }
        else {
            spin_lock(&pd->stat_lock);

            ret_val = unregister_pid(d, tmp[0]);
            if (ret_val == -1) {
                dbg_info("unregistration failed cpid %lld\n", tmp[0]);
                return -1;
            }

            spin_unlock(&pd->stat_lock);
            dbg_info("unregistration succeeded cpid %lld\n", tmp[0]);
        }
        break;

    // reconfiguration
    case IOCTL_RECONFIG_LOAD:
        // read vaddr + len
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, 2 * sizeof(unsigned long));
        if (ret_val != 0) {
            pr_info("user data could not be coppied, return %d\n", ret_val);
        } else {
            dbg_info("trying to obtain reconfig lock\n");
            spin_lock(&d->prc->lock);
            if (pd->en_avx)
                d->fpga_cnfg_avx->datapath_set[0] = 0x1;
            else
                d->fpga_cnfg->datapath_set = 0x1;

            ret_val = reconfigure(d, tmp[0], tmp[1]);
            if (ret_val != 0) {
                pr_info("reconfiguration failed, return %d\n", ret_val);
                return -1;
            }
            else {
                dbg_info("reconfiguration successfull\n");
            }

            dbg_info("releasing reconfig lock, coupling the design\n");
            if (pd->en_avx)
                d->fpga_cnfg_avx->datapath_clr[0] = 0x1;
            else
                d->fpga_cnfg->datapath_clr = 0x1;

            spin_unlock(&d->prc->lock);
        }
        break;

    // arp lookup
    case IOCTL_ARP_LOOKUP:
        if (pd->en_net_0 || pd->en_net_1) {
            ret_val = copy_from_user(&tmp, (unsigned long*) arg, sizeof(unsigned long));
            if (ret_val != 0) {
                pr_info("user data could not be coppied, return %d\n", ret_val);
            } else {
                dbg_info("arp lookup ...");
                spin_lock(&pd->stat_lock);

                for (i = 0; i < N_TOTAL_NODES; i++) {
                    if (i == NODE_ID)
                        continue;
                    tmp[0] ? (pd->fpga_stat_cnfg->net_1_arp = BASE_IP_ADDR_1 + i) : 
                        (pd->fpga_stat_cnfg->net_0_arp = BASE_IP_ADDR_0 + i);
                }

                spin_unlock(&pd->stat_lock);
            }
        } else {
            pr_info("network not enabled\n");
            return -1;
        }
        break;

    // set ip address
    case IOCTL_SET_IP_ADDRESS:
        if (pd->en_net_0 || pd->en_net_1) {
            ret_val = copy_from_user(&tmp, (unsigned long*) arg, 2 * sizeof(unsigned long));
            if (ret_val != 0) {
                pr_info("user data could not be coppied, return %d\n", ret_val);
            }
            else {
                spin_lock(&pd->stat_lock);

                // Set ip
                tmp[0] ? (pd->fpga_stat_cnfg->net_1_ip = tmp[1]) : 
                    (pd->fpga_stat_cnfg->net_0_ip = tmp[1]);

                spin_unlock(&pd->stat_lock);
                dbg_info("ip address changed to %llx\n", tmp[1]);
            }
        } else {
            pr_info("network not enabled\n");
            return -1;
        }

        break;

    // set board number
    case IOCTL_SET_BOARD_NUM:
        if (pd->en_net_0 || pd->en_net_1) {
            ret_val = copy_from_user(&tmp, (unsigned long*) arg, 2 * sizeof(unsigned long));
            if (ret_val != 0) {
                pr_info("user data could not be coppied, return %d\n", ret_val);
            } else {
                spin_lock(&pd->stat_lock);

                // Set board number
                tmp[0] ? (pd->fpga_stat_cnfg->net_1_boardnum = tmp[1]) :
                        (pd->fpga_stat_cnfg->net_0_boardnum = tmp[1]);

                spin_unlock(&pd->stat_lock);
                dbg_info("board number changed to %llx\n", tmp[1]);
            }
        } else {
            pr_info("network not enabled\n");
            return -1;
        }

        break;

    // rdma context
    case IOCTL_WRITE_CTX:
        if (pd->en_rdma_0 || pd->en_rdma_1) {
            ret_val = copy_from_user(&tmp, (unsigned long*) arg, 4 * sizeof(unsigned long));
            if (ret_val != 0) {
                dbg_info("user data could not be coppied, return %d\n", ret_val);
            } else {
                dbg_info("writing qp context ...");
                spin_lock(&pd->stat_lock);

                for (i = 0; i < 3; i++) {
                    tmp[0] ? (pd->fpga_stat_cnfg->rdma_1_qp_ctx[i] = tmp[i+1]) : 
                        (pd->fpga_stat_cnfg->rdma_0_qp_ctx[i] = tmp[i+1]);
                }

                spin_unlock(&pd->stat_lock);
            }
        }
        else {
            dbg_info("RDMA not enabled\n");
        }
        break;

    // rdma connection
    case IOCTL_WRITE_CONN:
        if (pd->en_rdma_0 || pd->en_rdma_1) {
            ret_val = copy_from_user(&tmp, (unsigned long*) arg, 4 * sizeof(unsigned long));
            if (ret_val != 0) {
                dbg_info("user data could not be coppied, return %d\n", ret_val);
            } else {
                dbg_info("writing qp connection ...");
                spin_lock(&pd->stat_lock);

                for (i = 0; i < 3; i++) {
                    tmp[0] ? (pd->fpga_stat_cnfg->rdma_1_qp_conn[i] = tmp[i+1]) :
                        (pd->fpga_stat_cnfg->rdma_0_qp_conn[i] = tmp[i+1]);
                }

                spin_unlock(&pd->stat_lock);
            }
        }
        else {
            dbg_info("RDMA not enabled\n");
        }
        break;

    // tcp offsets
    case IOCTL_SET_TCP_OFFS:
        if (pd->en_tcp_0 || pd->en_tcp_1) {
            ret_val = copy_from_user(&tmp, (unsigned long*) arg, 3 * sizeof(unsigned long));
            if (ret_val != 0) {
                dbg_info("user data could not be coppied, return %d\n", ret_val);
            } else {
                dbg_info("writing tcp mem offsets ...");
                spin_lock(&pd->stat_lock);

                for (i = 0; i < 2; i++) {
                    tmp[0] ? (pd->fpga_stat_cnfg->tcp_1_offs[i] = tmp[i+1]) : 
                        (pd->fpga_stat_cnfg->tcp_0_offs[i] = tmp[i+1]);
                }

                spin_unlock(&pd->stat_lock);
            }
        }
        else {
            dbg_info("TCP/IP not enabled\n");
        }
        break;

    // read config
    case IOCTL_READ_CNFG:
        tmp[0] = ((uint64_t)pd->n_fpga_chan << 32) | ((uint64_t)pd->n_fpga_reg << 48) |
                 ((uint64_t)pd->en_avx) | ((uint64_t)pd->en_bypass << 1) | ((uint64_t)pd->en_tlbf << 2) | ((uint64_t)pd->en_wb << 3) |
                 ((uint64_t)pd->en_strm << 4) | ((uint64_t)pd->en_mem << 5) | ((uint64_t)pd->en_pr << 6) | 
                 ((uint64_t)pd->en_rdma_0 << 16) | ((uint64_t)pd->en_rdma_1 << 17) | ((uint64_t)pd->en_tcp_0 << 18) | ((uint64_t)pd->en_tcp_1 << 19);
        dbg_info("reading config %llx\n", tmp[0]);
        ret_val = copy_to_user((unsigned long *)arg, &tmp, sizeof(unsigned long));
        break;

    // network status
    case IOCTL_NET_STATS:
        if (pd->en_net_0 || pd->en_net_1) {
            ret_val = copy_from_user(&tmp, (unsigned long*) arg, sizeof(unsigned long));
            if (ret_val != 0) {
                dbg_info("user data could not be coppied, return %d\n", ret_val);
            } else {
                dbg_info("retreiving network status for port %llx", tmp[0]);
                if(tmp[0]) {
                    for (i = 0; i < N_NET_STAT_REGS; i++) {
                        tmp[i] = pd->fpga_stat_cnfg->net_1_debug[i];
                    }
                } else {
                    for (i = 0; i < N_NET_STAT_REGS; i++) {
                        tmp[i] = pd->fpga_stat_cnfg->net_0_debug[i];
                    }
                }
                
                ret_val = copy_to_user((unsigned long *)arg, &tmp, N_NET_STAT_REGS * sizeof(unsigned long));
            }
        }
        else {
            dbg_info("network not enabled\n");
        }
        break;

    // engine status
    case IOCTL_READ_ENG_STATUS:
        dbg_info("fpga dev %d engine report\n", d->id);
        engine_status_read(d->engine_c2h);
        engine_status_read(d->engine_h2c);
        break;

    default:
        break;

    }

    return 0;
}

/* File operations */
/*
struct file_operations fpga_fops = {
    .owner = THIS_MODULE,
    .open = fpga_open,
    .release = fpga_release,
    .mmap = fpga_mmap,
    .unlocked_ioctl = fpga_ioctl,
};
*/

/**
 * @brief Register PID
 * 
 * @param d - vFPGA
 * @param pid - user PID
 * @return int32_t - Coyote PID
 */
int32_t register_pid(struct fpga_dev *d, pid_t pid)
{
    int32_t cpid;

    BUG_ON(!d);

    // lock
    spin_lock(&d->card_pid_lock);

    if(d->num_free_pid_chunks == 0) {
        dbg_info("not enough CPID slots\n");
        return -ENOMEM;
    }

    cpid = (int32_t)d->pid_alloc->id;
    d->pid_array[d->pid_alloc->id] = pid;
    d->pid_alloc = d->pid_alloc->next;

    // unlock
    spin_unlock(&d->card_pid_lock);

    return cpid;
}

/**
 * @brief Unregister Coyote PID
 * 
 * @param d - vFPGA
 * @param cpid - Coyote PID
 */
static int unregister_pid(struct fpga_dev *d, int32_t cpid)
{
    BUG_ON(!d);

    // lock
    spin_lock(&d->card_pid_lock);

    d->pid_chunks[cpid].next = d->pid_alloc;
    d->pid_alloc = &d->pid_chunks[cpid];

    // release lock
    spin_unlock(&d->card_pid_lock);

    return 0;
}

/**
 * @brief Allocate card memory
 * 
 * @param d - vFPGA
 * @param card_paddr - card physical address 
 * @param n_pages - number of pages to allocate
 * @param type - page size
 */
static int card_alloc(struct fpga_dev *d, uint64_t *card_paddr, uint64_t n_pages, int type)
{
    int i;
    struct pci_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;

    switch (type) {
    case 0: //
        // lock
        spin_lock(&pd->card_s_lock);

        if(pd->num_free_schunks < n_pages) {
            dbg_info("not enough free small card pages\n");
            return -ENOMEM;
        }

        for(i = 0; i < n_pages; i++) {
            card_paddr[i] = pd->salloc->id << STLB_PAGE_BITS;
            dbg_info("user card buffer allocated @ %llx device %d\n", card_paddr[i], d->id);
            pd->salloc = pd->salloc->next;
        }

        // release lock
        spin_unlock(&pd->card_s_lock);

        break;
    case 1:
        // lock
        spin_lock(&pd->card_l_lock);

        if(pd->num_free_lchunks < n_pages) {
            dbg_info("not enough free large card pages\n");
            return -ENOMEM;
        }

        for(i = 0; i < n_pages; i++) {
            card_paddr[i] = (pd->lalloc->id << LTLB_PAGE_BITS) + MEM_SEP;
            dbg_info("user card buffer allocated @ %llx device %d\n", card_paddr[i], d->id);
            pd->lalloc = pd->lalloc->next;
        }

        // release lock
        spin_unlock(&pd->card_l_lock);

        break;
    default: // TODO: Shared mem
        break;
    }

    return 0;
}

/**
 * @brief Free card memory
 * 
 * @param d - vFPGA
 * @param card_paddr - card physical address 
 * @param n_pages - number of pages to free
 * @param type - page size
 */
void card_free(struct fpga_dev *d, uint64_t *card_paddr, uint64_t n_pages, int type)
{
    int i;
    uint64_t tmp_id;
    struct pci_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    switch (type) {
    case 0: // small pages
        // lock
        spin_lock(&pd->card_s_lock);

        for(i = n_pages - 1; i >= 0; i--) {
            tmp_id = card_paddr[i] >> STLB_PAGE_BITS;
            pd->schunks[tmp_id].next = pd->salloc;
            pd->salloc = &pd->schunks[tmp_id];
        }

        // release lock
        spin_unlock(&pd->card_s_lock);

        break;
    case 1: // large pages
        // lock
        spin_lock(&pd->card_l_lock);

        for(i = n_pages - 1; i >= 0; i--) {
            tmp_id = (card_paddr[i] - MEM_SEP) >> LTLB_PAGE_BITS;
            pd->lchunks[tmp_id].next = pd->lalloc;
            pd->lalloc = &pd->lchunks[tmp_id];
        }

        // release lock
        spin_unlock(&pd->card_l_lock);

        break;
    default:
        break;
    }
}

/*
____________________ 
\______   \______   \
 |     ___/|       _/
 |    |    |    |   \
 |____|    |____|_  /
                  \/

*/

/**
 * @brief Reconfigure the vFPGA
 * 
 * @param d - vFPGA
 * @param vaddr - bitstream vaddr
 * @param len - bitstream length
 */
static int reconfigure(struct fpga_dev *d, uint64_t vaddr, uint64_t len)
{
    struct pr_ctrl *prc;
    struct pr_pages *tmp_buff;
    int i;
    uint64_t fsz_m;
    uint64_t fsz_r;
    uint64_t pr_bsize = PR_BATCH_SIZE;
    struct pci_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);
    prc = d->prc;
    BUG_ON(!prc);

    // lock
    spin_lock(&pd->prc_lock);

    hash_for_each_possible(pr_buff_map, tmp_buff, entry, vaddr) {
        if (tmp_buff->vaddr == vaddr && tmp_buff->reg_id == d->id) {
            // Reconfiguration
            fsz_m = len / pr_bsize;
            fsz_r = len % pr_bsize;
            dbg_info("bitstream full %lld, partial %lld\n", fsz_m, fsz_r);

            // full
            for (i = 0; i < fsz_m; i++) {
                dbg_info("page %d, phys %llx, len %llx\n", i, page_to_phys(prc->curr_buff.pages[i]), pr_bsize);
                pd->fpga_stat_cnfg->pr_addr = page_to_phys(tmp_buff->pages[i]);
                pd->fpga_stat_cnfg->pr_len = pr_bsize;
                if (fsz_r == 0 && i == fsz_m - 1)
                    pd->fpga_stat_cnfg->pr_ctrl = PR_CTRL_START_LAST;
                else
                    pd->fpga_stat_cnfg->pr_ctrl = PR_CTRL_START_MIDDLE;
            }

            // partial
            if (fsz_r > 0) {
                dbg_info("page %lld, phys %llx, len %llx\n", fsz_m, page_to_phys(prc->curr_buff.pages[fsz_m]), fsz_r);
                pd->fpga_stat_cnfg->pr_addr = page_to_phys(tmp_buff->pages[fsz_m]);
                pd->fpga_stat_cnfg->pr_len = fsz_r;
                pd->fpga_stat_cnfg->pr_ctrl = PR_CTRL_START_LAST;
                while ((pd->fpga_stat_cnfg->pr_stat & PR_STAT_DONE) != 0x1)
                    ndelay(100);
            } else {
                while ((pd->fpga_stat_cnfg->pr_stat & PR_STAT_DONE) != 0x1)
                    ndelay(100);
            }
        }
    }

    // unlock
    spin_unlock(&pd->prc_lock);

    return 0;
}

/**
 * @brief Allocate PR buffers
 * 
 * @param d - vFPGA
 * @param n_pages - number of pages to allocate
 */
static int alloc_pr_buffers(struct fpga_dev *d, unsigned long n_pages)
{
    int i;
    struct pr_ctrl *prc;
    struct pci_drvdata *pd;

    BUG_ON(!d);
    prc = d->prc;
    BUG_ON(!prc);
    pd = d->pd;
    BUG_ON(!pd);

    // obtain PR lock
    spin_lock(&prc->lock);

    if (prc->curr_buff.n_pages) {
        dbg_info("allocated PR buffers exist and are not mapped\n");
        return -1;
    }

    if (n_pages > MAX_PR_BUFF_NUM)
        prc->curr_buff.n_pages = MAX_PR_BUFF_NUM;
    else
        prc->curr_buff.n_pages = n_pages;

    prc->curr_buff.pages = kzalloc(n_pages * sizeof(*prc->curr_buff.pages), GFP_KERNEL);
    if (prc->curr_buff.pages == NULL) {
        return -ENOMEM;
    }

    dbg_info("allocated %lu bytes for page pointer array for %ld PR buffers @0x%p.\n",
             n_pages * sizeof(*prc->curr_buff.pages), n_pages, prc->curr_buff.pages);

    for (i = 0; i < prc->curr_buff.n_pages; i++) {
        prc->curr_buff.pages[i] = alloc_pages(GFP_ATOMIC, pd->ltlb_order->page_shift - PAGE_SHIFT);
        if (!prc->curr_buff.pages[i]) {
            dbg_info("PR buffer %d could not be allocated\n", i);
            goto fail_alloc;
        }

        dbg_info("PR buffer allocated @ %llx \n", page_to_phys(prc->curr_buff.pages[i]));
    }

    // release PR lock
    spin_unlock(&prc->lock);

    return 0;
fail_alloc:
    while (i)
        __free_pages(prc->curr_buff.pages[--i], pd->ltlb_order->page_shift - PAGE_SHIFT);
    // release PR lock
    spin_unlock(&prc->lock);
    return -ENOMEM;
}

/**
 * @brief Free PR pages
 * 
 * @param d - vFPGA
 * @param vaddr - virtual address
 */
static int free_pr_buffers(struct fpga_dev *d, uint64_t vaddr)
{
    int i;
    struct pr_pages *tmp_buff;
    struct pr_ctrl *prc;
    struct pci_drvdata *pd;

    BUG_ON(!d);
    prc = d->prc;   
    BUG_ON(!prc);
    pd = d->pd;
    BUG_ON(!pd);

    // obtain PR lock
    spin_lock(&prc->lock);

    hash_for_each_possible(pr_buff_map, tmp_buff, entry, vaddr) {
        if (tmp_buff->vaddr == vaddr && tmp_buff->reg_id == d->id) {

            // free pages
            for (i = 0; i < tmp_buff->n_pages; i++) {
                if (tmp_buff->pages[i])
                    __free_pages(tmp_buff->pages[i], pd->ltlb_order->page_shift - PAGE_SHIFT);
            }

            kfree(tmp_buff->pages);

            // Free from hash
            hash_del(&tmp_buff->entry);
        }
    }

    // obtain PR lock
    spin_unlock(&prc->lock);

    return 0;
}


/**
 * @brief ALlocate user buffers (used in systems without hugepage support)
 * 
 * @param d - vFPGA
 * @param n_pages - number of pages to allocate
 * @param cpid - Coyote PID
 */
static int alloc_user_buffers(struct fpga_dev *d, unsigned long n_pages, int32_t cpid)
{
    int i, ret_val = 0;
    struct pci_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    if (d->curr_user_buff.n_hpages) {
        dbg_info("allocated user buffers exist and are not mapped\n");
        return -1;
    }

    // check host
    if (n_pages > MAX_BUFF_NUM) 
        d->curr_user_buff.n_hpages = MAX_BUFF_NUM;
    else
        d->curr_user_buff.n_hpages = n_pages;

    // check card
    if(pd->en_mem)
        if (d->curr_user_buff.n_hpages > pd->num_free_lchunks)
            return -ENOMEM;

    d->curr_user_buff.huge = true;
    d->curr_user_buff.cpid = cpid;

    // alloc host
    d->curr_user_buff.hpages = kzalloc(d->curr_user_buff.n_hpages * sizeof(*d->curr_user_buff.hpages), GFP_KERNEL);
    if (d->curr_user_buff.hpages == NULL) {
        return -ENOMEM;
    }
    dbg_info("allocated %llu bytes for page pointer array for %lld user host buffers @0x%p.\n",
             d->curr_user_buff.n_hpages * sizeof(*d->curr_user_buff.hpages), d->curr_user_buff.n_hpages, d->curr_user_buff.hpages);

    for (i = 0; i < d->curr_user_buff.n_hpages; i++) {
        d->curr_user_buff.hpages[i] = alloc_pages(GFP_ATOMIC, pd->ltlb_order->page_shift - PAGE_SHIFT);
        if (!d->curr_user_buff.hpages[i]) {
            dbg_info("user host buffer %d could not be allocated\n", i);
            goto fail_host_alloc;
        }

        dbg_info("user host buffer allocated @ %llx device %d\n", page_to_phys(d->curr_user_buff.hpages[i]), d->id);
    }

    // alloc card
    if(pd->en_mem) {
        d->curr_user_buff.n_pages = d->curr_user_buff.n_hpages;
        d->curr_user_buff.cpages = kzalloc(d->curr_user_buff.n_pages * sizeof(uint64_t), GFP_KERNEL);
        if (d->curr_user_buff.cpages == NULL) {
            return -ENOMEM;
        }
        dbg_info("allocated %llu bytes for page pointer array for %lld user card buffers @0x%p.\n",
                d->curr_user_buff.n_pages * sizeof(*d->curr_user_buff.cpages), d->curr_user_buff.n_pages, d->curr_user_buff.cpages);

        ret_val = card_alloc(d, d->curr_user_buff.cpages, d->curr_user_buff.n_pages, LARGE_CHUNK_ALLOC);
        if (ret_val) {
            dbg_info("user card buffer %d could not be allocated\n", i);
            goto fail_card_alloc;
        }
    }

    return 0;
fail_host_alloc:
    while (i)
        __free_pages(d->curr_user_buff.hpages[--i], pd->ltlb_order->page_shift - PAGE_SHIFT);

    d->curr_user_buff.n_hpages = 0;

    kfree(d->curr_user_buff.hpages);

    return -ENOMEM;

fail_card_alloc:
    // release host
    for (i = 0; i < d->curr_user_buff.n_hpages; i++)
        __free_pages(d->curr_user_buff.hpages[i], pd->ltlb_order->page_shift - PAGE_SHIFT);

    d->curr_user_buff.n_hpages = 0;
    d->curr_user_buff.n_pages = 0;

    kfree(d->curr_user_buff.hpages);
    kfree(d->curr_user_buff.cpages);

    return -ENOMEM;
}

/**
 * @brief Free user buffers
 * 
 * @param d - vFPGA
 * @param vaddr - virtual address 
 * @param cpid - Coyote PID
 */
static int free_user_buffers(struct fpga_dev *d, uint64_t vaddr, int32_t cpid)
{
    int i;
    uint64_t vaddr_tmp;
    struct user_pages *tmp_buff;  
    uint64_t *map_array;
    struct pci_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    hash_for_each_possible(user_lbuff_map[d->id], tmp_buff, entry, vaddr) {

        if (tmp_buff->vaddr == vaddr && tmp_buff->cpid == cpid) {

            vaddr_tmp = tmp_buff->vaddr;

            // free host pages
            for (i = 0; i < tmp_buff->n_hpages; i++) {
                if (tmp_buff->hpages[i])
                    __free_pages(tmp_buff->hpages[i], pd->ltlb_order->page_shift - PAGE_SHIFT);
            }
            kfree(tmp_buff->hpages);

            // free card pages
            if(pd->en_mem) {
                card_free(d, tmp_buff->cpages, tmp_buff->n_pages, LARGE_CHUNK_ALLOC);
                kfree(tmp_buff->cpages);
            }

            // map array
            map_array = (uint64_t *)kzalloc(tmp_buff->n_hpages * 2 * sizeof(uint64_t), GFP_KERNEL);
            if (map_array == NULL) {
                dbg_info("map buffers could not be allocated\n");
                return -ENOMEM;
            }

            // fill mappings
            for (i = 0; i < tmp_buff->n_hpages; i++) {
                tlb_create_unmap(pd->ltlb_order, vaddr_tmp, cpid, &map_array[2*i]);
                vaddr_tmp += pd->ltlb_order->page_size;
            }

            // fire
            tlb_service_dev(d, pd->ltlb_order, map_array, tmp_buff->n_hpages);

            // free
            kfree((void *)map_array);

            // Free from hash
            hash_del(&tmp_buff->entry);
        }
    }

    return 0;
}

/**
 * @brief Page map list
 * 
 * @param vaddr - starting vaddr
 * @param paddr_host - host physical address
 * @param paddr_card - card physical address
 * @param cpid - Coyote PID
 * @param entry - liste entry
 */
static void tlb_create_map(struct tlb_order *tlb_ord, uint64_t vaddr, uint64_t paddr_host, uint64_t paddr_card, int32_t cpid, uint64_t *entry)
{
    uint64_t key;
    uint64_t tag;
    uint64_t phost;
    uint64_t pcard;

    key = (vaddr >> tlb_ord->page_shift) & tlb_ord->key_mask;
    tag = vaddr >> (tlb_ord->page_shift + tlb_ord->key_size);
    phost = (paddr_host >> tlb_ord->page_shift) & tlb_ord->phy_mask;
    pcard = ((paddr_card >> tlb_ord->page_shift) & tlb_ord->phy_mask) << tlb_ord->phy_size;

    // new entry
    entry[0] |= key | 
                (tag << tlb_ord->key_size) | 
                ((uint64_t)cpid << (tlb_ord->key_size + tlb_ord->tag_size)) | 
                (1UL << (tlb_ord->key_size + tlb_ord->tag_size + PID_SIZE));
    entry[1] |= phost | (pcard << tlb_ord->phy_size);

    dbg_info("creating new TLB entry, vaddr %llx, phost %llx, pcard %llx, cpid %d, hugepage %d\n", vaddr, paddr_host, paddr_card, cpid, tlb_ord->hugepage);
}

/**
 * @brief Page unmap lists
 * 
 * @param vaddr - starting vaddr
 * @param cpid - Coyote PID
 * @param entry - list entry
 */
static void tlb_create_unmap(struct tlb_order *tlb_ord, uint64_t vaddr, int32_t cpid, uint64_t *entry)
{
    uint64_t tag;
    uint64_t key;

    key = (vaddr >> tlb_ord->page_shift) & tlb_ord->key_mask;
    tag = vaddr >> (tlb_ord->page_shift + tlb_ord->key_size);

    // entry host
    entry[0] |= key | 
                (tag << tlb_ord->key_size) | 
                ((uint64_t)cpid << (tlb_ord->key_size + tlb_ord->tag_size)) | 
                (0UL << (tlb_ord->key_size + tlb_ord->tag_size + PID_SIZE));
    entry[1] |= 0;

    dbg_info("unmapping TLB entry, vaddr %llx, cpid %d, hugepage %d\n", vaddr, cpid, tlb_ord->hugepage);
}

/**
 * @brief Map TLB
 * 
 * @param d - vFPGA
 * @param en_tlbf - TLBF enabled
 * @param map_array - prepped map array
 * @param paddr - physical address
 * @param cpid - Coyote PID
 * @param card - map card mem as well
 */
static void tlb_service_dev(struct fpga_dev *d, struct tlb_order *tlb_ord, uint64_t* map_array, uint32_t n_pages)
{
    int i = 0;
    struct pci_drvdata *pd;

    BUG_ON(!d); 
    pd = d->pd;
    BUG_ON(!pd);

    // lock
    spin_lock(&d->lock);

    if(pd->en_tlbf && (n_pages > MAX_MAP_AXIL_PAGES)) {
        // lock
        spin_lock(&pd->tlb_lock);

        // start DMA
        pd->fpga_stat_cnfg->tlb_addr = virt_to_phys((void *)map_array);
        pd->fpga_stat_cnfg->tlb_len = n_pages * 2 * sizeof(uint64_t);
        if(tlb_ord->hugepage) {
            pd->fpga_stat_cnfg->tlb_ctrl = TLBF_CTRL_START | ((d->id && TLBF_CTRL_ID_MASK) << TLBF_CTRL_ID_SHFT);
        } else {
            pd->fpga_stat_cnfg->tlb_ctrl = TLBF_CTRL_START | (((pd->n_fpga_reg + d->id) && TLBF_CTRL_ID_MASK) << TLBF_CTRL_ID_SHFT);
        }

        // poll
        while ((pd->fpga_stat_cnfg->tlb_stat & TLBF_STAT_DONE) != 0x1)
            ndelay(100);
        
        // unlock
        spin_unlock(&pd->tlb_lock);
    } else {
        // map each page through AXIL
        for (i = 0; i < n_pages; i++) {
            if(tlb_ord->hugepage) {
                d->fpga_lTlb[0] = map_array[2*i+0];
                d->fpga_lTlb[1] = map_array[2*i+1];
            } else {
                d->fpga_sTlb[0] = map_array[2*i+0];
                d->fpga_sTlb[1] = map_array[2*i+1];
            }
        }
    }

    // unlock
    spin_unlock(&d->lock);
}

/**
 * @brief Release all remaining user pages
 * 
 * @param d - vFPGA
 * @param dirtied - modified
 */
static int tlb_put_user_pages_all(struct fpga_dev *d, int dirtied)
{
    int i, bkt;
    struct user_pages *tmp_buff;
    uint64_t vaddr_tmp;
    int32_t cpid_tmp;
    uint64_t *map_array;
    struct pci_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    hash_for_each(user_sbuff_map[d->id], bkt, tmp_buff, entry) {
        
        // release host pages
        if(dirtied)
            for(i = 0; i < tmp_buff->n_hpages; i++)
                SetPageDirty(tmp_buff->hpages[i]);

        for(i = 0; i < tmp_buff->n_hpages; i++)
            put_page(tmp_buff->hpages[i]);

        kfree(tmp_buff->hpages);

        // release card pages
        if(pd->en_mem) {
            if(tmp_buff->huge)
                card_free(d, tmp_buff->cpages, tmp_buff->n_pages, LARGE_CHUNK_ALLOC);
            else
                card_free(d, tmp_buff->cpages, tmp_buff->n_pages, SMALL_CHUNK_ALLOC);
        }

        // unmap from TLB
        vaddr_tmp = tmp_buff->vaddr;
        cpid_tmp = tmp_buff->cpid;

        // map array
        map_array = (uint64_t *)kzalloc(tmp_buff->n_pages * 2 * sizeof(uint64_t), GFP_KERNEL);
        if (map_array == NULL) {
            dbg_info("map buffers could not be allocated\n");
            return -ENOMEM;
        }

        // huge pages
        if(tmp_buff->huge) {
            // fill mappings
            for (i = 0; i < tmp_buff->n_pages; i++) {
                tlb_create_unmap(pd->ltlb_order, vaddr_tmp, cpid_tmp, &map_array[2*i]);
                vaddr_tmp += pd->ltlb_order->page_size;
            }

            // fire
            tlb_service_dev(d, pd->ltlb_order, map_array, tmp_buff->n_pages);

        // small pages
        } else {
            // fill mappings
            for (i = 0; i < tmp_buff->n_pages; i++) {
                tlb_create_unmap(pd->stlb_order, vaddr_tmp, cpid_tmp, &map_array[2*i]);
                vaddr_tmp += PAGE_SIZE;
            }

            // fire
            tlb_service_dev(d, pd->stlb_order, map_array, tmp_buff->n_pages);
        }

        // free
        kfree((void *)map_array);

        // remove from map
        hash_del(&tmp_buff->entry);
    }

    return 0;
}

/**
 * @brief Release user pages
 * 
 * @param d - vFPGA
 * @param vaddr - starting vaddr
 * @param cpid - Coyote PID
 * @param dirtied - modified
 */
static int tlb_put_user_pages(struct fpga_dev *d, uint64_t vaddr, int32_t cpid, int dirtied)
{
    int i;
    struct user_pages *tmp_buff;
    uint64_t vaddr_tmp;
    uint64_t *map_array;
    struct pci_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    hash_for_each_possible(user_sbuff_map[d->id], tmp_buff, entry, vaddr) {
        if(tmp_buff->vaddr == vaddr && tmp_buff->cpid == cpid) {

            // release host pages
            if(dirtied)
                for(i = 0; i < tmp_buff->n_hpages; i++)
                    SetPageDirty(tmp_buff->hpages[i]);

            for(i = 0; i < tmp_buff->n_hpages; i++)
                put_page(tmp_buff->hpages[i]);

            kfree(tmp_buff->hpages);

            // release card pages
            if(pd->en_mem) {
                if(tmp_buff->huge)
                    card_free(d, tmp_buff->cpages, tmp_buff->n_pages, LARGE_CHUNK_ALLOC);
                else
                    card_free(d, tmp_buff->cpages, tmp_buff->n_pages, SMALL_CHUNK_ALLOC);
            }

            // unmap from TLB
            vaddr_tmp = vaddr;

            // map array
            map_array = (uint64_t *)kzalloc(tmp_buff->n_pages * 2 * sizeof(uint64_t), GFP_KERNEL);
            if (map_array == NULL) {
                dbg_info("map buffers could not be allocated\n");
                return -ENOMEM;
            }

            // huge pages
            if(tmp_buff->huge) {
                // fill mappings
                for (i = 0; i < tmp_buff->n_pages; i++) {
                    tlb_create_unmap(pd->ltlb_order, vaddr_tmp, cpid, &map_array[2*i]);
                    vaddr_tmp += pd->ltlb_order->page_size;
                }

                // fire
                tlb_service_dev(d, pd->ltlb_order, map_array, tmp_buff->n_pages);

            // small pages
            } else {
                // fill mappings
                for (i = 0; i < tmp_buff->n_pages; i++) {
                    tlb_create_unmap(pd->stlb_order, vaddr_tmp, cpid, &map_array[2*i]);
                    vaddr_tmp += PAGE_SIZE;
                }

                // fire
                tlb_service_dev(d, pd->stlb_order, map_array, tmp_buff->n_pages);
            }

            // free
            kfree((void *)map_array);

            // remove from map
            hash_del(&tmp_buff->entry);
        }
    }

    return 0;
}

/** 
 * @brief Get user pages and fill TLB
 * 
 * @param d - vFPGA
 * @param start - starting vaddr
 * @param count - number of pages to map
 * @param cpid - Coyote PID
 * @param pid - user PID
 */
static int tlb_get_user_pages(struct fpga_dev *d, uint64_t start, size_t count, int32_t cpid, pid_t pid)
{
    int ret_val = 0, i, j;
    int n_pages, n_pages_huge;
    uint64_t first;
    uint64_t last;
    struct user_pages *user_pg;
    struct vm_area_struct *vma_area_init;
    int hugepages;
    uint64_t *hpages_phys;
    uint64_t curr_vaddr, last_vaddr;
    struct task_struct *curr_task;
    struct mm_struct *curr_mm;
    uint64_t *map_array;
    uint64_t vaddr_tmp;
    struct pci_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    // context
    curr_task = pid_task(find_vpid(pid), PIDTYPE_PID);
    dbg_info("pid found = %d", pid);
    curr_mm = curr_task->mm;

    // hugepages?
    vma_area_init = find_vma(curr_mm, start);
    hugepages = is_vm_hugetlb_page(vma_area_init);

    // number of pages
    first = (start & PAGE_MASK) >> PAGE_SHIFT;
    last = ((start + count - 1) & PAGE_MASK) >> PAGE_SHIFT;
    n_pages = last - first + 1;

    if(hugepages) {
        if(n_pages > MAX_N_MAP_HUGE_PAGES)
            n_pages = MAX_N_MAP_HUGE_PAGES;
    } else {
        if(n_pages > MAX_N_MAP_PAGES)
            n_pages = MAX_N_MAP_PAGES;
    }

    if (start + count < start)
        return -EINVAL;
    if (count == 0)
        return 0;

    // alloc
    user_pg = kzalloc(sizeof(struct user_pages), GFP_KERNEL);
    BUG_ON(!user_pg);

    user_pg->hpages = kcalloc(n_pages, sizeof(*user_pg->hpages), GFP_KERNEL);
    if (user_pg->hpages == NULL) {
        return -1;
    }
    dbg_info("allocated %lu bytes for page pointer array for %d pages @0x%p, passed size %ld.\n",
             n_pages * sizeof(*user_pg->hpages), n_pages, user_pg->hpages, count);

    dbg_info("pages=0x%p\n", user_pg->hpages);
    dbg_info("first = %llx, last = %llx\n", first, last);

    for (i = 0; i < n_pages - 1; i++) {
        user_pg->hpages[i] = NULL;
    }

    // pin
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5,9,0)
    ret_val = get_user_pages_remote(curr_mm, (unsigned long)start, n_pages, 1, user_pg->hpages, NULL, NULL);
#else 
    ret_val = get_user_pages_remote(curr_task, curr_mm, (unsigned long)start, n_pages, 1, user_pg->hpages, NULL, NULL);
#endif
    //ret_val = pin_user_pages_remote(curr_mm, (unsigned long)start, n_pages, 1, user_pg->hpages, NULL, NULL);
    dbg_info("get_user_pages_remote(%llx, n_pages = %d, page start = %lx, hugepages = %d)\n", start, n_pages, page_to_pfn(user_pg->hpages[0]), hugepages);

    if(ret_val < n_pages) {
        dbg_info("could not get all user pages, %d\n", ret_val);
        goto fail_host_unmap;
    }

    // flush cache
    for(i = 0; i < n_pages; i++)
        flush_dcache_page(user_pg->hpages[i]);

    // add mapped entry
    user_pg->vaddr = start;
    user_pg->n_hpages = n_pages;
    user_pg->huge = hugepages;

    vaddr_tmp = start;

    // huge pages
    if (hugepages) {
        first = (start & pd->ltlb_order->page_mask) >> pd->ltlb_order->page_shift;
        last = ((start + count - 1) & pd->ltlb_order->page_mask) >> pd->ltlb_order->page_shift;
        n_pages_huge = last - first + 1;
        user_pg->n_pages = n_pages_huge;

        // prep hpages
        hpages_phys = kzalloc(n_pages_huge * sizeof(uint64_t), GFP_KERNEL);
        if (hpages_phys == NULL) {
            dbg_info("card buffer %d could not be allocated\n", i);
            return -ENOMEM;
        }

        j = 0;
        curr_vaddr = start;
        last_vaddr = -1;
        for (i = 0; i < n_pages; i++) {
            if (((curr_vaddr & pd->ltlb_order->page_mask) >> pd->ltlb_order->page_shift) != ((last_vaddr & pd->ltlb_order->page_mask) >> pd->ltlb_order->page_shift)) {
                hpages_phys[j] = page_to_phys(user_pg->hpages[i]) & pd->ltlb_order->page_mask;
                dbg_info("hugepage %d at %llx\n", j, hpages_phys[j]);
                last_vaddr = curr_vaddr;
                j++;
            }
            curr_vaddr += PAGE_SIZE;
        }

        // card alloc
        if(pd->en_mem) {
            user_pg->cpages = kzalloc(n_pages_huge * sizeof(uint64_t), GFP_KERNEL);
            if (user_pg->cpages == NULL) {
                dbg_info("card buffer %d could not be allocated\n", i);
                return -ENOMEM;
            }

            ret_val = card_alloc(d, user_pg->cpages, n_pages_huge, LARGE_CHUNK_ALLOC);
            if (ret_val) {
                dbg_info("could not get all card pages, %d\n", ret_val);
                goto fail_card_unmap;
            }
            dbg_info("card allocated %d hugepages\n", n_pages_huge);
        }

        // map array
        map_array = (uint64_t *)kzalloc(n_pages_huge * 2 * sizeof(uint64_t), GFP_KERNEL);
        if (map_array == NULL) {
            dbg_info("map buffers could not be allocated\n");
            return -ENOMEM;
        }

        // fill mappings
        for (i = 0; i < n_pages_huge; i++) {
            tlb_create_map(pd->ltlb_order, vaddr_tmp, hpages_phys[i], (pd->en_mem ? user_pg->cpages[i] : 0), cpid, &map_array[2*i]);
            vaddr_tmp += pd->ltlb_order->page_size;
        }

        // fire
        tlb_service_dev(d, pd->ltlb_order, map_array, n_pages_huge);

        // free
        kfree((void *)map_array);
    
    // small pages
    } else {
        user_pg->n_pages = n_pages;

        // card alloc
        if(pd->en_mem) {
            user_pg->cpages = kzalloc(n_pages * sizeof(uint64_t), GFP_KERNEL);
            if (user_pg->cpages == NULL) {
                dbg_info("card buffer %d could not be allocated\n", i);
                return -ENOMEM;
            }

            ret_val = card_alloc(d, user_pg->cpages, n_pages, SMALL_CHUNK_ALLOC);
            if (ret_val) {
                dbg_info("could not get all card pages, %d\n", ret_val);
                goto fail_card_unmap;
            }
            dbg_info("card allocated %d regular pages\n", n_pages);
        }

        // map array
        map_array = (uint64_t *)kzalloc(n_pages * 2 * sizeof(uint64_t), GFP_KERNEL);
        if (map_array == NULL) {
            dbg_info("map buffers could not be allocated\n");
            return -ENOMEM;
        }

        // fill mappings
        for (i = 0; i < n_pages; i++) {
            tlb_create_map(pd->stlb_order, vaddr_tmp, page_to_phys(user_pg->hpages[i]), (pd->en_mem ? user_pg->cpages[i] : 0), cpid, &map_array[2*i]);
            vaddr_tmp += PAGE_SIZE;
        }

        // fire
        tlb_service_dev(d, pd->stlb_order, map_array, n_pages);

        // free
        kfree((void *)map_array);
    }

    hash_add(user_sbuff_map[d->id], &user_pg->entry, start);

    return n_pages;

fail_host_unmap:
    // release host pages
    for(i = 0; i < ret_val; i++) {
        put_page(user_pg->hpages[i]);
    }

    kfree(user_pg->hpages);

    return -ENOMEM;

fail_card_unmap:
    // release host pages
    for(i = 0; i < user_pg->n_hpages; i++) {
        put_page(user_pg->hpages[i]);
    }

    kfree(user_pg->hpages);
    kfree(user_pg->cpages);

    return -ENOMEM;
}

/*
 ___ ____  ____
|_ _/ ___||  _ \
 | |\___ \| |_) |
 | | ___) |  _ <
|___|____/|_| \_\
*/

/**
 * TLB page fault handling
 */
static irqreturn_t fpga_tlb_miss_isr(int irq, void *dev_id)
{
    unsigned long flags;
    uint64_t vaddr;
    uint32_t len;
    int32_t cpid;
    struct fpga_dev *d;
    struct pci_drvdata *pd;
    int ret_val = 0;
    pid_t pid;
    uint64_t tmp;

    dbg_info("(irq=%d) page fault ISR\n", irq);
    BUG_ON(!dev_id);

    d = (struct fpga_dev *)dev_id;

    pd = d->pd;

    // lock
    spin_lock_irqsave(&(d->lock), flags);

    // read page fault
    if (pd->en_avx) {
        vaddr = d->fpga_cnfg_avx->vaddr_miss;
        tmp = d->fpga_cnfg_avx->len_miss;
        len = LOW_32(tmp);
        cpid = (int32_t)HIGH_32(tmp);
    }
    else {
        vaddr = d->fpga_cnfg->vaddr_miss;
        tmp = d->fpga_cnfg->len_miss;
        len = LOW_32(tmp);
        cpid = (int32_t)HIGH_32(tmp);
    }
    dbg_info("page fault, vaddr %llx, length %x, cpid %d\n", vaddr, len, cpid);

    // get user pages
    pid = d->pid_array[cpid];
    ret_val = tlb_get_user_pages(d, vaddr, len, cpid, pid);

    if (ret_val > 0) {
        // restart the engine
        if (pd->en_avx)
            d->fpga_cnfg_avx->ctrl[0] = FPGA_CNFG_CTRL_IRQ_RESTART;
        else
            d->fpga_cnfg->ctrl = FPGA_CNFG_CTRL_IRQ_RESTART;
    }
    else {
        dbg_info("pages could not be obtained\n");
    }

    // unlock
    spin_unlock_irqrestore(&(d->lock), flags);

    return IRQ_HANDLED;
}

/*
 ___       _                             _
|_ _|_ __ | |_ ___ _ __ _ __ _   _ _ __ | |_ ___
 | || '_ \| __/ _ \ '__| '__| | | | '_ \| __/ __|
 | || | | | ||  __/ |  | |  | |_| | |_) | |_\__ \
|___|_| |_|\__\___|_|  |_|   \__,_| .__/ \__|___/
                                  |_|
*/

static void user_interrupts_enable(struct pci_drvdata *d, uint32_t mask)
{
    struct interrupt_regs *reg = (struct interrupt_regs *)(d->bar[BAR_XDMA_CONFIG] + XDMA_OFS_INT_CTRL);

    iowrite32(mask, &reg->user_int_enable_w1s);
}

static void user_interrupts_disable(struct pci_drvdata *d, uint32_t mask)
{
    struct interrupt_regs *reg = (struct interrupt_regs *)(d->bar[BAR_XDMA_CONFIG] + XDMA_OFS_INT_CTRL);

    iowrite32(mask, &reg->user_int_enable_w1c);
}

/**
 * Read interrupt status
 */
static uint32_t read_interrupts(struct pci_drvdata *d)
{
    struct interrupt_regs *reg = (struct interrupt_regs *)(d->bar[BAR_XDMA_CONFIG] + XDMA_OFS_INT_CTRL);
    uint32_t lo, hi;

    // interrupt check
    hi = ioread32(&reg->user_int_request);
    printk(KERN_INFO "ioread32(0x%p) returned 0x%08x (user_int_request).\n",
           &reg->user_int_request, hi);
    lo = ioread32(&reg->channel_int_request);
    printk(KERN_INFO
           "ioread32(0x%p) returned 0x%08x (channel_int_request)\n",
           &reg->channel_int_request, lo);

    // return interrupts: user in upper 16-bits, channel in lower 16-bits
    return build_u32(hi, lo);
}

/**
 * XDMA engine status
 */
static uint32_t engine_status_read(struct xdma_engine *engine)
{
    uint32_t val;

    BUG_ON(!engine);

    dbg_info("engine %s status:\n", engine->name);
    val = ioread32(&engine->regs->status);
    dbg_info("status = 0x%08x: %s%s%s%s%s%s%s%s%s\n", (uint32_t)val,
             (val & XDMA_STAT_BUSY) ? "BUSY " : "IDLE ",
             (val & XDMA_STAT_DESC_STOPPED) ? "DESC_STOPPED " : "",
             (val & XDMA_STAT_DESC_COMPLETED) ? "DESC_COMPLETED " : "",
             (val & XDMA_STAT_ALIGN_MISMATCH) ? "ALIGN_MISMATCH " : "",
             (val & XDMA_STAT_MAGIC_STOPPED) ? "MAGIC_STOPPED " : "",
             (val & XDMA_STAT_FETCH_STOPPED) ? "FETCH_STOPPED " : "",
             (val & XDMA_STAT_READ_ERROR) ? "READ_ERROR " : "",
             (val & XDMA_STAT_DESC_ERROR) ? "DESC_ERROR " : "",
             (val & XDMA_STAT_IDLE_STOPPED) ? "IDLE_STOPPED " : "");

    return val;
}

static uint32_t build_vector_reg(uint32_t a, uint32_t b, uint32_t c, uint32_t d)
{
    uint32_t reg_val = 0;

    reg_val |= (a & 0x1f) << 0;
    reg_val |= (b & 0x1f) << 8;
    reg_val |= (c & 0x1f) << 16;
    reg_val |= (d & 0x1f) << 24;

    return reg_val;
}

/**
 * Write MSI-X vectors
 */
static void write_msix_vectors(struct pci_drvdata *d)
{
    struct interrupt_regs *int_regs;
    uint32_t reg_val = 0;

    BUG_ON(!d);

    int_regs = (struct interrupt_regs *)(d->bar[0] + XDMA_OFS_INT_CTRL);

    // user MSI-X
    reg_val = build_vector_reg(0, 1, 2, 3);
    iowrite32(reg_val, &int_regs->user_msi_vector[0]);

    reg_val = build_vector_reg(4, 5, 6, 7);
    iowrite32(reg_val, &int_regs->user_msi_vector[1]);

    reg_val = build_vector_reg(8, 9, 10, 11);
    iowrite32(reg_val, &int_regs->user_msi_vector[2]);

    reg_val = build_vector_reg(12, 13, 14, 15);
    iowrite32(reg_val, &int_regs->user_msi_vector[3]);

    // channel MSI-X
    reg_val = build_vector_reg(16, 17, 18, 19);
    iowrite32(reg_val, &int_regs->channel_msi_vector[0]);

    reg_val = build_vector_reg(20, 21, 22, 23);
    iowrite32(reg_val, &int_regs->channel_msi_vector[1]);
}

/**
 * Remove user IRQs
 */
static void irq_teardown(struct pci_drvdata *d)
{
    int i;

    if (d->msix_enabled) {
        for (i = 0; i < d->n_fpga_reg; i++) {
            pr_info("releasing IRQ%d\n", d->irq_entry[i].vector);
            free_irq(d->irq_entry[i].vector, &d->fpga_dev[i]);
        }
    }
    else if (d->irq_line != -1) {
        pr_info("releasing IRQ%d\n", d->irq_line);
        free_irq(d->irq_line, d);
    }
}

/**
 * Setup user MSI-X
 */
static int msix_irq_setup(struct pci_drvdata *d)
{
    int i;
    int ret_val;

    BUG_ON(!d);

    write_msix_vectors(d);

    for (i = 0; i < d->n_fpga_reg; i++) {
        ret_val = request_irq(d->irq_entry[i].vector, fpga_tlb_miss_isr, 0,
                              DRV_NAME, &d->fpga_dev[i]);

        if (ret_val) {
            pr_info("couldn't use IRQ#%d, ret=%d\n", d->irq_entry[i].vector, ret_val);
            break;
        }

        pr_info("using IRQ#%d with %d\n", d->irq_entry[i].vector, d->fpga_dev[i].id);
    }

    // unwind
    if (ret_val) {
        while (--i >= 0)
            free_irq(d->irq_entry[i].vector, &d->fpga_dev[i]);
    }

    return ret_val;
}

/**
 * Setup user IRQs
 */
static int irq_setup(struct pci_drvdata *d, struct pci_dev *pdev)
{
    int ret_val = 0;

    if (d->msix_enabled)
    {
        ret_val = msix_irq_setup(d);
    }

    return ret_val;
}

/**
 * Check whether support for MSI-X exists
 */
static int msix_capable(struct pci_dev *pdev, int type)
{
    struct pci_bus *bus;

    BUG_ON(!pdev);

    if (pdev->no_msi)
        return 0;

    for (bus = pdev->bus; bus; bus = bus->parent)
        if (bus->bus_flags & PCI_BUS_FLAGS_NO_MSI)
            return 0;

    if (!pci_find_capability(pdev, type))
        return 0;

    return 1;
}

/**
 * Check whether MSI-X is present
 */
static int pci_check_msix(struct pci_drvdata *d, struct pci_dev *pdev)
{
    int ret_val = 0, i;
    int req_nvec = MAX_NUM_ENGINES + MAX_USER_IRQS;

    BUG_ON(!d);
    BUG_ON(!pdev);

    if (msix_capable(pdev, PCI_CAP_ID_MSIX)) {
        pr_info("enabling MSI-X\n");

        for (i = 0; i < req_nvec; i++)
            d->irq_entry[i].entry = i;

        ret_val = pci_enable_msix_range(pdev, d->irq_entry, 0, req_nvec);
        if (ret_val < 0)
            pr_info("could not enable MSI-X mode, ret %d\n", ret_val);
        else
            pr_info("obtained %d MSI-X irqs\n", ret_val);

        d->msix_enabled = 1;
    }
    else {
        pr_info("MSI-X not present, forcing polling mode\n");
        ret_val = -1;
        d->msix_enabled = 0;
    }

    if (ret_val < 0)
        return ret_val;
    else
        return 0;
}

/*
 _____             _                       _
| ____|_ __   __ _(_)_ __   ___   ___  ___| |_ _   _ _ __
|  _| | '_ \ / _` | | '_ \ / _ \ / __|/ _ \ __| | | | '_ \
| |___| | | | (_| | | | | |  __/ \__ \  __/ |_| |_| | |_) |
|_____|_| |_|\__, |_|_| |_|\___| |___/\___|\__|\__,_| .__/
             |___/                                  |_|
*/

static uint32_t get_engine_channel_id(struct engine_regs *regs)
{
    uint32_t val;

    BUG_ON(!regs);

    val = ioread32(&regs->id);
    return (val & 0x00000f00U) >> 8;
}

static uint32_t get_engine_id(struct engine_regs *regs)
{
    uint32_t val;

    BUG_ON(!regs);

    val = ioread32(&regs->id);
    return (val & 0xffff0000U) >> 16;
}

/**
 * Free writeback memory
 */
/*
static void engine_writeback_teardown(struct pci_drvdata *d, struct xdma_engine *engine)
{
    BUG_ON(!d);
    BUG_ON(!engine);

    if (engine->poll_mode_addr_virt) {
        pci_free_consistent(d->pci_dev, sizeof(struct xdma_poll_wb),
                            engine->poll_mode_addr_virt, engine->poll_mode_phys_addr);
        pr_info("released memory for descriptor writeback\n");
    }
}
*/

/**
 * Remove single engine
 */
static void engine_destroy(struct pci_drvdata *d, struct xdma_engine *engine)
{
    BUG_ON(!d);
    BUG_ON(!engine);

    pr_info("shutting off engine %s%d\n", engine->name, engine->channel);
    iowrite32(0x0, &engine->regs->ctrl);
    engine->running = 0;

    //engine_writeback_teardown(d, engine);

    kfree(engine);

    d->engines_num--;
}

/**
 * Remove all present engines
 */
static void remove_engines(struct pci_drvdata *d)
{
    int i;
    struct xdma_engine *engine;

    BUG_ON(!d);

    for (i = 0; i < d->n_fpga_chan; i++) {
        engine = d->fpga_dev[i * d->n_fpga_reg].engine_h2c;
        if (engine) {
            pr_info("remove %s%d\n", engine->name, engine->channel);
            engine_destroy(d, engine);
        }

        engine = d->fpga_dev[i * d->n_fpga_reg].engine_c2h;
        if (engine) {
            pr_info("remove %s%d\n", engine->name, engine->channel);
            engine_destroy(d, engine);
        }
    }

    if (d->en_pr) {
        engine = d->prc.engine_h2c;
        if (engine) {
            pr_info("remove %s%d\n", engine->name, engine->channel);
            engine_destroy(d, engine);
        }

        engine = d->prc.engine_c2h;
        if (engine) {
            pr_info("remove %s%d\n", engine->name, engine->channel);
            engine_destroy(d, engine);
        }
    }
}

/**
 * Check engine alignments
 */
static void engine_alignments(struct xdma_engine *engine)
{
    uint32_t val;
    uint32_t align_bytes;
    uint32_t granularity_bytes;
    uint32_t address_bits;

    val = ioread32(&engine->regs->alignments);
    pr_info("engine %p name %s alignments=0x%08x\n", engine,
            engine->name, (int)val);

    align_bytes = (val & 0x00ff0000U) >> 16;
    granularity_bytes = (val & 0x0000ff00U) >> 8;
    address_bits = (val & 0x000000ffU);

    if (val) {
        engine->addr_align = align_bytes;
        engine->len_granularity = granularity_bytes;
        engine->addr_bits = address_bits;
    }
    else {
        // Default
        engine->addr_align = 1;
        engine->len_granularity = 1;
        engine->addr_bits = 64;
    }
}

/*
static int engine_writeback_setup(struct pci_drvdata *d, struct xdma_engine *engine)
{
    uint32_t w;
    struct xdma_poll_wb *writeback;

    BUG_ON(!d);
    BUG_ON(!engine);

    // Set up address for polled mode writeback 
    pr_info("allocating memory for descriptor writeback for %s%d",
            engine->name, engine->channel);
    engine->poll_mode_addr_virt = pci_alloc_consistent(d->pci_dev,
                                                       sizeof(struct xdma_poll_wb), &engine->poll_mode_phys_addr);
    if (!engine->poll_mode_addr_virt) {
        pr_err("engine %p (%s) couldn't allocate writeback\n", engine,
               engine->name);
        return -1;
    }
    pr_info("allocated memory for descriptor writeback for %s%d",
            engine->name, engine->channel);

    writeback = (struct xdma_poll_wb *)engine->poll_mode_addr_virt;
    writeback->completed_desc_count = 0;

    pr_info("setting writeback location to 0x%llx for engine %p",
            engine->poll_mode_phys_addr, engine);
    w = cpu_to_le32(LOW_32(engine->poll_mode_phys_addr));
    iowrite32(w, &engine->regs->poll_mode_wb_lo);
    w = cpu_to_le32(HIGH_32(engine->poll_mode_phys_addr));
    iowrite32(w, &engine->regs->poll_mode_wb_hi);

    return 0;
}
*/

/**
 * Create c2h or h2c vFPGA engine
 * @param offs - engine config register offset
 * @param c2h - engine direction
 * @param channel - engine channel
 * @return created engine structure
 */
static struct xdma_engine *engine_create(struct pci_drvdata *d, int offs, int c2h, int channel)
{
    struct xdma_engine *engine;
    uint32_t reg_val = 0;//, ret_val = 0;

    // allocate memory for engine struct
    engine = kzalloc(sizeof(struct xdma_engine), GFP_KERNEL);
    if (!engine)
        return NULL;

    // info
    engine->channel = channel;
    engine->name = c2h ? "c2h" : "h2c";

    // associate devices
    engine->pd = d;

    // direction
    engine->c2h = c2h;

    // registers
    engine->regs = (d->bar[BAR_XDMA_CONFIG] + offs);
    engine->sgdma_regs = (d->bar[BAR_XDMA_CONFIG] + offs + SGDMA_OFFSET_FROM_CHANNEL);

    // Incremental mode
    iowrite32(!XDMA_CTRL_NON_INCR_ADDR, &engine->regs->ctrl_w1c);

    // alignments
    engine_alignments(engine);

    // writeback (not used)
    /*
    ret_val = engine_writeback_setup(d, engine);
    if (ret_val) {
        pr_info("Descriptor writeback setup failed for %p, channel %d\n", engine, engine->channel);
        return NULL;
    }
    */

    // start engine
    reg_val |= XDMA_CTRL_POLL_MODE_WB;
    reg_val |= XDMA_CTRL_IE_DESC_STOPPED;
    reg_val |= XDMA_CTRL_IE_DESC_COMPLETED;
    reg_val |= XDMA_CTRL_RUN_STOP;
    engine->running = 0;

    iowrite32(reg_val, &engine->regs->ctrl);
    reg_val = ioread32(&engine->regs->status);
    dbg_info("ioread32(0x%p) = 0x%08x (dummy read flushes writes).\n", &engine->regs->status, reg_val);

    return engine;
}

/**
 * Probes a single c2h or h2c engine
 * @param c2h - engine direction
 * @param channel - engine channel
 */
static int probe_for_engine(struct pci_drvdata *d, int c2h, int channel)
{
    int offs, i;
    struct engine_regs *regs;
    uint32_t engine_id, engine_id_expected, channel_id;
    struct xdma_engine *tmp_engine;

    offs = (c2h * C2H_CHAN_OFFS) + (channel * CHAN_RANGE);
    regs = d->bar[BAR_XDMA_CONFIG] + offs;

    if (c2h) { // c2h
        pr_info("probing for c2h engine %d at %p\n", channel, regs);
        engine_id_expected = XDMA_ID_C2H;
    }
    else { // h2c
        pr_info("probing for h2c engine %d at %p\n", channel, regs);
        engine_id_expected = XDMA_ID_H2C;
    }

    engine_id = get_engine_id(regs);
    channel_id = get_engine_channel_id(regs);
    pr_info("engine ID = 0x%x, channel ID = %d\n", engine_id, channel_id);

    if (engine_id != engine_id_expected) {
        pr_info("incorrect engine ID - skipping\n");
        return 0;
    }

    if (channel_id != channel) {
        pr_info("expected channel ID %d, read %d\n", channel, channel_id);
        return 0;
    }

    // init engine
    if (channel == d->n_fpga_chan && d->en_pr) {
        if (c2h) { // c2h
            pr_info("found PR c2h %d engine at %p\n", channel, regs);
            d->prc.engine_c2h = engine_create(d, offs, c2h, channel);
            if (!d->prc.engine_c2h) {
                pr_err("error creating channel engine\n");
                return -1;
            }
            pr_info("engine channel %d assigned to PR", channel);
            d->engines_num++;
        }
        else { // h2c
            pr_info("found PR h2c %d engine at %p\n", channel, regs);
            d->prc.engine_h2c = engine_create(d, offs, c2h, channel);
            if (!d->prc.engine_h2c) {
                pr_err("error creating channel engine\n");
                return -1;
            }
            pr_info("engine channel %d assigned to PR", channel);
            d->engines_num++;
        }
    }
    else {
        if (c2h) { // c2h
            pr_info("found vFPGA c2h %d engine at %p\n", channel, regs);
            tmp_engine = engine_create(d, offs, c2h, channel);
            if (!tmp_engine) {
                pr_err("error creating channel engine\n");
                return -1;
            }
            for (i = 0; i < d->n_fpga_reg; i++) {
                d->fpga_dev[channel * d->n_fpga_reg + i].engine_h2c = tmp_engine;
                pr_info("engine channel %d assigned to vFPGA %d", channel, d->fpga_dev[channel * d->n_fpga_reg + i].id);
            }
            d->engines_num++;
        }
        else { // h2c
            pr_info("found vFPGA h2c %d engine at %p\n", channel, regs);
            tmp_engine = engine_create(d, offs, c2h, channel);
            if (!tmp_engine) {
                pr_err("error creating channel engine\n");
                return -1;
            }
            for (i = 0; i < d->n_fpga_reg; i++) {
                d->fpga_dev[channel * d->n_fpga_reg + i].engine_c2h = tmp_engine;
                pr_info("engine channel %d assigned to vFPGA %d", channel, d->fpga_dev[channel * d->n_fpga_reg + i].id);
            }
            d->engines_num++;
        }
    }

    return 0;
}

/**
 * Probe c2h and h2c engines
 */
static int probe_engines(struct pci_drvdata *d)
{
    int ret_val = 0;
    int channel;

    BUG_ON(!d);

    // probe for vFPGA h2c engines
    for (channel = 0; channel < MAX_NUM_CHANNELS; channel++) {
        ret_val = probe_for_engine(d, 0, channel); // h2c
        if (ret_val)
            goto fail;
    }

    // probe for vFPGA c2h engines
    for (channel = 0; channel < MAX_NUM_CHANNELS; channel++) {
        ret_val = probe_for_engine(d, 1, channel); // c2h
        if (ret_val)
            goto fail;
    }

    if (d->engines_num < 2 * d->n_fpga_chan) {
        pr_info("failed to detect all required c2h or h2c engines\n");
        return -ENODEV;
    }

    pr_info("found %d engines\n", d->engines_num);

    goto success;
fail:
    pr_err("engine probing failed - unwinding\n");
    remove_engines(d);
success:
    return ret_val;
}

/*
 ____    _    ____                                _
| __ )  / \  |  _ \   _ __ ___   __ _ _ __  _ __ (_)_ __   __ _
|  _ \ / _ \ | |_) | | '_ ` _ \ / _` | '_ \| '_ \| | '_ \ / _` |
| |_) / ___ \|  _ <  | | | | | | (_| | |_) | |_) | | | | | (_| |
|____/_/   \_\_| \_\ |_| |_| |_|\__,_| .__/| .__/|_|_| |_|\__, |
                                     |_|   |_|            |___/
*/

/**
 * Map a single BAR
 * @param idx - BAR index
 * @param curr_idx - current BAR mapping
 */
static int map_single_bar(struct pci_drvdata *d, struct pci_dev *pdev, int idx, int curr_idx)
{
    resource_size_t bar_start, bar_len, map_len;

    bar_start = pci_resource_start(pdev, idx);
    bar_len = pci_resource_len(pdev, idx);
    map_len = bar_len;

    d->bar[curr_idx] = NULL;

    if (!bar_len) {
        pr_info("BAR #%d is not present\n", idx);
        return 0;
    }

    if (bar_len > INT_MAX) {
        pr_info("BAR %d limited from %llu to %d bytes\n", idx, (u64)bar_len, INT_MAX);
        map_len = (resource_size_t)INT_MAX;
    }

    pr_info("mapping BAR %d, %llu bytes to be mapped", idx, (u64)map_len);
    d->bar[curr_idx] = pci_iomap(pdev, idx, map_len);

    if (!d->bar[curr_idx]) {
        dev_err(&pdev->dev, "could not map BAR %d\n", idx);
        return -1;
    }

    pr_info("BAR%d at 0x%llx mapped at 0x%p, length=%llu, (%llu)\n",
            idx, (u64)bar_start, d->bar[curr_idx], (u64)map_len, (u64)bar_len);

    d->bar_phys_addr[curr_idx] = bar_start;
    d->bar_len[curr_idx] = map_len;

    return (int)map_len;
}

/**
 * Unmap mapped bars 
 */
static void unmap_bars(struct pci_drvdata *d, struct pci_dev *pdev)
{
    int i;

    for (i = 0; i < MAX_NUM_BARS; i++) {
        if (d->bar[i]) {
            pci_iounmap(pdev, d->bar[i]);
            d->bar[i] = NULL;
            pr_info("BAR%d unmapped\n", i);
        }
    }
}

/**
 * Mapping of the bars
 */
static int map_bars(struct pci_drvdata *d, struct pci_dev *pdev)
{
    int ret_val;
    int i;
    int curr_idx = 0;

    for (i = 0; i < MAX_NUM_BARS; ++i) {
        int bar_len = map_single_bar(d, pdev, i, curr_idx);
        if (bar_len == 0) {
            continue;
        }
        else if (bar_len < 0) {
            ret_val = -1;
            goto fail;
        }
        curr_idx++;
    }
    goto success;
fail:
    pr_err("mapping of the bars failed\n");
    unmap_bars(d, pdev);
    return ret_val;
success:
    return 0;
}

/*
 ____            _
|  _ \ ___  __ _(_) ___  _ __  ___
| |_) / _ \/ _` | |/ _ \| '_ \/ __|
|  _ <  __/ (_| | | (_) | | | \__ \
|_| \_\___|\__, |_|\___/|_| |_|___/
           |___/
*/

static int request_regions(struct pci_drvdata *d, struct pci_dev *pdev)
{
    int ret_val;

    BUG_ON(!d);
    BUG_ON(!pdev);

    pr_info("pci request regions\n");
    ret_val = pci_request_regions(pdev, DRV_NAME);
    if (ret_val) {
        pr_info("device in use, return %d\n", ret_val);
        d->got_regions = 0;
        d->regions_in_use = 1;
    }
    else {
        d->got_regions = 1;
        d->regions_in_use = 0;
    }

    return ret_val;
}

/*
 ____            _
|  _ \ _ __ ___ | |__   ___
| |_) | '__/ _ \| '_ \ / _ \
|  __/| | | (_) | |_) |  __/su
|_|   |_|  \___/|_.__/ \___|
*/

/**
 * PCI device probe function
 */
static int pci_probe(struct pci_dev *pdev, const struct pci_device_id *id)
{
    int ret_val = 0, i, j;
    struct pci_drvdata *d = NULL;

    // dynamic major
    dev_t dev = MKDEV(fpga_major, 0);
    int devno;

    // entering probe
    pr_info("probe (pdev = 0x%p, pci_id = 0x%p)\n", pdev, id);

    // allocate mem. for device instance
    d = devm_kzalloc(&pdev->dev, sizeof(struct pci_drvdata), GFP_KERNEL);
    if (!d) {
        dev_err(&pdev->dev, "device memory region not obtained\n");
        goto err_alloc;
    }
    // set device private data
    d->pci_dev = pdev;
    dev_set_drvdata(&pdev->dev, d);

    // enable PCIe device
    ret_val = pci_enable_device(pdev);
    if (ret_val) {
        dev_err(&pdev->dev, "pci device could not be enabled\n");
        goto err_enable;
    }
    pr_info("pci device node %p enabled\n", &pdev->dev);

    // enable bus master capability
    pci_set_master(pdev);
    pr_info("pci bus master capability enabled\n");

    // check IRQ
    ret_val = pci_check_msix(d, pdev);
    if (ret_val < 0) {
        dev_err(&pdev->dev, "pci IRQ error\n");
        goto err_irq_en;
    }

    // request PCI regions
    ret_val = request_regions(d, pdev);
    if (ret_val) {
        dev_err(&pdev->dev, "pci regions could not be obtained\n");
        goto err_regions;
    }
    pr_info("pci regions obtained\n");

    // BAR mapping
    ret_val = map_bars(d, pdev);
    if (ret_val) {
        dev_err(&pdev->dev, "mapping of the BARs failed\n");
        goto err_map;
    }

    // DMA addressing
    pr_info("sizeof(dma_addr_t) == %ld\n", sizeof(dma_addr_t));
    ret_val = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(64));
    if (ret_val) {
        dev_err(&pdev->dev, "failed to set 64b DMA mask\n");
        goto err_mask;
    }

    // get static config
    d->fpga_stat_cnfg = ioremap(d->bar_phys_addr[BAR_FPGA_CONFIG] + FPGA_STAT_CNFG_OFFS, FPGA_STAT_CNFG_SIZE);

    d->probe = d->fpga_stat_cnfg->probe;
    pr_info("deployment id %08x\n", d->probe);

    d->n_fpga_chan = d->fpga_stat_cnfg->n_chan;
    d->n_fpga_reg = d->fpga_stat_cnfg->n_regions;
    pr_info("detected %d virtual FPGA regions, %d FPGA channels\n", d->n_fpga_reg, d->n_fpga_chan);

    d->en_avx = (d->fpga_stat_cnfg->ctrl_cnfg & EN_AVX_MASK) >> EN_AVX_SHFT;
    d->en_bypass = (d->fpga_stat_cnfg->ctrl_cnfg & EN_BPSS_MASK) >> EN_BPSS_SHFT;
    d->en_tlbf = (d->fpga_stat_cnfg->ctrl_cnfg & EN_TLBF_MASK) >> EN_TLBF_SHFT;
    d->en_wb = (d->fpga_stat_cnfg->ctrl_cnfg & EN_WB_MASK) >> EN_WB_SHFT;
    pr_info("enabled AVX %d, enabled bypass %d, enabled tlb fast %d, enabled writeback %d\n", d->en_avx, d->en_bypass, d->en_tlbf, d->en_wb);
   
    d->stlb_order = kzalloc(sizeof(struct tlb_order), GFP_KERNEL);
    BUG_ON(!d->stlb_order);
    d->stlb_order->hugepage = false;
    d->stlb_order->key_size = (d->fpga_stat_cnfg->ctrl_cnfg & TLB_S_ORDER_MASK) >> TLB_S_ORDER_SHFT;
    d->stlb_order->assoc = (d->fpga_stat_cnfg->ctrl_cnfg & TLB_S_ASSOC_MASK) >> TLB_S_ASSOC_SHFT;
    d->stlb_order->page_shift = (d->fpga_stat_cnfg->ctrl_cnfg & TLB_S_PG_SHFT_MASK) >> TLB_S_PG_SHFT_SHFT;
    BUG_ON(d->stlb_order->page_shift != PAGE_SHIFT);
    d->stlb_order->page_size = PAGE_SIZE;
    d->stlb_order->page_mask = PAGE_MASK;
    d->stlb_order->key_mask = (1 << d->stlb_order->key_size) - 1;
    d->stlb_order->tag_size = TLB_VADDR_RANGE - d->stlb_order->page_shift - d->stlb_order->key_size;
    d->stlb_order->tag_mask = (1 << d->stlb_order->tag_size) - 1;
    d->stlb_order->phy_size = TLB_PADDR_RANGE - d->stlb_order->page_shift;
    d->stlb_order->phy_mask = (1 << d->stlb_order->phy_size) - 1;
    pr_info("sTLB order %d, sTLB assoc %d, sTLB page size %lld\n", d->stlb_order->key_size, d->stlb_order->assoc, d->stlb_order->page_size);

    d->ltlb_order = kzalloc(sizeof(struct tlb_order), GFP_KERNEL);
    BUG_ON(!d->ltlb_order);
    d->ltlb_order->hugepage = true;
    d->ltlb_order->key_size = (d->fpga_stat_cnfg->ctrl_cnfg & TLB_L_ORDER_MASK) >> TLB_L_ORDER_SHFT;
    d->ltlb_order->assoc = (d->fpga_stat_cnfg->ctrl_cnfg & TLB_L_ASSOC_MASK) >> TLB_L_ASSOC_SHFT;
    d->ltlb_order->page_shift = (d->fpga_stat_cnfg->ctrl_cnfg & TLB_L_PG_SHFT_MASK) >> TLB_L_PG_SHFT_SHFT;
    d->ltlb_order->page_size = 1 << d->ltlb_order->page_shift;
    d->ltlb_order->page_mask = (~(d->ltlb_order->page_size - 1));
    d->ltlb_order->key_mask = (1 << d->ltlb_order->key_size) - 1;
    d->ltlb_order->tag_size = TLB_VADDR_RANGE - d->ltlb_order->page_shift  - d->ltlb_order->key_size;
    d->ltlb_order->tag_mask = (1 << d->ltlb_order->tag_size) - 1;
    d->ltlb_order->phy_size = TLB_PADDR_RANGE - d->ltlb_order->page_shift ;
    d->ltlb_order->phy_mask = (1 << d->ltlb_order->phy_size) - 1;
    pr_info("lTLB order %d, lTLB assoc %d, lTLB page size %lld\n", d->ltlb_order->key_size, d->ltlb_order->assoc, d->ltlb_order->page_size);

    d->en_strm = (d->fpga_stat_cnfg->mem_cnfg & EN_STRM_MASK) >> EN_STRM_SHFT;
    d->en_mem = (d->fpga_stat_cnfg->mem_cnfg & EN_MEM_MASK) >> EN_MEM_SHFT;
    pr_info("enabled host streams %d, enabled card (fpga_mem) streams %d\n", d->en_strm, d->en_mem);

    d->en_pr = (d->fpga_stat_cnfg->pr_cnfg & EN_PR_MASK) >> EN_PR_SHFT;
    pr_info("enabled PR %d\n", d->en_pr);

    d->en_rdma_0 = (d->fpga_stat_cnfg->rdma_cnfg & EN_RDMA_0_MASK) >> EN_RDMA_0_SHFT;
    d->en_rdma_1 = (d->fpga_stat_cnfg->rdma_cnfg & EN_RDMA_1_MASK) >> EN_RDMA_1_SHFT;
    pr_info("enabled RDMA on QSFP0 %d, enabled RDMA on QSFP1 %d\n", d->en_rdma_0, d->en_rdma_1);

    d->en_tcp_0 = (d->fpga_stat_cnfg->tcp_cnfg & EN_TCP_0_MASK) >> EN_TCP_0_SHFT;
    d->en_tcp_1 = (d->fpga_stat_cnfg->tcp_cnfg & EN_TCP_1_MASK) >> EN_TCP_1_SHFT;
    pr_info("enabled TCP/IP on QSFP0 %d, enabled TCP/IP on QSFP1 %d\n", d->en_tcp_0, d->en_tcp_1);

    d->en_net_0 = d->en_rdma_0 | d->en_tcp_0;
    d->en_net_1 = d->en_rdma_1 | d->en_tcp_1;

    // lowspeed ctrl
    d->fpga_stat_cnfg->lspeed_cnfg = EN_LOWSPEED;

    // network board setup
    if (d->en_net_0) {
        d->fpga_stat_cnfg->net_0_ip = BASE_IP_ADDR_0 + NODE_ID;
        d->fpga_stat_cnfg->net_0_boardnum = NODE_ID;
    }
    if (d->en_net_1) {
        d->fpga_stat_cnfg->net_1_ip = BASE_IP_ADDR_1 + NODE_ID;
        d->fpga_stat_cnfg->net_1_boardnum = NODE_ID;
    }

    // init chunks card
    d->num_free_lchunks = N_LARGE_CHUNKS;
    d->num_free_schunks = N_SMALL_CHUNKS;

    d->lchunks = vzalloc(N_LARGE_CHUNKS * sizeof(struct chunk));
    if (!d->lchunks) {
        dev_err(&pdev->dev, "memory region for cmem structs not obtained\n");
        goto err_alloc_lchunks;
    }
    d->schunks = vzalloc(N_SMALL_CHUNKS * sizeof(struct chunk));
    if (!d->schunks) {
        dev_err(&pdev->dev, "memory region for cmem structs not obtained\n");
        goto err_alloc_schunks;
    }

    for (i = 0; i < N_LARGE_CHUNKS - 1; i++) {
        d->lchunks[i].id = i;
        d->lchunks[i].next = &d->lchunks[i + 1];
    }
    for (i = 0; i < N_SMALL_CHUNKS - 1; i++) {
        d->schunks[i].id = i;
        d->schunks[i].next = &d->schunks[i + 1];
    }
    d->lalloc = &d->lchunks[0];
    d->salloc = &d->schunks[0];

    // initialize spinlocks
    spin_lock_init(&d->card_l_lock);
    spin_lock_init(&d->card_s_lock);
    spin_lock_init(&d->prc.lock);
    spin_lock_init(&d->stat_lock);
    spin_lock_init(&d->prc_lock);
    spin_lock_init(&d->tlb_lock);

    // create FPGA devices
    // register major
    ret_val = alloc_chrdev_region(&dev, 0, d->n_fpga_reg, DEV_NAME);
    fpga_major = MAJOR(dev);
    if (ret_val) {
        dev_err(&pdev->dev, "failed to register virtual FPGA devices");
        goto err_char_alloc;
    }
    pr_info("virtual FPGA device regions allocated, major number %d\n", fpga_major);

    // create device class
    fpga_class = class_create(THIS_MODULE, DEV_NAME);

    // virtual FPGA devices
    d->fpga_dev = kmalloc(d->n_fpga_reg * sizeof(struct fpga_dev), GFP_KERNEL);
    if (!d->fpga_dev) {
        ret_val = -ENOMEM;
        dev_err(&pdev->dev, "could not allocate memory for fpga devices\n");
        goto err_char_mem;
    }
    memset(d->fpga_dev, 0, d->n_fpga_reg * sizeof(struct fpga_dev));
    pr_info("allocated memory for fpga devices\n");

    for (i = 0; i < d->n_fpga_reg; i++) {
        // ID
        d->fpga_dev[i].id = i;

        // PCI device
        d->fpga_dev[i].pd = d;
        d->fpga_dev[i].prc = &d->prc;

        // physical
        d->fpga_dev[i].fpga_phys_addr_ctrl = d->bar_phys_addr[BAR_FPGA_CONFIG] + FPGA_CTRL_OFFS + i * FPGA_CTRL_SIZE;
        d->fpga_dev[i].fpga_phys_addr_ctrl_avx = d->bar_phys_addr[BAR_FPGA_CONFIG] + FPGA_CTRL_CNFG_AVX_OFFS + i * FPGA_CTRL_CNFG_AVX_SIZE;

        // MMU control region
        d->fpga_dev[i].fpga_lTlb = ioremap(d->fpga_dev[i].fpga_phys_addr_ctrl + FPGA_CTRL_LTLB_OFFS, FPGA_CTRL_LTLB_SIZE);
        d->fpga_dev[i].fpga_sTlb = ioremap(d->fpga_dev[i].fpga_phys_addr_ctrl + FPGA_CTRL_STLB_OFFS, FPGA_CTRL_STLB_SIZE);

        // FPGA engine control
        d->fpga_dev[i].fpga_cnfg = ioremap(d->fpga_dev[i].fpga_phys_addr_ctrl + FPGA_CTRL_CNFG_OFFS, FPGA_CTRL_CNFG_SIZE);

        // FPGA engine control AVX
        d->fpga_dev[i].fpga_cnfg_avx = ioremap(d->fpga_dev[i].fpga_phys_addr_ctrl_avx, FPGA_CTRL_CNFG_AVX_SIZE);

        // init chunks pid
        d->fpga_dev[i].num_free_pid_chunks = N_CPID_MAX;

        d->fpga_dev[i].pid_chunks = vzalloc(N_CPID_MAX * sizeof(struct chunk));
        if (!d->fpga_dev[i].pid_chunks) {
            dev_err(&pdev->dev, "memory region for pid chunks not obtained\n");
            goto err_alloc_pid_chunks;
        }
        d->fpga_dev[i].pid_array = vzalloc(N_CPID_MAX * sizeof(pid_t));
        if (!d->fpga_dev[i].pid_array) {
            dev_err(&pdev->dev, "memory region for pid array not obtained\n");
            goto err_alloc_pid_array;
        }

        for (j = 0; j < N_CPID_MAX - 1; j++) {
            d->fpga_dev[i].pid_chunks[j].id = j;
            d->fpga_dev[i].pid_chunks[j].next = &d->fpga_dev[i].pid_chunks[j + 1];
        }
        d->fpga_dev[i].pid_alloc = &d->fpga_dev[i].pid_chunks[0];

        // initialize device spinlock
        spin_lock_init(&d->fpga_dev[i].lock);
        spin_lock_init(&d->fpga_dev[i].card_pid_lock);

        // writeback setup
        if(d->en_wb) {
            d->fpga_dev[i].wb_addr_virt = pci_alloc_consistent(d->pci_dev, WB_SIZE, &d->fpga_dev[i].wb_phys_addr);
            if(!d->fpga_dev[i].wb_addr_virt) {
                dev_err(&pdev->dev, "failed to allocate writeback memory\n");
                goto err_wb;
            }

            if(d->en_avx) {
                d->fpga_dev[i].fpga_cnfg_avx->wback[0] = d->fpga_dev[i].wb_phys_addr;
                d->fpga_dev[i].fpga_cnfg_avx->wback[1] = d->fpga_dev[i].wb_phys_addr + N_CPID_MAX * sizeof(uint32_t);
            } else {
                d->fpga_dev[i].fpga_cnfg->wback_rd = d->fpga_dev[i].wb_phys_addr;
                d->fpga_dev[i].fpga_cnfg->wback_wr = d->fpga_dev[i].wb_phys_addr + N_CPID_MAX * sizeof(uint32_t);
            }

            pr_info("allocated memory for descriptor writeback, vaddr %llx, paddr %llx",
                    (uint64_t)d->fpga_dev[i].wb_addr_virt, d->fpga_dev[i].wb_phys_addr);
        }

        // create device
        devno = MKDEV(fpga_major, i);
        device_create(fpga_class, NULL, devno, NULL, DEV_NAME "%d", i);
        pr_info("virtual FPGA device %d created\n", i);

        // add device
        cdev_init(&d->fpga_dev[i].cdev, &fpga_fops);
        d->fpga_dev[i].cdev.owner = THIS_MODULE;
        d->fpga_dev[i].cdev.ops = &fpga_fops;

        // Init hash
        hash_init(user_lbuff_map[i]);
        hash_init(user_sbuff_map[i]);

        ret_val = cdev_add(&d->fpga_dev[i].cdev, devno, 1);
        if (ret_val) {
            dev_err(&pdev->dev, "could not create a virtual FPGA device %d\n", i);
            goto err_char_reg;
        }
    }
    pr_info("all virtual FPGA devices added\n");

    // Init hash
    hash_init(pr_buff_map);

    // probe DMA engines
    ret_val = probe_engines(d);
    if (ret_val) {
        dev_err(&pdev->dev, "error whilst probing DMA engines\n");
        goto err_engines;
    }

    // user IRQs
    ret_val = irq_setup(d, pdev);
    if (ret_val) {
        dev_err(&pdev->dev, "IRQ setup error\n");
        goto err_irq;
    }

    // enable interrupts
    user_interrupts_enable(d, ~0);

    // flush writes
    read_interrupts(d);

    if (ret_val == 0)
        goto end;

err_irq:
    remove_engines(d);
err_engines:
err_char_reg:
    for (j = 0; j < i; j++) {
        device_destroy(fpga_class, MKDEV(fpga_major, j));
        cdev_del(&d->fpga_dev[j].cdev);
    }
err_wb:
    for (j = 0; j < i; j++) {
        set_memory_wb((uint64_t)d->fpga_dev[j].wb_addr_virt, N_WB_PAGES);
        pci_free_consistent(d->pci_dev, WB_SIZE,
            d->fpga_dev[j].wb_addr_virt, d->fpga_dev[j].wb_phys_addr);
    }
    kfree(d->fpga_dev);
    class_destroy(fpga_class);
    vfree(d->fpga_dev[i].pid_array);
err_alloc_pid_array:
    for (j = 0; j < i; j++) {
        vfree(d->fpga_dev[j].pid_array);
    }
    vfree(d->fpga_dev[i].pid_chunks);
err_alloc_pid_chunks:
    for (j = 0; j < i; j++) {
        vfree(d->fpga_dev[j].pid_chunks);
    }
err_char_mem:
    unregister_chrdev_region(dev, d->n_fpga_reg);
err_char_alloc:
    vfree(d->schunks);
err_alloc_schunks:
    vfree(d->lchunks);
err_alloc_lchunks:
err_mask:
    unmap_bars(d, pdev);
err_map:
    if (d->got_regions)
        pci_release_regions(pdev);
err_regions:
    if (d->msix_enabled) {
        pci_disable_msix(pdev);
        pr_info("MSI-X disabled\n");
    }
err_irq_en:
    if (!d->regions_in_use)
        pci_disable_device(pdev);
err_enable:
    kfree(d);
err_alloc:
end:
    pr_info("probe returning %d\n", ret_val);
    return ret_val;
}

/**
 * Removal of the PCI device
 */
static void pci_remove(struct pci_dev *pdev)
{
    struct pci_drvdata *d;
    int i;

    d = (struct pci_drvdata *)dev_get_drvdata(&pdev->dev);

    // disable FPGA interrupts
    user_interrupts_disable(d, ~0);
    pr_info("interrupts disabled\n");

    // remove IRQ
    irq_teardown(d);
    pr_info("IRQ teardown\n");

    // engine removal
    remove_engines(d);
    pr_info("engines removed\n");

    // delete char devices
    for (i = 0; i < d->n_fpga_reg; i++) {
        device_destroy(fpga_class, MKDEV(fpga_major, i));
        cdev_del(&d->fpga_dev[i].cdev);
    }
    pr_info("char devices deleted\n");

    // free writeback
    if(d->en_wb) {
        for(i = 0; i < d->n_fpga_reg; i++) {
            set_memory_wb((uint64_t)d->fpga_dev[i].wb_addr_virt, N_WB_PAGES);
            pci_free_consistent(d->pci_dev, WB_SIZE,
                d->fpga_dev[i].wb_addr_virt, d->fpga_dev[i].wb_phys_addr);
        }
    }

    // free pid structs
    for(i = 0; i < d->n_fpga_reg; i++) {
        vfree(d->fpga_dev[i].pid_array);
        vfree(d->fpga_dev[i].pid_chunks);
    }
    
    // free virtual FPGA memory
    kfree(d->fpga_dev);
    pr_info("virtual FPGA device memory freed\n");

    // remove class
    class_destroy(fpga_class);
    pr_info("fpga class deleted\n");

    // remove char devices
    unregister_chrdev_region(MKDEV(fpga_major, 0), d->n_fpga_reg);
    pr_info("char devices unregistered\n");

    // free card memory structs
    vfree(d->schunks);
    vfree(d->lchunks);

    // unmap BARs
    unmap_bars(d, pdev);
    pr_info("BARs unmapped\n");

    // release regions
    if (d->got_regions)
        pci_release_regions(pdev);
    pr_info("pci regions released\n");

    // disable interrupts
    if (d->msix_enabled) {
        pci_disable_msix(pdev);
        pr_info("MSI-X disabled\n");
    }

    // disable device
    if (!d->regions_in_use)
        pci_disable_device(pdev);
    pr_info("pci device disabled\n");

    // free device data
    devm_kfree(&pdev->dev, d);
    pr_info("device memory freed\n");

    pr_info("removal completed\n");
}

/*
 ____       _
|  _ \ _ __(_)_   _____ _ __
| | | | '__| \ \ / / _ \ '__|
| |_| | |  | |\ V /  __/ |
|____/|_|  |_| \_/ \___|_|
*/

static const struct pci_device_id pci_ids[] = {
    { PCI_DEVICE(0x10ee, 0x9011), },
    { PCI_DEVICE(0x10ee, 0x9012), },
    { PCI_DEVICE(0x10ee, 0x9014), },
    { PCI_DEVICE(0x10ee, 0x9018), },
    { PCI_DEVICE(0x10ee, 0x901F), },
    { PCI_DEVICE(0x10ee, 0x9021), },
    { PCI_DEVICE(0x10ee, 0x9022), },
    { PCI_DEVICE(0x10ee, 0x9024), },
    { PCI_DEVICE(0x10ee, 0x9028), },
    { PCI_DEVICE(0x10ee, 0x902F), },
    { PCI_DEVICE(0x10ee, 0x9031), },
    { PCI_DEVICE(0x10ee, 0x9032), },
    { PCI_DEVICE(0x10ee, 0x9034), },
    { PCI_DEVICE(0x10ee, 0x9038), },
    { PCI_DEVICE(0x10ee, 0x903F), },
    { PCI_DEVICE(0x10ee, 0x8011), },
    { PCI_DEVICE(0x10ee, 0x8012), },
    { PCI_DEVICE(0x10ee, 0x8014), },
    { PCI_DEVICE(0x10ee, 0x8018), },
    { PCI_DEVICE(0x10ee, 0x8021), },
    { PCI_DEVICE(0x10ee, 0x8022), },
    { PCI_DEVICE(0x10ee, 0x8024), },
    { PCI_DEVICE(0x10ee, 0x8028), },
    { PCI_DEVICE(0x10ee, 0x8031), },
    { PCI_DEVICE(0x10ee, 0x8032), },
    { PCI_DEVICE(0x10ee, 0x8034), },
    { PCI_DEVICE(0x10ee, 0x8038), },
    { PCI_DEVICE(0x10ee, 0x7011), },
    { PCI_DEVICE(0x10ee, 0x7012), },
    { PCI_DEVICE(0x10ee, 0x7014), },
    { PCI_DEVICE(0x10ee, 0x7018), },
    { PCI_DEVICE(0x10ee, 0x7021), },
    { PCI_DEVICE(0x10ee, 0x7022), },
    { PCI_DEVICE(0x10ee, 0x7024), },
    { PCI_DEVICE(0x10ee, 0x7028), },
    { PCI_DEVICE(0x10ee, 0x7031), },
    { PCI_DEVICE(0x10ee, 0x7032), },
    { PCI_DEVICE(0x10ee, 0x7034), },
    { PCI_DEVICE(0x10ee, 0x7038), },
    {0,}
};
MODULE_DEVICE_TABLE(pci, pci_ids);

static struct pci_driver pci_driver = {
    .name = DRV_NAME,
    .id_table = pci_ids,
    .probe = pci_probe,
    .remove = pci_remove,
};

/*
 ____            _     _
|  _ \ ___  __ _(_)___| |_ ___ _ __
| |_) / _ \/ _` | / __| __/ _ \ '__|
|  _ <  __/ (_| | \__ \ ||  __/ |
|_| \_\___|\__, |_|___/\__\___|_|
           |___/
*/

static int __init pci_init(void) {
    int ret_val;
    pr_info("loading: Coyote driver ...\n");

    ret_val = pci_register_driver(&pci_driver);
    if (ret_val) {
        pr_err("Coyote driver register returned %d\n", ret_val);
        return ret_val;
    }

    return 0;
}

static void __exit pci_exit(void) {
    pr_info("removal: Coyote driver ...\n");
    pci_unregister_driver(&pci_driver);
}

module_init(pci_init);
module_exit(pci_exit);

/* --------------------------------------------------------------------------- */
MODULE_DESCRIPTION("Coyote driver.");
MODULE_LICENSE("GPL");
MODULE_AUTHOR("Dario Korolija <dario.korolija@inf.ethz.ch");