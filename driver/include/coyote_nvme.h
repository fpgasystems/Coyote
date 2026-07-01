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
 * @file coyote_nvme.h
 * @brief NVMe device management for the Coyote driver
 *
 * Per-device discovery, controller initialization, admin/I/O queue setup, and
 * per-region LBA permission management for NVMe SSDs accessed by the FPGA shell
 * via the SQ/CQ BRAM controllers and the nvme_cnfg_slave AXI-Lite register block.
 *
 * All entry points are only meaningful when EN_NVME is set in the loaded bitstream;
 * callers must check bd_data->en_nvme before invoking.
 */

#ifndef _COYOTE_NVME_H_
#define _COYOTE_NVME_H_

#include "coyote_defs.h"

/// Allocate and initialize bd_data->nvme_mgr; called from coyote_setup when en_nvme is true
int  nvme_mgr_init(struct bus_driver_data *bd_data);

/// Free bd_data->nvme_mgr; called during driver teardown
void nvme_mgr_free(struct bus_driver_data *bd_data);

/// Claim an NVMe device by BDF, set up admin queue, identify namespace and allocate an LBA range for the given region; populates *req
long vfpga_nvme_init(struct vfpga_dev *device, struct nvme_init_ioctl *req);

/// Release the LBA range previously allocated to this region; tears down the device if no regions remain
long vfpga_nvme_close(struct vfpga_dev *device, uint32_t dev_id);

/// Test whether an NVMe device matching *req is already registered to this region; populates the output fields when found
long vfpga_nvme_is_registered(struct vfpga_dev *device, struct nvme_init_ioctl *req);

#endif // _COYOTE_NVME_H_
