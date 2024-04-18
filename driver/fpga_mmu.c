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

#include "fpga_mmu.h"

/*
███╗   ███╗███╗   ███╗██╗   ██╗
████╗ ████║████╗ ████║██║   ██║
██╔████╔██║██╔████╔██║██║   ██║
██║╚██╔╝██║██║╚██╔╝██║██║   ██║
██║ ╚═╝ ██║██║ ╚═╝ ██║╚██████╔╝
╚═╝     ╚═╝╚═╝     ╚═╝ ╚═════╝ 
*/




/**
 * @brief ISR
 *
 */
irqreturn_t fpga_isr(int irq, void *dev_id)
{
    struct fpga_dev *d;
    __u16 type;
    unsigned long flags;
    struct fpga_irq_pfault *irq_pf;
    struct fpga_irq_notify *irq_not;

    dbg_info("(irq=%d) ISR entry\n", irq);

    d = (struct fpga_dev *)dev_id;
    BUG_ON(!d);

    // lock
    spin_lock_irqsave(&(d->irq_lock), flags);

    // read irq type
    type = fpga_read_irq_type(d);

    switch (type)
    {
    case IRQ_DMA_OFFL:
        dbg_info("(irq=%d) dma offload completed, vFPGA %d\n", irq, d->id);
        atomic_set(&d->wait_offload, FLAG_SET);
        wake_up_interruptible(&d->waitqueue_offload);
        break;

    case IRQ_DMA_SYNC:
        dbg_info("(irq=%d) dma sync completed, vFPGA %d\n", irq, d->id);
        atomic_set(&d->wait_sync, FLAG_SET);
        wake_up_interruptible(&d->waitqueue_sync);
        break;

    case IRQ_INVLDT: 
        dbg_info("(irq=%d) invalidation completed, vFPGA %d\n", irq, d->id);
        atomic_set(&d->wait_invldt, FLAG_SET);
        wake_up_interruptible(&d->waitqueue_invldt);
        break;

    case IRQ_PFAULT:
        dbg_info("(irq=%d) page fault, vFPGA %d\n", irq, d->id);
        irq_pf = kzalloc(sizeof(struct fpga_irq_pfault), GFP_KERNEL);
        BUG_ON(!irq_pf);

        irq_pf->d = d;
        fpga_read_irq_pfault(d, irq_pf);

        INIT_WORK(&irq_pf->work_pfault, fpga_pfault_handler);

        if(!queue_work(d->wqueue_pfault, &irq_pf->work_pfault)) {
            pr_err("could not enqueue a workqueue, page fault ISR");
        }
        break;

    case IRQ_NOTIFY:
        dbg_info("(irq=%d) notify, vFPGA %d\n", irq, d->id);
        irq_not = kzalloc(sizeof(struct fpga_irq_notify), GFP_KERNEL);
        BUG_ON(!irq_not);

        irq_not->d = d;
        fpga_read_irq_notify(d, irq_not);

        INIT_WORK(&irq_not->work_notify, fpga_notify_handler);

        if(!queue_work(d->wqueue_notify, &irq_not->work_notify)) {
            pr_err("could not enqueue a workqueue, notify ISR");
        }
        break;

    default:
        break;
    }

    // clear irq
    fpga_clear_irq(d);

    // unlock
    spin_unlock_irqrestore(&(d->irq_lock), flags);

    return IRQ_HANDLED;
}

/**
 * @brief Notify function handler
 *
 * @param work - work struct
 */
void fpga_notify_handler(struct work_struct *work)
{
    struct fpga_dev *d;
    struct fpga_irq_notify *irq_not;

    irq_not = container_of(work, struct fpga_irq_notify, work_notify);
    BUG_ON(!irq_not);
    d = irq_not->d;

    // notfiication
    dbg_info("notify vFPGA %d, notval %d, cpid %d\n", d->id, irq_not->notval, irq_not->cpid);

    if (!user_notifier[d->id][irq_not->cpid]) {
        dbg_info("Dropped notify event because there is no recpient\n");
        return;
    }

    eventfd_signal(user_notifier[d->id][irq_not->cpid], irq_not->notval);

    kfree(irq_not);
}

/**
 * @brief Page fault handler takes care of the page fault
 * and then restarts the mmu engine. Called from a workqueue
 *
 * @param work - work struct
 */
void fpga_pfault_handler(struct work_struct *work)
{
    struct fpga_dev *d;
    struct fpga_irq_pfault *irq_pf;
    struct bus_drvdata *pd;
    pid_t hpid;
    int ret_val = 0;

    irq_pf = container_of(work, struct fpga_irq_pfault, work_pfault);
    BUG_ON(!irq_pf);
    d = irq_pf->d;
    pd = d->pd;

    d->n_pfaults++;

    BUG_ON(cyt_arch == CYT_ARCH_ECI);

    // lock
    mutex_lock(&d->mmu_lock);

    // read page fault from device
    hpid = d->pid_array[irq_pf->cpid];
    dbg_info("page fault vFPGA %d, vaddr %llx, length %x, stream %d, cpid %d\n", d->id, irq_pf->vaddr, irq_pf->len, irq_pf->stream, irq_pf->cpid);

#ifdef HMM_KERNEL
    if(en_hmm)
        ret_val = mmu_handler_hmm(d, irq_pf->vaddr, irq_pf->len, irq_pf->cpid, irq_pf->stream, hpid);
    else
#endif    
        ret_val = mmu_handler_gup(d, irq_pf->vaddr, irq_pf->len, irq_pf->cpid, irq_pf->stream, hpid);

    if (ret_val) {
        fpga_drop_irq_pfault(d, irq_pf->wr, irq_pf->cpid);
        pr_err("mmu handler error, vFPGA %d, err %d\n", d->id, ret_val);
        goto err_mmu;
    }

    // restart engine
    fpga_restart_mmu(d, irq_pf->wr, irq_pf->cpid);

    // unlock
    mutex_unlock(&d->mmu_lock);

    dbg_info("page fault vFPGA %d handled\n", d->id);

    kfree(irq_pf);

err_mmu:
    return;
}