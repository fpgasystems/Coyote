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
 * @file coyote_sysfs.h
 * @brief Coyote sysfs module
 *
 * sysfs is a virtual filesystem in Linux that exposes kernel objects and their attributes to the user-space
 * It can be used for reading and writing various attributes of devices in the kernel-space
 * The following methods retrieve or set attributes from memory-mapped FPGA registers
 * The attributes can also be read and set from a standard Linux terminal, e.g., cat /sys/kernel/coyote_sysfs_0/<attribute>
 *
 * In general, the methods in this file follow similar steps:
 *  1. Parse a generic kernel object (kobj) into a Coyote-specific variable of type bus_driver_data
 *  2. Ensure the parsed object is non-null, using BUG_ON(...)
 *  3. Retrieve or set the target attribute
 */

#ifndef _COYOTE_SYSFS_H_
#define _COYOTE_SYSFS_H_

#include "coyote_defs.h"

/// Get FPGA IP address
ssize_t cyt_attr_ip_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf);

/// Set FPGA IP address
ssize_t cyt_attr_ip_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count);

/// Get FPGA MAC address
ssize_t cyt_attr_mac_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf);

/// Set FPGA MAC address
ssize_t cyt_attr_mac_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count);

/// Get PR end of start-up (EOS) time
ssize_t cyt_attr_eost_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf);

/// Set PR end of start-up (EOS) time
ssize_t cyt_attr_eost_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count);

/// Get network stats on port QSFP0
ssize_t cyt_attr_nstats_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf);

/// Get XDMA stats
ssize_t cyt_attr_xstats_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf);

/// Get partial reconfiguration stats
ssize_t cyt_attr_prstats_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf);

/// Get engine stats
ssize_t cyt_attr_engines_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf);

/// Get Coyote FPGA configuration (N_REGIONS, EN_MEM, EN_STRM, EN_PR, EN_RDMA, TLB config etc.)
ssize_t cyt_attr_cnfg_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf);

#endif // _COYOTE_SYSFS_H_