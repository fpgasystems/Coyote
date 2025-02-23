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

#include "reconfig_mem.h"

// A map holding information about all the reconfiguration buffers allocated
// Data-type of each entry is reconfig_buff_metadata (see coyote_dev.h)
struct hlist_head reconfig_buffs_map[1 << (RECONFIG_HASH_TABLE_ORDER)]; 

int alloc_reconfig_buffer(struct reconfig_dev *device, unsigned long n_pages, pid_t pid, uint32_t crid) {
    BUG_ON(!device);
    
    // Reconfig buffers are first allocated, then mapped to user-space and finally, used to load the bitstream
    // Whenever buffers have been allocated and mapped, the variable n_pages is reset to 0
    // When different than zero, it means multiple allocations have occured but haven't been propagated to the user-space
    // Ideally, this should be prevented, as it means there are kernel-space allocated buffers that the user doesn't use
    if (device->curr_buff.n_pages) {
        pr_warn("allocated reconfig buffers exist but have not been mapped\n");
        return -1;
    }

    // Lock, preventing multiple simultaneous allocations
    spin_lock(&device->mem_lock);

    if (n_pages > MAX_RECONFIG_BUFF_NUM)
        device->curr_buff.n_pages = MAX_RECONFIG_BUFF_NUM;
    else
        device->curr_buff.n_pages = n_pages;

    // Allocate page pointer array; each entry is a pointer to a page allocated below (alloc_pages) 
    device->curr_buff.pages = vmalloc(n_pages * sizeof(*device->curr_buff.pages));
    if (device->curr_buff.pages == NULL) {
        pr_warn("failed to allocate page pointer array for reconfig buffers");
        return -ENOMEM;
    }
    dbg_info(
        "allocated %lu bytes for page pointer array for %ld n_pages of a reconfig buffer, ptr 0x%p\n",
        n_pages * sizeof(*device->curr_buff.pages), n_pages, device->curr_buff.pages
    );
    
    // Allocate the physical pages for the buffer
    int i;
    for (i = 0; i < device->curr_buff.n_pages; i++) {
        device->curr_buff.pages[i] = alloc_pages(GFP_ATOMIC, device->pd->ltlb_order->page_shift - PAGE_SHIFT);
        if (!device->curr_buff.pages[i]) {
            pr_warn("reconfig buffer page %d could not be allocated\n", i);
            goto fail_alloc;
        }
    }

    device->curr_buff.pid = pid;
    device->curr_buff.crid = crid;
    spin_unlock(&device->mem_lock);
    return 0;

fail_alloc:
    // Couldn't allocate all the required pages; free the ones that were actually allocated
    while (i) {
        __free_pages(device->curr_buff.pages[--i], device->pd->ltlb_order->page_shift - PAGE_SHIFT);
    }
    device->curr_buff.n_pages = 0;
    
    spin_unlock(&device->mem_lock);
    return -ENOMEM;
}

int free_reconfig_buffer(struct reconfig_dev *device, uint64_t virtual_address, pid_t pid, uint32_t crid) {
    BUG_ON(!device);

    // Iterate through metadata map of allocated buffers and free pages, delete map entry
    struct reconfig_buff_metadata *tmp_buff;
    hash_for_each_possible(reconfig_buffs_map, tmp_buff, entry, virtual_address) {
        if (tmp_buff->vaddr == virtual_address && tmp_buff->pid == pid && tmp_buff->crid == crid) {
            for (int i = 0; i < tmp_buff->n_pages; i++) {
                if (tmp_buff->pages[i]) {
                    __free_pages(tmp_buff->pages[i], device->pd->ltlb_order->page_shift - PAGE_SHIFT);
                }
            }
            vfree(tmp_buff->pages);

            hash_del(&tmp_buff->entry);
        }
    }

    // NOTE: All the functions from above (__free_pages, vfree, hash_del are void)
    // Therefore; there is no error handlind, and hence, always return 0
    return 0;
}
