#include "guest_fops.h"

/**
 * @brief file operations that handle this device
 * 
 */
struct file_operations fops = {
    .open = guest_open,
    .release = guest_release,
    .unlocked_ioctl = guest_ioctl,
    .mmap = guest_mmap};

/**
 * @brief called on opening a file.
 * Sets the file descriptor private data to later on access the
 * device struct easier. 
 *
 * @param inode
 * @param f
 * @return int
 */
int guest_open(struct inode *inode, struct file *f)
{
    struct vfpga *d;

    d = container_of(inode->i_cdev, struct vfpga, cdev);
    BUG_ON(!d);

    dbg_info("fpga device acquired\n");

    f->private_data = (void *)d;

    return 0;
}

/**
 * @brief Called when the device file is closed.
 * Releases all memory associated with this device by performing a 
 * call to the hypervisor and cleaning up all local mappings.
 *
 * @param inode
 * @param f
 * @return int
 */
int guest_release(struct inode *inode, struct file *f)
{
    struct vfpga *d;

    d = (struct vfpga *)f->private_data;
    BUG_ON(!d);

    // release all user pages
    guest_put_all_user_pages(d, 1);

    dbg_info("fpga device released");
    return 0;
}

/**
 * @brief guest version of register pid.
 * Writes to the REGISTER_PID register to
 * notify hypervisor of pid and then reads the same register
 * to get a cpid
 *
 * @param d vfpga struct
 * @param pid pid of the process
 * @return int32_t returns the cpid
 */
static int32_t register_pid(struct vfpga *d, pid_t pid)
{
    uint64_t cpid;
    unsigned long addr;

    BUG_ON(!d);
    addr = (unsigned long)d->pci_resources.bar2 + REGISTER_PID_OFFSET;
    cpid = INVALID_CPID;

    // Write pid to device
    writeq((uint64_t)pid, (void __iomem *)addr);

    // pull cpid
    while (cpid == INVALID_CPID)
    {
        cpid = readq((void __iomem *)addr);
    }

    // store for bookkeeping
    d->pid_array[cpid] = pid;

    return cpid;
}

/**
 * @brief Notifies the hypervisor of the unregistration of a process. Management
 * is handled in the hypervisor.
 *
 * @param d
 * @param cpid
 */
static void unregister_pid(struct vfpga *d, pid_t cpid)
{
    unsigned long addr;

    BUG_ON(!d);
    addr = (unsigned long)d->pci_resources.bar2 + UNREGISTER_PID_OFFSET;

    // write cpid to unregister offset
    writeq((uint64_t)cpid, (void __iomem *)addr);
    d->pid_array[cpid] = 0;
}

/**
 * @brief Handles ioctls to the device. Exposes
 * a similar interface as the normal driver to make it
 * easy to use the library and existing code. The following 
 * ioctl calls are implemented:
 * 
 * - IOCTL_REGISTER_PID
 * Called to register a process. Passes its pid as argument and returns
 * a cpid
 * 
 * - IOCTL_UNREGISTER_PID
 * Called with the cpid and deregisters this cpid again.
 * 
 * - IOCTL_MAP_USER
 * Called with vaddr, length, and cpid. Maps a region allocated by the user
 * to the fpga. 
 * 
 * - IOCTL_UNMAP_USER
 * Called with vaddr and cpid. Unmaps a previously mapped region.
 * 
 * - IOCTL_READ_CNFG
 * Called without any arguments and returns a number that encodes
 * the platform configuration.
 *
 * @param f
 * @param cmd
 * @param arg
 * @return long
 */
long guest_ioctl(struct file *f, unsigned int cmd, unsigned long arg)
{
    struct vfpga *d;
    int ret_val;
    uint64_t tmp[MAX_USER_WORDS];
    uint64_t cpid;

    d = (struct vfpga *)f->private_data;
    BUG_ON(!d);

    dbg_info("ioctl called with cmd %d and arg %lx\n", cmd, arg);

    switch (cmd)
    {
    case IOCTL_REGISTER_PID:
    {
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, sizeof(unsigned long));
        if (ret_val)
        {
            pr_info("Failed to copy from user");
            return ret_val;
        }

        spin_lock(&d->cpid_lock);
        cpid = register_pid(d, tmp[0]);
        if (cpid == -1)
        {
            dbg_info("registraion failed for pid %lld\n", tmp[0]);
            spin_unlock(&d->cpid_lock);
            return -EIO;
        }

        dbg_info("registration succeeded pid %lld, cpid %lld\n", tmp[0], cpid);
        ret_val = copy_to_user((unsigned long *)arg + 1, &cpid, sizeof(unsigned long));
        if (ret_val)
        {
            pr_info("Failed to wirte data");
            spin_unlock(&d->cpid_lock);
            return ret_val;
        }
        spin_unlock(&d->cpid_lock);
        return 0;
    }
    case IOCTL_UNREGISTER_PID:
    {
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, sizeof(unsigned long));
        if (ret_val)
        {
            pr_info("Failed to copy from user");
            return ret_val;
        }

        spin_lock(&d->cpid_lock);

        unregister_pid(d, tmp[0]);

        spin_unlock(&d->cpid_lock);
        dbg_info("unregistration succeeded cpid %lld\n", tmp[0]);

        return 0;
    }
    case IOCTL_MAP_USER:
    {
        // read vaddr + len + cpid
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, sizeof(unsigned long) * 3);
        if (ret_val)
        {
            pr_info("Failed to copy addr info from user\n");
            return ret_val;
        }

        cpid = tmp[2];

        dbg_info("Mapping user vaddr %llx of size %llu for cpid %llu\n", tmp[0], tmp[1], tmp[2]);
        ret_val = guest_get_user_pages(d, tmp[0], tmp[1], (int32_t)tmp[2], d->pid_array[cpid]);
        return ret_val;
    }
    case IOCTL_UNMAP_USER:
    {
        // read vaddr + cpid
        ret_val = copy_from_user(&tmp, (unsigned long *)arg, sizeof(unsigned long) * 2);
        if (ret_val)
        {
            pr_info("could not get addr info from user\n");
            return ret_val;
        }

        dbg_info("Putting user pages\n");
        ret_val = guest_put_user_pages(d, tmp[0], (int32_t)tmp[1], 1);
        return ret_val;
    }
    case IOCTL_READ_CNFG:
    {
        tmp[0] = readq((void __iomem *)d->pci_resources.bar2 + READ_CNFG_OFFSET);
        ret_val = copy_to_user((unsigned long *)arg, &tmp, sizeof(unsigned long));
        if (ret_val)
        {
            pr_info("Cannot read configuration\n");
            return ret_val;
        }
        return 0;
    }
    case IOCTL_TEST_INTERRUPT:
    {
        writeq(0, d->pci_resources.bar2 + TEST_INTERRUPT_OFFSET);
        return 0;
    }
    }

    // Not supported IOCTL
    return -EINVAL;
}

/**
 * @brief mmap of regions of the fpga. The actual fpga is here not available
 * we map into bar0 of the virtual device that acts as a passthrough to the
 * real hardware. Transparent to the user.
 *
 * @param f
 * @param vma
 * @return int
 */
int guest_mmap(struct file *f, struct vm_area_struct *vma)
{
    struct vfpga *d;
    unsigned long vaddr;
    unsigned long target_addr;
    int ret_val;

    d = (struct vfpga *)f->private_data;
    BUG_ON(!d);

    vaddr = vma->vm_start;

    dbg_info("called mmap with offset %lu\n", vma->vm_pgoff);

    // Do not cache this pages
    vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);

    // user ctrl region
    if (vma->vm_pgoff == MMAP_CTRL)
    {
        dbg_info("mapping user ctrl region at %llx of size %x\n",
            d->fpga_phys_addr_ctrl + FPGA_CTRL_USER_OFFS, FPGA_CTRL_USER_SIZE);
        target_addr = (unsigned long)d->fpga_phys_addr_ctrl + FPGA_CTRL_USER_OFFS;

        ret_val = remap_pfn_range(vma, vma->vm_start, target_addr >> PAGE_SHIFT,
                                  FPGA_CTRL_USER_SIZE, vma->vm_page_prot);
        if (ret_val)
        {
            return -EIO;
        }
        return 0;
    }

    // cnfg region
    if (vma->vm_pgoff == MMAP_CNFG)
    {
        dbg_info("mapping config region at %llx of size %x\n",
            d->fpga_phys_addr_ctrl + FPGA_CTRL_CNFG_OFFS, FPGA_CTRL_USER_SIZE);
        target_addr = (unsigned long)d->fpga_phys_addr_ctrl + FPGA_CTRL_CNFG_OFFS;

        ret_val = remap_pfn_range(vma, vma->vm_start, target_addr >> PAGE_SHIFT,
                                  FPGA_CTRL_CNFG_SIZE, vma->vm_page_prot);
        if (ret_val)
        {
            return -EIO;
        }
        return 0;
    }

    // cnfg AVX region
    if (vma->vm_pgoff == MMAP_CNFG_AVX)
    {
        dbg_info("mapping config AVX region at %llx of size %x\n",
            d->fpga_phys_addr_ctrl_avx, FPGA_CTRL_CNFG_AVX_SIZE);
        target_addr = (unsigned long)d->fpga_phys_addr_ctrl_avx;

        ret_val = remap_pfn_range(vma, vma->vm_start, target_addr >> PAGE_SHIFT,
                                  FPGA_CTRL_CNFG_AVX_SIZE, vma->vm_page_prot);
        if (ret_val)
        {
            return -EIO;
        }
        return 0;
    }

    return -EINVAL;
}