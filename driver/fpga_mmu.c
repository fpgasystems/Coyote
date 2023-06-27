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

#include "fpga_mmu.h"

/* User tables */
struct hlist_head user_lbuff_map[MAX_N_REGIONS][1 << (USER_HASH_TABLE_ORDER)]; // large alloc
struct hlist_head user_sbuff_map[MAX_N_REGIONS][1 << (USER_HASH_TABLE_ORDER)]; // main alloc

/* PR table */
struct hlist_head pr_buff_map[1 << (PR_HASH_TABLE_ORDER)];

/**
 * @brief ALlocate user buffers (used in systems without hugepage support)
 * 
 * @param d - vFPGA
 * @param n_pages - number of pages to allocate
 * @param cpid - Coyote PID
 */
int alloc_user_buffers(struct fpga_dev *d, unsigned long n_pages, int32_t cpid)
{
    int i, ret_val = 0;
    struct bus_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    if (d->curr_user_buff.n_hpages) {
        dbg_info("allocated user buffers exist and are not mapped\n");
        return -1;
    }

    // check host
    if (n_pages > MAX_BUFF_NUM) 
        d->curr_user_buff.n_hpages = MAX_BUFF_NUM;
    else
        d->curr_user_buff.n_hpages = n_pages;

    // check card
    if(pd->en_mem)
        if (d->curr_user_buff.n_hpages > pd->num_free_lchunks)
            return -ENOMEM;

    d->curr_user_buff.huge = true;
    d->curr_user_buff.cpid = cpid;

    // alloc host
    d->curr_user_buff.hpages = kzalloc(d->curr_user_buff.n_hpages * sizeof(*d->curr_user_buff.hpages), GFP_KERNEL);
    if (d->curr_user_buff.hpages == NULL) {
        return -ENOMEM;
    }
    dbg_info("allocated %llu bytes for page pointer array for %lld user host buffers @0x%p.\n",
             d->curr_user_buff.n_hpages * sizeof(*d->curr_user_buff.hpages), d->curr_user_buff.n_hpages, d->curr_user_buff.hpages);

    for (i = 0; i < d->curr_user_buff.n_hpages; i++) {
        d->curr_user_buff.hpages[i] = alloc_pages(GFP_ATOMIC, pd->ltlb_order->page_shift - PAGE_SHIFT);
        if (!d->curr_user_buff.hpages[i]) {
            dbg_info("user host buffer %d could not be allocated\n", i);
            goto fail_host_alloc;
        }

        dbg_info("user host buffer allocated @ %llx device %d\n", page_to_phys(d->curr_user_buff.hpages[i]), d->id);
    }

    // alloc card
    if(pd->en_mem) {
        d->curr_user_buff.n_pages = d->curr_user_buff.n_hpages;
        d->curr_user_buff.cpages = kzalloc(d->curr_user_buff.n_pages * sizeof(uint64_t), GFP_KERNEL);
        if (d->curr_user_buff.cpages == NULL) {
            return -ENOMEM;
        }
        dbg_info("allocated %llu bytes for page pointer array for %lld user card buffers @0x%p.\n",
                d->curr_user_buff.n_pages * sizeof(*d->curr_user_buff.cpages), d->curr_user_buff.n_pages, d->curr_user_buff.cpages);

        ret_val = card_alloc(d, d->curr_user_buff.cpages, d->curr_user_buff.n_pages, LARGE_CHUNK_ALLOC);
        if (ret_val) {
            dbg_info("user card buffer %d could not be allocated\n", i);
            goto fail_card_alloc;
        }
    }

    return 0;
fail_host_alloc:
    while (i)
        __free_pages(d->curr_user_buff.hpages[--i], pd->ltlb_order->page_shift - PAGE_SHIFT);

    d->curr_user_buff.n_hpages = 0;

    kfree(d->curr_user_buff.hpages);

    return -ENOMEM;

fail_card_alloc:
    // release host
    for (i = 0; i < d->curr_user_buff.n_hpages; i++)
        __free_pages(d->curr_user_buff.hpages[i], pd->ltlb_order->page_shift - PAGE_SHIFT);

    d->curr_user_buff.n_hpages = 0;
    d->curr_user_buff.n_pages = 0;

    kfree(d->curr_user_buff.hpages);
    kfree(d->curr_user_buff.cpages);

    return -ENOMEM;
}

/**
 * @brief Free user buffers
 * 
 * @param d - vFPGA
 * @param vaddr - virtual address 
 * @param cpid - Coyote PID
 */
int free_user_buffers(struct fpga_dev *d, uint64_t vaddr, int32_t cpid)
{
    int i;
    uint64_t vaddr_tmp;
    struct user_pages *tmp_buff;  
    uint64_t *map_array;
    struct bus_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    hash_for_each_possible(user_lbuff_map[d->id], tmp_buff, entry, vaddr) {

        if (tmp_buff->vaddr == vaddr && tmp_buff->cpid == cpid) {

            vaddr_tmp = tmp_buff->vaddr;

            // free host pages
            for (i = 0; i < tmp_buff->n_hpages; i++) {
                if (tmp_buff->hpages[i])
                    __free_pages(tmp_buff->hpages[i], pd->ltlb_order->page_shift - PAGE_SHIFT);
            }
            kfree(tmp_buff->hpages);

            // free card pages
            if(pd->en_mem) {
                card_free(d, tmp_buff->cpages, tmp_buff->n_pages, LARGE_CHUNK_ALLOC);
                kfree(tmp_buff->cpages);
            }

            // map array
            map_array = (uint64_t *)kzalloc(tmp_buff->n_hpages * 2 * sizeof(uint64_t), GFP_KERNEL);
            if (map_array == NULL) {
                dbg_info("map buffers could not be allocated\n");
                return -ENOMEM;
            }

            // fill mappings
            for (i = 0; i < tmp_buff->n_hpages; i++) {
                tlb_create_unmap(pd->ltlb_order, vaddr_tmp, cpid, &map_array[2*i]);
                vaddr_tmp += pd->ltlb_order->page_size;
            }

            // fire
            tlb_service_dev(d, pd->ltlb_order, map_array, tmp_buff->n_hpages);

            // free
            kfree((void *)map_array);

            // Free from hash
            hash_del(&tmp_buff->entry);
        }
    }

    return 0;
}

 /**
 * @brief Allocate PR buffers
 * 
 * @param d - vFPGA
 * @param n_pages - number of pages to allocate
 */
int alloc_pr_buffers(struct fpga_dev *d, unsigned long n_pages)
{
    int i;
    struct pr_ctrl *prc;
    struct bus_drvdata *pd;

    BUG_ON(!d);
    prc = d->prc;
    BUG_ON(!prc);
    pd = d->pd;
    BUG_ON(!pd);

    // obtain PR lock
    spin_lock(&prc->lock);

    if (prc->curr_buff.n_pages) {
        dbg_info("allocated PR buffers exist and are not mapped\n");
        return -1;
    }

    if (n_pages > MAX_PR_BUFF_NUM)
        prc->curr_buff.n_pages = MAX_PR_BUFF_NUM;
    else
        prc->curr_buff.n_pages = n_pages;

    prc->curr_buff.pages = kzalloc(n_pages * sizeof(*prc->curr_buff.pages), GFP_KERNEL);
    if (prc->curr_buff.pages == NULL) {
        return -ENOMEM;
    }

    dbg_info("allocated %lu bytes for page pointer array for %ld PR buffers @0x%p.\n",
             n_pages * sizeof(*prc->curr_buff.pages), n_pages, prc->curr_buff.pages);

    for (i = 0; i < prc->curr_buff.n_pages; i++) {
        prc->curr_buff.pages[i] = alloc_pages(GFP_ATOMIC, pd->ltlb_order->page_shift - PAGE_SHIFT);
        if (!prc->curr_buff.pages[i]) {
            dbg_info("PR buffer %d could not be allocated\n", i);
            goto fail_alloc;
        }

        dbg_info("PR buffer allocated @ %llx \n", page_to_phys(prc->curr_buff.pages[i]));
    }

    // release PR lock
    spin_unlock(&prc->lock);

    return 0;
fail_alloc:
    while (i)
        __free_pages(prc->curr_buff.pages[--i], pd->ltlb_order->page_shift - PAGE_SHIFT);
    // release PR lock
    spin_unlock(&prc->lock);
    return -ENOMEM;
}

/**
 * @brief Free PR pages
 * 
 * @param d - vFPGA
 * @param vaddr - virtual address
 */
int free_pr_buffers(struct fpga_dev *d, uint64_t vaddr)
{
    int i;
    struct pr_pages *tmp_buff;
    struct pr_ctrl *prc;
    struct bus_drvdata *pd;

    BUG_ON(!d);
    prc = d->prc;   
    BUG_ON(!prc);
    pd = d->pd;
    BUG_ON(!pd);

    // obtain PR lock
    spin_lock(&prc->lock);

    hash_for_each_possible(pr_buff_map, tmp_buff, entry, vaddr) {
        if (tmp_buff->vaddr == vaddr && tmp_buff->reg_id == d->id) {

            // free pages
            for (i = 0; i < tmp_buff->n_pages; i++) {
                if (tmp_buff->pages[i])
                    __free_pages(tmp_buff->pages[i], pd->ltlb_order->page_shift - PAGE_SHIFT);
            }

            kfree(tmp_buff->pages);

            // Free from hash
            hash_del(&tmp_buff->entry);
        }
    }

    // obtain PR lock
    spin_unlock(&prc->lock);

    return 0;
}

/**
 * @brief Allocate card memory
 * 
 * @param d - vFPGA
 * @param card_paddr - card physical address 
 * @param n_pages - number of pages to allocate
 * @param type - page size
 */
int card_alloc(struct fpga_dev *d, uint64_t *card_paddr, uint64_t n_pages, int type)
{
    int i;
    struct bus_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;

    switch (type) {
    case 0: //
        // lock
        spin_lock(&pd->card_s_lock);

        if(pd->num_free_schunks < n_pages) {
            dbg_info("not enough free small card pages\n");
            return -ENOMEM;
        }

        for(i = 0; i < n_pages; i++) {
            pd->salloc->used = true;
            card_paddr[i] = pd->salloc->id << STLB_PAGE_BITS;
            dbg_info("user card buffer allocated @ %llx device %d\n", card_paddr[i], d->id);
            pd->salloc = pd->salloc->next;
        }

        // release lock
        spin_unlock(&pd->card_s_lock);

        break;
    case 1:
        // lock
        spin_lock(&pd->card_l_lock);

        if(pd->num_free_lchunks < n_pages) {
            dbg_info("not enough free large card pages\n");
            return -ENOMEM;
        }

        for(i = 0; i < n_pages; i++) {
            pd->lalloc->used = true;
            card_paddr[i] = (pd->lalloc->id << LTLB_PAGE_BITS) + MEM_SEP;
            dbg_info("user card buffer allocated @ %llx device %d\n", card_paddr[i], d->id);
            pd->lalloc = pd->lalloc->next;
        }

        // release lock
        spin_unlock(&pd->card_l_lock);

        break;
    default: // TODO: Shared mem
        break;
    }

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
void card_free(struct fpga_dev *d, uint64_t *card_paddr, uint64_t n_pages, int type)
{
    int i;
    uint64_t tmp_id;
    struct bus_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    switch (type) {
    case 0: // small pages
        // lock
        spin_lock(&pd->card_s_lock);

        for(i = n_pages - 1; i >= 0; i--) {
            tmp_id = card_paddr[i] >> STLB_PAGE_BITS;
            if(pd->schunks[tmp_id].used) {
                pd->schunks[tmp_id].next = pd->salloc;
                pd->salloc = &pd->schunks[tmp_id];
            }
        }

        // release lock
        spin_unlock(&pd->card_s_lock);

        break;
    case 1: // large pages
        // lock
        spin_lock(&pd->card_l_lock);

        for(i = n_pages - 1; i >= 0; i--) {
            tmp_id = (card_paddr[i] - MEM_SEP) >> LTLB_PAGE_BITS;
            if(pd->lchunks[tmp_id].used) {
                pd->lchunks[tmp_id].next = pd->lalloc;
                pd->lalloc = &pd->lchunks[tmp_id];
            }
        }

        // release lock
        spin_unlock(&pd->card_l_lock);

        break;
    default:
        break;
    }
}

 /**
 * @brief Page map list
 * 
 * @param vaddr - starting vaddr
 * @param paddr_host - host physical address
 * @param paddr_card - card physical address
 * @param cpid - Coyote PID
 * @param entry - liste entry
 */
void tlb_create_map(struct tlb_order *tlb_ord, uint64_t vaddr, uint64_t paddr_host, uint64_t paddr_card, int32_t cpid, uint64_t *entry)
{
    uint64_t key;
    uint64_t tag;
    uint64_t phost;
    uint64_t pcard;

    key = (vaddr >> tlb_ord->page_shift) & tlb_ord->key_mask;
    tag = vaddr >> (tlb_ord->page_shift + tlb_ord->key_size);
    phost = (paddr_host >> tlb_ord->page_shift) & tlb_ord->phy_mask;
    pcard = (paddr_card >> tlb_ord->page_shift) & tlb_ord->phy_mask;

    // new entry
    entry[0] |= key | 
                (tag << tlb_ord->key_size) | 
                ((uint64_t)cpid << (tlb_ord->key_size + tlb_ord->tag_size)) | 
                (1UL << (tlb_ord->key_size + tlb_ord->tag_size + PID_SIZE));
    entry[1] |= phost | (pcard << tlb_ord->phy_size);

    dbg_info("creating new TLB entry, vaddr %llx, phost %llx, pcard %llx, cpid %d, hugepage %d\n", vaddr, paddr_host, paddr_card, cpid, tlb_ord->hugepage);
}

/**
 * @brief Page unmap lists
 * 
 * @param vaddr - starting vaddr
 * @param cpid - Coyote PID
 * @param entry - list entry
 */
void tlb_create_unmap(struct tlb_order *tlb_ord, uint64_t vaddr, int32_t cpid, uint64_t *entry)
{
    uint64_t tag;
    uint64_t key;

    key = (vaddr >> tlb_ord->page_shift) & tlb_ord->key_mask;
    tag = vaddr >> (tlb_ord->page_shift + tlb_ord->key_size);

    // entry host
    entry[0] |= key | 
                (tag << tlb_ord->key_size) | 
                ((uint64_t)cpid << (tlb_ord->key_size + tlb_ord->tag_size)) | 
                (0UL << (tlb_ord->key_size + tlb_ord->tag_size + PID_SIZE));
    entry[1] |= 0;

    dbg_info("unmapping TLB entry, vaddr %llx, cpid %d, hugepage %d\n", vaddr, cpid, tlb_ord->hugepage);
}

/**
 * @brief Map TLB
 * 
 * @param d - vFPGA
 * @param en_tlbf - TLBF enabled
 * @param map_array - prepped map array
 * @param paddr - physical address
 * @param cpid - Coyote PID
 * @param card - map card mem as well
 */
void tlb_service_dev(struct fpga_dev *d, struct tlb_order *tlb_ord, uint64_t* map_array, uint32_t n_pages)
{
    int i = 0;
    struct bus_drvdata *pd;

    BUG_ON(!d); 
    pd = d->pd;
    BUG_ON(!pd);

    if(pd->en_tlbf && (n_pages > MAX_MAP_AXIL_PAGES)) {
        // lock
        spin_lock(&pd->tlb_lock);

        // start DMA
        pd->fpga_stat_cnfg->tlb_addr = virt_to_phys((void *)map_array);
        pd->fpga_stat_cnfg->tlb_len = n_pages * 2 * sizeof(uint64_t);
        if(tlb_ord->hugepage) {
            pd->fpga_stat_cnfg->tlb_ctrl = TLBF_CTRL_START | ((d->id && TLBF_CTRL_ID_MASK) << TLBF_CTRL_ID_SHFT);
        } else {
            pd->fpga_stat_cnfg->tlb_ctrl = TLBF_CTRL_START | (((pd->n_fpga_reg + d->id) && TLBF_CTRL_ID_MASK) << TLBF_CTRL_ID_SHFT);
        }

        // poll
        while ((pd->fpga_stat_cnfg->tlb_stat & TLBF_STAT_DONE) != 0x1)
            ndelay(100);
        
        // unlock
        spin_unlock(&pd->tlb_lock);
    } else {
        // map each page through AXIL
        for (i = 0; i < n_pages; i++) {
            if(tlb_ord->hugepage) {
                d->fpga_lTlb[0] = map_array[2*i+0];
                d->fpga_lTlb[1] = map_array[2*i+1];
            } else {
                d->fpga_sTlb[0] = map_array[2*i+0];
                d->fpga_sTlb[1] = map_array[2*i+1];
            }
        }
    }
}

/**
 * @brief Release all remaining user pages
 * 
 * @param d - vFPGA
 * @param dirtied - modified
 */
int tlb_put_user_pages_all(struct fpga_dev *d, int dirtied)
{
    int i, bkt;
    struct user_pages *tmp_buff;
    uint64_t vaddr_tmp;
    int32_t cpid_tmp;
    uint64_t *map_array;
    struct bus_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    hash_for_each(user_sbuff_map[d->id], bkt, tmp_buff, entry) {
        
        // release host pages
        if(dirtied)
            for(i = 0; i < tmp_buff->n_hpages; i++)
                SetPageDirty(tmp_buff->hpages[i]);

        for(i = 0; i < tmp_buff->n_hpages; i++)
            put_page(tmp_buff->hpages[i]);

        kfree(tmp_buff->hpages);

        // release card pages
        if(pd->en_mem) {
            if(tmp_buff->huge)
                card_free(d, tmp_buff->cpages, tmp_buff->n_pages, LARGE_CHUNK_ALLOC);
            else
                card_free(d, tmp_buff->cpages, tmp_buff->n_pages, SMALL_CHUNK_ALLOC);
        }

        // unmap from TLB
        vaddr_tmp = tmp_buff->vaddr;
        cpid_tmp = tmp_buff->cpid;

        // map array
        map_array = (uint64_t *)kzalloc(tmp_buff->n_pages * 2 * sizeof(uint64_t), GFP_KERNEL);
        if (map_array == NULL) {
            dbg_info("map buffers could not be allocated\n");
            return -ENOMEM;
        }

        // huge pages
        if(tmp_buff->huge) {
            // fill mappings
            for (i = 0; i < tmp_buff->n_pages; i++) {
                tlb_create_unmap(pd->ltlb_order, vaddr_tmp, cpid_tmp, &map_array[2*i]);
                vaddr_tmp += pd->ltlb_order->page_size;
            }

            // fire
            tlb_service_dev(d, pd->ltlb_order, map_array, tmp_buff->n_pages);

        // small pages
        } else {
            // fill mappings
            for (i = 0; i < tmp_buff->n_pages; i++) {
                tlb_create_unmap(pd->stlb_order, vaddr_tmp, cpid_tmp, &map_array[2*i]);
                vaddr_tmp += PAGE_SIZE;
            }

            // fire
            tlb_service_dev(d, pd->stlb_order, map_array, tmp_buff->n_pages);
        }

        // free
        kfree((void *)map_array);

        // remove from map
        hash_del(&tmp_buff->entry);
    }

    return 0;
}

/**
 * @brief Release user pages (cpid)
 * 
 * @param d - vFPGA
 * @param cpid - Coyote PID
 * @param dirtied - modified
 */
int tlb_put_user_pages_cpid(struct fpga_dev *d, int32_t cpid, int dirtied)
{
    int i, bkt;
    struct user_pages *tmp_buff;
    uint64_t vaddr_tmp;
    uint64_t *map_array;
    struct bus_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    hash_for_each(user_sbuff_map[d->id], bkt, tmp_buff, entry) {
        if(tmp_buff->cpid == cpid) {

            // release host pages
            if(dirtied)
                for(i = 0; i < tmp_buff->n_hpages; i++)
                    SetPageDirty(tmp_buff->hpages[i]);

            for(i = 0; i < tmp_buff->n_hpages; i++)
                put_page(tmp_buff->hpages[i]);

            kfree(tmp_buff->hpages);

            // release card pages
            if(pd->en_mem) {
                if(tmp_buff->huge)
                    card_free(d, tmp_buff->cpages, tmp_buff->n_pages, LARGE_CHUNK_ALLOC);
                else
                    card_free(d, tmp_buff->cpages, tmp_buff->n_pages, SMALL_CHUNK_ALLOC);
            }

            // unmap from TLB
            vaddr_tmp = tmp_buff->vaddr;

            // map array
            map_array = (uint64_t *)kzalloc(tmp_buff->n_pages * 2 * sizeof(uint64_t), GFP_KERNEL);
            if (map_array == NULL) {
                dbg_info("map buffers could not be allocated\n");
                return -ENOMEM;
            }

            // huge pages
            if(tmp_buff->huge) {
                // fill mappings
                for (i = 0; i < tmp_buff->n_pages; i++) {
                    tlb_create_unmap(pd->ltlb_order, vaddr_tmp, cpid, &map_array[2*i]);
                    vaddr_tmp += pd->ltlb_order->page_size;
                }

                // fire
                tlb_service_dev(d, pd->ltlb_order, map_array, tmp_buff->n_pages);

            // small pages
            } else {
                // fill mappings
                for (i = 0; i < tmp_buff->n_pages; i++) {
                    tlb_create_unmap(pd->stlb_order, vaddr_tmp, cpid, &map_array[2*i]);
                    vaddr_tmp += PAGE_SIZE;
                }

                // fire
                tlb_service_dev(d, pd->stlb_order, map_array, tmp_buff->n_pages);
            }

            // free
            kfree((void *)map_array);

            // remove from map
            hash_del(&tmp_buff->entry);
        }
    }

    return 0;
}

/**
 * @brief Release user pages
 * 
 * @param d - vFPGA
 * @param vaddr - starting vaddr
 * @param cpid - Coyote PID
 * @param dirtied - modified
 */
int tlb_put_user_pages(struct fpga_dev *d, uint64_t vaddr, int32_t cpid, int dirtied)
{
    int i;
    struct user_pages *tmp_buff;
    uint64_t vaddr_tmp;
    uint64_t *map_array;
    struct bus_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    hash_for_each_possible(user_sbuff_map[d->id], tmp_buff, entry, vaddr) {
        if(tmp_buff->vaddr == vaddr && tmp_buff->cpid == cpid) {

            // release host pages
            if(dirtied)
                for(i = 0; i < tmp_buff->n_hpages; i++)
                    SetPageDirty(tmp_buff->hpages[i]);

            for(i = 0; i < tmp_buff->n_hpages; i++)
                put_page(tmp_buff->hpages[i]);

            kfree(tmp_buff->hpages);

            // release card pages
            if(pd->en_mem) {
                if(tmp_buff->huge)
                    card_free(d, tmp_buff->cpages, tmp_buff->n_pages, LARGE_CHUNK_ALLOC);
                else
                    card_free(d, tmp_buff->cpages, tmp_buff->n_pages, SMALL_CHUNK_ALLOC);
            }

            // unmap from TLB
            vaddr_tmp = vaddr;

            // map array
            map_array = (uint64_t *)kzalloc(tmp_buff->n_pages * 2 * sizeof(uint64_t), GFP_KERNEL);
            if (map_array == NULL) {
                dbg_info("map buffers could not be allocated\n");
                return -ENOMEM;
            }

            // huge pages
            if(tmp_buff->huge) {
                // fill mappings
                for (i = 0; i < tmp_buff->n_pages; i++) {
                    tlb_create_unmap(pd->ltlb_order, vaddr_tmp, cpid, &map_array[2*i]);
                    vaddr_tmp += pd->ltlb_order->page_size;
                }

                // fire
                tlb_service_dev(d, pd->ltlb_order, map_array, tmp_buff->n_pages);

            // small pages
            } else {
                // fill mappings
                for (i = 0; i < tmp_buff->n_pages; i++) {
                    tlb_create_unmap(pd->stlb_order, vaddr_tmp, cpid, &map_array[2*i]);
                    vaddr_tmp += PAGE_SIZE;
                }

                // fire
                tlb_service_dev(d, pd->stlb_order, map_array, tmp_buff->n_pages);
            }

            // free
            kfree((void *)map_array);

            // remove from map
            hash_del(&tmp_buff->entry);
        }
    }

    return 0;
}

/** 
 * @brief Get user pages and fill TLB
 * 
 * @param d - vFPGA
 * @param start - starting vaddr
 * @param count - number of pages to map
 * @param cpid - Coyote PID
 * @param pid - user PID
 */
int tlb_get_user_pages(struct fpga_dev *d, uint64_t start, size_t count, int32_t cpid, pid_t pid)
{
    int ret_val = 0, i, j;
    int n_pages, n_pages_huge;
    uint64_t first;
    uint64_t last;
    struct user_pages *user_pg;
    struct vm_area_struct *vma_area_init;
    int hugepages;
    uint64_t *hpages_phys;
    uint64_t curr_vaddr, last_vaddr;
    struct task_struct *curr_task;
    struct mm_struct *curr_mm;
    uint64_t *map_array;
    uint64_t vaddr_tmp;
    struct bus_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    // context
    curr_task = pid_task(find_vpid(pid), PIDTYPE_PID);
    dbg_info("pid found = %d", pid);
    curr_mm = curr_task->mm;

    // hugepages?
    vma_area_init = find_vma(curr_mm, start);
    hugepages = is_vm_hugetlb_page(vma_area_init);

    // number of pages
    first = (start & PAGE_MASK) >> PAGE_SHIFT;
    last = ((start + count - 1) & PAGE_MASK) >> PAGE_SHIFT;
    n_pages = last - first + 1;

    if(hugepages) {
        if(n_pages > MAX_N_MAP_HUGE_PAGES)
            n_pages = MAX_N_MAP_HUGE_PAGES;
    } else {
        if(n_pages > MAX_N_MAP_PAGES)
            n_pages = MAX_N_MAP_PAGES;
    }

    if (start + count < start)
        return -EINVAL;
    if (count == 0)
        return 0;

    // alloc
    user_pg = kzalloc(sizeof(struct user_pages), GFP_KERNEL);
    BUG_ON(!user_pg);

    user_pg->hpages = kcalloc(n_pages, sizeof(*user_pg->hpages), GFP_KERNEL);
    if (user_pg->hpages == NULL) {
        return -1;
    }
    dbg_info("allocated %lu bytes for page pointer array for %d pages @0x%p, passed size %ld.\n",
             n_pages * sizeof(*user_pg->hpages), n_pages, user_pg->hpages, count);

    dbg_info("pages=0x%p\n", user_pg->hpages);
    dbg_info("first = %llx, last = %llx\n", first, last);

    for (i = 0; i < n_pages - 1; i++) {
        user_pg->hpages[i] = NULL;
    }

    // pin
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5,9,0)
    ret_val = get_user_pages_remote(curr_mm, (unsigned long)start, n_pages, 1, user_pg->hpages, NULL, NULL);
#else 
    ret_val = get_user_pages_remote(curr_task, curr_mm, (unsigned long)start, n_pages, 1, user_pg->hpages, NULL, NULL);
#endif
    //ret_val = pin_user_pages_remote(curr_mm, (unsigned long)start, n_pages, 1, user_pg->hpages, NULL, NULL);
    dbg_info("get_user_pages_remote(%llx, n_pages = %d, page start = %lx, hugepages = %d)\n", start, n_pages, page_to_pfn(user_pg->hpages[0]), hugepages);

    if(ret_val < n_pages) {
        dbg_info("could not get all user pages, %d\n", ret_val);
        goto fail_host_unmap;
    }

    // flush cache
    for(i = 0; i < n_pages; i++)
        flush_dcache_page(user_pg->hpages[i]);

    // add mapped entry
    user_pg->vaddr = start;
    user_pg->n_hpages = n_pages;
    user_pg->huge = hugepages;

    vaddr_tmp = start;

    // huge pages
    if (hugepages) {
        first = (start & pd->ltlb_order->page_mask) >> pd->ltlb_order->page_shift;
        last = ((start + count - 1) & pd->ltlb_order->page_mask) >> pd->ltlb_order->page_shift;
        n_pages_huge = last - first + 1;
        user_pg->n_pages = n_pages_huge;

        // prep hpages
        hpages_phys = kzalloc(n_pages_huge * sizeof(uint64_t), GFP_KERNEL);
        if (hpages_phys == NULL) {
            dbg_info("card buffer %d could not be allocated\n", i);
            return -ENOMEM;
        }

        j = 0;
        curr_vaddr = start;
        last_vaddr = -1;
        for (i = 0; i < n_pages; i++) {
            if (((curr_vaddr & pd->ltlb_order->page_mask) >> pd->ltlb_order->page_shift) != ((last_vaddr & pd->ltlb_order->page_mask) >> pd->ltlb_order->page_shift)) {
                hpages_phys[j] = page_to_phys(user_pg->hpages[i]) & pd->ltlb_order->page_mask;
                dbg_info("hugepage %d at %llx\n", j, hpages_phys[j]);
                last_vaddr = curr_vaddr;
                j++;
            }
            curr_vaddr += PAGE_SIZE;
        }

        // card alloc
        if(pd->en_mem) {
            user_pg->cpages = kzalloc(n_pages_huge * sizeof(uint64_t), GFP_KERNEL);
            if (user_pg->cpages == NULL) {
                dbg_info("card buffer %d could not be allocated\n", i);
                return -ENOMEM;
            }

            ret_val = card_alloc(d, user_pg->cpages, n_pages_huge, LARGE_CHUNK_ALLOC);
            if (ret_val) {
                dbg_info("could not get all card pages, %d\n", ret_val);
                goto fail_card_unmap;
            }
            dbg_info("card allocated %d hugepages\n", n_pages_huge);
        }

        // map array
        map_array = (uint64_t *)kzalloc(n_pages_huge * 2 * sizeof(uint64_t), GFP_KERNEL);
        if (map_array == NULL) {
            dbg_info("map buffers could not be allocated\n");
            return -ENOMEM;
        }

        // fill mappings
        for (i = 0; i < n_pages_huge; i++) {
            tlb_create_map(pd->ltlb_order, vaddr_tmp, hpages_phys[i], (pd->en_mem ? user_pg->cpages[i] : 0), cpid, &map_array[2*i]);
            vaddr_tmp += pd->ltlb_order->page_size;
        }

        // fire
        tlb_service_dev(d, pd->ltlb_order, map_array, n_pages_huge);

        // free
        kfree((void *)map_array);
    
    // small pages
    } else {
        user_pg->n_pages = n_pages;

        // card alloc
        if(pd->en_mem) {
            user_pg->cpages = kzalloc(n_pages * sizeof(uint64_t), GFP_KERNEL);
            if (user_pg->cpages == NULL) {
                dbg_info("card buffer %d could not be allocated\n", i);
                return -ENOMEM;
            }

            ret_val = card_alloc(d, user_pg->cpages, n_pages, SMALL_CHUNK_ALLOC);
            if (ret_val) {
                dbg_info("could not get all card pages, %d\n", ret_val);
                goto fail_card_unmap;
            }
            dbg_info("card allocated %d regular pages\n", n_pages);
        }

        // map array
        map_array = (uint64_t *)kzalloc(n_pages * 2 * sizeof(uint64_t), GFP_KERNEL);
        if (map_array == NULL) {
            dbg_info("map buffers could not be allocated\n");
            return -ENOMEM;
        }

        // fill mappings
        for (i = 0; i < n_pages; i++) {
            tlb_create_map(pd->stlb_order, vaddr_tmp, page_to_phys(user_pg->hpages[i]), (pd->en_mem ? user_pg->cpages[i] : 0), cpid, &map_array[2*i]);
            vaddr_tmp += PAGE_SIZE;
        }

        // fire
        tlb_service_dev(d, pd->stlb_order, map_array, n_pages);

        // free
        kfree((void *)map_array);
    }

    hash_add(user_sbuff_map[d->id], &user_pg->entry, start);

    return n_pages;

fail_host_unmap:
    // release host pages
    for(i = 0; i < ret_val; i++) {
        put_page(user_pg->hpages[i]);
    }

    kfree(user_pg->hpages);

    return -ENOMEM;

fail_card_unmap:
    // release host pages
    for(i = 0; i < user_pg->n_hpages; i++) {
        put_page(user_pg->hpages[i]);
    }

    kfree(user_pg->hpages);
    kfree(user_pg->cpages);

    return -ENOMEM;
}