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

#ifndef __HYPERVISOR_INTERRUPTS_H__
#define __HYPERVISOR_INTERRUPTS_H__

#include "../coyote_dev.h"

/* MSIX header set up */
void set_up_msix_header(struct pci_config_space *cfg, uint8_t offset, uint16_t regs);
size_t write_to_msix_header(void *cfg, uint8_t offset, uint32_t val, uint8_t count);

/* MSIX management */
void msix_unset_all_interrupts(struct m_fpga_dev *d);
int handle_set_irq_msix(struct m_fpga_dev *d, struct vfio_irq_set *irq_set);
uint64_t fire_interrupt(struct msix_interrupt *inter);
irqreturn_t hypervisor_tlb_miss_isr(int irq, void *dev_id);

#endif