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

#include "pci_qdma.h"

static uint32_t current_device = 0;

void assign_device_id(struct bus_driver_data *bd_data) {
    bd_data->dev_id = current_device++;
    dbg_info("fpga device id %d, pci bus %02x, pci slot %02x\n", bd_data->dev_id, bd_data->pci_dev->bus->number, PCI_SLOT(bd_data->pci_dev->devfn));
    sprintf(bd_data->vfpga_dev_name, "%s_%d", DEV_FPGA_NAME, bd_data->dev_id);
    sprintf(bd_data->reconfig_dev_name, "%s_reconfig", bd_data->vfpga_dev_name);
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

    const int req_nvec = QDMA_N_MAX_IRQ;

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
        "BAR%d at 0x%llx mapped at 0x%llx, length=%llu, (%llu)\n",
        idx, (u64) bar_start, (u64) bd_data->bar[curr_idx], (u64) map_len, (u64) bar_len
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

void qdma_init_reg_layout(struct bus_driver_data *bd_data) {
    struct qdma_reg_layout *q = &bd_data->qreg;
    uint32_t misc_cap, dev_id;

    // GLBL2_MISC_CAP (0x134) is at the same offset on CPM4 and CPM5; bits[31:28] encode
    // the device type: 1 = Versal CPM4, 2 = Versal CPM5. (AMD dma_ip_drivers,
    // qdma_access_common.c qdma_fetch_version_details / qdma_soft_reg.h.)
    misc_cap = ioread32(bd_data->bar[BAR_DMA_CONFIG] + QDMA_GLBL2_MISC_CAP_REG);
    dev_id = (misc_cap >> QDMA_GLBL2_DEVICE_ID_SHIFT) & QDMA_GLBL2_DEVICE_ID_MASK;

    if (dev_id == QDMA_DEV_ID_CPM4) {
        q->dev_type            = QDMA_DEV_TYPE_CPM4;
        q->ctx_cmd_reg         = QDMA_CPM4_CTX_CMD_REG;
        q->ctx_data_reg_start  = QDMA_CPM4_CTX_DATA_REG_START;
        q->ctx_mask_reg_start  = QDMA_CPM4_CTX_MASK_REG_START;
        q->ctx_n_data_regs     = QDMA_CPM4_CTX_N_DATA_REGS;
        q->has_host_profile    = false;   // host profile is eQDMA/CPM5-only
        q->has_pfch_bypass     = true;    // ARM the per-queue prefetch slot via 0x1408/0x140c: in
                                          // SIMPLE mode the arming binds the queue to a slot (enables
                                          // ring fetch); the slot recycles via the byp_out->byp_in
                                          // pairing in the shim (PG347 simple-bypass procedure).
        q->c2h_simple_bypass   = true;    // prefetch-ctx bypass bit = 1 (SIMPLE) -> byp_in_st_sim,
                                          // matching the v4 pairing bitstream. Manual recipe: arm tag
                                          // + descriptor loopback (byp_out consumed, byp_in returns
                                          // the FPGA-addressed descriptor).
        q->fmap_indirect       = false;   // CPM4 FMAP = direct register 0x400 + func*4
        q->cmpt_valid_word     = QDMA_CPM4_CMPT_VALID_WORD;
        q->cmpt_valid_mask     = QDMA_CPM4_CMPT_VALID_MASK;
        pr_info("QDMA device: Versal CPM4 (GLBL2_MISC_CAP=0x%08x); using CPM4 register layout\n", misc_cap);
    } else {
        // Default to CPM5/eQDMA (dev_id == 2, and any unexpected value) -- matches the
        // historical Coyote/V80 behaviour.
        q->dev_type            = QDMA_DEV_TYPE_CPM5;
        q->ctx_cmd_reg         = QDMA_CPM5_CTX_CMD_REG;
        q->ctx_data_reg_start  = QDMA_CPM5_CTX_DATA_REG_START;
        q->ctx_mask_reg_start  = QDMA_CPM5_CTX_MASK_REG_START;
        q->ctx_n_data_regs     = QDMA_CPM5_CTX_N_DATA_REGS;
        q->has_host_profile    = true;
        q->has_pfch_bypass     = true;
        q->c2h_simple_bypass   = true;    // CPM5/eQDMA: simple bypass (SW pfch-tag) -- V80 behaviour
        q->fmap_indirect       = true;
        q->cmpt_valid_word     = QDMA_CPM5_CMPT_VALID_WORD;
        q->cmpt_valid_mask     = QDMA_CPM5_CMPT_VALID_MASK;
        if (dev_id != QDMA_DEV_ID_CPM5)
            pr_warn("QDMA device id %u unrecognised (GLBL2_MISC_CAP=0x%08x); defaulting to CPM5/eQDMA layout\n", dev_id, misc_cap);
        else
            pr_info("QDMA device: Versal CPM5/eQDMA (GLBL2_MISC_CAP=0x%08x); using eQDMA register layout\n", misc_cap);
    }
}

int wait_until_busy_cleared(struct bus_driver_data *bd_data) {
    int busy;
    uint32_t raw;
    // Bounded poll: if the QDMA config BAR (BAR2) is unreachable, reads return
    // 0xffffffff, so (raw & 0x1) is permanently 1 -> this used to spin forever and
    // wedge insmod in D-state. Time out instead so probe fails gracefully. Seen on
    // the VCK5000 CPM4 bring-up: BAR2 reads all-1s (QDMA CSRs not decoding there).
    int tries = 0;
    do {
        usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);
        raw = ioread32(bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_cmd_reg);
        busy = raw & 0x1;
        if (raw == 0xffffffff) {
            pr_err("QDMA ctx-cmd reg (BAR2+0x%x) reads 0xffffffff -- QDMA config BAR "
                   "not accessible; aborting queue setup\n", bd_data->qreg.ctx_cmd_reg);
            return -EIO;
        }
        if (++tries > QDMA_CTX_BUSY_MAX_TRIES) {
            pr_err("QDMA ctx-cmd busy bit never cleared after %d tries (last=0x%08x)\n",
                   tries, raw);
            return -ETIMEDOUT;
        }
    } while (busy);
    return 0;
}

int clear_ctx_reg(struct bus_driver_data *bd_data, int32_t qid, int32_t sel) {
    // Issue clear operation
    int32_t reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
                      ((sel & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
                      ((QDMA_CTX_CLR & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
                      ((qid & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
    iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_cmd_reg);
    wmb();
    return wait_until_busy_cleared(bd_data);
}

void invalidate_ctx_reg(struct bus_driver_data *bd_data, int32_t qid, int32_t sel) {
    // Issue invalidate operation
    int32_t reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
                      ((sel & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
                      ((QDMA_CTX_INV & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
                      ((qid & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
    iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_cmd_reg);
    wmb();
    wait_until_busy_cleared(bd_data);
}

int enable_queue(struct bus_driver_data *bd_data, int32_t qid, bool c2h, bool is_mm, uint32_t mm_chn) {
    // Initialize the queue struct
    dbg_info("creating queue with qid %d, c2h %d, is_mm %d, mm_chn %d\n", qid, c2h, is_mm, mm_chn);
    
    // Memory-mapped queues are only used for PR; i.e. to deliver partial image data from host to PMC (card)
    // Therefore, the static layer ties off the opposite (C2H) direction; if enabling for some reason,
    // ensure hardware has been modified accordingly. Additionally, ensure the C2H MM engine is enabled (QDMA_C2H_MM_CTRL_REG)
    if (is_mm && c2h) {
        pr_warn(
            "creating C2H queue in MM mode, but Coyote ties off C2H MM descriptors by default; ensure hardware in cr_pci.tcl was modified to support C2H MM."
        );
    }

    // Similarly, Coyote only relies on MM channel 0 and ties off MM interfaces to channel 1.
    // If using channel 1, ensure HW has been modified accordingly.
    if (is_mm && (mm_chn == 1)) {
        pr_warn(
            "creating queue in MM mode with mm_chn = 1, but Coyote ties off MM channel 1 descriptors by default; ensure hardware in cr_pci.tcl was modified to support C2H MM."
        );
    }

    struct qdma_queue *tmp_queue = kzalloc(sizeof(struct qdma_queue), GFP_KERNEL);
    if (!tmp_queue) { 
        pr_err("error allocating queue struct\n");
        return -1;
    }
    tmp_queue->qid = qid;
    tmp_queue->c2h = c2h;
    tmp_queue->is_mm = is_mm;
    tmp_queue->mm_chn = mm_chn;
    tmp_queue->running = false;
    tmp_queue->c2h_ring_vaddr = NULL;

    // CPM4 C2H: allocate the credit ring (content unused -> zeroed; provides per-packet
    // descriptor-fetch credits which CPM4 requires even in simple bypass) and the CMPT
    // (completion) host ring -- the engine writes one 8B record per packet there (the
    // silicon-validated completion mechanism); the driver only advances CIDX.
    if (c2h && bd_data->qreg.dev_type == QDMA_DEV_TYPE_CPM4) {
        tmp_queue->c2h_ring_vaddr = dma_alloc_coherent(&bd_data->pci_dev->dev,
                QDMA_CPM4_C2H_RING_BYTES, &tmp_queue->c2h_ring_paddr, GFP_KERNEL);
        if (!tmp_queue->c2h_ring_vaddr) {
            pr_err("failed to allocate C2H credit ring for qid %d\n", qid);
            kfree(tmp_queue);
            return -ENOMEM;
        }
        tmp_queue->cmpt_ring_vaddr = dma_alloc_coherent(&bd_data->pci_dev->dev,
                QDMA_CPM4_CMPT_RING_BYTES, &tmp_queue->cmpt_ring_paddr, GFP_KERNEL);
        if (!tmp_queue->cmpt_ring_vaddr) {
            pr_err("failed to allocate CMPT ring for qid %d\n", qid);
            dma_free_coherent(&bd_data->pci_dev->dev, QDMA_CPM4_C2H_RING_BYTES,
                              tmp_queue->c2h_ring_vaddr, tmp_queue->c2h_ring_paddr);
            kfree(tmp_queue);
            return -ENOMEM;
        }
    }
    
    // Clear any previous contexts
    dbg_info("clearing SW, HW, credit contexts for qid %d", qid);
    // Abort cleanly if the QDMA config BAR is unreachable (busy bit never clears /
    // reads 0xffffffff) rather than proceeding with a broken queue setup.
    if (clear_ctx_reg(bd_data, qid, QDMA_CTXT_SELC_DEC_SW_C2H) ||
        clear_ctx_reg(bd_data, qid, QDMA_CTXT_SELC_DEC_SW_H2C) ||
        clear_ctx_reg(bd_data, qid, QDMA_CTXT_SELC_DEC_HW_C2H) ||
        clear_ctx_reg(bd_data, qid, QDMA_CTXT_SELC_DEC_HW_H2C) ||
        clear_ctx_reg(bd_data, qid, QDMA_CTXT_SELC_DEC_CR_C2H) ||
        clear_ctx_reg(bd_data, qid, QDMA_CTXT_SELC_DEC_CR_H2C)) {
        pr_err("failed to clear QDMA contexts for qid %d (QDMA config BAR unreachable?)\n", qid);
        kfree(tmp_queue);
        return -EIO;
    }

    // Initialize the register mask to all 1s, as specified in the docs
    for (int i = 0; i < bd_data->qreg.ctx_n_data_regs; i++) {
        iowrite32(QDMA_CXT_MASK_DEF_VAL, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_mask_reg_start + i * 4);
        wmb();
    }
    usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);

    // Set-up descriptor SW context, based on Table 120 from QDMA specification from PG347 (v3.4) 
    // In the first 32 bits, we want to set function ID to 0 (only one PF) and disable interrupts by setting irq_arm to 0
    // Other bits don't matter to much, set to zero ---> hence, entire reg is zero.
    iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start);
    wmb();

    // Set bits 32 - 63; in these bits we want to set qen to 1, which enables the queue
    // Additionally, want to set bit 50 to 1, corresponding to bypass mode.
    if (is_mm) {
        // Memory-mapped mode --> set bit 63 to 1
        if (mm_chn == 0) {
            // Memory-mapped channel 0 --> set bit 51 to 0
            iowrite32(0x80040001, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + 4);
        } else if (mm_chn == 1) {
            // Memory-mapped channel 1 --> set bit 51 to 1
            iowrite32(0x800C0001, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + 4);
        } else {
            pr_err("invalid memory-mapped channel %d for qid %d\n", mm_chn, qid);
            goto fail;
        }
    } else {
        // Streaming mode --> set bit 63 to 0
        iowrite32(0x00040001, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + 4);
    }
    wmb();

    // Words 2..N: on CPM4 C2H queues, words 2/3 carry the descriptor-ring base (the credit
    // ring -- see QDMA_CPM4_C2H_RING_* in coyote_defs.h). W1 rng_sz idx stays 0, pointing at
    // GLBL_RNG_SZ_1. Elsewhere (CPM5/eQDMA, or H2C) these words are reserved -> 0.
    if (tmp_queue->c2h_ring_vaddr) {
        iowrite32((uint32_t)(tmp_queue->c2h_ring_paddr & 0xFFFFFFFF),
                  bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + 2 * 4);
        wmb();
        iowrite32((uint32_t)(tmp_queue->c2h_ring_paddr >> 32),
                  bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + 3 * 4);
        wmb();
    } else {
        for (int i = 2; i < bd_data->qreg.ctx_n_data_regs; i++) {
            iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + i * 4);
            wmb();
        }
    }

    // Write the context for this queue
    int32_t reg_val;
    if (c2h) {
        reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
                ((QDMA_CTXT_SELC_DEC_SW_C2H & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
                ((QDMA_CTX_WR & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
                ((qid & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
    } else {
        reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
                ((QDMA_CTXT_SELC_DEC_SW_H2C & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
                ((QDMA_CTX_WR & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
                ((qid & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
    }
    iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_cmd_reg);
    wmb();
    wait_until_busy_cleared(bd_data);

    // Verify the queue is enabled by reading back the SOFTWARE context and checking qen
    // (SW context word[1] bit 0). This is the authoritative queue-enable bit and its
    // position is identical on CPM4 and CPM5 (AMD dma_ip_drivers, SW_IND_CTXT_DATA_W1_QEN_MASK
    // = BIT(0)). Previously this read the HARDWARE context idl_stp_b, which is a
    // descriptor-engine idle/stopped status, not a queue-enable flag.
    reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
            (((c2h ? QDMA_CTXT_SELC_DEC_SW_C2H : QDMA_CTXT_SELC_DEC_SW_H2C) & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
            ((QDMA_CTX_RD & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
            ((qid & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
    iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_cmd_reg);
    wmb();
    wait_until_busy_cleared(bd_data);

    // SW context word[1] bit 0 = qen
    reg_val = ioread32(bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + 4);
    int32_t qen = reg_val & 0x1;
    if (qen) {
        dbg_info("enabled software context for qid %d", qid);
    } else {
        pr_err("failed to enable software context for qid %d (qen=0, sw_ctxt[1]=0x%08x), releasing queue\n", qid, reg_val);
        goto fail;
    }
    
    // Clear prefetch and completion contexts, as per QDMA specification from PG347 (v3.4), p301
    dbg_info("clearing prefetch and completion contexts for qid %d", qid);
    clear_ctx_reg(bd_data, qid, QDMA_CTXT_SELC_PFTCH);
    clear_ctx_reg(bd_data, qid, QDMA_CTXT_SELC_WRB);

    // Set up prefetch context for C2H streams, per Table 128 in QDMA spec (PG347 v3.4).
    // Prefetch-context word0 bit0 = bypass: 1 = SIMPLE bypass (eQDMA/CPM5 -- fabric provides the
    // descriptor + a SW-queried pfch_tag from 0x1408/0x140c), 0 = CACHE bypass. CPM4 has no
    // pfch-tag query registers, so simple bypass is not programmable there; use cache bypass
    // (bit0=0). (AMD PG302 C2H Stream Modes.) qreg.c2h_simple_bypass encodes this per device.
    if (c2h) {
        // word0: bypass bit0 (device-dependent), port_id[7:5]=0, bufsz_idx[4:1]=0 -> selects
        // C2H_BUF_SZ_0 (0xAB0, programmed to PAGE_SIZE in enable_queues).
        // CPM4 cache mode additionally needs pfch_en (bit27) = 1: without it, data arriving
        // before its demand-fetched descriptor completes is DROPPED (HW-verified: DROP_ACC
        // incremented on the first packet). With pfch_en the engine prefetches ring
        // descriptors ahead of data using the posted PIDX credits.
        iowrite32(bd_data->qreg.c2h_simple_bypass ? 0x1 : 0x08000000,
                  bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start);
        wmb();

        // word1: valid = 1 (bit 13) -- required in both simple and cache bypass
        iowrite32(0x2000, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + 4);
        wmb();

        // Fire command to write the prefetch context
        reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
                ((QDMA_CTXT_SELC_PFTCH & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
                ((QDMA_CTX_WR & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
                ((qid & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
   
        iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_cmd_reg);
        wmb();
        wait_until_busy_cleared(bd_data);
        
        // Verify prefetch contex is indeed set to valid; first issue read command
        reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
            ((QDMA_CTXT_SELC_PFTCH & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
            ((QDMA_CTX_RD & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
            ((qid & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
        iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_cmd_reg);
        wmb();
        usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);

        // Then, read bit 45, corresponding to valid bit
        reg_val = ioread32(bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + 4);
        int32_t valid = (reg_val >> 13) & 0x1;
        if (valid) {
            dbg_info("C2H prefetch context set valid, qid %d", qid);
        } else {
            pr_err("C2H prefetch context could not be set valid, qid %d", qid);
            goto fail;
        }

        // For simple bypass mode with commands issued from the FPGA, each command needs
        // to have a prefetch_tag, as explained on 258 of QDMA specification from PG347 (v3.4)
        // This tag can be requested by writing the queue ID to the register QDMA_C2H_PFCH_BYP_QID (0x1408)
        // Then, it can be obtained by reading the register QDMA_C2H_PFCH_BYP_TAG (0x140C)
        // Finally, we send it to Coyote by writing to the memory-mapped registers of the static layer,
        // so that it can always be used for DMA requests. Bit 31 is set to 1 to indicate it's a valid tag
        //
        // NOTE: the prefetch-bypass QID/TAG registers (0x1408/0x140c) are eQDMA/CPM5-only;
        // they do not exist on CPM4 (AMD dma_ip_drivers: absent from qdma_cpm4_reg.h). On CPM4
        // the C2H simple-bypass prefetch-tag mechanism differs and needs separate bring-up, so
        // skip it here. TODO(vck5000/CPM4): implement CPM4 C2H bypass prefetch tag; until then,
        // C2H stream (card->host) bypass transfers are not expected to work on CPM4. H2C
        // (host->card) MM/stream is independent of this and should work.
        if (bd_data->qreg.has_pfch_bypass) {
            iowrite32(qid, bd_data->bar[BAR_DMA_CONFIG] + QDMA_C2H_PFCH_BYP_QID_REG);
            wmb();
            usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);
            int32_t pfch_tag_reg = ioread32(bd_data->bar[BAR_DMA_CONFIG] + QDMA_C2H_PFCH_BYP_TAG_REG);
            int32_t pfch_qid = ((pfch_tag_reg >> 8) & 0xFFF) - QDMA_WR_QUEUE_START_IDX; // bits 19:8 are the queue ID; substract starting WR queue index because the HW stores them 0, 1 in pfch_tags in qdma_wr_wrapper
            int32_t pfch_tag = pfch_tag_reg & 0x7F;                                     // bits 6:0 are the tag
            reg_val = (1 << 31) | (pfch_qid << 8) | pfch_tag;

            bd_data->stat_cnfg->qdma_pfch_tag = reg_val;
            wmb();
            usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);
            bd_data->stat_cnfg->qdma_pfch_tag = 0;  // Reset valid signal

            dbg_info("C2H prefetch tag for qid %d is %d", pfch_qid + QDMA_WR_QUEUE_START_IDX, pfch_tag);
        } else {
            pr_warn_once("CPM4: skipping C2H prefetch-bypass tag (regs absent); C2H bypass streaming needs CPM4-specific bring-up\n");
        }
    }

    // Completion (CMPT/WRB) context. Coyote never uses the QDMA completion engine: every C2H
    // packet is sent with has_cmpt=0 (dis_cmpt=1) and completion is detected fabric-side via
    // axis_c2h_status; Coyote's "writeback" counters are themselves plain has_cmpt=0 C2H writes.
    //
    //  - CPM4: leave the CMPT context CLEARED (it was cleared above). Writing VALID with a zero
    //    ring base would make any stray completion event DMA to host address 0; with the context
    //    invalid, a stray event flags WRB_INV_Q instead. Safer, and nothing consults the CMPT
    //    context for has_cmpt=0 traffic.
    //  - CPM5/eQDMA (V80): keep the historical Coyote behavior (VALID=1, dir_c2h for C2H queues)
    //    unchanged, as shipped and validated on that platform. (CPM5 = 6 words, VALID W3 BIT(28).)
    if (bd_data->qreg.dev_type != QDMA_DEV_TYPE_CPM4) {
        for (int i = 0; i < bd_data->qreg.ctx_n_data_regs; i++) {
            iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + i * 4);
            wmb();
        }

        // VALID bit (device-specific word/mask)
        iowrite32(bd_data->qreg.cmpt_valid_mask,
                  bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + bd_data->qreg.cmpt_valid_word * 4);
        wmb();

        // dir_c2h (bit 146 = word4 bit18) in the wider CPM5 CMPT context
        if (c2h) {
            iowrite32(0x40000, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + 16);
            wmb();
        }

        // Fire command to write completion context
        reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
                    ((QDMA_CTXT_SELC_WRB & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
                    ((QDMA_CTX_WR & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
                    ((qid & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);

        iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_cmd_reg);
        wmb();
        wait_until_busy_cleared(bd_data);
        dbg_info("enabled completion context for qid %d", qid);
    } else if (c2h && tmp_queue->cmpt_ring_vaddr) {
        // CPM4 with completions ENABLED (the silicon-validated flow): program a real CMPT
        // context pointing at this queue's host CMPT ring. Field layout per AMD dma_ip_drivers
        // qdma_cpm4_access (CMPL_CTXT_DATA_W0..W3): W0 = en_stat_desc | trig_mode=1 (EVERY) |
        // color=1 | qsize_idx=0 (GLBL_RNG_SZ_1=512) | baddr[9:6]<<28; W1 = baddr[41:10];
        // W2 = baddr[63:42] | desc_size=0 (8B); W3 = VALID (BIT24), pidx/cidx = 0.
        uint64_t cba = (uint64_t)tmp_queue->cmpt_ring_paddr;
        uint32_t w0 = (1u << 0)                              /* en_stat_desc */
                    | (1u << 2)                              /* trig_mode = 1 (every) */
                    | (1u << 23)                             /* color init 1 */
                    | ((uint32_t)((cba >> 6) & 0xF) << 28);  /* baddr[9:6] */
        uint32_t w1 = (uint32_t)((cba >> 10) & 0xFFFFFFFF);  /* baddr[41:10] */
        uint32_t w2 = (uint32_t)((cba >> 42) & 0x3FFFFF);    /* baddr[63:42]; desc_size=0; pidx_l=0 */
        uint32_t w3 = (1u << 24);                            /* VALID; pidx_h=0, cidx=0 */

        iowrite32(w0, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + 0 * 4); wmb();
        iowrite32(w1, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + 1 * 4); wmb();
        iowrite32(w2, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + 2 * 4); wmb();
        iowrite32(w3, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + 3 * 4); wmb();

        reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
                    ((QDMA_CTXT_SELC_WRB & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
                    ((QDMA_CTX_WR & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
                    ((qid & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
        iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_cmd_reg);
        wmb();
        wait_until_busy_cleared(bd_data);
        tmp_queue->cmpt_cidx = 0;
        dbg_info("CPM4: CMPT context programmed for qid %d (ring pa %pad)", qid, &tmp_queue->cmpt_ring_paddr);
    } else {
        dbg_info("CPM4: CMPT context left cleared for qid %d (H2C queue)", qid);
    }

    // CPM4 C2H: ring the PIDX doorbell to post the credit ring (after all contexts are set,
    // matching the reference sequence). PIDX = entries-1 -> 511 credits outstanding.
    if (tmp_queue->c2h_ring_vaddr) {
        tmp_queue->c2h_pidx = QDMA_CPM4_C2H_RING_ENTRIES - 1;
        iowrite32(tmp_queue->c2h_pidx,
                  bd_data->bar[BAR_DMA_CONFIG] + QDMA_CPM4_DMAP_C2H_DSC_PIDX_REG + qid * QDMA_CPM4_PIDX_STEP);
        wmb();
    }

    // Set-up complete, add to array of queues
    tmp_queue->running = true;
    bd_data->queues[bd_data->num_queues] = tmp_queue;
    bd_data->num_queues++;
    dbg_info("enabled queue %d", qid);
    return 0;

fail:
    if (c2h) {
        invalidate_ctx_reg(bd_data, qid, QDMA_CTXT_SELC_PFTCH);
        invalidate_ctx_reg(bd_data, qid, QDMA_CTXT_SELC_DEC_SW_C2H);
    } else {
        invalidate_ctx_reg(bd_data, qid, QDMA_CTXT_SELC_DEC_SW_H2C);
    }
    if (tmp_queue->c2h_ring_vaddr)
        dma_free_coherent(&bd_data->pci_dev->dev, QDMA_CPM4_C2H_RING_BYTES,
                          tmp_queue->c2h_ring_vaddr, tmp_queue->c2h_ring_paddr);
    if (tmp_queue->cmpt_ring_vaddr)
        dma_free_coherent(&bd_data->pci_dev->dev, QDMA_CPM4_CMPT_RING_BYTES,
                          tmp_queue->cmpt_ring_vaddr, tmp_queue->cmpt_ring_paddr);
    kfree(tmp_queue);
    return -1;
}

// CPM4 C2H credit replenish: each C2H packet consumes one ring credit; read back the HW
// context CIDX per queue and top PIDX up to (cidx + entries - 1) so credits never run dry.
// Runs in process context (indirect ctx reads sleep in the busy-poll).
void c2h_credit_work_fn(struct work_struct *work) {
    struct bus_driver_data *bd_data =
        container_of(to_delayed_work(work), struct bus_driver_data, c2h_credit_work);
    int32_t reg_val;
    uint16_t cidx, pidx;

    for (int i = 0; i < bd_data->num_queues; i++) {
        struct qdma_queue *q = bd_data->queues[i];
        if (!q || !q->c2h || !q->c2h_ring_vaddr || !q->running)
            continue;
        // Indirect READ of the HW C2H context; word0[15:0] = cidx
        reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
                ((QDMA_CTXT_SELC_DEC_HW_C2H & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
                ((QDMA_CTX_RD & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
                ((q->qid & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
        iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_cmd_reg);
        wmb();
        if (wait_until_busy_cleared(bd_data))
            continue;
        cidx = ioread32(bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start) & 0xFFFF;
        pidx = (cidx + QDMA_CPM4_C2H_RING_ENTRIES - 1) & 0xFFFF;
        if (pidx != q->c2h_pidx) {
            pr_info("c2h credit consumed: qid %d cidx %u -> replenish pidx %u\n", q->qid, cidx, pidx);
            iowrite32(pidx, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CPM4_DMAP_C2H_DSC_PIDX_REG + q->qid * QDMA_CPM4_PIDX_STEP);
            wmb();
            q->c2h_pidx = pidx;
        }

        // CMPT ring: consume completion records by advancing CIDX. The engine maintains the
        // ring's status entry (en_stat_desc) whose low 16 bits are the current CMPT PIDX.
        if (q->cmpt_ring_vaddr) {
            uint16_t cmpt_pidx = (uint16_t)(*(volatile uint64_t *)((uint8_t *)q->cmpt_ring_vaddr
                                            + QDMA_CPM4_CMPT_RING_ENTRIES * 8) & 0xFFFF);
            uint16_t tgt = (uint16_t)((cmpt_pidx + QDMA_CPM4_CMPT_RING_ENTRIES - 1)
                                      % QDMA_CPM4_CMPT_RING_ENTRIES);
            if (cmpt_pidx != 0 || q->cmpt_cidx != 0) {
                if (tgt != q->cmpt_cidx) {
                    pr_info("cmpt record: qid %d pidx %u -> cidx %u\n", q->qid, cmpt_pidx, tgt);
                    iowrite32(tgt, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CPM4_DMAP_CMPT_CIDX_REG + q->qid * QDMA_CPM4_PIDX_STEP);
                    wmb();
                    q->cmpt_cidx = tgt;
                }
            }
        }
    }

    if (bd_data->c2h_credit_work_active)
        schedule_delayed_work(&bd_data->c2h_credit_work, msecs_to_jiffies(QDMA_CPM4_C2H_CREDIT_INTERVAL_MS));
}

int enable_queues(struct bus_driver_data *bd_data) {
    BUG_ON(!bd_data);
    int ret_val = 0;

    // Initialize the register mask to all 1s, i.e. all bits in data registers are valid    
    for (int i = 0; i < bd_data->qreg.ctx_n_data_regs; i++) {
        iowrite32(QDMA_CXT_MASK_DEF_VAL, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_mask_reg_start + i * 4);
        wmb();
    }
    usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);

    // CPM4: program the global ring-size table entry 0 (SW-ctx rng_sz idx 0 points here) for
    // the C2H credit rings.
    if (bd_data->qreg.dev_type == QDMA_DEV_TYPE_CPM4) {
        iowrite32(QDMA_CPM4_C2H_RING_ENTRIES, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CPM4_GLBL_RNG_SZ_1_REG);
        wmb();
        usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);
    }

    // Populate the function map table (FMAP), per Table 149 in QDMA spec (PG347 v3.4).
    // The QDMA separates queues per physical function; Coyote uses a single PF (func 0) and
    // enables all queues for it. CPM5/eQDMA programs FMAP via the INDIRECT context (sel=FMAP);
    // CPM4 programs it as a DIRECT register at 0x400 + func_id*4 (QID_BASE bits[10:0],
    // QID_MAX bits[22:11]) -- on CPM4 the indirect sel 0xc is QID2VEC, not FMAP.
    int32_t reg_val;
    if (bd_data->qreg.fmap_indirect) {
        for (int i = 0; i < bd_data->qreg.ctx_n_data_regs; i++) {
            if (i == 0) {
                // Set QID base
                iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + i * 4);
                wmb();
            } else if (i == 1) {
                // Set maximum queue ID
                iowrite32(QDMA_N_QUEUES - 1, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + i * 4);
                wmb();
            } else {
                iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + i * 4);
                wmb();
            }
        }

        reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
                          ((QDMA_CTXT_SELC_FMAP & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
                          ((QDMA_CTX_WR & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
                          ((0 & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
        iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_cmd_reg);
        wmb();
        usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);
    } else {
        // CPM4 direct FMAP register for func 0: QID_BASE=0, QID_MAX=QDMA_N_QUEUES-1.
        uint32_t fmap = (0 & QDMA_CPM4_FMAP_QID_BASE_MASK) |
                        (((QDMA_N_QUEUES - 1) & 0xFFF) << QDMA_CPM4_FMAP_QID_MAX_SHIFT);
        iowrite32(fmap, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CPM4_FMAP_BASE_REG + 0 * QDMA_CPM4_FMAP_STEP);
        wmb();
        usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);
    }
    dbg_info("initialized function map table");

    // Program host profile (required for MM transfers on eQDMA/CPM5) and the NOC steering
    // that rides on the host-profile context. Host profile is an eQDMA/CPM5-only feature:
    // the GLBL_VCH/BRIDGE_HOST_PROFILE registers (0x2c8/0x308) and the HOST_PROFILE indirect
    // context do NOT exist on CPM4 (AMD dma_ip_drivers: absent from qdma_cpm4_reg.h). On CPM4
    // the CPM_PCIE_NOC MM routing is fixed by the block design (cr_pci.tcl), so skip this.
    // TODO(vck5000/CPM4): confirm CPM4 MM NoC steering is handled entirely in HW.
    if (bd_data->qreg.has_host_profile) {
        // For more details, see: https://adaptivesupport.amd.com/s/article/000035811?language=en_US
        iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + QDMA_GLBL_VCH_HOST_PROFILE_REG);
        wmb();
        usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);

        iowrite32(QDMA_DEFAULT_HOST_PROFILE_ID, bd_data->bar[BAR_DMA_CONFIG] + QDMA_GLBL_BRIDGE_HOST_PROFILE_REG);
        wmb();
        usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);

        // Set steering interface for MM transfers
        // To avoid NoC contention, Coyote does as follows:
        // 1. Register writes (to shell/static layer) are delivered via NOC_0 (configured in cr_pci.tcl)
        // 2. Memory-mapped PR transfer are delievered via NOC_1 (configured below)
        for (int i = 0; i < bd_data->qreg.ctx_n_data_regs; i++) {
            if (i == 2) {
                // Bits [95:64] ---> set steering to NOC_1 for C2H MM (though effectively unused)
                iowrite32(0x40000000, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + i * 4);
            } else if (i == 5) {
                // Bits [191:160] ---> set steering to NOC_1 for H2C MM
                iowrite32(0x00040000, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + i * 4);
            } else {
                iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_data_reg_start + i * 4);
            }
            wmb();
        }

        reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
                          ((QDMA_CTXT_SELC_HOST_PROFILE & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
                          ((QDMA_CTX_WR & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
                          ((QDMA_DEFAULT_HOST_PROFILE_ID & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
        iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + bd_data->qreg.ctx_cmd_reg);
        wmb();
        usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);
        dbg_info("host profile set");
    } else {
        pr_info("CPM4: skipping host-profile programming (eQDMA-only); MM NoC routing is fixed in HW\n");
    }

    // Card-to-host (C2H) queues need a prefetch tag to operate in bypass mode
    // The prefetch tag holds up to 6 bits, i.e. 64 different tags can be used
    // Hence, we can only enable up to 64 C2H queues in bypass mode
    if (QDMA_N_ACTIVE_QUEUES > 64) {
        pr_err("cannot enable more than 64 C2H queues in bypass mode, requested %d\n", QDMA_N_ACTIVE_QUEUES);
        ret_val = -ENODEV;
        goto fail;
    }

    // Set up PR queue
    ret_val = enable_queue(bd_data, QDMA_PR_QUEUE_IDX, false, true, 0); 
    if (ret_val) { goto fail; }

    // Enable H2C (host-to-card) queues
    for (int32_t qid = QDMA_RD_QUEUE_START_IDX; qid < QDMA_RD_QUEUE_START_IDX + QDMA_N_ACTIVE_QUEUES; qid++) {
        ret_val = enable_queue(bd_data, qid, false, false, 0); 
        if (ret_val) { goto fail; }
    }

    // First, set the maximum size of the C2H buffer; otherwise it's zero and no transfers happen
    // See register 0xAB0
    iowrite32(PAGE_SIZE, bd_data->bar[BAR_DMA_CONFIG] + 0xab0);
    wmb();
    usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);
    dbg_info("initialized C2H buffer size");

    // Enable C2H (card-to-host) queues
    for (int32_t qid = QDMA_WR_QUEUE_START_IDX; qid < QDMA_WR_QUEUE_START_IDX + QDMA_N_ACTIVE_QUEUES; qid++) {
        ret_val = enable_queue(bd_data, qid, true, false, 0); 
        if (ret_val) { goto fail; }
    }

    if (bd_data->num_queues != (2 * QDMA_N_ACTIVE_QUEUES + 1)) {
        pr_err("failed to enable all required c2h or h2c queues; got %d, requested %d queues\n", bd_data->num_queues, 2 * QDMA_N_ACTIVE_QUEUES + 1);
        return -ENODEV;
    }

    // Enable H2C MM engine by writing to bit 0 (run) of H2C MM control
    iowrite32(1, bd_data->bar[BAR_DMA_CONFIG] + QDMA_H2C_MM_CTRL_REG);

    // NOTE: If relying on C2H MM transfer, write bit 1 in QDMA_C2H_MM_CTRL_REG
    // iowrite32(1, bd_data->bar[BAR_DMA_CONFIG] + QDMA_C2H_MM_CTRL_REG);

    dbg_info("found %d queues\n", bd_data->num_queues);
    goto success;

fail:
    pr_err("queue setup failed, unwinding\n");
    
    // Disable queues
    disable_queues(bd_data);
    
    // Disable MM engines
    iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + QDMA_H2C_MM_CTRL_REG);
    // iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + QDMA_C2H_MM_CTRL_REG);

    return -1;

success:
    return ret_val;
}

void disable_queues(struct bus_driver_data *bd_data) {
    BUG_ON(!bd_data);

    int num_queues = bd_data->num_queues;
    for (int i = 0; i < num_queues; i++) {
        struct qdma_queue *tmp_queue = bd_data->queues[i];
        if (tmp_queue) {
            dbg_info("disabling queue with qid %d\n", tmp_queue->qid);
            
            // Invalidate contexts, as per QDMA specification from PG347 (v3.4), p301
            if (tmp_queue->c2h) {
                invalidate_ctx_reg(bd_data, tmp_queue->qid, QDMA_CTXT_SELC_PFTCH);
                invalidate_ctx_reg(bd_data, tmp_queue->qid, QDMA_CTXT_SELC_WRB);
                invalidate_ctx_reg(bd_data, tmp_queue->qid, QDMA_CTXT_SELC_DEC_SW_C2H);
                invalidate_ctx_reg(bd_data, tmp_queue->qid, QDMA_CTXT_SELC_TIMER);
            } else {
                invalidate_ctx_reg(bd_data, tmp_queue->qid, QDMA_CTXT_SELC_WRB);
                invalidate_ctx_reg(bd_data, tmp_queue->qid, QDMA_CTXT_SELC_DEC_SW_H2C);
            }
            // Not really needed, but included for completness sake
            tmp_queue->running = 0;

            // Release the CPM4 C2H credit + CMPT rings, if any
            if (tmp_queue->c2h_ring_vaddr)
                dma_free_coherent(&bd_data->pci_dev->dev, QDMA_CPM4_C2H_RING_BYTES,
                                  tmp_queue->c2h_ring_vaddr, tmp_queue->c2h_ring_paddr);
            if (tmp_queue->cmpt_ring_vaddr)
                dma_free_coherent(&bd_data->pci_dev->dev, QDMA_CPM4_CMPT_RING_BYTES,
                                  tmp_queue->cmpt_ring_vaddr, tmp_queue->cmpt_ring_paddr);

            // Release the dynamically allocated memory for this engine
            kfree(tmp_queue);

            bd_data->num_queues--;
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
    ret_val = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(TLB_PADDR_RANGE)); // 44
    if (ret_val) {
        dev_err(&pdev->dev, "failed to set 64b DMA mask\n");
        goto err_mask;
    }

    // Memory map registers into the kernel space
    bd_data->stat_cnfg = ioremap(bd_data->bar_phys_addr[BAR_STAT_CONFIG] + FPGA_STAT_CNFG_OFFS, FPGA_STAT_CNFG_SIZE);
    bd_data->shell_cnfg = ioremap(bd_data->bar_phys_addr[BAR_SHELL_CONFIG] + FPGA_SHELL_CNFG_OFFS, FPGA_SHELL_CNFG_SIZE);

    // Detect CPM4 vs CPM5(eQDMA) and select the correct QDMA register layout before any
    // QDMA context/register programming. Must run after the DMA-config BAR is mapped.
    qdma_init_reg_layout(bd_data);

    // Set-up the QDMA queues
    ret_val = enable_queues(bd_data);
    if (ret_val) {
        dev_err(&pdev->dev, "error whilst probing DMA queues\n");
        goto err_queues;
    }

    // CPM4: start the C2H credit replenish work (tops up ring PIDX as packets consume credits)
    INIT_DELAYED_WORK(&bd_data->c2h_credit_work, c2h_credit_work_fn);
    if (bd_data->qreg.dev_type == QDMA_DEV_TYPE_CPM4) {
        bd_data->c2h_credit_work_active = true;
        schedule_delayed_work(&bd_data->c2h_credit_work, msecs_to_jiffies(QDMA_CPM4_C2H_CREDIT_INTERVAL_MS));
    }

    // Assert shell reset
    bd_data->stat_cnfg->reconfig_eost_reset = 0x0;
    wmb();
    usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);

    bd_data->stat_cnfg->reconfig_eost_reset = 0x1;
    wmb();
    usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);

    // Initialize spin locks
    init_spin_locks(bd_data);

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
    // Disable queues
    disable_queues(bd_data);
    
    // Disable MM engines
    iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + QDMA_H2C_MM_CTRL_REG);
    // iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + QDMA_C2H_MM_CTRL_REG);

err_queues:
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

    // Stop the CPM4 C2H credit replenish work before tearing anything down
    if (bd_data->c2h_credit_work_active) {
        bd_data->c2h_credit_work_active = false;
        cancel_delayed_work_sync(&bd_data->c2h_credit_work);
    }

    // Free HMM chunks
    #ifdef HMM_KERNEL    
        free_mem_regions(bd_data);
        dbg_info("freed svm private pages");
    #endif

    // Disable and remove interrupts
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

    // Disable QDMA queues
    disable_queues(bd_data);
    dbg_info("queue removed\n");

    // Disable QDMA MM engines
    iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + QDMA_H2C_MM_CTRL_REG);
    // iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + QDMA_C2H_MM_CTRL_REG);

    // Unmap QDMA BARs
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

// List of Versal devices which can be used with the Coyote driver
// 0x10ee is the vendor ID for AMD/Xilinx FPGAs, while the other number represents the device ID, set in the QDMA IP configuration
static const struct pci_device_id pci_ids[] = {
    { PCI_DEVICE(0x10ee, 0xB03F), },
    { PCI_DEVICE(0x10ee, 0xB13F), },
    { PCI_DEVICE(0x10ee, 0xB23F), },
    { PCI_DEVICE(0x10ee, 0xB33F), },
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
