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
 * @file pci_xdma.h
 * @brief Contains functions for loading and setting up the Coyote driver on PCI platforms with the XDMA core.
 */

#ifndef _PCI_XDMA_H_
#define _PCI_XDMA_H_

#include "pci_util.h"
#include "coyote_defs.h"
#include "coyote_setup.h"

/// Assign a unique ID to each Coyote-enabled FPGA card and set the unique device name
void assign_device_id(struct bus_driver_data *data);

//////////////////////////////////////////////
//                INTERRUPTS               //
////////////////////////////////////////////  

/** 
 * @brief Enables interrupts issued from vFPGAs
 *
 * Interrupts issued through the XDMA core must be enabled 
 * By writing to the IRQ Block User Interrupt Enable Mask W1S (0x08) register
 * W1S means "Write 1 to Set", which means that bits set to 1 in the mask
 * Will enable the corresponding interrupts
 * For more information, refer to the XDMA specification [PG195 (v4.1)]
 * In particular, page 59 onwards, Table 78 and Table 81 for this function
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 */
void vfpga_interrupts_enable(struct bus_driver_data *data);

/** 
 * @brief Disables interrupts issued from vFPGAs
 *
 * Interrupts issued through the XDMA core can be disabled (for e.g., when removing the driver) 
 * To do so, it's necessary to write to the IRQ Block User Interrupt Enable Mask W1C (0x12) register
 * W1C means "Write 1 to Clear", which means that bits set to 1 in the mask
 * Will disable the corresponding interrupts
 * For more information, refer to the XDMA specification [PG195 (v4.1)]
 * In particular, page 59 onwards, Table 78 and Table 82 for this function
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 */
void vfpga_interrupts_disable(struct bus_driver_data *data);

/** 
 * @brief Enables interrupts issued for reconfiguration
 *
 * Interrupts issued through the XDMA core must be enabled 
 * By writing to the IRQ Block User Interrupt Enable Mask W1S (0x08) register
 * The method is the same as for vFPGAs (above), but the mask is different
 * More informaction in the XDMA specification [PG195 (v4.1)], p59 onwards, Tables 78 and 81
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 */
void reconfig_interrupt_enable(struct bus_driver_data *data);

/** 
 * @brief Disables interrupts used for reconfiguration
 *
 * Similar implemenation as in vfpga_interrupts_disable, with a different 
 * For more information, see above functions and the XDMA specification, p59 onwards, Tables 78 and 82
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 */
void reconfig_interrupt_disable(struct bus_driver_data *data);

/** 
 * @brief Reads the interrupts registers from the XDMA core
 *
 * Util function which can be used for debugging but also to flush previous register values
 * For more details on the registers values, refer to the XDMA specification [PG195 (v4.1)], Tables 78, 86, 87
 * @return 32-bit value containing the interrupts requests; low 16 are user, top 16 are channel (unused in Coyote)
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information 
 */
uint32_t read_interrupts(struct bus_driver_data *data);

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

/**
 * @brief Writes MSI-X vectors to the XDMA configuration registers; per Table 90 in the XDMA specification
 * 
 * MSI-X vectors are required to uniquely identify an interrupt source and therefore call the correct ISR handler function.
 * In Coyote, we write one vector for each vFPGA device and one for the reconfiguration process
 * In total, there are at most 15 (vFPGA) interrupts and 1 (reconfiguration) interrupt, hence 16 vectors
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 */
void write_msix_vectors(struct bus_driver_data *data);

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
 *
 * @note enable_reconfig_irq is used to determine whether to set up the reconfiguration interrupt.
 * Additionally, it is used to indicate the "first" set-up of the Coyote driver,
 * when the bitstram is loaded using the Vivado Hardware Manager. When this happens, the MSI-X vectors
 * need to be written to the XDMA configuration registers using the write_msix_vectors function.
 * However, this function is also called after shell_pci_init, which is used when dynamically reconfiguring the shell
 * Then, there is no need to write the MSI-X vectors again, as they are already set up (the XDMA core stays online during shell reconfiguration).
 * However, the IRQ vectors need to be re-initialized for the vFPGA devices (but not for the reconfiguration device).
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
//                ENGINES                  //
////////////////////////////////////////////  

/// Returns the channel ID of the engine; see Tables 41 & 60 in the XDMA specification [PG195 (v4.1)]
uint32_t get_engine_channel_id(struct xdma_engine_regs *regs);

/// Returns the enginer ID; see Tables 41 & 60 in the XDMA specification [PG195 (v4.1)]
uint32_t get_engine_id(struct xdma_engine_regs *regs);

/// Reads from the XDMA aligment registers (address bits and alignment, length granularity) and sets the values in the engine struct
void read_engine_alignments(struct xdma_engine *engine);

/**
 * @brief Creates a C2H or H2C engine
 *
 * Allocates and initializes an XDMA engine structure for either
 * C2H (Card-to-Host) or H2C (Host-to-Card) data transfer. It sets up the engine
 * metadata, including its channel and direction. Additionally, it resets the engine
 * by writing to its control registers.
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 * @param offset Offset of the engine configuration register; obtained from the XDMA specification [PG195 (v4.1)], Table 38
 * @param c2h Direction of the engine (1 for C2H, 0 for H2C)
 * @param channel Channel number of the engine
 * @return Pointer to the created engine structure, or NULL on failure
 */
struct xdma_engine *engine_create(struct bus_driver_data *data, int offs, int c2h, int channel);

/**
 * @brief Probes a single C2H or H2C engine
 *
 * This function initializes an XDMA engine for a specific channel and direction.
 * Mostly a wrapper around engine_create, but also performs some sanity checks.
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 * @param c2h Direction of the engine (1 for C2H, 0 for H2C)
 * @param channel Channel number of the engine
 * @return 0 on success, negative error code on failure
 */
int probe_for_engine(struct bus_driver_data *data, int c2h, int channel);

/**
 * @brief Probes all C2H and H2C engines
 *
 * This function iterates through all available channels and initializes XDMA
 * engines for both C2H and H2C directions.
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 * @return 0 on success, negative error code on failure
 */
int probe_engines(struct bus_driver_data *data);

/**
 * @brief Removes a single XDMA engine
 *
 * Deallocates resources associated with a specific XDMA engine and resets control registers in hardware.
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 * @param engine Pointer to the XDMA engine structure to be removed
 */
void engine_destroy(struct bus_driver_data *data, struct xdma_engine *engine);

/**
 * @brief Remove all XDMA engines
 *
 * @param data Pointer to the bus driver data structure, containing Coyote device information
 */
void remove_engines(struct bus_driver_data *data);

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
 *
 * @note We need to distinguish between idx and curr_idx, since in Coyote curr_idx goes can be 0, 1, 2
 * However, idx is the index of the BAR in the PCI device structure, which can be between 0 and 6.
 * If the XDMA core is configure to have 64-bit addresses, then each BAR takes two slots, as explained in Table 3 
 * of the XDMA specification [PG195 (v4.1)].
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
 * mapping the device's BARs, initializing the XDMA engines, setting up char devices etc.
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

#endif // _PCI_XDMA_H_