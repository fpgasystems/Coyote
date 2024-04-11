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

#include "fpga_pops.h"

/*
██████╗  ██████╗ ██████╗ ███████╗
██╔══██╗██╔═══██╗██╔══██╗██╔════╝
██████╔╝██║   ██║██████╔╝███████╗
██╔═══╝ ██║   ██║██╔═══╝ ╚════██║
██║     ╚██████╔╝██║     ███████║
╚═╝      ╚═════╝ ╚═╝     ╚══════╝
*/  

/**
 * @brief Acquire a reconfiguration conrtoller
 * 
 */
int pr_open(struct inode *inode, struct file *file)
{
    int minor = iminor(inode);

    struct pr_dev *d = container_of(inode->i_cdev, struct pr_dev, cdev);
    BUG_ON(!d);

    dbg_info("reconfiguration device %d acquired, pid %d\n", minor, current->pid);

    // set private data
    file->private_data = (void *)d;

    return 0;
}

/**
 * @brief Release a region
 * 
 */
int pr_release(struct inode *inode, struct file *file)
{
    int minor = iminor(inode);

    struct pr_dev *d = container_of(inode->i_cdev, struct pr_dev, cdev);
    BUG_ON(!d);

    dbg_info("reconfiguration device %d released, pid %d\n", minor, current->pid);

    return 0;
}


/**
 * @brief ioctl, control and status
 * 
 */
long pr_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
    int ret_val = 0, i;
    struct pr_dev *d = (struct pr_dev *)file->private_data;
    struct bus_drvdata *pd;
    uint64_t tmp[MAX_USER_WORDS];
    uint64_t start_time, stop_time;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    switch (cmd) {
        case IOCTL_ALLOC_HOST_PR_MEM:
            // read n_pages
            ret_val = copy_from_user(&tmp, (unsigned long *)arg, 3 * sizeof(unsigned long));
            if (ret_val != 0) {
                pr_info("user data could not be coppied, return %d\n", ret_val);
            }
            else {
                ret_val = alloc_pr_buffers(d, tmp[0], tmp[1], tmp[2]);
                dbg_info("buff_num %d, arg %lx\n", d->curr_buff.n_pages, arg);
                if (ret_val != 0) {
                    pr_info("reconfig buffers could not be allocated\n");
                }
            }
            break;

        case IOCTL_FREE_HOST_PR_MEM:
            // read vaddr
            ret_val = copy_from_user(&tmp, (unsigned long *)arg, 3 * sizeof(unsigned long));
            if (ret_val != 0) {
                pr_info("user data could not be coppied, return %d\n", ret_val);
            }
            else {
                ret_val = free_pr_buffers(d, tmp[0], tmp[1], tmp[2]);
                dbg_info("reconfig buffers freed\n");
            }
            break;

        // reconfig shell
        case IOCTL_RECONFIGURE_SHELL:
            // read vaddr + len
            ret_val = copy_from_user(&tmp, (unsigned long *)arg, 4 * sizeof(unsigned long));
            if (ret_val != 0) {
                pr_info("user data could not be coppied, return %d\n", ret_val);
            } else {
                dbg_info("trying to obtain reconfig lock, pid %d\n", current->pid);
                
                // lock
                mutex_lock(&d->rcnfg_lock);

                // clean up current state
                if(cyt_arch == CYT_ARCH_PCI) {
                    shell_pci_remove(pd);
                } else {
                    shell_eci_remove(pd);
                }

                // decouple
                pd->fpga_stat_cnfg->pr_dcpl_set = 0x1;

                // reconfigure
                start_time = ktime_get_ns();

                ret_val = reconfigure_start(d, tmp[0], tmp[1], tmp[2], tmp[3]);
                if (ret_val != 0) {
                    pr_info("reconfiguration not successful, return %d\n", ret_val);
                    return -1;
                }

                // completion
                wait_event_interruptible(d->waitqueue_rcnfg, atomic_read(&d->wait_rcnfg) == FLAG_SET);
                
                // time
                stop_time = ktime_get_ns();
                pr_info("shell reconfiguration time %llu ms\n", (stop_time - start_time) / (1000 * 1000));

                atomic_set(&d->wait_rcnfg, FLAG_CLR);

                // reset
                pd->fpga_stat_cnfg->pr_eost_reset = 0x0;
                pd->fpga_stat_cnfg->pr_eost_reset = 0x1;

                // couple
                dbg_info("releasing reconfig lock, coupling the shell\n");
                pd->fpga_stat_cnfg->pr_dcpl_clr = 0x1;

                // reinit
                if(cyt_arch == CYT_ARCH_PCI) {
                    shell_pci_init(pd);
                } else {
                    
                    shell_eci_init(pd);
                }

                mutex_unlock(&d->rcnfg_lock);
            }
            break;

        // reconfig app
        case IOCTL_RECONFIGURE_APP:
            // read vaddr + len + vfid
            ret_val = copy_from_user(&tmp, (unsigned long *)arg, 5 * sizeof(unsigned long));
            if (ret_val != 0) {
                pr_info("user data could not be coppied, return %d\n", ret_val);
            } else {
                dbg_info("trying to obtain reconfig lock, pid %d\n", current->pid);
                
                // lock
                mutex_lock(&d->rcnfg_lock);

                // decouple
                pd->fpga_shell_cnfg->pr_dcpl_app_set = (1 << (uint32_t)tmp[4]);

                // reconfigure
                start_time = ktime_get_ns();

                ret_val = reconfigure_start(d, tmp[0], tmp[1], tmp[2], tmp[3]);
                if (ret_val != 0) {
                    pr_info("reconfiguration not successful, return %d\n", ret_val);
                    return -1;
                }

                // completion
                wait_event_interruptible(d->waitqueue_rcnfg, atomic_read(&d->wait_rcnfg) == FLAG_SET);

                // time
                stop_time = ktime_get_ns();
                pr_info("app reconfiguration time %llu ms\n", (stop_time - start_time) / (1000 * 1000));

                atomic_set(&d->wait_rcnfg, FLAG_CLR);

                // couple
                dbg_info("releasing reconfig lock, coupling the design\n");
                pd->fpga_shell_cnfg->pr_dcpl_app_clr = (1 << (uint32_t)tmp[3]);

                mutex_unlock(&d->rcnfg_lock);
            }
            break;

        // config
        case IOCTL_PR_CNFG:
            tmp[0] = (uint64_t)pd->en_pr;
            dbg_info("reading pr config 0x%llx\n", tmp[0]);
            ret_val = copy_to_user((unsigned long *)arg, &tmp, sizeof(unsigned long));
            break;

        // xdma status
        case IOCTL_STATIC_XDMA_STATS:
            dbg_info("retreiving xdma status");
            for(i = 0; i < N_XDMA_STAT_CH_REGS; i++) {
                tmp[i] = pd->fpga_stat_cnfg->xdma_debug[i];
            }
            ret_val = copy_to_user((unsigned long *)arg, &tmp, N_XDMA_STAT_CH_REGS * sizeof(unsigned long));
            break;

        default: 
            break;
    }

    return ret_val;
}

int pr_mmap(struct file *file, struct vm_area_struct *vma)
{
    int i;
    unsigned long vaddr;
    unsigned long vaddr_tmp;
    struct pr_dev *d;
    struct pr_pages *new_buff;
    struct bus_drvdata *pd;
   
    d = (struct pr_dev *)file->private_data;
    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    vaddr = vma->vm_start;

    vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);

    // map PR buffers
    if (vma->vm_pgoff == MMAP_PR)
    {
        dbg_info("reconfig device, mmap\n");

        // aligned page virtual address
        vaddr = ((vma->vm_start + pd->ltlb_order->page_size - 1) >> pd->ltlb_order->page_shift) << pd->ltlb_order->page_shift;
        vaddr_tmp = vaddr;

        if (d->curr_buff.n_pages != 0 && d->curr_buff.pid == current->pid) {
            // obtain mem lock
            spin_lock(&d->mem_lock);

            new_buff = kzalloc(sizeof(struct pr_pages), GFP_KERNEL);
            BUG_ON(!new_buff);

            // Map entry
            new_buff->vaddr = vaddr;
            new_buff->pid = current->pid;
            new_buff->crid = d->curr_buff.crid;
            new_buff->n_pages = d->curr_buff.n_pages;
            new_buff->pages = d->curr_buff.pages;

            hash_add(pr_buff_map, &new_buff->entry, vaddr);

            for (i = 0; i < new_buff->n_pages; i++) {
                // map to user space
                if (remap_pfn_range(vma, vaddr_tmp, page_to_pfn(d->curr_buff.pages[i]),
                                    pd->ltlb_order->page_size, vma->vm_page_prot)) {
                    return -EIO;
                }
                // next page vaddr
                vaddr_tmp += pd->ltlb_order->page_size;
            }

            // Current host buff empty
            d->curr_buff.n_pages = 0;

            // release mem lock
            spin_unlock(&d->mem_lock);

            return 0;
        }
    }

    return -EINVAL;
}
