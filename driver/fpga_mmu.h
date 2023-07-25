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

#ifndef __FPGA_MMU_H__
#define __FPGA_MMU_H__

#include "coyote_dev.h"

/* Alloc huge pages (should be used only if no host hugepages enabled!) */
int alloc_user_buffers(struct fpga_dev *d, unsigned long n_pages, int32_t cpid);
int free_user_buffers(struct fpga_dev *d, uint64_t vaddr, int32_t cpid);

/* PR memory regions */
int alloc_pr_buffers(struct fpga_dev *d, unsigned long n_pages);
int free_pr_buffers(struct fpga_dev *d, uint64_t vaddr);

/* Card memory resources */
int card_alloc(struct fpga_dev *d, uint64_t *card_paddr, uint64_t n_pages, int type);
void card_free(struct fpga_dev *d, uint64_t *card_paddr, uint64_t n_pages, int type);

/* TLB mappings */
void tlb_create_map(struct tlb_order *tlb_ord, uint64_t vaddr, uint64_t paddr_host, uint64_t paddr_card, int32_t cpid, uint64_t *entry);
void tlb_create_unmap(struct tlb_order *tlb_ord, uint64_t vaddr, int32_t cpid, uint64_t *entry);

/* TLB control */
void tlb_service_dev(struct fpga_dev *d, struct tlb_order *tlb_ord, uint64_t *entry, uint32_t n_pages);

/* Page table walks */
int tlb_get_user_pages(struct fpga_dev *d, uint64_t start, size_t count, int32_t cpid, pid_t pid);
int tlb_put_user_pages(struct fpga_dev *d, uint64_t vaddr, int32_t cpid, int dirtied);
int tlb_put_user_pages_cpid(struct fpga_dev *d, int32_t cpid, int dirtied);
int tlb_put_user_pages_all(struct fpga_dev *d, int dirtied);

#endif /* FPGA MMU */