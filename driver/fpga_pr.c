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

#include "fpga_pr.h"

/*
██████╗ ██████╗ 
██╔══██╗██╔══██╗
██████╔╝██████╔╝
██╔═══╝ ██╔══██╗
██║     ██║  ██║
╚═╝     ╚═╝  ╚═╝
*/ 

/* Hash tables */
struct hlist_head pr_buff_map[1 << (PR_HASH_TABLE_ORDER)]; 

/**
 * @brief ISR
 *
 */
irqreturn_t pr_isr(int irq, void *dev_id)
{
    struct pr_dev *d;
    unsigned long flags;

    dbg_info("(irq=%d) ISR entry\n", irq);

    d = (struct pr_dev *)dev_id;
    BUG_ON(!d);

    // lock
    spin_lock_irqsave(&(d->irq_lock), flags);

    dbg_info("(irq=%d) reconfig completed\n", irq);
    atomic_set(&d->wait_rcnfg, FLAG_SET);
    wake_up_interruptible(&d->waitqueue_rcnfg);

    // clear irq
    pr_clear_irq(d);

    // unlock
    spin_unlock_irqrestore(&(d->irq_lock), flags);

    return IRQ_HANDLED;
}

/**
 * @brief Allocate PR buffers
 * 
 * @param d - reconfig. dev
 * @param n_pages - number of pages to allocate
 */
int alloc_pr_buffers(struct pr_dev *d, unsigned long n_pages, pid_t pid, uint32_t crid)
{
    int i;
    struct bus_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    // obtain mem lock
    spin_lock(&d->mem_lock);

    if (d->curr_buff.n_pages) {
        dbg_info("allocated reconfig buffers exist and are not mapped\n");
        return -1;
    }

    if (n_pages > MAX_PR_BUFF_NUM)
        d->curr_buff.n_pages = MAX_PR_BUFF_NUM;
    else
        d->curr_buff.n_pages = n_pages;

    d->curr_buff.pages = vmalloc(n_pages * sizeof(*d->curr_buff.pages));
    if (d->curr_buff.pages == NULL) {
        return -ENOMEM;
    }

    dbg_info("allocated %lu bytes for page pointer array for %ld PR buffers @0x%p.\n",
             n_pages * sizeof(*d->curr_buff.pages), n_pages, d->curr_buff.pages);

    for (i = 0; i < d->curr_buff.n_pages; i++) {
        d->curr_buff.pages[i] = alloc_pages(GFP_ATOMIC, pd->ltlb_order->page_shift - PAGE_SHIFT);
        if (!d->curr_buff.pages[i]) {
            dbg_info("reconfig buffer %d could not be allocated\n", i);
            goto fail_alloc;
        }

        //dbg_info("reconfig buffer allocated @ %llx \n", page_to_phys(d->curr_buff.pages[i]));
    }

    d->curr_buff.pid = pid;
    d->curr_buff.crid = crid;

    // release mem lock
    spin_unlock(&d->mem_lock);

    return 0;

fail_alloc:
    while (i)
        __free_pages(d->curr_buff.pages[--i], pd->ltlb_order->page_shift - PAGE_SHIFT);
    d->curr_buff.n_pages = 0;
    
    // release mem lock
    spin_unlock(&d->mem_lock);
    return -ENOMEM;
}

/**
 * @brief Free PR buffers
 * 
 * @param d - reconfig. dev
 * @param vaddr - virtual address
 */
int free_pr_buffers(struct pr_dev *d, uint64_t vaddr, pid_t pid, uint32_t crid)
{
    int i;
    struct pr_pages *tmp_buff;
    struct bus_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    hash_for_each_possible(pr_buff_map, tmp_buff, entry, vaddr) {
        if (tmp_buff->vaddr == vaddr && tmp_buff->pid == pid && tmp_buff->crid == crid) {

            // free pages
            for (i = 0; i < tmp_buff->n_pages; i++) {
                if (tmp_buff->pages[i])
                    __free_pages(tmp_buff->pages[i], pd->ltlb_order->page_shift - PAGE_SHIFT);
            }

            vfree(tmp_buff->pages);

            // delete entry
            hash_del(&tmp_buff->entry);
        }
    }

    return 0;
}

/**
 * @brief Clear pending irq
 * 
 * @param d - reconfig. dev
*/
void pr_clear_irq(struct pr_dev *d) {
    struct bus_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    // clear
    pd->fpga_stat_cnfg->pr_ctrl = PR_CTRL_IRQ_CLR_PENDING;
}

/**
 * @brief Reconfigure the vFPGA
 * 
 * @param d - reconfig. dev
 * @param vaddr - bitstream vaddr
 * @param len - bitstream length
 */
int reconfigure_start(struct pr_dev *d, uint64_t vaddr, uint64_t len, pid_t pid, uint32_t crid)
{
    struct pr_pages *tmp_buff;
    int i;
    uint64_t fsz_m;
    uint64_t fsz_r;
    uint64_t pr_bsize;
    struct bus_drvdata *pd;
    int cmd_sent = 0;
    bool k = false;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    pr_bsize = pd->ltlb_order->page_size;

    hash_for_each_possible(pr_buff_map, tmp_buff, entry, vaddr) {

        if (tmp_buff->vaddr == vaddr && tmp_buff->pid == pid && tmp_buff->crid == crid) {
            // Reconfiguration
            fsz_m = len / pr_bsize;
            fsz_r = len % pr_bsize;
            dbg_info("bitstream full %lld x 2 MB, partial %lld B\n", fsz_m, fsz_r);

            // full
            for (i = 0; i < fsz_m; i++) {
                while(cmd_sent >= PR_THRSH) {
                    cmd_sent = pd->fpga_stat_cnfg->pr_ctrl;
                    usleep_range(PR_MIN_SLEEP_CMD, PR_MAX_SLEEP_CMD);
                }

                //dbg_info("page %d, phys %llx, len %llx\n", i, page_to_phys(tmp_buff->pages[fsz_m]), pr_bsize);
                pd->fpga_stat_cnfg->pr_addr_low = LOW_32(page_to_phys(tmp_buff->pages[i]));
                pd->fpga_stat_cnfg->pr_addr_high = HIGH_32(page_to_phys(tmp_buff->pages[i]));
                pd->fpga_stat_cnfg->pr_len = pr_bsize;
                if (fsz_r == 0 && i == fsz_m - 1)
                    pd->fpga_stat_cnfg->pr_ctrl = PR_CTRL_START_LAST;
                else
                    pd->fpga_stat_cnfg->pr_ctrl = PR_CTRL_START_MIDDLE;

                wmb();
                cmd_sent++;
            }

            // partial
            if (fsz_r > 0) {
                while(cmd_sent >= PR_THRSH) {
                    cmd_sent = pd->fpga_stat_cnfg->pr_ctrl;
                    usleep_range(PR_MIN_SLEEP_CMD, PR_MAX_SLEEP_CMD);
                }

                //dbg_info("page %lld, phys %llx, len %llx\n", fsz_m, page_to_phys(tmp_buff->pages[fsz_m]), fsz_r);
                pd->fpga_stat_cnfg->pr_addr_low = LOW_32(page_to_phys(tmp_buff->pages[fsz_m]));
                pd->fpga_stat_cnfg->pr_addr_high = HIGH_32(page_to_phys(tmp_buff->pages[fsz_m]));
                pd->fpga_stat_cnfg->pr_len = fsz_r;
                pd->fpga_stat_cnfg->pr_ctrl = PR_CTRL_START_LAST;

                wmb();
                cmd_sent++;
            }

            k = true;
        }
    }

    if(k)
        return 0;   
    else
        return -1;
}