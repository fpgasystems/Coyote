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

#include "eci_dev.h"

/*
 ____            _     _
|  _ \ ___  __ _(_)___| |_ ___ _ __
| |_) / _ \/ _` | / __| __/ _ \ '__|
|  _ <  __/ (_| | \__ \ ||  __/ |
|_| \_\___|\__, |_|___/\__\___|_|
           |___/
*/

static struct bus_drvdata *pd;

/**
 * @brief ECI device init
 * 
 */
int eci_init(void) 
{
    int ret_val = 0;
    
    // dynamic major
    dev_t dev = MKDEV(fpga_major, 0);

    // allocate mem. for device instance
    pd = kzalloc(sizeof(struct bus_drvdata), GFP_KERNEL);
    if(!pd) {
        pr_err("device memory region not obtained\n");
        ret_val = -ENOMEM;
        goto err_alloc;
    }

    // get static config
    pd->io_phys_addr = IO_PHYS_ADDR;
    pd->fpga_stat_cnfg = ioremap(pd->io_phys_addr + FPGA_STAT_CNFG_OFFS, FPGA_STAT_CNFG_SIZE);
    read_static_config(pd);
    
    // allocate card mem resources
    ret_val = alloc_card_resources(pd);
    if (ret_val) {
        pr_err("card resources could not be allocated\n");
        goto err_card_alloc; // ERR_CARD_ALLOC
    }

    // initialize spin locks
    init_spin_locks(pd);

    // create FPGA devices and register major
    ret_val = init_char_devices(pd, dev);
    if (ret_val) {
        goto err_create_fpga_dev; // ERR_CREATE_FPGA_DEV
    }

    // initialize vFPGAs
    ret_val = init_fpga_devices(pd);
    if (ret_val) {
        goto err_init_fpga_dev;
    }

    // Init hash
    hash_init(pr_buff_map);

    if(ret_val == 0)
        goto end;

err_init_fpga_dev:
    kfree(pd->fpga_dev);
    class_destroy(fpga_class);
err_create_fpga_dev:
    vfree(pd->schunks);
    vfree(pd->lchunks);
err_card_alloc:
err_alloc:
end:
    pr_info("probe returning %d\n", ret_val);
    return ret_val;
}

void eci_exit(void)
{   
    // delete vFPGAs
    free_fpga_devices(pd);
    
    // delete char devices
    free_char_devices(pd);

    // deallocate card resources
    free_card_resources(pd);

    // free device data
    kfree(pd);
    pr_info("device memory freed\n");

    pr_info("removal completed\n");
}

