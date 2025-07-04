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

#ifndef __GUEST_FOPS_H__
#define __GUEST_FOPS_H__

#include "guest_dev.h"
#include "guest_mm.h"

int guest_open(struct inode* inode, struct file *f);
int guest_release(struct inode *inode, struct file *f);
long guest_ioctl(struct file *f, unsigned int cmd, unsigned long arg);
int guest_mmap(struct file *f, struct vm_area_struct *vma);

#endif