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

#include "pci_dev.h"

inline uint32_t build_u32(uint32_t hi, uint32_t lo) {
    return ((hi & 0xFFFFUL) << 16) | (lo & 0xFFFFUL);
}

inline uint64_t build_u64(uint64_t hi, uint64_t lo) {
    return ((hi & 0xFFFFFFFULL) << 32) | (lo & 0xFFFFFFFFULL);
}

/*
██████╗  ██████╗██╗███████╗
██╔══██╗██╔════╝██║██╔════╝
██████╔╝██║     ██║█████╗  
██╔═══╝ ██║     ██║██╔══╝  
██║     ╚██████╗██║███████╗
╚═╝      ╚═════╝╚═╝╚══════╝
*/     

/**
 * Device 
*/
static uint32_t curr_dev = 0;
static LIST_HEAD(device_mappings);

/**
 * @brief Assign IDs
 * 
 */
int assign_dev_id(struct bus_drvdata *d) {
    int ret_val = 0;
    struct device_mapping *entry;

    if(strcmp(config_fname, "") == 0) {
        pr_info("fpga device %d, pci bus %02x, slot %02x\n", curr_dev, d->pci_dev->bus->number, PCI_SLOT(d->pci_dev->devfn));
        d->dev_id = curr_dev++;
        sprintf(d->vf_dev_name, "%s_%d", DEV_FPGA_NAME, d->dev_id);
        sprintf(d->pr_dev_name, "%s_pr", d->vf_dev_name);
    } else {
        ret_val = -ENODEV;
        list_for_each_entry(entry, &device_mappings, list) {
            if (d->pci_dev->bus->number == entry->bus && PCI_SLOT(d->pci_dev->devfn) == entry->slot) {
                d->dev_id = entry->device_id;
                pr_info("fpga device assigned %d, pci bus %02x, slot %02x\n", d->dev_id, d->pci_dev->bus->number, PCI_SLOT(d->pci_dev->devfn));
                sprintf(d->vf_dev_name, "%s_%d", DEV_FPGA_NAME, d->dev_id);
                sprintf(d->pr_dev_name, "%s_pr", d->vf_dev_name);
                ret_val = 0;
            }
        }
    }

    ret_val = 0;
    return ret_val;
}

/**
 * @brief Read external device config
 * 
 */
int read_dev_config(const char *fname) {
    /*struct file *file;
    char line[MAX_CONFIG_LINE_LENGTH];
    mm_segment_t old_fs;
    int device_id, bus, slot;
    int ret_val;

    char *line;
    ssize_t bytes_read = 0;
    ssize_t total_bytes_read = 0;

    // open file
    file = filp_open(fname, O_RDONLY, 0);
    if (IS_ERR(file)) {
        pr_err("provided dev config file could not be opened");
        return PTR_ERR(file);
    }

    // allocate memory for the line buffer
    line = kmalloc(MAX_LINE_LENGTH, GFP_KERNEL);
    if (!line) {
        pr_err("failed to allocate memory for line buffer\n");
        filp_close(file, NULL);
        return -ENOMEM;
    }

    // read from the file
    bytes_read = kernel_read(file, buf, count, &file->f_pos);

    old_fs = get_fs();
    set_fs(KERNEL_DS);

    while ((ret_val = vfs_read(file, line, sizeof(line), &file->f_pos)) > 0) {
        if (sscanf(line, "%d = %x %x", &device_id, &bus, &slot) == 3) {
            struct device_mapping *mapping = kmalloc(sizeof(struct device_mapping), GFP_KERNEL);
            if (!mapping) {
                ret_val = -ENOMEM;
                break;
            }
            mapping->device_id = device_id;
            mapping->bus = bus;
            mapping->slot = slot;
            INIT_LIST_HEAD(&mapping->list);
            list_add_tail(&mapping->list, &device_mappings);


            pr_info("device config, dev id %d, pci bus %02x, slot %02x\n", device_id, mapping->bus, mapping->slot);
        }

    }

    set_fs(old_fs);
    filp_close(file, NULL);
    return ret_val;
    */
   return 0;
}

/**
 * @brief User interrupt enable
 * 
 */
void user_interrupts_enable(struct bus_drvdata *d, uint32_t mask)
{
    struct interrupt_regs *reg = (struct interrupt_regs *)(d->bar[BAR_XDMA_CONFIG] + XDMA_OFS_INT_CTRL);

    iowrite32(mask & FPGA_USER_IRQ_MASK, &reg->user_int_enable_w1s);
}

/**
 * @brief User interrupt disable
 * 
 */
void user_interrupts_disable(struct bus_drvdata *d, uint32_t mask)
{
    struct interrupt_regs *reg = (struct interrupt_regs *)(d->bar[BAR_XDMA_CONFIG] + XDMA_OFS_INT_CTRL);

    iowrite32(mask & FPGA_USER_IRQ_MASK, &reg->user_int_enable_w1c);
}

/**
 * @brief User interrupt enable
 * 
 */
void pr_interrupt_enable(struct bus_drvdata *d)
{
    struct interrupt_regs *reg = (struct interrupt_regs *)(d->bar[BAR_XDMA_CONFIG] + XDMA_OFS_INT_CTRL);

    iowrite32(FPGA_PR_IRQ_MASK, &reg->user_int_enable_w1s);
}

/**
 * @brief User interrupt disable
 * 
 */
void pr_interrupt_disable(struct bus_drvdata *d)
{
    struct interrupt_regs *reg = (struct interrupt_regs *)(d->bar[BAR_XDMA_CONFIG] + XDMA_OFS_INT_CTRL);

    iowrite32(FPGA_PR_IRQ_MASK, &reg->user_int_enable_w1c);
}

/**
 * @brief Channel interrupt enable
 * 
 */
void channel_interrupts_enable(struct bus_drvdata *d, uint32_t mask)
{
    struct interrupt_regs *reg = (struct interrupt_regs *)(d->bar[BAR_XDMA_CONFIG] + XDMA_OFS_INT_CTRL);

    iowrite32(mask, &reg->channel_int_enable_w1s);
}

/**
 * @brief Channel interrupt disable
 * 
 */
void channel_interrupts_disable(struct bus_drvdata *d, uint32_t mask)
{
    struct interrupt_regs *reg = (struct interrupt_regs *)(d->bar[BAR_XDMA_CONFIG] + XDMA_OFS_INT_CTRL);

    iowrite32(mask, &reg->channel_int_enable_w1c);
}

/**
 * @brief Read interrupt status
 * 
 */
uint32_t read_interrupts(struct bus_drvdata *d)
{
    struct interrupt_regs *reg = (struct interrupt_regs *)(d->bar[BAR_XDMA_CONFIG] + XDMA_OFS_INT_CTRL);
    uint32_t lo, hi;

    // interrupt check
    hi = ioread32(&reg->user_int_request);
    printk(KERN_INFO "ioread32(0x%p) returned 0x%08x (user_int_request).\n",
           &reg->user_int_request, hi);
    lo = ioread32(&reg->channel_int_request);
    printk(KERN_INFO
           "ioread32(0x%p) returned 0x%08x (channel_int_request)\n",
           &reg->channel_int_request, lo);

    // return interrupts: user in upper 16-bits, channel in lower 16-bits
    return build_u32(hi, lo);
}

uint32_t build_vector_reg(uint32_t a, uint32_t b, uint32_t c, uint32_t d)
{
    uint32_t reg_val = 0;

    reg_val |= (a & 0x1f) << 0;
    reg_val |= (b & 0x1f) << 8;
    reg_val |= (c & 0x1f) << 16;
    reg_val |= (d & 0x1f) << 24;

    return reg_val;
}

/**
 * @brief Write MSI-X vectors
 * 
 */
void write_msix_vectors(struct bus_drvdata *d)
{
    struct interrupt_regs *int_regs;
    uint32_t reg_val = 0;

    BUG_ON(!d);

    int_regs = (struct interrupt_regs *)(d->bar[BAR_XDMA_CONFIG] + XDMA_OFS_INT_CTRL);

    // user MSI-X
    reg_val = build_vector_reg(0, 1, 2, 3);
    iowrite32(reg_val, &int_regs->user_msi_vector[0]);

    reg_val = build_vector_reg(4, 5, 6, 7);
    iowrite32(reg_val, &int_regs->user_msi_vector[1]);

    reg_val = build_vector_reg(8, 9, 10, 11);
    iowrite32(reg_val, &int_regs->user_msi_vector[2]);

    reg_val = build_vector_reg(12, 13, 14, 15);
    iowrite32(reg_val, &int_regs->user_msi_vector[3]);

    // channel MSI-X
    reg_val = build_vector_reg(16, 17, 18, 19);
    //iowrite32(reg_val, &int_regs->channel_msi_vector[0]);

    reg_val = build_vector_reg(20, 21, 22, 23);
    //iowrite32(reg_val, &int_regs->channel_msi_vector[1]);
}

/**
 * @brief Remove user IRQs
 * 
 */
void irq_teardown(struct bus_drvdata *d, bool pr_flow)
{
    int i;

        for (i = 0; i < d->n_fpga_reg; i++) {
            pr_info("releasing user IRQ%d\n", d->irq_entry[i].vector);
            free_irq(d->irq_entry[i].vector, &d->fpga_dev[i]);
        }
        
        if(pr_flow) {
            pr_info("releasing reconfiguration IRQ%d\n", d->irq_entry[FPGA_PR_IRQ_VECTOR].vector);
            free_irq(d->irq_entry[FPGA_PR_IRQ_VECTOR].vector, d->pr_dev);
        }
}

/**
 * @brief Setup user MSI-X
 * 
 */
int msix_irq_setup(struct bus_drvdata *d,  struct pci_dev *pdev, bool pr_flow)
{
    int i;
    int ret_val;
    uint32_t vector;

    BUG_ON(!d);

    // user
    for (i = 0; i < d->n_fpga_reg; i++) {
        vector = pci_irq_vector(pdev, i);
        d->irq_entry[i].vector = vector;
        
        //ret_val = request_irq(d->irq_entry[i].vector, fpga_isr, 0,
        //                      DRV_NAME, &d->fpga_dev[i]);

        ret_val = request_irq(vector, fpga_isr, 0,
                              DRV_NAME, &d->fpga_dev[i]);

        if (ret_val) {
            //pr_info("couldn't use IRQ#%d, ret=%d\n", d->irq_entry[i].vector, ret_val);
            pr_info("couldn't use IRQ#%d, ret=%d\n", vector, ret_val);
            goto err_user;
        }

        //pr_info("using IRQ#%d with vFPGA %d\n", d->irq_entry[i].vector, d->fpga_dev[i].id);
        pr_info("using IRQ#%d with vFPGA %d\n", vector, d->fpga_dev[i].id);
    }

    // pr
    if(pr_flow) {
        vector = pci_irq_vector(pdev, FPGA_PR_IRQ_VECTOR);
        d->irq_entry[FPGA_PR_IRQ_VECTOR].vector = vector;

        //ret_val = request_irq(d->irq_entry[FPGA_PR_IRQ_VECTOR].vector, pr_isr, 0,
        //                      DRV_NAME, d->pr_dev);

        ret_val = request_irq(vector, pr_isr, 0,
                              DRV_NAME, d->pr_dev);

        if (ret_val) {
            //pr_info("couldn't use IRQ#%d, ret=%d\n", d->irq_entry[FPGA_PR_IRQ_VECTOR].vector, ret_val);
            pr_info("couldn't use reconfiguration IRQ#%d, ret=%d\n", vector, ret_val);
            goto err_pr;
        }

        pr_info("using IRQ#%d with reconfiguration device\n", vector);

        write_msix_vectors(d);
    }

    return ret_val;

err_pr:
    for (i = 0; i < d->n_fpga_reg; i++)
        //free_irq(d->irq_entry[i].vector, &d->fpga_dev[i]);
        free_irq(vector, &d->fpga_dev[i]);

    return ret_val;

err_user:
    while (--i >= 0)
        //free_irq(d->irq_entry[i].vector, &d->fpga_dev[i]);
        free_irq(vector, &d->fpga_dev[i]);

    return ret_val;
}

/**
 * @brief Setup user IRQs
 * 
 */
int irq_setup(struct bus_drvdata *d, struct pci_dev *pdev, bool pr_flow)
{
    int ret_val = 0;

    if (d->msix_enabled)
    {
        ret_val = msix_irq_setup(d, pdev, pr_flow);
    }

    return ret_val;
}

/**
 * @brief Check whether support for MSI-X exists
 * 
 */
int msix_capable(struct pci_dev *pdev, int type)
{
    struct pci_bus *bus;

    BUG_ON(!pdev);

    if (pdev->no_msi)
        return 0;

    for (bus = pdev->bus; bus; bus = bus->parent)
        if (bus->bus_flags & PCI_BUS_FLAGS_NO_MSI)
            return 0;

    if (!pci_find_capability(pdev, type))
        return 0;

    return 1;
}

/**
 * @brief Check whether MSI-X is present
 * 
 */
int pci_check_msix(struct bus_drvdata *d, struct pci_dev *pdev)
{
    int ret_val = 0, i;
    int req_nvec = MAX_NUM_ENGINES + MAX_USER_IRQS;

    BUG_ON(!d);
    BUG_ON(!pdev);

    if (msix_capable(pdev, PCI_CAP_ID_MSIX)) {
        pr_info("enabling MSI-X\n");

        for (i = 0; i < req_nvec; i++)
            d->irq_entry[i].entry = i;

        ret_val = pci_alloc_irq_vectors(pdev, req_nvec, req_nvec, PCI_IRQ_MSIX);
        //ret_val = pci_enable_msix_range(pdev, d->irq_entry, 0, req_nvec);

        if (ret_val < 0)
            pr_info("could not enable MSI-X mode, ret %d\n", ret_val);
        else
            pr_info("obtained %d MSI-X irqs\n", ret_val);

        d->msix_enabled = 1;
    }
    else {
        pr_info("MSI-X not present, forcing polling mode\n");
        ret_val = -1;
        d->msix_enabled = 0;
    }

    if (ret_val < 0)
        return ret_val;
    else
        return 0;
}

void pci_enable_capability(struct pci_dev *pdev, int cmd)
{
	pcie_capability_set_word(pdev, PCI_EXP_DEVCTL, cmd);
}

/*
███████╗███╗   ██╗ ██████╗ ██╗███╗   ██╗███████╗███████╗
██╔════╝████╗  ██║██╔════╝ ██║████╗  ██║██╔════╝██╔════╝
█████╗  ██╔██╗ ██║██║  ███╗██║██╔██╗ ██║█████╗  ███████╗
██╔══╝  ██║╚██╗██║██║   ██║██║██║╚██╗██║██╔══╝  ╚════██║
███████╗██║ ╚████║╚██████╔╝██║██║ ╚████║███████╗███████║
╚══════╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝
*/

/**
 * @brief Get the engine channel id
 * 
 */
uint32_t get_engine_channel_id(struct engine_regs *regs)
{
    uint32_t val;

    BUG_ON(!regs);

    val = ioread32(&regs->id);
    return (val & 0x00000f00U) >> 8;
}

/**
 * @brief Get the engine id
 * 
 */
uint32_t get_engine_id(struct engine_regs *regs)
{
    uint32_t val;

    BUG_ON(!regs);

    val = ioread32(&regs->id);
    return (val & 0xffff0000U) >> 16;
}

/**
 * @brief Remove single engine
 * 
 */
void engine_destroy(struct bus_drvdata *d, struct xdma_engine *engine)
{
    BUG_ON(!d);
    BUG_ON(!engine);

    pr_info("shutting off engine %s%d\n", engine->name, engine->channel);
    iowrite32(0x0, &engine->regs->ctrl);
    engine->running = 0;

    //engine_writeback_teardown(d, engine);

    kfree(engine);

    d->engines_num--;
}

/**
 * @brief Remove all present engines
 * 
 */
void remove_engines(struct bus_drvdata *d)
{
    int i;
    struct xdma_engine *engine;

    BUG_ON(!d);

    for (i = 0; i < d->n_fpga_chan; i++) {
        engine = d->engine_h2c[i];
        if (engine) {
            pr_info("remove %s%d\n", engine->name, engine->channel);
            engine_destroy(d, engine);
        }

        engine = d->engine_c2h[i];
        if (engine) {
            pr_info("remove %s%d\n", engine->name, engine->channel);
            engine_destroy(d, engine);
        }
    }
}

/**
 * @brief Check engine alignments
 * 
 */
void engine_alignments(struct xdma_engine *engine)
{
    uint32_t val;
    uint32_t align_bytes;
    uint32_t granularity_bytes;
    uint32_t address_bits;

    val = ioread32(&engine->regs->alignments);
    pr_info("engine %p name %s alignments=0x%08x\n", engine,
            engine->name, (int)val);

    align_bytes = (val & 0x00ff0000U) >> 16;
    granularity_bytes = (val & 0x0000ff00U) >> 8;
    address_bits = (val & 0x000000ffU);

    if (val) {
        engine->addr_align = align_bytes;
        engine->len_granularity = granularity_bytes;
        engine->addr_bits = address_bits;
    }
    else {
        // Default
        engine->addr_align = 1;
        engine->len_granularity = 1;
        engine->addr_bits = 64;
    }
}

//#define XDMA_WBACK
#ifdef XDMA_WBACK
/**
 * @brief XDMA writeback teardown (replaced)
 * 
 */
void engine_writeback_teardown(struct bus_drvdata *d, struct xdma_engine *engine)
{
    BUG_ON(!d);
    BUG_ON(!engine);

    if (engine->poll_mode_addr_virt) {
        dma_free_coherent(&d->pci_dev->dev, sizeof(struct xdma_poll_wb),  engine->poll_mode_addr_virt, engine->poll_mode_phys_addr);
        pr_info("released memory for descriptor writeback\n");
    }
}

/**
 * @brief XDMA writeback setup (replaced)
 * 
 */
int engine_writeback_setup(struct bus_drvdata *d, struct xdma_engine *engine)
{
    uint32_t w;
    struct xdma_poll_wb *writeback;

    BUG_ON(!d);
    BUG_ON(!engine);

    // Set up address for polled mode writeback 
    pr_info("allocating memory for descriptor writeback for %s%d",
            engine->name, engine->channel);
    engine->poll_mode_addr_virt  = dma_alloc_coherent(&d->pci_dev->dev, sizeof(struct xdma_poll_wb), &engine->poll_mode_phys_addr, GFP_KERNEL);
    if (!engine->poll_mode_addr_virt) {
        pr_err("engine %p (%s) couldn't allocate writeback\n", engine,
               engine->name);
        return -1;
    }
    pr_info("allocated memory for descriptor writeback for %s%d",
            engine->name, engine->channel);

    writeback = (struct xdma_poll_wb *)engine->poll_mode_addr_virt;
    writeback->completed_desc_count = 0;

    pr_info("setting writeback location to 0x%llx for engine %p",
            engine->poll_mode_phys_addr, engine);
    w = cpu_to_le32(LOW_32(engine->poll_mode_phys_addr));
    iowrite32(w, &engine->regs->poll_mode_wb_lo);
    w = cpu_to_le32(HIGH_32(engine->poll_mode_phys_addr));
    iowrite32(w, &engine->regs->poll_mode_wb_hi);

    return 0;
}
#endif

/**
 * Create C2H or H2C vFPGA engine
 * 
 * @param offs - engine config register offset
 * @param c2h - engine direction
 * @param channel - engine channel
 * @return created engine structure
 */
struct xdma_engine *engine_create(struct bus_drvdata *d, int offs, int c2h, int channel)
{
    struct xdma_engine *engine;
    uint32_t reg_val = 0;//, ret_val = 0;

    // allocate memory for engine struct
    engine = kzalloc(sizeof(struct xdma_engine), GFP_KERNEL);
    if (!engine)
        return NULL;

    // info
    engine->channel = channel;
    engine->name = c2h ? "c2h" : "h2c";

    // associate devices
    engine->pd = d;

    // direction
    engine->c2h = c2h;

    // registers
    engine->regs = (d->bar[BAR_XDMA_CONFIG] + offs);
    engine->sgdma_regs = (d->bar[BAR_XDMA_CONFIG] + offs + SGDMA_OFFSET_FROM_CHANNEL);

    // Incremental mode
    iowrite32(!XDMA_CTRL_NON_INCR_ADDR, &engine->regs->ctrl_w1c);

    // alignments
    engine_alignments(engine);

    // writeback (replaced)
    /*
    ret_val = engine_writeback_setup(d, engine);
    if (ret_val) {
        pr_info("Descriptor writeback setup failed for %p, channel %d\n", engine, engine->channel);
        return NULL;
    }
    */

    // start engine
    //reg_val |= XDMA_CTRL_POLL_MODE_WB;
    reg_val |= XDMA_CTRL_IE_DESC_STOPPED;
    reg_val |= XDMA_CTRL_IE_DESC_COMPLETED;
    reg_val |= XDMA_CTRL_RUN_STOP;
    engine->running = 0;

    iowrite32(reg_val, &engine->regs->ctrl);
    reg_val = ioread32(&engine->regs->status);
    dbg_info("ioread32(0x%p) = 0x%08x (dummy read flushes writes).\n", &engine->regs->status, reg_val);

    return engine;
}

/**
 * Probes a single C2H or H2C engine
 * 
 * @param c2h - engine direction
 * @param channel - engine channel
 */
int probe_for_engine(struct bus_drvdata *d, int c2h, int channel)
{
    int offs;
    struct engine_regs *regs;
    uint32_t engine_id, engine_id_expected, channel_id;
    struct xdma_engine *tmp_engine;

    offs = (c2h * C2H_CHAN_OFFS) + (channel * CHAN_RANGE);
    regs = d->bar[BAR_XDMA_CONFIG] + offs;

    if (c2h) { // c2h
        pr_info("probing for c2h engine %d at %p\n", channel, regs);
        engine_id_expected = XDMA_ID_C2H;
    }
    else { // h2c
        pr_info("probing for h2c engine %d at %p\n", channel, regs);
        engine_id_expected = XDMA_ID_H2C;
    }

    engine_id = get_engine_id(regs);
    channel_id = get_engine_channel_id(regs);
    pr_info("engine ID = 0x%x, channel ID = %d\n", engine_id, channel_id);

    if (engine_id != engine_id_expected) {
        pr_info("incorrect engine ID - skipping\n");
        return 0;
    }

    if (channel_id != channel) {
        pr_info("expected channel ID %d, read %d\n", channel, channel_id);
        return 0;
    }

    // init engine
    if (c2h) { // c2h
        pr_info("found c2h %d engine at %p\n", channel, regs);
        tmp_engine = engine_create(d, offs, c2h, channel);
        if (!tmp_engine) {
            pr_err("error creating channel engine\n");
            return -1;
        }
        d->engine_c2h[channel] = tmp_engine;
        d->engines_num++;
    }
    else { // h2c
        pr_info("found h2c %d engine at %p\n", channel, regs);
        tmp_engine = engine_create(d, offs, c2h, channel);
        if (!tmp_engine) {
            pr_err("error creating channel engine\n");
            return -1;
        }
        d->engine_h2c[channel] = tmp_engine;
        d->engines_num++;
    }

    return 0;
}

/**
 * @brief Probe C2H and H2C engines
 * 
 */
int probe_engines(struct bus_drvdata *d)
{
    int ret_val = 0;
    int channel;

    BUG_ON(!d);

    // probe for vFPGA h2c engines
    for (channel = 0; channel < MAX_NUM_CHANNELS; channel++) {
        ret_val = probe_for_engine(d, 0, channel); // h2c
        if (ret_val)
            goto fail;
    }

    // probe for vFPGA c2h engines
    for (channel = 0; channel < MAX_NUM_CHANNELS; channel++) {
        ret_val = probe_for_engine(d, 1, channel); // c2h
        if (ret_val)
            goto fail;
    }

    if (d->engines_num < 2 * d->n_fpga_chan) {
        pr_info("failed to detect all required c2h or h2c engines\n");
        return -ENODEV;
    }

    pr_info("found %d engines\n", d->engines_num);

    goto success;
fail:
    pr_err("engine probing failed - unwinding\n");
    remove_engines(d);
success:
    return ret_val;
}

/*
██████╗  █████╗ ██████╗ ███████╗
██╔══██╗██╔══██╗██╔══██╗██╔════╝
██████╔╝███████║██████╔╝███████╗
██╔══██╗██╔══██║██╔══██╗╚════██║
██████╔╝██║  ██║██║  ██║███████║
╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝
*/

/**
 * @brief Map a single BAR
 * 
 * @param idx - BAR index
 * @param curr_idx - current BAR mapping
 */
int map_single_bar(struct bus_drvdata *d, struct pci_dev *pdev, int idx, int curr_idx)
{
    resource_size_t bar_start, bar_len, map_len;

    bar_start = pci_resource_start(pdev, idx);
    bar_len = pci_resource_len(pdev, idx);
    map_len = bar_len;

    d->bar[curr_idx] = NULL;

    if (!bar_len) {
        pr_info("BAR #%d is not present\n", idx);
        return 0;
    }

    if (bar_len > INT_MAX) {
        pr_info("BAR %d limited from %llu to %d bytes\n", idx, (u64)bar_len, INT_MAX);
        map_len = (resource_size_t)INT_MAX;
    }

    pr_info("mapping BAR %d, %llu bytes to be mapped", idx, (u64)map_len);
    d->bar[curr_idx] = pci_iomap(pdev, idx, map_len);

    if (!d->bar[curr_idx]) {
        dev_err(&pdev->dev, "could not map BAR %d\n", idx);
        return -1;
    }

    pr_info("BAR%d at 0x%llx mapped at 0x%p, length=%llu, (%llu)\n",
            idx, (u64)bar_start, d->bar[curr_idx], (u64)map_len, (u64)bar_len);

    d->bar_phys_addr[curr_idx] = bar_start;
    d->bar_len[curr_idx] = map_len;

    return (int)map_len;
}

/**
 * @brief PCI BAR unmapping
 * 
 */
void unmap_bars(struct bus_drvdata *d, struct pci_dev *pdev)
{
    int i;

    for (i = 0; i < CYT_BARS; i++) {
        if (d->bar[i]) {
            pci_iounmap(pdev, d->bar[i]);
            d->bar[i] = NULL;
            pr_info("BAR%d unmapped\n", i);
        }
    }
}

/**
 * @brief PCI BAR mapping
 * 
 */
int map_bars(struct bus_drvdata *d, struct pci_dev *pdev)
{
    int ret_val;
    int i = 0;
    int curr_idx = 0;

    while((curr_idx < CYT_BARS) && (i < MAX_NUM_BARS)) {
        int bar_len = map_single_bar(d, pdev, i++, curr_idx);
        if (bar_len == 0) {
            continue;
        }
        else if (bar_len < 0) {
            ret_val = -1;
            goto fail;
        }
        curr_idx++;
    }
    goto success;
fail:
    pr_err("mapping of the bars failed\n");
    unmap_bars(d, pdev);
    return ret_val;
success:
    return 0;
}

/*
██████╗ ███████╗ ██████╗ ██╗ ██████╗ ███╗   ██╗███████╗
██╔══██╗██╔════╝██╔════╝ ██║██╔═══██╗████╗  ██║██╔════╝
██████╔╝█████╗  ██║  ███╗██║██║   ██║██╔██╗ ██║███████╗
██╔══██╗██╔══╝  ██║   ██║██║██║   ██║██║╚██╗██║╚════██║
██║  ██║███████╗╚██████╔╝██║╚██████╔╝██║ ╚████║███████║
╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝
*/

/**
 * @brief Request PCI dev regions
 * 
 */
int request_regions(struct bus_drvdata *d, struct pci_dev *pdev)
{
    int ret_val;

    BUG_ON(!d);
    BUG_ON(!pdev);

    pr_info("pci request regions\n");
    ret_val = pci_request_regions(pdev, DRV_NAME);
    if (ret_val) {
        pr_info("device in use, return %d\n", ret_val);
        d->got_regions = 0;
        d->regions_in_use = 1;
    }
    else {
        d->got_regions = 1;
        d->regions_in_use = 0;
    }

    return ret_val;
}

/*
██████╗ ██████╗  ██████╗ ██████╗ ███████╗
██╔══██╗██╔══██╗██╔═══██╗██╔══██╗██╔════╝
██████╔╝██████╔╝██║   ██║██████╔╝█████╗  
██╔═══╝ ██╔══██╗██║   ██║██╔══██╗██╔══╝  
██║     ██║  ██║╚██████╔╝██████╔╝███████╗
╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝
*/

/**
 * @brief Shell init
 * 
 */
int shell_pci_init(struct bus_drvdata *d)
{
    int ret_val = 0;

    // dynamic major
    dev_t dev_fpga = MKDEV(d->fpga_major, 0);

    pr_info("initializing shell ...\n");

    // get shell config
    ret_val = read_shell_config(d);
    if(ret_val) {
        pr_err("cannot read static config\n");
        goto err_read_shell_cnfg;
    }

    // Sysfs entry
    ret_val = create_sysfs_entry(d);
    if (ret_val) {
        pr_err("cannot create a sysfs entry\n");
        goto err_sysfs;
    }

    // allocate card mem resources
    ret_val = alloc_card_resources(d);
    if (ret_val) {
        pr_err("card resources could not be allocated\n");
        goto err_card_alloc; // ERR_CARD_ALLOC
    }

    // create FPGA devices and register major
    ret_val = init_char_fpga_devices(d, dev_fpga);
    if (ret_val) {
        goto err_create_fpga_dev; // ERR_CREATE_FPGA_DEV
    }

    // initialize vFPGAs
    ret_val = init_fpga_devices(d);
    if (ret_val) {
        goto err_init_fpga_dev;
    }

    // user IRQs
    ret_val = irq_setup(d, d->pci_dev, false);
    if (ret_val) {
        pr_err("IRQ setup error\n");
        goto err_irq;
    }

    // enable interrupts
    user_interrupts_enable(d, ~0);
    //channel_interrupts_enable(d, ~0);

    // flush writes
    read_interrupts(d);

    if (ret_val == 0)
        goto end;

err_irq:
    free_fpga_devices(d);
err_init_fpga_dev:
    free_char_fpga_devices(d);
err_create_fpga_dev:
    vfree(d->schunks);
    vfree(d->lchunks);
err_card_alloc:
    remove_sysfs_entry(d);
err_sysfs:
err_read_shell_cnfg:
end:
    pr_info("shell load returning %d\n", ret_val);
    return ret_val;
}

/**
 * @brief Shell remove
 * 
 */
void shell_pci_remove(struct bus_drvdata *d)
{
    pr_info("removing shell ...\n");

    // free svm chunks
#ifdef HMM_KERNEL    
    free_mem_regions(d);
    pr_info("freed svm private pages");
#endif

    // disable FPGA interrupts
    //channel_interrupts_disable(d, ~0);
    user_interrupts_disable(d, ~0);
    pr_info("interrupts disabled\n");

    // remove IRQ
    irq_teardown(d, false);
    pr_info("IRQ teardown\n");

    // delete vFPGAs
    free_fpga_devices(d);
    
    // delete char devices
    free_char_fpga_devices(d);
    
    // deallocate card resources
    free_card_resources(d);

    // remove sysfs
    remove_sysfs_entry(d);

    pr_info("shell removed\n");
}

/**
 * @brief PCI device probe
 * 
 */
int pci_probe(struct pci_dev *pdev, const struct pci_device_id *id)
{
    int ret_val = 0;
    struct bus_drvdata *d = NULL;
    dev_t dev_fpga;
    dev_t dev_pr;

    // entering probe
    pr_info("probe (pdev = 0x%p, pci_id = 0x%p)\n", pdev, id);

    // allocate mem. for device instance
    d = devm_kzalloc(&pdev->dev, sizeof(struct bus_drvdata), GFP_KERNEL);
    if (!d) {
        dev_err(&pdev->dev, "device memory region not obtained\n");
        goto err_alloc; // ERR_ALLOC
    }
    // set device private data
    d->pci_dev = pdev;
    dev_set_drvdata(&pdev->dev, d);

    // dynamic major
    d->fpga_major = FPGA_MAJOR;
    d->pr_major = PR_MAJOR;

    dev_fpga = MKDEV(d->fpga_major, 0);
    dev_pr = MKDEV(d->pr_major, 0);

    // enable PCIe device
    ret_val = pci_enable_device(pdev);
    if (ret_val) {
        dev_err(&pdev->dev, "pci device could not be enabled\n");
        goto err_enable; // ERR_ENABLE
    }
    pr_info("pci device node %p enabled\n", &pdev->dev);

    ret_val = assign_dev_id(d);
    if(ret_val) {
        dev_err(&pdev->dev, "device id not found in the config file\n");
        goto err_dev_id; // ERR_DEV_ID
    }

    // relaxed ordering 
	pci_enable_capability(pdev, PCI_EXP_DEVCTL_RELAX_EN);

	// extended tag
	pci_enable_capability(pdev, PCI_EXP_DEVCTL_EXT_TAG);

    // MRRS
	pcie_set_readrq(pdev, 512);

    // enable bus master capability
    pci_set_master(pdev);
    pr_info("pci bus master capability enabled\n");

    // check IRQ
    ret_val = pci_check_msix(d, pdev);
    if (ret_val < 0) {
        dev_err(&pdev->dev, "pci IRQ error\n");
        goto err_irq_en; // ERR_IRQ_EN
    }

    // request PCI regions
    ret_val = request_regions(d, pdev);
    if (ret_val) {
        dev_err(&pdev->dev, "pci regions could not be obtained\n");
        goto err_regions; // ERR_REGIONS
    }
    pr_info("pci regions obtained\n");

    // BAR mapping
    ret_val = map_bars(d, pdev);
    if (ret_val) {
        dev_err(&pdev->dev, "mapping of the BARs failed\n");
        goto err_map; // ERR_MAP
    }

    // DMA addressing
    pr_info("sizeof(dma_addr_t) == %ld\n", sizeof(dma_addr_t));
    ret_val = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(64));
    if (ret_val) {
        dev_err(&pdev->dev, "failed to set 64b DMA mask\n");
        goto err_mask; // ERR_MASK
    }

    // probe DMA engines
    ret_val = probe_engines(d);
    if (ret_val) {
        dev_err(&pdev->dev, "error whilst probing DMA engines\n");
        goto err_engines;
    }

    // initialize spin locks
    init_spin_locks(d);

    // config remap
    d->fpga_stat_cnfg = ioremap(d->bar_phys_addr[BAR_STAT_CONFIG] + FPGA_STAT_CNFG_OFFS, FPGA_STAT_CNFG_SIZE);
    d->fpga_shell_cnfg = ioremap(d->bar_phys_addr[BAR_SHELL_CONFIG] + FPGA_SHELL_CNFG_OFFS, FPGA_SHELL_CNFG_SIZE);

    // read config
    ret_val = read_shell_config(d);
    if(ret_val) {
        dev_err(&pdev->dev, "cannot read shell config\n");
        goto err_read_shell_cnfg;
    }

    // Sysfs entry
    ret_val = create_sysfs_entry(d);
    if (ret_val) {
        dev_err(&pdev->dev, "cannot create a sysfs entry\n");
        goto err_sysfs;
    }

    // allocate card mem resources
    ret_val = alloc_card_resources(d);
    if (ret_val) {
        dev_err(&pdev->dev, "card resources could not be allocated\n");
        goto err_card_alloc; // ERR_CARD_ALLOC
    }

    // create PR device and register major
    ret_val = init_char_pr_device(d, dev_pr);
    if (ret_val) {
        goto err_create_pr_dev; // ERR_CREATE_FPGA_DEV
    }

    // initialize PR
    ret_val = init_pr_device(d);
    if (ret_val) {
        goto err_init_pr_dev;
    }

    // create FPGA devices and register major
    ret_val = init_char_fpga_devices(d, dev_fpga);
    if (ret_val) {
        goto err_create_fpga_dev; // ERR_CREATE_FPGA_DEV
    }

    // initialize vFPGAs
    ret_val = init_fpga_devices(d);
    if (ret_val) {
        goto err_init_fpga_dev;
    }

    // user IRQs
    ret_val = irq_setup(d, pdev, true);
    if (ret_val) {
        dev_err(&pdev->dev, "IRQ setup error\n");
        goto err_irq;
    }

    // enable interrupts
    pr_interrupt_enable(d);
    user_interrupts_enable(d, ~0);
    //channel_interrupts_enable(d, ~0);

    // flush writes
    read_interrupts(d);

    if (ret_val == 0)
        goto end;

err_irq:
    free_fpga_devices(d);
err_init_fpga_dev:
    free_char_fpga_devices(d);
err_create_fpga_dev:
    free_pr_device(d);
err_init_pr_dev:
    free_char_pr_device(d);
err_create_pr_dev:
    vfree(d->schunks);
    vfree(d->lchunks);
err_card_alloc:
    remove_sysfs_entry(d);
err_sysfs:
err_read_shell_cnfg:
    remove_engines(d);
err_engines:
err_mask:
    unmap_bars(d, pdev);
err_map:
    if (d->got_regions)
        pci_release_regions(pdev);
err_regions:
    if (d->msix_enabled) {
        pci_disable_msix(pdev);
        pr_info("MSI-X disabled\n");
    }
err_irq_en:
    if (!d->regions_in_use)
        pci_disable_device(pdev);
err_dev_id:
err_enable:
    kfree(d);
err_alloc:
end:
    pr_info("probe returning %d\n", ret_val);
    return ret_val;
}

/**
 * @brief PCI dev removal
 * 
 */
void pci_remove(struct pci_dev *pdev)
{
    struct bus_drvdata *d;

    d = (struct bus_drvdata *)dev_get_drvdata(&pdev->dev);

    // free svm chunks
#ifdef HMM_KERNEL    
    free_mem_regions(d);
    pr_info("freed svm private pages");
#endif

    // disable FPGA interrupts
    //channel_interrupts_disable(d, ~0);
    user_interrupts_disable(d, ~0);
    pr_interrupt_disable(d);
    pr_info("interrupts disabled\n");

    // remove IRQ
    irq_teardown(d, true);
    pr_info("IRQ teardown\n");

    // delete vFPGAs
    free_fpga_devices(d);

    // delete char devices
    free_char_fpga_devices(d);

    // delete PR
    free_pr_device(d);

    // delete char device
    free_char_pr_device(d);
    
    // deallocate card resources
    free_card_resources(d);

    // remove sysfs
    remove_sysfs_entry(d);

    // engine removal
    remove_engines(d);
    pr_info("engines removed\n");

    // unmap BARs
    unmap_bars(d, pdev);
    pr_info("BARs unmapped\n");

    // release regions
    if (d->got_regions)
        pci_release_regions(pdev);
    pr_info("pci regions released\n");

    // disable interrupts
    if (d->msix_enabled) {
        pci_disable_msix(pdev);
        pr_info("MSI-X disabled\n");
    }

    // disable device
    if (!d->regions_in_use)
        pci_disable_device(pdev);
    pr_info("pci device disabled\n");

    // free device data
    devm_kfree(&pdev->dev, d);
    pr_info("device memory freed\n");

    pr_info("removal completed\n");
}


/*
██████╗ ██████╗ ██╗██╗   ██╗███████╗██████╗ 
██╔══██╗██╔══██╗██║██║   ██║██╔════╝██╔══██╗
██║  ██║██████╔╝██║██║   ██║█████╗  ██████╔╝
██║  ██║██╔══██╗██║╚██╗ ██╔╝██╔══╝  ██╔══██╗
██████╔╝██║  ██║██║ ╚████╔╝ ███████╗██║  ██║
╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝
*/

static const struct pci_device_id pci_ids[] = {
    { PCI_DEVICE(0x10ee, 0x9011), },
    { PCI_DEVICE(0x10ee, 0x9012), },
    { PCI_DEVICE(0x10ee, 0x9014), },
    { PCI_DEVICE(0x10ee, 0x9018), },
    { PCI_DEVICE(0x10ee, 0x901F), },
    { PCI_DEVICE(0x10ee, 0x9021), },
    { PCI_DEVICE(0x10ee, 0x9022), },
    { PCI_DEVICE(0x10ee, 0x9024), },
    { PCI_DEVICE(0x10ee, 0x9028), },
    { PCI_DEVICE(0x10ee, 0x902F), },
    { PCI_DEVICE(0x10ee, 0x9031), },
    { PCI_DEVICE(0x10ee, 0x9032), },
    { PCI_DEVICE(0x10ee, 0x9034), },
    { PCI_DEVICE(0x10ee, 0x9038), },
    { PCI_DEVICE(0x10ee, 0x903F), },
    { PCI_DEVICE(0x10ee, 0x8011), },
    { PCI_DEVICE(0x10ee, 0x8012), },
    { PCI_DEVICE(0x10ee, 0x8014), },
    { PCI_DEVICE(0x10ee, 0x8018), },
    { PCI_DEVICE(0x10ee, 0x8021), },
    { PCI_DEVICE(0x10ee, 0x8022), },
    { PCI_DEVICE(0x10ee, 0x8024), },
    { PCI_DEVICE(0x10ee, 0x8028), },
    { PCI_DEVICE(0x10ee, 0x8031), },
    { PCI_DEVICE(0x10ee, 0x8032), },
    { PCI_DEVICE(0x10ee, 0x8034), },
    { PCI_DEVICE(0x10ee, 0x8038), },
    { PCI_DEVICE(0x10ee, 0x7011), },
    { PCI_DEVICE(0x10ee, 0x7012), },
    { PCI_DEVICE(0x10ee, 0x7014), },
    { PCI_DEVICE(0x10ee, 0x7018), },
    { PCI_DEVICE(0x10ee, 0x7021), },
    { PCI_DEVICE(0x10ee, 0x7022), },
    { PCI_DEVICE(0x10ee, 0x7024), },
    { PCI_DEVICE(0x10ee, 0x7028), },
    { PCI_DEVICE(0x10ee, 0x7031), },
    { PCI_DEVICE(0x10ee, 0x7032), },
    { PCI_DEVICE(0x10ee, 0x7034), },
    { PCI_DEVICE(0x10ee, 0x7038), },
    {0,}
};
MODULE_DEVICE_TABLE(pci, pci_ids);

static struct pci_driver pci_driver = {
    .name = DRV_NAME,
    .id_table = pci_ids,
    .probe = pci_probe,
    .remove = pci_remove,
};

/*
██████╗ ███████╗ ██████╗ ██╗███████╗████████╗███████╗██████╗ 
██╔══██╗██╔════╝██╔════╝ ██║██╔════╝╚══██╔══╝██╔════╝██╔══██╗
██████╔╝█████╗  ██║  ███╗██║███████╗   ██║   █████╗  ██████╔╝
██╔══██╗██╔══╝  ██║   ██║██║╚════██║   ██║   ██╔══╝  ██╔══██╗
██║  ██║███████╗╚██████╔╝██║███████║   ██║   ███████╗██║  ██║
╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
*/

/**
 * @brief PCI init
 * 
 */
int pci_init(void) {
    int ret_val;

    if(strcmp(config_fname, "") != 0) {
        pr_info("reading external device config ...");
        ret_val = read_dev_config(config_fname);
        //return ret_val;
    }

    ret_val = pci_register_driver(&pci_driver);
    if (ret_val) {
        pr_err("Coyote driver register returned %d\n", ret_val);
        return ret_val;
    }

    return 0;
}

/**
 * @brief PCI exit
 * 
 */
void pci_exit(void) {
    struct device_mapping *entry, *tmp;

    if(strcmp(config_fname, "") != 0) {
        list_for_each_entry_safe(entry, tmp, &device_mappings, list) {
            list_del(&entry->list);
            kfree(entry);
        }
    }

    pci_unregister_driver(&pci_driver);
}
