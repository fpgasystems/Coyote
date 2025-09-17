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
 * @file reconfig_isr.h
 * @brief Reconfiguration interrupt management; picking up interrupts when reconfiguration is complete
 */

#ifndef _RECONFIG_ISR_H_
#define _RECONFIG_ISR_H_

#include "coyote_defs.h"

/**
 * @brief Handles incoming interrupts related to reconfiguration
 *
 * A reconfiguration interrupt issued by the FPGA corresponds to reconfiguration being completed successfuly 
 * Once picked up by this function, it sets the wait_rcnfg variable to SET, which is polled on during IOCTL_RECONFIGURE_(SHELL|APP)
 * Finally, it clears the memory-mapped interrupt register in the FPGA
 *
 * @param irq interrupt value
 * @param dev pointer to the reconfiguration device being reconfigured
 * @return IRQ_HANDLED, indicating interrupt has been acknowledged
 */
irqreturn_t reconfig_isr(int irq, void *dev);

#endif // _RECONFIG_ISR_H_