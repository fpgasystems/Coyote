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
    mutex_lock(&device->mem_lock);
    if (device->curr_buff.n_pages) {
        mutex_unlock(&device->mem_lock);
        pr_warn("allocated reconfig buffers exist but have not been mapped\n");
        return -1;
    }

    if (n_pages > MAX_RECONFIG_BUFF_NUM) {
        dbg_info("requested reconfig buffer too large: %lu pages, max %d pages\n", n_pages, MAX_RECONFIG_BUFF_NUM); 
        mutex_unlock(&device->mem_lock); 
        return -ENOMEM;
    } else {
        device->curr_buff.n_pages = n_pages;
    }
    
    // Allocate page pointer array; each entry is a pointer to a page allocated below (alloc_pages) 
    device->curr_buff.pages = vmalloc(n_pages * sizeof(*device->curr_buff.pages));
    if (device->curr_buff.pages == NULL) {
        pr_warn("failed to allocate page pointer array for reconfig buffers");
        device->curr_buff.n_pages = 0;
        mutex_unlock(&device->mem_lock);
        return -ENOMEM;
    }
    dbg_info(
        "allocated %lu bytes for page pointer array for %ld n_pages of a reconfig buffer, ptr 0x%p\n",
        n_pages * sizeof(*device->curr_buff.pages), n_pages, device->curr_buff.pages
    );
    
    // Allocate the pages for this buffer
    int i;
    for (i = 0; i < device->curr_buff.n_pages; i++) {
        device->curr_buff.pages[i] = alloc_pages(GFP_KERNEL, RECONFIG_BUFF_PAGE_SHIFT - PAGE_SHIFT);
        if (!device->curr_buff.pages[i]) {
            pr_warn("reconfig buffer page %d could not be allocated\n", i);
            goto fail_alloc;
        }
    }

    // Obtain physical addresses for each page
    device->curr_buff.hpages = vmalloc(device->curr_buff.n_pages * sizeof(uint64_t));
    if (device->curr_buff.hpages == NULL) {
        pr_warn("failed to allocate physical address array for reconfig buffers");
        goto fail_alloc;
    }

    for (i = 0; i < device->curr_buff.n_pages; i++) {
        device->curr_buff.hpages[i] = dma_map_single(
            &device->bd_data->pci_dev->dev,
            page_to_virt(device->curr_buff.pages[i]),
            RECONFIG_BUFF_PAGE_SIZE,
            DMA_TO_DEVICE
        );

        if (dma_mapping_error(&device->bd_data->pci_dev->dev, device->curr_buff.hpages[i])) {
            pr_warn("failed to map reconfig page %d and obtain its physical address", i);
            goto fail_dma_map;
        }
    }

    device->curr_buff.pid = pid;
    device->curr_buff.crid = crid;
    mutex_unlock(&device->mem_lock);
    return 0;

fail_dma_map:
    // Unmap DMA
    for (int j = 0; j < i; j++) {
        dma_unmap_single(&device->bd_data->pci_dev->dev, device->curr_buff.hpages[j], RECONFIG_BUFF_PAGE_SIZE, DMA_TO_DEVICE);
    }
    vfree(device->curr_buff.hpages);
    i = device->curr_buff.n_pages;

fail_alloc:
    // Couldn't allocate all the required pages; free the ones that were actually allocated
    while (i) {
        __free_pages(device->curr_buff.pages[--i], RECONFIG_BUFF_PAGE_SHIFT - PAGE_SHIFT);
    }
    device->curr_buff.n_pages = 0;
    vfree(device->curr_buff.pages);

    mutex_unlock(&device->mem_lock);
    return -ENOMEM;
}
