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

#include "guest_drv.h"

struct class *guest_class;

//
// Device driver struct
//

static struct pci_device_id ids[] = {
    { PCI_DEVICE(0x0102, 0x0304) },
    { 0 }
};
MODULE_DEVICE_TABLE(pci, ids);

static struct pci_driver driver = {
    .name = COYOTE_DRIVER_NAME,
    .probe = guest_probe,
    .remove = guest_remove,
    .id_table = ids
};

/**
 * @brief Sets the permissions for the device file. Harcoded 
 * to rw for all users
 * 
 * @param dev 
 * @param env 
 * @return int 
 */
static int guest_uevent(struct device *dev, struct kobj_uevent_env *env)
{
    add_uevent_var(env, "DEVMODE=%#o", 0666);

    return 0;
}

//
// Module enty points
//

/**
 * @brief Called on load of the module and sets up a driver that 
 * can handle the emulated pci device
 * 
 * @return int 
 */
static int __init guest_init()
{
    int ret_val;

    ret_val = 0;

    // Create class
    #if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 5, 0)
        guest_class = class_create("coyote-guest");
    #else
        guest_class = class_create(THIS_MODULE, "coyote-guest");
    #endif
        guest_class->dev_uevent = guest_uevent;

    if (IS_ERR_OR_NULL(guest_class))
    {
        pr_err("Failed to create pci class\n");
        return -1;
    }

    // Register driver
    ret_val = pci_register_driver(&driver);
    if (ret_val)
    {
        pr_err("Failed to register driver\n");
    }

    dbg_info("init coyote guest driver");

    return ret_val;

}

/**
 * @brief clean up of management structures
 * and removes all sysfs entries. Deregisters the driver
 * with the kernel.
 * 
 */
static void __exit guest_exit()
{
    int ret_val;

    ret_val = 0;

    pci_unregister_driver(&driver);
    class_destroy(guest_class);

    dbg_info("exit coyote guest driver");
}

//
// Registering module
//

module_init(guest_init);
module_exit(guest_exit);
MODULE_AUTHOR(GUEST_MODULE_AUTHOR);
MODULE_LICENSE(GUEST_MODULE_LICENSE);
MODULE_DESCRIPTION(GUEST_MODULE_DESCRIPTION);