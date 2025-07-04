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

#include "pci_util.h"

inline uint32_t build_u32(uint32_t hi, uint32_t lo) {
    return ((hi & 0xFFFFUL) << 16) | (lo & 0xFFFFUL);
}

void pci_enable_capability(struct pci_dev *pdev, int capability) {
	pcie_capability_set_word(pdev, PCI_EXP_DEVCTL, capability);
}

bool msix_capable(struct pci_dev *pdev) {
    BUG_ON(!pdev);

    if (pdev->no_msi) { return false; }

    struct pci_bus *bus;
    for (bus = pdev->bus; bus; bus = bus->parent)
        if (bus->bus_flags & PCI_BUS_FLAGS_NO_MSI) { return false; }

    if (!pci_find_capability(pdev, PCI_CAP_ID_MSIX)) { return false; }

    return true;
}
