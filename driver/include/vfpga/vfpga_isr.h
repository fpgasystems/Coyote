/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
  * All rights reserved.
  *
  * Redistribution and use in source and binary forms, with or without modification,
  * are permitted provided that the following conditions are met:
  *
  * 1. Redistributions of source code must retain the above copyright notice,
  * this list of conditions and the following disclaimer.
  * 2. Redistributions in binary form must reproduce the above copyright notice,
  * this list of conditions and the following disclaimer in the documentation
  * and/or other materials provided with the distribution.
  * 3. Neither the name of the copyright holder nor the names of its contributors
  * may be used to endorse or promote products derived from this software
  * without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
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
