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

#include "fpga_uisr.h"

/*
██╗   ██╗██╗███████╗██████╗ 
██║   ██║██║██╔════╝██╔══██╗
██║   ██║██║███████╗██████╔╝
██║   ██║██║╚════██║██╔══██╗
╚██████╔╝██║███████║██║  ██║
 ╚═════╝ ╚═╝╚══════╝╚═╝  ╚═╝
*/          

struct eventfd_ctx *user_notifier[MAX_N_REGIONS][N_CPID_MAX];

int fpga_register_eventfd(struct fpga_dev *d, int cpid, int eventfd)
{
    int ret_val = 0;
    BUG_ON(!d);
    user_notifier[d->id][cpid] = eventfd_ctx_fdget(eventfd);

    if (IS_ERR_OR_NULL(user_notifier[d->id][cpid]))
    {
        ret_val = PTR_ERR(user_notifier[d->id][cpid]);
        user_notifier[d->id][cpid] = NULL;
    }

    return ret_val;
}

void fpga_unregister_eventfd(struct fpga_dev *d, int cpid)
{
    if (user_notifier[d->id][cpid])
        eventfd_ctx_put(user_notifier[d->id][cpid]);
    
    user_notifier[d->id][cpid] = NULL;
}
