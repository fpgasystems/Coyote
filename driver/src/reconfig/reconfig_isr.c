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
    device->bd_data->stat_cnfg->reconfig_ctrl = RECONFIG_CTRL_IRQ_CLR_PENDING;
    spin_unlock_irqrestore(&(device->irq_lock), flags);

    return IRQ_HANDLED;
}
