/**
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

#include "vfpga_hw.h"

uint32_t read_irq_type(struct vfpga_dev *device) {
    // Read register & apply correct mask to keep target values (see hw/hdl/shell/cnfg_slave_avx.sv)
    BUG_ON(!device);
    uint32_t type = (uint32_t) (HIGH_16(LOW_32(device->cnfg_regs->isr)));
    return type;
}

void read_irq_notify(struct vfpga_dev *device, struct vfpga_irq_notify *irq_not) {
    // Read register & apply correct mask to keep target values (see hw/hdl/shell/cnfg_slave_avx.sv)
    BUG_ON(!device);
    irq_not->ctid = (int32_t) LOW_32(device->cnfg_regs->isr_pid);
    irq_not->notification_value = (int32_t) HIGH_32(device->cnfg_regs->isr_len);
}

void read_irq_pfault(struct vfpga_dev *device, struct vfpga_irq_pfault *irq_pf) {
    // Read register & apply correct mask to keep target values (see hw/hdl/shell/cnfg_slave_avx.sv)
    BUG_ON(!device);
    irq_pf->vaddr = device->cnfg_regs->isr_vaddr;
    irq_pf->len = (int32_t) LOW_32(device->cnfg_regs->isr_len);
    irq_pf->ctid = (int32_t) LOW_32(device->cnfg_regs->isr_pid);
    irq_pf->stream = HIGH_16((int32_t) HIGH_32(device->cnfg_regs->isr)) & 0x3;
    irq_pf->wr = HIGH_16((int32_t) HIGH_32(device->cnfg_regs->isr)) >> 8;
}

void drop_irq_pfault(struct vfpga_dev *device, bool write, int32_t ctid) {
    // Set hardware registers to trigger the drop; 
    // But only set lower 16 bits, as these are the control ones; keep the rest same as before
    BUG_ON(!device);
    device->cnfg_regs->isr_pid = ctid; 
    device->cnfg_regs->isr = (device->cnfg_regs->isr & FPGA_CNF_CTRL_IRQ_MASK) | (write ? FPGA_CNFG_CTRL_IRQ_PF_WR_DROP : FPGA_CNFG_CTRL_IRQ_PF_RD_DROP);
}
 
void clear_irq(struct vfpga_dev *device) {
    // Set hardware register to trigger the clear
    // But only set lower 16 bits, as these are the control ones; keep the rest same as before
    BUG_ON(!device);
    device->cnfg_regs->isr = (device->cnfg_regs->isr & FPGA_CNF_CTRL_IRQ_MASK) | FPGA_CNFG_CTRL_IRQ_CLR_PENDING;
}

void restart_mmu(struct vfpga_dev *device, bool write, int32_t ctid) {
    // Set hardware registers to trigger the restart
    // But only set lower 16 bits, as these are the control ones; keep the rest same as before
    BUG_ON(!device);
    device->cnfg_regs->isr_pid = ctid; 
    device->cnfg_regs->isr = (device->cnfg_regs->isr & FPGA_CNF_CTRL_IRQ_MASK) | (write ? FPGA_CNFG_CTRL_IRQ_PF_WR_SUCCESS : FPGA_CNFG_CTRL_IRQ_PF_RD_SUCCESS);
}

void invalidate_tlb_entry(struct vfpga_dev *device, uint64_t vaddr, uint32_t n_pages, int32_t hpid, bool last) {
    // Set the hardware registers related to invalidation; the last one triggers the actual invalidation
    BUG_ON(!device);
    device->cnfg_regs->isr_pid = (uint64_t) hpid << 32;
    device->cnfg_regs->isr_vaddr = vaddr << PAGE_SHIFT;
    device->cnfg_regs->isr_len = ((uint64_t) n_pages) << PAGE_SHIFT;
    device->cnfg_regs->isr = (device->cnfg_regs->isr & FPGA_CNF_CTRL_IRQ_MASK) | (last ? FPGA_CNFG_CTRL_IRQ_INVLDT_LAST : FPGA_CNFG_CTRL_IRQ_INVLDT);
}

void change_tlb_lock(struct vfpga_dev *device) {
    BUG_ON(!device);
    device->cnfg_regs->isr = (device->cnfg_regs->isr & FPGA_CNF_CTRL_IRQ_MASK) | FPGA_CNFG_CTRL_IRQ_LOCK;
}

void create_tlb_mapping(
    struct vfpga_dev *device, struct tlb_metadata *tlb_meta, uint64_t vaddr, 
    uint64_t physical_address, int32_t host, int32_t ctid, pid_t hpid
) {
    BUG_ON(!device);
    uint64_t key = (vaddr >> (tlb_meta->page_shift - PAGE_SHIFT)) & tlb_meta->key_mask;
    uint64_t tag = (vaddr >> (tlb_meta->page_shift - PAGE_SHIFT)) >> tlb_meta->key_size;
    uint64_t physical_address_masked = (physical_address >> tlb_meta->page_shift) & tlb_meta->phy_mask;

    // Create new entry
    uint64_t entry [2];
    entry[0] |= physical_address_masked | ((uint64_t) hpid << 32);
    entry[1] |= key | (tag                          << (tlb_meta->key_size)) 
                    | ((uint64_t) ctid              << (tlb_meta->key_size + tlb_meta->tag_size))
                    | ((uint64_t) host              << (tlb_meta->key_size + tlb_meta->tag_size + PID_SIZE))
                    | (1UL                          << (tlb_meta->key_size + tlb_meta->tag_size + PID_SIZE + STRM_SIZE))
                    | (physical_address_masked      << (tlb_meta->key_size + tlb_meta->tag_size + PID_SIZE + STRM_SIZE + 1));

    dbg_info(
        "creating new TLB entry: virtual address %llx, physical address %llx, stream %d, ctid %d, hpid %d, hugepage %d\n", 
        vaddr, physical_address, host, ctid, hpid, tlb_meta->hugepage
    );

    // Map page through AXI Lite
    if(tlb_meta->hugepage) {
        device->fpga_lTlb[0] = entry[0];
        device->fpga_lTlb[1] = entry[1];
    } else {
        device->fpga_sTlb[0] = entry[0];
        device->fpga_sTlb[1] = entry[1];
    }
}

void create_tlb_unmapping(struct vfpga_dev *device, struct tlb_metadata *tlb_meta, uint64_t vaddr, pid_t hpid) {
    BUG_ON(!device);
    uint64_t key = (vaddr >> (tlb_meta->page_shift - PAGE_SHIFT)) & tlb_meta->key_mask;
    uint64_t tag = (vaddr >> (tlb_meta->page_shift - PAGE_SHIFT)) >> tlb_meta->key_size;

    // Invalidate entry, by setting field to zero
    uint64_t entry [2];
    entry[0] |= ((uint64_t) hpid << 32);
    entry[1] |= key | (tag << (tlb_meta->key_size)) 
                    | (0UL << (tlb_meta->key_size + tlb_meta->tag_size + PID_SIZE + STRM_SIZE));

    dbg_info("unmapping TLB entry: virtual address %llx, hpid %d, hugepage %d\n", vaddr, hpid, tlb_meta->hugepage);

    // Map page through AXI Lite
    if(tlb_meta->hugepage) {
        device->fpga_lTlb[0] = entry[0];
        device->fpga_lTlb[1] = entry[1];
    } else {
        device->fpga_sTlb[0] = entry[0];
        device->fpga_sTlb[1] = entry[1];
    }
}

void trigger_dma_offload(struct vfpga_dev *device, uint64_t *host_address, uint64_t *card_address, uint32_t n_pages, bool huge) {
    // Parse device data and check non-null
    BUG_ON(!device);
    struct bus_driver_data *bus_data = device->bd_data;
    BUG_ON(!bus_data);

    int cmd_sent = 0;
    uint32_t pg_inc = huge ? MAX_SINGLE_DMA_SYNC : 1;
    uint64_t len = huge ? (MAX_SINGLE_DMA_SYNC * PAGE_SIZE) : bus_data->stlb_meta->page_size;

    // Off-load all the pages
    // To avoid bottlenecking the system, there is a limit on the number of pages that can be off-loaded simultaneously
    for (int i = 0; i < n_pages; i += pg_inc) {
        if (host_address[i] == 0 || card_address[i] == 0) {
            continue;
        }

        // Sleep until some of the off-loads have been marked as processed and the current number becomes smaller than the limit
        while (cmd_sent >= DMA_THRSH) {
            cmd_sent = device->cnfg_regs->offl_ctrl;
            usleep_range(DMA_MIN_SLEEP_CMD, DMA_MAX_SLEEP_CMD);
        }

        // Write to registers for off-loading; the last one triggers the actual off-load
        device->cnfg_regs->offl_host_offs = host_address[i];
        device->cnfg_regs->offl_card_offs = card_address[i];
        device->cnfg_regs->offl_ctrl = (len << 32) | ((i == n_pages - pg_inc) ? DMA_CTRL_START_LAST : DMA_CTRL_START_MIDDLE);
        
        cmd_sent++;
    }
}

void trigger_dma_sync(struct vfpga_dev *device, uint64_t *host_address, uint64_t *card_address, uint32_t n_pages, bool huge) {
    // Parse device data and check non-null
    BUG_ON(!device);
    struct bus_driver_data *bus_data = device->bd_data;
    BUG_ON(!bus_data);

    int cmd_sent = 0;
    uint32_t pg_inc = huge ? MAX_SINGLE_DMA_SYNC : 1;
    uint64_t len = huge ? (MAX_SINGLE_DMA_SYNC * PAGE_SIZE) : bus_data->stlb_meta->page_size;

    // Sync all the pages
    // To avoid bottlenecking the system, there is a limit on the number of pages that can be synced simultaneously
    for (int i = 0; i < n_pages; i += pg_inc) {
        
        // Sleep until some of the syncs have been marked as processed and the current number becomes smaller than the limit
        while (cmd_sent >= DMA_THRSH) {
            cmd_sent = device->cnfg_regs->sync_ctrl;
            usleep_range(DMA_MIN_SLEEP_CMD, DMA_MAX_SLEEP_CMD);
        }

        // Write to registers for syncing; the last one triggers the actual sync
        device->cnfg_regs->sync_host_offs = host_address[i]; 
        device->cnfg_regs->sync_card_offs = card_address[i];
        device->cnfg_regs->sync_ctrl = (len << 32) | ((i == n_pages-pg_inc) ? DMA_CTRL_START_LAST : DMA_CTRL_START_MIDDLE);

        cmd_sent++;
    }
}

int alloc_card_memory(struct vfpga_dev *device, uint64_t *card_physical_address, uint32_t n_pages, bool huge) {
    // Parse device data and check non-null
    BUG_ON(!device);
    struct bus_driver_data *bus_data = device->bd_data;
    BUG_ON(!bus_data);

    spin_lock(&bus_data->card_lock);
    if (huge) {
        // Check sufficient space in card memory is available 
        if (bus_data->num_free_lchunks < n_pages) {
            pr_warn("not enough available hugepages on the card\n");
            return -ENOMEM;
        }

        // Obtain the next available physical address, mark it as used and update the card_physical_address list with this page
        for (int i = 0; i < n_pages; i++) {
            bus_data->lalloc->used = true;
            card_physical_address[i] = (bus_data->lalloc->id << bus_data->stlb_meta->page_shift) + bus_data->card_huge_offs;
            bus_data->lalloc = bus_data->lalloc->next;
        }
    } else {
        // Check sufficient space in card memory is available 
        if (bus_data->num_free_schunks < n_pages) {
            pr_warn("not enough available regular pages on the card\n");
            return -ENOMEM;
        }

        // Obtain the next available physical address, mark it as used and update the card_physical_address list with this page
        for (int i = 0; i < n_pages; i++) {
            bus_data->salloc->used = true;
            card_physical_address[i] = (bus_data->salloc->id << bus_data->stlb_meta->page_shift) + bus_data->card_reg_offs;
            bus_data->salloc = bus_data->salloc->next;
        }
    }

    dbg_info("user card buffer allocated @ %llx, n_pages %d, huge %d, device %d\n", card_physical_address[0], n_pages, huge, device->id);
    spin_unlock(&bus_data->card_lock);
    return 0;
}
 
void free_card_memory(struct vfpga_dev *device, uint64_t *card_physical_address, uint32_t n_pages, bool huge) {
    // Parse device data and check non-null
    BUG_ON(!device);
    struct bus_driver_data *bus_data = device->bd_data;
    BUG_ON(!bus_data);

    spin_lock(&bus_data->card_lock);

    // Iterate over the pages and mark them as free
    if (huge) {
        for (int i = n_pages - 1; i >= 0; i--) {
            uint64_t tmp_id = (card_physical_address[i] - bus_data->card_huge_offs) >> bus_data->stlb_meta->page_shift;
            if(bus_data->lchunks[tmp_id].used) {
                bus_data->lchunks[tmp_id].next = bus_data->lalloc;
                bus_data->lalloc = &bus_data->lchunks[tmp_id];
            }
        }
    } else {
        for (int i = n_pages - 1; i >= 0; i--) {
            uint64_t tmp_id = (card_physical_address[i] - bus_data->card_reg_offs) >> bus_data->stlb_meta->page_shift;
            if (bus_data->schunks[tmp_id].used) {
                bus_data->schunks[tmp_id].next = bus_data->salloc;
                bus_data->salloc = &bus_data->schunks[tmp_id];
            }
        }
    }

    spin_unlock(&bus_data->card_lock);
}