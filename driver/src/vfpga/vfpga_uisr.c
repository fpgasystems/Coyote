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

#include "vfpga_uisr.h"

/// List of eventfd contexts for all possible vFPGAs and Coyote threads
struct eventfd_ctx *user_notifier[MAX_N_REGIONS][N_CTID_MAX];

/// Every time a user interrupt is issued, the mutex is locked, avoiding race conditions until the interrupt has been handled
struct mutex user_notifier_lock[MAX_N_REGIONS][N_CTID_MAX];

/// List of values that have been set for a interrupt for a vFPGA and Coyote thread.
/// Values are set in vfpga_isr and read in vfpga_ops via ioctl.
int32_t interrupt_value[MAX_N_REGIONS][N_CTID_MAX];

int vfpga_register_eventfd(struct vfpga_dev *device, int ctid, int eventfd) {
    int ret_val = 0;
    BUG_ON(!device);
    
    mutex_init(&user_notifier_lock[device->id][ctid]);

    // Retrieve the kernel context from the eventfd file descriptor
    user_notifier[device->id][ctid] = eventfd_ctx_fdget(eventfd);
    if (IS_ERR_OR_NULL(user_notifier[device->id][ctid])) {
        ret_val = PTR_ERR(user_notifier[device->id][ctid]);
        user_notifier[device->id][ctid] = NULL;
        pr_warn("Could not retrieve eventfd kernel context, ret_val %d", ret_val);
    }

    return ret_val;
}

void vfpga_unregister_eventfd(struct vfpga_dev *device, int ctid) {
    // Release the kernel context and set the list entry to a nullptr
    if (user_notifier[device->id][ctid]) {
        eventfd_ctx_put(user_notifier[device->id][ctid]);
    }
    user_notifier[device->id][ctid] = NULL;
}
