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

#include "vfpga_gup.h"

/// A map of allocated user buffers, per vFPGA and Coyote thread
struct hlist_head user_buff_map[MAX_N_REGIONS][N_CTID_MAX][1 << (USER_HASH_TABLE_ORDER)]; // main alloc

int mmu_handler_gup(struct vfpga_dev *device, uint64_t vaddr, uint64_t len, int32_t ctid, int32_t stream, pid_t hpid) {
    int ret_val = 0;
    struct user_pages *user_pg;
    struct bus_driver_data *bd_data = device->bd_data;

    // Find context (host process ID)
    struct task_struct *curr_task = pid_task(find_vpid(hpid), PIDTYPE_PID);
    dbg_info("hpid found = %d", hpid);
    struct mm_struct *curr_mm = curr_task->mm;

    // Check if the request area is huge page or not
    struct vm_area_struct *vma_area_init = find_vma(curr_mm, vaddr);
    int hugepages = is_vm_hugetlb_page(vma_area_init);
    struct tlb_metadata *tlb_meta = hugepages ? bd_data->ltlb_meta : bd_data->stlb_meta;

    // Align to a page boundary and calculate the number of pages bust on the buffer lenght (in bytes)
    struct pf_aligned_desc pf_desc;
    pf_desc.vaddr = (vaddr & tlb_meta->page_mask) >> tlb_meta->page_shift;
    uint64_t last = ((vaddr + len - 1) & tlb_meta->page_mask) >> tlb_meta->page_shift;
    pf_desc.n_pages = last - pf_desc.vaddr + 1;
    if (hugepages) {
        pf_desc.n_pages = pf_desc.n_pages * bd_data->n_pages_in_huge;
        pf_desc.vaddr = pf_desc.vaddr << bd_data->dif_order_page_shift;
    }

    // Populate rest of the page fault descriptor
    pf_desc.ctid = ctid;
    pf_desc.hugepages = hugepages;

    // Check if mapping is already present
    user_pg = map_present(device, &pf_desc);

    // Handle the different cases, based on if the mapping is alread present or not, and if its HOST or CARD access
    if(user_pg) {
        if(stream == HOST_ACCESS) {
            if(user_pg->host == HOST_ACCESS) {
                dbg_info("host access, map present, updating TLB\n");
                tlb_map_gup(device, &pf_desc, user_pg, hpid);
            } else {
                dbg_info("card access, map present, migration\n");
                tlb_unmap_gup(device, user_pg, hpid);
                user_pg->host = HOST_ACCESS;
                migrate_to_host(device, user_pg);
                tlb_map_gup(device, &pf_desc, user_pg, hpid);
            }
        } else if(stream == CARD_ACCESS) {
            if(user_pg->host == HOST_ACCESS) {
                dbg_info("host access, map present, migration\n");
                tlb_unmap_gup(device, user_pg, hpid);
                user_pg->host = CARD_ACCESS;
                migrate_to_card(device, user_pg);
                tlb_map_gup(device, &pf_desc, user_pg, hpid);
            } else {
                dbg_info("card access, map present, updating TLB\n");
                tlb_map_gup(device, &pf_desc, user_pg, hpid);
            }
        } else {
            ret_val = -EINVAL;
            pr_err("access not supported, vFPGA %d\n", device->id);
        }
    } else {
        dbg_info("map not present\n");
        user_pg = tlb_get_user_pages(device, &pf_desc, hpid, curr_task, curr_mm);
        if(!user_pg) {
            pr_err("user pages could not be obtained\n");
            return -ENOMEM;
        }

        if(stream) {  
           tlb_map_gup(device, &pf_desc, user_pg, hpid);           
        } else {
           user_pg->host = CARD_ACCESS;
           migrate_to_card(device, user_pg);
           tlb_map_gup(device, &pf_desc, user_pg, hpid);
        }
    }

    return ret_val;
}

struct user_pages* map_present(struct vfpga_dev *device, struct pf_aligned_desc *pf_desc) {
    int bkt;
    struct user_pages *tmp_entry;

    // Iterate through the hash table to find a matching user page
    hash_for_each(user_buff_map[device->id][pf_desc->ctid], bkt, tmp_entry, entry) {
        if(pf_desc->vaddr >= tmp_entry->vaddr && pf_desc->vaddr < tmp_entry->vaddr + tmp_entry->n_pages) {
            // Hit
            if(pf_desc->vaddr + pf_desc->n_pages > tmp_entry->vaddr + tmp_entry->n_pages)
                pf_desc->n_pages =  tmp_entry->vaddr + tmp_entry->n_pages - pf_desc->vaddr;

            return tmp_entry;
        } else if(pf_desc->vaddr < tmp_entry->vaddr && pf_desc->vaddr + pf_desc->n_pages > tmp_entry->vaddr) {
            // Partial hit; modify the page fault descriptor to include the overlapping pages
            pf_desc->n_pages = tmp_entry->vaddr - pf_desc->vaddr;
        }
    }

    return 0;
}

void tlb_map_gup(struct vfpga_dev *device, struct pf_aligned_desc *pf_desc, struct user_pages *user_pg, pid_t hpid) {
    BUG_ON(!device);
    struct bus_driver_data *bd_data = device->bd_data;
    BUG_ON(!bd_data);

    // Find the first page that's in the page fault and then the first page that has already been mapped; calculate offset
    uint64_t pg_offs = pf_desc->vaddr - user_pg->vaddr;
    uint32_t n_pages = pf_desc->n_pages;

    int32_t n_pg_mapped = 0;
    uint64_t vaddr_tmp = pf_desc->vaddr;
    if (user_pg->huge) {
        // Do mappings - huge pages
        for (int i = 0; (i < n_pages) && (n_pg_mapped < MAX_N_MAP_PAGES); i+=bd_data->n_pages_in_huge) {
            create_tlb_mapping(
                device, bd_data->ltlb_meta, vaddr_tmp, 
                (user_pg->host == HOST_ACCESS) ? user_pg->hpages[i + pg_offs] : user_pg->cpages[i + pg_offs],
                user_pg->host, user_pg->ctid, hpid
            );

            vaddr_tmp += bd_data->n_pages_in_huge;
            n_pg_mapped++;
        }
    } else {
        // Do mappings - regular + regular pages coalesced into huge pages
        int i = 0;
        uint64_t paddr_tmp, paddr_curr;

        while((i < n_pages) && (n_pg_mapped < MAX_N_MAP_PAGES)) {
            // Coalesce, if possible
            bool is_huge = false;
            if (n_pages >= bd_data->n_pages_in_huge) {
                if (i <= n_pages - bd_data->n_pages_in_huge) {
                    if ((vaddr_tmp & bd_data->dif_order_page_mask) == 0) {
                        paddr_tmp = (user_pg->host == HOST_ACCESS) ? user_pg->hpages[i + pg_offs] : user_pg->cpages[i + pg_offs];
                        if ((paddr_tmp & ~bd_data->ltlb_meta->page_mask) == 0) {
                            is_huge = true; 
                            for (int j = i + 1; j < i + bd_data->n_pages_in_huge; j++) {
                                paddr_curr = (user_pg->host == HOST_ACCESS) ? user_pg->hpages[j + pg_offs] : user_pg->cpages[j + pg_offs];
                                if (paddr_curr != paddr_tmp + PAGE_SIZE) {
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

            // Call HW fucntion to do mapping
            create_tlb_mapping(
                device, is_huge ? bd_data->ltlb_meta : bd_data->stlb_meta, vaddr_tmp, 
                (user_pg->host == HOST_ACCESS) ? user_pg->hpages[i + pg_offs] : user_pg->cpages[i + pg_offs],
                user_pg->host, user_pg->ctid, hpid
            );
            
            // Proceed to next page
            vaddr_tmp += is_huge ? bd_data->n_pages_in_huge : 1;
            i += is_huge ? bd_data->n_pages_in_huge : 1;
            n_pg_mapped++;
        }
    }
}

void tlb_unmap_gup(struct vfpga_dev *device, struct user_pages *user_pg, pid_t hpid) {
    BUG_ON(!device);
    struct bus_driver_data *bd_data = device->bd_data;
    BUG_ON(!bd_data);

    // Metadata
    uint32_t n_pages = user_pg->n_pages;
    int32_t pg_inc = user_pg->huge ? bd_data->n_pages_in_huge : 1;
    uint64_t vaddr_tmp = user_pg->vaddr;

    if(user_pg->huge) {
        // Unmap - huge pages
        for (int i = 0; i < n_pages; i += bd_data->n_pages_in_huge) {
            create_tlb_unmapping(device, bd_data->ltlb_meta, vaddr_tmp, hpid);
            vaddr_tmp += bd_data->n_pages_in_huge;
        }
    } else {
        // Unmap - regular and coalesced
        int i = 0;
        uint64_t paddr_tmp, paddr_curr;
        while((i < n_pages)) {
            // Coalesce, if possible
            bool is_huge = false;
            if (n_pages >= bd_data->n_pages_in_huge) {
                if (i <= n_pages - bd_data->n_pages_in_huge) {
                    if ((vaddr_tmp & bd_data->dif_order_page_mask) == 0) {
                        paddr_tmp = (user_pg->host == HOST_ACCESS) ? user_pg->hpages[i] : user_pg->cpages[i];
                        if ((paddr_tmp & ~bd_data->ltlb_meta->page_mask) == 0) {
                            is_huge = true; 
                            for (int j = i + 1; j < i + bd_data->n_pages_in_huge; j++) {
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

            // Unmap
            create_tlb_unmapping(device, is_huge ? bd_data->ltlb_meta : bd_data->stlb_meta, vaddr_tmp, hpid);
            
            // Proceed to next page
            vaddr_tmp += is_huge ? bd_data->n_pages_in_huge : 1;
            i += is_huge ? bd_data->n_pages_in_huge : 1;
        }
    }
    
    // Invalidate TLB entry
    vaddr_tmp = user_pg->vaddr;
    for (int i = 0; i < n_pages; i += pg_inc) {
        invalidate_tlb_entry(device, vaddr_tmp, pg_inc, hpid, i == (n_pages - pg_inc));
        vaddr_tmp += pg_inc;
    }

    // Wait for completion
    wait_event_interruptible(device->waitqueue_invldt, atomic_read(&device->wait_invldt) == FLAG_SET);
    atomic_set(&device->wait_invldt, FLAG_CLR);
}

struct user_pages* tlb_get_user_pages(struct vfpga_dev *device, struct pf_aligned_desc *pf_desc, pid_t hpid, struct task_struct *curr_task, struct mm_struct *curr_mm) {
    int ret_val = 0;
    struct bus_driver_data *bd_data = device->bd_data;

    // Error handling
    BUG_ON(!device);
    BUG_ON(!bd_data);
    if (pf_desc->vaddr + pf_desc->n_pages < pf_desc->vaddr)
        return NULL;
    if (pf_desc->n_pages == 0)
        return NULL;

    // Allocate struct to hold the metadata, the actual pages and an array for the physical addresses
    struct user_pages *user_pg = kzalloc(sizeof(struct user_pages), GFP_KERNEL);
    BUG_ON(!user_pg);

    user_pg->pages = vmalloc(pf_desc->n_pages * sizeof(*user_pg->pages));
    BUG_ON(!user_pg->pages);
    for (int i = 0; i < pf_desc->n_pages - 1; i++) {
        user_pg->pages[i] = NULL;
    }

    user_pg->hpages = vmalloc(pf_desc->n_pages * sizeof(uint64_t));
    BUG_ON(!user_pg->hpages);
    
    dbg_info(
        "allocated %lu bytes for page pointer array for %d pages @0x%p\n",
        pf_desc->n_pages * sizeof(*user_pg->pages), pf_desc->n_pages, user_pg->pages
    );
    dbg_info("pages=0x%p\n", user_pg->pages);

    // Pin the pages
    #if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 5, 0)
       ret_val = get_user_pages_remote(curr_mm, (unsigned long) pf_desc->vaddr << PAGE_SHIFT, pf_desc->n_pages, 1, user_pg->pages, NULL);
    #elif LINUX_VERSION_CODE >= KERNEL_VERSION(5, 9, 0)
        ret_val = get_user_pages_remote(curr_mm, (unsigned long) pf_desc->vaddr << PAGE_SHIFT, pf_desc->n_pages, 1, user_pg->pages, NULL, NULL);
    #else 
        ret_val = get_user_pages_remote(curr_task, curr_mm, (unsigned long)pf_desc->vaddr << PAGE_SHIFT, pf_desc->n_pages, 1, user_pg->pages, NULL, NULL);
    #endif
    dbg_info("get_user_pages_remote(%llx, n_pages = %d, page start = %lx, hugepages = %d)\n", pf_desc->vaddr, pf_desc->n_pages, page_to_pfn(user_pg->pages[0]), pf_desc->hugepages);

    if(ret_val < pf_desc->n_pages) {
        dbg_info("could not get all user pages, %d\n", ret_val);
        goto fail_host_unmap;
    }

    // Flush cache
    for(int i = 0; i < pf_desc->n_pages; i++)
        flush_dcache_page(user_pg->pages[i]);

    // Find the physical address of the pages
    for(int i = 0;i < pf_desc->n_pages; i++)
        user_pg->hpages[i] = page_to_phys(user_pg->pages[i]);

    // Allocate memory on the card if available
    if(bd_data->en_mem) {
        user_pg->cpages = vmalloc(pf_desc->n_pages * sizeof(uint64_t));
        BUG_ON(!user_pg->cpages);

        ret_val = alloc_card_memory(device, user_pg->cpages, pf_desc->n_pages, pf_desc->hugepages);
        if (ret_val) {
            dbg_info("could not get all card pages, %d\n", ret_val);
            goto fail_card_unmap;
        }
    }

    // Populate metadata and store to hash table
    user_pg->vaddr = pf_desc->vaddr;
    user_pg->n_pages = pf_desc->n_pages;
    user_pg->huge = pf_desc->hugepages;
    user_pg->ctid = pf_desc->ctid;
    user_pg->host = HOST_ACCESS;

    hash_add(user_buff_map[device->id][pf_desc->ctid], &user_pg->entry, pf_desc->vaddr);

    return user_pg;

fail_host_unmap:
    // Release the pages
    for(int i = 0; i < ret_val; i++) {
        put_page(user_pg->pages[i]);
    }

    // Free the dynamically allocated memory
    vfree(user_pg->pages);
    vfree(user_pg->hpages);
    kfree(user_pg);

    return NULL;

fail_card_unmap:
    // Release the pages
    for(int i = 0; i < user_pg->n_pages; i++) {
        put_page(user_pg->pages[i]);
    }

    // Free the dynamically allocated memory
    vfree(user_pg->pages);
    vfree(user_pg->hpages);
    vfree(user_pg->cpages);
    kfree(user_pg);

    return NULL;
}

int tlb_put_user_pages(struct vfpga_dev *device, uint64_t vaddr, int32_t ctid, pid_t hpid, int dirtied) {
    BUG_ON(!device);
    struct bus_driver_data * bd_data = device->bd_data;
    BUG_ON(!bd_data);

    uint64_t vaddr_tmp = (vaddr & bd_data->stlb_meta->page_mask) >> bd_data->stlb_meta->page_shift;

    struct user_pages *tmp_entry;
    hash_for_each_possible(user_buff_map[device->id][ctid], tmp_entry, entry, vaddr_tmp) {
        if(vaddr_tmp >= tmp_entry->vaddr && vaddr_tmp <= tmp_entry->vaddr + tmp_entry->n_pages) {
            // Unmap from TLB
            tlb_unmap_gup(device, tmp_entry, hpid);

            // Release card memory
            if(bd_data->en_mem) {
                free_card_memory(device, tmp_entry->cpages, tmp_entry->n_pages, tmp_entry->huge);
                vfree(tmp_entry->cpages);
            }     
            
            // Release host pages
            if(tmp_entry->dma_attach) {
                #if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 2, 0)
                    // Unmap buffer from vFPGA bus address space
                    dma_resv_lock(tmp_entry->buf->resv, NULL);
                    dma_buf_unmap_attachment(tmp_entry->dma_attach, tmp_entry->sgt, DMA_BIDIRECTIONAL);
                    dma_resv_unlock(tmp_entry->buf->resv);

                    // Detach vFPGA from DMABuff
                    kfree(tmp_entry->dma_attach->importer_priv);
                    dma_buf_detach(tmp_entry->buf, tmp_entry->dma_attach);

                    // Decrease DMABuf refcount
                    dma_buf_put(tmp_entry->buf);
                #else
                    pr_warn("Error releasing user pages! DMA Bufs for Coyote GPU integration is only available on Linux >= 6.2.0. If you're seeing this message and your driver compiled: this is likely a bug; please report it to the Coyote team\n");
                    return -1;
                #endif
            } else {
                if(dirtied) {
                    for(int i = 0; i < tmp_entry->n_pages; i++) {
                        SetPageDirty(tmp_entry->pages[i]);
                    }
                }
                
                // Release page
                for(int i = 0; i < tmp_entry->n_pages; i++) {
                    put_page(tmp_entry->pages[i]);
                }
                
                // Release memory to hold pages
                vfree(tmp_entry->pages);
            }

            // Release memory to hold physical addresses
            vfree(tmp_entry->hpages);

            // Remove from map
            hash_del(&tmp_entry->entry);
        }
    }

    return 0;
}

int tlb_put_user_pages_ctid(struct vfpga_dev *device, int32_t ctid, pid_t hpid, int dirtied) {
    int i, bkt;
    struct user_pages *tmp_entry;

    BUG_ON(!device);
    struct bus_driver_data *bd_data = device->bd_data;
    BUG_ON(!bd_data);

    hash_for_each(user_buff_map[device->id][ctid], bkt, tmp_entry, entry) {
        // Unmap from TLB
        tlb_unmap_gup(device, tmp_entry, hpid);
        
        // Release card memory
        if(bd_data->en_mem) {
            free_card_memory(device, tmp_entry->cpages, tmp_entry->n_pages, tmp_entry->huge);
            vfree(tmp_entry->cpages);
        }

        if(tmp_entry->dma_attach) {
            #if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 2, 0)  
                // Unmap buffer from vFPGA bus address space
                dma_resv_lock(tmp_entry->buf->resv, NULL);
                dma_buf_unmap_attachment(tmp_entry->dma_attach, tmp_entry->sgt, DMA_BIDIRECTIONAL);
                dma_resv_unlock(tmp_entry->buf->resv);

                // Detach vFPGA from DMABuff
                kfree(tmp_entry->dma_attach->importer_priv);
                dma_buf_detach(tmp_entry->buf, tmp_entry->dma_attach);

                // Decrease DMABuf refcount
                dma_buf_put(tmp_entry->buf);
            #else
                pr_warn("Error releasing user pages! DMA Bufs for Coyote GPU integration is only available on Linux >= 6.2.0. If you're seeing this message and your driver compiled: this is likely a bug; please report it to the Coyote team\n");
                return -1;
            #endif
        } else {
            if(dirtied)
                for(i = 0; i < tmp_entry->n_pages; i++)
                    SetPageDirty(tmp_entry->pages[i]);
            
            // Release host pages
            for(i = 0; i < tmp_entry->n_pages; i++)
                put_page(tmp_entry->pages[i]);

            // Release memory to hold pages
            vfree(tmp_entry->pages);
        }

        // Release memory to hold physical addresses
        vfree(tmp_entry->hpages);

        // Remove from map
        hash_del(&tmp_entry->entry);
    }

    return 0;
}

void migrate_to_card(struct vfpga_dev *device, struct user_pages *user_pg) {
    mutex_lock(&device->offload_lock);

    trigger_dma_offload(device, user_pg->hpages, user_pg->cpages, user_pg->n_pages, user_pg->huge);
    
    wait_event_interruptible(device->waitqueue_offload, atomic_read(&device->wait_offload) == FLAG_SET);
    atomic_set(&device->wait_offload, FLAG_CLR);

    mutex_unlock(&device->offload_lock);
}

void migrate_to_host(struct vfpga_dev *device, struct user_pages *user_pg) {
    mutex_lock(&device->sync_lock);

    trigger_dma_sync(device, user_pg->hpages, user_pg->cpages, user_pg->n_pages, user_pg->huge);
    
    wait_event_interruptible(device->waitqueue_sync, atomic_read(&device->wait_sync) == FLAG_SET);
    atomic_set(&device->wait_sync, FLAG_CLR);

    mutex_unlock(&device->sync_lock);
}

int offload_user_pages(struct vfpga_dev *device, uint64_t vaddr, uint32_t len, int32_t ctid) {
    int ret_val = 1;

    BUG_ON(!device);
    struct bus_driver_data *bd_data = device->bd_data;
    BUG_ON(!bd_data);

    // Metadata
    pid_t hpid = device->pid_array[ctid];
    uint64_t vaddr_tmp = (vaddr & bd_data->stlb_meta->page_mask) >> bd_data->stlb_meta->page_shift;
    uint64_t vaddr_last = ((vaddr + len - 1) & bd_data->stlb_meta->page_mask) >> bd_data->stlb_meta->page_shift;

    struct user_pages *tmp_entry;
    while (vaddr_tmp <= vaddr_last) {
        hash_for_each_possible(user_buff_map[device->id][ctid], tmp_entry, entry, vaddr_tmp) {
            if(vaddr_tmp >= tmp_entry->vaddr && vaddr_tmp < tmp_entry->vaddr + tmp_entry->n_pages) {
                struct pf_aligned_desc pf_desc;
                pf_desc.vaddr = tmp_entry->vaddr;
                pf_desc.n_pages = tmp_entry->n_pages;
                pf_desc.ctid = ctid;
                pf_desc.hugepages = tmp_entry->huge;

                dbg_info("user triggered migration to card, vaddr %llx, ctid %d, last %llx\n", vaddr_tmp, ctid, vaddr_last);
                tlb_unmap_gup(device, tmp_entry, hpid);
                tmp_entry->host = CARD_ACCESS;
                migrate_to_card(device, tmp_entry);
                tlb_map_gup(device, &pf_desc, tmp_entry, hpid);
                ret_val = 0;

                vaddr_tmp += tmp_entry->n_pages;
            }
        }
    }

    return ret_val;
}

// TODO: BR - We could handle return values better in the future; same applies to off-load
int sync_user_pages(struct vfpga_dev *device, uint64_t vaddr, uint32_t len, int32_t ctid) {
    int ret_val = 1;
    
    BUG_ON(!device);
    struct bus_driver_data *bd_data = device->bd_data;
    BUG_ON(!bd_data);

    // Metadata
    pid_t hpid = device->pid_array[ctid];
    uint64_t vaddr_tmp = (vaddr & bd_data->stlb_meta->page_mask) >> bd_data->stlb_meta->page_shift;
    uint64_t vaddr_last = ((vaddr + len - 1) & bd_data->stlb_meta->page_mask) >> bd_data->stlb_meta->page_shift;

    // Iterate, until all the pages have been synced
    struct user_pages *tmp_entry;
    while (vaddr_tmp <= vaddr_last) {
        hash_for_each_possible(user_buff_map[device->id][ctid], tmp_entry, entry, vaddr_tmp) {
            if(vaddr_tmp >= tmp_entry->vaddr && vaddr_tmp < tmp_entry->vaddr + tmp_entry->n_pages) {
                struct pf_aligned_desc pf_desc;
                pf_desc.vaddr = tmp_entry->vaddr;
                pf_desc.n_pages = tmp_entry->n_pages;
                pf_desc.ctid = ctid;
                pf_desc.hugepages = tmp_entry->huge;
                
                dbg_info("user triggered migration to host, vaddr %llx, ctid %d, last %llx\n", vaddr_tmp, ctid, vaddr_last);
                tlb_unmap_gup(device, tmp_entry, hpid);
                tmp_entry->host = HOST_ACCESS;
                migrate_to_host(device, tmp_entry);
                tlb_map_gup(device, &pf_desc, tmp_entry, hpid);
                ret_val = 0;

                vaddr_tmp += tmp_entry->n_pages;
            }
        }
    }

    return ret_val;
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 2, 0)

const struct dma_buf_attach_ops gpu_importer_ops = {
    .allow_peer2peer = true,
    .move_notify = p2p_move_notify 
};

void p2p_move_notify(struct dma_buf_attachment *attach) {
    struct dma_buf_move_notify_private *importer_priv = (struct dma_buf_move_notify_private *) attach->importer_priv;
    struct vfpga_dev *device = importer_priv->device;
    BUG_ON(!device);

    // Metadata
    uint64_t vaddr_tmp = importer_priv->vaddr;
    int32_t ctid = importer_priv->ctid;
    pid_t hpid = device->pid_array[ctid];
    struct user_pages *tmp_entry;

    hash_for_each_possible(user_buff_map[device->id][ctid], tmp_entry, entry, vaddr_tmp) {
        if(vaddr_tmp >= tmp_entry->vaddr && vaddr_tmp <= tmp_entry->vaddr + tmp_entry->n_pages) {
            // Unmap any previous entry from TLB
            tlb_unmap_gup(device, tmp_entry, hpid);

            // Unmap buffer from vFPGA bus address space
            dma_buf_unmap_attachment(tmp_entry->dma_attach, tmp_entry->sgt, DMA_BIDIRECTIONAL);

            // Remap 
            tmp_entry->sgt = dma_buf_map_attachment(attach, DMA_BIDIRECTIONAL);

            // Find physical addresses
            struct scatterlist *sgl = tmp_entry->sgt->sgl;
            BUG_ON(!sgl);

            int cnt = 0;
            struct scatterlist *tmp_sgl = sgl;
            while (tmp_sgl) {
                for (int i = 0; i < sg_dma_len(tmp_sgl) >> PAGE_SHIFT; i++) {
                    tmp_entry->hpages[cnt + i] = sg_dma_address(tmp_sgl) + i * PAGE_SIZE;
                }
                cnt = sg_dma_len(tmp_sgl) >> PAGE_SHIFT;
                tmp_sgl = sg_next(tmp_sgl);
            }

            // Map to TLB
            struct pf_aligned_desc pf_desc;
            pf_desc.vaddr = vaddr_tmp;
            pf_desc.n_pages = tmp_entry->n_pages;
            pf_desc.ctid = ctid;
            pf_desc.hugepages = false;

            tlb_map_gup(device, &pf_desc, tmp_entry, hpid);

            tmp_entry->buf = attach->dmabuf;
            tmp_entry->dma_attach = attach;
        }
    }
}

int p2p_attach_dma_buf(struct vfpga_dev *device, int buf_fd, uint64_t vaddr, int32_t ctid)  {
    int ret_val = 0;
    
    BUG_ON(!device);
    struct device *dev = &device->bd_data->pci_dev->dev;
    struct bus_driver_data *bd_data = device->bd_data;
    BUG_ON(!dev);
    BUG_ON(!bd_data);

    // Metadata
    uint64_t vaddr_tmp = (vaddr & bd_data->stlb_meta->page_mask) >> bd_data->stlb_meta->page_shift;
    pid_t hpid = device->pid_array[ctid];

    // Allocate memory to hold the user pages struct 
    struct user_pages *user_pg = kzalloc(sizeof(struct user_pages), GFP_KERNEL);
    BUG_ON(!user_pg);

    // Retrieve dmabuf
    struct dma_buf *buf = dma_buf_get(buf_fd);
    if(IS_ERR(buf)) {
        pr_err("dma_buf_get failed\n");
        goto err_dma_buf;
    }

    // Set private fields
    struct dma_buf_move_notify_private *importer_priv = kzalloc(sizeof(struct dma_buf_move_notify_private), GFP_KERNEL);
    if(importer_priv == NULL) {
        pr_err("error in importer_priv creation!");
        goto err_not_private;
    }
    importer_priv->device = device;
    importer_priv->vaddr = vaddr_tmp;
    importer_priv->ctid = ctid;

    // Attach FPGA device as a dynamic importer, to avoid data migration issues
    user_pg->buf = buf;
    user_pg->dma_attach = dma_buf_dynamic_attach(buf, dev, &gpu_importer_ops, importer_priv);
    if(IS_ERR(user_pg->dma_attach)) {
        pr_err("dma_buf_attach failed\n");
        goto err_attach;
    }

    // Map DMA Buff into FPGA bus address space
    dma_resv_lock(buf->resv, NULL);
    user_pg->sgt = dma_buf_map_attachment(user_pg->dma_attach, DMA_BIDIRECTIONAL);
    dma_resv_unlock(buf->resv);

    if(IS_ERR(user_pg->sgt)) {
        pr_err("sg_table is NULL\n");
        goto err_sg;
    }

    // Calculate number of pages
    struct scatterlist *sgl = user_pg->sgt->sgl;
    struct scatterlist *tmp_sgl = sgl;
    if(sgl == NULL) {
        pr_err("scatterlist is NULL\n");
        goto err_sglist;
    }

    // Get the number of pages
    uint32_t n_pages = 0;
    while(tmp_sgl) {
        n_pages += sg_dma_len(tmp_sgl) >> PAGE_SHIFT;
        tmp_sgl = sg_next(tmp_sgl);
    }

    // Allocate space to hold the physical addresses of the pages and calculate physical addresses
    user_pg->hpages = vmalloc(n_pages * sizeof(uint64_t));
    BUG_ON(!user_pg->hpages);

    tmp_sgl = sgl;
    int cnt = 0;
    while (tmp_sgl) {
        for (int i = 0; i < sg_dma_len(tmp_sgl) >> PAGE_SHIFT; i++) {
            user_pg->hpages[cnt + i] = sg_dma_address(tmp_sgl) + i * PAGE_SIZE;
        }
        cnt += sg_dma_len(tmp_sgl) >> PAGE_SHIFT;
        tmp_sgl = sg_next(tmp_sgl);
    }

    // Allocate card memory, if available
    if(bd_data->en_mem) {
        user_pg->cpages = vmalloc(n_pages * sizeof(uint64_t));
        BUG_ON(!user_pg->cpages);

        ret_val = alloc_card_memory(device, user_pg->cpages, n_pages, false);
        if (ret_val) {
            dbg_info("could not get all card pages, %d\n", ret_val);
            goto err_card_unmap;
        }
    }

    // Add mapped entry to the user buff map
    user_pg->vaddr = vaddr_tmp;
    user_pg->n_pages = n_pages;
    user_pg->huge = false;
    user_pg->ctid = ctid;
    user_pg->host = HOST_ACCESS;
    hash_add(user_buff_map[device->id][ctid], &user_pg->entry, user_pg->vaddr);

    // Map to TLB
    struct pf_aligned_desc pf_desc;
    pf_desc.vaddr = vaddr_tmp;
    pf_desc.n_pages = user_pg->n_pages;
    pf_desc.ctid = ctid;
    pf_desc.hugepages = false;
    tlb_map_gup(device, &pf_desc, user_pg, hpid);

    dbg_info("dmabuf attached, n_pages %d\n", n_pages);
    return 0;

err_card_unmap:
    vfree(user_pg->hpages);
    vfree(user_pg->cpages);
err_sglist:
err_sg:
    dma_buf_detach(buf, user_pg->dma_attach);
err_attach:
    kfree(user_pg->dma_attach->importer_priv);
err_not_private:
    dma_buf_put(buf);
err_dma_buf:
    kfree(user_pg);
    return -EINVAL;
}

int p2p_detach_dma_buf(struct vfpga_dev *device, uint64_t vaddr, int32_t ctid, int dirtied) {
    BUG_ON(!device);
    struct bus_driver_data *bd_data = device->bd_data;
    BUG_ON(!bd_data);
    
    // Metadata
    uint64_t vaddr_tmp = (vaddr & bd_data->stlb_meta->page_mask) >> bd_data->stlb_meta->page_shift;
    pid_t hpid = device->pid_array[ctid];

    struct user_pages *tmp_entry;
    hash_for_each_possible(user_buff_map[device->id][ctid], tmp_entry, entry, vaddr_tmp) {
        if(vaddr_tmp >= tmp_entry->vaddr && vaddr_tmp <= tmp_entry->vaddr + tmp_entry->n_pages) {
            // Unmap from TLB
            tlb_unmap_gup(device, tmp_entry, hpid);
        
            // Release card memory
            if(bd_data->en_mem) {
                free_card_memory(device, tmp_entry->cpages, tmp_entry->n_pages, tmp_entry->huge);
                vfree(tmp_entry->cpages);
            }
            
            // Unmap buffer from vFPGA bus address space
            dma_resv_lock(tmp_entry->buf->resv, NULL);
            dma_buf_unmap_attachment(tmp_entry->dma_attach, tmp_entry->sgt, DMA_BIDIRECTIONAL);
            dma_resv_unlock(tmp_entry->buf->resv);

            // Detach vFPGA from DMABuf
            kfree(tmp_entry->dma_attach->importer_priv);
            dma_buf_detach(tmp_entry->buf, tmp_entry->dma_attach);

            // Decrease DMABuf refcount
            dma_buf_put(tmp_entry->buf);

            // Release host pages
            vfree(tmp_entry->hpages);
            
            // Remove from map
            hash_del(&tmp_entry->entry);
        }
    }
    
    return 0;
}

#else
void p2p_move_notify(struct dma_buf_attachment *attach){
    pr_warn("DMA Bufs for Coyote GPU integration is only available on Linux >= 6.2.0. If you're seeing this message and your driver compiled: this is likely a bug; please report it to the Coyote team\n");
}

int p2p_attach_dma_buf(struct vfpga_dev *device, int buf_fd, uint64_t vaddr, int32_t ctid) {
    pr_warn("DMA Bufs for Coyote GPU integration is only available on Linux >= 6.2.0. If you're seeing this message and your driver compiled: this is likely a bug; please report it to the Coyote team\n");
    return -1;
}

int p2p_detach_dma_buf(struct vfpga_dev *device, uint64_t vaddr, int32_t ctid, int dirtied) {
    pr_warn("DMA Bufs for Coyote GPU integration is only available on Linux >= 6.2.0. If you're seeing this message and your driver compiled: this is likely a bug; please report it to the Coyote team\n");
    return -1;
}

#endif