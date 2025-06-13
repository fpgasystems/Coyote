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
 * @file vfpga_ops.h
 * @brief Standard device operations for the vfpga_dev char device: open, release, ioctl and memory map (mmap)
 */

#ifndef _VFPGA_OPS_H_
#define _VFPGA_OPS_H_

#include "coyote_setup.h"
#include "coyote_defs.h"
#include "vfpga_isr.h"
#include "vfpga_uisr.h"

/// vfpga_dev open char device
int vfpga_dev_open(struct inode *inode, struct file *file);

/// vfpga_dev release (close) char device
int vfpga_dev_release(struct inode *inode, struct file *file);

/// vfpga_dev IOCTL calls
long vfpga_dev_ioctl(struct file *file, unsigned int cmd, unsigned long arg);

/// vfpga_dev memory map; maps user control region, vFPGA config and writeback regions
int vfpga_dev_mmap(struct file *file, struct vm_area_struct *vma);

#endif // _VFPGA_OPS_H_