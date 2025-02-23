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

#ifndef __RECONFIG_MEM_H__
#define __RECONFIG_MEM_H__

#include "coyote_dev.h"

/**
 * @brief Allocates host-side, kernel-space reconfiguration buffers
 *
 * In order for partial bitstreams to be loaded onto the FPGA,
 * they need to be written to the ICAP from the driver via PCIe and the XDMA core
 * This function allocates a buffer of sufficient size to hold a partial bitstream for reconfiguration
 * Following this function, the buffer is mapped to the user-space using an mmap call (reconfig_ops.h)
 * Finally, the partial bitstream can then be loaded into this buffer and used to trigger reconfiguration
 *
 * @param device reconfig_device for which the bitstream buffer should be allocated
 * @param n_pages number of hugepages required to hold the bitsream; calculated in user-space
 * @param pid host process ID
 * @param crid configuration ID (uniquely identifies the shell bitstream to be loaded)
 * @return alloc_success whether target memory allocation completed successfully
 */
int alloc_reconfig_buffer(struct reconfig_dev *device, unsigned long n_pages, pid_t pid, uint32_t crid);

/**
 * @brief De-allocates host-side, kernel-space reconfiguration buffer
 *
 * Performs the opposite of the function above; to be used when reconfiguration is complete
 *
 * @param device reconfig_device for which the bitstream buffer should be allocated
 * @param virtual_address buffer virtual address
 * @param pid host process ID
 * @param crid configuration ID 
 * @return always 0; check reconfig_mem.c for explanation
 */
int free_reconfig_buffer(struct reconfig_dev *device, uint64_t virtual_address, pid_t pid, uint32_t crid);

#endif