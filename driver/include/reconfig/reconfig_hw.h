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
 * @file reconfig_hw.h
 * @brief Low-level hardware functionality to trigger run-time reconfiguration of the FPGA
 */

#ifndef _RECONFIG_HW_H_
#define _RECONFIG_HW_H_
  
#include "coyote_defs.h"
#include "reconfig_mem.h"

/**
 * @brief Triggers the reconfiguration process
 * 
 * @param device reconfig_device to be reconfigured (corresponding to the actual physical FPGA we want to reconfigure)
 * @param vaddr bitstream buffer virtual address; obtained from alloc_buffer and mmap
 * @param pid host process ID
 * @param crid configuration ID 
 * @return reconfiguration started successfuly or not
 */
int reconfigure_start(struct reconfig_dev *device, uint64_t vaddr, uint64_t len, pid_t pid, uint32_t crid);

#endif // _RECONFIG_HW_H_