/**
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
 * @file reconfig_mem.h
 * @brief Memory management for reconfiguration: allocating and releasing memory to hold partial bitstreams
 */

#ifndef _RECONFIG_MEM_H_
#define _RECONFIG_MEM_H_

#include "coyote_defs.h"

/**
 * @brief Allocates host-side, kernel-space reconfiguration buffers
 *
 * In order for partial bitstreams to be loaded onto the FPGA,
 * they need to be written to the ICAP from the driver via PCIe and the XDMA core
 * This function allocates a buffer of sufficient size to hold a partial bitstream for reconfiguration
 * Following this function, the buffer is mapped to the user-space using an mmap call (reconfig_ops.h)
 * Finally, the partial bitstream can then be loaded into this buffer and used to trigger reconfiguration
 *
 * @param device reconfig_device for which the bitstream buffer should be allocated
 * @param n_pages number of hugepages required to hold the bitsream; calculated in user-space
 * @param pid host process ID
 * @param crid configuration ID (uniquely identifies the shell bitstream to be loaded)
 * @return whether target memory allocation completed successfully
 */
int alloc_reconfig_buffer(struct reconfig_dev *device, unsigned long n_pages, pid_t pid, uint32_t crid);

/**
 * @brief De-allocates host-side, kernel-space reconfiguration buffer
 *
 * Performs the opposite of the function above; to be used when reconfiguration is complete
 *
 * @param device reconfig_device for which the bitstream buffer should be allocated
 * @param vaddr buffer virtual address
 * @param pid host process ID
 * @param crid configuration ID 
 * @return always 0; check reconfig_mem.c for explanation
 */
int free_reconfig_buffer(struct reconfig_dev *device, uint64_t vaddr, pid_t pid, uint32_t crid);

#endif // _RECONFIG_MEM_H_