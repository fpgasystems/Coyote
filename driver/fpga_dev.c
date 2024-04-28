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

#include "fpga_dev.h"

/*
██████╗ ███████╗██╗   ██╗
██╔══██╗██╔════╝██║   ██║
██║  ██║█████╗  ██║   ██║
██║  ██║██╔══╝  ╚██╗ ██╔╝
██████╔╝███████╗ ╚████╔╝ 
╚═════╝ ╚══════╝  ╚═══╝  
*/

/**
 * @brief Fops
 * 
 */
struct file_operations fpga_fops = {
    .owner = THIS_MODULE,
    .open = fpga_open,
    .release = fpga_release,
    .unlocked_ioctl = fpga_ioctl,
    .mmap = fpga_mmap,
};

struct file_operations pr_fops = {
    .owner = THIS_MODULE,
    .open = pr_open,
    .release = pr_release,
    .unlocked_ioctl = pr_ioctl,
    .mmap = pr_mmap,
};

/**
 * @brief Sysfs
 * 
 */
static struct kobj_attribute kobj_attr_ip = __ATTR(cyt_attr_ip, 0664, cyt_attr_ip_show, cyt_attr_ip_store);
static struct kobj_attribute kobj_attr_mac = __ATTR(cyt_attr_mac, 0664, cyt_attr_mac_show, cyt_attr_mac_store);
static struct kobj_attribute kobj_attr_nstats = __ATTR_RO(cyt_attr_nstats);
static struct kobj_attribute kobj_attr_xstats = __ATTR_RO(cyt_attr_xstats);
static struct kobj_attribute kobj_attr_prstats = __ATTR_RO(cyt_attr_prstats);
static struct kobj_attribute kobj_attr_engines = __ATTR_RO(cyt_attr_engines);
static struct kobj_attribute kobj_attr_cnfg = __ATTR_RO(cyt_attr_cnfg);
static struct kobj_attribute kobj_attr_eost = __ATTR(cyt_attr_eost, 0664, cyt_attr_eost_show, cyt_attr_eost_store);

static struct attribute *attrs[] = {
    &kobj_attr_ip.attr,
    &kobj_attr_mac.attr,
    &kobj_attr_nstats.attr,
    &kobj_attr_xstats.attr,
    &kobj_attr_prstats.attr,
    &kobj_attr_engines.attr,
    &kobj_attr_cnfg.attr,
    &kobj_attr_eost.attr,
    NULL,
};
static struct attribute_group attr_group = {
    .attrs = attrs,
};

/**
 * @brief Read static configuration
 * 
 */
int read_shell_config(struct bus_drvdata *d) 
{
    long tmp;
    int ret_val = 0;

    // probe
    d->probe_stat = d->fpga_stat_cnfg->probe;
    pr_info("deployment static probe %08x\n", d->probe_stat);
    d->probe_shell = d->fpga_shell_cnfg->probe;
    pr_info("deployment shell probe %08x\n", d->probe_shell);

    // channels and regions
    d->n_fpga_chan = d->fpga_shell_cnfg->n_chan;
    d->n_fpga_reg = d->fpga_shell_cnfg->n_regions;
    pr_info("detected %d virtual FPGA regions, %d FPGA channels\n", d->n_fpga_reg, d->n_fpga_chan);

    // flags
    d->en_avx = (d->fpga_shell_cnfg->ctrl_cnfg & EN_AVX_MASK) >> EN_AVX_SHFT;
    d->en_wb = (d->fpga_shell_cnfg->ctrl_cnfg & EN_WB_MASK) >> EN_WB_SHFT;
    pr_info("enabled AVX %d, enabled writeback %d\n", d->en_avx,d->en_wb);
   
    // mmu
    d->stlb_order = kzalloc(sizeof(struct tlb_order), GFP_KERNEL);
    BUG_ON(!d->stlb_order);
    d->stlb_order->hugepage = false;
    d->stlb_order->key_size = (d->fpga_shell_cnfg->ctrl_cnfg & TLB_S_ORDER_MASK) >> TLB_S_ORDER_SHFT;
    d->stlb_order->assoc = (d->fpga_shell_cnfg->ctrl_cnfg & TLB_S_ASSOC_MASK) >> TLB_S_ASSOC_SHFT;
    d->stlb_order->page_shift = (d->fpga_shell_cnfg->ctrl_cnfg & TLB_S_PG_SHFT_MASK) >> TLB_S_PG_SHFT_SHFT;
    BUG_ON(d->stlb_order->page_shift != PAGE_SHIFT);
    d->stlb_order->page_size = PAGE_SIZE;
    d->stlb_order->page_mask = PAGE_MASK;
    d->stlb_order->key_mask = (1UL << d->stlb_order->key_size) - 1UL;
    d->stlb_order->tag_size = TLB_VADDR_RANGE - d->stlb_order->page_shift - d->stlb_order->key_size;
    d->stlb_order->tag_mask = (1UL << d->stlb_order->tag_size) - 1UL;
    d->stlb_order->phy_size = TLB_PADDR_RANGE - d->stlb_order->page_shift;
    d->stlb_order->phy_mask = (1UL << d->stlb_order->phy_size) - 1UL;
    pr_info("sTLB order %lld, sTLB assoc %d, sTLB page size %lld\n", d->stlb_order->key_size, d->stlb_order->assoc, d->stlb_order->page_size);

    d->ltlb_order = kzalloc(sizeof(struct tlb_order), GFP_KERNEL);
    BUG_ON(!d->ltlb_order);
    d->ltlb_order->hugepage = true;
    d->ltlb_order->key_size = (d->fpga_shell_cnfg->ctrl_cnfg & TLB_L_ORDER_MASK) >> TLB_L_ORDER_SHFT;
    d->ltlb_order->assoc = (d->fpga_shell_cnfg->ctrl_cnfg & TLB_L_ASSOC_MASK) >> TLB_L_ASSOC_SHFT;
    d->ltlb_order->page_shift = (d->fpga_shell_cnfg->ctrl_cnfg & TLB_L_PG_SHFT_MASK) >> TLB_L_PG_SHFT_SHFT;
    d->ltlb_order->page_size = 1UL << d->ltlb_order->page_shift;
    d->ltlb_order->page_mask = (~(d->ltlb_order->page_size - 1));
    d->ltlb_order->key_mask = (1UL << d->ltlb_order->key_size) - 1UL;
    d->ltlb_order->tag_size = TLB_VADDR_RANGE - d->ltlb_order->page_shift  - d->ltlb_order->key_size;
    d->ltlb_order->tag_mask = (1UL << d->ltlb_order->tag_size) - 1UL;
    d->ltlb_order->phy_size = TLB_PADDR_RANGE - d->ltlb_order->page_shift ;
    d->ltlb_order->phy_mask = (1UL << d->ltlb_order->phy_size) - 1UL;
    pr_info("lTLB order %lld, lTLB assoc %d, lTLB page size %lld\n", d->ltlb_order->key_size, d->ltlb_order->assoc, d->ltlb_order->page_size);

    d->dif_order_page_shift = d->ltlb_order->page_shift - d->stlb_order->page_shift;
    d->dif_order_page_size = 1 << d->dif_order_page_shift;
    d->dif_order_page_mask = d->dif_order_page_size - 1;
    d->n_pages_in_huge = 1 << d->dif_order_page_shift;

    // mem
    d->en_strm = (d->fpga_shell_cnfg->mem_cnfg & EN_STRM_MASK) >> EN_STRM_SHFT; 
    d->en_mem = (d->fpga_shell_cnfg->mem_cnfg & EN_MEM_MASK) >> EN_MEM_SHFT;
    pr_info("enabled host streams %d, enabled card streams (mem) %d\n", d->en_strm, d->en_mem);

    d->card_huge_offs = MEM_SEP;
    d->card_reg_offs = MEM_START;

    // pr
    d->en_pr = (d->fpga_shell_cnfg->pr_cnfg & EN_PR_MASK) >> EN_PR_SHFT;
    pr_info("enabled dynamic reconfiguration %d\n", d->en_pr);

    // set eost
    if(d->en_pr) {
        d->eost = eost;
        d->fpga_stat_cnfg->pr_eost = eost;
        pr_info("set EOST [clks] %lld\n", d->eost);
    }

    // network
    d->en_rdma = (d->fpga_shell_cnfg->rdma_cnfg & EN_RDMA_MASK) >> EN_RDMA_SHFT;
    d->qsfp = (d->fpga_shell_cnfg->rdma_cnfg & QSFP_MASK) >> QSFP_SHFT;
    pr_info("enabled RDMA %d, port %d\n", d->en_rdma, d->qsfp);

    d->en_tcp = (d->fpga_shell_cnfg->tcp_cnfg & EN_TCP_MASK) >> EN_TCP_SHFT;
    pr_info("enabled TCP/IP %d, port %d\n", d->en_tcp, d->qsfp);

    // set ip and mac
    d->en_net = d->en_rdma | d->en_tcp;
    if(d->en_net) {
        ret_val = kstrtol(ip_addr, 16, &tmp);
        d->net_ip_addr = (uint64_t) tmp;
        ret_val = kstrtol(mac_addr, 16, &tmp);
        d->net_mac_addr = (uint64_t) tmp;
        d->fpga_shell_cnfg->net_ip = d->net_ip_addr;
        d->fpga_shell_cnfg->net_mac = d->net_mac_addr;
        pr_info("set network ip %08x, mac %012llx\n", d->net_ip_addr, d->net_mac_addr);
    }

    return ret_val;
}

/**
 * @brief Allocate FPGA memory resources
 * 
 */
int alloc_card_resources(struct bus_drvdata *d) 
{
    int ret_val = 0;
    int i;

    if(d->en_mem) {
        // init chunks card
        d->num_free_lchunks = N_LARGE_CHUNKS;
        d->num_free_schunks = N_SMALL_CHUNKS;

        d->lchunks = vzalloc(N_LARGE_CHUNKS * sizeof(struct chunk));
        if (!d->lchunks) {
            pr_err("memory region for cmem structs not obtained\n");
            goto err_alloc_lchunks; // ERR_ALLOC_LCHUNKS
        }
        d->schunks = vzalloc(N_SMALL_CHUNKS * sizeof(struct chunk));
        if (!d->schunks) {
            pr_err("memory region for cmem structs not obtained\n");
            goto err_alloc_schunks; // ERR_ALLOC_SCHUNKS
        }

        for (i = 0; i < N_LARGE_CHUNKS - 1; i++) {
            d->lchunks[i].id = i;
            d->lchunks[i].used = false;
            d->lchunks[i].next = &d->lchunks[i + 1];
        }
        for (i = 0; i < N_SMALL_CHUNKS - 1; i++) {
            d->schunks[i].id = i;
            d->schunks[i].used = false;
            d->schunks[i].next = &d->schunks[i + 1];
        }
        d->lalloc = &d->lchunks[0];
        d->salloc = &d->schunks[0];
    }

    goto end;

err_alloc_schunks:
    vfree(d->lchunks);
err_alloc_lchunks: 
    ret_val = -ENOMEM;
end: 
    return ret_val;
}

/** 
 * @brief Free card memory resources
 * 
 */
void free_card_resources(struct bus_drvdata *d) 
{
    if(d->en_mem) {
        // free card memory structs
        vfree(d->schunks);
        vfree(d->lchunks);

        pr_info("card resources deallocated\n");
    }
}

/**
 * @brief Initialize spin locks
 * 
 */
void init_spin_locks(struct bus_drvdata *d) 
{
    // initialize spinlocks
    spin_lock_init(&d->card_lock);
    spin_lock_init(&d->stat_lock);
}

static struct kobj_type cyt_kobj_type = {
	.sysfs_ops	= &kobj_sysfs_ops
};



/**
 * @brief Create sysfs entry
 * 
 */
int create_sysfs_entry(struct bus_drvdata *d) {
    int ret_val = 0;
    char sysfs_name[MAX_CHAR_FDEV];
    sprintf(sysfs_name, "coyote_sysfs_%d", d->dev_id);
    
    pr_info("creating sysfs entry ...\n");

    ret_val = kobject_init_and_add(&d->cyt_kobj, &cyt_kobj_type, kernel_kobj, sysfs_name);
    if(ret_val) {
        return -ENOMEM;
    }

    kobject_uevent(&d->cyt_kobj, KOBJ_ADD);

    ret_val = sysfs_create_group(&d->cyt_kobj, &attr_group);
    if(ret_val) {
        return -ENODEV;
    }

    return ret_val;
}

/**
 * @brief Remove sysfs entry
 * 
 */
void remove_sysfs_entry(struct bus_drvdata *d) {
    pr_info("removing sysfs entry ...\n");

    sysfs_remove_group(&d->cyt_kobj, &attr_group);

    kobject_put(&d->cyt_kobj);
    
    d->cyt_kobj = cyt_kobj_empty;
}

#define FPGA_CLASS_MODE ((umode_t)(S_IRUGO | S_IWUGO))

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6,0,0)
static char *fpga_class_devnode(const struct device *dev, umode_t *mode)
#else
static char *fpga_class_devnode(struct device *dev, umode_t *mode)
#endif
{
    if (mode != NULL)
        *mode = FPGA_CLASS_MODE;
    return NULL;
}

/**
 * @brief Init char vFPGA devices
 * 
 */
int init_char_fpga_devices(struct bus_drvdata *d, dev_t dev) 
{
    int ret_val = 0;

    // vFPGAs
    ret_val = alloc_chrdev_region(&dev, 0, d->n_fpga_reg, d->vf_dev_name);
    d->fpga_major = MAJOR(dev);
    if (ret_val) {
        pr_err("failed to register vFPGA devices");
        goto end;
    }
    pr_info("vFPGA device regions allocated, major number %d\n", d->fpga_major);

    // create device class
    d->fpga_class = class_create(THIS_MODULE, d->vf_dev_name);
    d->fpga_class->devnode = fpga_class_devnode;

    // virtual FPGA devices
    d->fpga_dev = kmalloc(d->n_fpga_reg * sizeof(struct fpga_dev), GFP_KERNEL);
    if (!d->fpga_dev) {
        pr_err("could not allocate memory for vFPGAs\n");
        goto err_fpga_char_mem; // ERR_CHAR_MEM
    }
    memset(d->fpga_dev, 0, d->n_fpga_reg * sizeof(struct fpga_dev));
    pr_info("allocated memory for fpga devices\n");

    goto end;

err_fpga_char_mem:
    class_destroy(d->fpga_class);
    unregister_chrdev_region(dev, d->n_fpga_reg);
    ret_val = -ENOMEM;
end:
    return ret_val;
}

/**
 * @brief Delete char vFPGA devices
 * 
 */
void free_char_fpga_devices(struct bus_drvdata *d) 
{
    // free virtual FPGA memory
    kfree(d->fpga_dev);
    pr_info("virtual FPGA device memory freed\n");

    // remove class
    class_destroy(d->fpga_class);
    pr_info("vFPGA class deleted\n");
    
    // remove char devices
    unregister_chrdev_region(MKDEV(d->fpga_major, 0), d->n_fpga_reg);
    pr_info("char vFPGA devices unregistered\n");
}

/**
 * @brief Init char PR device
 * 
 */
int init_char_pr_device(struct bus_drvdata *d, dev_t dev) 
{
    int ret_val = 0;

    // PR
    ret_val = alloc_chrdev_region(&dev, 0, 1, d->pr_dev_name);
    d->pr_major = MAJOR(dev);
    if (ret_val) {
        pr_err("failed to register vFPGA devices");
        goto end;
    }
    pr_info("reconfig device regions allocated, major number %d\n", d->pr_major);

    // create device class
    d->pr_class = class_create(THIS_MODULE, d->pr_dev_name);
    d->pr_class->devnode = fpga_class_devnode;

    // PR device
    d->pr_dev = kmalloc(sizeof(struct pr_dev), GFP_KERNEL);
    if (!d->pr_dev) {
        pr_err("could not allocate memory for reconfig device\n");
        goto err_pr_char_mem; // ERR_CHAR_MEM
    }
    memset(d->pr_dev, 0, sizeof(struct pr_dev));
    pr_info("allocated memory for reconfig device\n");

    goto end;

err_pr_char_mem:
    class_destroy(d->pr_class);
    unregister_chrdev_region(dev, 1);
    ret_val = -ENOMEM;
end:
    return ret_val;
}

/**
 * @brief Delete char devices
 * 
 */
void free_char_pr_device(struct bus_drvdata *d) 
{
    // free PR device memory
    kfree(d->pr_dev);
    pr_info("reconfig device memory freed\n");

    // remove class
    class_destroy(d->pr_class);
    pr_info("reconfig class deleted\n");
    
    // remove char devices
    unregister_chrdev_region(MKDEV(d->pr_major, 0), 1);
    pr_info("char reconfig device unregistered\n");
}

/**
 * @brief Initialize vFPGAs
 * 
 */
int init_fpga_devices(struct bus_drvdata *d)
{
    int ret_val = 0;
    int i, j;
    int devno;
    char vf_dev_name_tmp[MAX_CHAR_FDEV];

    for (i = 0; i < d->n_fpga_reg; i++) {
        // ID
        d->fpga_dev[i].id = i;
        d->fpga_dev[i].ref_cnt = 0;

        d->fpga_dev[i].n_pfaults = 0;

        // PCI device
        d->fpga_dev[i].pd = d;

        // physical
        if(cyt_arch == CYT_ARCH_PCI) {
            d->fpga_dev[i].fpga_phys_addr_ctrl = d->bar_phys_addr[BAR_SHELL_CONFIG] + FPGA_CTRL_OFFS + i * FPGA_CTRL_SIZE;
            d->fpga_dev[i].fpga_phys_addr_ctrl_avx = d->bar_phys_addr[BAR_SHELL_CONFIG] + FPGA_CTRL_CNFG_AVX_OFFS + i * FPGA_CTRL_CNFG_AVX_SIZE;
        } else if(cyt_arch == CYT_ARCH_ECI) {
            d->fpga_dev[i].fpga_phys_addr_ctrl = d->io_phys_addr + FPGA_CTRL_OFFS + i*FPGA_CTRL_SIZE;
        }

        // MMU control region
        d->fpga_dev[i].fpga_lTlb = ioremap(d->fpga_dev[i].fpga_phys_addr_ctrl + FPGA_CTRL_LTLB_OFFS, FPGA_CTRL_LTLB_SIZE);
        d->fpga_dev[i].fpga_sTlb = ioremap(d->fpga_dev[i].fpga_phys_addr_ctrl + FPGA_CTRL_STLB_OFFS, FPGA_CTRL_STLB_SIZE);

        // FPGA engine control
        if(d->en_avx && cyt_arch == CYT_ARCH_PCI) {
            d->fpga_dev[i].fpga_cnfg = ioremap(d->fpga_dev[i].fpga_phys_addr_ctrl_avx, FPGA_CTRL_CNFG_AVX_SIZE);
        } else {
            d->fpga_dev[i].fpga_cnfg = ioremap(d->fpga_dev[i].fpga_phys_addr_ctrl + FPGA_CTRL_CNFG_OFFS, FPGA_CTRL_CNFG_SIZE);
        }

        // init chunks pid
        d->fpga_dev[i].num_free_pid_chunks = N_CPID_MAX;

        d->fpga_dev[i].pid_chunks = vzalloc(N_CPID_MAX * sizeof(struct chunk));
        if (!d->fpga_dev[i].pid_chunks) {
            pr_err("memory region for pid chunks not obtained\n");
            goto err_alloc_pid_chunks; // ERR_ALLOC_PID_CHUNKS
        }
        d->fpga_dev[i].pid_array = vzalloc(N_CPID_MAX * sizeof(pid_t));
        if (!d->fpga_dev[i].pid_array) {
            pr_err("memory region for pid array not obtained\n");
            goto err_alloc_pid_array; // ERR_ALLOC_PID_ARRAY
        }

        for (j = 0; j < N_CPID_MAX - 1; j++) {
            d->fpga_dev[i].pid_chunks[j].id = j;
            d->fpga_dev[i].pid_chunks[j].used = false;
            d->fpga_dev[i].pid_chunks[j].next = &d->fpga_dev[i].pid_chunks[j + 1];
        }
        d->fpga_dev[i].pid_alloc = &d->fpga_dev[i].pid_chunks[0];

        // initialize device spinlock
        spin_lock_init(&d->fpga_dev[i].irq_lock);
        mutex_init(&d->fpga_dev[i].mmu_lock);
        mutex_init(&d->fpga_dev[i].offload_lock);
        mutex_init(&d->fpga_dev[i].sync_lock);
        spin_lock_init(&d->fpga_dev[i].pid_lock);

        // initialize workqueues
        d->fpga_dev[i].wqueue_pfault = alloc_workqueue(DRV_NAME, WQ_UNBOUND | WQ_MEM_RECLAIM, 0);
        if(!d->fpga_dev[i].wqueue_pfault) {
            pr_err("page fault work queue not initialized\n");
            goto err_pfault_wqueue;
        }

        d->fpga_dev[i].wqueue_notify = alloc_workqueue(DRV_NAME, WQ_UNBOUND | WQ_MEM_RECLAIM, 0);
        if(!d->fpga_dev[i].wqueue_notify) {
            pr_err("notify work queue not initialized\n");
            goto err_notify_wqueue;
        }

        // initialize waitqueues
        init_waitqueue_head(&d->fpga_dev[i].waitqueue_invldt);
        atomic_set(&d->fpga_dev[i].wait_invldt, 0);
        
        init_waitqueue_head(&d->fpga_dev[i].waitqueue_offload);
        atomic_set(&d->fpga_dev[i].wait_offload, 0);

        init_waitqueue_head(&d->fpga_dev[i].waitqueue_sync);
        atomic_set(&d->fpga_dev[i].wait_sync, 0);

        // writeback setup
        if(d->en_wb) {
            d->fpga_dev[i].wb_addr_virt  = dma_alloc_coherent(&d->pci_dev->dev, WB_SIZE, &d->fpga_dev[i].wb_phys_addr, GFP_KERNEL);
            if(!d->fpga_dev[i].wb_addr_virt) {
                pr_err("failed to allocate writeback memory\n");
                goto err_wb;
            }

            for(j = 0; j < WB_BLOCKS; j++)
                    d->fpga_dev[i].fpga_cnfg->wback[j] = d->fpga_dev[i].wb_phys_addr + j*(N_CPID_MAX * sizeof(uint32_t));

            pr_info("allocated memory for descriptor writeback, vaddr %llx, paddr %llx",
                    (uint64_t)d->fpga_dev[i].wb_addr_virt, d->fpga_dev[i].wb_phys_addr);
        }

        // create device
        devno = MKDEV(d->fpga_major, i);

        sprintf(vf_dev_name_tmp, "%s_v%d", d->vf_dev_name, i);
        device_create(d->fpga_class, NULL, devno, NULL, vf_dev_name_tmp, i);
        pr_info("virtual FPGA device %d created\n", i);

        // add device
        cdev_init(&d->fpga_dev[i].cdev, &fpga_fops);
        d->fpga_dev[i].cdev.owner = THIS_MODULE;
        d->fpga_dev[i].cdev.ops = &fpga_fops;

        // Init hash
        for(j = 0; j < N_CPID_MAX; j++)
            hash_init(user_buff_map[i][j]);

        ret_val = cdev_add(&d->fpga_dev[i].cdev, devno, 1);
        if (ret_val) {
            pr_err("could not create a virtual FPGA device %d\n", i);
            goto err_char_reg;
        }
    }
    pr_info("all virtual FPGA devices added\n");

    goto end;

err_char_reg:
    for (j = 0; j < i; j++) {
        device_destroy(d->fpga_class, MKDEV(d->fpga_major, j));
        cdev_del(&d->fpga_dev[j].cdev);
    }
    if(d->en_wb) {
        set_memory_wb((uint64_t)d->fpga_dev[i].wb_addr_virt, N_WB_PAGES);
        dma_free_coherent(&d->pci_dev->dev, WB_SIZE, d->fpga_dev[i].wb_addr_virt, d->fpga_dev[i].wb_phys_addr);
    }
err_wb:
    if(d->en_wb) {
        for (j = 0; j < i; j++) {
            set_memory_wb((uint64_t)d->fpga_dev[j].wb_addr_virt, N_WB_PAGES);
            dma_free_coherent(&d->pci_dev->dev, WB_SIZE, d->fpga_dev[j].wb_addr_virt, d->fpga_dev[j].wb_phys_addr);
        }
    }
    destroy_workqueue(d->fpga_dev[i].wqueue_notify);
err_notify_wqueue:
    for (j = 0; j < i; j++) {
        destroy_workqueue(d->fpga_dev[j].wqueue_notify);
    }
    destroy_workqueue(d->fpga_dev[i].wqueue_pfault);
err_pfault_wqueue:
    for (j = 0; j < i; j++) {
        destroy_workqueue(d->fpga_dev[j].wqueue_pfault);
    }
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
    ret_val = -ENOMEM;
end:
    return ret_val;
}

/**
 * @brief Delete vFPGAs
 * 
 */
void free_fpga_devices(struct bus_drvdata *d) {
    int i;

    for(i = 0; i < d->n_fpga_reg; i++) {
        device_destroy(d->fpga_class, MKDEV(d->fpga_major, i));
        cdev_del(&d->fpga_dev[i].cdev);

        if(d->en_wb) {
            set_memory_wb((uint64_t)d->fpga_dev[i].wb_addr_virt, N_WB_PAGES);
            dma_free_coherent(&d->pci_dev->dev, WB_SIZE, d->fpga_dev[i].wb_addr_virt, d->fpga_dev[i].wb_phys_addr);
        }

        destroy_workqueue(d->fpga_dev[i].wqueue_notify);
        destroy_workqueue(d->fpga_dev[i].wqueue_pfault);

        vfree(d->fpga_dev[i].pid_array);
        vfree(d->fpga_dev[i].pid_chunks);
    }

    pr_info("vFPGAs deleted\n");
}

/**
 * @brief Initialize PR
 */
int init_pr_device(struct bus_drvdata *d)
{
    int ret_val = 0;
    int devno;

    // PCI device
    d->pr_dev->pd = d;

    // initialize device spinlock
    spin_lock_init(&d->pr_dev->irq_lock);
    mutex_init(&d->pr_dev->rcnfg_lock);
    spin_lock_init(&d->pr_dev->mem_lock);

    // initialize waitqueues
    init_waitqueue_head(&d->pr_dev->waitqueue_rcnfg);
    atomic_set(&d->pr_dev->wait_rcnfg, FLAG_CLR);

    // create device
    devno = MKDEV(d->pr_major, 0);
    device_create(d->pr_class, NULL, devno, NULL, d->pr_dev_name, 0);
    pr_info("reconfiguration device created\n");

    // add device
    cdev_init(&d->pr_dev->cdev, &pr_fops);
    d->pr_dev->cdev.owner = THIS_MODULE;
    d->pr_dev->cdev.ops = &pr_fops;

    hash_init(pr_buff_map);

    ret_val = cdev_add(&d->pr_dev->cdev, devno, 1);
    if (ret_val) {
        pr_err("could not create a reconfiguration device\n");
        goto err_char_reg;
    }
    pr_info("reconfiguration device added\n");

    goto end;

err_char_reg:
    device_destroy(d->pr_class, MKDEV(d->pr_major, 0));
    cdev_del(&d->pr_dev->cdev);
end:
    return ret_val;
}

/**
 * @brief Delete PR
 * 
 */
void free_pr_device(struct bus_drvdata *d) {
    device_destroy(d->pr_class, MKDEV(d->pr_major, 0));
    cdev_del(&d->pr_dev->cdev);

    pr_info("reconfig dev deleted\n");
}


