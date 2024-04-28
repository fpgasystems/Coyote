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

#include "fpga_sysfs.h"

/*
███████╗██╗   ██╗███████╗███████╗███████╗
██╔════╝╚██╗ ██╔╝██╔════╝██╔════╝██╔════╝
███████╗ ╚████╔╝ ███████╗█████╗  ███████╗
╚════██║  ╚██╔╝  ╚════██║██╔══╝  ╚════██║
███████║   ██║   ███████║██║     ███████║
╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚══════╝
*/ 

/**
 * @brief Sysfs read IP
 * 
 */
ssize_t cyt_attr_ip_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {   
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
  BUG_ON(!pd); 

  pr_info("coyote-sysfs:  current IP address: 0x%08x, port: %d\n", pd->net_ip_addr, pd->qsfp);
  return sprintf(buf, "IP address: %08x, port: %d\n", pd->net_ip_addr, pd->qsfp);
}

/**
 * @brief Sysfs write IP
 * 
 */
ssize_t cyt_attr_ip_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count) {
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
    BUG_ON(!pd); 

    sscanf(buf,"%08x",&pd->net_ip_addr);
    pr_info("coyote-sysfs:  setting IP address to: %08x, port %d\n", pd->net_ip_addr, pd->qsfp);
    pd->fpga_shell_cnfg->net_ip = pd->net_ip_addr;

    return count;
}

/**
 * @brief Sysfs read MAC
 * 
 */
ssize_t cyt_attr_mac_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {   
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
  BUG_ON(!pd); 

  pr_info("coyote-sysfs:  current MAC address: 0x%012llx, port: %d\n", pd->net_mac_addr, pd->qsfp);
  return sprintf(buf, "MAC address: %012llx, port: %d\n", pd->net_mac_addr, pd->qsfp);
}

/**
 * @brief Sysfs write MAC
 * 
 */
ssize_t cyt_attr_mac_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count) {
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
    BUG_ON(!pd); 

    sscanf(buf,"%012llx",&pd->net_mac_addr);
    pr_info("coyote-sysfs:  setting MAC address to: %012llx, port: %d\n", pd->net_mac_addr, pd->qsfp);
    pd->fpga_shell_cnfg->net_mac = pd->net_mac_addr;

    return count;
}

/**
 * @brief Sysfs read EOST 
 * 
 */
ssize_t cyt_attr_eost_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {   
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
  BUG_ON(!pd); 

  pr_info("coyote-sysfs:  current EOS time [clks]: %lld\n", pd->eost);
  return sprintf(buf, "EOST: %lld\n", pd->eost);
}

/**
 * @brief Sysfs write EOST
 * 
 */
ssize_t cyt_attr_eost_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count) {
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
    BUG_ON(!pd); 

    sscanf(buf,"%lld",&pd->eost);
    pr_info("coyote-sysfs:  setting EOST to: %lld\n", pd->eost);
    pd->fpga_stat_cnfg->pr_eost = eost;

    return count;
}


/**
 * @brief Sysfs read net stats QSFP0
 * 
 */
ssize_t cyt_attr_nstats_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {   
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
  BUG_ON(!pd); 

  pr_info("coyote-sysfs:  net stats\n");
  return sprintf(buf, "\n -- \033[31m\e[1mNET STATS\033[0m\e[0m QSFP0\n\n"
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
    
    LOW_32 (pd->fpga_shell_cnfg->net_debug[0]),
    HIGH_32(pd->fpga_shell_cnfg->net_debug[0]),
    LOW_32 (pd->fpga_shell_cnfg->net_debug[1]),
    HIGH_32(pd->fpga_shell_cnfg->net_debug[1]),
    LOW_32 (pd->fpga_shell_cnfg->net_debug[2]),
    HIGH_32(pd->fpga_shell_cnfg->net_debug[2]),
    LOW_32 (pd->fpga_shell_cnfg->net_debug[3]),
    HIGH_32(pd->fpga_shell_cnfg->net_debug[3]),
    LOW_32 (pd->fpga_shell_cnfg->net_debug[4]),
    HIGH_32(pd->fpga_shell_cnfg->net_debug[4]),
    LOW_32 (pd->fpga_shell_cnfg->net_debug[5]),
    HIGH_32(pd->fpga_shell_cnfg->net_debug[5]),
    LOW_32 (pd->fpga_shell_cnfg->net_debug[6]),
    HIGH_32(pd->fpga_shell_cnfg->net_debug[6]),
    LOW_32 (pd->fpga_shell_cnfg->net_debug[7]),
    LOW_32 (pd->fpga_shell_cnfg->net_debug[8]) 
  );
}

/**
 * @brief Sysfs read xdma stats
 * 
 */
ssize_t cyt_attr_xstats_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {   
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
  int sw = 0;

  BUG_ON(!pd); 

  pr_info("coyote-sysfs:  xdma stats\n");
  sw += sprintf(buf, "\n -- \033[31m\e[1mDMA HOST STATS\033[0m\e[0m\n\n");
  if(pd->n_fpga_chan >= 1) {
    sw += sprintf(buf + strlen(buf), 
        "CHANNEL 0:\n"
        "request cnt H2C: %lld\n"
        "request cnt C2H: %lld\n"
        "completion cnt H2C: %lld\n"
        "completion cnt C2H: %lld\n"
        "beat cnt H2C: %lld\n"
        "beat cnt C2H: %lld\n",
        
        LOW_32 (pd->fpga_shell_cnfg->xdma_debug[0]),
        HIGH_32(pd->fpga_shell_cnfg->xdma_debug[0]),
        LOW_32 (pd->fpga_shell_cnfg->xdma_debug[1]),
        HIGH_32(pd->fpga_shell_cnfg->xdma_debug[1]),
        LOW_32 (pd->fpga_shell_cnfg->xdma_debug[2]),
        HIGH_32(pd->fpga_shell_cnfg->xdma_debug[2])
    );
  }
  if(pd->n_fpga_chan >= 2) {
    sw += sprintf(buf + strlen(buf), 
        "CHANNEL 1:\n"
        "request cnt H2C: %lld\n"
        "request cnt C2H: %lld\n"
        "completion cnt H2C: %lld\n"
        "completion cnt C2H: %lld\n"
        "beat cnt H2C: %lld\n"
        "beat cnt C2H: %lld\n",
        
        LOW_32 (pd->fpga_shell_cnfg->xdma_debug[3]),
        HIGH_32(pd->fpga_shell_cnfg->xdma_debug[3]),
        LOW_32 (pd->fpga_shell_cnfg->xdma_debug[4]),
        HIGH_32(pd->fpga_shell_cnfg->xdma_debug[4]),
        LOW_32 (pd->fpga_shell_cnfg->xdma_debug[5]),
        HIGH_32(pd->fpga_shell_cnfg->xdma_debug[5])
    );
  }

  return sw;
}

/**
 * @brief Sysfs read prstats
 * 
 */
ssize_t cyt_attr_prstats_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {   
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
  int sw = 0;

  BUG_ON(!pd); 

  pr_info("coyote-sysfs:  pr stats\n");
  sw += sprintf(buf, "\n -- \033[31m\e[1mDMA PR STATS\033[0m\e[0m\n\n");
  sw += sprintf(buf + strlen(buf), 
    "CHANNEL 2:\n"
    "request cnt H2C: %d\n"
    "request cnt C2H: %d\n"
    "completion cnt H2C: %d\n"
    "completion cnt C2H: %d\n"
    "beat cnt H2C: %d\n"
    "beat cnt C2H: %d\n",

    (pd->fpga_stat_cnfg->xdma_debug[0]),
    (pd->fpga_stat_cnfg->xdma_debug[1]),
    (pd->fpga_stat_cnfg->xdma_debug[2]),
    (pd->fpga_stat_cnfg->xdma_debug[3]),
    (pd->fpga_stat_cnfg->xdma_debug[4]),
    (pd->fpga_stat_cnfg->xdma_debug[5])
  );
  return sw;
}

/**
 * @brief Sysfs read engine status
 * 
 */
ssize_t cyt_attr_engines_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {   
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
  uint32_t val;
  int sw = 0;

  BUG_ON(!pd); 

  pr_info("coyote-sysfs:  engine status\n");
  sw += sprintf(buf, "\n -- \033[31m\e[1mENGINE STATUS\033[0m\e[0m\n\n");
  if(pd->n_fpga_chan >= 1) {
    val = ioread32(&pd->engine_h2c[0]->regs->status);
    sw += sprintf(buf, "chan 0 h2c: 0x%08x\n", val);
  }

  if(pd->n_fpga_chan >= 1) {
    val = ioread32(&pd->engine_c2h[0]->regs->status);
    sw += sprintf(buf + strlen(buf), "chan 0 c2h: 0x%08x\n", val);
  }

  if(pd->n_fpga_chan >= 2) {
    val = ioread32(&pd->engine_h2c[1]->regs->status);
    sw += sprintf(buf + strlen(buf), "chan 1 h2c: 0x%08x\n", val);
  }

  if(pd->n_fpga_chan >= 2) {
    val = ioread32(&pd->engine_c2h[1]->regs->status);
    sw += sprintf(buf + strlen(buf), "chan 1 c2h: 0x%08x\n", val);
  }

  if(pd->n_fpga_chan >= 3) {
    val = ioread32(&pd->engine_h2c[2]->regs->status);
    sw += sprintf(buf + strlen(buf), "chan 2 h2c: 0x%08x\n", val);
  }

  if(pd->n_fpga_chan >= 3) {
    val = ioread32(&pd->engine_c2h[2]->regs->status);
    sw += sprintf(buf + strlen(buf), "chan 2 c2h: 0x%08x\n", val);
  }

  return sw;
}

/**
 * @brief Sysfs read config
 * 
 */
ssize_t cyt_attr_cnfg_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {   
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
  BUG_ON(!pd); 

  pr_info("coyote-sysfs:  config\n");
  return sprintf(buf, "\n -- \033[31m\e[1mCONFIG\033[0m\e[0m\n\n"
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
    
    pd->probe_shell,
    pd->n_fpga_chan,
    pd->n_fpga_reg,
    pd->en_strm,
    pd->en_mem,
    pd->en_pr,
    pd->en_rdma,
    pd->en_tcp,
    pd->en_avx,
    pd->en_wb,
    pd->stlb_order->key_size,
    pd->stlb_order->assoc,
    pd->stlb_order->page_size,
    pd->ltlb_order->key_size,
    pd->ltlb_order->assoc,
    pd->ltlb_order->page_size
  );
}


