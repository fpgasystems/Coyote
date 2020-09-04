# Control xbars
if {$cfg(en_avx) eq 1} {
    for {set i 0}  {$i < $cfg(n_reg)} {incr i} {
        set cmd "create_ip -name axi_crossbar -vendor xilinx.com -library ip -version 2.1 -module_name dyn_crossbar_$i"
        eval $cmd
        set offs [expr {0x10 + $i * 4}]
        set cmd [format "set_property -dict \[list \
                    CONFIG.NUM_MI {3} CONFIG.ADDR_WIDTH {64} CONFIG.PROTOCOL {AXI4LITE} CONFIG.DATA_WIDTH {64} CONFIG.CONNECTIVITY_MODE {SASD} CONFIG.R_REGISTER {1} \
                    CONFIG.S00_WRITE_ACCEPTANCE {1} CONFIG.S01_WRITE_ACCEPTANCE {1} CONFIG.S02_WRITE_ACCEPTANCE {1} CONFIG.S03_WRITE_ACCEPTANCE {1} CONFIG.S04_WRITE_ACCEPTANCE {1} CONFIG.S05_WRITE_ACCEPTANCE {1} CONFIG.S06_WRITE_ACCEPTANCE {1} CONFIG.S07_WRITE_ACCEPTANCE {1} CONFIG.S08_WRITE_ACCEPTANCE {1} CONFIG.S09_WRITE_ACCEPTANCE {1} CONFIG.S10_WRITE_ACCEPTANCE {1} CONFIG.S11_WRITE_ACCEPTANCE {1} CONFIG.S12_WRITE_ACCEPTANCE {1} CONFIG.S13_WRITE_ACCEPTANCE {1} CONFIG.S14_WRITE_ACCEPTANCE {1} CONFIG.S15_WRITE_ACCEPTANCE {1} \
                    CONFIG.S00_READ_ACCEPTANCE {1} CONFIG.S01_READ_ACCEPTANCE {1} CONFIG.S02_READ_ACCEPTANCE {1} CONFIG.S03_READ_ACCEPTANCE {1} CONFIG.S04_READ_ACCEPTANCE {1} CONFIG.S05_READ_ACCEPTANCE {1} CONFIG.S06_READ_ACCEPTANCE {1} CONFIG.S07_READ_ACCEPTANCE {1} CONFIG.S08_READ_ACCEPTANCE {1} CONFIG.S09_READ_ACCEPTANCE {1} CONFIG.S10_READ_ACCEPTANCE {1} CONFIG.S11_READ_ACCEPTANCE {1} CONFIG.S12_READ_ACCEPTANCE {1} CONFIG.S13_READ_ACCEPTANCE {1} CONFIG.S14_READ_ACCEPTANCE {1} CONFIG.S15_READ_ACCEPTANCE {1} \
                    CONFIG.M00_WRITE_ISSUING {1} CONFIG.M01_WRITE_ISSUING {1} CONFIG.M02_WRITE_ISSUING {1} CONFIG.M03_WRITE_ISSUING {1} CONFIG.M04_WRITE_ISSUING {1} CONFIG.M05_WRITE_ISSUING {1} CONFIG.M06_WRITE_ISSUING {1} CONFIG.M07_WRITE_ISSUING {1} CONFIG.M08_WRITE_ISSUING {1} CONFIG.M09_WRITE_ISSUING {1} CONFIG.M10_WRITE_ISSUING {1} CONFIG.M11_WRITE_ISSUING {1} CONFIG.M12_WRITE_ISSUING {1} CONFIG.M13_WRITE_ISSUING {1} CONFIG.M14_WRITE_ISSUING {1} CONFIG.M15_WRITE_ISSUING {1} \
                    CONFIG.M00_READ_ISSUING {1} CONFIG.M01_READ_ISSUING {1} CONFIG.M02_READ_ISSUING {1} CONFIG.M03_READ_ISSUING {1} CONFIG.M04_READ_ISSUING {1} CONFIG.M05_READ_ISSUING {1} CONFIG.M06_READ_ISSUING {1} CONFIG.M07_READ_ISSUING {1} CONFIG.M08_READ_ISSUING {1} CONFIG.M09_READ_ISSUING {1} CONFIG.M10_READ_ISSUING {1} CONFIG.M11_READ_ISSUING {1} CONFIG.M12_READ_ISSUING {1} CONFIG.M13_READ_ISSUING {1} CONFIG.M14_READ_ISSUING {1} CONFIG.M15_READ_ISSUING {1} \
                    CONFIG.S00_SINGLE_THREAD {1} CONFIG.M00_A00_BASE_ADDR  {0x0000000000%02x0000} CONFIG.M01_A00_BASE_ADDR {0x0000000000%02x0000} CONFIG.M02_A00_BASE_ADDR {0x0000000000%02x0000} CONFIG.M00_A00_ADDR_WIDTH {16} CONFIG.M01_A00_ADDR_WIDTH {16} CONFIG.M02_A00_ADDR_WIDTH {16} \
                    CONFIG.Component_Name {dyn_crossbar_$i}] \[get_ips dyn_crossbar_$i]" $offs [expr {$offs + 1}] [expr {$offs + 2}]    ]
        eval $cmd
    }
} else {
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
                    CONFIG.Component_Name {dyn_crossbar_$i}] \[get_ips dyn_crossbar_$i]" $offs [expr {$offs + 1}] [expr {$offs + 2}] [expr {$offs + 3}]   ]
        eval $cmd
    }
}

# Bypass ic
if {$cfg(en_bpss) eq 1} {
    create_ip -name axis_interconnect -vendor xilinx.com -library ip -version 1.1 -module_name axis_interconnect_cnfg_req_arbiter
    set_property -dict [list CONFIG.Component_Name {axis_interconnect_cnfg_req_arbiter} CONFIG.C_NUM_SI_SLOTS {2} CONFIG.SWITCH_TDATA_NUM_BYTES {12} CONFIG.HAS_TSTRB {false} CONFIG.HAS_TKEEP {false} CONFIG.HAS_TLAST {false} CONFIG.HAS_TID {false} CONFIG.HAS_TDEST {false} CONFIG.C_M00_AXIS_REG_CONFIG {1} CONFIG.SWITCH_PACKET_MODE {false} CONFIG.C_SWITCH_MAX_XFERS_PER_ARB {1} CONFIG.C_SWITCH_NUM_CYCLES_TIMEOUT {0} CONFIG.M00_AXIS_TDATA_NUM_BYTES {12} CONFIG.S00_AXIS_TDATA_NUM_BYTES {12} CONFIG.S01_AXIS_TDATA_NUM_BYTES {12} CONFIG.M00_S01_CONNECTIVITY {true}] [get_ips axis_interconnect_cnfg_req_arbiter]
}

# PR
if {$cfg(en_pr) eq 1} {
    create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name pr_clock_converter
    set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.Component_Name {pr_clock_converter}] [get_ips pr_clock_converter]

    create_ip -name axis_dwidth_converter -vendor xilinx.com -library ip -version 1.1 -module_name pr_dwidth_converter
    set_property -dict [list CONFIG.S_TDATA_NUM_BYTES {64} CONFIG.M_TDATA_NUM_BYTES {4} CONFIG.HAS_TLAST {1} CONFIG.HAS_TKEEP {1} CONFIG.HAS_MI_TKEEP {0} CONFIG.Component_Name {pr_dwidth_converter}] [get_ips pr_dwidth_converter]
}

# Data queues
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {256} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.Component_Name {axis_data_fifo_512}] [get_ips axis_data_fifo_512]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_1k
set_property -dict [list CONFIG.TDATA_NUM_BYTES {128} CONFIG.FIFO_DEPTH {256} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.Component_Name {axis_data_fifo_1k}] [get_ips axis_data_fifo_1k]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_2k
set_property -dict [list CONFIG.TDATA_NUM_BYTES {256} CONFIG.FIFO_DEPTH {256} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.Component_Name {axis_data_fifo_2k}] [get_ips axis_data_fifo_2k]

# Request queues
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_req_96_used
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.FIFO_DEPTH {64} CONFIG.HAS_WR_DATA_COUNT {1} CONFIG.Component_Name {axis_data_fifo_req_96_used}] [get_ips axis_data_fifo_req_96_used]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_req_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.FIFO_DEPTH {64} CONFIG.Component_Name {axis_data_fifo_req_96}] [get_ips axis_data_fifo_req_96]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_req_128
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.FIFO_DEPTH {64} CONFIG.Component_Name {axis_data_fifo_req_128}] [get_ips axis_data_fifo_req_128]

# Reg slices
create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_512_0
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.REG_CONFIG {8} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1}] [get_ips axis_register_slice_512_0]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_1k_0
set_property -dict [list CONFIG.TDATA_NUM_BYTES {128} CONFIG.REG_CONFIG {8} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1}] [get_ips axis_register_slice_1k_0]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_2k_0
set_property -dict [list CONFIG.TDATA_NUM_BYTES {256} CONFIG.REG_CONFIG {8} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1}] [get_ips axis_register_slice_2k_0]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axisr_register_slice_512_0
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.REG_CONFIG {8} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.TDEST_WIDTH {4}] [get_ips axisr_register_slice_512_0]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axisr_register_slice_1k_0
set_property -dict [list CONFIG.TDATA_NUM_BYTES {128} CONFIG.REG_CONFIG {8} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.TDEST_WIDTH {4}] [get_ips axisr_register_slice_1k_0]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axisr_register_slice_2k_0
set_property -dict [list CONFIG.TDATA_NUM_BYTES {256} CONFIG.REG_CONFIG {8} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.TDEST_WIDTH {4}] [get_ips axisr_register_slice_2k_0]

create_ip -name axi_register_slice -vendor xilinx.com -library ip -version 2.1 -module_name axi_register_slice_0
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {512} CONFIG.REG_AW {1} CONFIG.REG_AR {1} CONFIG.REG_B {1}] [get_ips axi_register_slice_0]

create_ip -name axi_register_slice -vendor xilinx.com -library ip -version 2.1 -module_name axil_register_slice_0
set_property -dict [list CONFIG.PROTOCOL {AXI4LITE} CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {64} CONFIG.REG_AW {1} CONFIG.REG_AR {1} CONFIG.REG_W {1} CONFIG.REG_R {1} CONFIG.REG_B {1} CONFIG.Component_Name {axil_register_slice_0}] [get_ips axil_register_slice_0]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_req_96_0
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.REG_CONFIG {8} CONFIG.Component_Name {axis_register_slice_req_96_0}] [get_ips axis_register_slice_req_96_0]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_meta_256_0
set_property -dict [list CONFIG.TDATA_NUM_BYTES {32} CONFIG.REG_CONFIG {8} CONFIG.Component_Name {axis_register_slice_meta_256_0}] [get_ips axis_register_slice_meta_256_0]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_meta_56_0
set_property -dict [list CONFIG.TDATA_NUM_BYTES {7} CONFIG.REG_CONFIG {8} CONFIG.Component_Name {axis_register_slice_meta_56_0}] [get_ips axis_register_slice_meta_56_0]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_meta_32_0
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.REG_CONFIG {8} CONFIG.Component_Name {axis_register_slice_meta_32_0}] [get_ips axis_register_slice_meta_32_0]