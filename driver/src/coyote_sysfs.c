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

#include "coyote_sysfs.h"

ssize_t cyt_attr_ip_show(struct kobject *kobj, struct kobj_attribute *attr, char *buff) {   
    struct bus_driver_data *bus_data = container_of(kobj, struct bus_driver_data, cyt_kobj);
    BUG_ON(!bus_data); 

    shell_info(bus_data, "current IP address: 0x%08x, port: %d\n", bus_data->net_ip_addr, bus_data->qsfp);
    return sprintf(buff, "IP address: %08x, port: %d\n", bus_data->net_ip_addr, bus_data->qsfp);
}

ssize_t cyt_attr_ip_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buff, size_t count) {
    struct bus_driver_data *bus_data = container_of(kobj, struct bus_driver_data, cyt_kobj);
    BUG_ON(!bus_data); 

    u32 ip;
    int ret_val = kstrtou32(buff, 16, &ip);
    if (ret_val) {
        shell_warn_ratelimited(bus_data, "invalid IP address, expected up to 8 hex digits\n");
        return ret_val;
    }
    bus_data->net_ip_addr = ip;
    shell_info(bus_data, "setting IP address to: %08x, port %d\n", bus_data->net_ip_addr, bus_data->qsfp);
    bus_data->shell_cnfg->net_ip = bus_data->net_ip_addr;

    return count;
}

ssize_t cyt_attr_mac_show(struct kobject *kobj, struct kobj_attribute *attr, char *buff) {   
    struct bus_driver_data *bus_data = container_of(kobj, struct bus_driver_data, cyt_kobj);
    BUG_ON(!bus_data); 

    shell_info(bus_data, "current MAC address: 0x%012llx, port: %d\n", bus_data->net_mac_addr, bus_data->qsfp);
    return sprintf(buff, "MAC address: %012llx, port: %d\n", bus_data->net_mac_addr, bus_data->qsfp);
}

ssize_t cyt_attr_mac_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buff, size_t count) {
    struct bus_driver_data *bus_data = container_of(kobj, struct bus_driver_data, cyt_kobj);
    BUG_ON(!bus_data); 

    u64 mac;
    int ret_val = kstrtou64(buff, 16, &mac);
    if (ret_val || mac >> 48) {
        shell_warn_ratelimited(bus_data, "invalid MAC address, expected up to 12 hex digits\n");
        return ret_val ? ret_val : -EINVAL;
    }
    bus_data->net_mac_addr = mac;
    shell_info(bus_data, "setting MAC address to: %012llx, port: %d\n", bus_data->net_mac_addr, bus_data->qsfp);
    bus_data->shell_cnfg->net_mac = bus_data->net_mac_addr;

    return count;
}

ssize_t cyt_attr_eost_show(struct kobject *kobj, struct kobj_attribute *attr, char *buff) {   
    struct bus_driver_data *bus_data = container_of(kobj, struct bus_driver_data, cyt_kobj);
    BUG_ON(!bus_data); 

    shell_info(bus_data, "current EOS time [clock cycles]: %lld\n", bus_data->eost);
    return sprintf(buff, "EOST: %lld\n", bus_data->eost);
}

ssize_t cyt_attr_eost_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buff, size_t count) {
    struct bus_driver_data *bus_data = container_of(kobj, struct bus_driver_data, cyt_kobj);
    BUG_ON(!bus_data); 

    u64 val;
    int ret_val = kstrtou64(buff, 10, &val);
    if (ret_val) {
        shell_warn_ratelimited(bus_data, "invalid EOST, expected a number of clock cycles\n");
        return ret_val;
    }
    bus_data->eost = val;
    shell_info(bus_data, "setting EOST to: %lld clock cycles\n", bus_data->eost);
    bus_data->stat_cnfg->reconfig_eost = bus_data->eost;

    return count;
}

ssize_t cyt_attr_nstats_show(struct kobject *kobj, struct kobj_attribute *attr, char *buff) {   
    struct bus_driver_data *bus_data = container_of(kobj, struct bus_driver_data, cyt_kobj);
    BUG_ON(!bus_data); 

    return sprintf(buff, "\n -- \033[31m\e[1mNET STATS\033[0m\e[0m QSFP0\n\n"
        "RX pkgs: %lld\n"
        "TX pkgs: %lld\n"
        "ARP RX pkgs: %lld\n"
        "ARP TX pkgs: %lld\n"
        "ICMP RX pkgs: %lld\n"
        "ICMP TX pkgs: %lld\n"
        "TCP RX pkgs: %lld\n"
        "TCP TX pkgs: %lld\n"
        "ROCE RX pkgs: %lld\n"
        "ROCE TX pkgs: %lld\n"
        "IBV RX pkgs: %lld\n"
        "IBV TX pkgs: %lld\n"
        "PSN drop cnt: %lld\n"
        "Retrans cnt: %lld\n"
        "TCP session cnt: %lld\n"
        "STRM down: %lld\n\n", 
        
        LOW_32 (bus_data->shell_cnfg->net_debug[0]),
        HIGH_32(bus_data->shell_cnfg->net_debug[0]),
        LOW_32 (bus_data->shell_cnfg->net_debug[1]),
        HIGH_32(bus_data->shell_cnfg->net_debug[1]),
        LOW_32 (bus_data->shell_cnfg->net_debug[2]),
        HIGH_32(bus_data->shell_cnfg->net_debug[2]),
        LOW_32 (bus_data->shell_cnfg->net_debug[3]),
        HIGH_32(bus_data->shell_cnfg->net_debug[3]),
        LOW_32 (bus_data->shell_cnfg->net_debug[4]),
        HIGH_32(bus_data->shell_cnfg->net_debug[4]),
        LOW_32 (bus_data->shell_cnfg->net_debug[5]),
        HIGH_32(bus_data->shell_cnfg->net_debug[5]),
        LOW_32 (bus_data->shell_cnfg->net_debug[6]),
        HIGH_32(bus_data->shell_cnfg->net_debug[6]),
        LOW_32 (bus_data->shell_cnfg->net_debug[7]),
        LOW_32 (bus_data->shell_cnfg->net_debug[8]) 
    );
}

ssize_t cyt_attr_hstats_show(struct kobject *kobj, struct kobj_attribute *attr, char *buff) {   
    struct bus_driver_data *bus_data = container_of(kobj, struct bus_driver_data, cyt_kobj);
    BUG_ON(!bus_data);

    int sw = 0;
    sw += sprintf(buff, "\n -- \033[31m\e[1mHOST DMA STATS\033[0m\e[0m\n\n");
    if(bus_data->n_fpga_chan >= 1) {
        sw += sprintf(buff + strlen(buff), 
            "CHANNEL 0:\n"
            "request cnt H2C: %lld\n"
            "request cnt C2H: %lld\n"
            "completion cnt H2C: %lld\n"
            "completion cnt C2H: %lld\n"
            "beat cnt H2C: %lld\n"
            "beat cnt C2H: %lld\n",
            
            LOW_32 (bus_data->shell_cnfg->hdma_debug[0]),
            HIGH_32(bus_data->shell_cnfg->hdma_debug[0]),
            LOW_32 (bus_data->shell_cnfg->hdma_debug[1]),
            HIGH_32(bus_data->shell_cnfg->hdma_debug[1]),
            LOW_32 (bus_data->shell_cnfg->hdma_debug[2]),
            HIGH_32(bus_data->shell_cnfg->hdma_debug[2])
        );
    }
    if(bus_data->n_fpga_chan >= 2) {
        sw += sprintf(buff + strlen(buff), 
            "CHANNEL 1:\n"
            "request cnt H2C: %lld\n"
            "request cnt C2H: %lld\n"
            "completion cnt H2C: %lld\n"
            "completion cnt C2H: %lld\n"
            "beat cnt H2C: %lld\n"
            "beat cnt C2H: %lld\n",
            
            LOW_32 (bus_data->shell_cnfg->hdma_debug[3]),
            HIGH_32(bus_data->shell_cnfg->hdma_debug[3]),
            LOW_32 (bus_data->shell_cnfg->hdma_debug[4]),
            HIGH_32(bus_data->shell_cnfg->hdma_debug[4]),
            LOW_32 (bus_data->shell_cnfg->hdma_debug[5]),
            HIGH_32(bus_data->shell_cnfg->hdma_debug[5])
        );
    }

    return sw;
}

ssize_t cyt_attr_prstats_show(struct kobject *kobj, struct kobj_attribute *attr, char *buff) {   
    struct bus_driver_data *bus_data = container_of(kobj, struct bus_driver_data, cyt_kobj);
    BUG_ON(!bus_data); 

    int sw = 0;
    sw += sprintf(buff, "\n -- \033[31m\e[1mDMA PR STATS\033[0m\e[0m\n\n");
    sw += sprintf(buff + strlen(buff), 
        "CHANNEL 2:\n"
        "request cnt H2C: %d\n"
        "request cnt C2H: %d\n"
        "completion cnt H2C: %d\n"
        "completion cnt C2H: %d\n"
        "beat cnt H2C: %d\n"
        "beat cnt C2H: %d\n",

        (bus_data->stat_cnfg->hdma_debug[0]),
        (bus_data->stat_cnfg->hdma_debug[1]),
        (bus_data->stat_cnfg->hdma_debug[2]),
        (bus_data->stat_cnfg->hdma_debug[3]),
        (bus_data->stat_cnfg->hdma_debug[4]),
        (bus_data->stat_cnfg->hdma_debug[5])
    );

    #ifdef PLATFORM_VERSAL
    sw += sprintf(
        buff + strlen(buff), 
        "On Versal devices, PR data goes fully through the NoC.\n"
        "As such, it's not possible to monitor the number of data beats in the pr_stats module.\n"
        "Hence, beatch count H2C is always 0.\n\n"
    );
    #endif

    return sw;
}

#ifdef PLATFORM_ULTRASCALE_PLUS
ssize_t cyt_attr_engines_show(struct kobject *kobj, struct kobj_attribute *attr, char *buff) {   
    struct bus_driver_data *bus_data = container_of(kobj, struct bus_driver_data, cyt_kobj);
    BUG_ON(!bus_data); 

    int sw = 0;
    uint32_t val;
    sw += sprintf(buff, "\n -- \033[31m\e[1mENGINE STATUS\033[0m\e[0m\n\n");
    for (int i = 0; i < bus_data->n_fpga_chan; i++) {
        if (bus_data->engine_h2c[i]) {
            val = ioread32(&bus_data->engine_h2c[i]->regs->status);
            sw += sprintf(buff + sw, "chan %d h2c: 0x%08x\n", i, val);
        }
        if (bus_data->engine_c2h[i]) {
            val = ioread32(&bus_data->engine_c2h[i]->regs->status);
            sw += sprintf(buff + sw, "chan %d c2h: 0x%08x\n", i, val);
        }
    }

    return sw;
}
#endif

ssize_t cyt_attr_cnfg_show(struct kobject *kobj, struct kobj_attribute *attr, char *buff) {   
    struct bus_driver_data *bus_data = container_of(kobj, struct bus_driver_data, cyt_kobj);
    BUG_ON(!bus_data); 

    return sprintf(buff, "\n -- \033[31m\e[1mCONFIG\033[0m\e[0m\n\n"
        "probe shell ID: %08x\n"
        "number of channels: %d\n"
        "number of vFPGAs: %d\n"
        "enabled streams: %d\n"
        "enabled memory: %d\n"
        "enabled dynamic reconfiguration: %d\n"
        "enabled RDMA: %d\n"
        "enabled TCP/IP: %d\n"
        "enabled AVX: %d\n"
        "enabled writeback: %d\n"
        "tlb regular order: %lld\n"
        "tlb regular assoc: %d\n"
        "tlb regular page size: %lld\n"
        "tlb hugepage order: %lld\n"
        "tlb hugepage assoc: %d\n"
        "tlb hugepage page size: %lld\n\n",
        
        bus_data->probe_shell,
        bus_data->n_fpga_chan,
        bus_data->n_fpga_reg,
        bus_data->en_strm,
        bus_data->en_mem,
        bus_data->en_pr,
        bus_data->en_rdma,
        bus_data->en_tcp,
        bus_data->en_avx,
        bus_data->en_wb,
        bus_data->stlb_meta->key_size,
        bus_data->stlb_meta->assoc,
        bus_data->stlb_meta->page_size,
        bus_data->ltlb_meta->key_size,
        bus_data->ltlb_meta->assoc,
        bus_data->ltlb_meta->page_size
    );
}

#ifdef PLATFORM_VERSAL
ssize_t cyt_attr_qdma_debug_regs_show(struct kobject *kobj, struct kobj_attribute *attr, char *buff) {   
    struct bus_driver_data *bus_data = container_of(kobj, struct bus_driver_data, cyt_kobj);
    BUG_ON(!bus_data); 

    return sprintf(buff, "\n -- \033[31m\e[1mQDMA DEBUG REGISTERS\033[0m\e[0m\n\n"
        "QDMA_C2H_ERR_STAT (0xAF0): 0x%x\n"
        "QDMA_C2H_FATAL_ERR_STAT (0xAF8): 0x%x\n"
        "QDMA_RAM_SBE_STS_A (0xF4): 0x%x\n"
        "QDMA_RAM_DBE_STS_A (0xFC): 0x%x\n"
        "QDMA_C2H_MM_Error_Code (0x1058): 0x%x\n"
        "QDMA_H2C_MM_Error_Code (0x1258): 0x%x\n"
        "QDMA_GLBL_TRQ_ERR_STS (0x264): 0x%x\n"
        "QDMA_GLBL_DSC_ERR_STS (0x254): 0x%x\n"
        "QDMA_GLBL_ERR_STAT (0x248): 0x%x\n"
        "QDMA_FAB_THR_LOG (0x314): 0x%x\n\n",

        ioread32(bus_data->bar[BAR_DMA_CONFIG] + 0xAF0),
        ioread32(bus_data->bar[BAR_DMA_CONFIG] + 0xAF8),
        ioread32(bus_data->bar[BAR_DMA_CONFIG] + 0xF4),
        ioread32(bus_data->bar[BAR_DMA_CONFIG] + 0xFC),
        ioread32(bus_data->bar[BAR_DMA_CONFIG] + 0x1058),
        ioread32(bus_data->bar[BAR_DMA_CONFIG] + 0x1258),
        ioread32(bus_data->bar[BAR_DMA_CONFIG] + 0x264),
        ioread32(bus_data->bar[BAR_DMA_CONFIG] + 0x254),
        ioread32(bus_data->bar[BAR_DMA_CONFIG] + 0x248),
        ioread32(bus_data->bar[BAR_DMA_CONFIG] + 0x314)
    );
}
#endif
