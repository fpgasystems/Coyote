
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

#include "fpga_gup.h"

/*
███╗   ███╗███╗   ███╗██╗   ██╗
████╗ ████║████╗ ████║██║   ██║
██╔████╔██║██╔████╔██║██║   ██║
██║╚██╔╝██║██║╚██╔╝██║██║   ██║
██║ ╚═╝ ██║██║ ╚═╝ ██║╚██████╔╝
╚═╝     ╚═╝╚═╝     ╚═╝ ╚═════╝ 
*/

/* Hash tables */
struct hlist_head user_buff_map[MAX_N_REGIONS][N_CPID_MAX][1 << (USER_HASH_TABLE_ORDER)]; // main alloc

/**
 * @brief The mmu handler does the heavy lifting in case of a page fault.
 * Takes the page fault struct and handles it.
 * 
 * @param d - vFPGA
 * @param pf - read page fault
 * @param hpid - host pid
 */
int mmu_handler_gup(struct fpga_dev *d, uint64_t vaddr, uint64_t len, int32_t cpid, int32_t stream, pid_t hpid)
{
    int ret_val = 0;
    struct user_pages *user_pg;
    struct bus_drvdata *pd = d->pd;
    struct desc_aligned pfa;
    uint64_t last;
    struct tlb_order *tlb_order;
    struct task_struct *curr_task;
    struct mm_struct *curr_mm;
    struct vm_area_struct *vma_area_init;
    int hugepages;

    // context
    curr_task = pid_task(find_vpid(hpid), PIDTYPE_PID);
    dbg_info("hpid found = %d", hpid);
    curr_mm = curr_task->mm;

    // hugepages?
    vma_area_init = find_vma(curr_mm, vaddr);
    hugepages = is_vm_hugetlb_page(vma_area_init);
    tlb_order = hugepages ? pd->ltlb_order : pd->stlb_order;

    // align and shift (PAGE_SIZE)
    pfa.vaddr = (vaddr & tlb_order->page_mask) >> tlb_order->page_shift;
    last = ((vaddr + len - 1) & tlb_order->page_mask) >> tlb_order->page_shift;
    pfa.n_pages = last - pfa.vaddr + 1;
    
    if (hugepages) {
        pfa.n_pages = pfa.n_pages * pd->n_pages_in_huge;
        pfa.vaddr = pfa.vaddr << pd->dif_order_page_shift;
    }
    pfa.cpid = cpid;
    pfa.hugepages = hugepages;

    // check user buff map
    user_pg = map_present(d, &pfa);

    if(user_pg) {
        if(stream == HOST_ACCESS) {
            if(user_pg->host == HOST_ACCESS) {
                dbg_info("host access, map present, updating TLB\n");
                tlb_map_gup(d, &pfa, user_pg, hpid);
            } else {
                dbg_info("card access, map present, migration\n");
                tlb_unmap_gup(d, user_pg, hpid);
                user_pg->host = HOST_ACCESS;
                migrate_to_host_gup(d, user_pg);
                tlb_map_gup(d, &pfa, user_pg, hpid);
            }
        } else if(stream == CARD_ACCESS) {
            if(user_pg->host == HOST_ACCESS) {
                dbg_info("host access, map present, migration\n");
                tlb_unmap_gup(d, user_pg, hpid);
                user_pg->host = CARD_ACCESS;
                migrate_to_card_gup(d, user_pg);
                tlb_map_gup(d, &pfa, user_pg, hpid);
            } else {
                dbg_info("card access, map present, updating TLB\n");
                tlb_map_gup(d, &pfa, user_pg, hpid);
            }
        } else {
            ret_val = -EINVAL;
            pr_err("access not supported, vFPGA %d\n", d->id);
        }
    } else {
        dbg_info("map not present\n");
        user_pg = tlb_get_user_pages(d, &pfa, hpid, curr_task, curr_mm);
        if(!user_pg) {
            pr_err("user pages could not be obtained\n");
            return -ENOMEM;
        }

       if(stream) {  
           tlb_map_gup(d, &pfa, user_pg, hpid);           
       } else {
           user_pg->host = CARD_ACCESS;
           migrate_to_card_gup(d, user_pg);
           tlb_map_gup(d, &pfa, user_pg, hpid);
       }
    }

    return ret_val;
}

/**
 * @brief Check if mapping is already present
 * 
 * @param d - vFPGA
 * @param pfa - aligned read page fault
 * @param user_pg - mapping
*/
struct user_pages* map_present(struct fpga_dev *d, struct desc_aligned *pfa) 
{
    int bkt;
    struct user_pages *tmp_entry;

    // hash
    hash_for_each(user_buff_map[d->id][pfa->cpid], bkt, tmp_entry, entry) {
        if(pfa->vaddr >= tmp_entry->vaddr && pfa->vaddr < tmp_entry->vaddr + tmp_entry->n_pages) {
            // hit
            if(pfa->vaddr + pfa->n_pages > tmp_entry->vaddr + tmp_entry->n_pages)
                pfa->n_pages =  tmp_entry->vaddr + tmp_entry->n_pages - pfa->vaddr;

            return tmp_entry;
        } else if(pfa->vaddr < tmp_entry->vaddr && pfa->vaddr + pfa->n_pages > tmp_entry->vaddr) {
            // partial
            pfa->n_pages = tmp_entry->vaddr - pfa->vaddr;
        }
    }

    return 0;
}

/**
 * @brief Create a TLB mapping
 * 
 * @param d - vFPGA
 * @param pfa - aligned read page fault
 * @param user_pg - mapping
 * @param hpid - host pid
*/
void tlb_map_gup(struct fpga_dev *d, struct desc_aligned *pfa, struct user_pages *user_pg, pid_t hpid) 
{
    int i, j;
    uint64_t pg_offs;
    uint64_t first_pfa, first_user;
    uint32_t n_pages;
    uint64_t vaddr_tmp;
    uint64_t paddr_tmp, paddr_curr;
    bool is_huge;
    int32_t n_pg_mapped = 0;
    struct bus_drvdata *pd = d->pd;

    first_pfa = pfa->vaddr;
    first_user = user_pg->vaddr;
    pg_offs = first_pfa - first_user;
    n_pages = pfa->n_pages;

    vaddr_tmp = first_pfa;

    if(user_pg->huge) {
        // fill mappings - huge
        for (i = 0; (i < n_pages) && (n_pg_mapped < MAX_N_MAP_PAGES); i+=pd->n_pages_in_huge) {
            tlb_create_map(d, pd->ltlb_order, vaddr_tmp, 
                (user_pg->host == HOST_ACCESS) ? user_pg->hpages[i + pg_offs] : user_pg->cpages[i + pg_offs],
                user_pg->host, user_pg->cpid, hpid);

            vaddr_tmp += pd->n_pages_in_huge;
            n_pg_mapped++;
        }
    } else {
        // fill mappings - regular (+coalesced)
        i = 0;
        while((i < n_pages) && (n_pg_mapped < MAX_N_MAP_PAGES)) {
            // coalesce
            is_huge = false;
            if(n_pages >= pd->n_pages_in_huge) {
                if(i <= n_pages - pd->n_pages_in_huge) {
                    if((vaddr_tmp & pd->dif_order_page_mask) == 0) {
                        paddr_tmp = (user_pg->host == HOST_ACCESS) ? user_pg->hpages[i + pg_offs] : user_pg->cpages[i + pg_offs];
                        if((paddr_tmp & ~pd->ltlb_order->page_mask) == 0) {
                            is_huge = true; 
                            for(j = i + 1; j < i + pd->n_pages_in_huge; j++) {
                                paddr_curr = (user_pg->host == HOST_ACCESS) ? user_pg->hpages[j + pg_offs] : user_pg->cpages[j + pg_offs];
                                if(paddr_curr != paddr_tmp + PAGE_SIZE) {
                                    is_huge = false;
                                    break;
                                } else {
                                    paddr_tmp = paddr_curr;
                                }
                            }
                        }
                    }
                }
            }

            // fill mappings
            tlb_create_map(d, is_huge ? pd->ltlb_order : pd->stlb_order, vaddr_tmp, 
            (user_pg->host == HOST_ACCESS) ? user_pg->hpages[i + pg_offs] : user_pg->cpages[i + pg_offs],
            user_pg->host, user_pg->cpid, hpid);

            vaddr_tmp += is_huge ? pd->n_pages_in_huge : 1;
            i += is_huge ? pd->n_pages_in_huge : 1;
            n_pg_mapped++;
        }
    }
}

/**
 * @brief Create unmapping
 * 
 * @param d - vFPGA
 * @param user_pg - mapping
 * @param hpid - host pid
*/
void tlb_unmap_gup(struct fpga_dev *d, struct user_pages *user_pg, pid_t hpid) 
{
    int i, j;
    uint32_t n_pages;
    uint64_t vaddr_tmp;
    uint64_t paddr_tmp, paddr_curr;
    bool is_huge;
    int32_t pg_inc;
    struct bus_drvdata *pd = d->pd;

    n_pages = user_pg->n_pages;
    pg_inc = user_pg->huge ? pd->n_pages_in_huge : 1;

    vaddr_tmp = user_pg->vaddr;

    if(user_pg->huge) {
        // unmap - huge
        for (i = 0; i < n_pages; i+=pd->n_pages_in_huge) {
            tlb_create_unmap(d, pd->ltlb_order, vaddr_tmp, hpid);
            
            vaddr_tmp += pd->n_pages_in_huge;
        }
    } else {
        // unmap - regular (+coalesced)
        i = 0;
        while((i < n_pages)) {
            // coalesce
            is_huge = false;
            if(n_pages >= pd->n_pages_in_huge) {
                if(i <= n_pages - pd->n_pages_in_huge) {
                    if((vaddr_tmp & pd->dif_order_page_mask) == 0) {
                        paddr_tmp = (user_pg->host == HOST_ACCESS) ? user_pg->hpages[i] : user_pg->cpages[i];
                        if((paddr_tmp & ~pd->ltlb_order->page_mask) == 0) {
                            is_huge = true; 
                            for(j = i + 1; j < i + pd->n_pages_in_huge; j++) {
                                paddr_curr = (user_pg->host == HOST_ACCESS) ? user_pg->hpages[j] : user_pg->cpages[j];
                                if(paddr_curr != paddr_tmp + PAGE_SIZE) {
                                    is_huge = false;
                                    break;
                                } else {
                                    paddr_tmp = paddr_curr;
                                }
                            }
                        }
                    }
                }
            }

            // unmap
            tlb_create_unmap(d, is_huge ? pd->ltlb_order : pd->stlb_order, vaddr_tmp, hpid);
            
            vaddr_tmp += is_huge ? pd->n_pages_in_huge : 1;
            i += is_huge ? pd->n_pages_in_huge : 1;
        }
    }
    
    // invalidate command
    vaddr_tmp = user_pg->vaddr;
    for (i = 0; i < n_pages; i += pg_inc) {
        fpga_invalidate(d, vaddr_tmp, pg_inc, hpid, i == (n_pages - pg_inc));
        vaddr_tmp += pg_inc;
    }

    // wait for completion
    wait_event_interruptible(d->waitqueue_invldt, atomic_read(&d->wait_invldt) == FLAG_SET);
    atomic_set(&d->wait_invldt, FLAG_CLR);
}

/**
 * @brief Offload
 * 
 * @param d - vFPGA
 * @param user_pg - mapping
 */
void migrate_to_card_gup(struct fpga_dev *d, struct user_pages *user_pg)
{
    // lock
    mutex_lock(&d->offload_lock);

    // start the offload
    dma_offload_start(d, user_pg->hpages, user_pg->cpages, user_pg->n_pages, user_pg->huge);
    
    // wait for completion
    wait_event_interruptible(d->waitqueue_offload, atomic_read(&d->wait_offload) == FLAG_SET);
    atomic_set(&d->wait_offload, FLAG_CLR);

    // unlock
    mutex_unlock(&d->offload_lock);
}

/**
 * @brief Offload user
 * 
 * @param d - vFPGA
 * @param user_pg - mapping
 */
int offload_user_gup(struct fpga_dev *d, uint64_t vaddr, int32_t cpid)
{
    int ret_val = 1;
    uint64_t vaddr_tmp;
    struct bus_drvdata *pd = d->pd;
    struct user_pages *tmp_entry;
    pid_t hpid;
    struct desc_aligned pfa;

    vaddr_tmp = (vaddr & pd->stlb_order->page_mask) >> pd->stlb_order->page_shift;
    hpid = d->pid_array[cpid];

    hash_for_each_possible(user_buff_map[d->id][cpid], tmp_entry, entry, vaddr_tmp) {
        if(vaddr_tmp >= tmp_entry->vaddr && vaddr_tmp < tmp_entry->vaddr + tmp_entry->n_pages) {
            pfa.vaddr = tmp_entry->vaddr;
            pfa.n_pages = tmp_entry->n_pages;
            pfa.cpid = cpid;
            pfa.hugepages = tmp_entry->huge;

            dbg_info("user triggered migration to card, vaddr %llx, cpid %d\n", vaddr_tmp, cpid);
            tlb_unmap_gup(d, tmp_entry, hpid);
            tmp_entry->host = CARD_ACCESS;
            migrate_to_card_gup(d, tmp_entry);
            tlb_map_gup(d, &pfa, tmp_entry, hpid);
            ret_val = 0;
        }
    }

    return ret_val;
}


/**
 * @brief Sync
 * 
 * @param d - vFPGA
 * @param user_pg - mapping
 */
void migrate_to_host_gup(struct fpga_dev *d, struct user_pages *user_pg)
{
    // lock
    mutex_lock(&d->sync_lock);

    // start the sync
    dma_sync_start(d, user_pg->hpages, user_pg->cpages, user_pg->n_pages, user_pg->huge);
    
    // wait for completion
    wait_event_interruptible(d->waitqueue_sync, atomic_read(&d->wait_sync) == FLAG_SET);
    atomic_set(&d->wait_sync, FLAG_CLR);

    // unlock
    mutex_unlock(&d->sync_lock);
}

/**
 * @brief Sync user
 * 
 * @param d - vFPGA
 * @param vaddr - virtual address
 * @param cpid - cpid
 */
int sync_user_gup(struct fpga_dev *d, uint64_t vaddr, int32_t cpid)
{
    int ret_val = 1;
    uint64_t vaddr_tmp;
    struct bus_drvdata *pd = d->pd;
    struct user_pages *tmp_entry;
    pid_t hpid;
    struct desc_aligned pfa;

    vaddr_tmp = (vaddr & pd->stlb_order->page_mask) >> pd->stlb_order->page_shift;
    hpid = d->pid_array[cpid];

    hash_for_each_possible(user_buff_map[d->id][cpid], tmp_entry, entry, vaddr_tmp) {
        if(vaddr_tmp >= tmp_entry->vaddr && vaddr_tmp < tmp_entry->vaddr + tmp_entry->n_pages) {
            pfa.vaddr = tmp_entry->vaddr;
            pfa.n_pages = tmp_entry->n_pages;
            pfa.cpid = cpid;
            pfa.hugepages = tmp_entry->huge;
            
            dbg_info("user triggered migration to host, vaddr %llx, cpid %d\n", vaddr_tmp, cpid);
            tlb_unmap_gup(d, tmp_entry, hpid);
            tmp_entry->host = HOST_ACCESS;
            migrate_to_host_gup(d, tmp_entry);
            tlb_map_gup(d, &pfa, tmp_entry, hpid);
            ret_val = 0;
        }
    }

    return ret_val;
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
struct user_pages* tlb_get_user_pages(struct fpga_dev *d, struct desc_aligned *pfa, pid_t hpid, struct task_struct *curr_task, struct mm_struct *curr_mm)
{
    int ret_val = 0, i;
    struct bus_drvdata *pd = d->pd;
    struct user_pages *user_pg;

    if (pfa->vaddr + pfa->n_pages < pfa->vaddr)
        return NULL;
    if (pfa->n_pages == 0)
        return NULL;

    // alloc
    user_pg = kzalloc(sizeof(struct user_pages), GFP_KERNEL);
    BUG_ON(!user_pg);

    user_pg->pages = vmalloc(pfa->n_pages * sizeof(*user_pg->pages));
    BUG_ON(!user_pg->pages);
    user_pg->hpages = vmalloc(pfa->n_pages * sizeof(uint64_t));
    BUG_ON(!user_pg->hpages);
    
    dbg_info("allocated %lu bytes for page pointer array for %d pages @0x%p\n",
             pfa->n_pages * sizeof(*user_pg->pages), pfa->n_pages, user_pg->pages);

    dbg_info("pages=0x%p\n", user_pg->pages);

    for (i = 0; i < pfa->n_pages - 1; i++) {
        user_pg->pages[i] = NULL;
    }

    // pin
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5,9,0)
    ret_val = get_user_pages_remote(curr_mm, (unsigned long)pfa->vaddr << PAGE_SHIFT, pfa->n_pages, 1, user_pg->pages, NULL, NULL);
#else 
    ret_val = get_user_pages_remote(curr_task, curr_mm, (unsigned long)pfa->vaddr << PAGE_SHIFT, pfa->n_pages, 1, user_pg->pages, NULL, NULL);
#endif
    dbg_info("get_user_pages_remote(%llx, n_pages = %d, page start = %lx, hugepages = %d)\n", pfa->vaddr, pfa->n_pages, page_to_pfn(user_pg->pages[0]), pfa->hugepages);

    if(ret_val < pfa->n_pages) {
        dbg_info("could not get all user pages, %d\n", ret_val);
        goto fail_host_unmap;
    }

    // flush cache
    for(i = 0; i < pfa->n_pages; i++)
        flush_dcache_page(user_pg->pages[i]);

    // host physical
    for(i = 0;i < pfa->n_pages; i++)
        user_pg->hpages[i] = page_to_phys(user_pg->pages[i]);

    // card alloc
    if(pd->en_mem) {
        user_pg->cpages = vmalloc(pfa->n_pages * sizeof(uint64_t));
        BUG_ON(!user_pg->cpages);

        ret_val = card_alloc(d, user_pg->cpages, pfa->n_pages, pfa->hugepages);
        if (ret_val) {
            dbg_info("could not get all card pages, %d\n", ret_val);
            goto fail_card_unmap;
        }
    }

    // add mapped entry
    user_pg->vaddr = pfa->vaddr;
    user_pg->n_pages = pfa->n_pages;
    user_pg->huge = pfa->hugepages;
    user_pg->cpid = pfa->cpid;
    user_pg->host = HOST_ACCESS;

    hash_add(user_buff_map[d->id][pfa->cpid], &user_pg->entry, pfa->vaddr);

    return user_pg;

fail_host_unmap:
    // release host pages
    for(i = 0; i < ret_val; i++) {
        put_page(user_pg->pages[i]);
    }

    vfree(user_pg->pages);
    vfree(user_pg->hpages);
    kfree(user_pg);

    return NULL;

fail_card_unmap:
    // release host pages
    for(i = 0; i < user_pg->n_pages; i++) {
        put_page(user_pg->pages[i]);
    }

    vfree(user_pg->pages);
    vfree(user_pg->hpages);
    vfree(user_pg->cpages);
    kfree(user_pg);

    return NULL;
}

/**
 * @brief Release user pages
 * 
 * @param d - vFPGA
 * @param vaddr - starting vaddr
 * @param cpid - Coyote PID
 * @param dirtied - modified
 */
int tlb_put_user_pages(struct fpga_dev *d, uint64_t vaddr, int32_t cpid, pid_t hpid, int dirtied)
{
    int i;
    struct user_pages *tmp_entry;
    uint64_t vaddr_tmp;
    struct bus_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    vaddr_tmp = (vaddr & pd->stlb_order->page_mask) >> pd->stlb_order->page_shift;

    hash_for_each_possible(user_buff_map[d->id][cpid], tmp_entry, entry, vaddr_tmp) {
        if(vaddr_tmp >= tmp_entry->vaddr && vaddr_tmp <= tmp_entry->vaddr + tmp_entry->n_pages) {
            // unmap from TLB
            tlb_unmap_gup(d, tmp_entry, hpid);

            // release card pages
            if(pd->en_mem) {
                card_free(d, tmp_entry->cpages, tmp_entry->n_pages, tmp_entry->huge);
                vfree(tmp_entry->cpages);
            }     
            
            // release host pages
            if(dirtied)
                for(i = 0; i < tmp_entry->n_pages; i++)
                    SetPageDirty(tmp_entry->pages[i]);

            for(i = 0; i < tmp_entry->n_pages; i++)
                put_page(tmp_entry->pages[i]);

            vfree(tmp_entry->pages);
            vfree(tmp_entry->hpages);

            // remove from map
            hash_del(&tmp_entry->entry);
        }
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
int tlb_put_user_pages_cpid(struct fpga_dev *d, int32_t cpid, pid_t hpid, int dirtied)
{
    int i, bkt;
    struct user_pages *tmp_entry;
    struct bus_drvdata *pd;

    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    hash_for_each(user_buff_map[d->id][cpid], bkt, tmp_entry, entry) {
        // unmap from TLB
        tlb_unmap_gup(d, tmp_entry, hpid);
        
        // release card pages
        if(pd->en_mem) {
            card_free(d, tmp_entry->cpages, tmp_entry->n_pages, tmp_entry->huge);
            vfree(tmp_entry->cpages);
        }

        if(dirtied)
            for(i = 0; i < tmp_entry->n_pages; i++)
                SetPageDirty(tmp_entry->pages[i]);

        for(i = 0; i < tmp_entry->n_pages; i++)
            put_page(tmp_entry->pages[i]);

        vfree(tmp_entry->pages);
        vfree(tmp_entry->hpages);

        // remove from map
        hash_del(&tmp_entry->entry);
    }

    return 0;
}
