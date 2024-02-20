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

#include "fpga_fops.h"

/*
███████╗ ██████╗ ██████╗ ███████╗
██╔════╝██╔═══██╗██╔══██╗██╔════╝
█████╗  ██║   ██║██████╔╝███████╗
██╔══╝  ██║   ██║██╔═══╝ ╚════██║
██║     ╚██████╔╝██║     ███████║
╚═╝      ╚═════╝ ╚═╝     ╚══════╝
*/     


/* Hash tables */
struct hlist_head spid_cnt_map[MAX_N_REGIONS][1 << (PID_HASH_TABLE_ORDER)];
struct hlist_head spid_hpid_map[MAX_N_REGIONS][1 << (PID_HASH_TABLE_ORDER)];
struct hlist_head hpid_cpid_map[MAX_N_REGIONS][1 << (PID_HASH_TABLE_ORDER)];

#ifdef HMM_KERNEL

static struct mmu_interval_notifier_ops cyt_not_ops = {
    .invalidate = cyt_interval_invalidate};

#endif 


 /**
 * @brief Acquire a region
 * 
 */
int fpga_open(struct inode *inode, struct file *file)
{
    struct spid_cnt *tmp_c_entry, *new_c_entry;
    uint32_t curr_ref_cnt;
    bool k = false;
    int minor = iminor(inode);

    struct fpga_dev *d = container_of(inode->i_cdev, struct fpga_dev, cdev);
    BUG_ON(!d);

    // ref count
    hash_for_each_possible(spid_cnt_map[d->id], tmp_c_entry, entry, current->pid) {
        if(tmp_c_entry->spid == current->pid) {
            k = true;
            curr_ref_cnt = ++tmp_c_entry->ref_cnt;
        }
    }

    if(!k) {
        new_c_entry = kzalloc(sizeof(struct spid_cnt), GFP_KERNEL);
        BUG_ON(!new_c_entry);
        new_c_entry->ref_cnt = 1;
        curr_ref_cnt = 1;
        new_c_entry->spid = current->pid;
        hash_add(spid_cnt_map[d->id], &new_c_entry->entry, current->pid);
    }

    pr_info("fpga device %d opened, spid %d, ref %d\n", minor, current->pid, curr_ref_cnt);

    // set private data
    file->private_data = (void *)d;

    return 0;
}

/**
 * @brief Release a region
 * 
 */
int fpga_release(struct inode *inode, struct file *file)
{
    int bkt;
    struct spid_cnt *tmp_c_entry;
    struct spid_hpid_pages *tmp_s_entry;
    struct hpid_cpid_pages *tmp_h_entry;
    struct list_head *l_p, *l_n;
    struct cpid_entry *l_entry;
    int minor = iminor(inode);

    struct fpga_dev *d = container_of(inode->i_cdev, struct fpga_dev, cdev);
    BUG_ON(!d);

    // ref count
    hash_for_each_possible(spid_cnt_map[d->id], tmp_c_entry, entry, current->pid) {
        if(tmp_c_entry->spid == current->pid) {

            tmp_c_entry->ref_cnt--;

            if(tmp_c_entry->ref_cnt == 0) {

                // clear
                hash_for_each(hpid_cpid_map[d->id], bkt, tmp_h_entry, entry) {

                    // traverse all cpid
                    list_for_each_safe(l_p, l_n, &tmp_h_entry->cpid_list) {
                        // entry
                        l_entry = list_entry(l_p, struct cpid_entry, list);

                #ifdef HMM_KERNEL
                        // unamp all leftover user pages
                        if(en_hmm)
                            free_card_mem(d, l_entry->cpid);
                        else 
                #endif                            
                            tlb_put_user_pages_cpid(d, l_entry->cpid, tmp_h_entry->hpid, 1);

                        // unregister (if registered)
                        d->pid_chunks[l_entry->cpid].next = d->pid_alloc;
                        d->pid_alloc = &d->pid_chunks[l_entry->cpid];

                        // delete entry
                        list_del(&l_entry->list); 

                        // remove if all cpid are gone
                        if(list_empty(&tmp_h_entry->cpid_list)) {
                #ifdef HMM_KERNEL                        
                            // remove notifier
                            if(en_hmm) {
                                dbg_info("releasing notifier for hpid %d\n", tmp_h_entry->hpid);
                                mmu_interval_notifier_remove(&tmp_h_entry->mmu_not);
                            }
                #endif 

                            // free from hpid hash
                            hash_del(&tmp_h_entry->entry);

                            // free from spid hash
                            hash_for_each_possible(spid_hpid_map[d->id], tmp_s_entry, entry, current->pid) {
                                if(tmp_s_entry->spid == current->pid && tmp_s_entry->hpid == tmp_h_entry->hpid) {
                                    // free from hpid hash
                                    hash_del(&tmp_s_entry->entry);
                                }
                            }
                        }
                    }
                }


                // free from ref count hash
                hash_del(&tmp_c_entry->entry);
            }

        }
    }
    
    pr_info("fpga device %d released, spid %d\n", minor, current->pid);

    return 0;
}

/**
 * @brief ioctl, control and status
 * 
 */
long fpga_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
    int ret_val, i;
    uint64_t tmp[MAX_USER_WORDS];
    int32_t cpid;
    pid_t hpid;
    pid_t spid;
    struct spid_hpid_pages *tmp_s_entry, *new_s_entry;
    struct hpid_cpid_pages *tmp_h_entry, *new_h_entry;
    struct list_head *l_p, *l_n;
    struct cpid_entry *l_entry;
    bool k = false;
#ifdef HMM_KERNEL    
    struct task_struct *task;
    struct mm_struct *mm;
#endif

    struct fpga_dev *d = (struct fpga_dev *)file->private_data;
    struct bus_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    switch (cmd) {

    // register a new cpid
    case IOCTL_REGISTER_CPID:
        // read cpid
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, sizeof(unsigned long));
        if (ret_val != 0) {
            pr_info("user data could not be coppied, return %d\n", ret_val);
        } else {
            
            // lock
            spin_lock(&d->pid_lock);

            spid = current->pid;
            hpid = (pid_t)tmp[0];

            // map
            if(d->num_free_pid_chunks == 0) {
                dbg_info("registration failed hpid %d, spid %d\n", hpid, spid);
                return -ENOMEM;
            }

            cpid = (int32_t)d->pid_alloc->id;
            d->pid_array[d->pid_alloc->id] = hpid;
            d->pid_alloc = d->pid_alloc->next;

            // add to spid map
            hash_for_each_possible(spid_hpid_map[d->id], tmp_s_entry, entry, spid) {
                if(tmp_s_entry->spid == spid && tmp_s_entry->hpid == hpid) {
                    k = true;
                }
            }

            if(!k) {
                new_s_entry = kzalloc(sizeof(struct spid_hpid_pages), GFP_KERNEL);
                BUG_ON(!new_s_entry);
                new_s_entry->hpid = hpid;
                new_s_entry->spid = spid;
                hash_add(spid_hpid_map[d->id], &new_s_entry->entry, spid);
                dbg_info("new entry in spid map, spid %d, hpid %d\n", hpid, spid);
            }
            
            // add to hpid map
            k = false;
            hash_for_each_possible(hpid_cpid_map[d->id], tmp_h_entry, entry, hpid) {
                if(tmp_h_entry->hpid == hpid) {
                    k = true;
                }
            }

            if(!k) {
                new_h_entry = kzalloc(sizeof(struct hpid_cpid_pages), GFP_KERNEL);
                BUG_ON(!new_h_entry);
                new_h_entry->hpid = hpid;
                INIT_LIST_HEAD(&new_h_entry->cpid_list);
#ifdef HMM_KERNEL
                if(en_hmm) {
                    task = pid_task(find_vpid(hpid), PIDTYPE_PID);
                    mm = task->mm;
                
                    ret_val = mmu_interval_notifier_insert(&new_h_entry->mmu_not, mm, 0, ULONG_MAX & PAGE_MASK, &cyt_not_ops);
                    if (ret_val) {
                        dbg_info("mmu notifier registration failed, vFPGA %d\n", d->id);
                        kfree(new_h_entry);
                        return ret_val;
                    } 
                }
#endif
                hash_add(hpid_cpid_map[d->id], &new_h_entry->entry, hpid);
            }

            //  add cpid
            hash_for_each_possible(hpid_cpid_map[d->id], tmp_h_entry, entry, hpid) {
                if(tmp_h_entry->hpid == hpid) {
                    // add to cpid list
                    l_entry = kmalloc(sizeof(struct cpid_entry), GFP_KERNEL);
                    BUG_ON(!l_entry);
                    l_entry->cpid = cpid;

                    list_add_tail(&l_entry->list, &tmp_h_entry->cpid_list);
                }
            }

#ifdef HMM_KERNEL
            INIT_LIST_HEAD(&migrated_pages[d->id][cpid]);
#endif            

            pr_info("registration succeeded, cpid %d, hpid %d, spid %d\n", cpid, hpid, spid);

            // return cpid
            tmp[1] = (int64_t) cpid;
            ret_val = copy_to_user((unsigned long *)arg, &tmp, 2 * sizeof(unsigned long));
            
            // unlock
            spin_unlock(&d->pid_lock);
        }
        break;
    
    // unregister cpid
    case IOCTL_UNREGISTER_CPID:
        // read cpid
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, sizeof(unsigned long));
        if (ret_val != 0) {
            pr_info("user data could not be coppied, return %d\n", ret_val);
        } else {
            spin_lock(&d->pid_lock);
            
            cpid = (int32_t)tmp[0];
            
            // map
            hpid = d->pid_array[cpid];
            spid = current->pid;
        
            // hash
            hash_for_each_possible(hpid_cpid_map[d->id], tmp_h_entry, entry, hpid) {
                if(tmp_h_entry->hpid == hpid) {
                    // traverse all cpid
                    list_for_each_safe(l_p, l_n, &tmp_h_entry->cpid_list) {
                        // entry
                        l_entry = list_entry(l_p, struct cpid_entry, list);

                        if(l_entry->cpid == cpid) {
    #ifdef HMM_KERNEL
                            // unamp all leftover user pages
                            if(en_hmm)
                                free_card_mem(d, cpid);
                            else 
    #endif                            
                                tlb_put_user_pages_cpid(d, cpid, hpid, 1);

                            // unregister (if registered)
                            d->pid_chunks[l_entry->cpid].next = d->pid_alloc;
                            d->pid_alloc = &d->pid_chunks[l_entry->cpid];

                            // delete entry
                            list_del(&l_entry->list);   
                        }
                    }

                    // remove if all cpid are gone
                    if(list_empty(&tmp_h_entry->cpid_list)) {
#ifdef HMM_KERNEL                        
                        // remove notifier
                        if(en_hmm) {
                            dbg_info("releasing notifier for hpid %d\n", hpid);
                            mmu_interval_notifier_remove(&tmp_h_entry->mmu_not);
                        }
#endif 

                        // free from hpid hash
                        hash_del(&tmp_h_entry->entry);

                        // free from spid hash
                        hash_for_each_possible(spid_hpid_map[d->id], tmp_s_entry, entry, spid) {
                            if(tmp_s_entry->spid == spid && tmp_s_entry->hpid == hpid) {
                                // free from hpid hash
                                hash_del(&tmp_s_entry->entry);
                            }
                        }
                    }
                }
            }

            pr_info("unregistration succeeded, cpid %d, hpid %d, spid %d\n", cpid, hpid, spid);

            spin_unlock(&d->pid_lock);
            
        }
        break;

    // notify registration
    case IOCTL_REGISTER_EVENTFD:
        // cpid + eventfd descriptor
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, 2 * sizeof(uint64_t));
        if (ret_val) {
            pr_info("user data could not be coppied, ret_val: %d\n", ret_val);
        } else {
            ret_val = fpga_register_eventfd(d, (int32_t)tmp[0], tmp[1]);
            if (ret_val) {
                pr_info("eventfd could not be registered, ret_val: %d\n", ret_val);
            }
        }
        break;

    case IOCTL_UNREGISTER_EVENTFD:
        // cpid
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, 2 * sizeof(uint64_t));
        if (ret_val) {
            pr_info("user data could not be coppied, ret_val: %d\n", ret_val);
        } else {
            fpga_unregister_eventfd(d, (int32_t)tmp[0]);
        }
        break;
    
    // explicit mapping
    case IOCTL_MAP_USER:
        // read vaddr + len + cpid
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, 3 * sizeof(unsigned long));
        if (ret_val != 0) {
            pr_info("user data could not be coppied, return %d\n", ret_val);
        } else {
            hpid = d->pid_array[cpid];

            // lock
            mutex_lock(&d->mmu_lock);
            fpga_change_lock_tlb(d);

#ifdef HMM_KERNEL
            if(en_hmm) 
                ret_val = mmu_handler_hmm(d, tmp[0], tmp[1], (int32_t)tmp[2], true, hpid);
            else
#endif            
                ret_val = mmu_handler_gup(d, tmp[0], tmp[1], (int32_t)tmp[2], true, hpid);
            
            if(ret_val) {
                pr_info("buffer could not be mapped, ret_val: %d\n", ret_val);
            }

            // unlock
            fpga_change_lock_tlb(d);
            mutex_unlock(&d->mmu_lock);

            dbg_info("user mapping vFPGA %d handled\n", d->id);
        }
        break;

    // explicit unmapping
    case IOCTL_UNMAP_USER:
        // read vaddr + cpid
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, 2 * sizeof(unsigned long));
        if (ret_val != 0) {
            pr_info("user data could not be coppied, return %d\n", ret_val);
        } else {
            if(!en_hmm) {
                hpid = d->pid_array[cpid];

                // lock
                mutex_lock(&d->mmu_lock);
                fpga_change_lock_tlb(d);

                tlb_put_user_pages(d, tmp[0], (int32_t)tmp[1], hpid, 1);

                // unlock
                fpga_change_lock_tlb(d);
                mutex_unlock(&d->mmu_lock);

                dbg_info("user unmapping vFPGA %d handled\n", d->id);
            }
        }
        break;
    
    // Offload
    case IOCTL_OFFLOAD_REQ:
        // read vaddr + cpid
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, 2 * sizeof(unsigned long));
        if (ret_val != 0) {
            pr_info("user data could not be coppied, return %d\n", ret_val);
        } else {
            if(!en_hmm) {
                ret_val = offload_user_gup(d, tmp[0], (int32_t)tmp[1]);
                if(ret_val) {
                    pr_info("buffer could not be offloaded, ret_val: %d\n", ret_val);
                }
            }
        }
        break;

    // Sync
    case IOCTL_SYNC_REQ:
        // read vaddr + cpid
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, 2 * sizeof(unsigned long));
        if (ret_val != 0) {
            pr_info("user data could not be coppied, return %d\n", ret_val);
        } else {
            if(!en_hmm) {
                ret_val = sync_user_gup(d, tmp[0], (int32_t)tmp[1]);
                if(ret_val) {
                    pr_info("buffer could not be synced, ret_val: %d\n", ret_val);
                }
            }
        }
        break;

    // set ip address
    case IOCTL_SET_IP_ADDRESS:
        if (pd->en_net) {
            ret_val = copy_from_user(&tmp, (unsigned long*) arg, sizeof(unsigned long));
            if (ret_val != 0) {
                pr_info("user data could not be coppied, return %d\n", ret_val);
            }
            else {
                spin_lock(&pd->stat_lock);

                // ip change
                pd->fpga_shell_cnfg->net_ip = tmp[0];
                dbg_info("ip address changed to %08llx\n", tmp[0]);
                pd->net_ip_addr = tmp[0];

                spin_unlock(&pd->stat_lock);
            }
        } else {
            pr_info("network not enabled\n");
            return -1;
        }
        break;

    // set board number
    case IOCTL_SET_MAC_ADDRESS:
        if (pd->en_net) {
            ret_val = copy_from_user(&tmp, (unsigned long*) arg, sizeof(unsigned long));
            if (ret_val != 0) {
                pr_info("user data could not be coppied, return %d\n", ret_val);
            } else {
                spin_lock(&pd->stat_lock);

                pd->fpga_shell_cnfg->net_mac = tmp[0];
                dbg_info("mac address changed to %llx\n", tmp[0]);
                pd->net_mac_addr = tmp[0];

                spin_unlock(&pd->stat_lock);
            }
        } else {
            pr_info("network not enabled\n");
            return -1;
        }
        break;
    
    // read config
    case IOCTL_READ_CNFG:
        tmp[0] = ((uint64_t)pd->n_fpga_chan << 32) | ((uint64_t)pd->n_fpga_reg << 48) |
                 ((uint64_t)pd->en_avx) | ((uint64_t)pd->en_wb << 1) |
                 ((uint64_t)pd->en_strm << 2) | ((uint64_t)pd->en_mem << 3) | ((uint64_t)pd->en_pr << 4) | 
                 ((uint64_t)pd->en_rdma << 16) | ((uint64_t)pd->en_tcp << 17);
        dbg_info("reading config 0x%llx\n", tmp[0]);
        ret_val = copy_to_user((unsigned long *)arg, &tmp, sizeof(unsigned long));
        break;

    // xdma status
    case IOCTL_SHELL_XDMA_STATS:
        dbg_info("retreiving xdma status");
        for(i = 0; i < pd->n_fpga_chan * N_XDMA_STAT_CH_REGS; i++) {
            tmp[i] = pd->fpga_shell_cnfg->xdma_debug[i];
        }
        ret_val = copy_to_user((unsigned long *)arg, &tmp, pd->n_fpga_chan * N_XDMA_STAT_CH_REGS * sizeof(unsigned long));
        break;

    // network status
    case IOCTL_SHELL_NET_STATS:
        if (pd->en_net) {
            dbg_info("retreiving network status for port %llx", tmp[0]);
            for (i = 0; i < N_NET_STAT_REGS; i++) {
                tmp[i] = pd->fpga_shell_cnfg->net_debug[i];
            }
            ret_val = copy_to_user((unsigned long *)arg, &tmp, N_NET_STAT_REGS * sizeof(unsigned long));
        }
        else {
            dbg_info("network not enabled\n");
        }
        break;

    default:
        break;

    }

    return 0;
}

/**
 * @brief Mmap control and mem
 * 
 */
int fpga_mmap(struct file *file, struct vm_area_struct *vma)
{
    struct fpga_dev *d;

    d = (struct fpga_dev *)file->private_data;
    BUG_ON(!d);

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

    return -EINVAL;
}