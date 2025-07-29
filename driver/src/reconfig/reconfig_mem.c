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
        device->curr_buff.pages[i] = alloc_pages(GFP_ATOMIC, 21 - PAGE_SHIFT);
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
        __free_pages(device->curr_buff.pages[--i], 21 - PAGE_SHIFT);
    }
    device->curr_buff.n_pages = 0;
    
    spin_unlock(&device->mem_lock);
    return -ENOMEM;
}

int free_reconfig_buffer(struct reconfig_dev *device, uint64_t vaddr, pid_t pid, uint32_t crid) {
    BUG_ON(!device);

    // Iterate through metadata map of allocated buffers and free pages, delete map entry
    struct reconfig_buff_metadata *tmp_buff;
    hash_for_each_possible(reconfig_buffs_map, tmp_buff, entry, vaddr) {
        if (tmp_buff->vaddr == vaddr && tmp_buff->pid == pid && tmp_buff->crid == crid) {
            for (int i = 0; i < tmp_buff->n_pages; i++) {
                if (tmp_buff->pages[i]) {
                    __free_pages(tmp_buff->pages[i], 21 - PAGE_SHIFT);
                }
            }
            vfree(tmp_buff->pages);

            hash_del(&tmp_buff->entry);
        }
    }

    // NOTE: All the functions from above (__free_pages, vfree, hash_del are void)
    // Therefore; there is no error handling, and hence, always return 0
    return 0;
}
