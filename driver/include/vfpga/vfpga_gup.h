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
 * @file vfpga_gup.h
 * @brief Header file for memory management of vFPGAs
 *
 * This file defines the functions for handling page faults, managing user pages, 
 * exporting necessary DMA Buffers for FPGA-GPU communication. 
 * NOTE: GUP stands for "Get User Pages", which is a Linux kernel mechanism to pin user-space pages in memory and Coyote swaps the pages between host and card.
 * NOTE: Previously (currently in LEGACY), there was an alternative memory management mechanism, using Linux's Hetereogeneous Memory Management (HMM) framework.
 *
 * The mapped user pages are stored in a hash_table, called user_buff_map
 * Functions in this file implement high-level logic for managing Coyote memory
 * And call functions in vfpga_hw.h that handle the low-level logic by writing to the memory-mapped registers in the FPGA
 * Additionally, this file provides functions for peer-to-peer DMA Buffer management, enabling direct FPGA-GPU communication.
 *
 * Important functions in this file include:
 *    - mmu_handler_gup; the top-level function, handles page faults issued by the FPGA
 *    - tlb_map_gup and tlb_unmap_gup; which maps/unmaps user pages to the TLB
 *    - offload_user_pages and sync_user_pages; handling the offloading and syncing of user pages between host and card
 *    - P2P DMA Buffer functions for managing DMA Buffers to FPGA-GPU communication 
 */

#ifndef _VFPGA_GUP_H_
#define _VFPGA_GUP_H_

#include "vfpga_hw.h"
#include "coyote_defs.h"

/**
 * @brief Top-level function; handles page faults issued by the FPGA
 *
 * @param device vFPGA char device
 * @param vaddr Buffer virtual address corresponding to the page fault
 * @param len Length, in bytes, of the page-faulting buffer
 * @param ctid Coyote thread ID
 * @param stream Access type: HOST (1) or CARD (0)
 * @param hpid Host process ID
 * @return 0 on success, negative error code on failure
 */
int mmu_handler_gup(struct vfpga_dev *device, uint64_t vaddr, uint64_t len, int32_t ctid, int32_t stream, pid_t hpid);

/**
 * @brief Checks if a mapping is already present in the user buffer map
 *
 * @param device vFPGA char device
 * @param pf_desc Aligned page fault descriptor; holds info about virtual address, length etc.
 * @return Pointer to the user_pages structure if mapping exists, NULL otherwise
 */
struct user_pages* map_present(struct vfpga_dev *device, struct pf_aligned_desc *pf_desc);

/**
 * @brief Creates a TLB mapping for the given user pages
 *
 * @param device vFPGA char device
 * @param pf_desc Aligned page fault descriptor; holds info about virtual address, length etc.
 * @param user_pg User pages structure
 * @param hpid Host process ID
 */
void tlb_map_gup(struct vfpga_dev *device, struct pf_aligned_desc *pf_desc, struct user_pages *user_pg, pid_t hpid);

/**
 * @brief Removes a TLB mapping for the given user pages
 *
 * @param device vFPGA char device
 * @param pf_desc Aligned page fault descriptor; holds info about virtual address, length etc.
 * @param hpid Host process ID
 */
void tlb_unmap_gup(struct vfpga_dev *device, struct user_pages *user_pg, pid_t hpid);

/**
 * @brief Pins user pages and prepares them for TLB mapping
 *
 * A function that is first called when no mapping for a user page exists
 * In this case, the function performs the following:
 *  - Allocates a new user_pages struct which holds informaton about page physical address, length etc.,
 *  - Pins the pages, to avoid them being swapped out
 *  - Flushes the cache to ensure data consistency between the FPGA and the CPU
 *  - Allocates the corresponding card buffer, if memory is enabled
 * This function is immediately followed by a call to tlb_map_gup, which maps the user pages to the vFPGA's TLB
 * 
 * @param device vFPGA char device
 * @param pf_desc Aligned page fault descriptor
 * @param hpid Host process ID
 * @param curr_task Current task structure
 * @param curr_mm Current memory management structure
 * @return Pointer to the user_pages structure on success, NULL on failure
 */
struct user_pages* tlb_get_user_pages(struct vfpga_dev *device, struct pf_aligned_desc *pf_desc, pid_t hpid, struct task_struct *curr_task, struct mm_struct *curr_mm);

/**
 * @brief Releases user pages and removes their TLB mappings.
 *
 * @param device vFPGA char device
 * @param vaddr Starting virtual address
 * @param ctid Coyote thread ID for which the pages were mapped
 * @param hpid Host process ID for which the pages were mapped
 * @param dirtied Indicates if the pages were modified
 * @return 0 on success, negative error code on failure
 */
int tlb_put_user_pages(struct vfpga_dev *device, uint64_t vaddr, int32_t ctid, pid_t hpid, int dirtied);

/**
 * @brief Releases all user pages for a given Coyote thread
 *
 * @param device vFPGA char device
 * @param ctid Coyote thread ID for which the pages should be released
 * @param hpid Host process ID associated with the Coyote thread
 * @param dirtied Indicates if the pages were modified
 * @return 0 on success, negative error code on failure
 */
int tlb_put_user_pages_ctid(struct vfpga_dev *device, int32_t ctid, pid_t hpid, int dirtied);

/**
 * @brief Helper function, migrates user pages to card memory
 *
 * @param device vFPGA char device
 * @param user_pg User pages to be migrated
 */
void migrate_to_card(struct vfpga_dev *device, struct user_pages *user_pg);

/**
 * @brief Helper function, migrates user pages back to the host memory
 *
 * @param device vFPGA char device
 * @param user_pg User pages to be migrated
 */
void migrate_to_host(struct vfpga_dev *device, struct user_pages *user_pg);

/**
 * @brief Trigger off-load operation; moving pages from host to card & updating mappings
 *
 * @param device vFPGA char device
 * @param vaddr Starting virtual address of the buffer to be offloaded
 * @param len Length, in bytes, of the buffer to be offloaded
 * @param ctid Coyote thread ID
 * @return 0 on success, negative error code on failure
 */
int offload_user_pages(struct vfpga_dev *device, uint64_t vaddr, uint32_t len, int32_t ctid);

/**
 * @brief Trigger sync operation; moving pages from card to host & updating mappings
 *
 * @param device vFPGA char device
 * @param vaddr Starting virtual address of the buffer to be synced
 * @param len Length, in bytes, of the buffer to be synced
 * @param ctid Coyote thread ID
 * @return 0 on success, negative error code on failure
 */
int sync_user_pages(struct vfpga_dev *device, uint64_t vaddr, uint32_t len, int32_t ctid);

/**
 * @brief Callback for handling page movement notifications in peer-to-peer DMA
 *
 * To manage page movements in GPU memory, this routines deletes TLB entries and retrieves new entries
 * It is passed as a parameter to the dma_buf_attach_ops struct, which is used when attaching the DMA Buffer
 *
 * @param attach DMA buffer attachment structure
 */
void p2p_move_notify(struct dma_buf_attachment *attach);

/**
 * @brief Attaches a DMA buffer to the vFPGA
 *
 * In general, this functions implements similary logic as tlb_get_user_pages, but for DMA Buffers
 * Functionality includes:
 *  - Allocating a new user_pages struct which holds informaton about page physical address, length etc.,
 *  - Attaches the DMA Buffer to the vFPGA char device, allowing the vFPGA to access the buffer
 *  - Maps the DMA Buffer to the FPGA's address spae, by providing a scatter-gather list represnting the physical memory of the buffer
 *  - Allocate corresponding card buffer, if memory is enabled
 *  - Maps the physical to virtual translations to the vFPGA's TLB using tlb_map_gup
 
 * @param device vFPGA char device
 * @param buf_fd File descriptor of the DMA buffer
 * @param vaddr Virtual address to map the buffer
 * @param ctid Coyote thread ID
 * @return 0 on success, negative error code on failure
 */
int p2p_attach_dma_buf(struct vfpga_dev *device, int buf_fd, uint64_t vaddr, int32_t ctid);

/**
 * @brief Detaches a DMA buffer from the vFPGA device
 * 
 * In general, this functions implements similary logic as tlb_put_user_pages, but for DMA Buffers
 * It is called at the end of the Coyote thread's execution, when the buffer is no longer needed
 * Functionality includes (which is largely opposite to p2p_attach_dma_buf):
 *  - Removing the TLB entries using tlb_unmap_gup
 *  - Freeing card memory, if memory is enabled 
 *  - Unmapping the DMA Buffer from the vFPGA's address space
 *  - Detaching the vFPGA device from the DMA Buffer
 *
 * @param device vFPGA char device
 * @param vaddr Virtual address of the buffer
 * @param ctid Coyote thread ID
 * @param dirtied Indicates if the buffer was modified
 * @return 0 on success, negative error code on failure
 */
int p2p_detach_dma_buf(struct vfpga_dev *device, uint64_t vaddr, int32_t ctid, int dirtied);

#endif // _VFPGA_GUP_H_
