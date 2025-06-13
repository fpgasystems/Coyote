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