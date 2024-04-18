#
# Register slices
#

# Common
create_ip -name axi_register_slice -vendor xilinx.com -library ip -version 2.1 -module_name axi_register_slice_512
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {512} CONFIG.REG_AW {1} CONFIG.REG_AR {1} CONFIG.REG_B {1} CONFIG.ID_WIDTH {6} CONFIG.MAX_BURST_LENGTH {14} CONFIG.NUM_READ_OUTSTANDING {32} CONFIG.NUM_WRITE_OUTSTANDING {32}] [get_ips axi_register_slice_512]

create_ip -name axi_register_slice -vendor xilinx.com -library ip -version 2.1 -module_name axil_register_slice
set_property -dict [list CONFIG.PROTOCOL {AXI4LITE} CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {64} CONFIG.REG_AW {1} CONFIG.REG_AR {1} CONFIG.REG_W {1} CONFIG.REG_R {1} CONFIG.REG_B {1} ] [get_ips axil_register_slice]

create_ip -name axi_register_slice -vendor xilinx.com -library ip -version 2.1 -module_name axim_register_slice
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {256} CONFIG.REG_AW {1} CONFIG.REG_AR {1} CONFIG.REG_B {1} CONFIG.ID_WIDTH {6} CONFIG.MAX_BURST_LENGTH {14} CONFIG.NUM_READ_OUTSTANDING {32} CONFIG.NUM_WRITE_OUTSTANDING {32}] [get_ips axim_register_slice]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.REG_CONFIG {8} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1}] [get_ips axis_register_slice_512]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axisr_register_slice_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.REG_CONFIG {8} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.TID_WIDTH {6}] [get_ips axisr_register_slice_512]

# Requests
create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_req_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_req_96]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_req_128
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_req_128]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_req_256
set_property -dict [list CONFIG.TDATA_NUM_BYTES {32} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_req_256]

# Meta
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

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_meta_72
set_property -dict [list CONFIG.TDATA_NUM_BYTES {9} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_meta_72]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_meta_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_meta_96]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_meta_128
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_meta_128]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_meta_256
set_property -dict [list CONFIG.TDATA_NUM_BYTES {32} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_meta_256]

create_ip -name axis_register_slice -vendor xilinx.com -library ip -version 1.1 -module_name axis_register_slice_meta_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.REG_CONFIG {8} ] [get_ips axis_register_slice_meta_512]

#
# CCross
#

# Common
create_ip -name axi_clock_converter -vendor xilinx.com -library ip -version 2.1 -module_name axi_clock_converter_512
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {512} CONFIG.ID_WIDTH {6}] [get_ips axi_clock_converter_512]

create_ip -name axi_clock_converter -vendor xilinx.com -library ip -version 2.1 -module_name axi_clock_converter_256
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {256} CONFIG.ID_WIDTH {6}] [get_ips axi_clock_converter_256]

create_ip -name axi_clock_converter -vendor xilinx.com -library ip -version 2.1 -module_name axil_clock_converter
set_property -dict [list CONFIG.PROTOCOL {AXI4LITE} CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {64} CONFIG.ID_WIDTH {0} CONFIG.AWUSER_WIDTH {0} CONFIG.ARUSER_WIDTH {0} CONFIG.RUSER_WIDTH {0} CONFIG.WUSER_WIDTH {0} CONFIG.BUSER_WIDTH {0}] [get_ips axil_clock_converter]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} ] [get_ips axis_clock_converter_512]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axisr_clock_converter_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} CONFIG.TID_WIDTH {6}] [get_ips axisr_clock_converter_512]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} ] [get_ips axis_clock_converter_96]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name axis_clock_converter_dma_rsp
set_property -dict [list CONFIG.TDATA_NUM_BYTES {0} CONFIG.TUSER_WIDTH {6} CONFIG.SYNCHRONIZATION_STAGES {2} ] [get_ips axis_clock_converter_dma_rsp]

# Meta
create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name meta_clock_converter_8
set_property -dict [list CONFIG.TDATA_NUM_BYTES {1} ] [get_ips meta_clock_converter_8]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name meta_clock_converter_16
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} ] [get_ips meta_clock_converter_16]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name meta_clock_converter_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} ] [get_ips meta_clock_converter_32]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name meta_clock_converter_64
set_property -dict [list CONFIG.TDATA_NUM_BYTES {8} ] [get_ips meta_clock_converter_64]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name meta_clock_converter_72
set_property -dict [list CONFIG.TDATA_NUM_BYTES {9} ] [get_ips meta_clock_converter_72]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name meta_clock_converter_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} ] [get_ips meta_clock_converter_96]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name meta_clock_converter_128
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} ] [get_ips meta_clock_converter_128]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name meta_clock_converter_256
set_property -dict [list CONFIG.TDATA_NUM_BYTES {32} ] [get_ips meta_clock_converter_256]

create_ip -name axis_clock_converter -vendor xilinx.com -library ip -version 1.1 -module_name meta_clock_converter_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} ] [get_ips meta_clock_converter_512]

#
# FIFOs
#

# Requests
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_req_96_used
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.FIFO_DEPTH {32} CONFIG.HAS_WR_DATA_COUNT {1} ] [get_ips axis_data_fifo_req_96_used]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_req_128_used
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.FIFO_DEPTH {32} CONFIG.HAS_WR_DATA_COUNT {1} ] [get_ips axis_data_fifo_req_128_used]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_req_256_used
set_property -dict [list CONFIG.TDATA_NUM_BYTES {32} CONFIG.FIFO_DEPTH {32} CONFIG.HAS_WR_DATA_COUNT {1} ] [get_ips axis_data_fifo_req_256_used]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_req_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_req_96]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_req_128
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_req_128]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_req_256
set_property -dict [list CONFIG.TDATA_NUM_BYTES {32} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_req_256]

# Meta
create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_meta_8
set_property -dict [list CONFIG.TDATA_NUM_BYTES {1} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_meta_8]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_meta_16
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_meta_16]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_meta_32
set_property -dict [list CONFIG.TDATA_NUM_BYTES {4} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_meta_32]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_meta_64
set_property -dict [list CONFIG.TDATA_NUM_BYTES {8} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_meta_64]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_meta_96
set_property -dict [list CONFIG.TDATA_NUM_BYTES {12} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_meta_96]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_meta_128
set_property -dict [list CONFIG.TDATA_NUM_BYTES {16} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_meta_128]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_meta_256
set_property -dict [list CONFIG.TDATA_NUM_BYTES {32} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_meta_256]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_meta_512
set_property -dict [list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {32} ] [get_ips axis_data_fifo_meta_512]

#
# Data queues
#

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
if {$cfg(pmtu) > 8192} {
    set nn 16384
}
if {$cfg(pmtu) > 16384} {
    set nn 32768
}
set nn512 [expr {$cfg(n_outs) * ($nn / 64)}]

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axis_data_fifo_512
set cmd "set_property -dict \[list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {$nn512} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1} ] \[get_ips axis_data_fifo_512]"
eval $cmd

create_ip -name axis_data_fifo -vendor xilinx.com -library ip -version 2.0 -module_name axisr_data_fifo_512
set cmd "set_property -dict \[list CONFIG.TDATA_NUM_BYTES {64} CONFIG.FIFO_DEPTH {$nn512} CONFIG.HAS_TKEEP {1} CONFIG.HAS_TLAST {1}  CONFIG.TID_WIDTH {6}] \[get_ips axisr_data_fifo_512]"
eval $cmd
