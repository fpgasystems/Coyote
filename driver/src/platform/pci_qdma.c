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

void wait_until_busy_cleared(struct bus_driver_data *bd_data) {
    int busy;
    do {
        usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);
        busy = ioread32(bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_CMD_REG) & 0x1;
    } while (busy);
}

void clear_ctx_reg(struct bus_driver_data *bd_data, int32_t qid, int32_t sel) {
    // Issue clear operation
    int32_t reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
                      ((sel & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
                      ((QDMA_CTX_CLR & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
                      ((qid & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
    iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_CMD_REG);
    wmb();
    wait_until_busy_cleared(bd_data);
}

void invalidate_ctx_reg(struct bus_driver_data *bd_data, int32_t qid, int32_t sel) {
    // Issue invalidate operation
    int32_t reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
                      ((sel & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
                      ((QDMA_CTX_INV & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
                      ((qid & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
    iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_CMD_REG);
    wmb();
    wait_until_busy_cleared(bd_data);
}

int enable_queue(struct bus_driver_data *bd_data, int c2h, int32_t qid) {
    // Initialize the queue struct
    dbg_info("creating queue with qid %d, c2h %d", qid, c2h);
    struct qdma_queue *tmp_queue = kzalloc(sizeof(struct qdma_queue), GFP_KERNEL);
    if (!tmp_queue) { 
        pr_err("error allocating queue struct\n");
        return -1;
    }
    tmp_queue->qid = qid;
    tmp_queue->c2h = c2h;
    tmp_queue->running = false;
    
    // Clear any previous contexts
    dbg_info("clearing SW, HW, credit contexts for qid %d", qid);
    clear_ctx_reg(bd_data, qid, QDMA_CTXT_SELC_DEC_SW_C2H);
    clear_ctx_reg(bd_data, qid, QDMA_CTXT_SELC_DEC_SW_H2C);
    clear_ctx_reg(bd_data, qid, QDMA_CTXT_SELC_DEC_HW_C2H);
    clear_ctx_reg(bd_data, qid, QDMA_CTXT_SELC_DEC_HW_H2C);
    clear_ctx_reg(bd_data, qid, QDMA_CTXT_SELC_DEC_CR_C2H);
    clear_ctx_reg(bd_data, qid, QDMA_CTXT_SELC_DEC_CR_H2C);

    // Initialize the register mask to all 1s, as specified in the docs
    for (int i = 0; i < QDMA_CTX_N_DATA_REGS; i++) {
        iowrite32(QDMA_CXT_MASK_DEF_VAL, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_MASK_REG_START + i * 4);
        wmb();
    }
    usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);

    // Set-up descriptor SW context, based on Table 6 from QDMA specification [PG302 v5.0]
    // In the first 32 bits, we want to set function ID to 0 (only one PF) and disable interrupts by setting irq_arm to 0
    // Other bits don't matter to much, set to zero ---> hence, entire reg is zero.
    iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_DATA_REG_START);
    wmb();

    // Set bits 32 - 63; in these bits we want to set qen to 1, which enables the queue
    // Additionally, want to set bit 50 to 1, corresponding to bypass mode.
    // Finally, bit 63 should be 0, indicating ST mode, instead of MM
    // Putting it al together, the hex value for the register is 0x00040001
    iowrite32(0x00040001, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_DATA_REG_START + 4);
    wmb();

    // The other fields are reserved, per the QDMA spec, hence set to 0
    for (int i = 2; i < QDMA_CTX_N_DATA_REGS; i++) {
        iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_DATA_REG_START + i * 4);
        wmb();
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
    iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_CMD_REG);
    wmb();
    wait_until_busy_cleared(bd_data);

    // Read the hardware register (idl_stp_b, Table 7 in spec) to check the queue is enabled
    // Fist, issue read command
    if (c2h) {
        reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
                ((QDMA_CTXT_SELC_DEC_HW_C2H & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
                ((QDMA_CTX_RD & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
                ((qid & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
    } else {
        reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
                ((QDMA_CTXT_SELC_DEC_HW_H2C & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
                ((QDMA_CTX_RD & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
                ((qid & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
    }
    iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_CMD_REG);
    wmb();
    wait_until_busy_cleared(bd_data);
    
    // Then, read bit 41, corresponding to idl_stp_b
    reg_val = ioread32(bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_DATA_REG_START + 4);
    int32_t idl_stp_b = (reg_val >> 9) & 0x1;
    if (idl_stp_b) {
        dbg_info("enabled software context for qid %d", qid);
    } else {
        pr_err("failed to enable software context for qid %d, releasing queue", qid);
        goto fail;
    }
    
    // Clear prefetch and completion contexts, as per QDMA specification [PG302 v5.0]
    dbg_info("clearing prefetch and completion contexts for qid %d", qid);
    clear_ctx_reg(bd_data, qid, QDMA_CTXT_SELC_PFTCH);
    clear_ctx_reg(bd_data, qid, QDMA_CTXT_SELC_WRB);

    // Set up prefetch context for C2H streams in simple bypass mode, per Table 14 in QDMA specification [PG302 v5.0]
    if (c2h) {
        // For bits 31:0, set bypass = 1 (bit 0), port_id = 0 (bits 7:5), and pfch_en = 0 (bit 28)
        iowrite32(0x1, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_DATA_REG_START);
        wmb();

        // For bits 63:32, valid = 1 (bit 45)
        iowrite32(0x2000, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_DATA_REG_START + 4);
        wmb();

        // Fire command to write the prefetch context
        reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
                ((QDMA_CTXT_SELC_PFTCH & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
                ((QDMA_CTX_WR & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
                ((qid & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
   
        iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_CMD_REG);
        wmb();
        wait_until_busy_cleared(bd_data);
        
        // Verify prefetch contex is indeed set to valid; first issue read command
        reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
            ((QDMA_CTXT_SELC_PFTCH & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
            ((QDMA_CTX_RD & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
            ((qid & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
        iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_CMD_REG);
        wmb();
        usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);

        // Then, read bit 45, corresponding to valid bit
        reg_val = ioread32(bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_DATA_REG_START + 4);
        int32_t valid = (reg_val >> 13) & 0x1;
        if (valid) {
            dbg_info("C2H prefetch context set valid, qid %d", qid);
        } else {
            pr_err("C2H prefetch context could not be set valid, qid %d", qid);
            goto fail;
        }

        // For simple bypass mode with commands issued from the FPGA, each command needs
        // to have a prefetch_tag, as explained on p51 of QDMA specification [PG302 v5.0]
        // This tag can be requested by writing the queue ID to the register QDMA_C2H_PFCH_BYP_QID (0x1408)
        // Then, it can be obtained by reading the register QDMA_C2H_PFCH_BYP_TAG (0x140C)
        // Finally, we send it to Coyote by writing to the memory-mapped registers of the static layer, 
        // so that it can always be used for DMA requests. Bit 31 is set to 1 to indicate it's a valid tag
        iowrite32(qid, bd_data->bar[BAR_DMA_CONFIG] + QDMA_C2H_PFCH_BYP_QID_REG);
        wmb();
        usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);
        int32_t pfch_tag_reg = ioread32(bd_data->bar[BAR_DMA_CONFIG] + QDMA_C2H_PFCH_BYP_TAG_REG);
        int32_t pfch_qid = ((pfch_tag_reg >> 8) & 0xFFF) - QDMA_WR_QUEUE_IDX;       // bits 19:8 are the queue ID; substract starting WR queue index because the HW stores them 0, 1 in pfch_tags in qdma_wr_wrapper                    
        int32_t pfch_tag = pfch_tag_reg & 0x7F;                                     // bits 6:0 are the tag   
        reg_val = (1 << 31) | (pfch_qid << 8) | pfch_tag;
        
        bd_data->stat_cnfg->qdma_pfch_tag = reg_val;
        wmb();
        usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);
        bd_data->stat_cnfg->qdma_pfch_tag = 0;  // Reset valid signal

        dbg_info("C2H prefetch tag for qid %d is %d", pfch_qid + QDMA_WR_QUEUE_IDX, pfch_tag);
    }

    // Set up completion context, per Table 16 in QDMA specification [PG302 v5.0]
    // For bits 31:0, need to set fnc_id (12:5) to 0 (there's only one PF) and en_stat_desc (bit 0) to 1.
    iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_DATA_REG_START);
    wmb();

    // For bits 63:32 and 95:64, there are no fields to be set, hence set to zero.
    iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_DATA_REG_START + 4);
    wmb();
    iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_DATA_REG_START + 8);
    wmb();

    // For bits 127:96, the valid bit (124) needs to be set
    iowrite32(0x10000000, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_DATA_REG_START + 12);
    wmb();

    // For bits 159:128, the dir_c2h bit (146) needs to be set
    if (c2h) {
        iowrite32(0x40000, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_DATA_REG_START + 16);
        wmb();
    } else {
        iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_DATA_REG_START + 16);
        wmb();
    }

    // The rest of the fields are zero
    for (int i = 5; i < QDMA_CTX_N_DATA_REGS; i++) {
        iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_DATA_REG_START + i * 4);
        wmb();
    }
    
    // Fire command to write completion context
    reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
                ((QDMA_CTXT_SELC_WRB & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
                ((QDMA_CTX_WR & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
                ((qid & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
   
    iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_CMD_REG);
    wmb();
    wait_until_busy_cleared(bd_data);
    dbg_info("enabled completion context for qid %d", qid);

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
    kfree(tmp_queue);
    return -1;
}

int enable_queues(struct bus_driver_data *bd_data) {
    BUG_ON(!bd_data);
    int ret_val = 0;

    // Populate the function map table, per Table 30 in QDMA specification [PG302 v5.0]
    // The QDMA allows to separate queues per physical function, providing full isolation between functions
    // Currently, Coyote only supports one PF per FPGA, hence we will enable all queues for this PF
    for (int i = 0; i < QDMA_CTX_N_DATA_REGS; i++) {
        if (i == 0) {   
            // Set QID base
            iowrite32(QDMA_RD_QUEUE_IDX, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_DATA_REG_START + i * 4);
            wmb();
        } else if (i == 1) {
            // Set maximum queue ID
            iowrite32(QDMA_N_QUEUES - 1, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_DATA_REG_START + i * 4);
            wmb();
        } else {
            iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_DATA_REG_START + i * 4);
            wmb();
        }
    }

    int32_t reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
                      ((QDMA_CTXT_SELC_FMAP & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
                      ((QDMA_CTX_WR & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
                      ((0 & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
    iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_CMD_REG);
    wmb();
    usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);
    dbg_info("initialized function map table");

    // Initialize the host profile context to zeros, per the docs
    for (int i = 0; i < QDMA_CTX_N_DATA_REGS; i++) {
        iowrite32(0, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_DATA_REG_START + i * 4);
        wmb();
    }

    reg_val = QDMA_CTX_BUSY_VAL_DEAULT |
                      ((QDMA_CTXT_SELC_HOST_PROFILE & QDMA_CTX_SEL_MASK) << QDMA_CTX_SEL_SHIFT) |
                      ((QDMA_CTX_WR & QDMA_CTX_OP_MASK) << QDMA_CTX_OP_SHIFT) |
                      ((QDMA_RD_QUEUE_IDX & QDMA_CTX_QID_MASK) << QDMA_CTX_QID_SHIFT);
    iowrite32(reg_val, bd_data->bar[BAR_DMA_CONFIG] + QDMA_CTX_CMD_REG);
    wmb();
    usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);
    dbg_info("reset host profile");

    // Enable H2C (host-to-card) queues
    for (int32_t qid = QDMA_RD_QUEUE_IDX; qid < QDMA_RD_QUEUE_IDX + QDMA_N_ACTIVE_QUEUES; qid++) {
        ret_val = enable_queue(bd_data, 0, qid); 
        if (ret_val) { goto fail; }
    }

    // First, set the maximum size of the C2H buffer; otherwise it's zero and no transfers happen
    // See page 48 of the QDMA specification [PG302 v5.0] and the register 0xAB0
    iowrite32(PAGE_SIZE, bd_data->bar[BAR_DMA_CONFIG] + 0xab0);
    wmb();
    usleep_range(DMA_MIN_SLEEP_CMD, DMA_MIN_SLEEP_CMD);
    dbg_info("initialized C2H buffer size");

    // Enable C2H (card-to-host) queues
    for (int32_t qid = QDMA_WR_QUEUE_IDX; qid < QDMA_WR_QUEUE_IDX + QDMA_N_ACTIVE_QUEUES; qid++) {
        ret_val = enable_queue(bd_data, 1, qid); 
        if (ret_val) { goto fail; }
    }

    if (bd_data->num_queues != 2 * QDMA_N_ACTIVE_QUEUES) {
        pr_err("failed to enable all required c2h or h2c queues; got %d, requested %d queues\n", bd_data->num_queues, 2 * QDMA_N_ACTIVE_QUEUES);
        return -ENODEV;
    }

    dbg_info("found %d queues\n", bd_data->num_queues);
    goto success;

fail:
    pr_err("queue setup failed, unwinding\n");
    disable_queues(bd_data);
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
            
            // Invalidate contexts, as per QDMA specification [PG302 v5.0], page 92
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
    ret_val = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(64));
    if (ret_val) {
        dev_err(&pdev->dev, "failed to set 64b DMA mask\n");
        goto err_mask;
    }

    // Memory map registers into the kernel space
    bd_data->stat_cnfg = ioremap(bd_data->bar_phys_addr[BAR_STAT_CONFIG] + FPGA_STAT_CNFG_OFFS, FPGA_STAT_CNFG_SIZE);
    bd_data->shell_cnfg = ioremap(bd_data->bar_phys_addr[BAR_SHELL_CONFIG] + FPGA_SHELL_CNFG_OFFS, FPGA_SHELL_CNFG_SIZE);

    // Set-up the QDMA queues
    ret_val = enable_queues(bd_data);
    if (ret_val) {
        dev_err(&pdev->dev, "error whilst probing DMA queues\n");
        goto err_queues;
    }

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
    disable_queues(bd_data);
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
