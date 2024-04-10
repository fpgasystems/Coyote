/**
 * Copyright (c) 2023, Systems Group, ETH Zurich
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

#include "hypervisor_mmu.h"

/**
 * @brief Pin user pages allocated in a vm.
 *  This is a modified version to work on the notifier that is passed
 *  down from the vm. 
 *  
 * The function reads the notifier and pins the pages from the vm.
 * The notifier contains gpa addresses. So first the function performs
 * a page table walk from guest physical address (gpa) to host virtual address (hva).
 * We use the hva to pin the corresponding physical pages.
 * 
 * After this step, this function will install mappings on the fpga TLB that correspond
 * to the virtual address given in the notifier. If the function uses the 
 * huge table TLB or the small table TLB depends on the notifier. This information
 * is passed down from the hypervisor. This is because if the vm runs with
 * huge pages all pages inside the vm are seen as huge pages by the hypervisor
 * so we have to pass through the intent on the user with the hypervisor.
 * 
 * In a last step, we actual fire the mapping to the fpga.
 *
 * @param d mediated dev
 * @param notifier notifier from the vm, already copied into the kernel
 * @return int 0 if successfull
 */
int hypervisor_tlb_get_user_pages(struct m_fpga_dev *d, struct hypervisor_map_notifier *notifier)
{
    int ret_val, i, j;
    struct fpga_dev *fd;
    struct bus_drvdata *pd;
    struct mm_struct *curr_mm;
    struct task_struct *curr_task;
    struct kvm *kvm;
    pid_t pid;
    uint64_t first, last;
    uint64_t curr_vaddr, last_vaddr, vaddr_tmp, gva;
    int n_pages, n_pages_huge;
    int hugepages;
    struct user_pages *user_pg;
    uint64_t *hpages_phys, *map_array;
    uint64_t count;
    uint64_t *kvm_hvas;

    ret_val = 0;

    BUG_ON(!d);
    fd = d->fpga;
    BUG_ON(!fd);
    pd = fd->pd;
    BUG_ON(!pd);
    kvm = d->kvm;
    BUG_ON(!kvm);
    BUG_ON(!notifier);
    BUG_ON(notifier->npages == 0);

    // number of pages
    n_pages = notifier->npages;
    gva = notifier->gva;
    dbg_info("Going to pin %d pages for gva %llx\n", n_pages, gva);

    // Get mmu context from kvm process
    curr_mm = kvm->mm;
    pid = kvm->userspace_pid;
    curr_task = pid_task(find_vpid(pid), PIDTYPE_PID);

    // get first host virtual address in kvm space
    kvm_hvas = kcalloc(notifier->npages, sizeof(uint64_t), GFP_KERNEL);
    if (!kvm_hvas)
    {
        goto err_hvas;
    }

    for (i = 0; i < n_pages; i++)
    {
        kvm_hvas[i] = gfn_to_hva(kvm, gpa_to_gfn(notifier->gpas[i]));
    }
    count = notifier->len;

    // hugepages support passed from vm
    hugepages = (int) notifier->is_huge;

    if (hugepages)
    {
        if (n_pages > MAX_N_MAP_HUGE_PAGES)
            n_pages = MAX_N_MAP_HUGE_PAGES;
    }
    else
    {
        if (n_pages > MAX_N_MAP_PAGES)
            n_pages = MAX_N_MAP_PAGES;
    }

    // overflow check
    if (gva + count < gva)
        return -EINVAL;
    if (count == 0)
        return 0;

    // allocate management structs
    user_pg = kzalloc(sizeof(struct user_pages), GFP_KERNEL);
    if (!user_pg)
    {
        ret_val = -ENOMEM;
        goto err_user_pg;
    }

    user_pg->hpages = kcalloc(n_pages, sizeof(struct page *), GFP_KERNEL);
    if (!user_pg->hpages)
    {
        ret_val = -ENOMEM;
        goto err_hpages;
    }

    // Pin all pages obtained from the vm
    for (i = 0; i < n_pages; i++)
    {
        // pin pages of the kvm
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 9, 0)
        ret_val = get_user_pages_remote(curr_mm, (unsigned long)kvm_hvas[i], 1, 1, user_pg->hpages + i, NULL, NULL);
#else
        ret_val = get_user_pages_remote(curr_task, curr_mm, (unsigned long)kvm_hvas[i], n_pages, 1, user_pg->hpages + i, NULL);
#endif
        if (ret_val != 1 || !user_pg->hpages[i])
        {
            pr_info("%s.%d: Failed to pin all pages, failed to map %d with ret_val %d", __func__, __LINE__, i, ret_val);
            goto err_pin_pages;
        }
        // dbg_info("pinned page hpa: %llx\n", page_to_phys(user_pg->hpages[i]));
    }

    dbg_info("Pinned pages\n");

    // Reset ret_val
    ret_val = 0;

    // flush cache
    for (i = 0; i < n_pages; i++)
    {
        flush_dcache_page(user_pg->hpages[i]);
    }

    // populate map entry
    user_pg->vaddr = gva;
    user_pg->n_hpages = n_pages;
    user_pg->huge = hugepages;
    
    dbg_info("mapping vaddr %llx, cpid %llu, hugepages %llu\n", gva, notifier->cpid, notifier->is_huge);

    vaddr_tmp = gva;

    if (hugepages) // For hugepages
    {
        // Shift page numbers to work on huge pages
        first = (gva & pd->ltlb_order->page_mask) >> pd->ltlb_order->page_shift;
        last = ((gva + count - 1) & pd->ltlb_order->page_mask) >> pd->ltlb_order->page_shift;
        n_pages_huge = last - first + 1;
        user_pg->n_pages = n_pages_huge;

        // allocate pages array
        hpages_phys = kzalloc(n_pages_huge * sizeof(uint64_t), GFP_KERNEL);
        if (!hpages_phys)
        {
            ret_val = -ENOMEM;
            goto err_phys_pages;
        }

        j = 0;
        curr_vaddr = gva;
        last_vaddr = -1;

        // Get the hpa for the huge pages
        for (i = 0; i < n_pages; i++)
        {
            // Only store an entry if we encounter a new huge page
            if (((curr_vaddr & pd->ltlb_order->page_mask) >> pd->ltlb_order->page_shift) !=
                ((last_vaddr & pd->ltlb_order->page_mask) >> pd->ltlb_order->page_shift))
            {
                hpages_phys[j] = page_to_phys(user_pg->hpages[i]) & pd->ltlb_order->page_mask;
                last_vaddr = curr_vaddr;
                j++;
            }
            curr_vaddr += PAGE_SIZE;
        }

        // If we have memory attached on the card we want to allocate
        // the same amount of memory on the card
        if (pd->en_mem)
        {
            // Allocate memory
            user_pg->cpages = kzalloc(n_pages_huge * sizeof(uint64_t), GFP_KERNEL);
            if (!user_pg->cpages)
            {
                pr_info("Failed to allocate card buffer");
                ret_val = -ENOMEM;
                goto err_cpages;
            }

            // Alloc 2MB chunks from the card
            ret_val = card_alloc(fd, user_pg->cpages, n_pages_huge, LARGE_CHUNK_ALLOC);
            if (ret_val)
            {
                pr_info("Failed to allocate card memory");
                ret_val = -ENOMEM;
                goto err_card_mem;
            }
            dbg_info("card allocated %d hugepages in hypervisor\n", n_pages_huge);
        }

        // alloc map array
        map_array = kzalloc(n_pages_huge * 2 * sizeof(uint64_t), GFP_KERNEL);
        if (!map_array)
        {
            pr_info("Failed to allocate map buffers\n");
            goto err_map_buffer;
        }

        vaddr_tmp = gva;

        // populate map with mappings from guest virtual address
        // to host physical addresses
        for (i = 0; i < n_pages_huge; i++)
        {
            tlb_create_map(pd->ltlb_order,
                           vaddr_tmp,
                           hpages_phys[i],
                           (pd->en_mem ? user_pg->cpages[i] : 0),
                           notifier->cpid,
                           &map_array[2 * i]);
            vaddr_tmp += pd->ltlb_order->page_size;
        }

#ifndef HYPERVISOR_TEST
        // Fire the fpga to the fpga
        tlb_service_dev(fd, pd->ltlb_order, map_array, n_pages_huge);
#endif

        kfree(map_array);
        kfree(hpages_phys);
    }
    else // For small pages
    {
        user_pg->n_pages = n_pages;

        // if memory is attached to the card we want to allocate
        // the same amount on the card
        if (pd->en_mem)
        {
            // Allocate pages management array
            user_pg->cpages = kzalloc(n_pages * sizeof(uint64_t), GFP_KERNEL);
            if (!user_pg->cpages)
            {
                dbg_info("could not allocate card buffer\n");
                ret_val = -ENOMEM;
                goto err_cpages;
            }
            
            // Allocate 4KB chunks of card memory
            ret_val = card_alloc(fd, user_pg->cpages, n_pages, SMALL_CHUNK_ALLOC);
            if (ret_val)
            {
                dbg_info("could not get all card pages, %d\n", ret_val);
                goto err_card_mem;
            }
        }

        // allocate map array
        map_array = (uint64_t *)kzalloc(n_pages * 2 * sizeof(uint64_t), GFP_KERNEL);
        if (!map_array)
        {
            dbg_info("map buffers could not be allocated\n");
            return -ENOMEM;
        }

        // populate mappings array with guest virtual address
        // to host physical mapping.
        for (i = 0; i < n_pages; i++)
        {
            tlb_create_map(pd->stlb_order,
                           vaddr_tmp,
                           page_to_phys(user_pg->hpages[i]),
                           (pd->en_mem ? user_pg->cpages[i] : 0),
                           notifier->cpid, &map_array[2 * i]);
            vaddr_tmp += pd->stlb_order->page_size;
        }

#ifndef HYPERVISOR_TEST
        // fire interrupt to install the mappings on the fpga
        tlb_service_dev(fd, pd->stlb_order, map_array, n_pages);
#endif

        // free buffers
        kfree(map_array);
        kfree(hpages_phys);
    }

    // Add entry into the sbuff hash map. This is for
    // managment of allocated memory and allows deallocation 
    // later on.
    hash_add(d->sbuff_map, &user_pg->entry, notifier->gva);

    return ret_val;

err_pin_pages:
    for (j = 0; j < i; j++)
    {
        put_page(user_pg->hpages[j]);
    }

    kfree(user_pg->hpages);
    kfree(user_pg);
    kfree(kvm_hvas);
    return -ENOMEM;

err_map_buffer:
    card_free(fd, user_pg->cpages, n_pages_huge, LARGE_CHUNK_ALLOC);
err_card_mem:
    kfree(user_pg->cpages);
err_cpages:
    kfree(hpages_phys);
err_phys_pages:
    for (i = 0; i < user_pg->n_hpages; i++)
    {
        put_page(user_pg->hpages[i]);
    }
err_hpages:
    kfree(user_pg);
err_user_pg:
    kfree(kvm_hvas);
err_hvas:
    return ret_val;
}

/**
 * @brief Unmap an entry described by a
 *  tmp_buffer. This is the hypervisor version 
 *  of the put user pages. This code is a small refactor of the original
 *  version since this function contains the code to actually unmap 
 *  a buffer and in turn is used by the put and put all functions.
 *
 * @param md mediated device
 * @param tmp_buffer user pages struct that describes the mapped region
 * @param dirtied Indicates if all pages should be marked dirty before putting
 * @return int 0 if successfull
 */
static int unmap_entry(struct m_fpga_dev *md, struct user_pages *tmp_buffer, int dirtied)
{
    int i;
    struct fpga_dev *d;
    struct bus_drvdata *pd;
    uint64_t vaddr_tmp, vaddr;
    uint64_t *map_array;
    int32_t cpid;
    struct tlb_order *tlb_order;

    BUG_ON(!md);
    d = md->fpga;
    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);
    BUG_ON(!tmp_buffer);
    BUG_ON(!(tmp_buffer->hpages));

    dbg_info("Putting user_pages entry\n");

    vaddr = tmp_buffer->vaddr;
    cpid = tmp_buffer->cpid;

    // If the pages should be dirtied,
    // go through all pages and mark them as dirty.
    if (dirtied)
    {
        for (i = 0; i < tmp_buffer->n_hpages; i++)
        {
            if (tmp_buffer->hpages[i])
                SetPageDirty(tmp_buffer->hpages[i]);
            else
                dbg_info("entry for page %d is NULL!\n", i);
        }
        dbg_info("Marked pages as dirty\n");
    }

    // Put all pages that belong to this buffer 
    // and allow the machine to evict them from memory 
    // if it desires to do so.
    for (i = 0; i < tmp_buffer->n_hpages; i++)
    {
        // dbg_info("Putting page %d...\n", i);
        if (tmp_buffer->hpages[i])
            put_page(tmp_buffer->hpages[i]);
        else
            dbg_info("entry for page %d is NULL!\n", i);
    }

    // release card pages
    if (pd->en_mem)
    {
        card_free(d, tmp_buffer->cpages, tmp_buffer->n_pages,
                  tmp_buffer->huge ? LARGE_CHUNK_ALLOC : SMALL_CHUNK_ALLOC);
    }

    //
    // Unmap from the TLB
    //
    vaddr_tmp = vaddr;

    // alloc map array
    map_array = (uint64_t *)kzalloc(tmp_buffer->n_pages * 2 * sizeof(uint64_t), GFP_KERNEL);
    if (!map_array)
    {
        dbg_info("map buffers could not be allocated\n");
        return -ENOMEM;
    }

    tlb_order = tmp_buffer->huge ? pd->ltlb_order : pd->stlb_order;

    for (i = 0; i < tmp_buffer->n_pages; i++)
    {
        // This code works for huge and small pages and therefore 
        // there is no need here to seperate the code for the two cases.
        // Create unmap entries in the map array.
        tlb_create_unmap(tlb_order, vaddr_tmp, cpid, &map_array[2 * i]);
        vaddr_tmp += tlb_order->page_size;
    }
#ifndef HYPERVISOR_TEST
    // Fire to actually remove the mappings from the tlb.
    tlb_service_dev(d, tlb_order, map_array, tmp_buffer->n_pages);
#endif
    kfree(map_array);

    dbg_info("Successfully put user pages at gva %llx consisting of %llu pages for cpid %d\n",
             tmp_buffer->vaddr, tmp_buffer->n_hpages, tmp_buffer->cpid);
    return 0;
}

/**
 * @brief Put all card and kernel pages and therefore allow evicitions,
 * as described by the notifier. The notifier contains the vaddr of the 
 * region that should be put. This function searches the hash table
 * for a corresponding mapping and uses the unmap_entry function
 * to unmap the corresponding buffer. Afterwards it removes 
 * the mapping from the hashtable.
 *
 * @param md mediated device
 * @param notifier notifier passed from the vm, copied into kernelspace
 * @return int 0 if successfull
 */
int hypervisor_tlb_put_user_pages(struct m_fpga_dev *md, struct hypervisor_map_notifier *notifier)
{
    struct user_pages *tmp_buff;
    struct fpga_dev *d;
    struct bus_drvdata *pd;

    uint64_t vaddr;
    uint64_t dirtied;
    int32_t cpid;

    BUG_ON(!md);
    d = md->fpga;
    BUG_ON(!d);
    pd = d->pd;

    BUG_ON(!notifier);
    vaddr = notifier->gva;
    dirtied = notifier->dirtied;
    cpid = notifier->cpid;

    // Find all user mappings that map to the same bucket as 
    // vaddr. 
    hash_for_each_possible(md->sbuff_map, tmp_buff, entry, vaddr)
    {
        // Check if it is the correct entry
        if (tmp_buff->vaddr == vaddr && tmp_buff->cpid == cpid)
        {
            // unmap from TLB
            unmap_entry(md, tmp_buff, dirtied);
            // delete from hashtable
            hash_del(&tmp_buff->entry);
            // free memory
            kfree(tmp_buff->hpages);
            kfree(tmp_buff);
        }
    }
    return 0;
}

/**
 * @brief Similar to hypervisor_tlb_put_user_pages but put all pages
 * hold by the device md.
 *
 * @param md mediated device
 * @param dirtied indicates if all pages should be marked dirty before putting
 * @return int 0 if successfull
 */
int hypervisor_tlb_put_user_pages_all(struct m_fpga_dev *md, int dirtied)
{
    struct fpga_dev *d;
    struct bus_drvdata *pd;
    int bkt;
    struct user_pages *tmp_buff;

    BUG_ON(!md);
    d = md->fpga;
    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    // Iterate through all mappings and unmap all
    hash_for_each(md->sbuff_map, bkt, tmp_buff, entry)
    {
        // unmap from TLB
        unmap_entry(md, tmp_buff, dirtied);
        // delete from hash table
        hash_del(&tmp_buff->entry);
        // free memory
        kfree(tmp_buff->hpages);
        kfree(tmp_buff);
    }
    return 0;
}