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

#include "hypervisor_ops.h"

/**
 * @brief Set the up capability section of the pci config space.
 * At the moment this includes the MSIX capability and the PCI express
 * endpoint capability which is copied from the actual hardware. 
 * This of course only happens if we are on PCI platform.
 * 
 * @param cfg 
 * @param pd 
 */
static void set_up_cap_section(struct pci_config_space *cfg, struct bus_drvdata *pd)
{
    struct cap_header *header;
    uint8_t offset;
    int i;

    // Init at the first position for the cap list
    cfg->cap_pointer = MSIX_OFFSET;
    // Let the OS know that this device has caps
    cfg->status |= BIT(4);

    set_up_msix_header(cfg, MSIX_OFFSET, NUM_INTERRUPTS);

    // Get header
    header = (struct cap_header *)((uint8_t *)cfg + MSIX_OFFSET);
    
    // If we are on a PCI platform, copy the endpoint header
    if (cyt_arch == CYT_ARCH_PCI)
    {
        // Point to the next cap
        header->next_pointer = MSIX_OFFSET + MSIX_SIZE;

        // Copy cap struct from pci device
        offset = pci_find_capability(pd->pci_dev, PCI_CAP_ID_EXP);
        for (i = 0; i < PCI_CAP_PCIX_SIZEOF_V2; i++)
        {
            pci_read_config_byte(pd->pci_dev,
                                offset + i, (uint8_t *)cfg + MSIX_OFFSET + MSIX_SIZE + i);
        }

        header = (struct cap_header *)((uint8_t *)cfg + MSIX_OFFSET + MSIX_SIZE);
    }
    header->next_pointer = 0;
}

/**
 * @brief Sets the pci configuration of the mdev
 * on creation of the virtual device. The configuration space
 * communicates to the guest os that we use 3 64bit bars 
 * and communicates the size of these bars. Furthermore
 * we emulate the the vendor_id 0x0102 and device_id 0x0304.
 * TODO: Discuss a change to the illeagal address 0xffff 
 * for the vendor id. QEMU replaces this illeageal id 
 * with an free vendor id. However, this might not be the
 * case for other emulation solutions.
 *
 * @param cfg pointer to pci_config_space
 */
static void set_pci_config(struct pci_config_space *cfg,
                           struct bus_drvdata *pd)
{

    uint64_t bar0_addr, bar2_addr, bar4_addr;

    // Clear memory
    memset(cfg, 0, sizeof(struct pci_config_space));

    // Device id
    cfg->vendor_id = 0x0102;
    cfg->device_id = 0x0304;

    // Can control the (virtual) bus
    cfg->command = PCI_COMMAND_IO | PCI_COMMAND_MEMORY;

    // No status
    cfg->status = 0x0200;

    cfg->revison_id = 0x10;
    cfg->programming_interface = 0x00;
    cfg->subclass = 0x00;
    cfg->class_code = 0xff;

    // Bar0: 64 bit in memory mode
    bar0_addr = COYOTE_HYPERVISOR_BAR0_MASK |
                PCI_BASE_ADDRESS_MEM_TYPE_64 |
                PCI_BASE_ADDRESS_SPACE_MEMORY;

    if (COYOTE_HYPERVISOR_BAR0_SIZE)
    {
        cfg->bar0 = bar0_addr;
        cfg->bar1 = (uint32_t)(bar0_addr >> 32);
    }

    // Bar2: 64 bit in memory mode
    bar2_addr = COYOTE_HYPERVISOR_BAR2_MASK |
                PCI_BASE_ADDRESS_MEM_TYPE_64 |
                PCI_BASE_ADDRESS_SPACE_MEMORY;

    if (COYOTE_HYPERVISOR_BAR2_SIZE)
    {
        cfg->bar2 = (uint32_t)bar2_addr;
        cfg->bar3 = (uint32_t)(bar2_addr >> 32);
    }

    // Bar4: 64 bit in memory mode
    bar4_addr = COYOTE_HYPERVISOR_BAR4_MASK |
                PCI_BASE_ADDRESS_MEM_TYPE_64 |
                PCI_BASE_ADDRESS_SPACE_MEMORY;

    if (COYOTE_HYPERVISOR_BAR4_SIZE)
    {
        cfg->bar4 = (uint32_t)bar4_addr;
        cfg->bar5 = (uint32_t)(bar4_addr >> 32);
    }

    // Init cap list
    set_up_cap_section(cfg, pd);

    // Interrupt pin
    cfg->interrupt_pin = 0x01;
}

/**
 * @brief handles create operation for the mediated device
 * allocates data structures and does basic initizalization.
 * This function should only called from the mdev framework!
 *
 * @param mdev passed from the vfio_mdev framework
 * @return int zero on success
 */
static int hypervisor_vfpga_create(struct mdev_device *mdev)
{
    struct device *dev;
    struct bus_drvdata *d;
    struct fpga_dev *fpga;
    struct m_fpga_dev *m_vfpga;
    int i;
    int ret_val;

    ret_val = 0;
    dbg_info("Create start.\n");

    // Load parent data to find out
    // the fpga region we belong to
    BUG_ON(!mdev);
    dev = mdev_parent_dev(mdev);
    if (!dev)
    {
        pr_err("Failed to get mdev parent device\n");
        return -EIO;
    }
    d = dev_get_drvdata(dev);
    if (!d)
    {
        pr_err("Failed to get bus drv data\n");
        return -EIO;
    }

    dbg_info("Got info\n");

    // Get id of parent device by parsing the name
    sscanf(dev->kobj.name, "fpga%d", &i);
    dbg_info("Create for parent device %d\n", i);
    // use the id to get the fpga_dev
    fpga = &d->fpga_dev[i];

    BUG_ON(!fpga);
    dbg_info("Got fpga\n");

    // allocate mangement struct for the new mediated device
    m_vfpga = kzalloc(sizeof(struct m_fpga_dev), GFP_KERNEL);
    if (!m_vfpga)
    {
        pr_err("failed to allocate m_vfpga memory\n");
        return -ENOMEM;
    }

    m_vfpga->fpga = fpga;
    m_vfpga->current_cpid = INVALID_CPID;

    // Get vcid. Unique per fpga region and 
    // used to make the pid unique
    spin_lock(&fpga->vcid_lock);
    m_vfpga->id = fpga->vcid_alloc->id;
    fpga->vcid_alloc = fpga->vcid_alloc->next;
    fpga->num_free_vcid_chunks -= 1;
    spin_unlock(&fpga->vcid_lock);

    // Set up pci config
    set_pci_config(&m_vfpga->pci_config, d);

    // Init locks
    spin_lock_init(&m_vfpga->lock);
    spin_lock_init(&m_vfpga->current_cpid_lock);

    // add into the list of virtual fpgas
    spin_lock(&fpga->list_lock);
    list_add(&m_vfpga->next, &fpga->mdev_list);
    spin_unlock(&fpga->list_lock);

    mdev_set_drvdata(mdev, m_vfpga);

    dbg_info("successfully created medaited vfpga device\n");

    return ret_val;
}

/**
 * @brief Called on deletion of the mediated device.
 * Furthermore it frees up the vcid and removes it from 
 * the list of fpgas. This function should only be called from the
 * mdev framework!
 *
 * @param mdev passed from the mdev framework
 * @return int zero on success
 */
static int hypervisor_vfpga_remove(struct mdev_device *mdev)
{
    struct fpga_dev *fpga;
    struct m_fpga_dev *m_vfpga;

    m_vfpga = mdev_get_drvdata(mdev);
    fpga = m_vfpga->fpga;

    // release vcid
    spin_lock(&fpga->vcid_lock);
    fpga->vcid_chunks[m_vfpga->id].next = fpga->vcid_alloc;
    fpga->vcid_alloc = &fpga->vcid_chunks[m_vfpga->id];
    fpga->num_free_pid_chunks += 1;
    spin_unlock(&fpga->vcid_lock);

    // Remove from the list of virtual vFPGAs
    spin_lock(&fpga->list_lock);
    list_del(&m_vfpga->next);
    spin_unlock(&fpga->list_lock);

    // Free memory
    kfree(m_vfpga);

    dbg_info("successfully removed mdeiated vfpga device\n");

    return 0;
}

/**
 * @brief handler function for the vfio kvm notify event.
 * Only called by the vfio framework. For example, if we use qemu
 * this function is called by qemu to let out module know which
 * kvm it is using. This is later needed to do page table walks inside
 * this module.
 *
 * @param nb notifier block from vfio
 * @param action what event happend
 * @param data payload
 * @return int zero on success
 */
int hypervisor_vfio_notifier(struct notifier_block *nb, unsigned long action, void *data)
{
    struct m_fpga_dev *vfpga;

    vfpga = container_of(nb, struct m_fpga_dev, notifier);

    spin_lock(&vfpga->lock);

    // only do something if this is a set kvm event
    if (action == VFIO_GROUP_NOTIFY_SET_KVM)
    {
        vfpga->kvm = data;
        dbg_info("kvm set successfully");
    }

    spin_unlock(&vfpga->lock);

    return 0;
}

/**
 * @brief handles the opening of the mediated device file (after creation)
 * this happens if the vm boots and therefore the file 
 * is opened from the hypervisor to emulate the pci device. This function
 * does most of the allocation to allow the emulation. 
 * This includes the MSIX region setup and the registration
 * of the kvm notifier.
 *
 * @param mdev passed from the mdev framework
 * @return int zero on success
 */
static int hypervisor_vfpga_open(struct mdev_device *mdev)
{
    struct m_fpga_dev *vfpga;
    long unsigned int events;
    int ret_val;
    int i;

    ret_val = 0;

    // Get virtual vFGPA struct
    vfpga = mdev_get_drvdata(mdev);

    spin_lock(&vfpga->lock);
    // mediated vfpgas are only inteded for the use by one vm at the time
    if (vfpga->in_use)
    {
        dbg_info("Failed to open vfio device: busy\n");
        spin_unlock(&vfpga->lock);
        return -EBUSY;
    }

    // Set busy
    vfpga->in_use = 1;
    spin_unlock(&vfpga->lock);

    // allocate msix table
    // TODO: remove this, seems to be handled by QEMU
    vfpga->msix_table = kzalloc(2000, GFP_KERNEL);
    if (!vfpga->msix_table)
    {
        dbg_info("Failed to allocate msix tabel\n");
        ret_val = -ENOMEM;
        goto err_msix_table;
    }

    // allocate array for eventfd fds
    vfpga->msix_vector = kzalloc(NUM_INTERRUPTS * sizeof(struct msix_interrupt), GFP_KERNEL);
    if (!vfpga->msix_vector)
    {
        dbg_info("Failed to allocate msix interrupts\n");
        ret_val = -ENOMEM;
        goto err_msix_interrupts;
    }

    // expliclty invalidate all file descriptors entries
    for (i = 0; i < NUM_INTERRUPTS; i++)
    {
        vfpga->msix_vector[i].eventfd = -1;
    }

    // Init memory maps
    hash_init(vfpga->sbuff_map);

    /* We know that this is the only thread accessing this device */

    // Register KVM notifier
    events = VFIO_GROUP_NOTIFY_SET_KVM;
    vfpga->notifier.notifier_call = hypervisor_vfio_notifier;
    ret_val = vfio_register_notifier(mdev_dev(mdev), VFIO_GROUP_NOTIFY, &events, &vfpga->notifier);
    if (ret_val)
    {
        pr_err("notifier registration failed\n");
    }

    dbg_info("successfully opened mediated vfpga\n");

    return ret_val;

err_msix_interrupts:
    kfree(vfpga->msix_table);
err_msix_table:
    return ret_val;
}

/**
 * @brief called when the device file is closed. This happens if the vm shuts down
 * removes every state that was associated with the current vm. This includes
 * to disable all current interrupts and free all msix data.
 *
 * @param mdev mdev device in question
 */
static void hypervisor_vfpga_close(struct mdev_device *mdev)
{
    struct m_fpga_dev *vfpga;
    int ret_val;

    ret_val = 0;

    // Get virtual vFGPA struct
    vfpga = mdev_get_drvdata(mdev);

    spin_lock(&vfpga->lock);

    BUG_ON(!vfpga->in_use);

    // unset all interrupts
    msix_unset_all_interrupts(vfpga);

    // Set free
    vfpga->in_use = 0;
    spin_unlock(&vfpga->lock);

    // free allocated memory
    kfree(vfpga->msix_table);
    kfree(vfpga->msix_vector);

    // Unregister vfio notifier
    ret_val = vfio_unregister_notifier(mdev_dev(mdev), VFIO_GROUP_NOTIFY, &vfpga->notifier);
    if (ret_val)
    {
        dbg_info("Failed to unregister VFIO notifier\n");
    }

    dbg_info("Closed mediated vfpga file\n");
}

/**
 * @brief General function to access data inside of the vm,
 * allows to read and write from the vm that is associated with the vfpga.
 * Only works after the device file was opened!
 *
 * @param vfpga mediated vfpga device
 * @param gpa guest physical address
 * @param count bytes to read/write
 * @param buf source/target buffer
 * @param write
 * @return ssize_t
 */
static ssize_t hypervisor_access_kvm(struct m_fpga_dev *vfpga,
                                     gpa_t gpa,
                                     size_t count,
                                     void *buf,
                                     int write)
{
    struct kvm *kvm;
    int ret_val;
    int idx;

    kvm = vfpga->kvm;
    BUG_ON(!kvm);

    ret_val = 0;

    dbg_info("Accessing kvm at gpa %llx to %s %lu bytes", gpa, (write ? "write" : "read"), count);

    /*
    The function uses the page tables of the vm and 
    therefore they are not allowed to change during the translation.
    Therefore we have to hold the srce lock.
    */
    idx = srcu_read_lock(&kvm->srcu);
    if (write)
    {
        ret_val = kvm_write_guest(kvm, gpa, buf, count);
    }
    else
    {
        ret_val = kvm_read_guest(kvm, gpa, buf, count);
    }

    if (ret_val)
    {
        pr_info("Failed to %s kvm\n", (write ? "write" : "read"));
    }
    srcu_read_unlock(&kvm->srcu, idx);

    return ret_val;
}

/**
 * @brief Bar0 access are relayed to the actual hardware for
 * calls that would be mmap in a not vm scenario. BAR0 acts as a passthrough
 * for this cases and are mmaped in the vm. Therefore this function is 
 * not used and should not be used since the trap comes at a very high cost 
 * and should be avoided whenever possible!
 *
 * @param vfpga mediated vfpga
 * @param buf read/write buffer
 * @param count bytes to read/write
 * @param pos offset into the bar register
 * @param write 1 for write
 * @return ssize_t bytes read/write
 */
static ssize_t handle_bar0_access(struct m_fpga_dev *vfpga, char __user *buf,
                                  size_t count, loff_t pos, int write)
{
    uint64_t offset;
    uint64_t index;
    struct fpga_dev *d;
    uint64_t tmp[64];
    void __iomem *ioaddr;
    int ret_val;
    ret_val = 0;

    BUG_ON(!vfpga);
    d = vfpga->fpga;
    BUG_ON(!d);

    /*
    20 is the shift that is used for the subregions between the not avx and avx 
    regions. Therefore to differentiate between accesses of this two regions 
    the fastes way is to compute the value of the upper bits.
    */
    index = pos >> 20;
    offset = pos & ((1 << 20) - 1);
    if (write)
    {
        dbg_info("Accessing bar0 at addr %#llx and offset %#llx with count %lu at index %llx\n", pos, offset, count, index);
    }

    switch (index)
    {
    case 0x1:
        /*
        Depending on the offset into the region we want to access at different
        mappings. This is happening here. This is one of the reasons why a trap
        is not very efficent.
        */
        if (offset >= FPGA_CTRL_LTLB_OFFS && offset < FPGA_CTRL_LTLB_SIZE + FPGA_CTRL_LTLB_OFFS)
        {
            ioaddr = (void __iomem *)vfpga->fpga->fpga_lTlb + (offset - FPGA_CTRL_LTLB_OFFS);
        }
        else if (offset >= FPGA_CTRL_STLB_OFFS && offset < FPGA_CTRL_STLB_SIZE + FPGA_CTRL_STLB_OFFS)
        {
            ioaddr = (void __iomem *)vfpga->fpga->fpga_sTlb + (offset - FPGA_CTRL_STLB_OFFS);
        }
        else if (offset >= FPGA_CTRL_USER_OFFS && offset < FPGA_CTRL_USER_OFFS + FPGA_CTRL_USER_SIZE)
        {
            ioaddr = (void __iomem *)vfpga->fpga->fpga_user + (offset - FPGA_CTRL_USER_OFFS);
        }
        else if (offset >= FPGA_CTRL_CNFG_OFFS && offset < FPGA_CTRL_CNFG_OFFS + FPGA_CTRL_CNFG_SIZE)
        {
            ioaddr = (void __iomem *)vfpga->fpga->fpga_cnfg + (offset - FPGA_CTRL_CNFG_OFFS);
        }
        else
        {
            return -EFAULT;
        }
        break;
    case 0x10:
        /*
        For avx accesses we do not have this problem. However, during testing we found out
        that this part is not working. The corresponding avx instrunction cannot
        be trapped and therefore if the corresponding region is not mmaped we cannot
        use avx.
        */
        ioaddr = (void __iomem *)vfpga->fpga->fpga_cnfg_avx + offset;
        break;
    default:
        dbg_info("Access to unspported offset!\n");
        return -EFAULT;
    }

    if (write)
        dbg_info("%s at ioaddr %p\n", write ? "write" : "read", ioaddr);

    if (write)
        dbg_info("tmp addr %p and buf addr %p\n", tmp, buf);

#ifndef HYPERVISOR_TEST
    if (write)
    {
        // copy from user
        ret_val = copy_from_user(tmp, buf, count);
        BUG_ON(ret_val);
        memcpy_toio(ioaddr, tmp, count);
        // write through to hardware
        dbg_info("performed write to ioaddr %p of %lu bytes, first 8 bytes %#016llx", ioaddr, count, tmp[0]);
    }
    else
    {
        // copy from io to user 
        memcpy_fromio(tmp, ioaddr, count);
        ret_val = copy_to_user(buf, tmp, count);
        BUG_ON(ret_val);
    }

#endif

    return count;
}

/**
 * @brief BAR2 is for communication between the hypervisor
 * and the guest driver. These are virtualized versions of the IOCTL
 * calls in fpga_fops. This function only handles reads from the register.
 * Here are control functions trapped and handled according to the 
 * desired behaviour but in a mediated manner. All these
 * calls are made by the guest driver to communicate with the hypervisor.
 * The instructions are:
 * 
 * REGISTER_PID:
 * Register PID. This is used in combination with a write to REGISTER_PID.
 * The read returns a new CPID that can be used by the guest.
 * 
 * READ_CNFG:
 * Read through of the the corresponding ioctl call. Returns key 
 * configuration parameters of the fpga platform.
 *
 * @param vfpga mediated vfpga
 * @param buf read buffer
 * @param count bytes to read
 * @param pos offset into the register
 * @return ssize_t bytes read
 */
static ssize_t handle_bar2_read(struct m_fpga_dev *vfpga, char __user *buf,
                                size_t count, loff_t pos)
{
    loff_t offset;
    int ret_val;
    uint64_t tmp[MAX_USER_WORDS];
    struct fpga_dev *d;
    struct bus_drvdata *pd;

    BUG_ON(!vfpga);
    d = vfpga->fpga;
    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    // The lower 32 bit represent a command that should be executed
    offset = pos & HYPERVISOR_OFFSET_MASK;
    switch (offset)
    {
    case REGISTER_PID_OFFSET:
    {
        spin_lock(&vfpga->current_cpid_lock);
        ret_val = copy_to_user(buf, &vfpga->current_cpid, sizeof(&vfpga->current_cpid));
        if (ret_val)
        {
            pr_err("%s.%u: Failed to read\n", __func__, __LINE__);
            spin_unlock(&vfpga->current_cpid_lock);
            return -EFAULT;
        }

        // Reset cpid
        vfpga->current_cpid = INVALID_CPID;
        spin_unlock(&vfpga->current_cpid_lock);

        return count;
    }
    case READ_CNFG_OFFSET:
    {
        if (!IS_ALIGNED(pos, 8))
        {
            dbg_info("READ_CNFG not correctly alligned\n");
            return -EFAULT;
        }

        if (count != 8)
        {
            dbg_info("READ_CNFG not 8 byte read\n");
            return -EFAULT;
        }

#ifdef HYPERVISOR_TEST
        tmp[0] = 0xdeadbeef;
#else
        tmp[0] = ((uint64_t)pd->n_fpga_chan << 32) | ((uint64_t)pd->n_fpga_reg << 48) |
                 ((uint64_t)pd->en_avx) | ((uint64_t)pd->en_bypass << 1) | ((uint64_t)pd->en_tlbf << 2) | ((uint64_t)pd->en_wb << 3) |
                 ((uint64_t)pd->en_strm << 4) | ((uint64_t)pd->en_mem << 5) | ((uint64_t)pd->en_pr << 6) |
                 ((uint64_t)pd->en_rdma_0 << 16) | ((uint64_t)pd->en_rdma_1 << 17) | ((uint64_t)pd->en_tcp_0 << 18) | ((uint64_t)pd->en_tcp_1 << 19);
#endif
        dbg_info("reading config 0x%llx\n", tmp[0]);

        ret_val = copy_to_user(buf, tmp, count);

        if (ret_val)
        {
            dbg_info("Failed to copy to user\n");
            return -EFAULT;
        }

        return count;
    }
    default:
    {
        // Not mapped, return no meaningful data
        return count;
    }
    }
}

/**
 * @brief AVX passthrough. this is not implemented for the simple reason, 
 * that trapping AVX instrunctions does not work at the moment. Therefore if 
 * this function would be needed it would not work and therefore the user should
 * fallback to a bitstream that does not use avx. 
 *
 * @param vfpga
 * @param buf
 * @param count
 * @param pos
 * @param is_write
 * @return ssize_t
 */
static ssize_t handle_bar4_access(struct m_fpga_dev *vfpga, char __user *buf,
                                  size_t count, loff_t pos, int is_write)
{
    return count;
}

/**
 * @brief Called by the vfpga framework for any access to the virtual pci
 * device in the vm. Based on the region accessed the access is handled
 * by a special function. Therefore this function acts as a simple
 * demultiplexer.
 *
 * @param mdev mediated vfpga device
 * @param buf read buffer
 * @param count bytes to read
 * @param ppos position, this is determined by VFIO by IOCTL calls to the driver, handled below
 * @return ssize_t bytes read
 */
static ssize_t hypervisor_vfpga_read(struct mdev_device *mdev, char __user *buf,
                                     size_t count, loff_t *ppos)
{
    loff_t pos, offset, index;
    int ret_val;
    struct m_fpga_dev *vfpga;

    pos = *ppos;
    offset = pos & HYPERVISOR_OFFSET_MASK;
    index = COYOTE_GET_INDEX(pos);
    ret_val = 0;
    vfpga = mdev_get_drvdata(mdev);

    switch (index)
    {
    case VFIO_PCI_CONFIG_REGION_INDEX:
    {
        // dbg_info("Reading pci config at offset %llu, reading %lu bytes\n", offset, count);
        if (offset + count > COYOTE_HYPERVISOR_CONFIG_SIZE)
        {
            pr_err("%s.%u: Out of bound read\n", __func__, __LINE__);
            return -EFAULT;
        }

        // Read from in memory config
        ret_val = copy_to_user(buf, ((char *)&vfpga->pci_config) + offset, count);
        if (ret_val)
        {
            pr_err("%s.%u: Failed to read\n", __func__, __LINE__);
            return -EFAULT;
        }

        return count;
    }
    case VFIO_PCI_BAR0_REGION_INDEX:
    {
        // Check bounds
        if (offset + count > COYOTE_HYPERVISOR_BAR0_SIZE)
        {
            pr_err("%s.%u: Out of bound read\n", __func__, __LINE__);
            return -EFAULT;
        }

        return handle_bar0_access(vfpga, buf, count, pos, 0);
    }
    case VFIO_PCI_BAR2_REGION_INDEX:
    {
        // Check bounds
        if (offset + count > COYOTE_HYPERVISOR_BAR2_SIZE)
        {
            pr_err("%s.%u: Out of bound read\n", __func__, __LINE__);
            return -EFAULT;
        }

        return handle_bar2_read(vfpga, buf, count, pos);
    }
    case VFIO_PCI_BAR4_REGION_INDEX:
    {
        // Check bounds
        if (offset + count > COYOTE_HYPERVISOR_BAR4_SIZE)
        {
            pr_err("%s.%u: Out of bound read\n", __func__, __LINE__);
            return -EFAULT;
        }

        return handle_bar4_access(vfpga, buf, count, pos, 0);
    }
    default:
    {
        // Not a valid region to read
        pr_debug("%s.%u: Read to invalid region %lld\n", __func__, __LINE__, index);
        return 0;
    }
    }
}

/**
 * @brief write to a base address register (BAR). Keeps the lowest 4 bits
 * at all time, since they contain non writeable bits.
 *
 * @param bar pointer to BAR
 * @param val value to be written
 * @param low write to low(1) or high(0) register
 */
static void cfg_bar_write(uint32_t *bar, uint32_t val, int low)
{
    if (low)
    {
        *bar = (val & GENMASK(31, 4)) |
               (*bar & GENMASK(3, 0));
    }
    else
    {
        *bar = val;
    }
}

/**
 * @brief Function to handle writes to the PCI config. Not all writes should be permitted
 * so this function emulates that should happen if we would wirte to an actual pci device
 * TODO: Here is some functionaly missing, but at the moment the relevant subset is implemented
 *
 * @param fpga mediated vfpga that the wrote is to
 * @param buf write buffer
 * @param count bytes to write
 * @param pos offset into the configuration space
 * @return int zero on success
 */
static int handle_pci_cfg_write(struct m_fpga_dev *fpga, char __user *buf, size_t count, loff_t pos)
{
    uint32_t new_val;
    int ret_val;

    ret_val = copy_from_user(&new_val, buf, count);
    if (ret_val)
    {
        dbg_info("could not copy new pci cfg value from userspace\n");
        return -EFAULT;
    }

    pos = pos & HYPERVISOR_OFFSET_MASK;

    switch (pos)
    {
    case 0x10: // BAR 0
        if (new_val == GENMASK(31, 0))
        {
            cfg_bar_write(&fpga->pci_config.bar0, (uint32_t)(COYOTE_HYPERVISOR_BAR0_MASK | PCI_BASE_ADDRESS_MEM_TYPE_64 | PCI_BASE_ADDRESS_SPACE_MEMORY), 1);
        }
        else
        {
            cfg_bar_write(&fpga->pci_config.bar0, new_val, 1);
        }
        break;
    case 0x14: // BAR 1
        if (new_val == GENMASK(31, 0))
        {
            cfg_bar_write(&fpga->pci_config.bar1, (uint32_t)(~(COYOTE_HYPERVISOR_BAR0_SIZE - 1) >> 32), 0);
        }
        else
        {
            cfg_bar_write(&fpga->pci_config.bar1, new_val, 0);
        }
        break;
    case 0x18: // BAR 2
        if (new_val == GENMASK(31, 0))
        {
            cfg_bar_write(&fpga->pci_config.bar2, (uint32_t)(COYOTE_HYPERVISOR_BAR2_MASK | PCI_BASE_ADDRESS_MEM_TYPE_64 | PCI_BASE_ADDRESS_SPACE_MEMORY), 1);
        }
        else
        {
            cfg_bar_write(&fpga->pci_config.bar2, new_val, 1);
        }
        break;
    case 0x1C: // BAR 3
        if (new_val == GENMASK(31, 0))
        {
            cfg_bar_write(&fpga->pci_config.bar3, (uint32_t)(~(COYOTE_HYPERVISOR_BAR2_SIZE - 1) >> 32), 0);
        }
        else
        {
            cfg_bar_write(&fpga->pci_config.bar3, new_val, 0);
        }
        break;
    case 0x20: // BAR 4
        if (new_val == GENMASK(31, 0))
        {
            cfg_bar_write(&fpga->pci_config.bar4, (uint32_t)(COYOTE_HYPERVISOR_BAR4_MASK | PCI_BASE_ADDRESS_MEM_TYPE_64 | PCI_BASE_ADDRESS_SPACE_MEMORY), 1);
        }
        else
        {
            cfg_bar_write(&fpga->pci_config.bar4, new_val, 1);
        }
        break;
    case 0x24: // BAR 5
        if (new_val == GENMASK(31, 0))
        {
            cfg_bar_write(&fpga->pci_config.bar5, (uint32_t)(~(COYOTE_HYPERVISOR_BAR4_SIZE - 1) >> 32), 0);
        }
        else
        {
            cfg_bar_write(&fpga->pci_config.bar5, new_val, 0);
        }
        break;
    case 0x3C: // Interrupt line
        fpga->pci_config.interrupt_line = (uint8_t)new_val;
        break;
    default:
        if (pos >= MSIX_OFFSET && pos < MSIX_OFFSET + MSIX_SIZE)
        {
            // Emulate write to msix header
            ret_val = write_to_msix_header((void *)(fpga->pci_config.cap_section + MSIX_OFFSET), pos - MSIX_OFFSET, new_val, count);
            if (ret_val < 0)
            {
                return ret_val;
            }
        }
        else
        {
            // dbg_info("write to fpga config with %lu not handled writes at offset 0x%llx",
            //          count, pos);
        }
    }

    return 0;
}

/**
 * @brief This function handles most of the communication.
 * The offset is interpreted as command to the hypervisor and 
 * the value of the write can be used as argument either to pass a simple
 * number or in case of more complicated data it passes a pointer to data
 * inside the vm. 
 * The following functionalities are handled:
 * 
 * REGISTER_PID:
 * A write to this command allocates a new CPID (if any are free)
 * and registers the pid passed as argument. The CPID can be retrieved by the
 * guest by a read at the same offset.
 * 
 * UNREGISTER_PID:
 * Complement to REGISTER_PID. The guest writes the CPID to this offset 
 * to deregister a guest process.
 * 
 * MAP_USER:
 * The guest writes the address to the notifier to this offset. The hypervisor
 * copies the notifier from the vm. The notifier contains information about
 * the address range that should be mapped on the fpga.
 * 
 * UNMAP_USER:
 * Counterpart to MAP_USER. Works in a similar matter. The guest writes 
 * the address of a notifier to this offset. The hypervisor reads the struct from the 
 * vm and unmaps the range. The range has to be mapped previsously with a call to
 * MAP_USER.
 * 
 * PUT_ALL_USER_PAGES:
 * The guest writes 0 or non zero to this offset to indicate if the pages
 * should not be dirtied/should be dirtied before releasing them. 
 * The call then puts all pages that were mapped by the mediated device.
 * The guest usally calls this if the device is closed in the vm.
 * 
 * TEST_INTERRUPT:
 * TODO: delete
 * 
 * @param vfpga mediated vfpga
 * @param buf write buffer
 * @param count bytes to write
 * @param pos offset into BAR2 region
 * @return ssize_t bytes written
 */
static ssize_t handle_bar2_write(struct m_fpga_dev *vfpga, const char __user *buf,
                                 size_t count, loff_t pos)
{
    loff_t offset;
    int ret_val;
    uint64_t pid, epid;
    uint64_t cpid;
    struct bus_drvdata *pd;
    uint64_t tmp[MAX_USER_WORDS + 2];
    struct hypervisor_map_notifier map_notifier, *full_map_notifier;
    uint64_t map_full_size;

    ret_val = 0;
    offset = pos & HYPERVISOR_OFFSET_MASK;
    pd = vfpga->fpga->pd;

    switch (offset)
    {
    case REGISTER_PID_OFFSET:
    {
        ret_val = copy_from_user(tmp, buf, count);
        if (ret_val)
        {
            pr_err("%s.%u: Failed to copy data from user\n", __func__, __LINE__);
            return -EFAULT;
        }

        pid = tmp[0];
        dbg_info("Registering pid %llu\n", pid);

        spin_lock(&pd->stat_lock);
        spin_lock(&vfpga->current_cpid_lock);

        // Calculate an effective pid to avoid clashes with other vms
        // lower 16 bits are the pid inside the vm and the upper 16
        // bits are to identify the vm
        epid = pid | (vfpga->id << 16);

        // register epid
        cpid = register_pid(vfpga->fpga, epid);
        if (cpid == -1)
        {
            pr_err("registration failed in hypervisor pid: %lld id: %d", pid, vfpga->id);
            spin_unlock(&pd->stat_lock);
            return -EIO;
        }

        // bookeeping which virtual devices belongs to which region
        vfpga->fpga->vdevs[cpid] = vfpga;

        vfpga->current_cpid = cpid;

        spin_unlock(&pd->stat_lock);
        spin_unlock(&vfpga->current_cpid_lock);

        dbg_info("Successfully registered pid %llu\n", pid);

        return count;
    }
    case UNREGISTER_PID_OFFSET:
    {
        // read cpid
        ret_val = copy_from_user(&tmp, buf, count);
        if (ret_val)
        {
            pr_err("%s.%u: Failed to copy data from user\n", __func__, __LINE__);
            return -EFAULT;
        }

        cpid = tmp[0];
        dbg_info("Unregistering cpid %llu\n", cpid);

        // Unregister cpid
        spin_lock(&pd->stat_lock);

        ret_val = unregister_pid(vfpga->fpga, cpid);
        if (ret_val)
        {
            pr_err("unregestration failed in hypervisor pid: %lld id: %d\n", pid, vfpga->id);
            spin_unlock(&pd->stat_lock);
            return -EIO;
        }

        // Remove reverse mapping, cpid is not in use anymore
        vfpga->fpga->vdevs[cpid] = NULL;
        dbg_info("unregestration succesfull in hypervisor pid: %lld id: %d\n", pid, vfpga->id);
        spin_unlock(&pd->stat_lock);
        return count;
    }
    case MAP_USER_OFFSET:
    {
        // read gpa of the arguments
        ret_val = copy_from_user(&tmp, buf, count);
        if (ret_val)
        {
            pr_info("%s.%d: Failed to copy gpa", __func__, __LINE__);
            return -EFAULT;
        }

        // read notifier header from guest
        ret_val = hypervisor_access_kvm(vfpga, tmp[0], sizeof(struct hypervisor_map_notifier), &map_notifier, 0);
        if (ret_val)
        {
            pr_info("%s.%d: Failed to read from guest", __func__, __LINE__);
            return -EIO;
        }

        // read complete notifier from guest
        map_full_size = sizeof(struct hypervisor_map_notifier) + map_notifier.npages * sizeof(uint64_t);
        full_map_notifier = kzalloc(map_full_size, GFP_KERNEL);

        ret_val = hypervisor_access_kvm(vfpga, tmp[0], map_full_size, full_map_notifier, 0);
        if (ret_val)
        {
            pr_info("%s.%d: Failed to read from guest", __func__, __LINE__);
            kfree(full_map_notifier);
            return -EIO;
        }

        dbg_info("Mapping user pages from hypervisor: gva: %llx, len: %llu, cpid: %llu", full_map_notifier->gva,
                 full_map_notifier->len, full_map_notifier->cpid);
        
        // Pin pages and install user mappings onto fpga.
        ret_val = hypervisor_tlb_get_user_pages(vfpga, full_map_notifier);
        if (ret_val)
        {
            pr_info("%s.%d: Failed to get all user pages", __func__, __LINE__);
        }
        else
        {
            ret_val = count;
            dbg_info("Successfully mapped user buffer\n");
        }

        kfree(full_map_notifier);
        return ret_val;
    }
    case UNMAP_USER_OFFSET:
    {
        // Copy gpa
        ret_val = copy_from_user(&tmp, buf, count);
        if (ret_val)
        {
            pr_info("%s.%d: Failed to copy gpa", __func__, __LINE__);
            return -EFAULT;
        }

        // read gva + cpid from kvm
        ret_val = hypervisor_access_kvm(vfpga, tmp[0], sizeof(struct hypervisor_map_notifier), &map_notifier,
                                        0);
        if (ret_val)
        {
            pr_info("%s.%d: Failed to read from kvm", __func__, __LINE__);
            return -EFAULT;
        }

        ret_val = hypervisor_tlb_put_user_pages(vfpga, &map_notifier);
        if (ret_val)
        {
            pr_info("%s.%d: Failed to put all user pages", __func__, __LINE__);
        }
        else
        {
            ret_val = count;
            dbg_info("Successfully unmapped user buffer\n");
        }

        return ret_val;
    }
    case PUT_ALL_USER_PAGES:
    {
        // read dirtied flag
        ret_val = copy_from_user(&tmp, buf, count);
        if (ret_val)
        {
            pr_info("could not copy dirtied flag\n");
            return -EFAULT;
        }

        // put all user pages 
        ret_val = hypervisor_tlb_put_user_pages_all(vfpga, tmp[0]);
        if (ret_val)
        {
            pr_info("could not put all user pages\n");
            return -EIO;
        }

        return count;
    }
    case TEST_INTERRUPT_OFFSET:
    {
        dbg_info("Fired interrupt with ret_val %llu!\n", fire_interrupt(&vfpga->msix_vector[0]));
        return count;
    }
    default:
    {
        // Not used, should not cause any state change
        return count;
    }
    }

    return count;
}

/**
 * @brief Similar to vfpga_read. Demultiplexes the writes
 * to the emulated pci device. 
 *
 * @param mdev mediated virtual device
 * @param buf write buffer
 * @param count bytes to write
 * @param ppos address
 * @return ssize_t bytes written
 */
static ssize_t hypervisor_vfpga_write(struct mdev_device *mdev, const char __user *buf,
                                      size_t count, loff_t *ppos)
{
    loff_t pos, offset, index;
    int ret_val;
    struct m_fpga_dev *vfpga;

    pos = *ppos;
    offset = pos & HYPERVISOR_OFFSET_MASK;
    index = COYOTE_GET_INDEX(pos);
    ret_val = 0;

    vfpga = mdev_get_drvdata(mdev);
    BUG_ON(!vfpga);

    switch (index)
    {
    case VFIO_PCI_CONFIG_REGION_INDEX:
    {
        if (offset + count > COYOTE_HYPERVISOR_CONFIG_SIZE)
        {
            pr_err("%s.%u: Out of bound write\n", __func__, __LINE__);
            return -EFAULT;
        }

        ret_val = handle_pci_cfg_write(vfpga, (char __user *)buf, count, pos);
        if (ret_val)
        {
            dbg_info("could not write pci cfg\n");
            return -EIO;
        }

        return count;
    }
    case VFIO_PCI_BAR0_REGION_INDEX:
    {
        // Check bounds
        if (offset + count > COYOTE_HYPERVISOR_BAR0_SIZE)
        {
            pr_err("%s.%u: Out of bound read\n", __func__, __LINE__);
            return -EFAULT;
        }

        return handle_bar0_access(vfpga, (char __user *)buf, count, pos, 1);
    }
    case VFIO_PCI_BAR2_REGION_INDEX:
    {
        // Check bounds
        if (offset + count > COYOTE_HYPERVISOR_BAR2_SIZE)
        {
            pr_err("%s.%u: Out of bound read\n", __func__, __LINE__);
            return -EFAULT;
        }

        return handle_bar2_write(vfpga, buf, count, pos);
    }
    case VFIO_PCI_BAR4_REGION_INDEX:
    {
        // Check bounds
        if (offset + count > COYOTE_HYPERVISOR_BAR4_SIZE)
        {
            pr_err("%s.%u: Out of bound read\n", __func__, __LINE__);
            return -EFAULT;
        }

        return handle_bar4_access(vfpga, (char *)buf, count, pos, 1);
    }
    default:
    {
        // Not a valid region to read
        pr_debug("%s.%d: Write to invalid region %lld\n", __func__, __LINE__, index);
        return 0;
    }
    }
}

/**
 * @brief IOCTL calls to the device. The vm cannot perform any ioctl calls
 * but the VFIO framework has a set of IOCTL functions that it will use to gather
 * information over the pci device that is emulated by this driver.
 * 
 * These are:
 * - VFIO_DEVICE_GET_INFO
 * Passes a pointer to a struct. This is filled by this function with the 
 * amount of regions and interrupts. Furthermore it communicates the 
 * capabilties of the device.
 * 
 * - VFIO_DEVICE_GET_REGION_INFO
 * Passes a pointer to a struct. The user set the index of the region 
 * it wants more information about and this function will set the remaining fields
 * with relevant information such as offset and size.
 * 
 * - VFIO_DEVICE_GET_IRQ_INFO
 * Similar to GET_REGION_INFO, but for interrupts. The user passes 
 * a struct and specifies about which kind of interrupt the information should
 * be provided and the this function will set the other fields.
 * 
 * - VFIO_DEVICE_SET_IRQS
 * Managment for the interrupts. The user calls with a combination of flags that
 * set interrupts. For more information consult the VFIO documentation.
 * 
 * - VFIO_DEVICE_RESET
 * TODO: Implement
 *
 * @param mdev mediated vfpga
 * @param cmd
 * @param arg
 * @return long
 */
static long hypervisor_vfpga_ioctl(struct mdev_device *mdev, unsigned int cmd, unsigned long arg)
{
    struct m_fpga_dev *vfpga;
    struct vfio_device_info dev_info;
    struct vfio_region_info region_info;
    struct vfio_irq_info irq_info;
    struct vfio_irq_set *irq_set;
    int ret_val;
    unsigned int bytes;
    void __user *argp;
    uint64_t index;

    BUG_ON(!mdev);
    vfpga = mdev_get_drvdata(mdev);
    if (!vfpga)
    {
        pr_err("Failed to get drv data\n");
        return -EIO;
    }

    ret_val = 0;
    argp = (void __user *)arg;

    switch (cmd)
    {
    case VFIO_DEVICE_GET_INFO:
    {
        // Copy the argsz paramter from user space
        ret_val = copy_from_user(&bytes, argp, sizeof(bytes));
        if (ret_val)
        {
            pr_err("%s.%u: Failed to copy from user space", __func__, __LINE__);
            return -EFAULT;
        }

        // Copy the dev_info struct
        ret_val = copy_from_user(&dev_info, argp, bytes);
        if (ret_val)
        {
            pr_err("%s.%u: Failed to copy from user space", __func__, __LINE__);
            return -EFAULT;
        }

        // Resetable PCI device
        dev_info.flags = VFIO_DEVICE_FLAGS_PCI | VFIO_DEVICE_FLAGS_RESET;

        // Propagate default values from the framework
        dev_info.num_regions = VFIO_PCI_NUM_REGIONS;
        dev_info.num_irqs = VFIO_PCI_NUM_IRQS;

        // Copy the updated info struct back to the user
        ret_val = copy_to_user(argp, &dev_info, bytes);
        if (ret_val)
        {
            pr_err("%s.%u: Failed to copy from user space", __func__, __LINE__);
            return -EFAULT;
        }

        return 0;
    }
    case VFIO_DEVICE_GET_REGION_INFO:
    {
        // Copy the argsz paramter from user space
        ret_val = copy_from_user(&bytes, argp, sizeof(bytes));
        if (ret_val)
        {
            pr_err("%s.%u: Failed to copy from user space", __func__, __LINE__);
            return -EFAULT;
        }

        // Copy the dev_info struct
        ret_val = copy_from_user(&region_info, argp, bytes);
        if (ret_val)
        {
            pr_err("%s.%u: Failed to copy from user space", __func__, __LINE__);
            return -EFAULT;
        }

        // For the config region and the
        // 3 64 bit registers return the size. Everything else does not
        // exist and is therefore 0.
        index = region_info.index;
        switch (index)
        {
        case VFIO_PCI_CONFIG_REGION_INDEX:
        {
            region_info.size = COYOTE_HYPERVISOR_CONFIG_SIZE;
            break;
        }
        case VFIO_PCI_BAR0_REGION_INDEX:
        {
            region_info.size = COYOTE_HYPERVISOR_BAR0_SIZE;
            // direct pass through, for high performance, do not trap this instructions
            region_info.flags |= VFIO_REGION_INFO_FLAG_MMAP;
            break;
        }
        case VFIO_PCI_BAR2_REGION_INDEX:
        {
            region_info.size = COYOTE_HYPERVISOR_BAR2_SIZE;
            break;
        }
        case VFIO_PCI_BAR4_REGION_INDEX:
        {
            region_info.size = COYOTE_HYPERVISOR_BAR4_SIZE;
            // direct pass through, for high performance, do not trap this instructions
            region_info.flags |= VFIO_REGION_INFO_FLAG_MMAP;
            break;
        }
        default:
        {
            region_info.size = 0;
        }
        }

        // Upper 32 bits are used to indicate the index
        region_info.offset = COYOTE_INDEX_TO_ADDR(index);

        // Allow read and write
        region_info.flags |= VFIO_REGION_INFO_FLAG_READ | VFIO_REGION_INFO_FLAG_WRITE;

        // Copy the updated info struct back to the user
        ret_val = copy_to_user(argp, &region_info, bytes);
        if (ret_val)
        {
            pr_err("%s.%u: Failed to copy from user space", __func__, __LINE__);
            return -EFAULT;
        }

        return 0;
    }
    case VFIO_DEVICE_GET_IRQ_INFO:
    {
        // Copy the argsz paramter from user space
        ret_val = copy_from_user(&bytes, argp, sizeof(bytes));
        if (ret_val)
        {
            pr_err("%s.%u: Failed to copy from user space", __func__, __LINE__);
            return -EFAULT;
        }

        // Copy the dev_info struct
        ret_val = copy_from_user(&irq_info, argp, bytes);
        if (ret_val)
        {
            pr_err("%s.%u: Failed to copy from user space", __func__, __LINE__);
            return -EFAULT;
        }

        // This device supports MSIX interrupts
        if (irq_info.index == VFIO_PCI_MSIX_IRQ_INDEX)
        {
            irq_info.flags = VFIO_IRQ_INFO_NORESIZE | VFIO_IRQ_INFO_EVENTFD;

            // Defined by a define in the header
            irq_info.count = NUM_INTERRUPTS;
        }
        // All other types are not supported
        else
        {
            irq_info.flags = 0;
            irq_info.flags = 0;
        }

        // Copy the updated info struct back to the user
        ret_val = copy_to_user(argp, &irq_info, bytes);
        if (ret_val)
        {
            pr_err("%s.%u: Failed to copy from user space", __func__, __LINE__);
            return -EFAULT;
        }

        return 0;
    }
    case VFIO_DEVICE_SET_IRQS:
    {
        // copy argz field
        ret_val = copy_from_user(&bytes, argp, sizeof(bytes));
        if (ret_val)
        {
            dbg_info("Failed to copy from user space\n");
            return -EFAULT;
        }

        // Allocate memory for addtional data
        irq_set = kzalloc(bytes, GFP_KERNEL);
        BUG_ON(!irq_set);

        // copy struct from user
        ret_val = copy_from_user(irq_set, argp, bytes);
        if (ret_val)
        {
            dbg_info("Failed to copy from user space\n");
            kfree(irq_set);
            return -EFAULT;
        }

        // Only MSIX interrupts are supported and needed by the
        // guest driver.
        switch (irq_set->index)
        {
        case VFIO_PCI_MSIX_IRQ_INDEX:
            ret_val = handle_set_irq_msix(vfpga, irq_set);
            break;
        default:
            // dbg_info("Tried to set IRQ! Flags: %x, Index: %u, Start: %u, Count: %u\n",
            //          irq_set->flags, irq_set->index, irq_set->start, irq_set->count);
            break;
        }

        kfree(irq_set);
        return ret_val;
    }
    case VFIO_DEVICE_RESET:
    {
        return 0;
    }
    default:
    {
        return -EINVAL;
    }
    }
}

/**
 * @brief Allows mmap of BAR 0 and 4, and therefore enables 
 * direct pass through of the control registers. The vma struct contains an offset
 * into the pci region and from this we can determine which BAR is mapped.
 * BAR 0 and BAR 4 are seperated from each other. This allows to adjust sizes of 
 * these control registers later on without to much effort to change the hypervisor. 
 * 
 * @param mdev 
 * @param vma 
 * @return int 
 */
int hypervisor_vfpga_mmap(struct mdev_device *mdev, struct vm_area_struct *vma)
{
    int region;
    unsigned long vaddr;
    unsigned long offset;

    struct m_fpga_dev *md;
    struct fpga_dev *d;
    struct bus_drvdata *pd;

    int ret_val;

    md = mdev_get_drvdata(mdev);
    BUG_ON(!md);
    d = md->fpga;
    BUG_ON(!d);
    pd = d->pd;
    BUG_ON(!pd);

    // offset into the pci region
    vaddr = vma->vm_pgoff << PAGE_SHIFT;
    // get the region that should be mapped
    region = COYOTE_GET_INDEX(vaddr);
    // offset into this region
    offset = vaddr & HYPERVISOR_OFFSET_MASK;
    ret_val = 0;

    dbg_info("MMAP with vaddr %lu, VFIO region index %d, offset %lu\n", vaddr, region, offset);

    // Do not cache
    vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);

    // Allow passthrough to hardware
    if (region == VFIO_PCI_BAR0_REGION_INDEX)
    {
        // BAR0 is for the address ctrl registers
        ret_val = remap_pfn_range(vma, vma->vm_start, d->fpga_phys_addr_ctrl >> PAGE_SHIFT,
                                  FPGA_CTRL_SIZE, vma->vm_page_prot);
        if (ret_val)
        {
            dbg_info("Failed to mmap BAR0.\n");
        }
        else
        {
            dbg_info("Mapped addr %llx with size %u\n", d->fpga_phys_addr_ctrl,
                     FPGA_CTRL_SIZE);
        }
    }
    else if (region == VFIO_PCI_BAR4_REGION_INDEX)
    {
        // BAR4 is for the avx address ctrl registers
        ret_val = remap_pfn_range(vma, vma->vm_start, d->fpga_phys_addr_ctrl_avx >> PAGE_SHIFT,
                                  FPGA_CTRL_CNFG_AVX_SIZE, vma->vm_page_prot);
        if (ret_val)
        {
            dbg_info("Failed to mmap BAR4.\n");
        }
        else
        {
            dbg_info("Mapped addr %llx with size %u\n", d->fpga_phys_addr_ctrl_avx,
                     FPGA_CTRL_CNFG_AVX_SIZE);
        }
    }
    else
    {
        // Not allowed region
        ret_val = -EINVAL;
    }

    return ret_val;
}

//
//
// START: This section contains static functions and arrays that display information 0x2000for the mediated devices in sysfs
//
//

static ssize_t
info_show(struct device *dev, struct device_attribute *attr, char *buf)
{

    return sprintf(buf, "fpga region\n");
}
static DEVICE_ATTR_RO(info);

static struct attribute *dummy_attrs[] = {
    &dev_attr_info.attr,
    NULL,
};

static const struct attribute_group fpga_dev_group = {
    .name = "vfpga",
    .attrs = dummy_attrs,
};

const struct attribute_group *fpga_dev_groups[] = {
    &fpga_dev_group,
    NULL,
};

static ssize_t
vfpga_info_show(struct device *dev,
                struct device_attribute *attr, char *buf)
{
    struct mdev_device *mdev = mdev_from_dev(dev);
    struct m_fpga_dev *vfpga = mdev_get_drvdata(mdev);

    return sprintf(buf, "virtual vfpga device with id %d\n", vfpga->id);
}
DEVICE_ATTR_RO(vfpga_info);

static struct attribute *vpga_attrs[] = {
    &dev_attr_vfpga_info.attr,
    NULL,
};

static const struct attribute_group vfpga_dev_group = {
    .name = "vpga info",
    .attrs = vpga_attrs,
};

const struct attribute_group *vfpga_dev_groups[] = {
    &vfpga_dev_group,
    NULL,
};

static ssize_t
name_show(struct device *dev, struct device_attribute *attrs, char *buf)
{
    return sprintf(buf, "%s-type\n", dev->kobj.name);
}
DEVICE_ATTR_RO(name);

static ssize_t
device_api_show(struct device *dev, struct device_attribute *attrs, char *buf)
{
    return sprintf(buf, VFIO_DEVICE_API_PCI_STRING);
}
DEVICE_ATTR_RO(device_api);

static struct attribute *vfpga_type_attrs[] = {
    &dev_attr_name.attr,
    &dev_attr_device_api.attr,
    NULL,
};

//
// END
//

/**
 * @brief This function populates a mdev_parent_ops
 * struct that is used to create a mediated type
 * that is shown in the sysfs and provides all the callbacks
 * used to manage all the devices
 *
 * @param vfpga virtual fpga region
 * @return struct mdev_parent_ops*
 */
struct mdev_parent_ops *hypervisor_get_ops(struct fpga_dev *vfpga)
{
    struct mdev_parent_ops *ops;
    struct attribute_group *type_group, **type_groups;
    char *name;

    BUG_ON(!vfpga);

    // alloc type group
    type_group = kzalloc(sizeof(struct attribute_group), GFP_KERNEL);

    if (!type_group)
    {
        dbg_info("Failed to allocate type group\n");
        goto err;
    }

    // alloc name
    name = kzalloc(64, GFP_KERNEL);
    if (!name)
    {
        dbg_info("could not allocate name\n");
        goto err_name;
    }

    // Create first and only type group
    sprintf(name, "fpga_mdev.%d", vfpga->id);
    type_group->name = name;
    type_group->attrs = vfpga_type_attrs;

    // Create type groups array
    type_groups = kzalloc(sizeof(struct attribute_group *) * 2, GFP_KERNEL);
    if (!type_groups)
    {
        dbg_info("Could not allocate type group array\n");
        goto err_type_groups;
    }
    type_groups[0] = type_group;
    type_groups[1] = NULL;

    ops = kzalloc(sizeof(struct mdev_parent_ops), GFP_KERNEL);
    if (!ops)
    {
        dbg_info("could not allocate mdev parent ops\n");
        goto err_ops;
    }

    // Set attributes
    ops->owner = THIS_MODULE;
    ops->dev_attr_groups = fpga_dev_groups;
    ops->mdev_attr_groups = vfpga_dev_groups;
    ops->supported_type_groups = type_groups;

    // Set handler functions
    ops->open_device = hypervisor_vfpga_open;
    ops->close_device = hypervisor_vfpga_close;
    ops->create = hypervisor_vfpga_create;
    ops->remove = hypervisor_vfpga_remove;
    ops->write = hypervisor_vfpga_write;
    ops->read = hypervisor_vfpga_read;
    ops->ioctl = hypervisor_vfpga_ioctl;
    ops->mmap = hypervisor_vfpga_mmap;

    dbg_info("created vfio-mdev operations\n");

    return ops;

err_ops:
    kfree(type_groups);
err_type_groups:
    kfree(name);
err_name:
    kfree(type_group);
err:
    return NULL;
}