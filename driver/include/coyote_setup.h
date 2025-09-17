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

/**
 * @file coyote_setup.h
 * @brief Functions for initializing, setting up and freeing Coyote devices (vfpga_dev, reconfig_dev) and utility functions (set up sysfs, reading config etc.)
 */

#ifndef _COYOTE_SETUP_H_
#define _COYOTE_SETUP_H_

#include "coyote_defs.h"
#include "vfpga_ops.h"
#include "reconfig_ops.h"
#include "coyote_sysfs.h"

/**
 * @brief Reads the synthesized shell configuration and populates fields of bus_driver_data
 * The configuration was specifified during the hardware synthesis in CMakeLists.txt
 * The method also prints the configuration to the kernel log; can be queryed with `dmesg`
 */
int read_shell_config(struct bus_driver_data *data);

/// Allocates and initializes metadata structs used for managing card memory, if enabled 
int allocate_card_resources(struct bus_driver_data *data);

/// Releases metadata structs used for managing card memory, if enabled; opposite of allocate_card_resources
void free_card_resources(struct bus_driver_data *data);

/// Initialize general (not used by individual vFPGAs) spin locks used in Coyote; used to protect shared resources and ensure safe access
void init_spin_locks(struct bus_driver_data *data);

/// Initialize sysfs entry for Coyote; for more details see coyote_sysfs.h
int create_sysfs_entry(struct bus_driver_data *data);

/// Removes sysfs entry for Coyote; used oly when the driver is unloaded
void remove_sysfs_entry(struct bus_driver_data *data);

/// Allocates and registers all the char vFPGA devices (one for every region)
int alloc_vfpga_devices(struct bus_driver_data *data, dev_t device);

/// Sets up the previously allocated vFPGA char devices (above); memory mapping registers, initializing work queues, mutexes etc.
int setup_vfpga_devices(struct bus_driver_data *data);

/// Releases resources used by vFPGA char devices; destroys work queues etc., opposite of setup_vfpga_devices
void teardown_vfpga_devices(struct bus_driver_data *data);

/// Frees the allocated vFPGA char devices and unregisters it from the OS; opposite of alloc_vfpga_devices
void free_vfpga_devices(struct bus_driver_data *data);

/// Allocates a char reconfig_device which is used to interact with the static layer for shell reconfiguration
int alloc_reconfig_device(struct bus_driver_data *data, dev_t device);

/// Sets up the previously allocated reconfig char device (above); initializing work queues, mutexes, hash tables etc.
int setup_reconfig_device(struct bus_driver_data *data);

/// Releases resources used by the reconfig device; destroys work queues etc., opposite of setup_reconfig_device
void teardown_reconfig_device(struct bus_driver_data *data);

/// Frees the allocated reconfig char device and unregisters it from the OS; opposite of alloc_reconfig_device
void free_reconfig_device(struct bus_driver_data *data);

#endif  // _COYOTE_SETUP_H_