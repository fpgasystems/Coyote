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

#ifndef __FPGA_HMM_H__
#define __FPGA_HMM_H__

#include "coyote_dev.h"
#include "fpga_hw.h"

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
int mmu_handler_hmm(struct fpga_dev *d, uint64_t vaddr, uint64_t len, int32_t cpid, int32_t stream, pid_t hpid);

/* Invalidations */
bool cyt_interval_invalidate(struct mmu_interval_notifier *interval_sub, const struct mmu_notifier_range *range, unsigned long cur_seq);

/* Migrations */
int user_migrate_to_card(struct fpga_dev *d, struct cyt_migrate *args);
int user_migrate_to_host(struct fpga_dev *d, struct cyt_migrate *args);
int fpga_migrate_to_host(struct fpga_dev *d, struct cyt_migrate *args);
int fpga_migrate_to_card(struct fpga_dev *d, struct cyt_migrate *args);
struct page *host_ptw(uint64_t vaddr, pid_t hpid);
vm_fault_t cpu_migrate_to_host(struct vm_fault *vmf);
int fpga_do_host_fault(struct fpga_dev *d, struct cyt_migrate *args); // not really needed ...

/* Mapping */
void tlb_map_hmm(struct fpga_dev *d, uint64_t vaddr, uint64_t *paddr, uint32_t n_pages, int32_t host, int32_t cpid, pid_t hpid, bool huge); 
void tlb_unmap_hmm(struct fpga_dev *d, uint64_t vaddr, uint32_t n_pages, pid_t hpid, bool huge);

/* Private pages */
void free_card_mem(struct fpga_dev *d, int cpid);
void free_mem_regions(struct bus_drvdata *pd);
void cpu_free_private_page(struct page *page);
struct page *alloc_private_page(struct fpga_dev *d);
int alloc_new_prvt_pages(struct fpga_dev *d);
int is_thp(struct vm_area_struct *vma, unsigned long addr, int *locked);

#endif

#endif /* FPGA HMM */