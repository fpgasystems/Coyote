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
