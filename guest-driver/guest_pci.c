#include "guest_pci.h"

dev_t devt;
struct vfpga vfpga;

/**
 * @brief Sets-up the msix interrupts such that the hypervisor can interrupt
 * in a case of a page fault on the system.
 *
 * @param pdev
 * @return int
 */
static int register_msix(struct pci_dev *pdev)
{
    int nvecs;
    int i;
    int ret_val;

    nvecs = NUM_USER_INTERRUPTS;
    ret_val = 0;

    for (i = 0; i < nvecs; i++)
    {
        vfpga.irq_entry[i].entry = i;
    }

    /* Enable as many interrupts as possible */
    ret_val = pci_enable_msix_range(pdev, vfpga.irq_entry, 0, nvecs);
    if (ret_val < 0)
    {
        dbg_info("Failed to allocate all msix vectors");
        return ret_val;
    }

    /* For now, the guest only needs one interrupt, for the page fault
     this will be extended eventaully to support user interrupts*/

    ret_val = request_irq(vfpga.irq_entry[0].vector,
                          guest_fpga_tlb_miss_isr, 0, DRV_NAME, &vfpga);

    if (ret_val)
    {
        dbg_info("could not register irq!\n");
        return ret_val;
    }

    return 0;
}

/**
 * @brief Load configuration for the fpga from the hypervisor
 * This is done by reading from the READ_CNFG offset.
 *
 * @param d vfpga struct
 */
static void load_fpga_config(struct vfpga *d)
{
    uint64_t config;
    // load from bar2 offset

    config = readq((volatile __iomem void *)d->pci_resources.bar2 + READ_CNFG_OFFSET);

    // set avx enabled
    d->en_avx = config & 0x01;
}

/**
 * @brief Called upon the bus picks up the emulated
 * pci device. Creates chardevs, claims resources
 * and maps the BARs.
 *
 * @param pdev
 * @param id
 * @return int
 */
int guest_probe(struct pci_dev *pdev, const struct pci_device_id *id)
{
    int ret_val;

    ret_val = 0;
    vfpga.pdev = pdev;
    dbg_info("probed driver\n");

    // Alloc char region
    ret_val = alloc_chrdev_region(&devt, 0, 1, "coyote-guest");
    if (ret_val)
    {
        dbg_info("failed to allocate chrdev region\n");
        goto err;
    }

    /* Init the chardev */
    cdev_init(&vfpga.cdev, &fops);
    ret_val = cdev_add(&vfpga.cdev, devt, 1);
    if (ret_val)
    {
        dbg_info("Failed to add chrdev\n");
        goto err_cdev_add;
    }

    /* Enable the pci device */
    ret_val = pci_enable_device(pdev);
    if (ret_val)
    {
        dbg_info("Failed to enable pci dev\n");
        goto err_pci_enable;
    }

    /* Allocate all regions of the pci device */
    ret_val = pci_request_regions(pdev, "coyote-guest-drv");
    if (ret_val)
    {
        dbg_info("failed to request regions");
        goto err_pci_request_regions;
    }

    // This device is allowed to master the bus
    pci_set_master(pdev);

    dbg_info("Successfully requested resources\n");

    /* Requesting all bars and store information about the bars*/
    vfpga.pci_resources.bar0 = pci_iomap(pdev, 0, pci_resource_len(pdev, 0));
    vfpga.pci_resources.bar2 = pci_iomap(pdev, 2, pci_resource_len(pdev, 2));
    vfpga.pci_resources.bar4 = pci_iomap(pdev, 4, pci_resource_len(pdev, 4));

    vfpga.pci_resources.bar0_start = pci_resource_start(pdev, 0);
    vfpga.pci_resources.bar0_end = pci_resource_end(pdev, 0);

    vfpga.pci_resources.bar2_start = pci_resource_start(pdev, 2);
    vfpga.pci_resources.bar2_end = pci_resource_end(pdev, 2);

    vfpga.pci_resources.bar4_start = pci_resource_start(pdev, 4);
    vfpga.pci_resources.bar4_end = pci_resource_end(pdev, 4);

    dbg_info("Loaded BAR 0, 2 and 4 into the driver with sizes\nBAR0: %llx\nBAR2: %llx\nBAR4: %llx\n",
             pci_resource_len(pdev, 0),
             pci_resource_len(pdev, 2),
             pci_resource_len(pdev, 4));

    /* CTRL is BAR0 and AVX-CTRL is BAR4 */
    vfpga.fpga_phys_addr_ctrl = vfpga.pci_resources.bar0_start;
    vfpga.fpga_phys_addr_ctrl_avx = vfpga.pci_resources.bar4_start;

    /* Map the CTRL registers to allow the access from the kernel */
    vfpga.fpga_cnfg = ioremap(vfpga.fpga_phys_addr_ctrl + FPGA_CTRL_CNFG_OFFS, FPGA_CTRL_CNFG_SIZE);
    vfpga.fpga_cnfg_avx = ioremap(vfpga.fpga_phys_addr_ctrl_avx, FPGA_CTRL_CNFG_AVX_SIZE);

    /* Enable MSIX interrupts */
    ret_val = register_msix(pdev);
    if (ret_val)
    {
        dbg_info("Failed to register interrupts\n");
        goto err_interrupt;
    }

    /* Load config from hypervisor */
    load_fpga_config(&vfpga);

    // Init pid array
    vfpga.pid_array = vcalloc(N_CPID_MAX, sizeof(pid_t));

    // Init locks
    spin_lock_init(&vfpga.cpid_lock);
    spin_lock_init(&vfpga.lock);

    /* Create kernel device */
    vfpga.dev = device_create(guest_class, NULL, devt, NULL, "fpga0");
    if (IS_ERR_OR_NULL(vfpga.dev))
    {
        dbg_info("Failed to create device\n");
        ret_val = -1;
        goto err_device_create;
    }

    dbg_info("created coyote device\n");

    return 0;

err_device_create:
    pci_free_irq_vectors(pdev);
    pci_disable_msix(pdev);
err_interrupt:
    pci_iounmap(pdev, (void __iomem *)vfpga.pci_resources.bar0);
    pci_iounmap(pdev, (void __iomem *)vfpga.pci_resources.bar2);
    pci_iounmap(pdev, (void __iomem *)vfpga.pci_resources.bar4);
    vfpga.pci_resources.bar0 = NULL;
    vfpga.pci_resources.bar2 = NULL;
    vfpga.pci_resources.bar4 = NULL;
    pci_release_regions(pdev);
err_pci_request_regions:
    pci_disable_device(pdev);
err_pci_enable:
    cdev_del(&vfpga.cdev);
err_cdev_add:
    unregister_chrdev_region(devt, 1);
err:
    return ret_val;
}

/**
 * @brief Called on deletion of the device.
 * Frees resources and unmaps the bar regions.
 *
 * @param pdev
 */
void guest_remove(struct pci_dev *pdev)
{
    // Destory device
    device_destroy(guest_class, devt);

    // Unmap pci regions
    pci_iounmap(pdev, (void __iomem *)vfpga.pci_resources.bar0);
    pci_iounmap(pdev, (void __iomem *)vfpga.pci_resources.bar2);
    pci_iounmap(pdev, (void __iomem *)vfpga.pci_resources.bar4);
    
    /* Release regions */
    pci_release_regions(pdev);

    // Disable device
    free_irq(vfpga.irq_entry[0].vector, &vfpga);
    pci_disable_msix(pdev);
    pci_disable_device(pdev);
    cdev_del(&vfpga.cdev);
    unregister_chrdev_region(devt, 1);
}