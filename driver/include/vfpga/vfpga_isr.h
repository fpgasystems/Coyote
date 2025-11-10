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
 * @file vfpga_isr.h
 * @brief vFPGA interrupts (page faults, invalidations, user interrupts etc.)
 */

#ifndef _VFPGA_ISR_H_
#define _VFPGA_ISR_H_

#include "coyote_defs.h"
#include "vfpga_hw.h"
#include "vfpga_gup.h"

#ifdef HMM_KERNEL
#include "fpga_hmm.h"
#endif

/**
 * @brief Top-level vFPGA interrupt routine; registered during set-up in msix_irq_setup(...)
 *
 * Catches interrupts issued by the vFPGA (sent via XDMA and PCIe) and calls the appropriate callback method
 * Interrupts, in the order of importance are:
 *  1. Completed DMA offloads/syncs
 *  2. Completed TLB invalidation
 *  3. Page fault
 *  4. User interrupts (notification)
 *
 * For more details, refer to: Chapter 3.1.3.5 Interrupts in Abstractions for Modern Heterogeneous Systems (2024), Dario Korlija
 *
 * @param irq Interrupt type
 * @param d Generic pointer to a Linux device; internally parsed into a vfpga_dev pointer
 */
irqreturn_t vfpga_isr(int irq, void *d);

/// Handles user interupts (notifications)
void vfpga_notify_handler(struct work_struct *work);

/// Handles vFPGA page faults, by invalidating and updating TLB; migrating data where required
void vfpga_pfault_handler(struct work_struct *work);

#endif // _VFPGA_ISR_H_
