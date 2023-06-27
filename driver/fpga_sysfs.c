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

/**
 * @brief Sysfs read IP QSFP0
 * 
 */
ssize_t cyt_attr_ip_q0_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {   
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
  BUG_ON(!pd); 

  pr_info("coyote-sysfs:  current IP address QSFP0: 0x%08x\n", pd->net_0_ip_addr);
  return sprintf(buf, "IP QSFP0: %08x\n", pd->net_0_ip_addr);
}

/**
 * @brief Sysfs write IP QSFP0
 * 
 */
ssize_t cyt_attr_ip_q0_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count) {
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
    BUG_ON(!pd); 

    sscanf(buf,"%08x",&pd->net_0_ip_addr);
    pr_info("coyote-sysfs:  setting IP address on QSFP0 to: %08x\n", pd->net_0_ip_addr);
    pd->fpga_stat_cnfg->net_0_ip = pd->net_0_ip_addr;

    return count;
}

/**
 * @brief Sysfs read IP QSFP1
 * 
 */
ssize_t cyt_attr_ip_q1_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {   
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
  BUG_ON(!pd); 

  pr_info("coyote-sysfs:  current IP address QSFP1: 0x%08x\n", pd->net_1_ip_addr);
  return sprintf(buf, "IP QSFP1: %08x\n", pd->net_1_ip_addr);
}

/**
 * @brief Sysfs write IP QSFP1
 * 
 */
ssize_t cyt_attr_ip_q1_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count) {
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
    BUG_ON(!pd); 

    sscanf(buf,"%08x",&pd->net_1_ip_addr);
    pr_info("coyote-sysfs:  setting IP address on QSFP1 to: %08x\n", pd->net_1_ip_addr);
    pd->fpga_stat_cnfg->net_1_ip = pd->net_1_ip_addr;

    return count;
}

/**
 * @brief Sysfs read MAC QSFP0
 * 
 */
ssize_t cyt_attr_mac_q0_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {   
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
  BUG_ON(!pd); 

  pr_info("coyote-sysfs:  current MAC address QSFP0: 0x%012llxx\n", pd->net_0_mac_addr);
  return sprintf(buf, "MAC QSFP0: %012llx\n", pd->net_0_mac_addr);
}

/**
 * @brief Sysfs write MAC QSFP0
 * 
 */
ssize_t cyt_attr_mac_q0_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count) {
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
    BUG_ON(!pd); 

    sscanf(buf,"%012llx",&pd->net_0_mac_addr);
    pr_info("coyote-sysfs:  setting MAC address on QSFP0 to: %012llx\n", pd->net_0_mac_addr);
    pd->fpga_stat_cnfg->net_0_mac = pd->net_0_mac_addr;

    return count;
}

/**
 * @brief Sysfs read MAC QSFP1
 * 
 */
ssize_t cyt_attr_mac_q1_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {   
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
  BUG_ON(!pd); 

  pr_info("coyote-sysfs:  current MAC address QSFP1: 0x%012llx\n", pd->net_1_mac_addr);
  return sprintf(buf, "MAC QSFP1: %012llx\n", pd->net_1_mac_addr);
}

/**
 * @brief Sysfs write IP QSFP1
 * 
 */
ssize_t cyt_attr_mac_q1_store(struct kobject *kobj, struct kobj_attribute *attr, const char *buf, size_t count) {
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
    BUG_ON(!pd); 

    sscanf(buf,"%012llx",&pd->net_1_mac_addr);
    pr_info("coyote-sysfs:  setting MAC address on QSFP1 to: %012llx\n", pd->net_1_mac_addr);
    pd->fpga_stat_cnfg->net_1_mac = pd->net_1_mac_addr;

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
 * @brief Sysfs write IP QSFP1
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
ssize_t cyt_attr_nstats_q0_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {   
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
  BUG_ON(!pd); 

  pr_info("coyote-sysfs:  net stats QSFP0\n");
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
    
    LOW_32 (pd->fpga_stat_cnfg->net_0_debug[0]),
    HIGH_32(pd->fpga_stat_cnfg->net_0_debug[0]),
    LOW_32 (pd->fpga_stat_cnfg->net_0_debug[1]),
    HIGH_32(pd->fpga_stat_cnfg->net_0_debug[1]),
    LOW_32 (pd->fpga_stat_cnfg->net_0_debug[2]),
    HIGH_32(pd->fpga_stat_cnfg->net_0_debug[2]),
    LOW_32 (pd->fpga_stat_cnfg->net_0_debug[3]),
    HIGH_32(pd->fpga_stat_cnfg->net_0_debug[3]),
    LOW_32 (pd->fpga_stat_cnfg->net_0_debug[4]),
    HIGH_32(pd->fpga_stat_cnfg->net_0_debug[4]),
    LOW_32 (pd->fpga_stat_cnfg->net_0_debug[5]),
    HIGH_32(pd->fpga_stat_cnfg->net_0_debug[5]),
    LOW_32 (pd->fpga_stat_cnfg->net_0_debug[6]),
    HIGH_32(pd->fpga_stat_cnfg->net_0_debug[6]),
    LOW_32 (pd->fpga_stat_cnfg->net_0_debug[7]),
    LOW_32 (pd->fpga_stat_cnfg->net_0_debug[8]) 
  );
}

/**
 * @brief Sysfs read net stats QSFP1
 * 
 */
ssize_t cyt_attr_nstats_q1_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {   
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
  BUG_ON(!pd); 

  pr_info("coyote-sysfs:  net stats QSFP1\n");
  return sprintf(buf, "\n -- \033[31m\e[1mNET STATS\033[0m\e[0m QSFP1\n\n"
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
    
    LOW_32 (pd->fpga_stat_cnfg->net_1_debug[0]),
    HIGH_32(pd->fpga_stat_cnfg->net_1_debug[0]),
    LOW_32 (pd->fpga_stat_cnfg->net_1_debug[1]),
    HIGH_32(pd->fpga_stat_cnfg->net_1_debug[1]),
    LOW_32 (pd->fpga_stat_cnfg->net_1_debug[2]),
    HIGH_32(pd->fpga_stat_cnfg->net_1_debug[2]),
    LOW_32 (pd->fpga_stat_cnfg->net_1_debug[3]),
    HIGH_32(pd->fpga_stat_cnfg->net_1_debug[3]),
    LOW_32 (pd->fpga_stat_cnfg->net_1_debug[4]),
    HIGH_32(pd->fpga_stat_cnfg->net_1_debug[4]),
    LOW_32 (pd->fpga_stat_cnfg->net_1_debug[5]),
    HIGH_32(pd->fpga_stat_cnfg->net_1_debug[5]),
    LOW_32 (pd->fpga_stat_cnfg->net_1_debug[6]),
    HIGH_32(pd->fpga_stat_cnfg->net_1_debug[6]),
    LOW_32 (pd->fpga_stat_cnfg->net_1_debug[7]),
    LOW_32 (pd->fpga_stat_cnfg->net_1_debug[8]) 
  );
}

/**
 * @brief Sysfs read xdma stats
 * 
 */
ssize_t cyt_attr_xstats_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf) {   
  struct bus_drvdata *pd = container_of(kobj, struct bus_drvdata, cyt_kobj);
  BUG_ON(!pd); 

  pr_info("coyote-sysfs:  xdma stats\n");
  return sprintf(buf, "\n -- \033[31m\e[1mXDMA STATS\033[0m\e[0m\n\n"
    "CHANNEL 0:\n"
    "request cnt H2C: %lld\n"
    "request cnt C2H: %lld\n"
    "completion cnt H2C: %lld\n"
    "completion cnt C2H: %lld\n"
    "beat cnt H2C: %lld\n"
    "beat cnt C2H: %lld\n"
    "CHANNEL 1:\n"
    "request cnt H2C: %lld\n"
    "request cnt C2H: %lld\n"
    "completion cnt H2C: %lld\n"
    "completion cnt C2H: %lld\n"
    "beat cnt H2C: %lld\n"
    "beat cnt C2H: %lld\n"
    "CHANNEL 2:\n"
    "request cnt H2C: %lld\n"
    "request cnt C2H: %lld\n"
    "completion cnt H2C: %lld\n"
    "completion cnt C2H: %lld\n"
    "beat cnt H2C: %lld\n"
    "beat cnt C2H: %lld\n"
    "CHANNEL 3:\n"
    "request cnt H2C: %lld\n"
    "request cnt C2H: %lld\n"
    "completion cnt H2C: %lld\n"
    "completion cnt C2H: %lld\n"
    "beat cnt H2C: %lld\n"
    "beat cnt C2H: %lld\n\n", 
    
    LOW_32 (pd->fpga_stat_cnfg->xdma_debug[0]),
    HIGH_32(pd->fpga_stat_cnfg->xdma_debug[0]),
    LOW_32 (pd->fpga_stat_cnfg->xdma_debug[1]),
    HIGH_32(pd->fpga_stat_cnfg->xdma_debug[1]),
    LOW_32 (pd->fpga_stat_cnfg->xdma_debug[2]),
    HIGH_32(pd->fpga_stat_cnfg->xdma_debug[2]),
    LOW_32 (pd->fpga_stat_cnfg->xdma_debug[3]),
    HIGH_32(pd->fpga_stat_cnfg->xdma_debug[3]),
    LOW_32 (pd->fpga_stat_cnfg->xdma_debug[4]),
    HIGH_32(pd->fpga_stat_cnfg->xdma_debug[4]),
    LOW_32 (pd->fpga_stat_cnfg->xdma_debug[5]),
    HIGH_32(pd->fpga_stat_cnfg->xdma_debug[5]),
    LOW_32 (pd->fpga_stat_cnfg->xdma_debug[6]),
    HIGH_32(pd->fpga_stat_cnfg->xdma_debug[6]),
    LOW_32 (pd->fpga_stat_cnfg->xdma_debug[7]),
    HIGH_32(pd->fpga_stat_cnfg->xdma_debug[7]),
    LOW_32 (pd->fpga_stat_cnfg->xdma_debug[8]),
    HIGH_32(pd->fpga_stat_cnfg->xdma_debug[8]),
    LOW_32 (pd->fpga_stat_cnfg->xdma_debug[9]),
    HIGH_32(pd->fpga_stat_cnfg->xdma_debug[9]),
    LOW_32 (pd->fpga_stat_cnfg->xdma_debug[10]),
    HIGH_32(pd->fpga_stat_cnfg->xdma_debug[10]),
    LOW_32 (pd->fpga_stat_cnfg->xdma_debug[11]),
    HIGH_32(pd->fpga_stat_cnfg->xdma_debug[11])
  );
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
    "probe ID: %08x\n"
    "number of channels: %d\n"
    "number of vFPGAs: %d\n"
    "enabled streams: %d\n"
    "enabled memory: %d\n"
    "enabled reconfiguration: %d\n"
    "enabled RDMA QSFP0: %d\n"
    "enabled RDMA QSFP1: %d\n"
    "enabled TCP/IP QSFP0: %d\n"
    "enabled TCP/IP QSFP1: %d\n"
    "enabled AVX: %d\n"
    "enabled bypass: %d\n"
    "enabled fast TLB: %d\n"
    "enabled writeback: %d\n"
    "tlb regular order: %d\n"
    "tlb regular assoc: %d\n"
    "tlb regular page size: %lld\n"
    "tlb hugepage order: %d\n"
    "tlb hugepage assoc: %d\n"
    "tlb hugepage page size: %lld\n\n",
    
    pd->probe,
    pd->n_fpga_chan,
    pd->n_fpga_reg,
    pd->en_strm,
    pd->en_mem,
    pd->en_pr,
    pd->en_rdma_0,
    pd->en_rdma_1,
    pd->en_tcp_0,
    pd->en_tcp_1,
    pd->en_avx,
    pd->en_bypass,
    pd->en_tlbf,
    pd->en_wb,
    pd->stlb_order->key_size,
    pd->stlb_order->assoc,
    pd->stlb_order->page_size,
    pd->ltlb_order->key_size,
    pd->ltlb_order->assoc,
    pd->ltlb_order->page_size
  );
}

