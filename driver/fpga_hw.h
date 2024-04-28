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


#ifndef __FPGA_HW_H__
#define __FPGA_HW_H__

#include "coyote_dev.h"

/* IRQ */
uint32_t fpga_read_irq_type(struct fpga_dev *d);
int32_t fpga_read_irq_notify(struct fpga_dev *d, struct fpga_irq_notify *irq_not);
void fpga_read_irq_pfault(struct fpga_dev *d, struct fpga_irq_pfault *irq_pf);
void fpga_drop_irq_pfault(struct fpga_dev *d, bool wr, int32_t cpid);
void fpga_change_lock_tlb(struct fpga_dev *d);
void fpga_restart_mmu(struct fpga_dev *d, bool wr, int32_t cpid);
void fpga_clear_irq(struct fpga_dev *d);

/* Invalidate */
void fpga_invalidate(struct fpga_dev *d, uint64_t vaddr, uint32_t n_pages, int32_t hpid, bool last);

/* Service TLB */
void tlb_create_map(struct fpga_dev *d, struct tlb_order *tlb_ord, uint64_t vaddr, uint64_t paddr, int32_t host, int32_t cpid, pid_t hpid);
void tlb_create_unmap(struct fpga_dev *d, struct tlb_order *tlb_ord, uint64_t vaddr, pid_t hpid);

/* Card memory resources */
int card_alloc(struct fpga_dev *d, uint64_t *card_paddr, uint32_t n_pages, bool huge);
void card_free(struct fpga_dev *d, uint64_t *card_paddr, uint32_t n_pages, bool huge);

/* DMA */
void dma_offload_start(struct fpga_dev *d, uint64_t *host_address, uint64_t *card_address, uint32_t n_pages, bool huge);
void dma_sync_start(struct fpga_dev *d, uint64_t *host_address, uint64_t *card_address, uint32_t n_pages, bool huge);

#endif /* FPGA HW */