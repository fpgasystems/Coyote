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
 * @file pci_qdma.h
 * @brief Contains functions for loading and setting up the Coyote driver on PCI platforms with the QDMA core.
 */

#ifdef PLATFORM_VERSAL

#ifndef _PCI_QDMA_H_
#define _PCI_QDMA_H_

#include "pci_util.h"
#include "coyote_defs.h"
#include "coyote_setup.h"

/// Assign a unique ID to each Coyote-enabled FPGA card and set the unique device name
void assign_device_id(struct bus_driver_data *data);

//////////////////////////////////////////////
//                INTERRUPTS               //
////////////////////////////////////////////  

/**
 * @brief Sets up Coyote IRQs for vfpga and reconfig devices
 *
 * This function initializes the MSI-X interrupt vectors for the device and associates
 * them with the appropriate interrupt handler functions (vfpga_isr, reconfig_isr).
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 * @param pdev Pointer to the PCI device structure associated with the Coyote device.
 * @param enable_reconfig_irq Boolean flag to enable reconfiguration interrupts.
 * @return 0 on success, negative error code on failure.
 */
int irq_setup(struct bus_driver_data *data, struct pci_dev *pdev, bool enable_reconfig_irq);

/**
 * @brief Removes previously set-up IRQs (opposite of irq_setup)
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 * @param enable_reconfig_irq Boolean flag to disable reconfiguration interrupts; same purpose as in irq_setup.
 */
void irq_teardown(struct bus_driver_data *data, bool enable_reconfig_irq);

/**
 * @brief Checks if MSI-X is supported and enabled for the PCI device.
 *
 * This function verifies the presence of MSI-X capability in the PCI device and
 * allocates the required number of MSI-X vectors, which are later used in irq_setup.
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 * @param pdev Pointer to the PCI device structure associated with the Coyote device.
 * @return 0 on success, negative error code on failure.
 */
int pci_check_msix(struct bus_driver_data *data, struct pci_dev *pdev);

//////////////////////////////////////////////
//                  BARS                   //
//////////////////////////////////////////// 

/**
 * @brief Maps a single BAR (Base Address Register) of the PCI device
 *
 * This function maps a specific BAR to the driver's address space, using the `pci_iomap` function.
 * Additionally, it includes sanity checks for the BAR type and size.
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information.
 * @param pdev Pointer to the PCI device structure.
 * @param idx Index of the BAR to be mapped.
 * @param curr_idx Index in the driver's BAR array where the mapped BAR will be stored.
 *        This is incremented for each successfully mapped BAR and ensures that the mapped BARs
 *        are stored sequentially in the driver's data structure.
 * @return 0 on success, negative error code on failure.
 */
int map_single_bar(struct bus_driver_data *data, struct pci_dev *pdev, int idx, int curr_idx);

/**
 * @brief Maps all BARs for the Coyote driver
 *
 * This function iterates through all available BARs of the PCI device and maps them
 * into the driver's address space using `map_single_bar`.
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 * @param pdev Pointer to the PCI device structure
 * @return 0 on success, negative error code on failure.
 */
int map_bars(struct bus_driver_data *data, struct pci_dev *pdev);

/**
 * @brief Unmaps all previously mapped BARs of the PCI device.
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 * @param pdev Pointer to the PCI device structure.
 */
void unmap_bars(struct bus_driver_data *data, struct pci_dev *pdev);

//////////////////////////////////////////////
//                QUEUES                   //
////////////////////////////////////////////  

/**
 * @brief Utility function, checks that queue context busy bit isn't set, meaning new values can be written to the regs
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 */
void wait_until_busy_cleared(struct bus_driver_data *bd_data);

/**
 * @brief Utility function, clears a given context of a queue
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 * @param qid Queue ID
 * @param sel The context to be cleared, options are listed in the QDMA specification from PG347 (v3.4), p301
 */
void clear_ctx_reg(struct bus_driver_data *bd_data, int32_t qid, int32_t sel);

/**
 * @brief Utility function, invalidates a given context of a queue
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 * @param qid Queue ID
 * @param sel The context to be invalidated, options are listed in the QDMA specification from PG347 (v3.4), p301
 */
void invalidate_ctx_reg(struct bus_driver_data *bd_data, int32_t qid, int32_t sel);

/**
 * @brief Enables a single C2H or H2C queue
 *
 * This function initializes a QDMA queue for a specific queue ID and direction,
 * by following the steps outlined in the QDMA specification from PG347 (v3.4), p300 - 302.
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 * @param qid Queue ID
 * @param c2h Direction of the engine (1 for C2H, 0 for H2C)
 * @param is_mm Memory mapped (1) or streaming (0) queue
 * @param mm_chn Memory mapped channel ID (0 or 1); only relevant if is_mm is set to 1
 * @return 0 on success, negative error code on failure
 */
int enable_queue(struct bus_driver_data *data, int32_t qid, bool c2h, bool is_mm, uint32_t mm_chn);

/**
 * @brief Enable QDMA C2H and H2C queues
 *
 * This function iterates through the requested QDMA queues and initializes them by writing the QDMA registers
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 * @return 0 on success, negative error code on failure
 */
int enable_queues(struct bus_driver_data *data);

/**
 * @brief Disable all active QDMA queues
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 */
void disable_queues(struct bus_driver_data *data);

//////////////////////////////////////////////
//                DRIVER                   //
//////////////////////////////////////////// 

/**
 * @brief (Re-)Initializes the Coyote shell when running on PCI platforms
 *
 * This function implements a subset of the pci_probe functionality and it 
 * should be used to re-initialize the Coyote shell after partial reconfiguration
 * It is called from reconfig_ops.c during the reconfiguration process
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 * @return 0 on success, negative error code on failure.
 */
int shell_pci_init(struct bus_driver_data *data);

/**
 * @brief Clears the state of the Coyote shell when running on PCI platforms
 *
 * This function releases the resources and resets the hardware components
 * associated with the shell layer. Only called when the shell is removed
 * through reconfiguration (from reconfig_ops.c).
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 */
void shell_pci_remove(struct bus_driver_data *data);

/**
 * @brief Top-level PCI initialization function for the Coyote driver.
 *
 * This function is called during the PCI device enumeration process to initialize
 * the Coyote driver for the detected PCI device. It sets up the necessary resources,
 * mapping the device's BARs, initializing the QDMA, setting up char devices etc.
 */
int pci_probe(struct pci_dev *pdev, const struct pci_device_id *id);

/**
 * @brief Top-level PCI device removal function for the Coyote driver
 *
 * This function is called during the PCI device removal process to clean up
 * the resources and de-initialize the Coyote driver
 */
void pci_remove(struct pci_dev *pdev);

/// Top-level entry function, called by coyote_init and simply a wrapper around pci_probe
int pci_init(void);

/// Top-level exit function, called by coyote_exit and simply a wrapper around pci_remove
void pci_exit(void);

#endif // _PCI_QDMA_H_

#endif // PLATFORM_VERSAL
