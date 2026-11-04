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
    shell_info(data, "deployment static probe %08x\n", data->probe_stat);
    data->probe_shell = data->shell_cnfg->probe;
    shell_info(data, "deployment shell probe %08x\n", data->probe_shell);

    // All-ones reads: the static layer or the shell does not respond (not programmed, or a failed reconfiguration)
    if (data->probe_stat == ~0U || data->probe_shell == ~0U) {
        shell_err(data, "static layer or shell not responding, probe %08x/%08x\n", data->probe_stat, data->probe_shell);
        return -ENODEV;
    }

    data->n_fpga_chan = data->shell_cnfg->n_chan;
    data->n_fpga_reg = data->shell_cnfg->n_regions;
    shell_info(data, "detected %d virtual FPGA regions, %d FPGA channels\n", data->n_fpga_reg, data->n_fpga_chan);

    // Reject a configuration the driver cannot handle; vector 15 is for reconfiguration
    uint32_t s_pg_shift = (data->shell_cnfg->ctrl_cnfg & TLB_S_PG_SHFT_MASK) >> TLB_S_PG_SHIFT_SHIFT;
    uint32_t l_pg_shift = (data->shell_cnfg->ctrl_cnfg & TLB_L_PG_SHFT_MASK) >> TLB_L_PG_SHIFT_SHIFT;
    if (data->n_fpga_reg < 1 || data->n_fpga_reg > FPGA_RECONFIG_IRQ_VECTOR ||
        data->n_fpga_chan < 1 || data->n_fpga_chan > XDMA_MAX_NUM_CHANNELS ||
        s_pg_shift != PAGE_SHIFT || l_pg_shift <= PAGE_SHIFT || l_pg_shift > 30) {
        shell_err(data, "invalid shell config: %d regions, %d channels, ctrl_cnfg %llx\n",
            data->n_fpga_reg, data->n_fpga_chan, (uint64_t) data->shell_cnfg->ctrl_cnfg);
        data->n_fpga_reg = 0;
        return -ENODEV;
    }

    data->en_avx = (data->shell_cnfg->ctrl_cnfg & EN_AVX_MASK) >> EN_AVX_SHIFT;
    data->en_wb = (data->shell_cnfg->ctrl_cnfg & EN_WB_MASK) >> EN_WB_SHIFT;
    shell_info(data, "enabled AVX %d, enabled writeback %d\n", data->en_avx,data->en_wb);
   
    data->stlb_meta = kzalloc(sizeof(struct tlb_metadata), GFP_KERNEL);
    data->ltlb_meta = kzalloc(sizeof(struct tlb_metadata), GFP_KERNEL);
    if (!data->stlb_meta || !data->ltlb_meta) {
        data->n_fpga_reg = 0;
        return -ENOMEM;
    }
    data->stlb_meta->hugepage = false;
    data->stlb_meta->key_size = (data->shell_cnfg->ctrl_cnfg & TLB_S_ORDER_MASK) >> TLB_S_ORDER_SHIFT;
    data->stlb_meta->assoc = (data->shell_cnfg->ctrl_cnfg & TLB_S_ASSOC_MASK) >> TLB_S_ASSOC_SHIFT;
    data->stlb_meta->page_shift = s_pg_shift;
    data->stlb_meta->page_size = PAGE_SIZE;
    data->stlb_meta->page_mask = PAGE_MASK;
    data->stlb_meta->key_mask = (1UL << data->stlb_meta->key_size) - 1UL;
    data->stlb_meta->tag_size = TLB_VADDR_RANGE - data->stlb_meta->page_shift - data->stlb_meta->key_size;
    data->stlb_meta->tag_mask = (1UL << data->stlb_meta->tag_size) - 1UL;
    data->stlb_meta->phy_size = TLB_PADDR_RANGE - data->stlb_meta->page_shift;
    data->stlb_meta->phy_mask = (1UL << data->stlb_meta->phy_size) - 1UL;
    shell_info(data, "sTLB order %lld, sTLB assoc %d, sTLB page size %lld\n", data->stlb_meta->key_size, data->stlb_meta->assoc, data->stlb_meta->page_size);

    data->ltlb_meta->hugepage = true;
    data->ltlb_meta->key_size = (data->shell_cnfg->ctrl_cnfg & TLB_L_ORDER_MASK) >> TLB_L_ORDER_SHIFT;
    data->ltlb_meta->assoc = (data->shell_cnfg->ctrl_cnfg & TLB_L_ASSOC_MASK) >> TLB_L_ASSOC_SHIFT;
    data->ltlb_meta->page_shift = l_pg_shift;
    data->ltlb_meta->page_size = 1UL << data->ltlb_meta->page_shift;
    data->ltlb_meta->page_mask = (~(data->ltlb_meta->page_size - 1));
    data->ltlb_meta->key_mask = (1UL << data->ltlb_meta->key_size) - 1UL;
    data->ltlb_meta->tag_size = TLB_VADDR_RANGE - data->ltlb_meta->page_shift  - data->ltlb_meta->key_size;
    data->ltlb_meta->tag_mask = (1UL << data->ltlb_meta->tag_size) - 1UL;
    data->ltlb_meta->phy_size = TLB_PADDR_RANGE - data->ltlb_meta->page_shift ;
    data->ltlb_meta->phy_mask = (1UL << data->ltlb_meta->phy_size) - 1UL;
    shell_info(data, "lTLB order %lld, lTLB assoc %d, lTLB page size %lld\n", data->ltlb_meta->key_size, data->ltlb_meta->assoc, data->ltlb_meta->page_size);

    data->dif_order_page_shift = data->ltlb_meta->page_shift - data->stlb_meta->page_shift;
    data->dif_order_page_size = 1 << data->dif_order_page_shift;
    data->dif_order_page_mask = data->dif_order_page_size - 1;
    data->n_pages_in_huge = 1 << data->dif_order_page_shift;

    data->en_strm = (data->shell_cnfg->mem_cnfg & EN_STRM_MASK) >> EN_STRM_SHIFT; 
    data->en_mem = (data->shell_cnfg->mem_cnfg & EN_MEM_MASK) >> EN_MEM_SHIFT;
    shell_info(data, "enabled host streams %d, enabled card streams (mem) %d\n", data->en_strm, data->en_mem);

    data->n_host_axi = (data->shell_cnfg->mem_cnfg & N_STRM_AXI_MASK) >> N_STRM_AXI_SHIFT;
    data->n_card_axi = (data->shell_cnfg->mem_cnfg & N_CARD_AXI_MASK) >> N_CARD_AXI_SHIFT;
    shell_info(
        data, "number of host AXI interfaces %d, number of card AXI interfaces %d\n", 
        data->en_strm ? data->n_host_axi : 0, 
        data->en_mem ? data->n_card_axi : 0
    );

    data->en_block_mem = (data->shell_cnfg->mem_cnfg & EN_BLOCK_MEM_MASK) >> EN_BLOCK_MEM_SHIFT;
    shell_info(data, "enabled block memory implementation (Versal only): %d\n", data->en_block_mem);

    data->card_reg_offs = 0;
    data->card_huge_offs = N_SMALL_CHUNKS * data->stlb_meta->page_size;

    data->en_shell_pblock = (data->shell_cnfg->shell_pblock_cnfg & EN_SHELL_PBLOCK_MASK) >> EN_SHELL_PBLOCK_SHIFT;
    shell_info(data, "enabled shell pblock %d\n", data->en_shell_pblock);

    data->en_pr = (data->shell_cnfg->pr_cnfg & EN_PR_MASK) >> EN_PR_SHIFT;
    shell_info(data, "enabled partial (app) reconfiguration %d\n", data->en_pr);

    if(data->en_pr) {
        data->eost = eost;
        data->stat_cnfg->reconfig_eost = eost;
        shell_info(data, "set EOST [clks] %lld\n", data->eost);
    }

    data->en_rdma = (data->shell_cnfg->rdma_cnfg & EN_RDMA_MASK) >> EN_RDMA_SHIFT;
    data->qsfp = (data->shell_cnfg->rdma_cnfg & QSFP_MASK) >> QSFP_SHIFT;
    shell_info(data, "enabled RDMA %d, port %d\n", data->en_rdma, data->qsfp);

    data->en_tcp = (data->shell_cnfg->tcp_cnfg & EN_TCP_MASK) >> EN_TCP_SHIFT;
    shell_info(data, "enabled TCP/IP %d, port %d\n", data->en_tcp, data->qsfp);

    data->en_net = data->en_rdma | data->en_tcp;
    if(data->en_net) {
        long tmp;
        ret_val = kstrtol(ip_addr, 16, &tmp);
        data->net_ip_addr = (uint64_t) tmp;
        ret_val = kstrtol(mac_addr, 16, &tmp);
        data->net_mac_addr = (uint64_t) tmp;
        data->shell_cnfg->net_ip = data->net_ip_addr;
        data->shell_cnfg->net_mac = data->net_mac_addr;
        shell_info(data, "set network ip %08x, mac %012llx\n", data->net_ip_addr, data->net_mac_addr);
    }

    return ret_val;
}

void free_shell_config(struct bus_driver_data *data) {
    kfree(data->stlb_meta);
    kfree(data->ltlb_meta);
    data->stlb_meta = NULL;
    data->ltlb_meta = NULL;
}

////////////////////////////////////////////////
//      CARD MEMORY RESOURCES & SPIN LOCKS    //  
////////////////////////////////////////////////   

int allocate_card_resources(struct bus_driver_data *data) {
    int ret_val = 0;

    // If memory not enabled, skip
    if (!data->en_mem) {
        goto end;
    }

    // Allocate memory to hold metadata for each of the memory blocks
    data->card_lblocks = vzalloc(N_MEM_BLOCKS * sizeof(struct memory_partition));
    if (!data->card_lblocks) {
        shell_err(data, "failed to allocate memory for card_lblocks\n");
        goto err_alloc_lblocks;
    }
    data->card_sblocks = vzalloc(N_MEM_BLOCKS * sizeof(struct memory_partition));
    if (!data->card_sblocks) {
        shell_err(data, "failed to allocate memory for card_sblocks\n");
        goto err_alloc_sblocks;
    }
    
    // The chunk struct (defined in coyote_defs.h) is used to keep track of the next chunk to use for allocation, no. of free chunks etc.
    // Separate allocations for large and small chunks, corresponding to regular and huge pages
    int i;
    for (i = 0; i < N_MEM_BLOCKS; i++) {
        // All chunks are initially free
        data->card_lblocks[i].free_chunks = N_LARGE_CHUNKS;
        data->card_sblocks[i].free_chunks = N_SMALL_CHUNKS;

        // Set-up huge pages region
        data->card_lblocks[i].chunks = vzalloc(N_LARGE_CHUNKS * sizeof(struct chunk));
        if (!data->card_lblocks[i].chunks) {
            shell_err(data, "card memory region for huge pages could not be obtained\n");
            goto err_alloc_lchunks;
        }
        for (int j = 0; j < N_LARGE_CHUNKS; j++) {
            data->card_lblocks[i].chunks[j].id = j;
            data->card_lblocks[i].chunks[j].used = false;
            if (j == N_LARGE_CHUNKS - 1) {
                data->card_lblocks[i].chunks[j].next = &data->card_lblocks[i].chunks[0];
            } else {
                data->card_lblocks[i].chunks[j].next = &data->card_lblocks[i].chunks[j + 1];
            }
        }

        // Set-up regular pages region
        data->card_sblocks[i].chunks = vzalloc(N_SMALL_CHUNKS * sizeof(struct chunk));
        if (!data->card_sblocks[i].chunks) {
            shell_err(data, "card memory region for regular pages could not be obtained\n");
            goto err_alloc_schunks;
        }
        for (int j = 0; j < N_SMALL_CHUNKS; j++) {
            data->card_sblocks[i].chunks[j].id = j;
            data->card_sblocks[i].chunks[j].used = false;
            if (j == N_SMALL_CHUNKS - 1) {
                data->card_sblocks[i].chunks[j].next = &data->card_sblocks[i].chunks[0];
            } else {
                data->card_sblocks[i].chunks[j].next = &data->card_sblocks[i].chunks[j + 1];
            }
        }

        // Point to first chunk for new allocations
        data->card_lblocks[i].alloc = &data->card_lblocks[i].chunks[0];
        data->card_sblocks[i].alloc = &data->card_sblocks[i].chunks[0];
    }

    goto end;

err_alloc_schunks:
    vfree(data->card_lblocks[i].chunks);

err_alloc_lchunks: 
    for (int k = 0; k < i; k++) {
        vfree(data->card_sblocks[k].chunks);
        vfree(data->card_lblocks[k].chunks);
    }
    vfree(data->card_sblocks);

err_alloc_sblocks:
    vfree(data->card_lblocks);

err_alloc_lblocks: 
    ret_val = -ENOMEM;

end: 
    return ret_val;
}

void free_card_resources(struct bus_driver_data *data) {
    // Free the dynamically allocated card memory structs from allocate_card_resources
    if (data->en_mem) {
        for (int i = 0; i < N_MEM_BLOCKS; i++) {
            vfree(data->card_lblocks[i].chunks);
            vfree(data->card_sblocks[i].chunks);
        }

        vfree(data->card_lblocks);
        vfree(data->card_sblocks);
        
        shell_info(data, "card resources deallocated\n");
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
static struct kobj_attribute kobj_attr_hstats = __ATTR_RO(cyt_attr_hstats);
static struct kobj_attribute kobj_attr_prstats = __ATTR_RO(cyt_attr_prstats);
#ifdef PLATFORM_ULTRASCALE_PLUS
static struct kobj_attribute kobj_attr_engines = __ATTR_RO(cyt_attr_engines);
#endif
static struct kobj_attribute kobj_attr_cnfg = __ATTR_RO(cyt_attr_cnfg);
static struct kobj_attribute kobj_attr_eost = __ATTR(cyt_attr_eost, 0664, cyt_attr_eost_show, cyt_attr_eost_store);
#ifdef PLATFORM_VERSAL
static struct kobj_attribute kobj_attr_qdma_debug_regs = __ATTR_RO(cyt_attr_qdma_debug_regs);
#endif

static struct attribute *attrs[] = {
    &kobj_attr_ip.attr,
    &kobj_attr_mac.attr,
    &kobj_attr_nstats.attr,
    &kobj_attr_hstats.attr,
    &kobj_attr_prstats.attr,
    #ifdef PLATFORM_ULTRASCALE_PLUS
    &kobj_attr_engines.attr,
    #endif
    &kobj_attr_cnfg.attr,
    &kobj_attr_eost.attr,
    #ifdef PLATFORM_VERSAL
    &kobj_attr_qdma_debug_regs.attr,
    #endif
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
    
    shell_info(data, "creating sysfs entry...\n");

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
    shell_info(data, "removing sysfs entry...\n");
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
        shell_err(data, "failed to register vFPGA devices\n");
        goto end;
    }
    shell_info(data, "vFPGA device regions allocated, major number %d\n", data->vfpga_major);

    // Create a class for the vFPGA devicse; initialized in the function setup_vfpga_device
    #if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 5, 0)        
        data->vfpga_class = class_create(data->vfpga_dev_name);   
    #else        
        data->vfpga_class = class_create(THIS_MODULE, data->vfpga_dev_name);    
    #endif
    if (IS_ERR(data->vfpga_class)) {
        shell_err(data, "failed to create vFPGA device class\n");
        unregister_chrdev_region(dev, data->n_fpga_reg);
        ret_val = PTR_ERR(data->vfpga_class);
        goto end;
    }
    data->vfpga_class->devnode = fpga_class_devnode;

    // Allocate memory for the vFPGA device structure, which holds its information, locks, wait-queues, maps etc.
    data->vfpga_dev = kmalloc(data->n_fpga_reg * sizeof(struct vfpga_dev), GFP_KERNEL);
    if (!data->vfpga_dev) {
        shell_err(data, "could not allocate memory for vFPGAs\n");
        goto err_fpga_char_mem; // ERR_CHAR_MEM
    }
    memset(data->vfpga_dev, 0, data->n_fpga_reg * sizeof(struct vfpga_dev));
    shell_info(data, "allocated memory for fpga devices\n");

    goto end;

err_fpga_char_mem:
    class_destroy(data->vfpga_class);
    unregister_chrdev_region(dev, data->n_fpga_reg);
    ret_val = -ENOMEM;
end:
    return ret_val;
}

// Releases what setup_vfpga_devices set up for vFPGA i, except the char device; safe on a partially set-up vFPGA
static void release_vfpga_device(struct bus_driver_data *data, int i) {
    struct vfpga_dev *device = &data->vfpga_dev[i];

    // Drain queued page faults and notifications first; they access the registers unmapped below
    if (device->wqueue_notify) {
        destroy_workqueue(device->wqueue_notify);
        device->wqueue_notify = NULL;
    }
    if (device->wqueue_pfault) {
        destroy_workqueue(device->wqueue_pfault);
        device->wqueue_pfault = NULL;
    }

    if (device->fpga_lTlb) {
        iounmap(device->fpga_lTlb);
        device->fpga_lTlb = NULL;
    }
    if (device->fpga_sTlb) {
        iounmap(device->fpga_sTlb);
        device->fpga_sTlb = NULL;
    }
    if (device->cnfg_regs) {
        iounmap(device->cnfg_regs);
        device->cnfg_regs = NULL;
    }

    if (device->wb_addr_virt) {
        set_memory_wb((uint64_t) device->wb_addr_virt, N_WB_PAGES);
        dma_free_coherent(&data->pci_dev->dev, WB_SIZE, device->wb_addr_virt, device->wb_phys_addr);
        device->wb_addr_virt = NULL;
    }

    vfree(device->pid_array);
    vfree(device->ctid_chunks);
    device->pid_array = NULL;
    device->ctid_chunks = NULL;
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
        if (!data->vfpga_dev[i].fpga_lTlb || !data->vfpga_dev[i].fpga_sTlb || !data->vfpga_dev[i].cnfg_regs) {
            shell_err(data, "could not map the registers of vFPGA %d\n", i);
            goto err_vfpga_alloc;
        }

        // Initialize variables for Coyote threads; one for each thread per vFPGA; max is N_CTID_MAX
        // Number of free Coyote threads in this vFPGA; variable incremented every time a Coyote thread is created
        data->vfpga_dev[i].num_free_ctid_chunks = N_CTID_MAX;
        
        // Allocated memory for the Coyote thread chunks; each chunk is a struct with an ID, used flag and a pointer to the next chunk
        data->vfpga_dev[i].ctid_chunks = vzalloc(N_CTID_MAX * sizeof(struct chunk));
        if (!data->vfpga_dev[i].ctid_chunks) {
            shell_err(data, "memory region for pid chunks not obtained\n");
            goto err_vfpga_alloc;
        }

        // Host process ID (pid) associated with the Coyote threads
        data->vfpga_dev[i].pid_array = vzalloc(N_CTID_MAX * sizeof(pid_t));
        if (!data->vfpga_dev[i].pid_array) {
            shell_err(data, "memory region for pid array not obtained\n");
            goto err_vfpga_alloc;
        }

        // Variable housekeeping for Coyote threads; ID starts from 0, increments by 1
        for (int j = 0; j < N_CTID_MAX; j++) {
            data->vfpga_dev[i].ctid_chunks[j].id = j;
            data->vfpga_dev[i].ctid_chunks[j].used = false;
            data->vfpga_dev[i].ctid_chunks[j].next = (j + 1 < N_CTID_MAX) ? &data->vfpga_dev[i].ctid_chunks[j + 1] : NULL;
        }
        data->vfpga_dev[i].pid_alloc = &data->vfpga_dev[i].ctid_chunks[0];

        // Must be initialised before the first notification, whether or not an eventfd is registered
        for (int j = 0; j < N_CTID_MAX; j++) {
            sema_init(&user_notifier_lock[i][j], 1);
            atomic_set(&notification_pending[i][j], 0);
        }

        // Initialize device spinlocks and mutexes
        spin_lock_init(&data->vfpga_dev[i].irq_lock);
        mutex_init(&data->vfpga_dev[i].mmu_lock);
        mutex_init(&data->vfpga_dev[i].offload_lock);
        mutex_init(&data->vfpga_dev[i].sync_lock);
        mutex_init(&data->vfpga_dev[i].pid_lock);

        // Initialize workqueues
        data->vfpga_dev[i].wqueue_pfault = alloc_workqueue(COYOTE_DRIVER_NAME, WQ_UNBOUND | WQ_MEM_RECLAIM, 1);
        if(!data->vfpga_dev[i].wqueue_pfault) {
            shell_err(data, "page fault work queue not initialized\n");
            goto err_vfpga_alloc;
        }

        data->vfpga_dev[i].wqueue_notify = alloc_workqueue(COYOTE_DRIVER_NAME, WQ_UNBOUND | WQ_MEM_RECLAIM, 1);
        if(!data->vfpga_dev[i].wqueue_notify) {
            shell_err(data, "notify work queue not initialized\n");
            goto err_vfpga_alloc;
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
                shell_err(data, "failed to allocate writeback memory\n");
                goto err_vfpga_alloc;
            }
            
            ret_val = set_memory_uc((uint64_t) data->vfpga_dev[i].wb_addr_virt, N_WB_PAGES);
            if (ret_val) {
                shell_err(data, "failed to set UC for writeback memory\n");
                goto err_vfpga_setup;
            }

            for (int j = 0; j < WB_BLOCKS; j++) {
                data->vfpga_dev[i].cnfg_regs->wback[j] = data->vfpga_dev[i].wb_phys_addr + j * (N_CTID_MAX * sizeof(uint32_t));
            }

            vfpga_info(
                &data->vfpga_dev[i], "allocated memory for descriptor writeback, vaddr %llx, paddr %llx\n",
                (uint64_t)data->vfpga_dev[i].wb_addr_virt, data->vfpga_dev[i].wb_phys_addr
            );
        }

        // Register the char device first, then create its node, so the node never exists without a device behind it
        int device_number = MKDEV(data->vfpga_major, i);
        cdev_init(&data->vfpga_dev[i].cdev, &vfpga_ops);
        data->vfpga_dev[i].cdev.owner = THIS_MODULE;
        data->vfpga_dev[i].cdev.ops = &vfpga_ops;

        // Initialize hashmaps; in this case only one which is used for keeping track of memory buffers and TLB mappings
        for (int j = 0; j < N_CTID_MAX; j++) {
            hash_init(user_buff_map[i][j]);
        }

        ret_val = cdev_add(&data->vfpga_dev[i].cdev, device_number, 1);
        if (ret_val) {
            shell_err(data, "could not create a virtual FPGA device %d\n", i);
            goto err_vfpga_setup;
        }

        sprintf(vf_dev_name_tmp, "%s_v%d", data->vfpga_dev_name, i);
        struct device *dev = device_create(data->vfpga_class, NULL, device_number, NULL, vf_dev_name_tmp, i);
        if (IS_ERR(dev)) {
            ret_val = PTR_ERR(dev);
            shell_err(data, "could not create the device node of vFPGA %d\n", i);
            cdev_del(&data->vfpga_dev[i].cdev);
            goto err_vfpga_setup;
        }
        vfpga_info(&data->vfpga_dev[i], "virtual FPGA device created\n");
    }

    shell_info(data, "all virtual FPGA devices added\n");
    return 0;

// Undo vFPGA i (partially set up, its char device not registered) and every vFPGA before it
err_vfpga_alloc:
    ret_val = -ENOMEM;
err_vfpga_setup:
    release_vfpga_device(data, i);
    for (int j = 0; j < i; j++) {
        device_destroy(data->vfpga_class, MKDEV(data->vfpga_major, j));
        cdev_del(&data->vfpga_dev[j].cdev);
        release_vfpga_device(data, j);
    }
    return ret_val;
}

void vfpga_irq_teardown(struct bus_driver_data *data) {
    BUG_ON(!data);

    for (int i = 0; i < data->n_fpga_reg; i++) {
        vfpga_info(&data->vfpga_dev[i], "releasing user IRQ%d\n", data->irq_entry[i].vector);
        free_irq(data->irq_entry[i].vector, &data->vfpga_dev[i]);
    }
}

void teardown_vfpga_devices(struct bus_driver_data *data) {
    for (int i = 0; i < data->n_fpga_reg; i++) {
        device_destroy(data->vfpga_class, MKDEV(data->vfpga_major, i));
        cdev_del(&data->vfpga_dev[i].cdev);
        release_vfpga_device(data, i);
    }

    shell_info(data, "vFPGA devices deleted\n");
}

void free_vfpga_devices(struct bus_driver_data *data) {
    kfree(data->vfpga_dev);
    shell_info(data, "memory for vFPGA device freed\n");

    class_destroy(data->vfpga_class);
    shell_info(data, "vFPGA class deleted\n");
    
    unregister_chrdev_region(MKDEV(data->vfpga_major, 0), data->n_fpga_reg);
    shell_info(data, "unregistered char vFPGA devices\n");
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
        shell_err(data, "failed to register reconfig device\n");
        goto end;
    }
    shell_info(data, "reconfig device regions allocated, major number %d\n", data->reconfig_major);

    // Create a class for the reconfiguration device; initialized in the function setup_reconfig_device
    #if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 5, 0)        
        data->reconfig_class = class_create(data->reconfig_dev_name);    
    #else        
        data->reconfig_class = class_create(THIS_MODULE, data->reconfig_dev_name);  
    #endif   
    if (IS_ERR(data->reconfig_class)) {
        shell_err(data, "failed to create reconfig device class\n");
        unregister_chrdev_region(device, 1);
        ret_val = PTR_ERR(data->reconfig_class);
        goto end;
    }
    data->reconfig_class->devnode = fpga_class_devnode;

    // Allocate memory for the reconfiguration device structure, which holds its information, locks, wait-queues, maps etc.
    data->reconfig_dev = kmalloc(sizeof(struct reconfig_dev), GFP_KERNEL);
    if (!data->reconfig_dev) {
        shell_err(data, "could not allocate memory for reconfig device\n");
        goto err_pr_char_mem; // ERR_CHAR_MEM
    }
    memset(data->reconfig_dev, 0, sizeof(struct reconfig_dev));
    shell_info(data, "allocated memory for reconfig device\n");

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
    shell_info(data, "reconfiguration device created\n");

    cdev_init(&data->reconfig_dev->cdev, &reconfig_ops);
    data->reconfig_dev->cdev.owner = THIS_MODULE;
    data->reconfig_dev->cdev.ops = &reconfig_ops;
    
    // Register the char device with the kernel through cdev_add and the previously allocated unique device number
    ret_val = cdev_add(&data->reconfig_dev->cdev, device_number, 1);
    if (ret_val) {
        shell_err(data, "could not create a reconfiguration device\n");
        goto err_char_reg;
    }
    shell_info(data, "reconfiguration device registered\n");

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
    shell_info(data, "reconfig device deleted\n");
}

void free_reconfig_device(struct bus_driver_data *data) {
    kfree(data->reconfig_dev);
    shell_info(data, "memory for reconfig device freed\n");

    class_destroy(data->reconfig_class);
    shell_info(data, "reconfig class deleted\n");
    
    unregister_chrdev_region(MKDEV(data->reconfig_major, 0), 1);
    shell_info(data, "unregistered char reconfig device\n");
}
