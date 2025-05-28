/**
  * Copyright (c) 2023, Systems Group, ETH Zurich
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
 
#include "hypervisor_drv.h"

/**
 * @brief Initalizes the hypervisor and creates
 * the mdev types inside the device tree.
 * 
 * @param bd bus_drvdata, initiliazed prior to this call
 * @return int 0 if succeeded
 */
int hypervisor_init(struct bus_drvdata *bd) {
    struct mdev_parent_ops *ops;
    int ret_val;
    int i, j;

    BUG_ON(!bd);

    for (i = 0; i < bd->n_fpga_reg; i++) {
        
        // Get ops for the device
        ops = hypervisor_get_ops(&bd->fpga_dev[i]);
        if (!ops) {
            pr_err ("Failed to get mdev-vfio ops\n");
            goto rollback;
        }

        // Allocate vcid chunks
        bd->fpga_dev[i].vcid_chunks = vzalloc(sizeof(struct chunk) * MAX_VMS);
        BUG_ON(!bd->fpga_dev->vcid_chunks);

        for (j = 1; j < MAX_VMS; j++) 
        {
            bd->fpga_dev[i].vcid_chunks[j].id = j;
            bd->fpga_dev[i].vcid_chunks[j-1].next = &bd->fpga_dev->vcid_chunks[j];
        }

        bd->fpga_dev[i].vcid_alloc = bd->fpga_dev->vcid_chunks;
        bd->fpga_dev[i].num_free_vcid_chunks = MAX_VMS;

        spin_lock_init(&bd->fpga_dev[i].vcid_lock);

        // Register with mdev
        ret_val = mdev_register_device(bd->fpga_dev[i].dev, ops);
        if (ret_val) {
            pr_err ("Error while registering mdev\n");
            goto rollback;
        }

        dbg_info("Registered mdev device %d\n", i);
    }

    dbg_info("Hypervisor initialized\n");

    return 0;

rollback:
    for (i = i - 1; i >= 0; i--) {
        mdev_unregister_device(bd->fpga_dev[i].dev);
    }
    return ret_val;
}

/**
 * @brief tear down code for the hypervisor. Unregisters the mdev
 * class and therefore removes the types for the fpgas. 
 * Might block if there are still mediated devices
 * opened and used by vms. 
 * 
 * @param bd bus_drvdata, initiliazed prior to this call
 * @return int 0 if succeeded
 */
void hypervisor_exit(struct bus_drvdata *bd) {
    int i;

    for (i = 0; i < bd->n_fpga_reg; i++)
    {
        mdev_unregister_device(bd->fpga_dev[i].dev);
    }
    
    dbg_info("Unregistered all mdev devices");
    return;
}

MODULE_LICENSE("GPL");