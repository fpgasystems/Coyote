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

#ifndef __HYPERVISOR_MMU_H__
#define __HYPERVISOR_MMU_H__

#include "../coyote_dev.h"
#include "../fpga_mmu.h"
#include "hypervisor.h"

int hypervisor_tlb_get_user_pages(struct m_fpga_dev *d, struct hypervisor_map_notifier *notifier);
int hypervisor_tlb_put_user_pages(struct m_fpga_dev *md, struct hypervisor_map_notifier *notifier);
int hypervisor_tlb_put_user_pages_all(struct m_fpga_dev *md, int dirtied);

#endif