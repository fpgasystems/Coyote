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

# Data queues
set nn 1024
if {$cfg(pmtu) > 1024} {
    set nn 2048
}
if {$cfg(pmtu) > 2048} {
    set nn 4096
}
if {$cfg(pmtu) > 4096} {
    set nn 8192
}
set nn512 [expr {$cfg(n_outs) * ($nn / 64)}]

# AXI
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_512
set cmd "set_property -dict \[list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {$nn512} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} ] \[get_ips axis_data_fifo_512]"
eval $cmd

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_clock_converter_512]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_req_96_used
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.FIFO_DEPTH {32} CONFIG.HAS_WR_DATA_COUNT {1} ] [get_ips axis_data_fifo_req_96_used]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_req_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_req_96]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_req_128
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_req_128]

create_ip -name axi_clock_converter -vendor xilinx.com -library ip -version 2.1 -module_name axil_clock_converter
set_property -dict [list CONFIG.PROTOCOL {AXI4LITE} CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {64} CONFIG.ID_WIDTH {0} CONFIG.AWUSER_WIDTH {0} CONFIG.ARUSER_WIDTH {0} CONFIG.RUSER_WIDTH {0} CONFIG.WUSER_WIDTH {0} CONFIG.BUSER_WIDTH {0}] [get_ips axil_clock_converter]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_dma_rsp
set_property -dict [list CONFIG.TDATA_NUM_BYTES {0} CONFIG.TUSER_WIDTH {6} CONFIG.SYNCHRONIZATION_STAGES {2} ] [get_ips axis_clock_converter_dma_rsp]

# AXIR
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axisr_data_fifo_512
set cmd "set_property -dict \[list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {$nn512} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1}  CONFIG.TID_WIDTH {6}] \[get_ips axisr_data_fifo_512]"
eval $cmd

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axisr_clock_converter_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.TID_WIDTH {6}] [get_ips axisr_clock_converter_512]

# Stripe
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_stripe_b
set_property -dict [list CONFIG.TDATA_NUM_BYTES {0} CONFIG.TUSER_WIDTH {2}] [get_ips axis_data_fifo_stripe_b]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_stripe_r
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.TUSER_WIDTH {2} CONFIG.HAS_TLAST {1}] [get_ips axis_data_fifo_stripe_r]

# TLB
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_128_tlb
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.FIFO_DEPTH {64} CONFIG.HAS_TLAST {1} ] [get_ips axis_data_fifo_128_tlb]

create_ip -name axis_interconnect -vendor xilinx.com -library ip -version 1.1 -module_name axis_interconnect_tlb
set_property -dict [list CONFIG.C_NUM_SI_SLOTS {2} CONFIG.SWITCH_TDATA_NUM_BYTES {16} CONFIG.HAS_TSTRB {false} CONFIG.HAS_TKEEP {false} CONFIG.HAS_TLAST {true} CONFIG.HAS_TID {false} CONFIG.HAS_TDEST {false} CONFIG.SWITCH_PACKET_MODE {false} CONFIG.C_SWITCH_MAX_XFERS_PER_ARB {1} CONFIG.C_SWITCH_NUM_CYCLES_TIMEOUT {0} CONFIG.M00_AXIS_TDATA_NUM_BYTES {16} CONFIG.S00_AXIS_TDATA_NUM_BYTES {16} CONFIG.S01_AXIS_TDATA_NUM_BYTES {16} CONFIG.M00_S01_CONNECTIVITY {true}] [get_ips axis_interconnect_tlb]

# Bypass ic
create_ip -name axis_interconnect -vendor xilinx.com -library ip -version 1.1 -module_name axis_interconnect_cnfg_req_arbiter
set_property -dict [list CONFIG.C_NUM_SI_SLOTS {2} CONFIG.SWITCH_TDATA_NUM_BYTES {12} CONFIG.HAS_TSTRB {false} CONFIG.HAS_TKEEP {false} CONFIG.HAS_TLAST {false} CONFIG.HAS_TID {false} CONFIG.HAS_TDEST {false} CONFIG.C_M00_AXIS_REG_CONFIG {1} CONFIG.SWITCH_PACKET_MODE {false} CONFIG.C_SWITCH_MAX_XFERS_PER_ARB {1} CONFIG.C_SWITCH_NUM_CYCLES_TIMEOUT {0} CONFIG.M00_AXIS_TDATA_NUM_BYTES {12} CONFIG.S00_AXIS_TDATA_NUM_BYTES {12} CONFIG.S01_AXIS_TDATA_NUM_BYTES {12} CONFIG.M00_S01_CONNECTIVITY {true}] [get_ips axis_interconnect_cnfg_req_arbiter]

# HBM
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_hbm_r
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.TUSER_WIDTH {4} CONFIG.FIFO_DEPTH {128} CONFIG.HAS_TLAST {1} ] [get_ips axis_data_fifo_hbm_r]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_hbm_w
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {128} CONFIG.HAS_TSTRB {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_data_fifo_hbm_w]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_hbm_b
set_property -dict [list CONFIG.TDATA_NUM_BYTES {0} CONFIG.TUSER_WIDTH {4} CONFIG.FIFO_DEPTH {128} ] [get_ips axis_data_fifo_hbm_b]

# PR
create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name pr_clock_converter
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} ] [get_ips pr_clock_converter]

create_ip -name axis_dwidth_converter -vendor xilinx.com -library ip -version 1.1 -module_name pr_dwidth_converter
set_property -dict [list CONFIG.S_TDATA_NUM_BYTES {64} CONFIG.M_TDATA_NUM_BYTES {4} CONFIG.HAS_TLAST {1} CONFIG.HAS_TKEEP {1} CONFIG.HAS_MI_TKEEP {0} ] [get_ips pr_dwidth_converter]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name pr_reg_slice
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.HAS_TLAST {1} ] [get_ips pr_reg_slice]

# Meta
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_meta_8
set_property -dict [list CONFIG.TDATA_NUM_BYTES {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_meta_8]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_meta_16
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_meta_16]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_meta_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_meta_32]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_meta_48
set_property -dict [list CONFIG.TDATA_NUM_BYTES {6} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_meta_48]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_meta_72
set_property -dict [list CONFIG.TDATA_NUM_BYTES {9} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_meta_72]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_meta_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_meta_96]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_meta_256
set_property -dict [list CONFIG.TDATA_NUM_BYTES {32} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_meta_256]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_meta_8
set_property -dict [list CONFIG.TDATA_NUM_BYTES {1} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_meta_8]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_meta_16
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_meta_16]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_meta_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_meta_32]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_meta_56
set_property -dict [list CONFIG.TDATA_NUM_BYTES {7} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_meta_56]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_meta_64
set_property -dict [list CONFIG.TDATA_NUM_BYTES {8} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_meta_64]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_meta_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_meta_96]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_meta_128
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_meta_128]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_meta_256
set_property -dict [list CONFIG.TDATA_NUM_BYTES {32} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_meta_256]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_meta_544
set_property -dict [list CONFIG.TDATA_NUM_BYTES {68} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_meta_544]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name meta_clock_converter_8
set_property -dict [list CONFIG.TDATA_NUM_BYTES {1} ] [get_ips meta_clock_converter_8]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name meta_clock_converter_16
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} ] [get_ips meta_clock_converter_16]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name meta_clock_converter_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} ] [get_ips meta_clock_converter_32]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name meta_clock_converter_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} ] [get_ips meta_clock_converter_96]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name meta_clock_converter_256
set_property -dict [list CONFIG.TDATA_NUM_BYTES {32} ] [get_ips meta_clock_converter_256]

# Reg slices
create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.REG_CONFIG {8} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1}] [get_ips axis_register_slice_512]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axisr_register_slice_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.REG_CONFIG {8} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.TID_WIDTH {6}] [get_ips axisr_register_slice_512]

create_ip -name axi_register_slice -vendor xilinx.com -library ip -version 2.1 -module_name axi_register_slice_512
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {512} CONFIG.REG_AW {1} CONFIG.REG_AR {1} CONFIG.REG_B {1} CONFIG.ID_WIDTH {1} CONFIG.MAX_BURST_LENGTH {14} CONFIG.NUM_READ_OUTSTANDING {32} CONFIG.NUM_WRITE_OUTSTANDING {32}] [get_ips axi_register_slice_512]

create_ip -name axi_register_slice -vendor xilinx.com -library ip -version 2.1 -module_name axim_register_slice
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {256} CONFIG.REG_AW {1} CONFIG.REG_AR {1} CONFIG.REG_B {1} CONFIG.ID_WIDTH {1} CONFIG.MAX_BURST_LENGTH {14} CONFIG.NUM_READ_OUTSTANDING {32} CONFIG.NUM_WRITE_OUTSTANDING {32}] [get_ips axim_register_slice]

create_ip -name axi_register_slice -vendor xilinx.com -library ip -version 2.1 -module_name axil_register_slice
set_property -dict [list CONFIG.PROTOCOL {AXI4LITE} CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {64} CONFIG.REG_AW {1} CONFIG.REG_AR {1} CONFIG.REG_W {1} CONFIG.REG_R {1} CONFIG.REG_B {1} ] [get_ips axil_register_slice]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_req_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_req_96]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_req_128
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_req_128]

# Converters
create_ip -name axis_dwidth_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_dwidth_converter_tlb
set_property -dict [list CONFIG.S_TDATA_NUM_BYTES {64} CONFIG.M_TDATA_NUM_BYTES {16} CONFIG.HAS_TLAST {1} CONFIG.HAS_TKEEP {1} ] [get_ips axis_dwidth_converter_tlb]

# Enzian
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_w_buff
set_property -dict [list CONFIG.TDATA_NUM_BYTES {128} CONFIG.FIFO_DEPTH {32} CONFIG.HAS_TSTRB {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_data_fifo_w_buff]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_splitter_9
set_property -dict [list CONFIG.TDATA_NUM_BYTES {0} CONFIG.TUSER_WIDTH {9} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_splitter_9]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_splitter_48
set_property -dict [list CONFIG.TDATA_NUM_BYTES {6} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_splitter_48]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_r
set_property -dict [list CONFIG.TDATA_NUM_BYTES {128} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_r]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_w
set_property -dict [list CONFIG.TDATA_NUM_BYTES {128} CONFIG.REG_CONFIG {8} CONFIG.HAS_TSTRB {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_register_slice_w]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_b
set_property -dict [list CONFIG.TDATA_NUM_BYTES {0} CONFIG.TUSER_WIDTH {4} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_b]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_wr_req
set_property -dict [list CONFIG.TDATA_NUM_BYTES {136} CONFIG.TUSER_WIDTH {5} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_wr_req]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_vc
set_property -dict [list CONFIG.TDATA_NUM_BYTES {136} CONFIG.TUSER_WIDTH {5} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_vc]

create_ip -name axis_dwidth_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_dwidth_net_user
set_property -dict [list CONFIG.S_TDATA_NUM_BYTES {64} CONFIG.M_TDATA_NUM_BYTES {128} CONFIG.HAS_TLAST {1} CONFIG.HAS_TKEEP {1} CONFIG.HAS_MI_TKEEP {1} ] [get_ips axis_dwidth_net_user]

create_ip -name axis_dwidth_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_dwidth_user_net
set_property -dict [list CONFIG.S_TDATA_NUM_BYTES {128} CONFIG.M_TDATA_NUM_BYTES {64} CONFIG.HAS_TLAST {1} CONFIG.HAS_TKEEP {1} ] [get_ips axis_dwidth_user_net]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_wr_req_w
set_property -dict [list CONFIG.TDATA_NUM_BYTES {128} CONFIG.FIFO_DEPTH {256} CONFIG.HAS_TSTRB {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_data_fifo_wr_req_w]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_wr_req_aw
set_property -dict [list CONFIG.TDATA_NUM_BYTES {6} CONFIG.FIFO_DEPTH {256} ] [get_ips axis_data_fifo_wr_req_aw]

# Reset sync
create_ip -name proc_sys_reset -vendor xilinx.com -library ip -version 5.0 -module_name proc_sys_reset_gen_h

create_ip -name proc_sys_reset -vendor xilinx.com -library ip -version 5.0 -module_name proc_sys_reset_gen_l
set_property -dict [list CONFIG.C_EXT_RESET_HIGH {0}] [get_ips proc_sys_reset_gen_l]

# Clock 
create_ip -name axi_clock_converter -vendor xilinx.com -library ip -version 2.1 -module_name axi_clock_converter_256
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {256} CONFIG.ID_WIDTH {1}] [get_ips axi_clock_converter_256]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} ] [get_ips axis_clock_converter_96]

update_compile_order -fileset sources_1