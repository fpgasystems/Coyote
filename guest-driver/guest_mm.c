#include "guest_mm.h"

struct hlist_head user_sbuff_map[1 << (USER_HASH_TABLE_ORDER)];

/**
 * @brief Release all pages that are hold by the device
 * d. The param dirtied specifies if the pages should be marked
 * dirty before they can be evicted.
 * 
 * @param d vfpga struct
 * @param dirtied 
 * @return int 
 */
int guest_put_all_user_pages(struct vfpga *d, int dirtied)
{
    int i, bkt;
    struct user_pages *tmp_buff;
    
    BUG_ON(!d);

    hash_for_each(user_sbuff_map, bkt, tmp_buff, entry)
    {
        if (dirtied)
        {
            for (i = 0; i < tmp_buff->n_pages; i++)
                SetPageDirty(tmp_buff->hpages[i]);
        }

        for (i = 0; i < tmp_buff->n_pages; i++)
        {
            put_page(tmp_buff->hpages[i]);
        }

        kfree(tmp_buff->hpages);
        hash_del(&tmp_buff->entry);
    }

    // tell hypervisor to flush everything
    writeq((uint64_t) dirtied, (void __iomem *)d->pci_resources.bar2 + PUT_ALL_USER_PAGES);
    
    return 0;
}

/**
 * @brief explictly unmap an existing mapping. 
 * Takes the vaddr and cpid and unmaps an existing mapping
 * from the fpga. It also removes this mapping from the hashtable.
 * 
 * @param d vfpga device
 * @param vaddr start address that is to be unmapped
 * @param cpid cpid that mapped this address
 * @param dirtied mark pages as dirty prior to putting them
 * @return int 
 */
int guest_put_user_pages(struct vfpga *d, uint64_t vaddr, int32_t cpid, int dirtied)
{
    int i;
    struct user_pages *tmp_buff;
    struct hypervisor_map_notifier *notifier;
    uint64_t notifier_addr;

    BUG_ON(!d);

    /*
    Iterate through all possible buckets there the vaddr could be mapped
    to. Check if the found the correct entry and if so, remove it.

    The unmapping involves a call to the hypervisor.
    */
    hash_for_each_possible(user_sbuff_map, tmp_buff, entry, vaddr)
    {
        if (tmp_buff->vaddr == vaddr && tmp_buff->cpid == cpid)
        {
            if (dirtied)
            {
                for (i = 0; i < tmp_buff->n_pages; i++)
                    SetPageDirty(tmp_buff->hpages[i]);
            }

            for (i = 0; i < tmp_buff->n_pages; i++)
            {
                put_page(tmp_buff->hpages[i]);
            }

            // Notifiy hypervisor of unmap
            notifier = kzalloc(sizeof(struct hypervisor_map_notifier), GFP_KERNEL);
            if (!notifier)
            {
                pr_info("failed to allocate memory for the hypervisor notifier");
                return -ENOMEM;
            }

            // populate notifier
            notifier->gva = vaddr;
            notifier->cpid = cpid;
            notifier->dirtied = dirtied;

            // notify
            notifier_addr = virt_to_phys(notifier);
            writeq(notifier_addr, d->pci_resources.bar2 + UNMAP_USER_OFFSET);

            // free
            kfree(notifier);

            // Clean up
            hash_del(&tmp_buff->entry);
            kfree(tmp_buff->hpages);
            // kfree(tmp_buff);
        }
    }

    return 0;
}

/**
 * @brief Pins a user buffer so that it will not be evicted from cache and makes
 * it readable to the vfpga by a call to the hypervisor.
 * 
 * @param d vfpga device
 * @param start start address
 * @param count number of bytes that should be mapped
 * @param cpid cpid of the calling process
 * @param pid pid of the calling process
 * @return int 
 */
int guest_get_user_pages(struct vfpga *d, uint64_t start, size_t count, int32_t cpid, pid_t pid)
{
    uint64_t first, last;
    uint64_t notifier_addr;
    int n_pages;
    int ret_val;
    int i;

    struct task_struct *curr_task;
    struct mm_struct *curr_mm;
    struct vm_area_struct *vma_area_init;
    int hugepages;

    struct user_pages *user_pg;
    struct hypervisor_map_notifier *notifier;

    dbg_info("Getting user pages\n");
    
    ret_val = 0;
    BUG_ON(!d);

    // get mmu context
    curr_task = pid_task(find_vpid(pid), PIDTYPE_PID);
    if (!curr_task)
    {
        dbg_info("failed to get pid\n");
        return -1;
    }
    dbg_info("pid found %d", pid);
    curr_mm = curr_task->mm;

    // Determine if hugepages
    vma_area_init = find_vma(curr_mm, start);
    hugepages = is_vm_hugetlb_page(vma_area_init);

    // number of pages
    first = (start & PAGE_MASK) >> PAGE_SHIFT;
    last = ((start + count - 1) & PAGE_MASK) >> PAGE_SHIFT;
    n_pages = last - first + 1;

    if (start + count < start)
        return -EINVAL;
    if (count == 0)
        return 0;

    // alloc user_pages
    user_pg = kzalloc(sizeof(struct user_pages), GFP_KERNEL);
    if (!user_pg)
    {
        pr_info("Failed to allocate memory\n");
        ret_val = -ENOMEM;
        goto err_user_pg;
    }

    // alloc hardware pages
    user_pg->hpages = kcalloc(n_pages, sizeof(*user_pg->hpages), GFP_KERNEL);
    if (!user_pg->hpages)
    {
        pr_info("Failed to allocate memory\n");
        ret_val = -ENOMEM;
        goto err_hpages;
    }

    dbg_info("allocated buffer for %d pages, passed size %ld.\n", n_pages, count);
    dbg_info("pages=0x%p\n", user_pg->hpages);
    dbg_info("first = %llx, last = %llx\n", first, last);
    dbg_info("hugepages: %d\n", hugepages);

    // Pin the pages
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 9, 0)
    ret_val = get_user_pages_remote(curr_mm, (unsigned long)start, n_pages, 1, user_pg->hpages, NULL, NULL);
#else
    ret_val = get_user_pages_remote(curr_task, curr_mm, (unsigned long)start, n_pages, 1, user_pg->hpages, NULL);
#endif

    // It was not possible to pin all pages
    if (ret_val < n_pages)
    {
        pr_info("could not get all user pages, %d\n", ret_val);
        goto fail_host_unmap;
    }

    // flush data cache for those pages
    for (i = 0; i < n_pages; i++)
        flush_dcache_page(user_pg->hpages[i]);

    // populte user pages struct
    user_pg->vaddr = start;
    user_pg->n_pages = n_pages;
    user_pg->cpid = cpid;

    // Prepare map notifier 
    notifier = kzalloc(sizeof(struct hypervisor_map_notifier) + sizeof(uint64_t) * n_pages, GFP_KERNEL);
    if (!notifier)
    {
        pr_info("Could not allocate notifier\n");
        goto err_notifier;
    }

    // populate notifier
    notifier->gva = start;
    notifier->len = count;
    notifier->cpid = cpid;
    notifier->npages = n_pages;
    notifier->is_huge = hugepages;

    /*
    Do the first step of the page table walk inside the vm
    and pass the guest physical addresses to the hypervisor.
    */
    for (i = 0; i < n_pages; i++)
    {
        notifier->gpas[i] = page_to_phys(user_pg->hpages[i]);
        // dbg_info("Notifier gpa %d is set to %llx\n", i, notifier->gpas[i]);
    }

    dbg_info("populated notifier with %lld pages\n", notifier->npages);

    /*
    Pass physical address to the hypervisor
    */
    notifier_addr = virt_to_phys(notifier);
    writeq(notifier_addr, d->pci_resources.bar2 + MAP_USER_OFFSET);

    dbg_info("Notified hypervisor with notifier at addr 0x%llx\n", notifier_addr);

    kfree(notifier);

    // Add to the hash table
    hash_add(user_sbuff_map, &user_pg->entry, start);

    return 0;
    
err_notifier:
    for (i = 0; i < n_pages; i++)
    {
        put_page(user_pg->hpages[i]);
    }
    kfree(user_pg->hpages);
err_hpages:
    kfree(user_pg);
err_user_pg:
    return ret_val;
fail_host_unmap:
    for (i = 0; i < ret_val; i++)
    {
        put_page(user_pg->hpages[i]);
    }
    kfree(user_pg->hpages);
    kfree(user_pg);
    return -ENOMEM;
}