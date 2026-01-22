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

#include "coyote_setup.h"

////////////////////////////////////////////////
//            SHELL CONFIGURATION             //  
////////////////////////////////////////////////    

int read_shell_config(struct bus_driver_data *data) {
    int ret_val = 0;

    data->probe_stat = data->stat_cnfg->probe;
    dbg_info("deployment static probe %08x\n", data->probe_stat);
    data->probe_shell = data->shell_cnfg->probe;
    dbg_info("deployment shell probe %08x\n", data->probe_shell);

    data->n_fpga_chan = data->shell_cnfg->n_chan;
    data->n_fpga_reg = data->shell_cnfg->n_regions;
    dbg_info("detected %d virtual FPGA regions, %d FPGA channels\n", data->n_fpga_reg, data->n_fpga_chan);

    data->en_avx = (data->shell_cnfg->ctrl_cnfg & EN_AVX_MASK) >> EN_AVX_SHIFT;
    data->en_wb = (data->shell_cnfg->ctrl_cnfg & EN_WB_MASK) >> EN_WB_SHIFT;
    dbg_info("enabled AVX %d, enabled writeback %d\n", data->en_avx,data->en_wb);
   
    data->stlb_meta = kzalloc(sizeof(struct tlb_metadata), GFP_KERNEL);
    BUG_ON(!data->stlb_meta);
    data->stlb_meta->hugepage = false;
    data->stlb_meta->key_size = (data->shell_cnfg->ctrl_cnfg & TLB_S_ORDER_MASK) >> TLB_S_ORDER_SHIFT;
    data->stlb_meta->assoc = (data->shell_cnfg->ctrl_cnfg & TLB_S_ASSOC_MASK) >> TLB_S_ASSOC_SHIFT;
    data->stlb_meta->page_shift = (data->shell_cnfg->ctrl_cnfg & TLB_S_PG_SHFT_MASK) >> TLB_S_PG_SHIFT_SHIFT;
    BUG_ON(data->stlb_meta->page_shift != PAGE_SHIFT);
    data->stlb_meta->page_size = PAGE_SIZE;
    data->stlb_meta->page_mask = PAGE_MASK;
    data->stlb_meta->key_mask = (1UL << data->stlb_meta->key_size) - 1UL;
    data->stlb_meta->tag_size = TLB_VADDR_RANGE - data->stlb_meta->page_shift - data->stlb_meta->key_size;
    data->stlb_meta->tag_mask = (1UL << data->stlb_meta->tag_size) - 1UL;
    data->stlb_meta->phy_size = TLB_PADDR_RANGE - data->stlb_meta->page_shift;
    data->stlb_meta->phy_mask = (1UL << data->stlb_meta->phy_size) - 1UL;
    dbg_info("sTLB order %lld, sTLB assoc %d, sTLB page size %lld\n", data->stlb_meta->key_size, data->stlb_meta->assoc, data->stlb_meta->page_size);

    data->ltlb_meta = kzalloc(sizeof(struct tlb_metadata), GFP_KERNEL);
    BUG_ON(!data->ltlb_meta);
    data->ltlb_meta->hugepage = true;
    data->ltlb_meta->key_size = (data->shell_cnfg->ctrl_cnfg & TLB_L_ORDER_MASK) >> TLB_L_ORDER_SHIFT;
    data->ltlb_meta->assoc = (data->shell_cnfg->ctrl_cnfg & TLB_L_ASSOC_MASK) >> TLB_L_ASSOC_SHIFT;
    data->ltlb_meta->page_shift = (data->shell_cnfg->ctrl_cnfg & TLB_L_PG_SHFT_MASK) >> TLB_L_PG_SHIFT_SHIFT;
    data->ltlb_meta->page_size = 1UL << data->ltlb_meta->page_shift;
    data->ltlb_meta->page_mask = (~(data->ltlb_meta->page_size - 1));
    data->ltlb_meta->key_mask = (1UL << data->ltlb_meta->key_size) - 1UL;
    data->ltlb_meta->tag_size = TLB_VADDR_RANGE - data->ltlb_meta->page_shift  - data->ltlb_meta->key_size;
    data->ltlb_meta->tag_mask = (1UL << data->ltlb_meta->tag_size) - 1UL;
    data->ltlb_meta->phy_size = TLB_PADDR_RANGE - data->ltlb_meta->page_shift ;
    data->ltlb_meta->phy_mask = (1UL << data->ltlb_meta->phy_size) - 1UL;
    dbg_info("lTLB order %lld, lTLB assoc %d, lTLB page size %lld\n", data->ltlb_meta->key_size, data->ltlb_meta->assoc, data->ltlb_meta->page_size);

    data->dif_order_page_shift = data->ltlb_meta->page_shift - data->stlb_meta->page_shift;
    data->dif_order_page_size = 1 << data->dif_order_page_shift;
    data->dif_order_page_mask = data->dif_order_page_size - 1;
    data->n_pages_in_huge = 1 << data->dif_order_page_shift;

    data->en_strm = (data->shell_cnfg->mem_cnfg & EN_STRM_MASK) >> EN_STRM_SHIFT; 
    data->en_mem = (data->shell_cnfg->mem_cnfg & EN_MEM_MASK) >> EN_MEM_SHIFT;
    dbg_info("enabled host streams %d, enabled card streams (mem) %d\n", data->en_strm, data->en_mem);

    data->card_huge_offs = MEM_SEP;
    data->card_reg_offs = MEM_START;

    data->en_pr = (data->shell_cnfg->pr_cnfg & EN_PR_MASK) >> EN_PR_SHIFT;
    dbg_info("enabled partial reconfiguration %d\n", data->en_pr);

    if(data->en_pr) {
        data->eost = eost;
        data->stat_cnfg->reconfig_eost = eost;
        dbg_info("set EOST [clks] %lld\n", data->eost);
    }

    data->en_rdma = (data->shell_cnfg->rdma_cnfg & EN_RDMA_MASK) >> EN_RDMA_SHIFT;
    data->qsfp = (data->shell_cnfg->rdma_cnfg & QSFP_MASK) >> QSFP_SHIFT;
    dbg_info("enabled RDMA %d, port %d\n", data->en_rdma, data->qsfp);

    data->en_tcp = (data->shell_cnfg->tcp_cnfg & EN_TCP_MASK) >> EN_TCP_SHIFT;
    dbg_info("enabled TCP/IP %d, port %d\n", data->en_tcp, data->qsfp);

    data->en_net = data->en_rdma | data->en_tcp;
    if(data->en_net) {
        long tmp;
        ret_val = kstrtol(ip_addr, 16, &tmp);
        data->net_ip_addr = (uint64_t) tmp;
        ret_val = kstrtol(mac_addr, 16, &tmp);
        data->net_mac_addr = (uint64_t) tmp;
        data->shell_cnfg->net_ip = data->net_ip_addr;
        data->shell_cnfg->net_mac = data->net_mac_addr;
        dbg_info("set network ip %08x, mac %012llx\n", data->net_ip_addr, data->net_mac_addr);
    }

    return ret_val;
}

////////////////////////////////////////////////
//      CARD MEMORY RESOURCES & SPIN LOCKS    //  
////////////////////////////////////////////////   

int allocate_card_resources(struct bus_driver_data *data) {
    int ret_val = 0;
    
    // If the shell was synthesized with memory enabled, allocate the card memory metadata structures
    // We use the chunk struct (defined in coyote_defs.h), to keep track of the next chunk to use for allocation, no. of free chunks etc.
    // Separate allocations for large and small chunks, corresponding to regular and huge pages
    if (data->en_mem) {
        data->num_free_lchunks = N_LARGE_CHUNKS;
        data->num_free_schunks = N_SMALL_CHUNKS;

        data->lchunks = vzalloc(N_LARGE_CHUNKS * sizeof(struct chunk));
        if (!data->lchunks) {
            pr_err("memory regison for larger card memory structs could not obtained\n");
            goto err_alloc_lchunks;
        }
        data->schunks = vzalloc(N_SMALL_CHUNKS * sizeof(struct chunk));
        if (!data->schunks) {
            pr_err("memory regison for small card memory structs could not obtained\n");
            goto err_alloc_schunks;
        }

        for (int i = 0; i < N_LARGE_CHUNKS - 1; i++) {
            data->lchunks[i].id = i;
            data->lchunks[i].used = false;
            data->lchunks[i].next = &data->lchunks[i + 1];
        }
        for (int i = 0; i < N_SMALL_CHUNKS - 1; i++) {
            data->schunks[i].id = i;
            data->schunks[i].used = false;
            data->schunks[i].next = &data->schunks[i + 1];
        }
        data->lalloc = &data->lchunks[0];
        data->salloc = &data->schunks[0];
    }

    goto end;

err_alloc_schunks:
    vfree(data->lchunks);
err_alloc_lchunks: 
    ret_val = -ENOMEM;
end: 
    return ret_val;
}

void free_card_resources(struct bus_driver_data *data) {
    if (data->en_mem) {
        // Free the dynamically allocated card memory structs from allocate_card_resources
        vfree(data->schunks);
        vfree(data->lchunks);

        dbg_info("card resources deallocated\n");
    }
}

void init_spin_locks(struct bus_driver_data *data) {
    spin_lock_init(&data->card_lock);
    spin_lock_init(&data->stat_lock);
}

////////////////////////////////////////////////
//              SYSFS SET-UP                  //  
////////////////////////////////////////////////    

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

static struct kobj_type cyt_kobj_type = {
	.sysfs_ops	= &kobj_sysfs_ops
};

int create_sysfs_entry(struct bus_driver_data *data) {
    int ret_val = 0;
    char sysfs_name[MAX_CHAR_FDEV];
    sprintf(sysfs_name, "coyote_sysfs_%d", data->dev_id);
    
    dbg_info("creating sysfs entry...\n");

    ret_val = kobject_init_and_add(&data->cyt_kobj, &cyt_kobj_type, kernel_kobj, sysfs_name);
    if(ret_val) {
        return -ENOMEM;
    }

    kobject_uevent(&data->cyt_kobj, KOBJ_ADD);

    ret_val = sysfs_create_group(&data->cyt_kobj, &attr_group);
    if (ret_val) {
        return -ENODEV;
    }

    return ret_val;
}

void remove_sysfs_entry(struct bus_driver_data *data) {
    dbg_info("removing sysfs entry...\n");
    sysfs_remove_group(&data->cyt_kobj, &attr_group);
    kobject_put(&data->cyt_kobj);
    data->cyt_kobj = cyt_kobj_empty;
}

////////////////////////////////////////////////
//              vFPGA DEVICE                  //  
////////////////////////////////////////////////    

// vFPGA device file operations; implemented in vfpga_ops.c
struct file_operations vfpga_ops = {
    .owner = THIS_MODULE,
    .open = vfpga_dev_open,
    .release = vfpga_dev_release,
    .unlocked_ioctl = vfpga_dev_ioctl,
    .mmap = vfpga_dev_mmap,
};

#define FPGA_CLASS_MODE ((umode_t)(S_IRUGO | S_IWUGO))
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 0, 0)
static char *fpga_class_devnode(const struct device *dev, umode_t *mode)
#else
static char *fpga_class_devnode(struct device *dev, umode_t *mode)
#endif
{
    if (mode != NULL)
        *mode = FPGA_CLASS_MODE;
    return NULL;
}

int alloc_vfpga_devices(struct bus_driver_data *data, dev_t dev) {
    int ret_val = 0;

    // Allocate a region for the n_fpga_reg vFPGA devices and obtain their major number
    ret_val = alloc_chrdev_region(&dev, 0, data->n_fpga_reg, data->vfpga_dev_name);
    data->vfpga_major = MAJOR(dev);
    if (ret_val) {
        pr_err("failed to register vFPGA devices");
        goto end;
    }
    dbg_info("vFPGA device regions allocated, major number %d\n", data->vfpga_major);

    // Create a class for the vFPGA devicse; initialized in the function setup_vfpga_device
    #if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 5, 0)        
        data->vfpga_class = class_create(data->vfpga_dev_name);   
    #else        
        data->vfpga_class = class_create(THIS_MODULE, data->vfpga_dev_name);    
    #endif
    data->vfpga_class->devnode = fpga_class_devnode;

    // Allocate memory for the vFPGA device structure, which holds its information, locks, wait-queues, maps etc.
    data->vfpga_dev = kmalloc(data->n_fpga_reg * sizeof(struct vfpga_dev), GFP_KERNEL);
    if (!data->vfpga_dev) {
        pr_err("could not allocate memory for vFPGAs\n");
        goto err_fpga_char_mem; // ERR_CHAR_MEM
    }
    memset(data->vfpga_dev, 0, data->n_fpga_reg * sizeof(struct vfpga_dev));
    dbg_info("allocated memory for fpga devices\n");

    goto end;

err_fpga_char_mem:
    class_destroy(data->vfpga_class);
    unregister_chrdev_region(dev, data->n_fpga_reg);
    ret_val = -ENOMEM;
end:
    return ret_val;
}

int setup_vfpga_devices(struct bus_driver_data *data) {
    int ret_val = 0;
    char vf_dev_name_tmp[MAX_CHAR_FDEV];

    // Iterate through the number of FPGA regions and set up each vFPGA device
    int i = 0;
    for (i = 0; i < data->n_fpga_reg; i++) {
        // Reset variables
        data->vfpga_dev[i].id = i;
        data->vfpga_dev[i].ref_cnt = 0;

        // Assign PCI device to data struct
        data->vfpga_dev[i].bd_data = data;

        // Set physical address of control registers (AVX + non-AVX)
        data->vfpga_dev[i].vfpga_cnfg_phys_addr = data->bar_phys_addr[BAR_SHELL_CONFIG] + VFPGA_CTRL_OFFS + i * VFPGA_CTRL_SIZE;
        data->vfpga_dev[i].vfpga_cnfg_avx_phys_addr = data->bar_phys_addr[BAR_SHELL_CONFIG] + VFPGA_CTRL_CNFG_AVX_OFFS + i * VFPGA_CTRL_CNFG_AVX_SIZE;
        
        // Memory map the control registers for MMU and shell configuration
        data->vfpga_dev[i].fpga_lTlb = ioremap(data->vfpga_dev[i].vfpga_cnfg_phys_addr + VFPGA_CTRL_LTLB_OFFS, VFPGA_CTRL_LTLB_SIZE);
        data->vfpga_dev[i].fpga_sTlb = ioremap(data->vfpga_dev[i].vfpga_cnfg_phys_addr + VFPGA_CTRL_STLB_OFFS, VFPGA_CTRL_STLB_SIZE);
        if(data->en_avx) {
            data->vfpga_dev[i].cnfg_regs = ioremap(data->vfpga_dev[i].vfpga_cnfg_avx_phys_addr, VFPGA_CTRL_CNFG_AVX_SIZE);
        } else {
            data->vfpga_dev[i].cnfg_regs = ioremap(data->vfpga_dev[i].vfpga_cnfg_phys_addr + VFPGA_CTRL_CNFG_OFFS, VFPGA_CTRL_CNFG_SIZE);
        }

        // Initialize variables for Coyote threads; one for each thread per vFPGA; max is N_CTID_MAX
        // Number of free Coyote threads in this vFPGA; variable incremented every time a Coyote thread is created
        data->vfpga_dev[i].num_free_ctid_chunks = N_CTID_MAX;
        
        // Allocated memory for the Coyote thread chunks; each chunk is a struct with an ID, used flag and a pointer to the next chunk
        data->vfpga_dev[i].ctid_chunks = vzalloc(N_CTID_MAX * sizeof(struct chunk));
        if (!data->vfpga_dev[i].ctid_chunks) {
            pr_err("memory region for pid chunks not obtained\n");
            goto err_alloc_pid_chunks;
        }

        // Host process ID (pid) associated with the Coyote threads
        data->vfpga_dev[i].pid_array = vzalloc(N_CTID_MAX * sizeof(pid_t));
        if (!data->vfpga_dev[i].pid_array) {
            pr_err("memory region for pid array not obtained\n");
            goto err_alloc_pid_array;
        }

        // Variable housekeeping for Coyote threads; ID starts from 0, increments by 1
        for (int j = 0; j < N_CTID_MAX - 1; j++) {
            data->vfpga_dev[i].ctid_chunks[j].id = j;
            data->vfpga_dev[i].ctid_chunks[j].used = false;
            data->vfpga_dev[i].ctid_chunks[j].next = &data->vfpga_dev[i].ctid_chunks[j + 1];
        }
        data->vfpga_dev[i].pid_alloc = &data->vfpga_dev[i].ctid_chunks[0];

        // Initialize device spinlocks and mutexes
        spin_lock_init(&data->vfpga_dev[i].irq_lock);
        mutex_init(&data->vfpga_dev[i].mmu_lock);
        mutex_init(&data->vfpga_dev[i].offload_lock);
        mutex_init(&data->vfpga_dev[i].sync_lock);
        mutex_init(&data->vfpga_dev[i].pid_lock);

        // Initialize workqueues
        data->vfpga_dev[i].wqueue_pfault = alloc_workqueue(COYOTE_DRIVER_NAME, WQ_UNBOUND | WQ_MEM_RECLAIM, 0);
        if(!data->vfpga_dev[i].wqueue_pfault) {
            pr_err("page fault work queue not initialized\n");
            goto err_pfault_wqueue;
        }

        data->vfpga_dev[i].wqueue_notify = alloc_workqueue(COYOTE_DRIVER_NAME, WQ_UNBOUND | WQ_MEM_RECLAIM, 0);
        if(!data->vfpga_dev[i].wqueue_notify) {
            pr_err("notify work queue not initialized\n");
            goto err_notify_wqueue;
        }

        // initialize waitqueues
        init_waitqueue_head(&data->vfpga_dev[i].waitqueue_invldt);
        atomic_set(&data->vfpga_dev[i].wait_invldt, 0);
        
        init_waitqueue_head(&data->vfpga_dev[i].waitqueue_offload);
        atomic_set(&data->vfpga_dev[i].wait_offload, 0);

        init_waitqueue_head(&data->vfpga_dev[i].waitqueue_sync);
        atomic_set(&data->vfpga_dev[i].wait_sync, 0);

        // Set-up writeback memory if enabled; used for polling transfer completions
        if (data->en_wb) {
            data->vfpga_dev[i].wb_addr_virt  = dma_alloc_coherent(&data->pci_dev->dev, WB_SIZE, &data->vfpga_dev[i].wb_phys_addr, GFP_KERNEL);
            if (!data->vfpga_dev[i].wb_addr_virt) {
                pr_err("failed to allocate writeback memory\n");
                goto err_wb;
            }
            
            int ret_val = set_memory_uc((uint64_t) data->vfpga_dev[i].wb_addr_virt, N_WB_PAGES);
            if (ret_val) {
                pr_err("failed so set UC for writeback memory\n");
                goto err_wb;
            }

            for (int j = 0; j < WB_BLOCKS; j++) {
                data->vfpga_dev[i].cnfg_regs->wback[j] = data->vfpga_dev[i].wb_phys_addr + j * (N_CTID_MAX * sizeof(uint32_t));
            }

            dbg_info(
                "allocated memory for descriptor writeback, vaddr %llx, paddr %llx\n",
                (uint64_t)data->vfpga_dev[i].wb_addr_virt, data->vfpga_dev[i].wb_phys_addr
            );
        }

        // Create and initialize the device, by specifying its file operations; major number was obtained in alloc_reconfig_device
        int device_number = MKDEV(data->vfpga_major, i);

        sprintf(vf_dev_name_tmp, "%s_v%d", data->vfpga_dev_name, i);
        device_create(data->vfpga_class, NULL, device_number, NULL, vf_dev_name_tmp, i);
        dbg_info("virtual FPGA device %d created\n", i);

        cdev_init(&data->vfpga_dev[i].cdev, &vfpga_ops);
        data->vfpga_dev[i].cdev.owner = THIS_MODULE;
        data->vfpga_dev[i].cdev.ops = &vfpga_ops;

        // Initialize hashmaps; in this case only one which is used for keeping track of memory buffers and TLB mappings
        for (int j = 0; j < N_CTID_MAX; j++) {
            hash_init(user_buff_map[i][j]);
        }

        // Register each char vFPGA device with the kernel through cdev_add and the previously allocated unique device number
        ret_val = cdev_add(&data->vfpga_dev[i].cdev, device_number, 1);
        if (ret_val) {
            pr_err("could not create a virtual FPGA device %d\n", i);
            goto err_char_reg;
        }
    }

    dbg_info("all virtual FPGA devices added\n");

    goto end;

// Error handling; if any of the steps fail, clean up the previously allocated resources
err_char_reg:
    for (int j = 0; j < i; j++) {
        device_destroy(data->vfpga_class, MKDEV(data->vfpga_major, j));
        cdev_del(&data->vfpga_dev[j].cdev);
    }
	// Unmap control register regions if they were mapped
	if (data->vfpga_dev[i].fpga_lTlb) {
        iounmap(data->vfpga_dev[i].fpga_lTlb);
        data->vfpga_dev[i].fpga_lTlb = NULL;
    }
    if (data->vfpga_dev[i].fpga_sTlb) {
        iounmap(data->vfpga_dev[i].fpga_sTlb);
        data->vfpga_dev[i].fpga_sTlb = NULL;
    }
    if (data->vfpga_dev[i].cnfg_regs) {
        iounmap(data->vfpga_dev[i].cnfg_regs);
        data->vfpga_dev[i].cnfg_regs = NULL;
	}
    if (data->en_wb) {
        set_memory_wb((uint64_t)data->vfpga_dev[i].wb_addr_virt, N_WB_PAGES);
        dma_free_coherent(&data->pci_dev->dev, WB_SIZE, data->vfpga_dev[i].wb_addr_virt, data->vfpga_dev[i].wb_phys_addr);
    }
err_wb:
    if (data->en_wb) {
        for (int j = 0; j < i; j++) {
            set_memory_wb((uint64_t)data->vfpga_dev[j].wb_addr_virt, N_WB_PAGES);
            dma_free_coherent(&data->pci_dev->dev, WB_SIZE, data->vfpga_dev[j].wb_addr_virt, data->vfpga_dev[j].wb_phys_addr);
        }
    }
    destroy_workqueue(data->vfpga_dev[i].wqueue_notify);
err_notify_wqueue:
    for (int j = 0; j < i; j++) {
        destroy_workqueue(data->vfpga_dev[j].wqueue_notify);
    }
    destroy_workqueue(data->vfpga_dev[i].wqueue_pfault);
err_pfault_wqueue:
    for (int j = 0; j < i; j++) {
        destroy_workqueue(data->vfpga_dev[j].wqueue_pfault);
    }
    vfree(data->vfpga_dev[i].pid_array);
err_alloc_pid_array:
    for (int j = 0; j < i; j++) {
        vfree(data->vfpga_dev[j].pid_array);
    }
    vfree(data->vfpga_dev[i].ctid_chunks);
err_alloc_pid_chunks:
    for (int j = 0; j < i; j++) {
        vfree(data->vfpga_dev[j].ctid_chunks);
    }
    ret_val = -ENOMEM;
end:
    return ret_val;
}

void teardown_vfpga_devices(struct bus_driver_data *data) {
    // Iterate through all the vFPGA devices; releasing memory, work-queues etc.
    for (int i = 0; i < data->n_fpga_reg; i++) {
        device_destroy(data->vfpga_class, MKDEV(data->vfpga_major, i));
        cdev_del(&data->vfpga_dev[i].cdev);

        // Unmap control register regions if they were mapped
        if (data->vfpga_dev[i].fpga_lTlb) {
            iounmap(data->vfpga_dev[i].fpga_lTlb);
            data->vfpga_dev[i].fpga_lTlb = NULL;
        }
        if (data->vfpga_dev[i].fpga_sTlb) {
            iounmap(data->vfpga_dev[i].fpga_sTlb);
            data->vfpga_dev[i].fpga_sTlb = NULL;
        }
        if (data->vfpga_dev[i].cnfg_regs) {
            iounmap(data->vfpga_dev[i].cnfg_regs);
            data->vfpga_dev[i].cnfg_regs = NULL;
        }

        if(data->en_wb) {
            set_memory_wb((uint64_t)data->vfpga_dev[i].wb_addr_virt, N_WB_PAGES);
            dma_free_coherent(&data->pci_dev->dev, WB_SIZE, data->vfpga_dev[i].wb_addr_virt, data->vfpga_dev[i].wb_phys_addr);
        }

        destroy_workqueue(data->vfpga_dev[i].wqueue_notify);
        destroy_workqueue(data->vfpga_dev[i].wqueue_pfault);

        vfree(data->vfpga_dev[i].pid_array);
        vfree(data->vfpga_dev[i].ctid_chunks);
    }

    dbg_info("vFPGA devices deleted\n");
}

void free_vfpga_devices(struct bus_driver_data *data) {
    kfree(data->vfpga_dev);
    dbg_info("memory for vFPGA device freed\n");

    class_destroy(data->vfpga_class);
    dbg_info("vFPGA class deleted\n");
    
    unregister_chrdev_region(MKDEV(data->vfpga_major, 0), data->n_fpga_reg);
    dbg_info("unregistered char vFPGA devices\n");
}

////////////////////////////////////////////////
//          RECONFIGURATION DEVICE            //  
////////////////////////////////////////////////    

// Reconfiguration device file operations; implemented in reconfig_ops.c
struct file_operations reconfig_ops = {
    .owner = THIS_MODULE,
    .open = reconfig_dev_open,
    .release = reconfig_dev_release,
    .unlocked_ioctl = reconfig_dev_ioctl,
    .mmap = reconfig_dev_mmap,
};

int alloc_reconfig_device(struct bus_driver_data *data, dev_t device) {
    int ret_val = 0;

    // Allocate a region for the reconfiguration device and obtain its major number
    ret_val = alloc_chrdev_region(&device, 0, 1, data->reconfig_dev_name);
    data->reconfig_major = MAJOR(device);
    if (ret_val) {
        pr_err("failed to register reconfig device");
        goto end;
    }
    dbg_info("reconfig device regions allocated, major number %d\n", data->reconfig_major);

    // Create a class for the reconfiguration device; initialized in the function setup_reconfig_device
    #if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 5, 0)        
        data->reconfig_class = class_create(data->reconfig_dev_name);    
    #else        
        data->reconfig_class = class_create(THIS_MODULE, data->reconfig_dev_name);  
    #endif   
    data->reconfig_class->devnode = fpga_class_devnode;

    // Allocate memory for the reconfiguration device structure, which holds its information, locks, wait-queues, maps etc.
    data->reconfig_dev = kmalloc(sizeof(struct reconfig_dev), GFP_KERNEL);
    if (!data->reconfig_dev) {
        pr_err("could not allocate memory for reconfig device\n");
        goto err_pr_char_mem; // ERR_CHAR_MEM
    }
    memset(data->reconfig_dev, 0, sizeof(struct reconfig_dev));
    dbg_info("allocated memory for reconfig device\n");

    goto end;

err_pr_char_mem:
    class_destroy(data->reconfig_class);
    unregister_chrdev_region(device, 1);
    ret_val = -ENOMEM;
end:
    return ret_val;
}

int setup_reconfig_device(struct bus_driver_data *data) {
    int ret_val = 0;

    // Assign PCI device to data struct
    data->reconfig_dev->bd_data = data;

    // Initialize variables held by reconfig device
    hash_init(reconfig_buffs_map);
    mutex_init(&data->reconfig_dev->rcnfg_lock);
    spin_lock_init(&data->reconfig_dev->irq_lock);
    spin_lock_init(&data->reconfig_dev->mem_lock);
    init_waitqueue_head(&data->reconfig_dev->waitqueue_rcnfg);
    atomic_set(&data->reconfig_dev->wait_rcnfg, FLAG_CLR);

    // Create and initialize the device, by specifying its file operations; major number was obtained in alloc_reconfig_device
    // Returns a unique device number (major + minor no.) for the reconfiguration device
    int device_number = MKDEV(data->reconfig_major, 0);
    device_create(data->reconfig_class, NULL, device_number, NULL, data->reconfig_dev_name, 0);
    dbg_info("reconfiguration device created\n");

    cdev_init(&data->reconfig_dev->cdev, &reconfig_ops);
    data->reconfig_dev->cdev.owner = THIS_MODULE;
    data->reconfig_dev->cdev.ops = &reconfig_ops;
    
    // Register the char device with the kernel through cdev_add and the previously allocated unique device number
    ret_val = cdev_add(&data->reconfig_dev->cdev, device_number, 1);
    if (ret_val) {
        pr_err("could not create a reconfiguration device\n");
        goto err_char_reg;
    }
    dbg_info("reconfiguration device registered\n");

    goto end;

err_char_reg:
    device_destroy(data->reconfig_class, MKDEV(data->reconfig_major, 0));
    cdev_del(&data->reconfig_dev->cdev);
end:
    return ret_val;
}

void teardown_reconfig_device(struct bus_driver_data *data) {
    device_destroy(data->reconfig_class, MKDEV(data->reconfig_major, 0));
    cdev_del(&data->reconfig_dev->cdev);
    dbg_info("reconfig device deleted\n");
}

void free_reconfig_device(struct bus_driver_data *data) {
    kfree(data->reconfig_dev);
    dbg_info("memory for reconfig device freed\n");

    class_destroy(data->reconfig_class);
    dbg_info("reconfig class deleted\n");
    
    unregister_chrdev_region(MKDEV(data->reconfig_major, 0), 1);
    dbg_info("unregistered char reconfig device\n");
}
