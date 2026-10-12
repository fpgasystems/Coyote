######################################################################################
# This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
#
# MIT Licence
# Copyright (c) 2021-2026, Systems Group, ETH Zurich
# All rights reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
######################################################################################

##
## NVMe infrastructure IP instantiation
##

# Buffer NVMe-to-HBM write data independently of the stripe mapper's AW
# expansion latency. The stripe still regenerates physical WLAST at each
# 1 KiB fragment boundary.
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_nvme_w
set_property -dict [list \
    CONFIG.TDATA_NUM_BYTES {64} \
    CONFIG.FIFO_DEPTH {32} \
    CONFIG.HAS_TSTRB {1} \
    CONFIG.HAS_TLAST {1} \
] [get_ips axis_data_fifo_nvme_w]

# ============================================================================
# AXI BRAM Controllers
# ============================================================================

# 16 devices. The SSD-visible windows are fixed for every depth (SQ 16 KiB and
# PRP 1 MiB per device); nvme_sq_ctrl and nvme_prp_ctrl compact addresses ahead
# of the controllers to physical storage: one 64-byte SQE per configured entry,
# and 32 64-bit PRP entries per 4-KiB SSD-visible page.
set nvme_prp_mem_depth [expr {16 * $cfg(nvme_queue_depth) * 32}]
set nvme_sq_mem_depth [expr {16 * $cfg(nvme_queue_depth)}]
set nvme_queue_bits [expr {int(log($cfg(nvme_queue_depth))/log(2))}]

# PRP BRAM controller — 64-bit data, single port, AXI4, 1-cycle BRAM latency
create_ip -name axi_bram_ctrl -vendor xilinx.com -library ip -version 4.1 -module_name nvme_prp_axi_bram_ctrl
set_property -dict [list CONFIG.DATA_WIDTH {64} CONFIG.SINGLE_PORT_BRAM {1} CONFIG.PROTOCOL {AXI4} CONFIG.READ_LATENCY {1} CONFIG.MEM_DEPTH $nvme_prp_mem_depth ] [get_ips nvme_prp_axi_bram_ctrl]

# SQ BRAM controller — 512-bit data, single port, AXI4, 2-cycle BRAM latency
create_ip -name axi_bram_ctrl -vendor xilinx.com -library ip -version 4.1 -module_name nvme_sq_axi_bram_ctrl
set_property -dict [list CONFIG.DATA_WIDTH {512} CONFIG.SINGLE_PORT_BRAM {1} CONFIG.PROTOCOL {AXI4} CONFIG.READ_LATENCY {2} CONFIG.MEM_DEPTH $nvme_sq_mem_depth ] [get_ips nvme_sq_axi_bram_ctrl]

# CQ BRAM controller — 128-bit data, single port, AXI4
create_ip -name axi_bram_ctrl -vendor xilinx.com -library ip -version 4.1 -module_name nvme_cq_axi_bram_ctrl
set_property -dict [list CONFIG.DATA_WIDTH {128} CONFIG.SINGLE_PORT_BRAM {1} CONFIG.PROTOCOL {AXI4} CONFIG.MEM_DEPTH {4096} ] [get_ips nvme_cq_axi_bram_ctrl]

# ============================================================================
# ILA Debug Cores (instantiated only when EN_ILA_NVME_* defines are active)
# ============================================================================

# These legacy ILA 6.2 definitions are not available for the V80 part. Their
# corresponding RTL instantiations are all disabled by default, so omit the IP
# definitions only for the PL-connected flow. The existing UltraScale+/HOST
# project continues to create exactly the same optional debug cores as before.
if {$cfg(en_nvme_host) eq 1} {

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_nvme_top
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {34} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {1}  CONFIG.C_PROBE1_WIDTH {1}  CONFIG.C_PROBE2_WIDTH {4} \
    CONFIG.C_PROBE3_WIDTH {48} CONFIG.C_PROBE4_WIDTH {28} CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE6_WIDTH {4}  CONFIG.C_PROBE7_WIDTH {1}  CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {16} CONFIG.C_PROBE10_WIDTH {1} CONFIG.C_PROBE11_WIDTH {1} \
    CONFIG.C_PROBE12_WIDTH {4} CONFIG.C_PROBE13_WIDTH {15} CONFIG.C_PROBE14_WIDTH {1} \
    CONFIG.C_PROBE15_WIDTH {1} CONFIG.C_PROBE16_WIDTH {1} CONFIG.C_PROBE17_WIDTH {1} \
    CONFIG.C_PROBE18_WIDTH {1} CONFIG.C_PROBE19_WIDTH {16} CONFIG.C_PROBE20_WIDTH {1} \
    CONFIG.C_PROBE21_WIDTH {1} CONFIG.C_PROBE22_WIDTH {1} CONFIG.C_PROBE23_WIDTH {1} \
    CONFIG.C_PROBE24_WIDTH {1} CONFIG.C_PROBE25_WIDTH {1} CONFIG.C_PROBE26_WIDTH {1} \
    CONFIG.C_PROBE27_WIDTH {1} CONFIG.C_PROBE28_WIDTH {1} CONFIG.C_PROBE29_WIDTH {1} \
    CONFIG.C_PROBE30_WIDTH {1} CONFIG.C_PROBE31_WIDTH {1} CONFIG.C_PROBE32_WIDTH {1} \
    CONFIG.C_PROBE33_WIDTH {1} \
] [get_ips ila_nvme_top]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_nvme_s0
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {9} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_PROBE1_WIDTH {1} CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} CONFIG.C_PROBE4_WIDTH {4} CONFIG.C_PROBE5_WIDTH {4} \
    CONFIG.C_PROBE6_WIDTH {1} CONFIG.C_PROBE7_WIDTH {1} CONFIG.C_PROBE8_WIDTH {2} \
] [get_ips ila_nvme_s0]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_nvme_s1
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {17} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_PROBE1_WIDTH {1} CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} CONFIG.C_PROBE4_WIDTH {16} CONFIG.C_PROBE5_WIDTH {64} \
    CONFIG.C_PROBE6_WIDTH {1} CONFIG.C_PROBE7_WIDTH {1} CONFIG.C_PROBE8_WIDTH {16} \
    CONFIG.C_PROBE9_WIDTH {1} CONFIG.C_PROBE10_WIDTH {1} CONFIG.C_PROBE11_WIDTH {1} \
    CONFIG.C_PROBE12_WIDTH {1} CONFIG.C_PROBE13_WIDTH {64} CONFIG.C_PROBE14_WIDTH {3} \
    CONFIG.C_PROBE15_WIDTH {1} CONFIG.C_PROBE16_WIDTH {1} \
] [get_ips ila_nvme_s1]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_nvme_s2
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {13} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_PROBE1_WIDTH {1} CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} CONFIG.C_PROBE4_WIDTH {1} CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE6_WIDTH {4} CONFIG.C_PROBE7_WIDTH {64} CONFIG.C_PROBE8_WIDTH {16} \
    CONFIG.C_PROBE9_WIDTH {1} CONFIG.C_PROBE10_WIDTH {1} CONFIG.C_PROBE11_WIDTH {64} \
    CONFIG.C_PROBE12_WIDTH {3} \
] [get_ips ila_nvme_s2]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_nvme_info_table
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {24} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_PROBE1_WIDTH {1} CONFIG.C_PROBE2_WIDTH {4} \
    CONFIG.C_PROBE3_WIDTH {4} CONFIG.C_PROBE4_WIDTH {48} CONFIG.C_PROBE5_WIDTH {28} \
    CONFIG.C_PROBE6_WIDTH {1} CONFIG.C_PROBE7_WIDTH {1} CONFIG.C_PROBE8_WIDTH {16} \
    CONFIG.C_PROBE9_WIDTH {64} CONFIG.C_PROBE10_WIDTH $nvme_queue_bits CONFIG.C_PROBE11_WIDTH {1} \
    CONFIG.C_PROBE12_WIDTH {1} CONFIG.C_PROBE13_WIDTH {4} CONFIG.C_PROBE14_WIDTH $nvme_queue_bits \
    CONFIG.C_PROBE15_WIDTH {1} CONFIG.C_PROBE16_WIDTH {1} CONFIG.C_PROBE17_WIDTH {4} \
    CONFIG.C_PROBE18_WIDTH {1} CONFIG.C_PROBE19_WIDTH {1} CONFIG.C_PROBE20_WIDTH {4} \
    CONFIG.C_PROBE21_WIDTH {4} CONFIG.C_PROBE22_WIDTH {1} CONFIG.C_PROBE23_WIDTH {1} \
] [get_ips ila_nvme_info_table]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_nvme_manage_prp
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {16} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_PROBE1_WIDTH {1} CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} CONFIG.C_PROBE4_WIDTH {64} CONFIG.C_PROBE5_WIDTH {64} \
    CONFIG.C_PROBE6_WIDTH {1} CONFIG.C_PROBE7_WIDTH {1} CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {1} CONFIG.C_PROBE10_WIDTH {48} CONFIG.C_PROBE11_WIDTH {1} \
    CONFIG.C_PROBE12_WIDTH {1} CONFIG.C_PROBE13_WIDTH {1} CONFIG.C_PROBE14_WIDTH {4} \
    CONFIG.C_PROBE15_WIDTH {64} \
] [get_ips ila_nvme_manage_prp]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_nvme_cnfg_slave
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {17} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_PROBE1_WIDTH {1} CONFIG.C_PROBE2_WIDTH {64} \
    CONFIG.C_PROBE3_WIDTH {1} CONFIG.C_PROBE4_WIDTH {1} CONFIG.C_PROBE5_WIDTH {32} \
    CONFIG.C_PROBE6_WIDTH {1} CONFIG.C_PROBE7_WIDTH {1} CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {1} CONFIG.C_PROBE10_WIDTH {4} CONFIG.C_PROBE11_WIDTH {1} \
    CONFIG.C_PROBE12_WIDTH {1} CONFIG.C_PROBE13_WIDTH {4} CONFIG.C_PROBE14_WIDTH {4} \
    CONFIG.C_PROBE15_WIDTH {1} CONFIG.C_PROBE16_WIDTH {64} \
] [get_ips ila_nvme_cnfg_slave]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_nvme_sq_ctrl
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {16} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_PROBE1_WIDTH {1} CONFIG.C_PROBE2_WIDTH {4} \
    CONFIG.C_PROBE3_WIDTH [expr {4 + $nvme_queue_bits}] CONFIG.C_PROBE4_WIDTH {1} CONFIG.C_PROBE5_WIDTH [expr {4 + $nvme_queue_bits}] \
    CONFIG.C_PROBE6_WIDTH {1} CONFIG.C_PROBE7_WIDTH [expr {4 + $nvme_queue_bits}] CONFIG.C_PROBE8_WIDTH [expr {4 + $nvme_queue_bits}] \
    CONFIG.C_PROBE9_WIDTH {32} CONFIG.C_PROBE10_WIDTH {32} CONFIG.C_PROBE11_WIDTH {32} \
    CONFIG.C_PROBE12_WIDTH {32} CONFIG.C_PROBE13_WIDTH {32} CONFIG.C_PROBE14_WIDTH {32} \
    CONFIG.C_PROBE15_WIDTH {32} \
] [get_ips ila_nvme_sq_ctrl]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_nvme_cq_ctrl
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {18} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_PROBE1_WIDTH {4} CONFIG.C_PROBE2_WIDTH {16} \
    CONFIG.C_PROBE3_WIDTH {1} CONFIG.C_PROBE4_WIDTH {1} CONFIG.C_PROBE5_WIDTH {4} \
    CONFIG.C_PROBE6_WIDTH {15} CONFIG.C_PROBE7_WIDTH {1} CONFIG.C_PROBE8_WIDTH {3} \
    CONFIG.C_PROBE9_WIDTH {4} CONFIG.C_PROBE10_WIDTH $nvme_queue_bits CONFIG.C_PROBE11_WIDTH {8} \
    CONFIG.C_PROBE12_WIDTH {64} CONFIG.C_PROBE13_WIDTH {64} \
    CONFIG.C_PROBE14_WIDTH $nvme_queue_bits CONFIG.C_PROBE15_WIDTH {16} \
    CONFIG.C_PROBE16_WIDTH {16} CONFIG.C_PROBE17_WIDTH {1} \
] [get_ips ila_nvme_cq_ctrl]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_nvme_prp_ctrl
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {19} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_PROBE1_WIDTH {1} CONFIG.C_PROBE2_WIDTH [expr {9 + $nvme_queue_bits}] \
    CONFIG.C_PROBE3_WIDTH {32} CONFIG.C_PROBE4_WIDTH {1} CONFIG.C_PROBE5_WIDTH [expr {9 + $nvme_queue_bits}] \
    CONFIG.C_PROBE6_WIDTH {32} CONFIG.C_PROBE7_WIDTH {1} CONFIG.C_PROBE8_WIDTH [expr {12 + $nvme_queue_bits}] \
    CONFIG.C_PROBE9_WIDTH [expr {9 + $nvme_queue_bits}] CONFIG.C_PROBE10_WIDTH {32} CONFIG.C_PROBE11_WIDTH {32} \
    CONFIG.C_PROBE12_WIDTH {1} CONFIG.C_PROBE13_WIDTH {1} CONFIG.C_PROBE14_WIDTH {20} \
    CONFIG.C_PROBE15_WIDTH {1} CONFIG.C_PROBE16_WIDTH {1} CONFIG.C_PROBE17_WIDTH {32} \
    CONFIG.C_PROBE18_WIDTH {32} \
] [get_ips ila_nvme_prp_ctrl]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_nvme_cq_head_tracker
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {16} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_PROBE1_WIDTH {4} CONFIG.C_PROBE2_WIDTH {3} \
    CONFIG.C_PROBE3_WIDTH {4} CONFIG.C_PROBE4_WIDTH {1} CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE6_WIDTH {4} CONFIG.C_PROBE7_WIDTH $nvme_queue_bits CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {1} CONFIG.C_PROBE10_WIDTH {48} CONFIG.C_PROBE11_WIDTH {1} \
    CONFIG.C_PROBE12_WIDTH {1} CONFIG.C_PROBE13_WIDTH [expr {1 + $nvme_queue_bits}] CONFIG.C_PROBE14_WIDTH {1} \
    CONFIG.C_PROBE15_WIDTH {64} \
] [get_ips ila_nvme_cq_head_tracker]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_nvme_sq_doorbell_writer
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {10} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_PROBE1_WIDTH {1} CONFIG.C_PROBE2_WIDTH {64} \
    CONFIG.C_PROBE3_WIDTH $nvme_queue_bits CONFIG.C_PROBE4_WIDTH {1} CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE6_WIDTH {48} CONFIG.C_PROBE7_WIDTH {1} CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {2} \
] [get_ips ila_nvme_sq_doorbell_writer]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_nvme_stripe
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {25} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} CONFIG.C_DATA_DEPTH {4096} \
    CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_PROBE1_WIDTH {1} CONFIG.C_PROBE2_WIDTH {64} \
    CONFIG.C_PROBE3_WIDTH {8} CONFIG.C_PROBE4_WIDTH {3} CONFIG.C_PROBE5_WIDTH {2} \
    CONFIG.C_PROBE6_WIDTH {1} CONFIG.C_PROBE7_WIDTH {1} CONFIG.C_PROBE8_WIDTH {512} \
    CONFIG.C_PROBE9_WIDTH {64} CONFIG.C_PROBE10_WIDTH {1} CONFIG.C_PROBE11_WIDTH {1} \
    CONFIG.C_PROBE12_WIDTH {1} CONFIG.C_PROBE13_WIDTH {2} CONFIG.C_PROBE14_WIDTH {1} \
    CONFIG.C_PROBE15_WIDTH {1} CONFIG.C_PROBE16_WIDTH {64} CONFIG.C_PROBE17_WIDTH {8} \
    CONFIG.C_PROBE18_WIDTH {3} CONFIG.C_PROBE19_WIDTH {2} CONFIG.C_PROBE20_WIDTH {1} \
    CONFIG.C_PROBE21_WIDTH {1} CONFIG.C_PROBE22_WIDTH {512} CONFIG.C_PROBE23_WIDTH {2} \
    CONFIG.C_PROBE24_WIDTH {1} \
] [get_ips ila_nvme_stripe]

} elseif {$cfg(en_nvme_pl) eq 1} {

# Reuse the existing RTL ILA probe layouts with the Versal-compatible AXIS ILA
# implementation. Only the runtime datapath monitors enabled in RTL are needed
# for the PL-connected debug build.
create_ip -name axis_ila -vendor xilinx.com -library ip -module_name ila_nvme_manage_prp
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {16} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_PROBE1_WIDTH {1} CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {1} CONFIG.C_PROBE4_WIDTH {64} CONFIG.C_PROBE5_WIDTH {64} \
    CONFIG.C_PROBE6_WIDTH {1} CONFIG.C_PROBE7_WIDTH {1} CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {1} CONFIG.C_PROBE10_WIDTH {48} CONFIG.C_PROBE11_WIDTH {1} \
    CONFIG.C_PROBE12_WIDTH {1} CONFIG.C_PROBE13_WIDTH {1} CONFIG.C_PROBE14_WIDTH {4} \
    CONFIG.C_PROBE15_WIDTH {64} \
] [get_ips ila_nvme_manage_prp]

create_ip -name axis_ila -vendor xilinx.com -library ip -module_name ila_nvme_sq_ctrl
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {16} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_PROBE1_WIDTH {1} CONFIG.C_PROBE2_WIDTH {4} \
    CONFIG.C_PROBE3_WIDTH [expr {4 + $nvme_queue_bits}] CONFIG.C_PROBE4_WIDTH {1} CONFIG.C_PROBE5_WIDTH [expr {4 + $nvme_queue_bits}] \
    CONFIG.C_PROBE6_WIDTH {1} CONFIG.C_PROBE7_WIDTH [expr {4 + $nvme_queue_bits}] CONFIG.C_PROBE8_WIDTH [expr {4 + $nvme_queue_bits}] \
    CONFIG.C_PROBE9_WIDTH {32} CONFIG.C_PROBE10_WIDTH {32} CONFIG.C_PROBE11_WIDTH {32} \
    CONFIG.C_PROBE12_WIDTH {32} CONFIG.C_PROBE13_WIDTH {32} CONFIG.C_PROBE14_WIDTH {32} \
    CONFIG.C_PROBE15_WIDTH {32} \
] [get_ips ila_nvme_sq_ctrl]

create_ip -name axis_ila -vendor xilinx.com -library ip -module_name ila_nvme_cq_ctrl
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {18} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_PROBE1_WIDTH {4} CONFIG.C_PROBE2_WIDTH {16} \
    CONFIG.C_PROBE3_WIDTH {1} CONFIG.C_PROBE4_WIDTH {1} CONFIG.C_PROBE5_WIDTH {4} \
    CONFIG.C_PROBE6_WIDTH {15} CONFIG.C_PROBE7_WIDTH {1} CONFIG.C_PROBE8_WIDTH {3} \
    CONFIG.C_PROBE9_WIDTH {4} CONFIG.C_PROBE10_WIDTH $nvme_queue_bits CONFIG.C_PROBE11_WIDTH {8} \
    CONFIG.C_PROBE12_WIDTH {64} CONFIG.C_PROBE13_WIDTH {64} \
    CONFIG.C_PROBE14_WIDTH $nvme_queue_bits CONFIG.C_PROBE15_WIDTH {16} \
    CONFIG.C_PROBE16_WIDTH {16} CONFIG.C_PROBE17_WIDTH {1} \
] [get_ips ila_nvme_cq_ctrl]

create_ip -name axis_ila -vendor xilinx.com -library ip -module_name ila_nvme_prp_ctrl
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {19} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_PROBE1_WIDTH {1} CONFIG.C_PROBE2_WIDTH [expr {9 + $nvme_queue_bits}] \
    CONFIG.C_PROBE3_WIDTH {32} CONFIG.C_PROBE4_WIDTH {1} CONFIG.C_PROBE5_WIDTH [expr {9 + $nvme_queue_bits}] \
    CONFIG.C_PROBE6_WIDTH {32} CONFIG.C_PROBE7_WIDTH {1} CONFIG.C_PROBE8_WIDTH [expr {12 + $nvme_queue_bits}] \
    CONFIG.C_PROBE9_WIDTH [expr {9 + $nvme_queue_bits}] CONFIG.C_PROBE10_WIDTH {32} CONFIG.C_PROBE11_WIDTH {32} \
    CONFIG.C_PROBE12_WIDTH {1} CONFIG.C_PROBE13_WIDTH {1} CONFIG.C_PROBE14_WIDTH {20} \
    CONFIG.C_PROBE15_WIDTH {1} CONFIG.C_PROBE16_WIDTH {1} CONFIG.C_PROBE17_WIDTH {32} \
    CONFIG.C_PROBE18_WIDTH {32} \
] [get_ips ila_nvme_prp_ctrl]

create_ip -name axis_ila -vendor xilinx.com -library ip -module_name ila_nvme_stripe
set_property -dict [list \
    CONFIG.C_MON_TYPE {Net_Probes} \
    CONFIG.C_NUM_OF_PROBES {25} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} CONFIG.C_DATA_DEPTH {4096} \
    CONFIG.C_PROBE0_WIDTH {1} CONFIG.C_PROBE1_WIDTH {1} CONFIG.C_PROBE2_WIDTH {64} \
    CONFIG.C_PROBE3_WIDTH {8} CONFIG.C_PROBE4_WIDTH {3} CONFIG.C_PROBE5_WIDTH {2} \
    CONFIG.C_PROBE6_WIDTH {1} CONFIG.C_PROBE7_WIDTH {1} CONFIG.C_PROBE8_WIDTH {512} \
    CONFIG.C_PROBE9_WIDTH {64} CONFIG.C_PROBE10_WIDTH {1} CONFIG.C_PROBE11_WIDTH {1} \
    CONFIG.C_PROBE12_WIDTH {1} CONFIG.C_PROBE13_WIDTH {2} CONFIG.C_PROBE14_WIDTH {1} \
    CONFIG.C_PROBE15_WIDTH {1} CONFIG.C_PROBE16_WIDTH {64} CONFIG.C_PROBE17_WIDTH {8} \
    CONFIG.C_PROBE18_WIDTH {3} CONFIG.C_PROBE19_WIDTH {2} CONFIG.C_PROBE20_WIDTH {1} \
    CONFIG.C_PROBE21_WIDTH {1} CONFIG.C_PROBE22_WIDTH {512} CONFIG.C_PROBE23_WIDTH {2} \
    CONFIG.C_PROBE24_WIDTH {1} \
] [get_ips ila_nvme_stripe]

}
