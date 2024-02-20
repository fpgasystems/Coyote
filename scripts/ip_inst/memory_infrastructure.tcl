##
## MEM WRAPPER
##

##
## DDRs
## 
create_ip -name proc_sys_reset -vendor xilinx.com -library ip -version 5.0 -module_name proc_sys_reset_ddr
set_property -dict [list CONFIG.C_EXT_RESET_HIGH {1}] [get_ips proc_sys_reset_ddr]

# DDR cores
# u250
if {$cfg(fdev) eq "u250"} {
    
    if {$cfg(ddr_0) eq 1} {
        # Create instance: ddr4_0, and set properties
        create_ip -name ddr4 -vendor xilinx.com -library ip -module_name ddr4_0
        set_property -dict [ list \
            CONFIG.C0.DDR4_AxiSelection {true} \
            CONFIG.C0.BANK_GROUP_WIDTH {2} \
            CONFIG.C0.CKE_WIDTH {1} \
            CONFIG.C0.CS_WIDTH {1} \
            CONFIG.C0.ODT_WIDTH {1} \
            CONFIG.C0.ControllerType {DDR4_SDRAM} \
            CONFIG.C0.DDR4_AxiAddressWidth {34} \
            CONFIG.C0.DDR4_AxiDataWidth {512} \
            CONFIG.C0.DDR4_CLKOUT0_DIVIDE {5} \
            CONFIG.C0.DDR4_CasLatency {17} \
            CONFIG.C0.DDR4_CasWriteLatency {12} \
            CONFIG.C0.DDR4_DataMask {NONE} \
            CONFIG.C0.DDR4_DataWidth {72} \
            CONFIG.C0.DDR4_Ecc {true} \
            CONFIG.C0.DDR4_InputClockPeriod {3332} \
            CONFIG.C0.DDR4_MemoryPart {MTA18ASF2G72PZ-2G3} \
            CONFIG.C0.DDR4_MemoryType {RDIMMs} \
            CONFIG.C0.DDR4_TimePeriod {833} \
            CONFIG.C0.DDR4_AUTO_AP_COL_A3 {true} \
            CONFIG.C0.DDR4_Mem_Add_Map {ROW_COLUMN_BANK_INTLV} \
        ] [get_ips ddr4_0]
    }

    if {$cfg(ddr_1) eq 1} {
        # Create instance: ddr4_1, and set properties
        create_ip -name ddr4 -vendor xilinx.com -library ip -module_name ddr4_1
        set_property -dict [ list \
            CONFIG.C0.DDR4_AxiSelection {true} \
            CONFIG.C0.BANK_GROUP_WIDTH {2} \
            CONFIG.C0.CKE_WIDTH {1} \
            CONFIG.C0.CS_WIDTH {1} \
            CONFIG.C0.ODT_WIDTH {1} \
            CONFIG.C0.ControllerType {DDR4_SDRAM} \
            CONFIG.C0.DDR4_AxiAddressWidth {34} \
            CONFIG.C0.DDR4_AxiDataWidth {512} \
            CONFIG.C0.DDR4_CLKOUT0_DIVIDE {5} \
            CONFIG.C0.DDR4_CasLatency {17} \
            CONFIG.C0.DDR4_CasWriteLatency {12} \
            CONFIG.C0.DDR4_DataMask {NONE} \
            CONFIG.C0.DDR4_DataWidth {72} \
            CONFIG.C0.DDR4_Ecc {true} \
            CONFIG.C0.DDR4_InputClockPeriod {3332} \
            CONFIG.C0.DDR4_MemoryPart {MTA18ASF2G72PZ-2G3} \
            CONFIG.C0.DDR4_MemoryType {RDIMMs} \
            CONFIG.C0.DDR4_TimePeriod {833} \
            CONFIG.C0.DDR4_AUTO_AP_COL_A3 {true} \
            CONFIG.C0.DDR4_Mem_Add_Map {ROW_COLUMN_BANK_INTLV} \
        ] [get_ips ddr4_1]
    }

    if {$cfg(ddr_2) eq 1} {
        # Create instance: ddr4_2, and set properties
        create_ip -name ddr4 -vendor xilinx.com -library ip -module_name ddr4_2
        set_property -dict [ list \
            CONFIG.C0.DDR4_AxiSelection {true} \
            CONFIG.C0.BANK_GROUP_WIDTH {2} \
            CONFIG.C0.CKE_WIDTH {1} \
            CONFIG.C0.CS_WIDTH {1} \
            CONFIG.C0.ODT_WIDTH {1} \
            CONFIG.C0.ControllerType {DDR4_SDRAM} \
            CONFIG.C0.DDR4_AxiAddressWidth {34} \
            CONFIG.C0.DDR4_AxiDataWidth {512} \
            CONFIG.C0.DDR4_CLKOUT0_DIVIDE {5} \
            CONFIG.C0.DDR4_CasLatency {17} \
            CONFIG.C0.DDR4_CasWriteLatency {12} \
            CONFIG.C0.DDR4_DataMask {NONE} \
            CONFIG.C0.DDR4_DataWidth {72} \
            CONFIG.C0.DDR4_Ecc {true} \
            CONFIG.C0.DDR4_InputClockPeriod {3332} \
            CONFIG.C0.DDR4_MemoryPart {MTA18ASF2G72PZ-2G3} \
            CONFIG.C0.DDR4_MemoryType {RDIMMs} \
            CONFIG.C0.DDR4_TimePeriod {833} \
            CONFIG.C0.DDR4_AUTO_AP_COL_A3 {true} \
            CONFIG.C0.DDR4_Mem_Add_Map {ROW_COLUMN_BANK_INTLV} \
        ] [get_ips ddr4_2]
    }

    if {$cfg(ddr_3) eq 1} {
        # Create instance: ddr4_3, and set properties
        create_ip -name ddr4 -vendor xilinx.com -library ip -module_name ddr4_3
        set_property -dict [ list \
            CONFIG.C0.DDR4_AxiSelection {true} \
            CONFIG.C0.BANK_GROUP_WIDTH {2} \
            CONFIG.C0.CKE_WIDTH {1} \
            CONFIG.C0.CS_WIDTH {1} \
            CONFIG.C0.ODT_WIDTH {1} \
            CONFIG.C0.ControllerType {DDR4_SDRAM} \
            CONFIG.C0.DDR4_AxiAddressWidth {34} \
            CONFIG.C0.DDR4_AxiDataWidth {512} \
            CONFIG.C0.DDR4_CLKOUT0_DIVIDE {5} \
            CONFIG.C0.DDR4_CasLatency {17} \
            CONFIG.C0.DDR4_CasWriteLatency {12} \
            CONFIG.C0.DDR4_DataMask {NONE} \
            CONFIG.C0.DDR4_DataWidth {72} \
            CONFIG.C0.DDR4_Ecc {true} \
            CONFIG.C0.DDR4_InputClockPeriod {3332} \
            CONFIG.C0.DDR4_MemoryPart {MTA18ASF2G72PZ-2G3} \
            CONFIG.C0.DDR4_MemoryType {RDIMMs} \
            CONFIG.C0.DDR4_TimePeriod {833} \
            CONFIG.C0.DDR4_AUTO_AP_COL_A3 {true} \
            CONFIG.C0.DDR4_Mem_Add_Map {ROW_COLUMN_BANK_INTLV} \
        ] [get_ips ddr4_3]
    }

}

# u280
if {$cfg(fdev) eq "u280"} {

    if {$cfg(ddr_0) eq 1} {
        # Create instance: ddr4_0, and set properties
        create_ip -name ddr4 -vendor xilinx.com -library ip -module_name ddr4_0
        set_property -dict [ list \
            CONFIG.C0.DDR4_AxiSelection {true} \
            CONFIG.C0.BANK_GROUP_WIDTH {2} \
            CONFIG.C0.CKE_WIDTH {1} \
            CONFIG.C0.CS_WIDTH {1} \
            CONFIG.C0.ODT_WIDTH {1} \
            CONFIG.C0.ControllerType {DDR4_SDRAM} \
            CONFIG.C0.DDR4_AxiAddressWidth {34} \
            CONFIG.C0.DDR4_AxiDataWidth {512} \
            CONFIG.C0.DDR4_CLKOUT0_DIVIDE {5} \
            CONFIG.C0.DDR4_CasLatency {17} \
            CONFIG.C0.DDR4_CasWriteLatency {12} \
            CONFIG.C0.DDR4_DataMask {NONE} \
            CONFIG.C0.DDR4_DataWidth {72} \
            CONFIG.C0.DDR4_Ecc {true} \
            CONFIG.C0.DDR4_InputClockPeriod {9996} \
            CONFIG.C0.DDR4_MemoryPart {MTA18ASF2G72PZ-2G3} \
            CONFIG.C0.DDR4_MemoryType {RDIMMs} \
            CONFIG.C0.DDR4_TimePeriod {833} \
            CONFIG.C0.DDR4_AUTO_AP_COL_A3 {true} \
            CONFIG.C0.DDR4_Mem_Add_Map {ROW_COLUMN_BANK_INTLV} \
        ] [get_ips ddr4_0]
    }

    if {$cfg(ddr_1) eq 1} {
        # Create instance: ddr4_1, and set properties
        create_ip -name ddr4 -vendor xilinx.com -library ip -module_name ddr4_1
        set_property -dict [ list \
            CONFIG.C0.DDR4_AxiSelection {true} \
            CONFIG.C0.BANK_GROUP_WIDTH {2} \
            CONFIG.C0.CKE_WIDTH {1} \
            CONFIG.C0.CS_WIDTH {1} \
            CONFIG.C0.ODT_WIDTH {1} \
            CONFIG.C0.ControllerType {DDR4_SDRAM} \
            CONFIG.C0.DDR4_AxiAddressWidth {34} \
            CONFIG.C0.DDR4_AxiDataWidth {512} \
            CONFIG.C0.DDR4_CLKOUT0_DIVIDE {5} \
            CONFIG.C0.DDR4_CasLatency {17} \
            CONFIG.C0.DDR4_CasWriteLatency {12} \
            CONFIG.C0.DDR4_DataMask {NONE} \
            CONFIG.C0.DDR4_DataWidth {72} \
            CONFIG.C0.DDR4_Ecc {true} \
            CONFIG.C0.DDR4_InputClockPeriod {9996} \
            CONFIG.C0.DDR4_MemoryPart {MTA18ASF2G72PZ-2G3} \
            CONFIG.C0.DDR4_MemoryType {RDIMMs} \
            CONFIG.C0.DDR4_TimePeriod {833} \
            CONFIG.C0.DDR4_AUTO_AP_COL_A3 {true} \
            CONFIG.C0.DDR4_Mem_Add_Map {ROW_COLUMN_BANK_INTLV} \
        ] [get_ips ddr4_1]
    }

}

# vcu118
if {$cfg(fdev) eq "vcu118"} {
    
    if {$cfg(ddr_0) eq 1} {
        # Create instance: ddr4_0, and set properties
        create_ip -name ddr4 -vendor xilinx.com -library ip -module_name ddr4_0
        set_property -dict [ list \
            CONFIG.C0.DDR4_AxiSelection {true} \
            CONFIG.C0.BANK_GROUP_WIDTH {1} \
            CONFIG.C0.DDR4_AxiAddressWidth {31} \
            CONFIG.C0.DDR4_AxiDataWidth {512} \
            CONFIG.C0.DDR4_CLKOUT0_DIVIDE {5} \
            CONFIG.C0.DDR4_CasWriteLatency {12} \
            CONFIG.C0.DDR4_DataMask {DM_NO_DBI} \
            CONFIG.C0.DDR4_DataWidth {64} \
            CONFIG.C0.DDR4_Ecc {false} \
            CONFIG.C0.DDR4_InputClockPeriod {4000} \
            CONFIG.C0.DDR4_MemoryPart {MT40A256M16GE-083E} \
            CONFIG.C0.DDR4_TimePeriod {833} \
        ] [get_ips ddr4_0]
    }

    if {$cfg(ddr_1) eq 1} {
        # Create instance: ddr4_1, and set properties
        create_ip -name ddr4 -vendor xilinx.com -library ip -module_name ddr4_1
        set_property -dict [ list \
            CONFIG.C0.DDR4_AxiSelection {true} \
            CONFIG.C0.BANK_GROUP_WIDTH {1} \
            CONFIG.C0.DDR4_AxiAddressWidth {31} \
            CONFIG.C0.DDR4_AxiDataWidth {512} \
            CONFIG.C0.DDR4_CLKOUT0_DIVIDE {5} \
            CONFIG.C0.DDR4_CasWriteLatency {12} \
            CONFIG.C0.DDR4_DataMask {DM_NO_DBI} \
            CONFIG.C0.DDR4_DataWidth {64} \
            CONFIG.C0.DDR4_Ecc {false} \
            CONFIG.C0.DDR4_InputClockPeriod {4000} \
            CONFIG.C0.DDR4_MemoryPart {MT40A256M16GE-083E} \
            CONFIG.C0.DDR4_TimePeriod {833} \
        ] [get_ips ddr4_1]
    }
}

# Enzian
if {$cfg(fdev) eq "enzian"} {

    if {$cfg(ddr_0) eq 1} {
        # Create instance: ddr4_0, and set properties
        create_ip -name ddr4 -vendor xilinx.com -library ip -module_name ddr4_0
        set_property -dict [ list \
            CONFIG.C0.DDR4_AxiSelection {true} \
            CONFIG.C0.CKE_WIDTH {2} \
            CONFIG.C0.CS_WIDTH {2} \
            CONFIG.C0.DDR4_AxiAddressWidth {37} \
            CONFIG.C0.DDR4_AxiDataWidth {512} \
            CONFIG.C0.DDR4_CLKOUT0_DIVIDE {6} \
            CONFIG.C0.DDR4_CasLatency {18} \
            CONFIG.C0.DDR4_CasWriteLatency {11} \
            CONFIG.C0.DDR4_DataMask {NONE} \
            CONFIG.C0.DDR4_DataWidth {72} \
            CONFIG.C0.DDR4_EN_PARITY {true} \
            CONFIG.C0.DDR4_Ecc {true} \
            CONFIG.C0.DDR4_InputClockPeriod {10005} \
            CONFIG.C0.DDR4_MemoryPart {MTA144ASQ16G72LSZ-2S6} \
            CONFIG.C0.DDR4_MemoryType {LRDIMMs} \
            CONFIG.C0.DDR4_TimePeriod {938} \
            CONFIG.C0.DDR4_isCustom {true} \
            CONFIG.C0.LR_WIDTH {2} \
            CONFIG.C0.ODT_WIDTH {2} \
            CONFIG.C0.StackHeight {4} \
        ] [get_ips ddr4_0]
    }

    if {$cfg(ddr_1) eq 1} {
        # Create instance: ddr4_1, and set properties
        create_ip -name ddr4 -vendor xilinx.com -library ip -module_name ddr4_1
        set_property -dict [ list \
            CONFIG.C0.DDR4_AxiSelection {true} \
            CONFIG.C0.CKE_WIDTH {2} \
            CONFIG.C0.CS_WIDTH {2} \
            CONFIG.C0.DDR4_AxiAddressWidth {37} \
            CONFIG.C0.DDR4_AxiDataWidth {512} \
            CONFIG.C0.DDR4_CLKOUT0_DIVIDE {6} \
            CONFIG.C0.DDR4_CasLatency {18} \
            CONFIG.C0.DDR4_CasWriteLatency {11} \
            CONFIG.C0.DDR4_DataMask {NONE} \
            CONFIG.C0.DDR4_DataWidth {72} \
            CONFIG.C0.DDR4_EN_PARITY {true} \
            CONFIG.C0.DDR4_Ecc {true} \
            CONFIG.C0.DDR4_InputClockPeriod {10005} \
            CONFIG.C0.DDR4_MemoryPart {MTA144ASQ16G72LSZ-2S6} \
            CONFIG.C0.DDR4_MemoryType {LRDIMMs} \
            CONFIG.C0.DDR4_TimePeriod {938} \
            CONFIG.C0.DDR4_isCustom {true} \
            CONFIG.C0.LR_WIDTH {2} \
            CONFIG.C0.ODT_WIDTH {2} \
            CONFIG.C0.StackHeight {4} \
        ] [get_ips ddr4_1]
    }

    if {$cfg(ddr_2) eq 1} {
        # Create instance: ddr4_2, and set properties
        create_ip -name ddr4 -vendor xilinx.com -library ip -module_name ddr4_2
        set_property -dict [ list \
            CONFIG.C0.DDR4_AxiSelection {true} \
            CONFIG.C0.CKE_WIDTH {2} \
            CONFIG.C0.CS_WIDTH {2} \
            CONFIG.C0.DDR4_AxiAddressWidth {37} \
            CONFIG.C0.DDR4_AxiDataWidth {512} \
            CONFIG.C0.DDR4_CLKOUT0_DIVIDE {6} \
            CONFIG.C0.DDR4_CasLatency {18} \
            CONFIG.C0.DDR4_CasWriteLatency {11} \
            CONFIG.C0.DDR4_DataMask {NONE} \
            CONFIG.C0.DDR4_DataWidth {72} \
            CONFIG.C0.DDR4_EN_PARITY {true} \
            CONFIG.C0.DDR4_Ecc {true} \
            CONFIG.C0.DDR4_InputClockPeriod {10005} \
            CONFIG.C0.DDR4_MemoryPart {MTA144ASQ16G72LSZ-2S6} \
            CONFIG.C0.DDR4_MemoryType {LRDIMMs} \
            CONFIG.C0.DDR4_TimePeriod {938} \
            CONFIG.C0.DDR4_isCustom {true} \
            CONFIG.C0.LR_WIDTH {2} \
            CONFIG.C0.ODT_WIDTH {2} \
            CONFIG.C0.StackHeight {4} \
        ] [get_ips ddr4_2]
    }

    if {$cfg(ddr_3) eq 1} {
        # Create instance: ddr4_3, and set properties
        create_ip -name ddr4 -vendor xilinx.com -library ip -module_name ddr4_3
        set_property -dict [ list \
            CONFIG.C0.DDR4_AxiSelection {true} \
            CONFIG.C0.CKE_WIDTH {2} \
            CONFIG.C0.CS_WIDTH {2} \
            CONFIG.C0.DDR4_AxiAddressWidth {37} \
            CONFIG.C0.DDR4_AxiDataWidth {512} \
            CONFIG.C0.DDR4_CLKOUT0_DIVIDE {6} \
            CONFIG.C0.DDR4_CasLatency {18} \
            CONFIG.C0.DDR4_CasWriteLatency {11} \
            CONFIG.C0.DDR4_DataMask {NONE} \
            CONFIG.C0.DDR4_DataWidth {72} \
            CONFIG.C0.DDR4_EN_PARITY {true} \
            CONFIG.C0.DDR4_Ecc {true} \
            CONFIG.C0.DDR4_InputClockPeriod {10005} \
            CONFIG.C0.DDR4_MemoryPart {MTA144ASQ16G72LSZ-2S6} \
            CONFIG.C0.DDR4_MemoryType {LRDIMMs} \
            CONFIG.C0.DDR4_TimePeriod {938} \
            CONFIG.C0.DDR4_isCustom {true} \
            CONFIG.C0.LR_WIDTH {2} \
            CONFIG.C0.ODT_WIDTH {2} \
            CONFIG.C0.StackHeight {4} \
        ] [get_ips ddr4_3]
    }

}

create_ip -name axi_register_slice -vendor xilinx.com -library ip -version 2.1 -module_name axi_reg_ddr_sink_int
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {512} CONFIG.ID_WIDTH {4} ] [get_ips axi_reg_ddr_sink_int]

create_ip -name axi_data_fifo -vendor xilinx.com -library ip -version 2.1 -module_name axi_data_fifo_ddr_sink_int
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {512} CONFIG.ID_WIDTH {4} CONFIG.WRITE_FIFO_DEPTH {512} CONFIG.READ_FIFO_DEPTH {512} CONFIG.WRITE_FIFO_DELAY {1} CONFIG.READ_FIFO_DELAY {1}] [get_ips axi_data_fifo_ddr_sink_int]

# DDR xbar
create_ip -name axi_crossbar -vendor xilinx.com -library ip -version 2.1 -module_name ddr_xbar
set cmd [format "set_property -dict \[list \
    CONFIG.NUM_SI {$cfg(n_mem_chan)} \
    CONFIG.NUM_MI {$cfg(n_ddr_chan)} \
    CONFIG.ADDR_WIDTH {64} \
    CONFIG.STRATEGY {1} \
    CONFIG.DATA_WIDTH {512} \
    CONFIG.CONNECTIVITY_MODE {SAMD} \
    CONFIG.ID_WIDTH {4} \
    CONFIG.S01_BASE_ID {0x00000004} \
    CONFIG.S02_BASE_ID {0x00000008} \
    CONFIG.S03_BASE_ID {0x0000000c} \
    CONFIG.S04_BASE_ID {0x00000010} \
    CONFIG.S05_BASE_ID {0x00000014} \
    CONFIG.S06_BASE_ID {0x00000018} \
    CONFIG.S07_BASE_ID {0x0000001c} \
    CONFIG.S08_BASE_ID {0x00000020} \
    CONFIG.S09_BASE_ID {0x00000024} \
    CONFIG.S10_BASE_ID {0x00000028} \
    CONFIG.S11_BASE_ID {0x0000002c} \
    CONFIG.S12_BASE_ID {0x00000030} \
    CONFIG.S13_BASE_ID {0x00000034} \
    CONFIG.S14_BASE_ID {0x00000038} \
    CONFIG.S15_BASE_ID {0x0000003c} "]
    for {set i 0}  {$i < $cfg(n_mem_chan)} {incr i} {
        append cmd [format "CONFIG.S%02d_THREAD_ID_WIDTH {1} " $i]
        append cmd [format "CONFIG.S%02d_WRITE_ACCEPTANCE {8} " $i]
        append cmd [format "CONFIG.S%02d_READ_ACCEPTANCE {8} " $i]
    }
    for {set i 0}  {$i < $cfg(n_ddr_chan)} {incr i} {
        append cmd [format "CONFIG.M%02d_WRITE_ISSUING {8} " $i]
        append cmd [format "CONFIG.M%02d_READ_ISSUING {8} " $i]
        append cmd [format "CONFIG.M%02d_A00_ADDR_WIDTH {34} " $i] 
        append cmd [format "CONFIG.M%02d_A00_BASE_ADDR {0x00000%03x00000000} "  $i [expr {$i*4}]]
    }
append cmd "] \[get_ips ddr_xbar]"
eval $cmd

create_ip -name axi_register_slice -vendor xilinx.com -library ip -version 2.1 -module_name axi_reg_ddr_src_int
set_property -dict [list CONFIG.ADDR_WIDTH {34} CONFIG.DATA_WIDTH {512} CONFIG.ID_WIDTH {4} ] [get_ips axi_reg_ddr_src_int]

create_ip -name axi_data_fifo -vendor xilinx.com -library ip -version 2.1 -module_name axi_data_fifo_ddr_src_int
set_property -dict [list CONFIG.ADDR_WIDTH {34} CONFIG.DATA_WIDTH {512} CONFIG.ID_WIDTH {4} CONFIG.WRITE_FIFO_DEPTH {512} CONFIG.READ_FIFO_DEPTH {512} CONFIG.WRITE_FIFO_DELAY {1} CONFIG.READ_FIFO_DELAY {1}] [get_ips axi_data_fifo_ddr_src_int]

create_ip -name axi_clock_converter -vendor xilinx.com -library ip -version 2.1 -module_name axi_ccross_ddr_src_int
set_property -dict [list CONFIG.ADDR_WIDTH {34} CONFIG.DATA_WIDTH {512} CONFIG.ID_WIDTH {4}] [get_ips axi_ccross_ddr_src_int]