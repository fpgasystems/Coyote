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
 * @file pci_util.h
 * @brief Coyote PCI utility functions
 */

#ifndef _PCI_UTIL_H_
#define _PCI_UTIL_H_

#include "coyote_defs.h"

/// Utility functions, concatenates two 16-bit values into a single 32-bit value
inline uint32_t build_u32(uint32_t hi, uint32_t lo);

/**
 * @brief Enables a specific PCIe capability for the device
 *
 * @param pdev Pointer to the PCI device structure
 * @param capability Capability to enable
 */
void pci_enable_capability(struct pci_dev *pdev, int cmd);

/**
 * @brief Checks if the PCI device supports MSI-X
 *
 * @param pdev Pointer to the PCI device structure.
 * @return `true` if MSI-X is supported, `false` otherwise.
 */
bool msix_capable(struct pci_dev *pdev);

#endif // _PCI_UTIL_H_
