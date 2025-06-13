
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
