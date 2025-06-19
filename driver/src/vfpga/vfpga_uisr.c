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
