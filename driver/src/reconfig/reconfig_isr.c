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

#include "reconfig_isr.h"

irqreturn_t reconfig_isr(int irq, void *dev) {
    dbg_info("(irq=%d) ISR entry\n", irq);
    struct reconfig_dev *device = (struct reconfig_dev *) dev;
    BUG_ON(!device);

    // Lock, preventing multiple simultaneous interrupts
    unsigned long flags;
    spin_lock_irqsave(&(device->irq_lock), flags);
    
    // Mark reconfiguration as completed
    // The FLAG_SET is picked up by IOCTL_RECONFIGURE_(SHELL|APP) in reconfig_ops.c
    dbg_info("(irq=%d) reconfig completed\n", irq);
    atomic_set(&device->wait_rcnfg, FLAG_SET);
    wake_up_interruptible(&device->waitqueue_rcnfg);

    // Clear IRQ by writing to memory-mapped register and unlock
    device->pd->fpga_stat_cnfg->reconfig_ctrl = RECONFIG_CTRL_IRQ_CLR_PENDING;
    spin_unlock_irqrestore(&(device->irq_lock), flags);

    return IRQ_HANDLED;
}
