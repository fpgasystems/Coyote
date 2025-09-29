##
## SHELL IPs
##

# Reset sync
create_ip -name proc_sys_reset -vendor xilinx.com -library ip -version 5.0 -module_name proc_sys_reset_a;
set_property -dict [list CONFIG.C_EXT_RESET_HIGH {1}] [get_ips proc_sys_reset_a]

create_ip -name proc_sys_reset -vendor xilinx.com -library ip -version 5.0 -module_name proc_sys_reset_n;
set_property -dict [list CONFIG.C_EXT_RESET_HIGH {1}] [get_ips proc_sys_reset_n]

create_ip -name proc_sys_reset -vendor xilinx.com -library ip -version 5.0 -module_name proc_sys_reset_u;
set_property -dict [list CONFIG.C_EXT_RESET_HIGH {1}] [get_ips proc_sys_reset_u]

# HBM
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_hbm_r
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.TUSER_WIDTH {4} CONFIG.FIFO_DEPTH {128} CONFIG.HAS_TLAST {1} ] [get_ips axis_data_fifo_hbm_r]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_hbm_w
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {128} CONFIG.HAS_TSTRB {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_data_fifo_hbm_w]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_hbm_b
set_property -dict [list CONFIG.TDATA_NUM_BYTES {0} CONFIG.TUSER_WIDTH {4} CONFIG.FIFO_DEPTH {128} ] [get_ips axis_data_fifo_hbm_b]

# Stripe
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

update_compile_order -fileset sources_1
