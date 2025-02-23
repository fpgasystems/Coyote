#include "reconfig_hw.h"

int reconfigure_start(struct reconfig_dev *device, uint64_t virtual_address, uint64_t len, pid_t pid, uint32_t crid) {
    int ret_val = 1;

    // Parse bus data and check non-null
    BUG_ON(!device);
    struct bus_drvdata *bus_data = device->pd;
    BUG_ON(!bus_data);

    // Iterate through all the entries of allocated buffers
    // Where the virtual address, PID and configuration ID (crid) match, trigger reconfig by writing to FPGA memory
    int cmd_sent = 0;
    struct reconfig_buff_metadata *tmp_buff;
    hash_for_each_possible(reconfig_buffs_map, tmp_buff, entry, virtual_address) {
        if (tmp_buff->vaddr == virtual_address && tmp_buff->pid == pid && tmp_buff->crid == crid) {
            // Bitsreams are always loaded to FPGA memory in buffers of hugepages
            uint64_t bitstream_page_size = bus_data->ltlb_order->page_size;

            uint64_t n_bistream_full_pages = len / bitstream_page_size;
            uint64_t partial_bitsream_size = len % bitstream_page_size;
            dbg_info(
                "reconfig bitstream: full pages %lld (hugepages), partial %lld B\n", 
                n_bistream_full_pages, partial_bitsream_size
            );

            // Write full pages, sequentially; but make sure not to over-saturate with writes (cmd_sent)
            for (int i = 0; i < n_bistream_full_pages; i++) {
                while(cmd_sent >= RECONFIG_THRESHOLD) {
                    cmd_sent = bus_data->fpga_stat_cnfg->reconfig_ctrl;
                    usleep_range(RECONFIG_MIN_SLEEP_CMD, RECONFIG_MAX_SLEEP_CMD);
                }

                bus_data->fpga_stat_cnfg->reconfig_addr_low = LOW_32(page_to_phys(tmp_buff->pages[i]));
                bus_data->fpga_stat_cnfg->reconfig_addr_high = HIGH_32(page_to_phys(tmp_buff->pages[i]));
                bus_data->fpga_stat_cnfg->reconfig_len = bitstream_page_size;
                if (partial_bitsream_size == 0 && i == n_bistream_full_pages - 1)
                    bus_data->fpga_stat_cnfg->reconfig_ctrl = RECONFIG_CTRL_START_LAST;
                else
                    bus_data->fpga_stat_cnfg->reconfig_ctrl = RECONFIG_CTRL_START_MIDDLE;

                // write memory barrier; ensuring writes remain in-order and not changed by compiler, processor etc.
                wmb();
                cmd_sent++;
            }

            // Write the last partial page
            if (partial_bitsream_size > 0) {
                while(cmd_sent >= RECONFIG_THRESHOLD) {
                    cmd_sent = bus_data->fpga_stat_cnfg->reconfig_ctrl;
                    usleep_range(RECONFIG_MIN_SLEEP_CMD, RECONFIG_MAX_SLEEP_CMD);
                }

                bus_data->fpga_stat_cnfg->reconfig_addr_low = LOW_32(page_to_phys(tmp_buff->pages[n_bistream_full_pages]));
                bus_data->fpga_stat_cnfg->reconfig_addr_high = HIGH_32(page_to_phys(tmp_buff->pages[n_bistream_full_pages]));
                bus_data->fpga_stat_cnfg->reconfig_len = partial_bitsream_size;
                bus_data->fpga_stat_cnfg->reconfig_ctrl = RECONFIG_CTRL_START_LAST;
                
                wmb();
                cmd_sent++;
            }

            ret_val = 0;
        }
    }

    return ret_val;
}