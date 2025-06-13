/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
  * All rights reserved.
  *
  * Redistribution and use in source and binary forms, with or without modification,
  * are permitted provided that the following conditions are met:
  *
  * 1. Redistributions of source code must retain the above copyright notice,
  * this list of conditions and the following disclaimer.
  * 2. Redistributions in binary form must reproduce the above copyright notice,
  * this list of conditions and the following disclaimer in the documentation
  * and/or other materials provided with the distribution.
  * 3. Neither the name of the copyright holder nor the names of its contributors
  * may be used to endorse or promote products derived from this software
  * without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  */

/**
 * @file vfpga_hw.h
 * @brief vFPGA hardware functions
 *
 * Functions in this file are primarily used for low-level hardware operations in the vFPGA
 * Typically, this includes writing to or reading from hardware registers, which are memory-mapped during driver loading
 * The registers typically start an operation in hardware or contain some control flow data (virtual address, length etc.)
 */

#ifndef _VFPGA_HW_H_
#define _VFPGA_HW_H_

#include "coyote_defs.h"

/**
 * @brief Parse interrupt type
 * 
 * @param device vFPGA char device
 * @return type of interrupt (IRQ_DMA_OFFL, IRQ_DMA_SYNC, IRQ_INVLDT, IRQ_PFAULT, IRQ_NOTIFY)
 */
uint32_t read_irq_type(struct vfpga_dev *device);

/**
 * @brief Parse user notification IRQ
 * 
 * @param device vFPGA char device
 * @param irq_not notification struct, to be set (updated) by this function
 */
void read_irq_notify(struct vfpga_dev *device, struct vfpga_irq_notify *irq_not);

/**
 * @brief Parse page fault IRQ
 * 
 * @param device vFPGA char device
 * @param irq_pf page fault struct, to be set (updated) by this function
 */
void read_irq_pfault(struct vfpga_dev *device, struct vfpga_irq_pfault *irq_pf);

/**
 * @brief Drops the page fault, because it went wrong somewhere
 *
 * @param device vFPGA char device
 * @param write write operation (true) or read operation (false)
 * @param ctid Coyote thread ID
 */
void drop_irq_pfault(struct vfpga_dev *device, bool write, int32_t ctid);

/**
 * @brief Resets the IRQ registers in hardware
 *
 * @param device vFPGA char device
 */
void clear_irq(struct vfpga_dev *device);

/**
 * @brief Restarts the MMU, by signaling a page fault has correctly been handled
 *
 * @param device vFPGA char device
 * @param write write operation (true) or read operation (false)
 * @param ctid Coyote thread ID
 */
void restart_mmu(struct vfpga_dev *device, bool write, int32_t ctid);

/**
 * @brief Invalidate a TLB entry
 *
 * @param device vFPGA char device
 * @param vaddr starting virtual address of the buffer to be invalidated
 * @param n_pages number of consecutive pages to be invalidated
 * @param hpid host process ID
 * @param last is this the last page of the buffer to be invalidated (equivalent to a tlast in an AXI stream)
 */
void invalidate_tlb_entry(struct vfpga_dev *device, uint64_t vaddr, uint32_t n_pages, int32_t hpid, bool last);

/**
 * @brief Locks or unlocks the TLB, potentially prevent new entries (if locked)
 *
 * @param device vFPGA char device
 */
void change_tlb_lock(struct vfpga_dev *device);

/**
 * @brief Create a TLB mapping
 *
 * @param device vFPGA char device
 * @param tlb_meta helper struct, containing TLB information (page size & shift, key size & shift etc.)
 * @param vaddr buffer virtual address
 * @param physical_address buffer physical address
 * @param host does the buffer reside in host memory (1) or in card memory (0)
 * @param ctid Coyote thread ID
 * @param hpid Host process ID
 */
void create_tlb_mapping(
  struct vfpga_dev *device, struct tlb_metadata *tlb_meta, uint64_t vaddr, 
  uint64_t physical_address, int32_t host, int32_t ctid, pid_t hpid
);

/**
 * @brief Unmap TLB entry
 *
 * @param device vFPGA char device
 * @param tlb_meta helper struct, containing TLB information (page size & shift, key size & shift etc.)
 * @param vaddr buffer virtual address
 * @param hpid Host process ID
 */
void create_tlb_unmapping(struct vfpga_dev *device, struct tlb_metadata *tlb_meta, uint64_t vaddr, pid_t hpid);

/**
 * @brief Triggers DMA off-load from host memory to card memory (asynchronous)
 * 
 * @param device vFPGA char device
 * @param host_address - virtual address of the buffer on the host to be off-loaded 
 * @param card_address - target virtual address on the card 
 * @param n_pages - number of pages in the buffer to be off-loaded
 * @param huge - whether the buffer is using hugepages or regular pages
 */
void trigger_dma_offload(struct vfpga_dev *device, uint64_t *host_address, uint64_t *card_address, uint32_t n_pages, bool huge);

/**
 * @brief Triggers DMA sync from card memory to host memory (asynchronous)
 * 
 * @param device vFPGA char device
 * @param host_address - target virtual address of the buffer on the host
 * @param card_address - virtual address of the buffer on the card 
 * @param n_pages - number of pages in the buffer to be synced
 * @param huge - whether the buffer is using hugepages or regular pages
 */
void trigger_dma_sync(struct vfpga_dev *device, uint64_t *host_address, uint64_t *card_address, uint32_t n_pages, bool huge);

/**
 * @brief Allocates memory on the card's HBM or DDR memory and updates the card_physical_address parameter with the allocated addresses
 * 
 * @param device vFPGA char device
 * @param card_physical_address initially null/empty, set by the function to reflect the physical address of the allocated pages
 * @param n_pages number of pages to be allocated
 * @param huge whether the memory is using hugepages or regular pages
 * @return whether the allocation was successful; can fail if there is insufficient space on the card
 */
int alloc_card_memory(struct vfpga_dev *device, uint64_t *card_physical_address, uint32_t n_pages, bool huge);

/**
 * @brief Release memory on the card; opposite of the above alloc_card_memory function
 * 
 * @param device vFPGA char device
 * @param card_physical_address list of pages allocated on the card's memory and their corresponding physical addresses
 * @param n_pages number of pages to be freed
 * @param huge whether the memory to be freed is using hugepages or regular pages
 */
void free_card_memory(struct vfpga_dev *device, uint64_t *card_physical_address, uint32_t n_pages, bool huge);

#endif // _VFPGA_HW_H_