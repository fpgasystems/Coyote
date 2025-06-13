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
███████╗ ██████╗██╗
██╔════╝██╔════╝██║
█████╗  ██║     ██║
██╔══╝  ██║     ██║
███████╗╚██████╗██║
╚══════╝ ╚═════╝╚═╝
*/

static struct bus_driver_data *bd_data;

/**
 * @brief Shell init
 * 
 */
int shell_eci_init(struct bus_driver_data *d)
{
    int ret_val = 0;

    // dynamic major
    dev_t dev_fpga = MKDEV(d->vfpga_major, 0);

    pr_info("initializing shell ...\n");

    // get shell config
    ret_val = read_shell_config(d);
    if(ret_val) {
        pr_err("cannot read static config\n");
        goto err_read_shell_cnfg;
    }

    // Sysfs entry
    ret_val = create_sysfs_entry(d);
    if (ret_val) {
        pr_err("cannot create a sysfs entry\n");
        goto err_sysfs;
    }

    // allocate card mem resources
    ret_val = allocate_card_resources(d);
    if (ret_val) {
        pr_err("card resources could not be allocated\n");
        goto err_card_alloc; // ERR_CARD_ALLOC
    }

    // initialize spin locks
    init_spin_locks(d);

    // create FPGA devices and register major
    ret_val = alloc_vfpga_devices(d, dev_fpga);
    if (ret_val) {
        goto err_create_fpga_dev; // ERR_CREATE_FPGA_DEV
    }

    // initialize vFPGAs
    ret_val = setup_vfpga_devices(d);
    if (ret_val) {
        goto err_init_fpga_dev;
    }

    if (ret_val == 0)
        goto end;

err_init_fpga_dev:
    free_vfpga_devices(d);
err_create_fpga_dev:
    vfree(d->schunks);
    vfree(d->lchunks);
err_card_alloc:
    remove_sysfs_entry(d);
err_sysfs:
err_read_shell_cnfg:
end:
    pr_info("probe returning %d\n", ret_val);
    return ret_val;
}

/**
 * @brief Shell remove
 * 
 */
void shell_eci_remove(struct bus_driver_data *d)
{
    pr_info("removing shell ...\n");

    // delete vFPGAs
    teardown_vfpga_devices(d);
    
    // delete char devices
    free_vfpga_devices(d);
    
    // deallocate card resources
    free_card_resources(d);

    // remove sysfs
    remove_sysfs_entry(d);

    pr_info("shell removed\n");
}

/**
 * @brief ECI device init
 * 
 */
int eci_init(void) 
{
    int ret_val = 0;
    dev_t dev_fpga;
    dev_t dev_pr;

    // allocate mem. for device instance
    bd_data = kzalloc(sizeof(struct bus_driver_data), GFP_KERNEL);
    if(!bd_data) {
        pr_err("device memory region not obtained\n");
        ret_val = -ENOMEM;
        goto err_alloc;
    }

    // dynamic major
    bd_data->vfpga_major = VFPGA_DEV_MAJOR;
    bd_data->reconfig_major = RECONFIG_DEV_MAJOR;

    dev_fpga = MKDEV(bd_data->vfpga_major, 0);
    dev_pr = MKDEV(bd_data->reconfig_major, 0);

    // get static config
    bd_data->io_phys_addr = IO_PHYS_ADDR;
    bd_data->stat_cnfg = ioremap(bd_data->io_phys_addr + FPGA_STAT_CNFG_OFFS, FPGA_STAT_CNFG_SIZE);
    bd_data->shell_cnfg = ioremap(bd_data->io_phys_addr + FPGA_SHELL_CNFG_OFFS, FPGA_SHELL_CNFG_SIZE);
    ret_val = read_shell_config(bd_data);
    if(ret_val) {
        pr_err("cannot read shell config\n");
        goto err_read_shell_cnfg;
    }

    // Sysfs entry
    ret_val = create_sysfs_entry(bd_data);
    if (ret_val) {
        pr_err("cannot create a sysfs entry\n");
        goto err_sysfs;
    }
    
    // allocate card mem resources
    ret_val = allocate_card_resources(bd_data);
    if (ret_val) {
        pr_err("card resources could not be allocated\n");
        goto err_card_alloc; // ERR_CARD_ALLOC
    }

    // initialize spin locks
    init_spin_locks(bd_data);

    // create FPGA devices and register major
    ret_val = alloc_vfpga_devices(bd_data, dev_fpga);
    if (ret_val) {
        goto err_create_fpga_dev; // ERR_CREATE_FPGA_DEV
    }

    // initialize vFPGAs
    ret_val = setup_vfpga_devices(bd_data);
    if (ret_val) {
        goto err_init_fpga_dev;
    }

    if(bd_data->en_pr) {
        // create PR device and register major
        ret_val = alloc_reconfig_device(bd_data, dev_pr);
        if (ret_val) {
            goto err_create_reconfig_dev; // ERR_CREATE_FPGA_DEV
        }

        // initialize PR
        ret_val = setup_reconfig_device(bd_data);
        if (ret_val) {
            goto err_init_reconfig_dev;
        }
    }

    if(ret_val == 0)
        goto end;


err_init_reconfig_dev:
    free_reconfig_device(bd_data);
err_create_reconfig_dev:
    teardown_vfpga_devices(bd_data);
err_init_fpga_dev:
    free_vfpga_devices(bd_data);
err_create_fpga_dev:
    vfree(bd_data->schunks);
    vfree(bd_data->lchunks);
err_card_alloc:
    remove_sysfs_entry(bd_data);
err_sysfs:
err_read_shell_cnfg:
err_alloc:
end:
    pr_info("probe returning %d\n", ret_val);
    return ret_val;
}

void eci_exit(void)
{   
    if(bd_data->en_pr) {
        // delete PR
        teardown_reconfig_device(bd_data);

        // delete char device
        free_reconfig_device(bd_data);
    }

    // delete vFPGAs
    teardown_vfpga_devices(bd_data);
    
    // delete char devices
    free_vfpga_devices(bd_data);

    // deallocate card resources
    free_card_resources(bd_data);

    // remove sysfs
    remove_sysfs_entry(bd_data);

    // free device data
    kfree(bd_data);
    pr_info("device memory freed\n");

    pr_info("removal completed\n");
}

