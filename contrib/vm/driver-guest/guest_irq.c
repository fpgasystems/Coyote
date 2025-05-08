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

#include "guest_irq.h"

/**
 * @brief Guest callback for a page fault on the fpga.
 * This handles an interrupt that is fired by the hypervisor 
 * as a response to a real interrupt happening in hardware.
 * The function reads the faulting address from special hardware
 * registers and uses the get user pages function
 * to install mappings on the hardware.
 * 
 * @param irq 
 * @param dev_id 
 * @return irqreturn_t 
 */
irqreturn_t guest_fpga_tlb_miss_isr(int irq, void *dev_id)
{
    unsigned long flags;
    uint64_t vaddr;
    uint32_t len;
    int32_t cpid;
    struct vfpga *d;
    int ret_val = 0;
    pid_t pid;
    uint64_t tmp;

    dbg_info("(irq=%d) page fault ISR\n", irq);
    BUG_ON(!dev_id);

    d = (struct vfpga *)dev_id;
    BUG_ON(!d);

    // lock
    spin_lock_irqsave(&(d->lock), flags);

    // read page fault from hardware register
    if (d->en_avx) {
        vaddr = d->fpga_cnfg_avx->vaddr_miss;
        tmp = d->fpga_cnfg_avx->len_miss;
        len = LOW_32(tmp);
        cpid = (int32_t)HIGH_32(tmp);
    }
    else {
        vaddr = d->fpga_cnfg->vaddr_miss;
        tmp = d->fpga_cnfg->len_miss;
        len = LOW_32(tmp);
        cpid = (int32_t)HIGH_32(tmp);
    }
    dbg_info("page fault, vaddr %llx, length %x, cpid %d\n", vaddr, len, cpid);

    // get user pages
    pid = d->pid_array[cpid];
    ret_val = guest_get_user_pages(d, vaddr, len, cpid, pid);
    
    if (!ret_val) {
        // restart the engine
        if (d->en_avx)
            d->fpga_cnfg_avx->ctrl[0] = FPGA_CNFG_CTRL_IRQ_RESTART;
        else
            d->fpga_cnfg->ctrl = FPGA_CNFG_CTRL_IRQ_RESTART;
    }
    else {
        dbg_info("pages could not be obtained\n");
    }

    // unlock
    spin_unlock_irqrestore(&(d->lock), flags);

    return IRQ_HANDLED;
}