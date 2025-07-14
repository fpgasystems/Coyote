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

/**
 * @brief Utility function, constructs a 32-bit MSI-X vector register value.
 *
 * This function packs four 5-bit fields (a, b, c, d) into a single 32-bit value.
 * Each field represents an MSI-X table entry index
 * 5 bit-values are used, per the XDMA specification [PG195 (v4.1)], Table 90 onwards
 *
 * @param a The first 5-bit field (bits 0–4)
 * @param b The second 5-bit field (bits 8–12)
 * @param c The third 5-bit field (bits 16–20)
 * @param d The fourth 5-bit field (bits 24–28)
 * @return A 32-bit value representing the packed MSI-X vector register
 */
uint32_t build_vector_reg(uint32_t a, uint32_t b, uint32_t c, uint32_t d);


#endif // _PCI_UTIL_H_
