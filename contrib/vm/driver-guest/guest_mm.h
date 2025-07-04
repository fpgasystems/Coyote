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

#ifndef __GUEST_MM_H__
#define __GUEST_MM_H__

#include "guest_dev.h"

int guest_put_all_user_pages(struct vfpga *d, int dirtied);
int guest_get_user_pages(struct vfpga *d, uint64_t start, size_t count, int32_t cpid, pid_t pid);
int guest_put_user_pages(struct vfpga *d, uint64_t vaddr, int32_t cpid, int dirtied);

#endif