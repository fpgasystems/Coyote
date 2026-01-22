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

#include "vfpga_ops.h"

// Hash map holding the mapping between host process ID (hpid) and Coyote thread IDs (ctid) for each vFPGA device 
struct hlist_head hpid_ctid_map[MAX_N_REGIONS][1 << (PID_HASH_TABLE_ORDER)];

#ifdef HMM_KERNEL
    static struct mmu_interval_notifier_ops cyt_not_ops = {
        .invalidate = cyt_interval_invalidate
    };
#endif 

int vfpga_dev_open(struct inode *inode, struct file *file) {
    // Parse inode arg into vfpga_dev struct and check it's non-null (BUG_ON)
    int minor = iminor(inode);
    struct vfpga_dev *device = container_of(inode->i_cdev, struct vfpga_dev, cdev);
    BUG_ON(!device);
    dbg_info("vFPGA device %d opened, hpid %d, ref_cnt %d\n", minor, current->pid, device->ref_cnt);

    // Set file private data, so the attributes of the opened vfpga_dev can be accessed in other methods
    file->private_data = (void *) device;
    device->ref_cnt++;

    return 0;
}

int vfpga_dev_release(struct inode *inode, struct file *file) {
    int bkt;
    struct hpid_ctid_pages *tmp_h_entry;
    struct list_head *l_p, *l_n;

    // Obtain vFPGA device from file private data (set during open) and check device is not NULL
    struct vfpga_dev *device = container_of(inode->i_cdev, struct vfpga_dev, cdev);
    BUG_ON(!device);

    // Traverse all Coyote threads for this vFPGA device and free their resources
    if(--device->ref_cnt == 0) {
        hash_for_each(hpid_ctid_map[device->id], bkt, tmp_h_entry, entry) {
            list_for_each_safe(l_p, l_n, &tmp_h_entry->ctid_list) {
                // entry
                struct ctid_entry *l_entry = list_entry(l_p, struct ctid_entry, list);

                // Unamp all leftover user pages
                #ifdef HMM_KERNEL
                    if(en_hmm) 
                        free_card_mem(device, l_entry->ctid);
                    else 
                #endif                            
                    tlb_put_user_pages_ctid(device, l_entry->ctid, tmp_h_entry->hpid, 1);

                // Unregister Coyote thread (if registered)
                device->ctid_chunks[l_entry->ctid].next = device->pid_alloc;
                device->pid_alloc = &device->ctid_chunks[l_entry->ctid];

                // Delete entry
                list_del(&l_entry->list); 

                // Remove notifier and entry if all cThreads for this HPID are gone
                if(list_empty(&tmp_h_entry->ctid_list)) {
                    #ifdef HMM_KERNEL                        
                        // remove notifier
                        if(en_hmm) {
                            dbg_info("releasing notifier for hpid %d\n", tmp_h_entry->hpid);
                            mmu_interval_notifier_remove(&tmp_h_entry->mmu_not);
                        }
                    #endif 

                    hash_del(&tmp_h_entry->entry);
                }
            }
        }
    }
    
    int minor = iminor(inode);
    dbg_info("vFPGA device %d released, spid %d, ref cnt %d\n", minor, current->pid, device->ref_cnt);

    return 0;
}

long vfpga_dev_ioctl(struct file *file, unsigned int command, unsigned long arg) {
    int ret_val = 0;
        
    #ifdef HMM_KERNEL    
        struct task_struct *task;
        struct mm_struct *mm;
    #endif

    // Parse device and device attributes
    struct vfpga_dev *device = (struct vfpga_dev *) file->private_data;
    BUG_ON(!device);
    struct bus_driver_data *device_data = device->bd_data;
    BUG_ON(!device_data);

    // Array of arguments passed from/back to user-space; number of arguments depends on IOCTL call
    uint64_t tmp[MAX_USER_ARGS];

    switch (command) {

        // Register a new Coyote thread ID (ctid) with the vFPGA device
        // Each vFPFA can have multiple Coyote threads registered, which are identified by a unique Coyote thread ID (ctid)
        // The maximum number of Coyote threads is defined by N_CTID_MAX, defined in coyote_defs.h
        // Additionally, each Coyote thread is associated with a host process ID (hpid)
        // Args: host process ID (hpid)
        // Return: Coyote thread ID (ctid)
        case IOCTL_REGISTER_CTID:
            ret_val = copy_from_user(&tmp, (unsigned long *)arg, sizeof(unsigned long));
            if (ret_val != 0) {
                pr_warn("user data could not be coppied, return %d\n", ret_val);
            } else {
                mutex_lock(&device->pid_lock);

                pid_t spid = current->pid;
                pid_t hpid = (pid_t) tmp[0];

                // Check if a new Coyote thread can be registered
                if (device->num_free_ctid_chunks == 0) {
                    dbg_info("no free ctid chunks left for hpid %d, spid %d\n", hpid, spid);
                    mutex_unlock(&device->pid_lock);
                    return -ENOMEM;
                }

                int32_t ctid = (int32_t) device->pid_alloc->id;
                device->pid_array[device->pid_alloc->id] = hpid;
                device->pid_alloc = device->pid_alloc->next;
                
                // If the hpid has not been already stored to the map, store it now
                bool hpid_found = false;
                struct hpid_ctid_pages *tmp_h_entry, *new_h_entry;
                struct ctid_entry *l_entry;
                            
                hash_for_each_possible(hpid_ctid_map[device->id], tmp_h_entry, entry, hpid) {
                    if (tmp_h_entry->hpid == hpid) {
                        hpid_found = true;
                    }
                }

                if(!hpid_found) {
                    new_h_entry = kzalloc(sizeof(struct hpid_ctid_pages), GFP_KERNEL);
                    BUG_ON(!new_h_entry);
                    
                    new_h_entry->hpid = hpid;
                    INIT_LIST_HEAD(&new_h_entry->ctid_list);
                    #ifdef HMM_KERNEL
                        if(en_hmm) {
                            task = pid_task(find_vpid(hpid), PIDTYPE_PID);
                            mm = task->mm;
                    
                            ret_val = mmu_interval_notifier_insert(&new_h_entry->mmu_not, mm, 0, ULONG_MAX & PAGE_MASK, &cyt_not_ops);
                            if (ret_val) {
                                dbg_info("mmu notifier registration failed, vFPGA %d\n", device->id);
                                kfree(new_h_entry);
                                return ret_val;
                            } 
                        }
                    #endif
                    hash_add(hpid_ctid_map[device->id], &new_h_entry->entry, hpid);
                }

                // Add ctid to the tail of the ctid list for this hpid
                hash_for_each_possible(hpid_ctid_map[device->id], tmp_h_entry, entry, hpid) {
                    if (tmp_h_entry->hpid == hpid) {
                        l_entry = kmalloc(sizeof(struct ctid_entry), GFP_KERNEL);
                        BUG_ON(!l_entry);
                        l_entry->ctid = ctid;
                        list_add_tail(&l_entry->list, &tmp_h_entry->ctid_list);
                    }
                }

                #ifdef HMM_KERNEL
                    INIT_LIST_HEAD(&migrated_pages[device->id][ctid]);
                #endif            

                dbg_info("registration succeeded, ctid %d, hpid %d, spid %d\n", ctid, hpid, spid);

                // Return ctid and unlock
                tmp[1] = (int64_t) ctid;
                ret_val = copy_to_user((unsigned long *)arg, &tmp, 2 * sizeof(unsigned long));
                mutex_unlock(&device->pid_lock);
            }
            break;
        
        // Unregister a previously registered Coyote thread ID (ctid) from the vFPGA device
        // In essence, performing the opposite of the IOCTL_REGISTER_CTID call
        // Args: Coyote thread ID (ctid)
        case IOCTL_UNREGISTER_CTID:
            ret_val = copy_from_user(&tmp, (unsigned long *) arg, sizeof(unsigned long));
            if (ret_val != 0) {
                pr_warn("user data could not be coppied, return %d\n", ret_val);
            } else {
                mutex_lock(&device->pid_lock);
                
                int32_t ctid = (int32_t) tmp[0];
                pid_t hpid = device->pid_array[ctid];
                pid_t spid = current->pid;
            
                struct hpid_ctid_pages *tmp_h_entry;
                struct list_head *l_p, *l_n;
                struct ctid_entry *l_entry;

                // Traverse all Coyote thread IDs until a match is found
                hash_for_each_possible(hpid_ctid_map[device->id], tmp_h_entry, entry, hpid) {
                    if(tmp_h_entry->hpid == hpid) {
                        list_for_each_safe(l_p, l_n, &tmp_h_entry->ctid_list) {
                            l_entry = list_entry(l_p, struct ctid_entry, list);

                            if(l_entry->ctid == ctid) {
                                // Unmap any leftover user pages for this Coyot thread
                                #ifdef HMM_KERNEL
                                    if(en_hmm)
                                        free_card_mem(device, ctid);
                                    else 
                                #endif                            
                                    tlb_put_user_pages_ctid(device, ctid, hpid, 1);

                                // Unregister Coyote thread and delete entry from list
                                device->ctid_chunks[l_entry->ctid].next = device->pid_alloc;
                                device->pid_alloc = &device->ctid_chunks[l_entry->ctid];
                                list_del(&l_entry->list);   
                            }
                        }

                        // If there are no more Coyote threads registered for this host process ID (hpid), remove the hpid entry
                        if(list_empty(&tmp_h_entry->ctid_list)) {
                            #ifdef HMM_KERNEL                        
                                if(en_hmm) {
                                    dbg_info("releasing notifier for hpid %d\n", hpid);
                                    mmu_interval_notifier_remove(&tmp_h_entry->mmu_not);
                                }
                            #endif 
                            hash_del(&tmp_h_entry->entry);
                        }
                    }
                }

                dbg_info("unregistration succeeded, ctid %d, hpid %d, spid %d\n", ctid, hpid, spid);
                mutex_unlock(&device->pid_lock);
                
            }
            break;

        // Registers a new event file descriptor (efd) for a Coyote thread ID (ctid) with the vFPGA device, 
        // This file descriptor is used for sending user interrupts to the user space (see vfpga_uisr.c)
        // Args: Coyote thread ID (ctid), Event file descriptor (efd)
        case IOCTL_REGISTER_EVENTFD:
            ret_val = copy_from_user(&tmp, (unsigned long *) arg, 2 * sizeof(uint64_t));
            if (ret_val) {
                pr_warn("user data could not be coppied, ret_val: %d\n", ret_val);
            } else {
                ret_val = vfpga_register_eventfd(device, (int32_t) tmp[0], tmp[1]);
                if (ret_val) {
                    dbg_info("eventfd could not be registered, ret_val: %d\n", ret_val);
                }
            }
            break;

        // Unregisters a previously registered event file descriptor (efd) for a Coyote thread ID (ctid)
        // Args: Coyote thread ID (ctid)
        case IOCTL_UNREGISTER_EVENTFD:
            ret_val = copy_from_user(&tmp, (unsigned long *) arg, sizeof(uint64_t));
            if (ret_val) {
                pr_warn("user data could not be coppied, ret_val: %d\n", ret_val);
            } else {
                vfpga_unregister_eventfd(device, (int32_t) tmp[0]);
            }
            break;
        
        // Explicit mapping of user pages; will map the user pages into the vFPGA's TLB and set-up corresponding card buffers, if enabled
        // Args: Virtual address, length, Coyote thread ID (ctid)
        case IOCTL_MAP_USER_MEM:
            ret_val = copy_from_user(&tmp, (unsigned long *) arg, 3 * sizeof(unsigned long));
            if (ret_val != 0) {
                pr_warn("user data could not be coppied, return %d\n", ret_val);
            } else {
                int32_t ctid = (int32_t)tmp[2];
                pid_t hpid = device->pid_array[ctid];

                mutex_lock(&device->mmu_lock);
                change_tlb_lock(device);

                #ifdef HMM_KERNEL
                    if(en_hmm) 
                        ret_val = mmu_handler_hmm(device, tmp[0], tmp[1], ctid, true, hpid);
                    else
                #endif            
                    ret_val = mmu_handler_gup(device, tmp[0], tmp[1], ctid, true, hpid);
                
                if (ret_val && ret_val != BUFF_NEEDS_EXP_SYNC_RET_CODE) {
                    dbg_info("buffer could not be mapped, ret_val: %d\n", ret_val);
                }

                change_tlb_lock(device);
                mutex_unlock(&device->mmu_lock);

                dbg_info("user mapping vFPGA %d handled\n", device->id);
            }
            break;

        // Explictily unmap (release) user pages 
        // Args: Virtual address, Coyote thread ID (ctid)
        case IOCTL_UNMAP_USER_MEM:
            ret_val = copy_from_user(&tmp, (unsigned long *) arg, 2 * sizeof(unsigned long));
            if (ret_val != 0) {
                pr_warn("user data could not be coppied, return %d\n", ret_val);
            } else {
                if(!en_hmm) {
                    int32_t ctid = (int32_t) tmp[1];
                    pid_t hpid = device->pid_array[ctid];

                    mutex_lock(&device->mmu_lock);
                    change_tlb_lock(device);
                    tlb_put_user_pages(device, tmp[0], ctid, hpid, 1);
                    change_tlb_lock(device);
                    mutex_unlock(&device->mmu_lock);

                    dbg_info("user unmapping vFPGA %d handled\n", device->id);
                }
            }
            break;

        // Map (attach) DMA Buffer
        // Args: DMA Buffer file descriptor (fd), virtual address, Coyote thread ID (ctid)
        case IOCTL_MAP_DMABUF:
            #if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 2, 0)
                ret_val = copy_from_user(&tmp, (unsigned long *) arg, 3 * sizeof(unsigned long));
                if (ret_val != 0) {
                    pr_warn("user data could not be coppied, return %d\n", ret_val);
                } else {
                    int32_t ctid = (int32_t) tmp[2];

                    dbg_info("mapping dmabuff for vFPGA %d, fd %d, virtual address %llx, ctid %d\n", device->id, (int) tmp[0], tmp[1], ctid);

                    mutex_lock(&device->mmu_lock);
                    change_tlb_lock(device);                    
                    
                    ret_val = p2p_attach_dma_buf(device, tmp[0], tmp[1], ctid);
                    if(ret_val) {
                        dbg_info("buffer could not be mapped, ret_val: %d\n", ret_val);
                    }

                    change_tlb_lock(device);
                    mutex_unlock(&device->mmu_lock);
                }
            #else
                pr_warn("Failed to map DMABUF! DMA Bufs for Coyote GPU integration is only available on Linux >= 6.2.0. If you're seeing this message and your driver compiled: this is likely a bug; please report it to the Coyote team\n");
                ret_val = -1;
            #endif  
            break;

        // Unmap (detach) DMA Buffer
        // Args: DMA Buffer file descriptor (fd), Coyote thread ID (ctid)
        case IOCTL_UNMAP_DMABUF:
            #if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 2, 0)
                ret_val = copy_from_user(&tmp, (unsigned long *) arg, 2 * sizeof(unsigned long));
                if (ret_val != 0) {
                    pr_warn("user data could not be coppied, return %d\n", ret_val);
                } else {
                    if(!en_hmm) {
                        int32_t ctid = (int32_t) tmp[1];

                        dbg_info("unmapping dmabuff for vFPGA %d, ctid %d\n", device->id, ctid);
                        
                        mutex_lock(&device->mmu_lock);
                        change_tlb_lock(device);
                        p2p_detach_dma_buf(device, tmp[0], ctid, 1);
                        change_tlb_lock(device);
                        mutex_unlock(&device->mmu_lock);
                    }
                }
            #else
                pr_warn("Failed to unmap DMABUF! DMA Bufs for Coyote GPU integration is only available on Linux >= 6.2.0. If you're seeing this message and your driver compiled: this is likely a bug; please report it to the Coyote team\n");
                ret_val = -1;
            #endif  
            break;
        
        // Off-load user buffer to card memory
        // Args: virtual address, buffer length, Coyote thread ID (ctid)
        case IOCTL_OFFLOAD_REQ:
            if (!device_data->en_mem) {
                pr_warn("cannot off-load buffer when shell is built without memory\n");
                return -1;
            }

            ret_val = copy_from_user(&tmp, (unsigned long *) arg, 3 * sizeof(unsigned long));
            if (ret_val != 0) {
                pr_warn("user data could not be coppied, return %d\n", ret_val);
            } else {
                if(!en_hmm) {
                    ret_val = offload_user_pages(device, tmp[0], (uint32_t) tmp[1], (int32_t) tmp[2]);
                    if(ret_val) {
                        dbg_info("buffer could not be offloaded, ret_val: %d\n", ret_val);
                    }
                }
            }
            break;

        // Sync user buffer from card memory
        // Args: virtual address, buffer length, Coyote thread ID (ctid)
        case IOCTL_SYNC_REQ:
            if (!device_data->en_mem) {
                pr_warn("cannot sync buffer when shell is built without memory\n");
                return -1;
            }

            ret_val = copy_from_user(&tmp, (unsigned long *) arg, 3 * sizeof(unsigned long));
            if (ret_val != 0) {
                pr_warn("user data could not be coppied, return %d\n", ret_val);
            } else {
                if(!en_hmm) {
                    ret_val = sync_user_pages(device, tmp[0], (uint32_t) tmp[1], (int32_t) tmp[2]);
                    if (ret_val) {
                        dbg_info("buffer could not be synced, ret_val: %d\n", ret_val);
                    }
                }
            }
            break;

        // Set FPGA IP address
        // Args: IP address
        case IOCTL_SET_IP_ADDRESS:
            if (device_data->en_net) {
                ret_val = copy_from_user(&tmp, (unsigned long*) arg, sizeof(unsigned long));
                if (ret_val != 0) {
                    pr_warn("user data could not be coppied, return %d\n", ret_val);
                } else {
                    spin_lock(&device_data->stat_lock);
                    device_data->shell_cnfg->net_ip = tmp[0];
                    device_data->net_ip_addr = tmp[0];
                    dbg_info("IP address changed to %08llx\n", tmp[0]);
                    spin_unlock(&device_data->stat_lock);
                }
            } else {
                pr_warn("network not enabled; cannot set FPGA IP address\n");
                return -1;
            }
            break;

        // Set FPGA MAC address
        // Args: MAC address
        case IOCTL_SET_MAC_ADDRESS:
            if (device_data->en_net) {
                ret_val = copy_from_user(&tmp, (unsigned long*) arg, sizeof(unsigned long));
                if (ret_val != 0) {
                    pr_warn("user data could not be coppied, return %d\n", ret_val);
                } else {
                    spin_lock(&device_data->stat_lock);
                    device_data->shell_cnfg->net_mac = tmp[0];
                    device_data->net_mac_addr = tmp[0];
                    dbg_info("MAC address changed to %llx\n", tmp[0]);
                    spin_unlock(&device_data->stat_lock);
                }
            } else {
                pr_warn("network not enabled; cannot set FPGA MAC address\n");
                return -1;
            }
            break;
        
        // Get FPGA IP address
        // Return: IP address
        case IOCTL_GET_IP_ADDRESS:
            tmp[0] = device_data->net_ip_addr;
            dbg_info("FPGA IP address %llx\n", tmp[0]);
            ret_val = copy_to_user((unsigned long *) arg, &tmp, sizeof(unsigned long));
            if (ret_val != 0) {
                pr_warn("could not copy data to user space, return %d\n", ret_val);
            }
            break;

        // Get FPGA MAC address
        // Return: MAC address
        case IOCTL_GET_MAC_ADDRESS:
            tmp[0] = device_data->net_mac_addr;
            dbg_info("FPGA MAC address %llx\n", tmp[0]);
            ret_val = copy_to_user((unsigned long *) arg, &tmp, sizeof(unsigned long));
            if (ret_val != 0) {
                pr_warn("could not copy data to user space, return %d\n", ret_val);
            }
            break;
        
        // Read shell config
        // Return: Various (compile-time) shell parameters (EN_RDMA, EN_MEM, etc.)
        case IOCTL_READ_SHELL_CONFIG:
            tmp[0] = ((uint64_t)device_data->n_fpga_chan << 32) | ((uint64_t)device_data->n_fpga_reg << 48) |
                     ((uint64_t)device_data->en_avx) | ((uint64_t)device_data->en_wb << 1) |
                     ((uint64_t)device_data->en_strm << 2) | ((uint64_t)device_data->en_mem << 3) | ((uint64_t)device_data->en_pr << 4) | 
                     ((uint64_t)device_data->en_rdma << 16) | ((uint64_t)device_data->en_tcp << 17);

            tmp[1] = ((uint64_t)device_data->shell_cnfg->ctrl_cnfg);
            dbg_info("reading shell config 0x%llx\n", tmp[0]);
            ret_val = copy_to_user((unsigned long *) arg, &tmp, 2 * sizeof(unsigned long));
            if (ret_val != 0) {
                pr_warn("could not copy data to user space, return %d\n", ret_val);
            }
            break;

        // Read XDMA stats
        // Return: Various XDMA status registers
        case IOCTL_SHELL_XDMA_STATS:
            dbg_info("retrieving XDMA stats\n");
            for (int i = 0; i < device_data->n_fpga_chan * N_XDMA_STAT_CH_REGS; i++) {
                tmp[i] = device_data->shell_cnfg->xdma_debug[i];
            }
            ret_val = copy_to_user((unsigned long *) arg, &tmp, device_data->n_fpga_chan * N_XDMA_STAT_CH_REGS * sizeof(unsigned long));
            if (ret_val != 0) {
                pr_warn("could not copy data to user space, return %d\n", ret_val);
            }
            break;

        // Retrieve network stats
        // Return: Various network stats
        case IOCTL_SHELL_NET_STATS:
            if (device_data->en_net) {
                dbg_info("retrieving network stats\n");
                for (int i = 0; i < N_NET_STAT_REGS; i++) {
                    tmp[i] = device_data->shell_cnfg->net_debug[i];
                }
                ret_val = copy_to_user((unsigned long *) arg, &tmp, N_NET_STAT_REGS * sizeof(unsigned long));
                if (ret_val != 0) {
                    pr_warn("could not copy data to user space, return %d\n", ret_val);
                }
            } else {
                pr_warn("network not enabled; cannot retrieve network stats\n");
                return -1;
            }
            break;
        
        // Marks that user a interrupt (notification) has been processed in the user space; for more details see vfpga_isr.c and vfpga_uisr.h
        // Args: Coyote thread ID (ctid)
        case IOCTL_SET_NOTIFICATION_PROCESSED:
            ret_val = copy_from_user(&tmp, (unsigned long *) arg, sizeof(unsigned long));
            if (ret_val != 0) {
                pr_warn("user data could not be copied, return %d\n", ret_val);
            } else {
                int32_t ctid = (int32_t) tmp[0];
                dbg_info("marking notification with vfpga ID %d, ctid %d as processed\n", device->id, ctid);
                mutex_unlock(&user_notifier_lock[device->id][ctid]);
            }
            break;
        
        // Returns the interrupt value to the user-space process. This happens as a reaction to a evenfd write.
        // See vfpga_isr.c for details.
        case IOCTL_GET_NOTIFICATION_VALUE:
            // This ioctl does a read & write.
            // 1. retrieve the ctid from the user-space process.
            ret_val = copy_from_user(&tmp, (unsigned long *) arg, sizeof(unsigned long));
            if (ret_val != 0) {
                pr_warn("user data could not be copied, return %d\n", ret_val);
            } else {
                // 2. send the interrupt value for this ctid!
                int32_t ctid = (int32_t) tmp[0];
                dbg_info("retrieving interrupt value for vfpga ID %d, ctid %d\n", device->id, ctid);
                tmp[0] = interrupt_value[device->id][ctid];
                ret_val = copy_to_user((unsigned long *) arg, &tmp, sizeof(uint32_t));
                if (ret_val != 0) {
                    pr_warn("could not copy data to user space, return %d\n", ret_val);
                }
            }
            break;

        default:
            dbg_info("vFPGA device %d received unknown IOCTL call %d\n", device->id, command);
            ret_val = 1;
            break;
    }

    return ret_val;
}

int vfpga_dev_mmap(struct file *file, struct vm_area_struct *vma) {
    // Obtain vFPGA device from file private data (set during open) and check device is not NULL
    struct vfpga_dev *device = (struct vfpga_dev *) file->private_data;
    BUG_ON(!device);

    vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);

    // Memory map user registers (CSR) in vFPGAs; the ones parsed from axi_ctrl interface in the vFPGA
    if (vma->vm_pgoff == MMAP_CTRL) {
        dbg_info(
            "fpga dev. %d, memory mapping user ctrl region at %llx of size %x\n",
            device->id, device->vfpga_cnfg_phys_addr + VFPGA_CTRL_USER_OFFS, VFPGA_CTRL_USER_SIZE
        );
        int ret_val = remap_pfn_range(
            vma, 
            vma->vm_start, 
            (device->vfpga_cnfg_phys_addr + VFPGA_CTRL_USER_OFFS) >> PAGE_SHIFT,
            VFPGA_CTRL_USER_SIZE, 
            vma->vm_page_prot
        );
        if (ret_val) {
            pr_warn("remap_pfn_range failed for user ctrl region, ret_val: %d\n", ret_val);
            return -EIO;
        } else {
            return 0;
        }
    }

    // Memory map vFPGA config (non-AVX) region (cnfg_slave)
    if (vma->vm_pgoff == MMAP_CNFG) {
        dbg_info(
            "fpga dev. %d, memory mapping config region at %llx of size %x\n",
            device->id, device->vfpga_cnfg_phys_addr + VFPGA_CTRL_CNFG_OFFS, VFPGA_CTRL_CNFG_SIZE
        );
        int ret_val = remap_pfn_range(
            vma, 
            vma->vm_start, 
            (device->vfpga_cnfg_phys_addr + VFPGA_CTRL_CNFG_OFFS) >> PAGE_SHIFT,
            VFPGA_CTRL_CNFG_SIZE, 
            vma->vm_page_prot
        );
        if (ret_val) {
            pr_warn("remap_pfn_range failed for shell config region, ret_val: %d\n", ret_val);
            return -EIO;
        } else {
            return 0;
        }
    }

    // Memory map shell config (AVX) region (cnfg_slave_avx)
    if (vma->vm_pgoff == MMAP_CNFG_AVX) {
        dbg_info(
            "fpga dev. %d, memory mapping config AVX region at %llx of size %x\n",
            device->id, device->vfpga_cnfg_avx_phys_addr, VFPGA_CTRL_CNFG_AVX_SIZE
        );
        int ret_val = remap_pfn_range(
            vma, 
            vma->vm_start, 
            device->vfpga_cnfg_avx_phys_addr >> PAGE_SHIFT,
            VFPGA_CTRL_CNFG_AVX_SIZE, 
            vma->vm_page_prot
        );
        if (ret_val) {
            pr_warn("remap_pfn_range failed for shell config AVX region, ret_val: %d\n", ret_val);
            return -EIO;
        } else {
            return 0;
        }
    }

    // Memory map writeback region
    if (vma->vm_pgoff == MMAP_WB) {
        dbg_info(
            "fpga dev. %d, memory mapping writeback regions at %llx of size %lx\n",
            device->id, device->wb_phys_addr, WB_SIZE
        );
        
        // dma_mmap_coherent expects vma->pg_offs to be 0; hence MMAP_WB was changed to 0 and MMAP_CTRL to 3
        int ret_val = dma_mmap_coherent(
            &device->bd_data->pci_dev->dev, vma, (void *) device->wb_addr_virt, device->wb_phys_addr, WB_SIZE 
        );

        if (ret_val) {
            pr_warn("dma_mmap_coherent failed for writeback region, ret_val: %d\n", ret_val);
            return -EIO;
        } else {
            return 0;
        }
    }

    pr_warn("requested unknown memory mapping for vFPGA device\n");
    return -EINVAL;
}