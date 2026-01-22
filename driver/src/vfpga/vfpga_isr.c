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

#include "vfpga_isr.h"

irqreturn_t vfpga_isr(int irq, void *d) {
    dbg_info("(irq=%d) ISR entry\n", irq);
    struct vfpga_dev *device = (struct vfpga_dev *) d;
    BUG_ON(!device);

    // Lock, until the interrupt has been processed, preventing multiple interrupts being processed simultaneously
    // Note, some interrupts (page faults, notifications) are handled asynchronously, so the lock is unlocked before the work is fully complete
    unsigned long flags;
    spin_lock_irqsave(&(device->irq_lock), flags);

    // Parse interrupt type and handle according
    __u16 type = read_irq_type(device);
    switch (type) {
        case IRQ_DMA_OFFL:
            // vFPGA completed DMA off-load, set the correct flag (which is being polled on in the memory handler (HMM/GUP))
            dbg_info("(irq=%d) DMA offload completed, vFPGA %d\n", irq, device->id);
            atomic_set(&device->wait_offload, FLAG_SET);
            wake_up_interruptible(&device->waitqueue_offload);
            break;

        case IRQ_DMA_SYNC:
            // vFPGA completed DMA sync, set the correct flag (which is being polled on in the memory handler (HMM/GUP))
            dbg_info("(irq=%d) DMA sync completed, vFPGA %d\n", irq, device->id);
            atomic_set(&device->wait_sync, FLAG_SET);
            wake_up_interruptible(&device->waitqueue_sync);
            break;

        case IRQ_INVLDT: 
            // vFPGA completed invalidation, set the correct flag (which is being polled on in the memory handler (HMM/GUP))
            dbg_info("(irq=%d) invalidation completed, vFPGA %d\n", irq, device->id);
            atomic_set(&device->wait_invldt, FLAG_SET);
            wake_up_interruptible(&device->waitqueue_invldt);
            break;

        case IRQ_PFAULT:
            // vFPGA issued page fault; issue asynchronous work via vfpga_pfault_handler to handle the page fault
            dbg_info("(irq=%d) page fault, vFPGA %d\n", irq, device->id);
            struct vfpga_irq_pfault *irq_pf = kzalloc(sizeof(struct vfpga_irq_pfault), GFP_ATOMIC);
            BUG_ON(!irq_pf);

            irq_pf->device = device;
            read_irq_pfault(device, irq_pf);

            INIT_WORK(&irq_pf->work_pfault, vfpga_pfault_handler);

            if(!queue_work(device->wqueue_pfault, &irq_pf->work_pfault)) {
                pr_err("could not enqueue a workqueue, page fault ISR\n");
                kfree(irq_pf);
            }
            break;

        case IRQ_NOTIFY:
            // vFPGA issued a user interrupt (notification); issue asynchronous work via vfpga_notify_handler to handle the user interrupt
            dbg_info("(irq=%d) notify, vFPGA %d\n", irq, device->id);
            struct vfpga_irq_notify *irq_not = kzalloc(sizeof(struct vfpga_irq_notify), GFP_ATOMIC);
            BUG_ON(!irq_not);

            irq_not->device = device;
            read_irq_notify(device, irq_not);

            INIT_WORK(&irq_not->work_notify, vfpga_notify_handler);

            if(!queue_work(device->wqueue_notify, &irq_not->work_notify)) {
                pr_err("could not enqueue a workqueue, notify ISR\n");
                kfree(irq_not);
            }
            break;

        default:
            dbg_info("(irq=%d) unknown ISR entry, dropping...\n", irq);
            break;
    }

    // Clear IRQ and unlock
    clear_irq(device);
    spin_unlock_irqrestore(&(device->irq_lock), flags);
    return IRQ_HANDLED;
}

void vfpga_notify_handler(struct work_struct *work) {   
    // Parse the IRQ and its corresponding vFPGA device; check non-null
    struct vfpga_irq_notify *irq_not = container_of(work, struct vfpga_irq_notify, work_notify);
    BUG_ON(!irq_not);
    struct vfpga_dev *device = irq_not->device;
    BUG_ON(!device);
    
    // Mutex, preventing multiple simultaneous user interrupts (notifications)
    // Typically, the hardware can issue interrupts faster than the software can process them; therefore a mutex (to prevent some interrupts being dropped)
    // In case the notification cannot be parsed, the mutex is unlocked immediately; otherwise it's unlocked form the user-space via IOCTL_SET_NOTIFICATION_PROCESSED
    mutex_lock(&user_notifier_lock[device->id][irq_not->ctid]);
    dbg_info("notify vFPGA %d, notification value %d, ctid %d\n", device->id, irq_not->notification_value, irq_not->ctid);

    // Check an eventfd exists for this vFPGA and Coyote thread (must have been registered using vfpga_register_eventfd(...))
    if (!user_notifier[device->id][irq_not->ctid]) {
        pr_warn("dropped notify event because there is no recpient\n");
        mutex_unlock(&user_notifier_lock[device->id][irq_not->ctid]);
        kfree(irq_not);
        return;
    }

    // Set the interrupt value for the vFPGA.
    // This value is read from the cthread via ioctl. See the implementation in vfpga_ops.c.
    // Note: In older versions of coyote, this value was directly passed via the eventfd
    // below. However, the eventfd_signal in the linux kernel changed recently. While we could pass
    // a value before (see code path for kernel version < 6.8.0), we can now only increase
    // the eventfd counter by 1. This removes the possibility of passing the interrupt value
    // directly via the event. Instead, we now only use the event to notify the user-space
    // process.
    interrupt_value[device->id][irq_not->ctid] = irq_not->notification_value;

    // Write the notification value to the eventfd; the value is polled on in the user-space (see bThread.cpp)
    
    #if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 8, 0)
        // In recent kernel versions, the function signature of eventfd_signal changed.
        // The function is now a void and automatically increments the eventfd
        // counter by 1 instead of by a provided value.
        eventfd_signal(user_notifier[device->id][irq_not->ctid]);
        int ret_val = 1;
    #else
        // Note, the return value is equal to the value written.
        // For polling in user-space to work, this value must be non-zero;
        int ret_val = eventfd_signal(user_notifier[device->id][irq_not->ctid], 1);
    #endif

    if (ret_val != 1) {
        pr_warn("could not signal eventfd\n");
        mutex_unlock(&user_notifier_lock[device->id][irq_not->ctid]);
    }

    kfree(irq_not);
}

void vfpga_pfault_handler(struct work_struct *work) {
    // Parse the IRQ and its corresponding vFPGA device; check non-null
    struct vfpga_irq_pfault *irq_pf = container_of(work, struct vfpga_irq_pfault, work_pfault);
    BUG_ON(!irq_pf);
    struct vfpga_dev *device = irq_pf->device;
    BUG_ON(!device);

    mutex_lock(&device->mmu_lock);
    pid_t hpid = device->pid_array[irq_pf->ctid];
    dbg_info("page fault vFPGA %d, virtual address %llx, length %d, stream %d, ctid %d, hpid %d\n", 
        device->id, irq_pf->vaddr, irq_pf->len, irq_pf->stream, irq_pf->ctid, hpid
    );

    int ret_val = -1;
    #ifdef HMM_KERNEL
        // User enabled unified memory (heteregenous memory management)
        if(en_hmm)
            ret_val = mmu_handler_hmm(device, irq_pf->vaddr, irq_pf->len, irq_pf->ctid, irq_pf->stream, hpid);
        else
    #else
        // Alternative memory management, via the get_user_pages mechanism (default)
        ret_val = mmu_handler_gup(device, irq_pf->vaddr, irq_pf->len, irq_pf->ctid, irq_pf->stream, hpid);
    #endif

    if (ret_val && ret_val != BUFF_NEEDS_EXP_SYNC_RET_CODE) {
        drop_irq_pfault(device, irq_pf->wr, irq_pf->ctid);
        pr_err("MMU handler error, vFPGA %d, error %d\n", device->id, ret_val);
        goto err_mmu;
    }

    // Restart MMU and unlock mutex
    restart_mmu(device, irq_pf->wr, irq_pf->ctid);
    mutex_unlock(&device->mmu_lock);
    dbg_info("page fault vFPGA %d handled\n", device->id);
    kfree(irq_pf);
    return;

err_mmu:
    mutex_unlock(&device->mmu_lock);
    kfree(irq_pf);
    return;
}