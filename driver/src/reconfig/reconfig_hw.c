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

#include "reconfig_hw.h"

// The descriptor FIFO drops commands posted while it is full; reconfig_ctrl reads its occupancy
static int __must_check wait_reconfig_fifo(struct bus_driver_data *bus_data, int *cmd_sent) {
    unsigned long deadline = jiffies + msecs_to_jiffies(CYT_POLL_TIMEOUT_MS);
    while (*cmd_sent >= RECONFIG_THRESHOLD) {
        *cmd_sent = bus_data->stat_cnfg->reconfig_ctrl;
        if (time_after(jiffies, deadline)) {
            shell_err_ratelimited(bus_data, "reconfiguration descriptor queue made no progress for %d ms\n", CYT_POLL_TIMEOUT_MS);
            return -ETIMEDOUT;
        }
        usleep_range(RECONFIG_MIN_SLEEP_CMD, RECONFIG_MAX_SLEEP_CMD);
    }
    return 0;
}

int reconfigure_start(struct reconfig_dev *device, uint64_t vaddr, uint64_t len, pid_t pid, uint32_t crid) {
    int ret_val = -ENOENT;

    // Parse bus data and check non-null
    BUG_ON(!device);
    struct bus_driver_data *bus_data = device->bd_data;
    BUG_ON(!bus_data);

    // Iterate through all the entries of allocated buffers
    // Where the virtual address, PID and configuration ID (crid) match, trigger reconfig by writing to FPGA memory
    int cmd_sent = 0;
    struct reconfig_buff_metadata *tmp_buff;
    hash_for_each_possible(reconfig_buffs_map, tmp_buff, entry, vaddr) {
        if (tmp_buff->vaddr == vaddr && tmp_buff->pid == pid && tmp_buff->crid == crid) {
            uint64_t n_bistream_full_pages = len / RECONFIG_BUFF_PAGE_SIZE;
            uint64_t partial_bitsream_size = len % RECONFIG_BUFF_PAGE_SIZE;
            shell_info(
                bus_data, "reconfig bitstream: full pages %lld (hugepages), partial %lld B\n", 
                n_bistream_full_pages, partial_bitsream_size
            );

            // Write full pages, sequentially; but make sure not to over-saturate with writes (cmd_sent)
            for (int i = 0; i < n_bistream_full_pages; i++) {
                ret_val = wait_reconfig_fifo(bus_data, &cmd_sent);
                if (ret_val) {
                    return ret_val;
                }

                bus_data->stat_cnfg->reconfig_addr_low = LOW_32(tmp_buff->hpages[i]);
                bus_data->stat_cnfg->reconfig_addr_high = HIGH_32(tmp_buff->hpages[i]);
                bus_data->stat_cnfg->reconfig_len = RECONFIG_BUFF_PAGE_SIZE;
                wmb();
                
                if (partial_bitsream_size == 0 && i == n_bistream_full_pages - 1) {
                    bus_data->stat_cnfg->reconfig_ctrl = RECONFIG_CTRL_START_LAST;
                } else {
                    bus_data->stat_cnfg->reconfig_ctrl = RECONFIG_CTRL_START_MIDDLE;
                }
                wmb();
                cmd_sent++;
            }

            // Write the last partial page
            if (partial_bitsream_size > 0) {
                ret_val = wait_reconfig_fifo(bus_data, &cmd_sent);
                if (ret_val) {
                    return ret_val;
                }
                
                bus_data->stat_cnfg->reconfig_addr_low = LOW_32(tmp_buff->hpages[n_bistream_full_pages]);
                bus_data->stat_cnfg->reconfig_addr_high = HIGH_32(tmp_buff->hpages[n_bistream_full_pages]);
                bus_data->stat_cnfg->reconfig_len = partial_bitsream_size;
                wmb();

                bus_data->stat_cnfg->reconfig_ctrl = RECONFIG_CTRL_START_LAST;
                wmb();
                cmd_sent++;
            }

            ret_val = 0;
        }
    }

    if (ret_val == -ENOENT) {
        shell_warn_ratelimited(bus_data, "no reconfig buffer at vaddr 0x%llx for pid %d, crid %u\n", vaddr, pid, crid);
    }
    return ret_val;
}