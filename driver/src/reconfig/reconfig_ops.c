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

#include "reconfig_ops.h"

int reconfig_dev_open(struct inode *inode, struct file *file) {
    // Parse inode arg into reconfig_dev struct and check it's non-null (BUG_ON)
    int minor = iminor(inode);
    struct reconfig_dev *device = container_of(inode->i_cdev, struct reconfig_dev, cdev);
    BUG_ON(!device);
    dbg_info("reconfiguration device %d acquired, pid %d\n", minor, current->pid);

    // Set file private data, so the attributes of the opened reconfig_dev can be accessed in other methods
    file->private_data = (void *) device;

    return 0;
}

int reconfig_dev_release(struct inode *inode, struct file *file) {
    // The release method for reconfig_dev is largely obsolete
    // Since `open` did not allocate any dynamic memory or interact with hardware
    // Therefore, we simply check that the device is non-null with BUG_ON
    int minor = iminor(inode);
    struct reconfig_dev *device = container_of(inode->i_cdev, struct reconfig_dev, cdev);
    BUG_ON(!device);

    dbg_info("reconfiguration device %d released, pid %d\n", minor, current->pid);
    return 0;
}

long reconfig_dev_ioctl(struct file *file, unsigned int command, unsigned long arg) {
    int ret_val = 0;

    // Parse device attributes and PCIe driver data
    struct reconfig_dev *device = (struct reconfig_dev *) file->private_data;
    BUG_ON(!device);
    struct bus_drvdata *bus_data = device->pd;
    BUG_ON(!bus_data);

    // Array of arguments passed from user-space; number of arguments depends on IOCTL call
    unsigned long tmp[MAX_USER_ARGS];

    switch (command) {
        // Host-side memory allocation to hold bitstreams
        // Args: n_pages, host PID, configuration ID (crid)
        case IOCTL_ALLOC_HOST_RECONFIG_MEM:
            ret_val = copy_from_user(&tmp, (unsigned long *) arg, 3 * sizeof(unsigned long));
            if (ret_val != 0) {
                pr_warn("user data could not be coppied, return %d\n", ret_val);
            } else {
                ret_val = alloc_reconfig_buffer(device, tmp[0], tmp[1], tmp[2]);
                dbg_info("allocated reconfig buffers, n_pages %d\n", device->curr_buff.n_pages);
                if (ret_val != 0) {
                    pr_warn("reconfig buffers could not be allocated, return %d\n", ret_val);
                }
            }
            break;

        // Release host-side memory for bitstream
        // Args: virtual address, host PID, configuration ID (crid)
        case IOCTL_FREE_HOST_RECONFIG_MEM:
            ret_val = copy_from_user(&tmp, (unsigned long *) arg, 3 * sizeof(unsigned long));
            if (ret_val != 0) {
                pr_warn("user data could not be coppied, return %d\n", ret_val);
            }
            else {
                // NOTE: free_reconfig_buffer always returns zero; hence no error handling
                ret_val = free_reconfig_buffer(device, tmp[0], tmp[1], tmp[2]);
                dbg_info("reconfig buffer freed, virtual address 0x%lx\n", tmp[0]);
            }
            break;

        // Reconfigure shell
        // Args: bitstream virtual address, buffer length, host PID, configuration ID (crid)
        case IOCTL_RECONFIGURE_SHELL:
            ret_val = copy_from_user(&tmp, (unsigned long *)arg, 4 * sizeof(unsigned long));
            if (ret_val != 0) {
                pr_warn("user data could not be coppied, return %d\n", ret_val);
            } else {
                dbg_info("starting shell reconfiguration, pid %d\n", current->pid);
                
                // Lock mutex, to avoid multiple reconfigurations at the same time
                mutex_lock(&device->rcnfg_lock);

                // Clean up current shell state
                shell_pci_remove(bus_data);
                
                // Decouple
                bus_data->fpga_stat_cnfg->reconfig_dcpl_set = 0x1;

                // Reconfigure and wait until completion
                uint64_t start_time = ktime_get_ns();
                ret_val = reconfigure_start(device, tmp[0], tmp[1], tmp[2], tmp[3]);
                if (ret_val != 0) {
                    pr_warn("shell reconfiguration not successful, return %d\n", ret_val);
                    return -1;
                }

                wait_event_interruptible(device->waitqueue_rcnfg, atomic_read(&device->wait_rcnfg) == FLAG_SET);
                uint64_t stop_time = ktime_get_ns();
                dbg_info("shell reconfiguration time %llu ms\n", (stop_time - start_time) / (1000 * 1000));
                atomic_set(&device->wait_rcnfg, FLAG_CLR);

                // Reset end-of-start up time (active-low)
                bus_data->fpga_stat_cnfg->reconfig_eost_reset = 0x0;
                bus_data->fpga_stat_cnfg->reconfig_eost_reset = 0x1;

                // Couple and re-init the shell, unlock mutex
                dbg_info("shell reconfiguration complete, coupling the design and unlocking mutex\n");
                bus_data->fpga_stat_cnfg->reconfig_dcpl_clr = 0x1;
                shell_pci_init(bus_data);
                mutex_unlock(&device->rcnfg_lock);
            }
            break;
        
        // Reconfigure app
        // Args: virtual address, buffer length, host PID, configuration ID (crid), vFPGA ID
        case IOCTL_RECONFIGURE_APP:
            ret_val = copy_from_user(&tmp, (unsigned long *) arg, 5 * sizeof(unsigned long));
            if (ret_val != 0) {
                pr_warn("user data could not be coppied, return %d\n", ret_val);
            } else {
                dbg_info("trying to obtain reconfig lock, pid %d\n", current->pid);
                
                // Lock mutex, to avoid multiple reconfigurations at the same time
                mutex_lock(&device->rcnfg_lock);

                // Decouple
                bus_data->fpga_shell_cnfg->reconfig_dcpl_app_set = (1 << (uint32_t) tmp[4]);

                // Reconfigure and wait until completion
                uint64_t start_time = ktime_get_ns();
                ret_val = reconfigure_start(device, tmp[0], tmp[1], tmp[2], tmp[3]);
                if (ret_val != 0) {
                    pr_warn("app reconfiguration not successful, return %d\n", ret_val);
                    return -1;
                }

                wait_event_interruptible(device->waitqueue_rcnfg, atomic_read(&device->wait_rcnfg) == FLAG_SET);
                uint64_t stop_time = ktime_get_ns();
                dbg_info("app reconfiguration time %llu ms\n", (stop_time - start_time) / (1000 * 1000));
                atomic_set(&device->wait_rcnfg, FLAG_CLR);

                // Couple and unlock mutex
                dbg_info("app reconfiguration complete, coupling the design and unlocking mutex\n");
                bus_data->fpga_shell_cnfg->reconfig_dcpl_app_clr = (1 << (uint32_t)tmp[3]);
                mutex_unlock(&device->rcnfg_lock);
            }
            break;

        // Read PR config
        // Return: partial reconfiguration (EN_PR) enabled or not
        case IOCTL_PR_CNFG:
            tmp[0] = (uint64_t) bus_data->en_pr;
            dbg_info("reading PR config 0x%lx\n", tmp[0]);
            ret_val = copy_to_user((unsigned long *) arg, &tmp, sizeof(unsigned long));
            break;

        // Read XDMA stats
        // Return: Various XDMA status registers
        case IOCTL_STATIC_XDMA_STATS:
            dbg_info("retrieving XDMA status");
            for(int i = 0; i < N_XDMA_STAT_CH_REGS; i++) {
                tmp[i] = bus_data->fpga_stat_cnfg->xdma_debug[i];
            }
            ret_val = copy_to_user((unsigned long *)arg, &tmp, N_XDMA_STAT_CH_REGS * sizeof(unsigned long));
            break;

        default: 
            break;
    }

    return ret_val;
}

int reconfig_dev_mmap(struct file *file, struct vm_area_struct *vma) {
    // Parse device attributes
    struct reconfig_dev *device = (struct reconfig_dev *) file->private_data;
    BUG_ON(!device);
    uint64_t page_size = device->pd->ltlb_order->page_size;
    uint64_t page_shift = device->pd->ltlb_order->page_shift;

    // Map previously allocated reconfiguration buffers to user-space
    // Buffers must have been allocated using IOCTL_ALLOC_HOST_RECONFIG_MEM
    vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);
    if (vma->vm_pgoff == MMAP_PR) {
        dbg_info("reconfig device, starting mmap\n");

        // Align virtual address (vma->vm_start) to page boundary
        uint64_t virtual_address = ((vma->vm_start + page_size - 1) >> page_shift) << page_shift;

        // Check pages have been allocated and the current process was the one that allocated them 
        if (device->curr_buff.n_pages != 0 && device->curr_buff.pid == current->pid) {
            spin_lock(&device->mem_lock);

            // Store metadata about the recently allocated buffer to the map (reconfig_buffs_map)
            struct reconfig_buff_metadata *new_buff = kzalloc(sizeof(struct reconfig_buff_metadata), GFP_KERNEL);
            BUG_ON(!new_buff);
            new_buff->vaddr = virtual_address;
            new_buff->pid = current->pid;
            new_buff->crid = device->curr_buff.crid;
            new_buff->n_pages = device->curr_buff.n_pages;
            new_buff->pages = device->curr_buff.pages;
            hash_add(reconfig_buffs_map, &new_buff->entry, virtual_address);
            
            // Remap each page to user-space
            uint64_t virtual_address_tmp = virtual_address;
            for (int i = 0; i < new_buff->n_pages; i++) {
                if (remap_pfn_range(
                        vma, virtual_address_tmp, 
                        page_to_pfn(device->curr_buff.pages[i]), page_size, vma->vm_page_prot)
                    ) {
                        pr_warn("failed to remap, virtual address 0x%llx\n", virtual_address_tmp);
                        return -EIO;
                    }
                virtual_address_tmp += page_size;
            }

            // Mark current buff as empty, to allo future mmaps (see first if in this function)
            device->curr_buff.n_pages = 0;

            spin_unlock(&device->mem_lock);
            dbg_info("reconfig device, completed mmap\n");
            return 0;
        }
    }

    return -EINVAL;
}
