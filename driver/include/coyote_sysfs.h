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