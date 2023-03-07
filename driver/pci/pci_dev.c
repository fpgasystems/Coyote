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

/*
 _   _ _   _ _
| | | | |_(_) |
| | | | __| | |
| |_| | |_| | |
 \___/ \__|_|_|
*/

inline uint32_t build_u32(uint32_t hi, uint32_t lo) {
    return ((hi & 0xFFFFUL) << 16) | (lo & 0xFFFFUL);
}

inline uint64_t build_u64(uint64_t hi, uint64_t lo) {
    return ((hi & 0xFFFFFFFULL) << 32) | (lo & 0xFFFFFFFFULL);
}

/*
 ___       _                             _
|_ _|_ __ | |_ ___ _ __ _ __ _   _ _ __ | |_ ___
 | || '_ \| __/ _ \ '__| '__| | | | '_ \| __/ __|
 | || | | | ||  __/ |  | |  | |_| | |_) | |_\__ \
|___|_| |_|\__\___|_|  |_|   \__,_| .__/ \__|___/
                                  |_|
*/

/**
 * @brief User interrupt enable
 * 
 */
void user_interrupts_enable(struct bus_drvdata *d, uint32_t mask)
{
    struct interrupt_regs *reg = (struct interrupt_regs *)(d->bar[BAR_XDMA_CONFIG] + XDMA_OFS_INT_CTRL);

    iowrite32(mask, &reg->user_int_enable_w1s);
}

/**
 * @brief User interrupt disable
 * 
 */
void user_interrupts_disable(struct bus_drvdata *d, uint32_t mask)
{
    struct interrupt_regs *reg = (struct interrupt_regs *)(d->bar[BAR_XDMA_CONFIG] + XDMA_OFS_INT_CTRL);

    iowrite32(mask, &reg->user_int_enable_w1c);
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

    int_regs = (struct interrupt_regs *)(d->bar[0] + XDMA_OFS_INT_CTRL);

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
    iowrite32(reg_val, &int_regs->channel_msi_vector[0]);

    reg_val = build_vector_reg(20, 21, 22, 23);
    iowrite32(reg_val, &int_regs->channel_msi_vector[1]);
}

/**
 * @brief Remove user IRQs
 * 
 */
void irq_teardown(struct bus_drvdata *d)
{
    int i;

    if (d->msix_enabled) {
        for (i = 0; i < d->n_fpga_reg; i++) {
            pr_info("releasing IRQ%d\n", d->irq_entry[i].vector);
            free_irq(d->irq_entry[i].vector, &d->fpga_dev[i]);
        }
    }
    else if (d->irq_line != -1) {
        pr_info("releasing IRQ%d\n", d->irq_line);
        free_irq(d->irq_line, d);
    }
}

/**
 * @brief Setup user MSI-X
 * 
 */
int msix_irq_setup(struct bus_drvdata *d)
{
    int i;
    int ret_val;

    BUG_ON(!d);

    write_msix_vectors(d);

    for (i = 0; i < d->n_fpga_reg; i++) {
        ret_val = request_irq(d->irq_entry[i].vector, fpga_tlb_miss_isr, 0,
                              DRV_NAME, &d->fpga_dev[i]);

        if (ret_val) {
            pr_info("couldn't use IRQ#%d, ret=%d\n", d->irq_entry[i].vector, ret_val);
            break;
        }

        pr_info("using IRQ#%d with %d\n", d->irq_entry[i].vector, d->fpga_dev[i].id);
    }

    // unwind
    if (ret_val) {
        while (--i >= 0)
            free_irq(d->irq_entry[i].vector, &d->fpga_dev[i]);
    }

    return ret_val;
}

/**
 * @brief Setup user IRQs
 * 
 */
int irq_setup(struct bus_drvdata *d, struct pci_dev *pdev)
{
    int ret_val = 0;

    if (d->msix_enabled)
    {
        ret_val = msix_irq_setup(d);
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

        ret_val = pci_enable_msix_range(pdev, d->irq_entry, 0, req_nvec);
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

/*
 _____             _                       _
| ____|_ __   __ _(_)_ __   ___   ___  ___| |_ _   _ _ __
|  _| | '_ \ / _` | | '_ \ / _ \ / __|/ _ \ __| | | | '_ \
| |___| | | | (_| | | | | |  __/ \__ \  __/ |_| |_| | |_) |
|_____|_| |_|\__, |_|_| |_|\___| |___/\___|\__|\__,_| .__/
             |___/                                  |_|
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
        engine = d->fpga_dev[i * d->n_fpga_reg].engine_h2c;
        if (engine) {
            pr_info("remove %s%d\n", engine->name, engine->channel);
            engine_destroy(d, engine);
        }

        engine = d->fpga_dev[i * d->n_fpga_reg].engine_c2h;
        if (engine) {
            pr_info("remove %s%d\n", engine->name, engine->channel);
            engine_destroy(d, engine);
        }
    }

    if (d->en_pr) {
        engine = d->prc.engine_h2c;
        if (engine) {
            pr_info("remove %s%d\n", engine->name, engine->channel);
            engine_destroy(d, engine);
        }

        engine = d->prc.engine_c2h;
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
        dma_free_coherent(&d->pci_dev->dev, sizeof(struct xdma_poll_wb),
                            engine->poll_mode_addr_virt, engine->poll_mode_phys_addr);
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
    engine->poll_mode_addr_virt = dma_alloc_coherent(&d->pci_dev->dev,
                                                       sizeof(struct xdma_poll_wb), &engine->poll_mode_phys_addr, GFP_ATOMIC);
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

    // writeback (not used)
    /*
    ret_val = engine_writeback_setup(d, engine);
    if (ret_val) {
        pr_info("Descriptor writeback setup failed for %p, channel %d\n", engine, engine->channel);
        return NULL;
    }
    */

    // start engine
    reg_val |= XDMA_CTRL_POLL_MODE_WB;
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
    int offs, i;
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
    if (channel == d->n_fpga_chan && d->en_pr) {
        if (c2h) { // c2h
            pr_info("found PR c2h %d engine at %p\n", channel, regs);
            d->prc.engine_c2h = engine_create(d, offs, c2h, channel);
            if (!d->prc.engine_c2h) {
                pr_err("error creating channel engine\n");
                return -1;
            }
            pr_info("engine channel %d assigned to PR", channel);
            d->engines_num++;
        }
        else { // h2c
            pr_info("found PR h2c %d engine at %p\n", channel, regs);
            d->prc.engine_h2c = engine_create(d, offs, c2h, channel);
            if (!d->prc.engine_h2c) {
                pr_err("error creating channel engine\n");
                return -1;
            }
            pr_info("engine channel %d assigned to PR", channel);
            d->engines_num++;
        }
    }
    else {
        if (c2h) { // c2h
            pr_info("found vFPGA c2h %d engine at %p\n", channel, regs);
            tmp_engine = engine_create(d, offs, c2h, channel);
            if (!tmp_engine) {
                pr_err("error creating channel engine\n");
                return -1;
            }
            for (i = 0; i < d->n_fpga_reg; i++) {
                d->fpga_dev[channel * d->n_fpga_reg + i].engine_h2c = tmp_engine;
                pr_info("engine channel %d assigned to vFPGA %d", channel, d->fpga_dev[channel * d->n_fpga_reg + i].id);
            }
            d->engines_num++;
        }
        else { // h2c
            pr_info("found vFPGA h2c %d engine at %p\n", channel, regs);
            tmp_engine = engine_create(d, offs, c2h, channel);
            if (!tmp_engine) {
                pr_err("error creating channel engine\n");
                return -1;
            }
            for (i = 0; i < d->n_fpga_reg; i++) {
                d->fpga_dev[channel * d->n_fpga_reg + i].engine_c2h = tmp_engine;
                pr_info("engine channel %d assigned to vFPGA %d", channel, d->fpga_dev[channel * d->n_fpga_reg + i].id);
            }
            d->engines_num++;
        }
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
 ____    _    ____                                _
| __ )  / \  |  _ \   _ __ ___   __ _ _ __  _ __ (_)_ __   __ _
|  _ \ / _ \ | |_) | | '_ ` _ \ / _` | '_ \| '_ \| | '_ \ / _` |
| |_) / ___ \|  _ <  | | | | | | (_| | |_) | |_) | | | | | (_| |
|____/_/   \_\_| \_\ |_| |_| |_|\__,_| .__/| .__/|_|_| |_|\__, |
                                     |_|   |_|            |___/
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

    for (i = 0; i < MAX_NUM_BARS; i++) {
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
    int i;
    int curr_idx = 0;

    for (i = 0; i < MAX_NUM_BARS; ++i) {
        int bar_len = map_single_bar(d, pdev, i, curr_idx);
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
 ____            _
|  _ \ ___  __ _(_) ___  _ __  ___
| |_) / _ \/ _` | |/ _ \| '_ \/ __|
|  _ <  __/ (_| | | (_) | | | \__ \
|_| \_\___|\__, |_|\___/|_| |_|___/
           |___/
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
 ____            _
|  _ \ _ __ ___ | |__   ___
| |_) | '__/ _ \| '_ \ / _ \
|  __/| | | (_) | |_) |  __/su
|_|   |_|  \___/|_.__/ \___|
*/

/**
 * @brief PCI device probe
 * 
 */
int pci_probe(struct pci_dev *pdev, const struct pci_device_id *id)
{
    int ret_val = 0, i;
    struct bus_drvdata *d = NULL;

    // dynamic major
    dev_t dev = MKDEV(fpga_major, 0);

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

    // enable PCIe device
    ret_val = pci_enable_device(pdev);
    if (ret_val) {
        dev_err(&pdev->dev, "pci device could not be enabled\n");
        goto err_enable; // ERR_ENABLE
    }
    pr_info("pci device node %p enabled\n", &pdev->dev);

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

    // get static config
    d->fpga_stat_cnfg = ioremap(d->bar_phys_addr[BAR_FPGA_CONFIG] + FPGA_STAT_CNFG_OFFS, FPGA_STAT_CNFG_SIZE);
    ret_val = read_static_config(d);
    if(ret_val) {
        dev_err(&pdev->dev, "cannot read static config\n");
        goto err_read_stat_cnfg;
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

    // initialize spin locks
    init_spin_locks(d);

    // create FPGA devices and register major
    ret_val = init_char_devices(d, dev);
    if (ret_val) {
        goto err_create_fpga_dev; // ERR_CREATE_FPGA_DEV
    }

    // initialize vFPGAs
    ret_val = init_fpga_devices(d);
    if (ret_val) {
        goto err_init_fpga_dev;
    }

    // Init hash
    hash_init(pr_buff_map);

    // probe DMA engines
    ret_val = probe_engines(d);
    if (ret_val) {
        dev_err(&pdev->dev, "error whilst probing DMA engines\n");
        goto err_engines;
    }

    // user IRQs
    ret_val = irq_setup(d, pdev);
    if (ret_val) {
        dev_err(&pdev->dev, "IRQ setup error\n");
        goto err_irq;
    }

    // enable interrupts
    user_interrupts_enable(d, ~0);

    // flush writes
    read_interrupts(d);

    if (ret_val == 0)
        goto end;

err_irq:
    remove_engines(d);
err_engines:
    for(i = 0; i < d->n_fpga_reg; i++) {
        device_destroy(fpga_class, MKDEV(fpga_major, i));
        cdev_del(&d->fpga_dev[i].cdev);

        if(d->en_wb) {
            set_memory_wb((uint64_t)d->fpga_dev[i].wb_addr_virt, N_WB_PAGES);
            dma_free_coherent(&d->pci_dev->dev, WB_SIZE,
                d->fpga_dev[i].wb_addr_virt, d->fpga_dev[i].wb_phys_addr);
        }

        vfree(d->fpga_dev[i].pid_array);
        vfree(d->fpga_dev[i].pid_chunks);
    }
err_init_fpga_dev:
    kfree(d->fpga_dev);
    class_destroy(fpga_class);
err_create_fpga_dev:
    vfree(d->schunks);
    vfree(d->lchunks);
err_card_alloc:
    remove_sysfs_entry(d);
err_sysfs:
err_read_stat_cnfg:
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

    // disable FPGA interrupts
    user_interrupts_disable(d, ~0);
    pr_info("interrupts disabled\n");

    // remove IRQ
    irq_teardown(d);
    pr_info("IRQ teardown\n");

    // engine removal
    remove_engines(d);
    pr_info("engines removed\n");

    // delete vFPGAs
    free_fpga_devices(d);
    
    // delete char devices
    free_char_devices(d);
    
    // deallocate card resources
    free_card_resources(d);

    // remove sysfs
    remove_sysfs_entry(d);

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
 ____       _
|  _ \ _ __(_)_   _____ _ __
| | | | '__| \ \ / / _ \ '__|
| |_| | |  | |\ V /  __/ |
|____/|_|  |_| \_/ \___|_|
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
 ____            _     _
|  _ \ ___  __ _(_)___| |_ ___ _ __
| |_) / _ \/ _` | / __| __/ _ \ '__|
|  _ <  __/ (_| | \__ \ ||  __/ |
|_| \_\___|\__, |_|___/\__\___|_|
           |___/
*/

/**
 * @brief PCI init
 * 
 */
int pci_init(void) {
    int ret_val;

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
    pci_unregister_driver(&pci_driver);
}
