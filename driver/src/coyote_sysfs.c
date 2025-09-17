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

    dbg_info("coyote-sysfs:  current IP address: 0x%08x, port: %d\n", bus_data->net_ip_addr, bus_data->qsfp);
    return sprintf(buff, "IP address: %08x, port: %d\n", bus_data->net_ip_addr, bus_data->qsfp);
}

ssize_t cyt_attr_ip_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buff, size_t count) {
    struct bus_driver_data *bus_data = container_of(kobj, struct bus_driver_data, cyt_kobj);
    BUG_ON(!bus_data); 

    sscanf(buff,"%08x",&bus_data->net_ip_addr);
    dbg_info("coyote-sysfs:  setting IP address to: %08x, port %d\n", bus_data->net_ip_addr, bus_data->qsfp);
    bus_data->shell_cnfg->net_ip = bus_data->net_ip_addr;

    return count;
}

ssize_t cyt_attr_mac_show(struct kobject *kobj, struct kobj_attribute *attr, char *buff) {   
    struct bus_driver_data *bus_data = container_of(kobj, struct bus_driver_data, cyt_kobj);
    BUG_ON(!bus_data); 

    dbg_info("coyote-sysfs:  current MAC address: 0x%012llx, port: %d\n", bus_data->net_mac_addr, bus_data->qsfp);
    return sprintf(buff, "MAC address: %012llx, port: %d\n", bus_data->net_mac_addr, bus_data->qsfp);
}

ssize_t cyt_attr_mac_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buff, size_t count) {
    struct bus_driver_data *bus_data = container_of(kobj, struct bus_driver_data, cyt_kobj);
    BUG_ON(!bus_data); 

    sscanf(buff,"%012llx",&bus_data->net_mac_addr);
    dbg_info("coyote-sysfs:  setting MAC address to: %012llx, port: %d\n", bus_data->net_mac_addr, bus_data->qsfp);
    bus_data->shell_cnfg->net_mac = bus_data->net_mac_addr;

    return count;
}

ssize_t cyt_attr_eost_show(struct kobject *kobj, struct kobj_attribute *attr, char *buff) {   
    struct bus_driver_data *bus_data = container_of(kobj, struct bus_driver_data, cyt_kobj);
    BUG_ON(!bus_data); 

    dbg_info("coyote-sysfs:  current EOS time [clock cycles]: %lld\n", bus_data->eost);
    return sprintf(buff, "EOST: %lld\n", bus_data->eost);
}

ssize_t cyt_attr_eost_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buff, size_t count) {
    struct bus_driver_data *bus_data = container_of(kobj, struct bus_driver_data, cyt_kobj);
    BUG_ON(!bus_data); 

    sscanf(buff,"%lld",&bus_data->eost);
    dbg_info("coyote-sysfs:  setting EOST to: %lld clock cycles\n", bus_data->eost);
    bus_data->stat_cnfg->reconfig_eost = eost;

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

ssize_t cyt_attr_xstats_show(struct kobject *kobj, struct kobj_attribute *attr, char *buff) {   
    struct bus_driver_data *bus_data = container_of(kobj, struct bus_driver_data, cyt_kobj);
    BUG_ON(!bus_data);

    int sw = 0;
    sw += sprintf(buff, "\n -- \033[31m\e[1mDMA HOST STATS\033[0m\e[0m\n\n");
    if(bus_data->n_fpga_chan >= 1) {
        sw += sprintf(buff + strlen(buff), 
            "CHANNEL 0:\n"
            "request cnt H2C: %lld\n"
            "request cnt C2H: %lld\n"
            "completion cnt H2C: %lld\n"
            "completion cnt C2H: %lld\n"
            "beat cnt H2C: %lld\n"
            "beat cnt C2H: %lld\n",
            
            LOW_32 (bus_data->shell_cnfg->xdma_debug[0]),
            HIGH_32(bus_data->shell_cnfg->xdma_debug[0]),
            LOW_32 (bus_data->shell_cnfg->xdma_debug[1]),
            HIGH_32(bus_data->shell_cnfg->xdma_debug[1]),
            LOW_32 (bus_data->shell_cnfg->xdma_debug[2]),
            HIGH_32(bus_data->shell_cnfg->xdma_debug[2])
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
            
            LOW_32 (bus_data->shell_cnfg->xdma_debug[3]),
            HIGH_32(bus_data->shell_cnfg->xdma_debug[3]),
            LOW_32 (bus_data->shell_cnfg->xdma_debug[4]),
            HIGH_32(bus_data->shell_cnfg->xdma_debug[4]),
            LOW_32 (bus_data->shell_cnfg->xdma_debug[5]),
            HIGH_32(bus_data->shell_cnfg->xdma_debug[5])
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

        (bus_data->stat_cnfg->xdma_debug[0]),
        (bus_data->stat_cnfg->xdma_debug[1]),
        (bus_data->stat_cnfg->xdma_debug[2]),
        (bus_data->stat_cnfg->xdma_debug[3]),
        (bus_data->stat_cnfg->xdma_debug[4]),
        (bus_data->stat_cnfg->xdma_debug[5])
    );

    return sw;
}

ssize_t cyt_attr_engines_show(struct kobject *kobj, struct kobj_attribute *attr, char *buff) {   
    struct bus_driver_data *bus_data = container_of(kobj, struct bus_driver_data, cyt_kobj);
    BUG_ON(!bus_data); 

    int sw = 0;
    uint32_t val;
    sw += sprintf(buff, "\n -- \033[31m\e[1mENGINE STATUS\033[0m\e[0m\n\n");
    if(bus_data->n_fpga_chan >= 1) {
        val = ioread32(&bus_data->engine_h2c[0]->regs->status);
        sw += sprintf(buff, "chan 0 h2c: 0x%08x\n", val);
    }

    if(bus_data->n_fpga_chan >= 1) {
        val = ioread32(&bus_data->engine_c2h[0]->regs->status);
        sw += sprintf(buff + strlen(buff), "chan 0 c2h: 0x%08x\n", val);
    }

    if(bus_data->n_fpga_chan >= 2) {
        val = ioread32(&bus_data->engine_h2c[1]->regs->status);
        sw += sprintf(buff + strlen(buff), "chan 1 h2c: 0x%08x\n", val);
    }

    if(bus_data->n_fpga_chan >= 2) {
        val = ioread32(&bus_data->engine_c2h[1]->regs->status);
        sw += sprintf(buff + strlen(buff), "chan 1 c2h: 0x%08x\n", val);
    }

    if(bus_data->n_fpga_chan >= 3) {
        val = ioread32(&bus_data->engine_h2c[2]->regs->status);
        sw += sprintf(buff + strlen(buff), "chan 2 h2c: 0x%08x\n", val);
    }

    if(bus_data->n_fpga_chan >= 3) {
        val = ioread32(&bus_data->engine_c2h[2]->regs->status);
        sw += sprintf(buff + strlen(buff), "chan 2 c2h: 0x%08x\n", val);
    }

    return sw;
}

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


