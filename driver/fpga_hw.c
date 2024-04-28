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

#include "fpga_hw.h"

//
// IRQ ops
//

/**
 * @brief Read in the irq type
 * 
 * @param d - vFPGA
 * @param irq_pf - page fault struct
 */
uint32_t fpga_read_irq_type(struct fpga_dev *d)
{
    uint64_t tmp;
    uint32_t type;

    tmp = d->fpga_cnfg->isr;
    
    // read
    type = (uint32_t)(HIGH_16(LOW_32(tmp)));

    return type;
}

/**
 * @brief Clear pending irq
 * 
 * @param d - vFPGA
*/
void fpga_clear_irq(struct fpga_dev *d) {
    // clear
    d->fpga_cnfg->isr = FPGA_CNFG_CTRL_IRQ_CLR_PENDING;
}

/**
 * @brief Read in the notification
 *
 * @param d - vFPGA
 */
int32_t fpga_read_irq_notify(struct fpga_dev *d, struct fpga_irq_notify *irq_not)
{
    uint64_t tmp;

    tmp = d->fpga_cnfg->isr_pid;
    irq_not->cpid = (int32_t)LOW_32(tmp);
    tmp = d->fpga_cnfg->isr_len;
    irq_not->notval = (int32_t)HIGH_32(tmp);

    return 0;
}

/**
 * @brief Read in the page fault
 *
 * @param d - vFPGA
 * @param irq_pf - page fault struct
 */
void fpga_read_irq_pfault(struct fpga_dev *d, struct fpga_irq_pfault *irq_pf)
{
    irq_pf->vaddr = d->fpga_cnfg->isr_vaddr;
    irq_pf->len = (int32_t)LOW_32(d->fpga_cnfg->isr_len);
    irq_pf->cpid = (int32_t)LOW_32(d->fpga_cnfg->isr_pid);
    irq_pf->stream = HIGH_16((int32_t)HIGH_32(d->fpga_cnfg->isr)) && 0x3;
    irq_pf->wr = HIGH_16((int32_t)HIGH_32(d->fpga_cnfg->isr)) >> 8;
}

/**
 * @brief Drop the page fault, errored out somewhere
 *
 * @param d - vFPGA
 */
void fpga_drop_irq_pfault(struct fpga_dev *d, bool wr, int32_t cpid)
{
    d->fpga_cnfg->isr_pid = cpid; 
    d->fpga_cnfg->isr = wr ? FPGA_CNFG_CTRL_IRQ_PF_WR_DROP : FPGA_CNFG_CTRL_IRQ_PF_RD_DROP;
}

/**
 * @brief Restart the MMU
 *
 * @param d - vFPGA
 */
void fpga_restart_mmu(struct fpga_dev *d, bool wr, int32_t cpid)
{
    d->fpga_cnfg->isr_pid = cpid; 
    d->fpga_cnfg->isr = wr ? FPGA_CNFG_CTRL_IRQ_PF_WR_SUCCESS : FPGA_CNFG_CTRL_IRQ_PF_RD_SUCCESS;
}

/**
 * @brief Invalidate the TLBs
 *
 * @param d - vFPGA
 */
void fpga_invalidate(struct fpga_dev *d, uint64_t vaddr, uint32_t n_pages, int32_t hpid, bool last)
{
    d->fpga_cnfg->isr_pid = (uint64_t)hpid << 32;
    d->fpga_cnfg->isr_vaddr = vaddr << PAGE_SHIFT;
    d->fpga_cnfg->isr_len = ((uint64_t)n_pages) << PAGE_SHIFT;
    d->fpga_cnfg->isr = last ? FPGA_CNFG_CTRL_IRQ_INVLDT_LAST : FPGA_CNFG_CTRL_IRQ_INVLDT;
}

/**
 * @brief Lock the TLBs
 *
 * @param d - vFPGA
 */
void fpga_change_lock_tlb(struct fpga_dev *d)
{
    d->fpga_cnfg->isr = FPGA_CNFG_CTRL_IRQ_LOCK;
}

/**
 * @brief Allocate card memory
 * 
 * @param d - vFPGA
 * @param card_paddr - card physical address 
 * @param n_pages - number of pages to allocate
 * @param type - page size
 */
int card_alloc(struct fpga_dev *d, uint64_t *card_paddr, uint32_t n_pages, bool huge)
{
    int i;
    struct bus_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;

    // lock
    spin_lock(&pd->card_lock);

    if(huge) {
        if(pd->num_free_lchunks < n_pages) {
            dbg_info("not enough free huge card pages\n");
            return -ENOMEM;
        }

        for(i = 0; i < n_pages; i++) {
            pd->lalloc->used = true;
            card_paddr[i] = (pd->lalloc->id << pd->stlb_order->page_shift) + pd->card_huge_offs;
            pd->lalloc = pd->lalloc->next;
        }
    } else {
        if(pd->num_free_schunks < n_pages) {
            dbg_info("not enough free card pages\n");
            return -ENOMEM;
        }

        for(i = 0; i < n_pages; i++) {
            pd->salloc->used = true;
            card_paddr[i] = (pd->salloc->id << pd->stlb_order->page_shift) + pd->card_reg_offs;
            pd->salloc = pd->salloc->next;
        }
    }

    dbg_info("user card buffer allocated @ %llx, n_pages %d, huge %d, device %d\n", card_paddr[0], n_pages, huge, d->id);

    // unlock
    spin_unlock(&pd->card_lock);

    return 0;
}

/**
 * @brief Free card memory
 * 
 * @param d - vFPGA
 * @param card_paddr - card physical address 
 * @param n_pages - number of pages to free
 * @param type - page size
 */
void card_free(struct fpga_dev *d, uint64_t *card_paddr, uint32_t n_pages, bool huge)
{
    int i;
    uint64_t tmp_id;
    struct bus_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    // lock
    spin_lock(&pd->card_lock);

    if(huge) {
        for(i = n_pages - 1; i >= 0; i--) {
            tmp_id = (card_paddr[i] - pd->card_huge_offs) >> pd->stlb_order->page_shift;
            if(pd->lchunks[tmp_id].used) {
                pd->lchunks[tmp_id].next = pd->lalloc;
                pd->lalloc = &pd->lchunks[tmp_id];
            }
        }
    } else {
        for(i = n_pages - 1; i >= 0; i--) {
            tmp_id = (card_paddr[i] - pd->card_reg_offs) >> pd->stlb_order->page_shift;
            if(pd->schunks[tmp_id].used) {
                pd->schunks[tmp_id].next = pd->salloc;
                pd->salloc = &pd->schunks[tmp_id];
            }
        }
    }

    //dbg_info("user card buffer freed @ %llx, n_pages %d, huge %d, device %d\n", card_paddr[0], n_pages, huge, d->id);

    // unlock
    spin_unlock(&pd->card_lock);
}

 /**
 * @brief Page map list
 * 
 * @param vaddr - starting vaddr
 * @param padd - physical address
 * @param host - host/card flag
 * @param cpid - Coyote PID
 * @param hpid - host PID
 * @param entry - liste entry
 */
void tlb_create_map(struct fpga_dev *d, struct tlb_order *tlb_ord, uint64_t vaddr, uint64_t paddr, int32_t host, int32_t cpid, pid_t hpid)
{
    uint64_t key;
    uint64_t tag;
    uint64_t phys_addr;
    uint64_t entry [2];

    BUG_ON(!d);

    key = (vaddr >> (tlb_ord->page_shift - PAGE_SHIFT)) & tlb_ord->key_mask;
    tag = (vaddr >> (tlb_ord->page_shift - PAGE_SHIFT)) >> tlb_ord->key_size;
    phys_addr = (paddr >> tlb_ord->page_shift) & tlb_ord->phy_mask;

    // new entry
    entry[0] |= phys_addr | ((uint64_t)hpid << 32);
    entry[1] |= key | (tag            << (tlb_ord->key_size)) 
                    | ((uint64_t)cpid << (tlb_ord->key_size + tlb_ord->tag_size))
                    | ((uint64_t)host << (tlb_ord->key_size + tlb_ord->tag_size + PID_SIZE))
                    | (1UL            << (tlb_ord->key_size + tlb_ord->tag_size + PID_SIZE + STRM_SIZE))
                    | (phys_addr      << (tlb_ord->key_size + tlb_ord->tag_size + PID_SIZE + STRM_SIZE + 1));

    dbg_info("creating new TLB entry, vaddr_fa %llx, paddr %llx, strm %d, cpid %d, hpid %d, hugepage %d\n", vaddr, paddr, host, cpid, hpid, tlb_ord->hugepage);

    // map each page through AXIL
    if(tlb_ord->hugepage) {
        d->fpga_lTlb[0] = entry[0];
        d->fpga_lTlb[1] = entry[1];
    } else {
        d->fpga_sTlb[0] = entry[0];
        d->fpga_sTlb[1] = entry[1];
    }
}

/**
 * @brief Page unmap lists
 * 
 * @param vaddr - starting vaddr
 * @param cpid - Coyote PID
 * @param entry - list entry
 */
void tlb_create_unmap(struct fpga_dev *d, struct tlb_order *tlb_ord, uint64_t vaddr, pid_t hpid)
{
    uint64_t tag;
    uint64_t key;
    uint64_t entry [2];

    BUG_ON(!d);

    key = (vaddr >> (tlb_ord->page_shift - PAGE_SHIFT)) & tlb_ord->key_mask;
    tag = (vaddr >> (tlb_ord->page_shift - PAGE_SHIFT)) >> tlb_ord->key_size;

    // entry host
    entry[0] |= ((uint64_t)hpid << 32);
    entry[1] |= key | (tag << (tlb_ord->key_size)) 
                    | (0UL << (tlb_ord->key_size + tlb_ord->tag_size + PID_SIZE + STRM_SIZE));

    dbg_info("unmapping TLB entry, vaddr_fa %llx, hpid %d, hugepage %d\n", vaddr, hpid, tlb_ord->hugepage);

    // map each page through AXIL
    if(tlb_ord->hugepage) {
        d->fpga_lTlb[0] = entry[0];
        d->fpga_lTlb[1] = entry[1];
    } else {
        d->fpga_sTlb[0] = entry[0];
        d->fpga_sTlb[1] = entry[1];
    }
}

/**
 * @brief Start the offload
 * 
 * @param d - vFPGA
 * @param user_pg - mapping
 */
void dma_offload_start(struct fpga_dev *d, uint64_t *host_address, uint64_t *card_address, uint32_t n_pages, bool huge)
{
    int i = 0;
    struct bus_drvdata *pd;
    int cmd_sent = 0;
    uint32_t pg_inc;
    uint64_t len;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    pg_inc = huge ? MAX_SINGLE_DMA_SYNC : 1;
    len = huge ? (MAX_SINGLE_DMA_SYNC * PAGE_SIZE) : pd->stlb_order->page_size;

    for(i = 0; i < n_pages; i+=pg_inc) {
        if(host_address[i] == 0 || card_address[i] == 0)
            continue;

        while(cmd_sent >= DMA_THRSH) {
            cmd_sent = d->fpga_cnfg->offl_ctrl;
            usleep_range(DMA_MIN_SLEEP_CMD, DMA_MAX_SLEEP_CMD);
        }

        d->fpga_cnfg->offl_host_offs = host_address[i];
        d->fpga_cnfg->offl_card_offs = card_address[i];
        d->fpga_cnfg->offl_ctrl = (len << 32) | ((i == n_pages-pg_inc) ? DMA_CTRL_START_LAST : DMA_CTRL_START_MIDDLE);
        
        

        cmd_sent++;
    }
}

/**
 * @brief Start the offload
 * 
 * @param d - vFPGA
 * @param user_pg - mapping
 */
void dma_sync_start(struct fpga_dev *d, uint64_t *host_address, uint64_t *card_address, uint32_t n_pages, bool huge)
{
    int i = 0;
    struct bus_drvdata *pd;
    int cmd_sent = 0;
    uint32_t pg_inc;
    uint64_t len;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    pg_inc = huge ? MAX_SINGLE_DMA_SYNC : 1;
    len = huge ? (MAX_SINGLE_DMA_SYNC * PAGE_SIZE) : pd->stlb_order->page_size;

    for(i = 0; i < n_pages; i+=pg_inc) {
        while(cmd_sent >= DMA_THRSH) {
            cmd_sent = d->fpga_cnfg->sync_ctrl;
            usleep_range(DMA_MIN_SLEEP_CMD, DMA_MAX_SLEEP_CMD);
        }

        d->fpga_cnfg->sync_host_offs = host_address[i]; 
        d->fpga_cnfg->sync_card_offs = card_address[i];
        d->fpga_cnfg->sync_ctrl = (len << 32) | ((i == n_pages-pg_inc) ? DMA_CTRL_START_LAST : DMA_CTRL_START_MIDDLE);

        cmd_sent++;
    }
}