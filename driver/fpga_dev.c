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
#include "fpga_sysfs.h"

int fpga_major = FPGA_MAJOR;
struct class *fpga_class = NULL;

/**
 * @brief Fops
 * 
 */
struct file_operations fpga_fops = {
    .owner = THIS_MODULE,
    .open = fpga_open,
    .release = fpga_release,
    .mmap = fpga_mmap,
    .unlocked_ioctl = fpga_ioctl,
};

/**
 * @brief Sysfs
 * 
 */
static struct kobj_attribute kobj_attr_ip_q0 = __ATTR(cyt_attr_ip_q0, 0664, cyt_attr_ip_q0_show, cyt_attr_ip_q0_store);
static struct kobj_attribute kobj_attr_ip_q1 = __ATTR(cyt_attr_ip_q1, 0664, cyt_attr_ip_q1_show, cyt_attr_ip_q1_store);
static struct kobj_attribute kobj_attr_mac_q0 = __ATTR(cyt_attr_mac_q0, 0664, cyt_attr_mac_q0_show, cyt_attr_mac_q0_store);
static struct kobj_attribute kobj_attr_mac_q1 = __ATTR(cyt_attr_mac_q1, 0664, cyt_attr_mac_q1_show, cyt_attr_mac_q1_store);
static struct kobj_attribute kobj_attr_nstats_q0 = __ATTR_RO(cyt_attr_nstats_q0);
static struct kobj_attribute kobj_attr_nstats_q1 = __ATTR_RO(cyt_attr_nstats_q1);
static struct kobj_attribute kobj_attr_xstats = __ATTR_RO(cyt_attr_xstats);
static struct kobj_attribute kobj_attr_cnfg = __ATTR_RO(cyt_attr_cnfg);
static struct kobj_attribute kobj_attr_eost = __ATTR(cyt_attr_eost, 0664, cyt_attr_eost_show, cyt_attr_eost_store);

static struct attribute *attrs[] = {
    &kobj_attr_ip_q0.attr,
    &kobj_attr_ip_q1.attr,
    &kobj_attr_mac_q0.attr,
    &kobj_attr_mac_q1.attr,
    &kobj_attr_nstats_q0.attr,
    &kobj_attr_nstats_q1.attr,
    &kobj_attr_xstats.attr,
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
int read_static_config(struct bus_drvdata *d) 
{
    long tmp;
    int ret_val = 0;

    // probe
    d->probe = d->fpga_stat_cnfg->probe;
    pr_info("deployment id %08x\n", d->probe);

    // channels and regions
    d->n_fpga_chan = d->fpga_stat_cnfg->n_chan;
    d->n_fpga_reg = d->fpga_stat_cnfg->n_regions;
    pr_info("detected %d virtual FPGA regions, %d FPGA channels\n", d->n_fpga_reg, d->n_fpga_chan);

    // flags
    d->en_avx = (d->fpga_stat_cnfg->ctrl_cnfg & EN_AVX_MASK) >> EN_AVX_SHFT;
    d->en_bypass = (d->fpga_stat_cnfg->ctrl_cnfg & EN_BPSS_MASK) >> EN_BPSS_SHFT;
    d->en_tlbf = (d->fpga_stat_cnfg->ctrl_cnfg & EN_TLBF_MASK) >> EN_TLBF_SHFT;
    d->en_wb = (d->fpga_stat_cnfg->ctrl_cnfg & EN_WB_MASK) >> EN_WB_SHFT;
    pr_info("enabled AVX %d, enabled bypass %d, enabled tlb fast %d, enabled writeback %d\n", d->en_avx, d->en_bypass, d->en_tlbf, d->en_wb);
   
    // mmu
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

    // mem
    d->en_strm = (d->fpga_stat_cnfg->mem_cnfg & EN_STRM_MASK) >> EN_STRM_SHFT; 
    d->en_mem = (d->fpga_stat_cnfg->mem_cnfg & EN_MEM_MASK) >> EN_MEM_SHFT;
    pr_info("enabled host streams %d, enabled card streams (mem) %d\n", d->en_strm, d->en_mem);

    // pr
    d->en_pr = (d->fpga_stat_cnfg->pr_cnfg & EN_PR_MASK) >> EN_PR_SHFT;
    pr_info("enabled PR %d\n", d->en_pr);

    // set eost
    if(d->en_pr) {
        d->eost = eost;
        d->fpga_stat_cnfg->pr_eost = eost;
        pr_info("set EOST [clks] %lld\n", d->eost);
    }

    // network
    d->en_rdma_0 = (d->fpga_stat_cnfg->rdma_cnfg & EN_RDMA_0_MASK) >> EN_RDMA_0_SHFT;
    d->en_rdma_1 = (d->fpga_stat_cnfg->rdma_cnfg & EN_RDMA_1_MASK) >> EN_RDMA_1_SHFT;
    pr_info("enabled RDMA on QSFP0 %d, enabled RDMA on QSFP1 %d\n", d->en_rdma_0, d->en_rdma_1);

    d->en_tcp_0 = (d->fpga_stat_cnfg->tcp_cnfg & EN_TCP_0_MASK) >> EN_TCP_0_SHFT;
    d->en_tcp_1 = (d->fpga_stat_cnfg->tcp_cnfg & EN_TCP_1_MASK) >> EN_TCP_1_SHFT;
    pr_info("enabled TCP/IP on QSFP0 %d, enabled TCP/IP on QSFP1 %d\n", d->en_tcp_0, d->en_tcp_1);

    // set ip and mac
    d->en_net_0 = d->en_rdma_0 | d->en_tcp_0;
    if(d->en_net_0) {
        ret_val = kstrtol(ip_addr_q0, 16, &tmp);
        d->net_0_ip_addr = (uint64_t) tmp;
        ret_val = kstrtol(mac_addr_q0, 16, &tmp);
        d->net_0_mac_addr = (uint64_t) tmp;
        d->fpga_stat_cnfg->net_0_ip = d->net_0_ip_addr;
        d->fpga_stat_cnfg->net_0_mac = d->net_0_mac_addr;
        pr_info("set QSFP0 ip %08x, mac %012llx\n", d->net_0_ip_addr, d->net_0_mac_addr);
    }
    d->en_net_1 = d->en_rdma_1 | d->en_tcp_1;
    if(d->en_net_1) {
        ret_val = kstrtol(ip_addr_q1, 16, &tmp);
        d->net_1_ip_addr = (uint64_t) tmp;
        ret_val = kstrtol(mac_addr_q1, 16, &tmp);
        d->net_1_mac_addr = (uint64_t) tmp;
        d->fpga_stat_cnfg->net_1_ip = d->net_1_ip_addr;
        d->fpga_stat_cnfg->net_1_mac = d->net_1_mac_addr;
        pr_info("set QSFP1 ip %08x, mac %012llx\n", d->net_1_ip_addr, d->net_1_mac_addr);
    }

    // lowspeed ctrl
    d->fpga_stat_cnfg->lspeed_cnfg = EN_LOWSPEED;

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
        d->lchunks[i].used = false;
        d->lchunks[i].id = i;
        d->lchunks[i].next = &d->lchunks[i + 1];
    }
    for (i = 0; i < N_SMALL_CHUNKS - 1; i++) {
        d->schunks[i].used = false;
        d->schunks[i].id = i;
        d->schunks[i].next = &d->schunks[i + 1];
    }
    d->lalloc = &d->lchunks[0];
    d->salloc = &d->schunks[0];

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
    // free card memory structs
    vfree(d->schunks);
    vfree(d->lchunks);

    pr_info("card resources deallocated\n");
}

/**
 * @brief Initialize spin locks
 * 
 */
void init_spin_locks(struct bus_drvdata *d) 
{
    // initialize spinlocks
    spin_lock_init(&d->card_l_lock);
    spin_lock_init(&d->card_s_lock);
    spin_lock_init(&d->prc.lock);
    spin_lock_init(&d->stat_lock);
    spin_lock_init(&d->prc_lock);
    spin_lock_init(&d->tlb_lock);
}

static struct kobj_type cyt_kobj_type = {
	.sysfs_ops	= &kobj_sysfs_ops,
};

/**
 * @brief Create sysfs entry
 * 
 */
int create_sysfs_entry(struct bus_drvdata *d) {
    int ret_val = 0;
    
    pr_info("creating sysfs entry - coyote_cnfg\n");

    ret_val = kobject_init_and_add(&d->cyt_kobj, &cyt_kobj_type, kernel_kobj, "coyote_cnfg");
    if(ret_val) {
        return -ENOMEM;
    }

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
    sysfs_remove_group(&d->cyt_kobj, &attr_group);
    kobject_put(&d->cyt_kobj);
}

/**
 * @brief Init char devices
 * 
 */
int init_char_devices(struct bus_drvdata *d, dev_t dev) 
{
    int ret_val = 0;

    ret_val = alloc_chrdev_region(&dev, 0, d->n_fpga_reg, DEV_NAME);
    fpga_major = MAJOR(dev);
    if (ret_val) {
        pr_err("failed to register virtual FPGA devices");
        goto end;
    }
    pr_info("virtual FPGA device regions allocated, major number %d\n", fpga_major);

    // create device class
    fpga_class = class_create(THIS_MODULE, DEV_NAME);

    // virtual FPGA devices
    d->fpga_dev = kmalloc(d->n_fpga_reg * sizeof(struct fpga_dev), GFP_KERNEL);
    if (!d->fpga_dev) {
        pr_err("could not allocate memory for fpga devices\n");
        goto err_char_mem; // ERR_CHAR_MEM
    }
    memset(d->fpga_dev, 0, d->n_fpga_reg * sizeof(struct fpga_dev));
    pr_info("allocated memory for fpga devices\n");

    goto end;

err_char_mem:
    unregister_chrdev_region(dev, d->n_fpga_reg);
    ret_val = -ENOMEM;
end:
    return ret_val;
}

/**
 * @brief Delete char devices
 * 
 */
void free_char_devices(struct bus_drvdata *d) 
{
    // free virtual FPGA memory
    kfree(d->fpga_dev);
    pr_info("virtual FPGA device memory freed\n");

    // remove class
    class_destroy(fpga_class);
    pr_info("fpga class deleted\n");
    
    // remove char devices
    unregister_chrdev_region(MKDEV(fpga_major, 0), d->n_fpga_reg);
    pr_info("char devices unregistered\n");
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

    for (i = 0; i < d->n_fpga_reg; i++) {
        // ID
        d->fpga_dev[i].id = i;

        // PCI device
        d->fpga_dev[i].pd = d;
        d->fpga_dev[i].prc = &d->prc;

        // physical
        if(cyt_arch == CYT_ARCH_PCI) {
            d->fpga_dev[i].fpga_phys_addr_ctrl = d->bar_phys_addr[BAR_FPGA_CONFIG] + FPGA_CTRL_OFFS + i * FPGA_CTRL_SIZE;
            d->fpga_dev[i].fpga_phys_addr_ctrl_avx = d->bar_phys_addr[BAR_FPGA_CONFIG] + FPGA_CTRL_CNFG_AVX_OFFS + i * FPGA_CTRL_CNFG_AVX_SIZE;
        } else if(cyt_arch == CYT_ARCH_ECI) {
            d->fpga_dev[i].fpga_phys_addr_ctrl = d->io_phys_addr + FPGA_CTRL_OFFS + i*FPGA_CTRL_SIZE;
        }

        // MMU control region
        d->fpga_dev[i].fpga_lTlb = ioremap(d->fpga_dev[i].fpga_phys_addr_ctrl + FPGA_CTRL_LTLB_OFFS, FPGA_CTRL_LTLB_SIZE);
        d->fpga_dev[i].fpga_sTlb = ioremap(d->fpga_dev[i].fpga_phys_addr_ctrl + FPGA_CTRL_STLB_OFFS, FPGA_CTRL_STLB_SIZE);

        // FPGA engine control
        d->fpga_dev[i].fpga_cnfg = ioremap(d->fpga_dev[i].fpga_phys_addr_ctrl + FPGA_CTRL_CNFG_OFFS, FPGA_CTRL_CNFG_SIZE);

        // FPGA engine control AVX
        if(cyt_arch == CYT_ARCH_PCI) {
            d->fpga_dev[i].fpga_cnfg_avx = ioremap(d->fpga_dev[i].fpga_phys_addr_ctrl_avx, FPGA_CTRL_CNFG_AVX_SIZE);
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
            d->fpga_dev[i].pid_chunks[j].used = false;
            d->fpga_dev[i].pid_chunks[j].id = j;
            d->fpga_dev[i].pid_chunks[j].next = &d->fpga_dev[i].pid_chunks[j + 1];
        }
        d->fpga_dev[i].pid_alloc = &d->fpga_dev[i].pid_chunks[0];

        // initialize device spinlock
        spin_lock_init(&d->fpga_dev[i].lock);
        spin_lock_init(&d->fpga_dev[i].card_pid_lock);

        // writeback setup
        if(d->en_wb) {
            d->fpga_dev[i].wb_addr_virt = dma_alloc_coherent(&d->pci_dev->dev, WB_SIZE, &d->fpga_dev[i].wb_phys_addr, GFP_ATOMIC);
            if(!d->fpga_dev[i].wb_addr_virt) {
                pr_err("failed to allocate writeback memory\n");
                goto err_wb;
            }

            if(cyt_arch == CYT_ARCH_PCI && d->en_avx) {
                for(j = 0; j < WB_BLOCKS; j++)
                    d->fpga_dev[i].fpga_cnfg_avx->wback[j] = d->fpga_dev[i].wb_phys_addr + j*(N_CPID_MAX * sizeof(uint32_t));
            } else {
                for(j = 0; j < WB_BLOCKS; j++)
                    d->fpga_dev[i].fpga_cnfg->wback[j] = d->fpga_dev[i].wb_phys_addr + j*(N_CPID_MAX * sizeof(uint32_t));
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
        hash_init(pid_cpid_map[i]);
        hash_init(user_lbuff_map[i]);
        hash_init(user_sbuff_map[i]);

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
        device_destroy(fpga_class, MKDEV(fpga_major, j));
        cdev_del(&d->fpga_dev[j].cdev);
    }
err_wb:
    if(d->en_wb) {
        for (j = 0; j < i; j++) {
            set_memory_wb((uint64_t)d->fpga_dev[j].wb_addr_virt, N_WB_PAGES);
            dma_free_coherent(&d->pci_dev->dev, WB_SIZE,
                d->fpga_dev[j].wb_addr_virt, d->fpga_dev[j].wb_phys_addr);
        }
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
        device_destroy(fpga_class, MKDEV(fpga_major, i));
        cdev_del(&d->fpga_dev[i].cdev);

        if(d->en_wb) {
            set_memory_wb((uint64_t)d->fpga_dev[i].wb_addr_virt, N_WB_PAGES);
            dma_free_coherent(&d->pci_dev->dev, WB_SIZE,
                d->fpga_dev[i].wb_addr_virt, d->fpga_dev[i].wb_phys_addr);
        }

        vfree(d->fpga_dev[i].pid_array);
        vfree(d->fpga_dev[i].pid_chunks);
    }

    pr_info("vFPGAs deleted\n");
}
