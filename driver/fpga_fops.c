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
 _____
|  ___|__  _ __  ___
| |_ / _ \| '_ \/ __|
|  _| (_) | |_) \__ \
|_|  \___/| .__/|___/
          |_|
*/

struct hlist_head pid_cpid_map[MAX_N_REGIONS][1 << (USER_HASH_TABLE_ORDER)]; // cid mapping

 /**
 * @brief Acquire a region
 * 
 */
int fpga_open(struct inode *inode, struct file *file)
{
    int minor = iminor(inode);

    struct fpga_dev *d = container_of(inode->i_cdev, struct fpga_dev, cdev);
    BUG_ON(!d);

    dbg_info("fpga device %d acquired, calling pid %d\n", minor, current->pid);

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
    int32_t cpid;
    struct cid_entry *tmp_cid;
    pid_t pid;

    int minor = iminor(inode);

    struct fpga_dev *d = container_of(inode->i_cdev, struct fpga_dev, cdev);
    BUG_ON(!d);

    pid = current->pid;

    hash_for_each_possible(pid_cpid_map[d->id], tmp_cid, entry, pid) {
        if(tmp_cid->pid == pid) {
            cpid = tmp_cid->cpid;

            // unamp all leftover user pages
            tlb_put_user_pages_cpid(d, cpid, 1);

            // unregister (if registered)
            unregister_pid(d, cpid);

            // Free from hash
            hash_del(&tmp_cid->entry);
        }
    }

    dbg_info("fpga device %d released, pid %d\n", minor, current->pid);

    return 0;
}

/**
 * @brief XDMA engine status
 * 
 */
uint32_t engine_status_read(struct xdma_engine *engine)
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

/**
 * @brief ioctl, control and status
 * 
 */
long fpga_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
    int ret_val, i;
    uint64_t tmp[MAX_USER_WORDS];
    uint64_t cpid;
    pid_t pid;
    struct cid_entry *tmp_cid;

    struct fpga_dev *d = (struct fpga_dev *)file->private_data;
    struct bus_drvdata *pd;

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
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, sizeof(unsigned long));
        if (ret_val != 0) {
            pr_info("user data could not be coppied, return %d\n", ret_val);
        } else {
            spin_lock(&pd->stat_lock);

            pid = (pid_t) tmp[0];

            cpid = (int32_t)register_pid(d, pid);
            if (cpid == -1)
            {
                dbg_info("registration failed pid %d\n", pid); 
                return -1;
            }

            tmp_cid = kzalloc(sizeof(struct cid_entry), GFP_KERNEL);
            BUG_ON(!tmp_cid);

            tmp_cid->pid = pid;
            tmp_cid->cpid = cpid;

            hash_add(pid_cpid_map[d->id], &tmp_cid->entry, pid);

            // return cpid
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
        } else {
            spin_lock(&pd->stat_lock);
            
            cpid = tmp[0];
            pid = d->pid_array[cpid];

            // map
            hash_for_each_possible(pid_cpid_map[d->id], tmp_cid, entry, pid) {
                if(tmp_cid->pid == pid && tmp_cid->cpid == cpid) {
                    // unamp all leftover user pages
                    tlb_put_user_pages_cpid(d, cpid, 1);

                    // Free from hash
                    hash_del(&tmp_cid->entry);
                }
            }

            ret_val = unregister_pid(d, cpid); // tmp[0] - cpid
            if (ret_val == -1) {
                dbg_info("unregistration failed cpid %lld\n", cpid);
                return -1;
            }

            spin_unlock(&pd->stat_lock);
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
            ret_val = copy_from_user(&tmp, (unsigned long*) arg, 2 * sizeof(unsigned long));
            if (ret_val != 0) {
                pr_info("user data could not be coppied, return %d\n", ret_val);
            } else {
                dbg_info("arp lookup qsfp%llx, target ip %08llx", tmp[0], tmp[1]);
                spin_lock(&pd->stat_lock);
    
                tmp[0] ? (pd->fpga_stat_cnfg->net_1_arp = tmp[1]) : 
                    (pd->fpga_stat_cnfg->net_0_arp = tmp[1]);

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

                // ip change
                if(tmp[0]) {
                    if(pd->net_1_ip_addr != tmp[1]) {
                        pd->fpga_stat_cnfg->net_1_ip = tmp[1];
                        dbg_info("ip address qsfp%llx changed to %08llx\n", tmp[0], tmp[1]);
                        pd->net_1_ip_addr = tmp[1];
                    }
                } else {
                    if(pd->net_0_ip_addr != tmp[1]) {
                        pd->fpga_stat_cnfg->net_0_ip = tmp[1];
                        dbg_info("ip address qsfp%llx changed to %08llx\n", tmp[0], tmp[1]);
                        pd->net_0_ip_addr = tmp[1];
                    }
                }

                spin_unlock(&pd->stat_lock);
                
            }
        } else {
            pr_info("network not enabled\n");
            return -1;
        }

        break;

    // set board number
    case IOCTL_SET_MAC_ADDRESS:
        if (pd->en_net_0 || pd->en_net_1) {
            ret_val = copy_from_user(&tmp, (unsigned long*) arg, 2 * sizeof(unsigned long));
            if (ret_val != 0) {
                pr_info("user data could not be coppied, return %d\n", ret_val);
            } else {
                spin_lock(&pd->stat_lock);

                // mac address change
                if(tmp[0]) {
                    if(pd->net_1_mac_addr != tmp[1]) {
                        pd->fpga_stat_cnfg->net_1_mac = tmp[1];
                        dbg_info("mac address qsfp%llx changed to %llx\n", tmp[0], tmp[1]);
                        pd->net_1_mac_addr = tmp[1];
                    }
                } else {
                    if(pd->net_0_mac_addr != tmp[1]) {
                        pd->fpga_stat_cnfg->net_0_mac = tmp[1];
                        dbg_info("mac address qsfp%llx changed to %llx\n", tmp[0], tmp[1]);
                        pd->net_0_mac_addr = tmp[1];
                    }
                }

                spin_unlock(&pd->stat_lock);
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
        dbg_info("reading config 0x%llx\n", tmp[0]);
        ret_val = copy_to_user((unsigned long *)arg, &tmp, sizeof(unsigned long));
        break;

    // xdma status
    case IOCTL_XDMA_STATS:
        dbg_info("retreiving xdma status");
        for(i = 0; i < pd->n_fpga_chan * N_XDMA_STAT_CH_REGS; i++) {
            tmp[i] = pd->fpga_stat_cnfg->xdma_debug[i];
        }
        ret_val = copy_to_user((unsigned long *)arg, &tmp, pd->n_fpga_chan * N_XDMA_STAT_CH_REGS * sizeof(unsigned long));
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

    // net dropper
    case IOCTL_NET_DROP:
        if (pd->en_net_0 || pd->en_net_1) {
            ret_val = copy_from_user(&tmp, (unsigned long*) arg, 4 * sizeof(unsigned long));
            if (ret_val != 0) {
                pr_info("user data could not be coppied, return %d\n", ret_val);
            }
            else {
                spin_lock(&pd->stat_lock);

                // tmp[0] - qsfp, tmp[1] - clr, tmp[2] - tx

                if(tmp[0] == 0) {
                    if(tmp[1]) {
                        // clear
                        pd->fpga_stat_cnfg->net_drop_clr_0 = 0x1;
                        pr_info("clear q0 network drop\n");
                    } else {
                        // drop
                        if(tmp[2]) pd->fpga_stat_cnfg->net_drop_0[1] = tmp[3];
                        else pd->fpga_stat_cnfg->net_drop_0[0] = tmp[3];
                        pr_info("drop set q0, tx %llx, packet number %llx, \n", tmp[2], tmp[3]);
                    }
                } else {
                    if(tmp[1]) {
                        // clear
                        pd->fpga_stat_cnfg->net_drop_clr_1 = 0x1;
                        pr_info("clear q1 network drop\n");
                    } else {
                        // drop
                        if(tmp[2]) pd->fpga_stat_cnfg->net_drop_1[1] = tmp[3];
                        else pd->fpga_stat_cnfg->net_drop_1[0] = tmp[3];
                        pr_info("drop set q1, tx %llx, packet number %llx, \n", tmp[2], tmp[3]);
                    }
                }

                spin_unlock(&pd->stat_lock);
                
            }
        } else {
            pr_info("network not enabled\n");
            return -1;
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
    int i;
    unsigned long vaddr;
    unsigned long vaddr_tmp;
    struct fpga_dev *d;
    struct pr_ctrl *prc;
    struct user_pages *new_user_buff;
    struct pr_pages *new_pr_buff;
    struct bus_drvdata *pd;
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

/*
 _   _ _   _ _
| | | | |_(_) |
| | | | __| | |
| |_| | |_| | |
 \___/ \__|_|_|
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
    d->pid_chunks[cpid].used = true;
    d->pid_array[d->pid_alloc->id] = pid;
    d->pid_alloc = d->pid_alloc->next;

    // unlock
    spin_unlock(&d->card_pid_lock);

    dbg_info("registration succeeded pid %d, cpid %d\n", pid, cpid);

    return cpid;
}

/**
 * @brief Unregister Coyote PID
 * 
 * @param d - vFPGA
 * @param cpid - Coyote PID
 */
int unregister_pid(struct fpga_dev *d, int32_t cpid)
{
    BUG_ON(!d);

    // lock
    spin_lock(&d->card_pid_lock);

    if(d->pid_chunks[cpid].used == true) {
        d->pid_chunks[cpid].used = false;
        d->pid_chunks[cpid].next = d->pid_alloc;
        d->pid_alloc = &d->pid_chunks[cpid];
    }

    // release lock
    spin_unlock(&d->card_pid_lock);

    dbg_info("unregistration succeeded cpid %d\n", cpid);

    return 0;
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
int reconfigure(struct fpga_dev *d, uint64_t vaddr, uint64_t len)
{
    struct pr_ctrl *prc;
    struct pr_pages *tmp_buff;
    int i;
    uint64_t fsz_m;
    uint64_t fsz_r;
    uint64_t pr_bsize = PR_BATCH_SIZE;
    struct bus_drvdata *pd;

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
