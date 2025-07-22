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
 * @file vfpga_uisr.h
 * @brief vFPGA user interrupts (notifications)
 *
 * Methods to register user interrupt (notification) callbacks, as requested by the user
 * In Coyote, user interrupts (notifications) are linked to a Coyote thread, through its ID (ctid)
 * Therefore, there can be multiple interrupt callbacks for one vFPGA, since it's possible to have more than one Coyote thread per vFPGA
 * For more details, see Example 3: Multi-threading and Example 4: User interrupts 
 *
 * To handle interrupts, Coyote uses eventfd, a Linux kernel mechanism for event signalling
 * eventfd can be used to communicate events between the kernel- and the user-space, or between processes
 * In Coyote, an eventfd is created from the user-space and registered by the driver using the method vfpga_register_eventfd
 * Then, when an interrupt from the FPGA is picked up by the driver (see vfpga_isr.c), the driver writes to the appropariate eventfd
 * The user-space software polls on the same eventfd, and, when a change is detected, executes the appropriate callback (see sw/bThread.cpp)
 */

#ifndef _VFPGA_UISR_H_
#define _VFPGA_UISR_H_

#include "coyote_defs.h"

/**
 * @brief Registers an eventfd for a given Coyote thread and vFPGA device
 *
 * @param device vfpga_dev for which the eventfd should be registered
 * @param ctid Coyote thread ID (obtained from user-space)
 * @param eventfd eventfd file descriptor, as created in the user-space (see sw/bThread.cpp)
 * @return whether eventfd was successfully registered
 */
int vfpga_register_eventfd(struct vfpga_dev *device, int ctid, int eventfd);

/**
 * @brief Unregisters an eventfd for a given Coyote thread and vFPGA device
 *
 * @param device vfpga_dev for which the eventfd should be released
 * @param ctid Coyote thread ID of the eventfd which should be released
 */
void vfpga_unregister_eventfd(struct vfpga_dev *device, int ctid);

#endif // _VFPGA_UISR_H_