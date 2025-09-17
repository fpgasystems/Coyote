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

#include "pci_xdma.h"

static uint32_t current_device = 0;

void assign_device_id(struct bus_driver_data *bd_data) {
    bd_data->dev_id = current_device++;
    dbg_info("fpga device id %d, pci bus %02x, pci slot %02x\n", bd_data->dev_id, bd_data->pci_dev->bus->number, PCI_SLOT(bd_data->pci_dev->devfn));
    sprintf(bd_data->vfpga_dev_name, "%s_%d", DEV_FPGA_NAME, bd_data->dev_id);
    sprintf(bd_data->reconfig_dev_name, "%s_reconfig", bd_data->vfpga_dev_name);
}

void vfpga_interrupts_enable(struct bus_driver_data *bd_data) {
    struct xdma_interrupt_regs *reg = (struct xdma_interrupt_regs *)(bd_data->bar[BAR_DMA_CONFIG] + XDMA_OFS_INT_CTRL);
    iowrite32(FPGA_USER_IRQ_MASK, &reg->user_int_enable_w1s);
}

void vfpga_interrupts_disable(struct bus_driver_data *bd_data) {
    struct xdma_interrupt_regs *reg = (struct xdma_interrupt_regs *)(bd_data->bar[BAR_DMA_CONFIG] + XDMA_OFS_INT_CTRL);
    iowrite32(FPGA_USER_IRQ_MASK, &reg->user_int_enable_w1c);
}

void reconfig_interrupt_enable(struct bus_driver_data *bd_data) {
    struct xdma_interrupt_regs *reg = (struct xdma_interrupt_regs *)(bd_data->bar[BAR_DMA_CONFIG] + XDMA_OFS_INT_CTRL);
    iowrite32(FPGA_RECONFIG_IRQ_MASK, &reg->user_int_enable_w1s);
}

void reconfig_interrupt_disable(struct bus_driver_data *bd_data) {
    struct xdma_interrupt_regs *reg = (struct xdma_interrupt_regs *)(bd_data->bar[BAR_DMA_CONFIG] + XDMA_OFS_INT_CTRL);
    iowrite32(FPGA_RECONFIG_IRQ_MASK, &reg->user_int_enable_w1c);
}

uint32_t read_interrupts(struct bus_driver_data *bd_data) {
    struct xdma_interrupt_regs *reg = (struct xdma_interrupt_regs *)(bd_data->bar[BAR_DMA_CONFIG] + XDMA_OFS_INT_CTRL);
    uint32_t lo, hi;

    // hi, lo represent the actual register values
    hi = ioread32(&reg->user_int_request);
    lo = ioread32(&reg->channel_int_request);

    // &reg->user_int_request, &reg->channel_int_request are memory locations of the registers
    dbg_info("ioread32(0x%p) returned 0x%08x (user_int_request).\n", &reg->user_int_request, hi);
    dbg_info("ioread32(0x%p) returned 0x%08x (channel_int_request)\n", &reg->channel_int_request, lo);

    return build_u32(hi, lo);
}

void write_msix_vectors(struct bus_driver_data *bd_data) {
    BUG_ON(!bd_data);

    uint32_t reg_val = 0;
    struct xdma_interrupt_regs *int_regs = (struct xdma_interrupt_regs *)(bd_data->bar[BAR_DMA_CONFIG] + XDMA_OFS_INT_CTRL);

    reg_val = build_vector_reg(0, 1, 2, 3);
    iowrite32(reg_val, &int_regs->user_msi_vector[0]);

    reg_val = build_vector_reg(4, 5, 6, 7);
    iowrite32(reg_val, &int_regs->user_msi_vector[1]);

    reg_val = build_vector_reg(8, 9, 10, 11);
    iowrite32(reg_val, &int_regs->user_msi_vector[2]);

    reg_val = build_vector_reg(12, 13, 14, 15);
    iowrite32(reg_val, &int_regs->user_msi_vector[3]);
}

int irq_setup(struct bus_driver_data *bd_data, struct pci_dev *pdev, bool enable_reconfig_irq) {
    BUG_ON(!bd_data);

    // Check MSI-X is available and enabled
    if (!bd_data->msix_enabled) {
        pr_err("MSI-X not enabled, cannot set-up interrupts, exiting...\n");
        return -1;
    }

    // vFPGA IRQ
    int i, ret_val;
    for (i = 0; i < bd_data->n_fpga_reg; i++) {
        // Request a vector for this vFPGA device
        uint32_t vector = pci_irq_vector(pdev, i);
        bd_data->irq_entry[i].vector = vector;
        ret_val = request_irq(vector, vfpga_isr, 0, COYOTE_DRIVER_NAME, &bd_data->vfpga_dev[i]);

        if (ret_val) {
            pr_err("couldn't use IRQ#%d, ret=%d\n", vector, ret_val);
            goto err_user;
        }

        dbg_info("using IRQ#%d with vFPGA %d\n", vector, bd_data->vfpga_dev[i].id);
    }

    // Reconfiguration IRQ
    if (enable_reconfig_irq) {
        uint32_t vector = pci_irq_vector(pdev, FPGA_RECONFIG_IRQ_VECTOR);
        bd_data->irq_entry[FPGA_RECONFIG_IRQ_VECTOR].vector = vector;
        ret_val = request_irq(vector, reconfig_isr, 0, COYOTE_DRIVER_NAME, bd_data->reconfig_dev);

        if (ret_val) {
            pr_err("couldn't use reconfiguration IRQ#%d, ret=%d\n", vector, ret_val);
            goto err_reconfig;
        }

        dbg_info("using IRQ#%d with reconfiguration device\n", vector);

        // Write the MSI-X vectors to the XDMA configuration registers
        // Should only happen once, when the bitstream is first loaded
        write_msix_vectors(bd_data);
    }

    return ret_val;

err_reconfig:
    for (i = 0; i < bd_data->n_fpga_reg; i++) { free_irq(bd_data->irq_entry[i].vector, &bd_data->vfpga_dev[i]); }
    return ret_val;

err_user:
    while (--i >= 0) { free_irq(bd_data->irq_entry[i].vector, &bd_data->vfpga_dev[i]); }
    return ret_val;
}

void irq_teardown(struct bus_driver_data *bd_data, bool enable_reconfig_irq) {
    BUG_ON(!bd_data);

    for (int i = 0; i < bd_data->n_fpga_reg; i++) {
        dbg_info("releasing user IRQ%d\n", bd_data->irq_entry[i].vector);
        free_irq(bd_data->irq_entry[i].vector, &bd_data->vfpga_dev[i]);
    }
        
    if (enable_reconfig_irq) {
        dbg_info("releasing reconfiguration IRQ%d\n", bd_data->irq_entry[FPGA_RECONFIG_IRQ_VECTOR].vector);
        free_irq(bd_data->irq_entry[FPGA_RECONFIG_IRQ_VECTOR].vector, bd_data->reconfig_dev);
    }
}

int pci_check_msix(struct bus_driver_data *bd_data, struct pci_dev *pdev) {
    BUG_ON(!bd_data);
    BUG_ON(!pdev);

    int ret_val = 0;
    const int req_nvec = MAX_NUM_ENGINES + MAX_USER_IRQS;

    // Check if MSI-X is enabled on the target system
    if (msix_capable(pdev)) {
        dbg_info("enabling MSI-X\n");

        for (int i = 0; i < req_nvec; i++) {
            bd_data->irq_entry[i].entry = i;
        }

        // Allocate MSI-X vectors which can later be used for vFPGA devices and reconfiguration (irq_setup function)  
        ret_val = pci_alloc_irq_vectors(pdev, req_nvec, req_nvec, PCI_IRQ_MSIX);

        if (ret_val < 0) {
            pr_warn("could not enable MSI-X mode, ret %d\n", ret_val);
            bd_data->msix_enabled = 0;
            return ret_val;
        } else {
            dbg_info("allocated %d MSI-X IRQ vectors\n", ret_val);
            bd_data->msix_enabled = 1;
            return 0;
        }
    } else {
        pr_warn("MSI-X not present\n");
        bd_data->msix_enabled = 0;
        return -1;
    }
}

uint32_t get_engine_channel_id(struct xdma_engine_regs *regs) {
    BUG_ON(!regs);
    uint32_t val = ioread32(&regs->id);
    return (val & 0x00000f00U) >> 8;
}

uint32_t get_engine_id(struct xdma_engine_regs *regs) {
    BUG_ON(!regs);
    uint32_t val = ioread32(&regs->id);
    return (val & 0xffff0000U) >> 16;
}

void read_engine_alignments(struct xdma_engine *engine) {
    uint32_t val = ioread32(&engine->regs->alignments);
    dbg_info(
        "engine %p name %s alignments=0x%08x\n", 
        engine, engine->name, (int) val 
    );

    uint32_t align_bytes = (val & 0x00ff0000U) >> 16;
    uint32_t granularity_bytes = (val & 0x0000ff00U) >> 8;
    uint32_t address_bits = (val & 0x000000ffU);

    if (val) {
        engine->addr_align = align_bytes;
        engine->len_granularity = granularity_bytes;
        engine->addr_bits = address_bits;
    }
    else {
        // Fall-back to default, if register cannot be read
        engine->addr_align = 1;
        engine->len_granularity = 1;
        engine->addr_bits = 64;
    }
}

struct xdma_engine *engine_create(struct bus_driver_data *bd_data, int offset, int c2h, int channel) {
    struct xdma_engine *engine;
    
    // Allocate memory for engine struct
    engine = kzalloc(sizeof(struct xdma_engine), GFP_KERNEL);
    if (!engine) { return NULL; }

    // Engine metadata
    engine->channel = channel;
    engine->name = c2h ? "c2h" : "h2c";

    // Devices associated with this engine (basically a pointer to Coyote bus bd_data)
    engine->bd_data = bd_data;

    // Direction: card-to-host or host-to-card
    engine->c2h = c2h;

    // Address of the registers for this engine; see XDMA specification [PG195 (v4.1)]
    engine->regs = (bd_data->bar[BAR_DMA_CONFIG] + offset);
    engine->sgdma_regs = (bd_data->bar[BAR_DMA_CONFIG] + offset + SGDMA_OFFSET_FROM_CHANNEL);

    // Enabled incremental mode
    iowrite32(!XDMA_CTRL_NON_INCR_ADDR, &engine->regs->ctrl_w1c);

    // Set the aligments by reading the alignments register
    read_engine_alignments(engine);

    // (Re)start the engine by setting and clearing registers, defined in Table 42 of XDMA specification [PG195 (v4.1)]
    uint32_t reg_val = 0;
    reg_val |= XDMA_CTRL_IE_DESC_STOPPED;
    reg_val |= XDMA_CTRL_IE_DESC_COMPLETED;
    reg_val |= XDMA_CTRL_RUN_STOP;
    iowrite32(reg_val, &engine->regs->ctrl);
    reg_val = ioread32(&engine->regs->status);
    dbg_info("ioread32(0x%p) = 0x%08x (dummy read flushes writes).\n", &engine->regs->status, reg_val);

    engine->running = 1;
    return engine;
}

int probe_for_engine(struct bus_driver_data *bd_data, int c2h, int channel) {
    // Offset derived from Table 38 of the XDMA specification [PG195 (v4.1)]
    int offset = (c2h * C2H_CHAN_OFFS) + (channel * CHAN_RANGE);
    struct xdma_engine_regs *regs = bd_data->bar[BAR_DMA_CONFIG] + offset;

    // The expected ID comes from the XDMA specification [PG195 (v4.1)]
    // In particular, Table 41 for H2C engines and Table 60 for C2H engines; bits 31:16
    uint32_t engine_id_expected;
    if (c2h) {
        dbg_info("probing for c2h engine %d at %p\n", channel, regs);
        engine_id_expected = XDMA_ID_C2H;
    } else {
        dbg_info("probing for h2c engine %d at %p\n", channel, regs);
        engine_id_expected = XDMA_ID_H2C;
    }

    // Some basic sanity checks, to make sure the registers read match the expected values
    // If not, this enigne is skipped and the error will be caught downstream (by having less engines than expected)
    uint32_t engine_id = get_engine_id(regs);
    uint32_t channel_id = get_engine_channel_id(regs);
    if (engine_id != engine_id_expected) {
        pr_warn("incorrect engine ID, skipping...\n");
        return 0;
    }

    if (channel_id != channel) {
        pr_warn("expected channel ID %d, read %d\n", channel, channel_id);
        return 0;
    }

    dbg_info("engine ID = 0x%x, channel ID = %d\n", engine_id, channel_id);

    // Create and set-up the engine
    if (c2h) { 
        dbg_info("found c2h %d engine at %p\n", channel, regs);
        struct xdma_engine *tmp_engine = engine_create(bd_data, offset, c2h, channel);
        if (!tmp_engine) {
            pr_err("error creating channel engine\n");
            return -1;
        }
        bd_data->engine_c2h[channel] = tmp_engine;
        bd_data->engines_num++;
    } else { 
        dbg_info("found h2c %d engine at %p\n", channel, regs);
        struct xdma_engine *tmp_engine = engine_create(bd_data, offset, c2h, channel);
        if (!tmp_engine) {
            pr_err("error creating channel engine\n");
            return -1;
        }
        bd_data->engine_h2c[channel] = tmp_engine;
        bd_data->engines_num++;
    }

    return 0;
}

int probe_engines(struct bus_driver_data *bd_data) {
    BUG_ON(!bd_data);
    int ret_val = 0;

    // Probe for H2C (host-to-card) engines (pass 0 to probe_for_engine)
    for (int channel = 0; channel < MAX_NUM_CHANNELS; channel++) {
        ret_val = probe_for_engine(bd_data, 0, channel); 
        if (ret_val) { goto fail; }
    }

    // Probe for C2H (card-to-host) engines (pass 1 to probe_for_engine)
    for (int channel = 0; channel < MAX_NUM_CHANNELS; channel++) {
        ret_val = probe_for_engine(bd_data, 1, channel); 
        if (ret_val) { goto fail; }
    }

    if (bd_data->engines_num < 2 * bd_data->n_fpga_chan) {
        pr_err("failed to detect all required c2h or h2c engines\n");
        return -ENODEV;
    }

    dbg_info("found %d engines\n", bd_data->engines_num);
    goto success;

fail:
    pr_err("engine probing failed, unwinding\n");
    remove_engines(bd_data);
    return -1;

success:
    return ret_val;
}

void engine_destroy(struct bus_driver_data *bd_data, struct xdma_engine *engine) {
    BUG_ON(!bd_data);
    BUG_ON(!engine);
    
    // Write to the control register for this engine; see Table 42 of the XDMA specification [PG195 (v4.1)]
    iowrite32(0x0, &engine->regs->ctrl);
    engine->running = 0;

    // Release the dynamically allocated memory for this engine
    kfree(engine);

    bd_data->engines_num--;
}

void remove_engines(struct bus_driver_data *bd_data) {
    BUG_ON(!bd_data);

    for (int i = 0; i < bd_data->n_fpga_chan; i++) {
        struct xdma_engine *engine = bd_data->engine_h2c[i];
        if (engine) {
            dbg_info("remove engine name %s, channel %d\n", engine->name, engine->channel);
            engine_destroy(bd_data, engine);
        }

        engine = bd_data->engine_c2h[i];
        if (engine) {
            dbg_info("remove engine name %s, channel %d\n", engine->name, engine->channel);
            engine_destroy(bd_data, engine);
        }
    }
}

int map_single_bar(struct bus_driver_data *bd_data, struct pci_dev *pdev, int idx, int curr_idx) {
    resource_size_t bar_start = pci_resource_start(pdev, idx);
    resource_size_t bar_len = pci_resource_len(pdev, idx);
    resource_size_t map_len = bar_len;
    bd_data->bar[curr_idx] = NULL;

    // Error checking
    if (!bar_len) {
        dbg_info("BAR%d is not present\n", idx);
        return 0;
    }

    if (bar_len > INT_MAX) {
        pr_warn("BAR %d limited from %llu to %d bytes\n", idx, (u64) bar_len, INT_MAX);
        map_len = (resource_size_t) INT_MAX;
    }

    // Map the BAR to the kernel address space
    dbg_info("mapping BAR %d, %llu bytes to be mapped", idx, (u64) map_len);
    bd_data->bar[curr_idx] = pci_iomap(pdev, idx, map_len);

    if (!bd_data->bar[curr_idx]) {
        dev_err(&pdev->dev, "could not map BAR%d\n", idx);
        return -1;
    }

    dbg_info(
        "BAR%d at 0x%llx mapped at 0x%p, length=%llu, (%llu)\n",
        idx, (u64) bar_start, bd_data->bar[curr_idx], (u64) map_len, (u64) bar_len
    );

    // Populate metadata in the bus driver bd_data structure
    bd_data->bar_phys_addr[curr_idx] = bar_start;
    bd_data->bar_len[curr_idx] = map_len;

    return (int) map_len;
}

int map_bars(struct bus_driver_data *bd_data, struct pci_dev *pdev) {
    // Iterate through bars and map them
    int i = 0;
    int curr_idx = 0;
    
    while ((curr_idx < CYT_BARS) && (i < MAX_NUM_BARS)) {
        int bar_len = map_single_bar(bd_data, pdev, i++, curr_idx);
        if (bar_len == 0) {
            continue;
        } else if (bar_len < 0) {
            goto fail;
        }
        curr_idx++;
    }
    goto success;
fail:
    pr_err("mapping of the bars failed\n");
    unmap_bars(bd_data, pdev);
    return -1;
success:
    return 0;
}

void unmap_bars(struct bus_driver_data *bd_data, struct pci_dev *pdev) {
    for (int i = 0; i < CYT_BARS; i++) {
        if (bd_data->bar[i]) {
            pci_iounmap(pdev, bd_data->bar[i]);
            bd_data->bar[i] = NULL;
            dbg_info("BAR%d unmapped\n", i);
        }
    }
}

int shell_pci_init(struct bus_driver_data *bd_data) {
    int ret_val = 0;
    dbg_info("initializing shell ...\n");

    // Obtain dynamic major and minor numbers for the FPGA device
    dev_t dev_vfpga = MKDEV(bd_data->vfpga_major, 0);

    // Read shell config
    ret_val = read_shell_config(bd_data);
    if (ret_val) {
        pr_err("cannot read static config\n");
        goto err_read_shell_cnfg;
    }

    // Create sysfs entry
    ret_val = create_sysfs_entry(bd_data);
    if (ret_val) {
        pr_err("cannot create a sysfs entry\n");
        goto err_sysfs;
    }

    // Allocate card memory resources
    ret_val = allocate_card_resources(bd_data);
    if (ret_val) {
        pr_err("card resources could not be allocated\n");
        goto err_card_alloc;
    }

    // Create vFPGA devices and register major number
    ret_val = alloc_vfpga_devices(bd_data, dev_vfpga);
    if (ret_val) {
        goto err_create_fpga_dev;
    }

    // Set-up the above-created vFPGAs 
    ret_val = setup_vfpga_devices(bd_data);
    if (ret_val) {
        goto err_init_fpga_dev;
    }

    // Set-up vFPGAs IRQs
    ret_val = irq_setup(bd_data, bd_data->pci_dev, false);
    if (ret_val) {
        pr_err("IRQ setup error\n");
        goto err_irq;
    }
    vfpga_interrupts_enable(bd_data);
    read_interrupts(bd_data);

    if (ret_val == 0) { goto end; }

err_irq:
    teardown_vfpga_devices(bd_data);
err_init_fpga_dev:
    free_vfpga_devices(bd_data);
err_create_fpga_dev:
    free_card_resources(bd_data);
err_card_alloc:
    remove_sysfs_entry(bd_data);
err_sysfs:
err_read_shell_cnfg:
end:
    dbg_info("shell load returning %d\n", ret_val);
    return ret_val;
}

void shell_pci_remove(struct bus_driver_data *bd_data) {
    dbg_info("removing shell...\n");

    // Free HMM chunks
    #ifdef HMM_KERNEL    
        free_mem_regions(bd_data);
        dbg_info("freed svm private pages");
    #endif

    // Disable and remove vFPGA interrupts
    vfpga_interrupts_disable(bd_data);
    irq_teardown(bd_data, false);
    dbg_info("vfpga interrupts disabled\n");

    // Clear and release vFPGAs devices
    teardown_vfpga_devices(bd_data);
    free_vfpga_devices(bd_data);
    dbg_info("vfpga devices released\n");

    // Deallocate card memory resources
    free_card_resources(bd_data);
    dbg_info("card memory resources released\n");

    // Remove sysfs entry
    remove_sysfs_entry(bd_data);
    dbg_info("sysfs removed\n");

    dbg_info("shell removed\n");
}

int pci_probe(struct pci_dev *pdev, const struct pci_device_id *id) {
    int ret_val = 0;
    dbg_info("probe (pdev = 0x%p, pci_id = 0x%p)\n", pdev, id);

    // Allocate memory for the device instance
    struct bus_driver_data *bd_data = devm_kzalloc(&pdev->dev, sizeof(struct bus_driver_data), GFP_KERNEL);
    if (!bd_data) {
        dev_err(&pdev->dev, "device memory region not obtained\n");
        goto err_alloc;
    }

    // Set device private bd_data; so that we can access it later (both the PCI device and the bus driver bd_data)
    bd_data->pci_dev = pdev;
    dev_set_drvdata(&pdev->dev, bd_data);

    // Obtain a (dynamic) major and minor number for the vFPGA device and reconfig device
    bd_data->vfpga_major = VFPGA_DEV_MAJOR;
    bd_data->reconfig_major = RECONFIG_DEV_MAJOR;
    dev_t dev_vfpga = MKDEV(bd_data->vfpga_major, 0);
    dev_t dev_reconfig = MKDEV(bd_data->reconfig_major, 0);

    // Enable PCIe device
    ret_val = pci_enable_device(pdev);
    if (ret_val) {
        dev_err(&pdev->dev, "pci device could not be enabled\n");
        goto err_enable;
    }
    dbg_info("pci device node %p enabled\n", &pdev->dev);

    // Set unique ID for this FPGA card
    assign_device_id(bd_data);
    
    // PCI capabilities and properties
	pci_enable_capability(pdev, PCI_EXP_DEVCTL_RELAX_EN);
	pci_enable_capability(pdev, PCI_EXP_DEVCTL_EXT_TAG);
	pcie_set_readrq(pdev, 512);
    pci_set_master(pdev);

    // Check MSI-X is supported
    ret_val = pci_check_msix(bd_data, pdev);
    if (ret_val < 0) {
        dev_err(&pdev->dev, "pci IRQ error\n");
        goto err_irq_en;
    }

    // Request PCI regions
    ret_val = pci_request_regions(pdev, COYOTE_DRIVER_NAME);
    if (ret_val) {
        bd_data->got_regions = 0;
        bd_data->regions_in_use = 1;
        dev_err(&pdev->dev, "device in use, pci regions could not be obtained\n");
        goto err_regions;
    } else {
        bd_data->got_regions = 1;
        bd_data->regions_in_use = 0;
        dbg_info("pci regions obtained\n");
    }

    // BAR mapping
    ret_val = map_bars(bd_data, pdev);
    if (ret_val) {
        dev_err(&pdev->dev, "mapping of the BARs failed\n");
        goto err_map; // ERR_MAP
    }

    // DMA addressing
    dbg_info("sizeof(dma_addr_t) == %ld\n", sizeof(dma_addr_t));
    ret_val = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(64));
    if (ret_val) {
        dev_err(&pdev->dev, "failed to set 64b DMA mask\n");
        goto err_mask;
    }

    // Probe and initialize XDMA engines
    ret_val = probe_engines(bd_data);
    if (ret_val) {
        dev_err(&pdev->dev, "error whilst probing DMA engines\n");
        goto err_engines;
    }

    // Initialize spin locks
    init_spin_locks(bd_data);

    // Memory map XDMA configuration registers into the kernel space
    bd_data->stat_cnfg = ioremap(bd_data->bar_phys_addr[BAR_STAT_CONFIG] + FPGA_STAT_CNFG_OFFS, FPGA_STAT_CNFG_SIZE);
    bd_data->shell_cnfg = ioremap(bd_data->bar_phys_addr[BAR_SHELL_CONFIG] + FPGA_SHELL_CNFG_OFFS, FPGA_SHELL_CNFG_SIZE);

    // Read shell config
    ret_val = read_shell_config(bd_data);
    if(ret_val) {
        dev_err(&pdev->dev, "cannot read shell config\n");
        goto err_read_shell_cnfg;
    }

    // Create sysfs entry
    ret_val = create_sysfs_entry(bd_data);
    if (ret_val) {
        dev_err(&pdev->dev, "cannot create a sysfs entry\n");
        goto err_sysfs;
    }

    // Allocate card memory resources
    ret_val = allocate_card_resources(bd_data);
    if (ret_val) {
        dev_err(&pdev->dev, "card memory resources could not be allocated\n");
        goto err_card_alloc; 
    }

    // Create reconfig device and register major
    ret_val = alloc_reconfig_device(bd_data, dev_reconfig);
    if (ret_val) {
        dev_err(&pdev->dev, "could not allocate reconfig device\n");
        goto err_create_reconfig_dev; 
    }

    // Set-up reconfig device
    ret_val = setup_reconfig_device(bd_data);
    if (ret_val) {
        dev_err(&pdev->dev, "could not set-up reconfig device\n");
        goto err_init_reconfig_dev;
    }

    // Create vFPGA devices and register major
    ret_val = alloc_vfpga_devices(bd_data, dev_vfpga);
    if (ret_val) {
        dev_err(&pdev->dev, "could not allocate vfpga devices\n");
        goto err_create_fpga_dev; 
    }

    // Set-up vFPGA devices
    ret_val = setup_vfpga_devices(bd_data);
    if (ret_val) {
        dev_err(&pdev->dev, "could not set-up vfpga devices\n");
        goto err_init_fpga_dev;
    }

    // Set-up IRQs
    ret_val = irq_setup(bd_data, pdev, true);
    if (ret_val) {
        dev_err(&pdev->dev, "IRQ setup error\n");
        goto err_irq;
    }
    reconfig_interrupt_enable(bd_data);
    vfpga_interrupts_enable(bd_data);
    read_interrupts(bd_data);

    if (ret_val == 0)
        goto end;

err_irq:
    teardown_vfpga_devices(bd_data);
err_init_fpga_dev:
    free_vfpga_devices(bd_data);
err_create_fpga_dev:
    teardown_reconfig_device(bd_data);
err_init_reconfig_dev:
    free_reconfig_device(bd_data);
err_create_reconfig_dev:
    free_card_resources(bd_data);
err_card_alloc:
    remove_sysfs_entry(bd_data);
err_sysfs:
err_read_shell_cnfg:
    remove_engines(bd_data);
err_engines:
err_mask:
    unmap_bars(bd_data, pdev);
err_map:
    if (bd_data->got_regions) { pci_release_regions(pdev); }
err_regions:
    if (bd_data->msix_enabled) { pci_disable_msix(pdev); }
err_irq_en:
    if (!bd_data->regions_in_use) { pci_disable_device(pdev); }
err_enable:
    kfree(bd_data);
err_alloc:
end:
    dbg_info("probe returning %d\n", ret_val);
    return ret_val;
}

void pci_remove(struct pci_dev *pdev) {
    struct bus_driver_data *bd_data = (struct bus_driver_data *) dev_get_drvdata(&pdev->dev);

    // Free HMM chunks
    #ifdef HMM_KERNEL    
        free_mem_regions(bd_data);
        dbg_info("freed svm private pages");
    #endif

    // Disable and remove interrupts
    vfpga_interrupts_disable(bd_data);
    reconfig_interrupt_disable(bd_data);
    irq_teardown(bd_data, true);
    dbg_info("interrupts disabled\n");

    // Clear and release vFPGA devices 
    teardown_vfpga_devices(bd_data);
    free_vfpga_devices(bd_data);
    dbg_info("vfpga devices released\n");

    // Clear and release reconfiguration device
    teardown_reconfig_device(bd_data);
    free_reconfig_device(bd_data);
    dbg_info("reconfig device released\n");

    // Deallocate card resources
    free_card_resources(bd_data);
    dbg_info("card memory resources released\n");

    // Remove sysfs entry
    remove_sysfs_entry(bd_data);
    dbg_info("sysfs remove\n");

    // Remove XDMA engines
    remove_engines(bd_data);
    dbg_info("engines removed\n");

    // Unmap XDMA BARs
    unmap_bars(bd_data, pdev);
    dbg_info("BARs unmapped\n");

    // Release regions
    if (bd_data->got_regions) {
        pci_release_regions(pdev);
        dbg_info("pci regions released\n");
    }

    // Disable interrupts
    if (bd_data->msix_enabled) {
        pci_disable_msix(pdev);
        dbg_info("MSI-X disabled\n");
    }

    // Disable device
    if (!bd_data->regions_in_use) {
        pci_disable_device(pdev);
        dbg_info("pci device disabled\n");
    }

    // Release device bd_data memory
    devm_kfree(&pdev->dev, bd_data);
    dbg_info("device memory freed\n");

    dbg_info("removal completed\n");
}

// List of devices which can be used with the Coyote driver
// 0x10ee is the vendor ID for AMD/Xilinx FPGAs, while the other number represents the device ID
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

// Define the entry and exit point for the PCI driver, 
// Simply pointing to the probe and remove functions; as well as the list of supported devices
static struct pci_driver pci_driver = {
    .name = COYOTE_DRIVER_NAME,
    .id_table = pci_ids,
    .probe = pci_probe,
    .remove = pci_remove,
};

int pci_init(void) {
    int ret_val = pci_register_driver(&pci_driver);
    if (ret_val) {
        pr_err("failed to regiser coyote pci driver, ret_val %d\n", ret_val);
        return ret_val;
    }

    return 0;
}

void pci_exit(void) {
    pci_unregister_driver(&pci_driver);
}
