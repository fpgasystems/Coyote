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
 * @file vfpga_ops.h
 * @brief Standard device operations for the vfpga_dev char device: open, release, ioctl and memory map (mmap)
 */

#ifndef _VFPGA_OPS_H_
#define _VFPGA_OPS_H_

#include "coyote_setup.h"
#include "coyote_defs.h"
#include "vfpga_isr.h"
#include "vfpga_uisr.h"

/// vfpga_dev open char device
int vfpga_dev_open(struct inode *inode, struct file *file);

/// vfpga_dev release (close) char device
int vfpga_dev_release(struct inode *inode, struct file *file);

/// vfpga_dev IOCTL calls
long vfpga_dev_ioctl(struct file *file, unsigned int cmd, unsigned long arg);

/// vfpga_dev memory map; maps user control region, vFPGA config and writeback regions
int vfpga_dev_mmap(struct file *file, struct vm_area_struct *vma);

#endif // _VFPGA_OPS_H_