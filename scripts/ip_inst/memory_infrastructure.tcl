##
## MEMORY IPs
## 

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
# NOTE: vcu118 is no longer actively supported in Coyote and the below IP instantiation remains only for reference
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
# NOTE: Enzian is no longer actively supported in Coyote and the below IP instantiation remains only for reference
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
