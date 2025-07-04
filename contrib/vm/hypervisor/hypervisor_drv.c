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