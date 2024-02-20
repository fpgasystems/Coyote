#
# Clocks
#

# Clock gen
set cmd "set clk_wiz_shell \[ create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_shell ]"
eval $cmd
set cmd "set_property -dict \[list \
    CONFIG.USE_PHASE_ALIGNMENT {true} \
    CONFIG.USE_PHASE_ALIGNMENT {true} \
    CONFIG.PRIM_SOURCE {Single_ended_clock_capable_pin} \
    CONFIG.PRIM_IN_FREQ {250.000} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT3_USED {true} \
    CONFIG.CLKOUT4_USED {true} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {[expr {$cfg(aclk_f)}]} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {[expr {$cfg(nclk_f)}]} \
    CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {[expr {$cfg(uclk_f)}]} \
    CONFIG.CLKOUT4_REQUESTED_OUT_FREQ {300} \
    CONFIG.SECONDARY_SOURCE {Single_ended_clock_capable_pin} \
    CONFIG.CLKOUT1_DRIVES {Buffer} \
    CONFIG.CLKOUT2_DRIVES {Buffer} \
    CONFIG.CLKOUT3_DRIVES {Buffer} \
    CONFIG.CLKOUT4_DRIVES {Buffer} \
    CONFIG.NUM_OUT_CLKS {3} \
    CONFIG.CLKOUT1_JITTER {102.086} \
    CONFIG.CLKOUT2_JITTER {94.862} \
    CONFIG.CLKOUT2_PHASE_ERROR {87.180} \
    CONFIG.CLKOUT3_JITTER {94.862} \
    CONFIG.CLKOUT3_PHASE_ERROR {87.180} \
    CONFIG.USE_LOCKED {false} \
    CONFIG.USE_RESET {false} \
] \[get_ips clk_wiz_shell]"
eval $cmd

# Reset sync
create_ip -name proc_sys_reset -vendor xilinx.com -library ip -version 5.0 -module_name proc_sys_reset_a;
set_property -dict [list CONFIG.C_EXT_RESET_HIGH {1}] [get_ips proc_sys_reset_a]

create_ip -name proc_sys_reset -vendor xilinx.com -library ip -version 5.0 -module_name proc_sys_reset_n;
set_property -dict [list CONFIG.C_EXT_RESET_HIGH {1}] [get_ips proc_sys_reset_n]

create_ip -name proc_sys_reset -vendor xilinx.com -library ip -version 5.0 -module_name proc_sys_reset_u;
set_property -dict [list CONFIG.C_EXT_RESET_HIGH {1}] [get_ips proc_sys_reset_u]

#
# Register slices
#

# Split
create_ip -name axi_register_slice -vendor xilinx.com -library ip -version 2.1 -module_name axi_reg_shell_src_s0_int
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {512} CONFIG.ID_WIDTH {6} CONFIG.REG_AW {0} CONFIG.REG_AR {0} CONFIG.REG_R {0} CONFIG.REG_B {0} ] [get_ips axi_reg_shell_src_s0_int]

create_ip -name axi_register_slice -vendor xilinx.com -library ip -version 2.1 -module_name axi_reg_shell_src_s2_int
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {64} ] [get_ips axi_reg_shell_src_s2_int]

create_ip -name axi_register_slice -vendor xilinx.com -library ip -version 2.1 -module_name axi_reg_shell_src_s4_int
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {64} CONFIG.REG_W {7} CONFIG.REG_R {7} CONFIG.PROTOCOL {AXI4LITE}] [get_ips axi_reg_shell_src_s4_int]

create_ip -name axi_register_slice -vendor xilinx.com -library ip -version 2.1 -module_name axim_reg_shell_src_s0_int
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {512} CONFIG.ID_WIDTH {6} CONFIG.REG_AW {0} CONFIG.REG_AR {0} CONFIG.REG_R {0} CONFIG.REG_B {0} ] [get_ips axim_reg_shell_src_s0_int]

create_ip -name axi_register_slice -vendor xilinx.com -library ip -version 2.1 -module_name axim_reg_shell_src_s2_int
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {256} ] [get_ips axim_reg_shell_src_s2_int]

create_ip -name axi_register_slice -vendor xilinx.com -library ip -version 2.1 -module_name axi_reg_shell_sink_int
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {512} CONFIG.ID_WIDTH {6} ] [get_ips axi_reg_shell_sink_int]

# HBM
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_hbm_r
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.TUSER_WIDTH {4} CONFIG.FIFO_DEPTH {128} CONFIG.HAS_TLAST {1} ] [get_ips axis_data_fifo_hbm_r]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_hbm_w
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {128} CONFIG.HAS_TSTRB {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_data_fifo_hbm_w]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_hbm_b
set_property -dict [list CONFIG.TDATA_NUM_BYTES {0} CONFIG.TUSER_WIDTH {4} CONFIG.FIFO_DEPTH {128} ] [get_ips axis_data_fifo_hbm_b]

# Split
create_ip -name axi_data_fifo -vendor xilinx.com -library ip -version 2.1 -module_name axi_data_fifo_shell_sink_int
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {512} CONFIG.ID_WIDTH {6} CONFIG.WRITE_FIFO_DEPTH {512} CONFIG.READ_FIFO_DEPTH {512} CONFIG.WRITE_FIFO_DELAY {1} CONFIG.READ_FIFO_DELAY {1}] [get_ips axi_data_fifo_shell_sink_int]

#
# Dwidth
#

create_ip -name axi_dwidth_converter -vendor xilinx.com -library ip -version 2.1 -module_name axi_dwidth_shell_src_s1_int
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.SI_DATA_WIDTH {512} CONFIG.SI_ID_WIDTH {6} CONFIG.MI_DATA_WIDTH {64}] [get_ips axi_dwidth_shell_src_s1_int]

create_ip -name axi_dwidth_converter -vendor xilinx.com -library ip -version 2.1 -module_name axim_dwidth_shell_src_s1_int
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.SI_DATA_WIDTH {512} CONFIG.MI_DATA_WIDTH {256} CONFIG.SI_ID_WIDTH {6}] [get_ips axim_dwidth_shell_src_s1_int]

#
# Protocols
#

create_ip -name axi_protocol_converter -vendor xilinx.com -library ip -version 2.1 -module_name axi_protocol_shell_src_s3_int
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {64}] [get_ips axi_protocol_shell_src_s3_int]

#
# XBARs
#

create_ip -name axi_crossbar -vendor xilinx.com -library ip -version 2.1 -module_name shell_xbar
set cmd [format "set_property -dict \[list \
    CONFIG.ID_WIDTH {4} \
    CONFIG.ADDR_WIDTH {64} \
    CONFIG.DATA_WIDTH {512} \
    CONFIG.S00_WRITE_ACCEPTANCE {8} \
    CONFIG.S00_READ_ACCEPTANCE {8} \
    CONFIG.S00_THREAD_ID_WIDTH {4} \
    CONFIG.S01_THREAD_ID_WIDTH {4} \
    CONFIG.S02_THREAD_ID_WIDTH {4} \
    CONFIG.S03_THREAD_ID_WIDTH {4} \
    CONFIG.S04_THREAD_ID_WIDTH {4} \
    CONFIG.S05_THREAD_ID_WIDTH {4} \
    CONFIG.S06_THREAD_ID_WIDTH {4} \
    CONFIG.S07_THREAD_ID_WIDTH {4} \
    CONFIG.S08_THREAD_ID_WIDTH {4} \
    CONFIG.S09_THREAD_ID_WIDTH {4} \
    CONFIG.S10_THREAD_ID_WIDTH {4} \
    CONFIG.S11_THREAD_ID_WIDTH {4} \
    CONFIG.S12_THREAD_ID_WIDTH {4} \
    CONFIG.S13_THREAD_ID_WIDTH {4} \
    CONFIG.S14_THREAD_ID_WIDTH {4} \
    CONFIG.S15_THREAD_ID_WIDTH {4} \
    CONFIG.S01_BASE_ID {0x00000010} \
    CONFIG.S02_BASE_ID {0x00000020} \
    CONFIG.S03_BASE_ID {0x00000030} \
    CONFIG.S04_BASE_ID {0x00000040} \
    CONFIG.S05_BASE_ID {0x00000050} \
    CONFIG.S06_BASE_ID {0x00000060} \
    CONFIG.S07_BASE_ID {0x00000070} \
    CONFIG.S08_BASE_ID {0x00000080} \
    CONFIG.S09_BASE_ID {0x00000090} \
    CONFIG.S10_BASE_ID {0x000000a0} \
    CONFIG.S11_BASE_ID {0x000000b0} \
    CONFIG.S12_BASE_ID {0x000000c0} \
    CONFIG.S13_BASE_ID {0x000000d0} \
    CONFIG.S14_BASE_ID {0x000000e0} \
    CONFIG.S15_BASE_ID {0x000000f0} \
    CONFIG.M00_WRITE_ISSUING {8} \
    CONFIG.M00_READ_ISSUING {8} \
    CONFIG.M00_A00_BASE_ADDR {0x0000000000000000} \
    CONFIG.M00_A00_ADDR_WIDTH {15} "] 
if {$cfg(en_avx) eq 1} {
    append cmd "CONFIG.NUM_MI {[expr {2* $cfg(n_reg) + 1}]} "

    for {set i 0}  {$i < $cfg(n_reg)} {incr i} {
        append cmd [format "CONFIG.M%02d_WRITE_ISSUING {8} " [expr {2*$i+1}]]
        append cmd [format "CONFIG.M%02d_WRITE_ISSUING {8} " [expr {2*$i+2}]]
        append cmd [format "CONFIG.M%02d_READ_ISSUING {8} " [expr {2*$i+1}]]
        append cmd [format "CONFIG.M%02d_READ_ISSUING {8} " [expr {2*$i+2}]]
        append cmd [format "CONFIG.M%02d_A00_ADDR_WIDTH {18} " [expr {2*$i+1}]]
        append cmd [format "CONFIG.M%02d_A00_ADDR_WIDTH {18} " [expr {2*$i+2}]]
        append cmd [format "CONFIG.M%02d_A00_BASE_ADDR {0x0000000000%02x0000} " [expr {2*$i+1}] [expr {0x10 + $i*4}]]
        append cmd [format "CONFIG.M%02d_A00_BASE_ADDR {0x000000000%03x0000} "  [expr {2*$i+2}] [expr {0x100 + $i*4}]]
    }
} else {
    append cmd "CONFIG.NUM_MI {[expr {$cfg(n_reg) + 1}]} "

    for {set i 0}  {$i < $cfg(n_reg)} {incr i} {
        append cmd [format "CONFIG.M%02d_WRITE_ISSUING {8} " [expr {$i+1}]]
        append cmd [format "CONFIG.M%02d_READ_ISSUING {8} " [expr {$i+1}]]
        append cmd [format "CONFIG.M%02d_A00_ADDR_WIDTH {18} " [expr {$i+1}]]
        append cmd [format "CONFIG.M%02d_A00_BASE_ADDR {0x0000000000%02x0000} " [expr {0x10 + $i*4}]]
    }
}
append cmd "] \[get_ips shell_xbar]"
eval $cmd

#
# Stripe
#

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_stripe_b
set_property -dict [list CONFIG.TDATA_NUM_BYTES {0} CONFIG.TUSER_WIDTH {2}] [get_ips axis_data_fifo_stripe_b]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_stripe_r
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.TUSER_WIDTH {2} CONFIG.HAS_TLAST {1}] [get_ips axis_data_fifo_stripe_r]

#
# Debug
#

create_ip -name debug_bridge -vendor xilinx.com -library ip -version 3.0 -module_name debug_bridge_dynamic
set cmd "set_property -dict \[list CONFIG.C_NUM_BS_MASTER {$cfg(n_reg)} CONFIG.C_DESIGN_TYPE {1}] \[get_ips debug_bridge_dynamic]"
eval $cmd

# if {$cfg(en_pr) eq 1} {
#     create_ip -name debug_bridge -vendor xilinx.com -library ip -version 3.0 -module_name debug_bridge_dynamic
#     set cmd "set_property -dict \[list CONFIG.C_NUM_BS_MASTER {$cfg(n_reg)} CONFIG.C_DESIGN_TYPE {1}] \[get_ips debug_bridge_dynamic]"
#     eval $cmd
# } else {
#     create_ip -name debug_bridge -vendor xilinx.com -library ip -version 3.0 -module_name debug_bridge_dynamic
#     set_property -dict [list CONFIG.C_DEBUG_MODE {1} CONFIG.C_NUM_BS_MASTER {0} CONFIG.C_DESIGN_TYPE {1}] [get_ips debug_bridge_dynamic]
# }

create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_shell_xstats
set_property -dict [list CONFIG.C_PROBE_IN5_WIDTH {32} CONFIG.C_PROBE_IN4_WIDTH {32} CONFIG.C_PROBE_IN3_WIDTH {32} CONFIG.C_PROBE_IN2_WIDTH {32} CONFIG.C_PROBE_IN1_WIDTH {32} CONFIG.C_PROBE_IN0_WIDTH {32} CONFIG.C_NUM_PROBE_OUT {0} CONFIG.C_NUM_PROBE_IN {6}] [get_ips vio_shell_xstats]

create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_shell_decoupling
set cmd "set_property -dict \[list CONFIG.C_PROBE_IN0_WIDTH {$cfg(n_reg)} CONFIG.C_PROBE_OUT0_WIDTH {1} CONFIG.C_PROBE_OUT1_WIDTH {$cfg(n_reg)} CONFIG.C_NUM_PROBE_OUT {2} CONFIG.C_NUM_PROBE_IN {1}] \[get_ips vio_shell_decoupling]"
eval $cmd

# Control xbars
for {set i 0}  {$i < $cfg(n_reg)} {incr i} {
    set cmd "create_ip -name axi_crossbar -vendor xilinx.com -library ip -version 2.1 -module_name dyn_crossbar_$i"
    eval $cmd
    set offs [expr {0x10 + $i * 4}]
    set cmd [format "set_property -dict \[list \
                CONFIG.NUM_MI {4} CONFIG.ADDR_WIDTH {64} CONFIG.PROTOCOL {AXI4LITE} CONFIG.DATA_WIDTH {64} CONFIG.CONNECTIVITY_MODE {SASD} CONFIG.R_REGISTER {1} \
                CONFIG.S00_WRITE_ACCEPTANCE {1} CONFIG.S01_WRITE_ACCEPTANCE {1} CONFIG.S02_WRITE_ACCEPTANCE {1} CONFIG.S03_WRITE_ACCEPTANCE {1} CONFIG.S04_WRITE_ACCEPTANCE {1} CONFIG.S05_WRITE_ACCEPTANCE {1} CONFIG.S06_WRITE_ACCEPTANCE {1} CONFIG.S07_WRITE_ACCEPTANCE {1} CONFIG.S08_WRITE_ACCEPTANCE {1} CONFIG.S09_WRITE_ACCEPTANCE {1} CONFIG.S10_WRITE_ACCEPTANCE {1} CONFIG.S11_WRITE_ACCEPTANCE {1} CONFIG.S12_WRITE_ACCEPTANCE {1} CONFIG.S13_WRITE_ACCEPTANCE {1} CONFIG.S14_WRITE_ACCEPTANCE {1} CONFIG.S15_WRITE_ACCEPTANCE {1} \
                CONFIG.S00_READ_ACCEPTANCE {1} CONFIG.S01_READ_ACCEPTANCE {1} CONFIG.S02_READ_ACCEPTANCE {1} CONFIG.S03_READ_ACCEPTANCE {1} CONFIG.S04_READ_ACCEPTANCE {1} CONFIG.S05_READ_ACCEPTANCE {1} CONFIG.S06_READ_ACCEPTANCE {1} CONFIG.S07_READ_ACCEPTANCE {1} CONFIG.S08_READ_ACCEPTANCE {1} CONFIG.S09_READ_ACCEPTANCE {1} CONFIG.S10_READ_ACCEPTANCE {1} CONFIG.S11_READ_ACCEPTANCE {1} CONFIG.S12_READ_ACCEPTANCE {1} CONFIG.S13_READ_ACCEPTANCE {1} CONFIG.S14_READ_ACCEPTANCE {1} CONFIG.S15_READ_ACCEPTANCE {1} \
                CONFIG.M00_WRITE_ISSUING {1} CONFIG.M01_WRITE_ISSUING {1} CONFIG.M02_WRITE_ISSUING {1} CONFIG.M03_WRITE_ISSUING {1} CONFIG.M04_WRITE_ISSUING {1} CONFIG.M05_WRITE_ISSUING {1} CONFIG.M06_WRITE_ISSUING {1} CONFIG.M07_WRITE_ISSUING {1} CONFIG.M08_WRITE_ISSUING {1} CONFIG.M09_WRITE_ISSUING {1} CONFIG.M10_WRITE_ISSUING {1} CONFIG.M11_WRITE_ISSUING {1} CONFIG.M12_WRITE_ISSUING {1} CONFIG.M13_WRITE_ISSUING {1} CONFIG.M14_WRITE_ISSUING {1} CONFIG.M15_WRITE_ISSUING {1} \
                CONFIG.M00_READ_ISSUING {1} CONFIG.M01_READ_ISSUING {1} CONFIG.M02_READ_ISSUING {1} CONFIG.M03_READ_ISSUING {1} CONFIG.M04_READ_ISSUING {1} CONFIG.M05_READ_ISSUING {1} CONFIG.M06_READ_ISSUING {1} CONFIG.M07_READ_ISSUING {1} CONFIG.M08_READ_ISSUING {1} CONFIG.M09_READ_ISSUING {1} CONFIG.M10_READ_ISSUING {1} CONFIG.M11_READ_ISSUING {1} CONFIG.M12_READ_ISSUING {1} CONFIG.M13_READ_ISSUING {1} CONFIG.M14_READ_ISSUING {1} CONFIG.M15_READ_ISSUING {1} \
                CONFIG.S00_SINGLE_THREAD {1} CONFIG.M00_A00_BASE_ADDR  {0x0000000000%02x0000} CONFIG.M01_A00_BASE_ADDR {0x0000000000%02x0000} CONFIG.M02_A00_BASE_ADDR {0x0000000000%02x0000} CONFIG.M03_A00_BASE_ADDR {0x0000000000%02x0000} CONFIG.M00_A00_ADDR_WIDTH {16} CONFIG.M01_A00_ADDR_WIDTH {16} CONFIG.M02_A00_ADDR_WIDTH {16} CONFIG.M03_A00_ADDR_WIDTH {16} \
                ] \[get_ips dyn_crossbar_$i]" $offs [expr {$offs + 1}] [expr {$offs + 2}] [expr {$offs + 3}]   ]
    eval $cmd
}

# TLB
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_128_tlb
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.FIFO_DEPTH {64} CONFIG.HAS_TLAST {1} ] [get_ips axis_data_fifo_128_tlb]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_cch_req_128
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.FIFO_DEPTH {256} ] [get_ips axis_data_fifo_cch_req_128]

create_ip -name axis_interconnect -vendor xilinx.com -library ip -version 1.1 -module_name axis_interconnect_tlb
set_property -dict [list CONFIG.C_NUM_SI_SLOTS {2} CONFIG.SWITCH_TDATA_NUM_BYTES {16} CONFIG.HAS_TSTRB {false} CONFIG.HAS_TKEEP {false} CONFIG.HAS_TLAST {true} CONFIG.HAS_TID {false} CONFIG.HAS_TDEST {false} CONFIG.SWITCH_PACKET_MODE {false} CONFIG.C_SWITCH_MAX_XFERS_PER_ARB {1} CONFIG.C_SWITCH_NUM_CYCLES_TIMEOUT {0} CONFIG.M00_AXIS_TDATA_NUM_BYTES {16} CONFIG.S00_AXIS_TDATA_NUM_BYTES {16} CONFIG.S01_AXIS_TDATA_NUM_BYTES {16} CONFIG.M00_S01_CONNECTIVITY {true}] [get_ips axis_interconnect_tlb]

# Bypass ic
create_ip -name axis_interconnect -vendor xilinx.com -library ip -version 1.1 -module_name axis_interconnect_cnfg_req_arbiter
set_property -dict [list CONFIG.C_NUM_SI_SLOTS {2} CONFIG.SWITCH_TDATA_NUM_BYTES {12} CONFIG.HAS_TSTRB {false} CONFIG.HAS_TKEEP {false} CONFIG.HAS_TLAST {false} CONFIG.HAS_TID {false} CONFIG.HAS_TDEST {false} CONFIG.C_M00_AXIS_REG_CONFIG {1} CONFIG.SWITCH_PACKET_MODE {false} CONFIG.C_SWITCH_MAX_XFERS_PER_ARB {1} CONFIG.C_SWITCH_NUM_CYCLES_TIMEOUT {0} CONFIG.M00_AXIS_TDATA_NUM_BYTES {12} CONFIG.S00_AXIS_TDATA_NUM_BYTES {12} CONFIG.S01_AXIS_TDATA_NUM_BYTES {12} CONFIG.M00_S01_CONNECTIVITY {true}] [get_ips axis_interconnect_cnfg_req_arbiter]

# Converters
create_ip -name axis_dwidth_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_dwidth_converter_tlb
set_property -dict [list CONFIG.S_TDATA_NUM_BYTES {64} CONFIG.M_TDATA_NUM_BYTES {16} CONFIG.HAS_TLAST {1} CONFIG.HAS_TKEEP {1} ] [get_ips axis_dwidth_converter_tlb]

update_compile_order -fileset sources_1
