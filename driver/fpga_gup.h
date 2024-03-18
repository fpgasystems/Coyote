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

#ifndef __FPGA_GUP_H__
#define __FPGA_GUP_H__

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

/* MMU */
int mmu_handler_gup(struct fpga_dev *d, uint64_t vaddr, uint64_t len, int32_t cpid, int32_t stream, pid_t hpid);

/* Mapping */
struct user_pages* map_present(struct fpga_dev *d, struct desc_aligned *pfa);
void tlb_map_gup(struct fpga_dev *d, struct desc_aligned *pfa, struct user_pages *user_pg, pid_t hpid);
void tlb_unmap_gup(struct fpga_dev *d, struct user_pages *user_pg, pid_t hpid);

/* PTW */
struct user_pages* tlb_get_user_pages(struct fpga_dev *d, struct desc_aligned *pfa, pid_t hpid, struct task_struct *curr_task, struct mm_struct *curr_mm);
int tlb_put_user_pages(struct fpga_dev *d, uint64_t vaddr, int32_t cpid, pid_t hpid, int dirtied);
int tlb_put_user_pages_cpid(struct fpga_dev *d, int32_t cpid, pid_t hpid, int dirtied);

/* DMA */
void migrate_to_card_gup(struct fpga_dev *d, struct user_pages *user_pg);
void migrate_to_host_gup(struct fpga_dev *d, struct user_pages *user_pg);
int offload_user_gup(struct fpga_dev *d, uint64_t vaddr, int32_t cpid);
int sync_user_gup(struct fpga_dev *d, uint64_t vaddr, int32_t cpid);

#endif /* FPGA GUP */