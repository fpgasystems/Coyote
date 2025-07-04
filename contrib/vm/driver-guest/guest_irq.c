/**
 * Copyright (c) 2025,  Systems Group, ETH Zurich
 * All rights reserved.
 *
 * This file is part of the Coyote VM driver for Linux.
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
        vaddr = d->cnfg_regs->vaddr_miss;
        tmp = d->cnfg_regs->len_miss;
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
            d->cnfg_regs->ctrl = FPGA_CNFG_CTRL_IRQ_RESTART;
    }
    else {
        dbg_info("pages could not be obtained\n");
    }

    // unlock
    spin_unlock_irqrestore(&(d->lock), flags);

    return IRQ_HANDLED;
}