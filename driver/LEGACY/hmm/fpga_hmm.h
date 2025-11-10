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

#ifndef __FPGA_HMM_H__
#define __FPGA_HMM_H__

#include "coyote_defs.h"
#include "vfpga_hw.h"

/*
███╗   ███╗███╗   ███╗██╗   ██╗
████╗ ████║████╗ ████║██║   ██║
██╔████╔██║██╔████╔██║██║   ██║
██║╚██╔╝██║██║╚██╔╝██║██║   ██║
██║ ╚═╝ ██║██║ ╚═╝ ██║╚██████╔╝
╚═╝  
*/

#ifdef HMM_KERNEL

/* MMU */
int mmu_handler_hmm(struct vfpga_dev *d, uint64_t vaddr, uint64_t len, int32_t ctid, int32_t stream, pid_t hpid);

/* Invalidations */
bool cyt_interval_invalidate(struct mmu_interval_notifier *interval_sub, const struct mmu_notifier_range *range, unsigned long cur_seq);

/* Migrations */
int user_migrate_to_card(struct vfpga_dev *d, struct cyt_migrate *args);
int user_migrate_to_host(struct vfpga_dev *d, struct cyt_migrate *args);
int fpga_migrate_to_host(struct vfpga_dev *d, struct cyt_migrate *args);
int fpga_migrate_to_card(struct vfpga_dev *d, struct cyt_migrate *args);
struct page *host_ptw(uint64_t vaddr, pid_t hpid);
vm_fault_t cpu_migrate_to_host(struct vm_fault *vmf);
int fpga_do_host_fault(struct vfpga_dev *d, struct cyt_migrate *args); // not really needed ...

/* Mapping */
void tlb_map_hmm(struct vfpga_dev *d, uint64_t vaddr, uint64_t *paddr, uint32_t n_pages, int32_t host, int32_t ctid, pid_t hpid, bool huge); 
void tlb_unmap_hmm(struct vfpga_dev *d, uint64_t vaddr, uint32_t n_pages, pid_t hpid, bool huge);

/* Private pages */
void free_card_mem(struct vfpga_dev *d, int ctid);
void free_mem_regions(struct bus_driver_data *bd_data);
void cpu_free_private_page(struct page *page);
struct page *alloc_private_page(struct vfpga_dev *d);
int alloc_new_prvt_pages(struct vfpga_dev *d);
int is_thp(struct vm_area_struct *vma, unsigned long addr, int *locked);

#endif

#endif /* FPGA HMM */