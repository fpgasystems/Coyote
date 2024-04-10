#ifndef __GUEST_PCI_H__
#define __GUEST_PCI_H__

#include "guest_dev.h"
#include "guest_irq.h"

int guest_probe(struct pci_dev *pdev, const struct pci_device_id *id);
void guest_remove(struct pci_dev *pdev);

#endif