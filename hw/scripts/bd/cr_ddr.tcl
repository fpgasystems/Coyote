# Main DDR
proc cr_bd_design_ddr { parentCell } {
  upvar #0 cfg cnfg

  # CHANGE DESIGN NAME HERE
  set design_name design_ddr

  common::send_msg_id "BD_TCL-003" "INFO" "Currently there is no design <$design_name> in project, so creating one..."

  create_bd_design $design_name

  set bCheckIPsPassed 1
  ########################################################################################################
  # CHECK IPs
  ########################################################################################################
  set bCheckIPs 1
  if { $bCheckIPs == 1 } {
     set list_check_ips "\
  xilinx.com:ip:ddr4:2.2\
  xilinx.com:ip:proc_sys_reset:5.0\
  "

   set list_ips_missing ""
   common::send_msg_id "BD_TCL-006" "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_msg_id "BD_TCL-115" "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

  }

  if { $bCheckIPsPassed != 1 } {
    common::send_msg_id "BD_TCL-1003" "WARNING" "Will not continue with creation of design due to the error(s) above."
    return 3
  }

  variable script_folder

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_msg_id "BD_TCL-100" "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_msg_id "BD_TCL-101" "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

########################################################################################################
########################################################################################################
# DDR
########################################################################################################
########################################################################################################

########################################################################################################
# Create all ports
########################################################################################################

# u250
if {$cnfg(fdev) eq "u250"} {
    set ecc 1

    # Interfaces
    if {$cnfg(ddr_0) eq 1} {
        set c0_ddr4 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 c0_ddr4 ]
        set c0_sys_clk_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 c0_sys_clk_0 ]
        set_property -dict [ list \
        CONFIG.FREQ_HZ {300000000} \
        ] $c0_sys_clk_0

        set axi_ctrl_ddr_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_ctrl_ddr_0 ]
        set_property -dict [ list \
        CONFIG.PROTOCOL {AXI4LITE} \
        CONFIG.FREQ_HZ {300000000} \
        CONFIG.MAX_BURST_LENGTH {1} \
        CONFIG.SUPPORTS_NARROW_BURST {0} \
        ] $axi_ctrl_ddr_0
    }

    if {$cnfg(ddr_1) eq 1} {
        set c1_ddr4 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 c1_ddr4 ]
        set c1_sys_clk_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 c1_sys_clk_0 ]
        set_property -dict [ list \
        CONFIG.FREQ_HZ {300000000} \
        ] $c1_sys_clk_0

        set axi_ctrl_ddr_1 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_ctrl_ddr_1 ]
        set_property -dict [ list \
        CONFIG.PROTOCOL {AXI4LITE} \
        CONFIG.FREQ_HZ {300000000} \
        CONFIG.MAX_BURST_LENGTH {1} \
        CONFIG.SUPPORTS_NARROW_BURST {0} \
        ] $axi_ctrl_ddr_1
    }

    if {$cnfg(ddr_2) eq 1} {
        set c2_ddr4 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 c2_ddr4 ]
        set c2_sys_clk_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 c2_sys_clk_0 ]
        set_property -dict [ list \
        CONFIG.FREQ_HZ {300000000} \
        ] $c2_sys_clk_0

        set axi_ctrl_ddr_2 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_ctrl_ddr_2 ]
        set_property -dict [ list \
        CONFIG.PROTOCOL {AXI4LITE} \
        CONFIG.FREQ_HZ {300000000} \
        CONFIG.MAX_BURST_LENGTH {1} \
        CONFIG.SUPPORTS_NARROW_BURST {0} \
        ] $axi_ctrl_ddr_2
    }

    if {$cnfg(ddr_3) eq 1} {
        set c3_ddr4 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 c3_ddr4 ]
        set c3_sys_clk_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 c3_sys_clk_0 ]
        set_property -dict [ list \
        CONFIG.FREQ_HZ {300000000} \
        ] $c3_sys_clk_0

        set axi_ctrl_ddr_3 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_ctrl_ddr_3 ]
        set_property -dict [ list \
        CONFIG.PROTOCOL {AXI4LITE} \
        CONFIG.FREQ_HZ {300000000} \
        CONFIG.MAX_BURST_LENGTH {1} \
        CONFIG.SUPPORTS_NARROW_BURST {0} \
        ] $axi_ctrl_ddr_3
    }

    # Components
    if {$cnfg(ddr_0) eq 1} {
        # Create instance: ddr4_0, and set properties
        set ddr4_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4:2.2 ddr4_0 ]
        set_property -dict [ list \
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
        ] $ddr4_0


        # Create instance: rst_ddr4_0_300M, and set properties
        set rst_ddr4_0_300M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ddr4_0_300M ]
    }

    if {$cnfg(ddr_1) eq 1} {
        # Create instance: ddr4_1, and set properties
        set ddr4_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4:2.2 ddr4_1 ]
        set_property -dict [ list \
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
        ] $ddr4_1

        # Create instance: rst_ddr4_1_300M, and set properties
        set rst_ddr4_1_300M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ddr4_1_300M ]
    }

    if {$cnfg(ddr_2) eq 1} {
        # Create instance: ddr4_2, and set properties
        set ddr4_2 [ create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4:2.2 ddr4_2 ]
        set_property -dict [ list \
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
        ] $ddr4_2

        # Create instance: rst_ddr4_0_300M, and set properties
        set rst_ddr4_2_300M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ddr4_2_300M ]
    }

    if {$cnfg(ddr_3) eq 1} {
        # Create instance: ddr4_3, and set properties
        set ddr4_3 [ create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4:2.2 ddr4_3 ]
        set_property -dict [ list \
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
        ] $ddr4_3

        # Create instance: rst_ddr4_0_300M, and set properties
        set rst_ddr4_3_300M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ddr4_3_300M ]
    }

}

# u280
if {$cnfg(fdev) eq "u280"} {
    set ecc 1

    # Interfaces
    if {$cnfg(ddr_0) eq 1} {
        set c0_ddr4 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 c0_ddr4 ]
        set c0_sys_clk_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 c0_sys_clk_0 ]
        set_property -dict [ list \
            CONFIG.FREQ_HZ {100000000} \
        ] $c0_sys_clk_0

        set axi_ctrl_ddr_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_ctrl_ddr_0 ]
        set_property -dict [ list \
            CONFIG.PROTOCOL {AXI4LITE} \
            CONFIG.FREQ_HZ {300000000} \
            CONFIG.MAX_BURST_LENGTH {1} \
            CONFIG.SUPPORTS_NARROW_BURST {0} \
        ] $axi_ctrl_ddr_0
    }

    if {$cnfg(ddr_1) eq 1} {
        set c1_ddr4 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 c1_ddr4 ]
        set c1_sys_clk_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 c1_sys_clk_0 ]
        set_property -dict [ list \
            CONFIG.FREQ_HZ {100000000} \
        ] $c1_sys_clk_0

        set axi_ctrl_ddr_1 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_ctrl_ddr_1 ]
        set_property -dict [ list \
            CONFIG.PROTOCOL {AXI4LITE} \
            CONFIG.FREQ_HZ {300000000} \
            CONFIG.MAX_BURST_LENGTH {1} \
            CONFIG.SUPPORTS_NARROW_BURST {0} \
        ] $axi_ctrl_ddr_1
    }

    # Components
    if {$cnfg(ddr_0) eq 1} {
        # Create instance: ddr4_0, and set properties
        set ddr4_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4:2.2 ddr4_0 ]
        set_property -dict [ list \
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
        ] $ddr4_0


        # Create instance: rst_ddr4_0_300M, and set properties
        set rst_ddr4_0_300M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ddr4_0_300M ]
    }

    if {$cnfg(ddr_1) eq 1} {
        # Create instance: ddr4_1, and set properties
        set ddr4_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4:2.2 ddr4_1 ]
        set_property -dict [ list \
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
        ] $ddr4_1

        # Create instance: rst_ddr4_0_300M, and set properties
        set rst_ddr4_1_300M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ddr4_1_300M ]
    }
}

# vcu118
if {$cnfg(fdev) eq "vcu118"} {
    set ecc 0

    # Interfaces
    if {$cnfg(ddr_0) eq 1} {
        set c0_ddr4 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 c0_ddr4 ]
        set c0_sys_clk_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 c0_sys_clk_0 ]
        set_property -dict [ list \
            CONFIG.FREQ_HZ {250000000} \
        ] $c0_sys_clk_0
    }

        if {$cnfg(ddr_1) eq 1} {
        set c1_ddr4 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 c1_ddr4 ]
        set c1_sys_clk_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 c1_sys_clk_0 ]
        set_property -dict [ list \
            CONFIG.FREQ_HZ {250000000} \
        ] $c1_sys_clk_0
    }

    # Components
    if {$cnfg(ddr_0) eq 1} {
        # Create instance: ddr4_0, and set properties
        set ddr4_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4:2.2 ddr4_0 ]
        set_property -dict [ list \
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
        ] $ddr4_0

        # Create instance: rst_ddr4_0_300M, and set properties
        set rst_ddr4_0_300M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ddr4_0_300M ]
    }

    if {$cnfg(ddr_1) eq 1} {
        # Create instance: ddr4_0, and set properties
        set ddr4_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4:2.2 ddr4_1 ]
        set_property -dict [ list \
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
        ] $ddr4_1

        # Create instance: rst_ddr4_0_300M, and set properties
        set rst_ddr4_1_300M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ddr4_1_300M ]
    }
}

# Enzian
if {$cnfg(fdev) eq "enzian"} {
    if {$cnfg(ddr_0) eq 1} {
      set c0_ddr4 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 c0_ddr4 ]
      set c0_sys_clk_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 c0_sys_clk_0 ]
      set_property -dict [ list \
        CONFIG.FREQ_HZ {100000000} \
      ] $c0_sys_clk_0

      set axi_ctrl_ddr_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_ctrl_ddr_0 ]
      set_property -dict [ list \
        CONFIG.PROTOCOL {AXI4LITE} \
        #CONFIG.FREQ_HZ {300000000} \
        CONFIG.FREQ_HZ {266500000} \
        CONFIG.MAX_BURST_LENGTH {1} \
        CONFIG.SUPPORTS_NARROW_BURST {0} \
      ] $axi_ctrl_ddr_0
    }


    if {$cnfg(ddr_1) eq 1} {
      set c1_ddr4 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 c1_ddr4 ]
      set c1_sys_clk_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 c1_sys_clk_0 ]
      set_property -dict [ list \
        CONFIG.FREQ_HZ {100000000} \
      ] $c1_sys_clk_0

      set axi_ctrl_ddr_1 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_ctrl_ddr_1 ]
      set_property -dict [ list \
        CONFIG.PROTOCOL {AXI4LITE} \
        #CONFIG.FREQ_HZ {300000000} \
        CONFIG.FREQ_HZ {266500000} \
        CONFIG.MAX_BURST_LENGTH {1} \
        CONFIG.SUPPORTS_NARROW_BURST {0} \
      ] $axi_ctrl_ddr_1
    }


    if {$cnfg(ddr_2) eq 1} {
      set c2_ddr4 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 c2_ddr4 ]
      set c2_sys_clk_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 c2_sys_clk_0 ]
      set_property -dict [ list \
        CONFIG.FREQ_HZ {100000000} \
      ] $c2_sys_clk_0

      set axi_ctrl_ddr_2 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_ctrl_ddr_2 ]
      set_property -dict [ list \
        CONFIG.PROTOCOL {AXI4LITE} \
        #CONFIG.FREQ_HZ {300000000} \
        CONFIG.FREQ_HZ {266500000} \
        CONFIG.MAX_BURST_LENGTH {1} \
        CONFIG.SUPPORTS_NARROW_BURST {0} \
      ] $axi_ctrl_ddr_2
    }


    if {$cnfg(ddr_3) eq 1} {
      set c3_ddr4 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 c3_ddr4 ]
      set c3_sys_clk_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 c3_sys_clk_0 ]
      set_property -dict [ list \
        CONFIG.FREQ_HZ {100000000} \
      ] $c3_sys_clk_0

      set axi_ctrl_ddr_3 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_ctrl_ddr_3 ]
      set_property -dict [ list \
        CONFIG.PROTOCOL {AXI4LITE} \
        #CONFIG.FREQ_HZ {300000000} \
        CONFIG.FREQ_HZ {266500000} \
        CONFIG.MAX_BURST_LENGTH {1} \
        CONFIG.SUPPORTS_NARROW_BURST {0} \
      ] $axi_ctrl_ddr_3
    }

    if {$cnfg(ddr_0) eq 1} {
        # Create instance: ddr4_0, and set properties
        set ddr4_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4:2.2 ddr4_0 ]
        set_property -dict [ list \
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
        ] $ddr4_0

        # Create instance: rst_ddr4_0_300M, and set properties
        set rst_ddr4_0_300M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ddr4_0_300M ]
    }

    if {$cnfg(ddr_1) eq 1} {
        # Create instance: ddr4_0, and set properties
        set ddr4_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4:2.2 ddr4_1 ]
        set_property -dict [ list \
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
        ] $ddr4_1


        # Create instance: rst_ddr4_0_300M, and set properties
        set rst_ddr4_1_300M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ddr4_1_300M ]
    }


    if {$cnfg(ddr_2) eq 1} {
        # Create instance: ddr4_0, and set properties
        set ddr4_2 [ create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4:2.2 ddr4_2 ]
        set_property -dict [ list \
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
        ] $ddr4_2


        # Create instance: rst_ddr4_0_300M, and set properties
        set rst_ddr4_2_300M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ddr4_2_300M ]
    }


    if {$cnfg(ddr_3) eq 1} {
        # Create instance: ddr4_0, and set properties
        set ddr4_3 [ create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4:2.2 ddr4_3 ]
        set_property -dict [ list \
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
        ] $ddr4_3

        # Create instance: rst_ddr4_0_300M, and set properties
        set rst_ddr4_3_300M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ddr4_3_300M ]
    }
}

# DDR channels
if {$cnfg(en_dcard) eq 1} {
    for {set i 0}  {$i < $cnfg(n_mem_chan)} {incr i} {
    set cmd "set axi_ddr_in_$i \[ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_ddr_in_$i ]
            set_property -dict \[ list \
                CONFIG.ADDR_WIDTH {64} \
                CONFIG.ARUSER_WIDTH {0} \
                CONFIG.AWUSER_WIDTH {0} \
                CONFIG.BUSER_WIDTH {0} \
                CONFIG.DATA_WIDTH {512} \
                CONFIG.HAS_BRESP {1} \
                CONFIG.HAS_BURST {1} \
                CONFIG.HAS_CACHE {1} \
                CONFIG.HAS_LOCK {1} \
                CONFIG.HAS_PROT {1} \
                CONFIG.HAS_QOS {0} \
                CONFIG.HAS_REGION {0} \
                CONFIG.HAS_RRESP {1} \
                CONFIG.HAS_WSTRB {1} \
                CONFIG.ID_WIDTH {6} \
                CONFIG.MAX_BURST_LENGTH {64} \
                CONFIG.NUM_READ_OUTSTANDING {8} \
                CONFIG.NUM_READ_THREADS {8} \
                CONFIG.NUM_WRITE_OUTSTANDING {8} \
                CONFIG.NUM_WRITE_THREADS {8} \
                CONFIG.PROTOCOL {AXI4} \
                CONFIG.READ_WRITE_MODE {READ_WRITE} \
                CONFIG.RUSER_BITS_PER_BYTE {0} \
                CONFIG.RUSER_WIDTH {0} \
                CONFIG.SUPPORTS_NARROW_BURST {0} \
                CONFIG.WUSER_BITS_PER_BYTE {0} \
                CONFIG.WUSER_WIDTH {0} \
            ] \$axi_ddr_in_$i"
    eval $cmd
    }
}

# System reset
set uresetn [ create_bd_port -dir I -type rst aresetn ]

# System clock
set cmd "set aclk \[ create_bd_port -dir I -type clk aclk ]
        set_property -dict \[ list \
            CONFIG.ASSOCIATED_BUSIF {"
            for {set i 0}  {$i < $cnfg(n_mem_chan)} {incr i} {
                append cmd "axi_ddr_in_$i"
                if {$i != $cnfg(n_mem_chan) - 1} {
                    append cmd ":"
                }
            }
            append cmd "} \
            CONFIG.ASSOCIATED_RESET {aresetn} \
            CONFIG.FREQ_HZ {$cnfg(aclk_f)000000} \
        ] \$aclk"
eval $cmd

# External reset
set sys_reset [ create_bd_port -dir I -type rst sys_reset ]
    set_property -dict [ list \
    CONFIG.POLARITY {ACTIVE_HIGH} \
] $sys_reset

########################################################################################################
# Create interconnect
########################################################################################################

# Create instance: axi_interconnect_0, and set properties
if {$cnfg(en_dcard) eq 1} {
    set ic1_si $cnfg(n_mem_chan)
    set ic1_mi $cnfg(n_ddr_chan)

    set cmd "set axi_interconnect_0 \[ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0 ]
            set_property -dict \[ list \
            CONFIG.NUM_MI {$ic1_mi} \
            CONFIG.NUM_SI {$ic1_si} \
            CONFIG.STRATEGY {2} \ "
    for {set j 0}  {$j < $cnfg(n_ddr_chan)} {incr j} {
        append cmd "[format " CONFIG.M%02d_HAS_DATA_FIFO {2} CONFIG.M%02d_HAS_REGSLICE {4}" $j $j]"
    }
    for {set j 0}  {$j < $cnfg(n_mem_chan)} {incr j} {
        append cmd "[format " CONFIG.S%02d_HAS_REGSLICE {4}" $j]"
    }
    append cmd "] \$axi_interconnect_0"
    eval $cmd
}

########################################################################################################
# Create interface connections
########################################################################################################

for {set i 0}  {$i < $cnfg(n_ddr_chan)} {incr i} {
    set cmd [format "connect_bd_intf_net -intf_net axi_interconnect_0_M%02d_AXI \[get_bd_intf_pins axi_interconnect_0/M%02d_AXI] \[get_bd_intf_pins ddr4_%d/C0_DDR4_S_AXI]" $i $i $i]
    eval $cmd

    set cmd [format "connect_bd_intf_net -intf_net ddr4_%d_C0_DDR4 \[get_bd_intf_ports c$i\_ddr4] \[get_bd_intf_pins ddr4_$i/C0_DDR4]" $i]
    eval $cmd
    set cmd [format "connect_bd_intf_net -intf_net diff_clock_rtl_%d_2 \[get_bd_intf_ports c$i\_sys_clk_0] \[get_bd_intf_pins ddr4_$i/C0_SYS_CLK]" $i $i $i]
    eval $cmd
 
    if {$ecc == 1} {
        set cmd "connect_bd_intf_net [get_bd_intf_ports axi_ctrl_ddr_$i] [get_bd_intf_pins ddr4_$i/C0_DDR4_S_AXI_CTRL]"
        eval $cmd
    }
}

for {set j 0}  {$j < $cnfg(n_mem_chan)} {incr j} {
    set cmd [format "connect_bd_intf_net -intf_net axi_ddr_in_$j\_1 \[get_bd_intf_ports axi_ddr_in_$j] \[get_bd_intf_pins axi_interconnect_0/S%02d_AXI]" $j]
    eval $cmd
}

########################################################################################################
# Create port connections
########################################################################################################

set cmd "connect_bd_net \[get_bd_ports sys_reset]"
if {$cnfg(ddr_0) eq 1} {
    append cmd " \[get_bd_pins ddr4_0/sys_rst]"
}
if {$cnfg(ddr_1) eq 1} {
    append cmd " \[get_bd_pins ddr4_1/sys_rst]"
}
if {$cnfg(ddr_2) eq 1} {
    append cmd " \[get_bd_pins ddr4_2/sys_rst]"
}
if {$cnfg(ddr_3) eq 1} {
    append cmd " \[get_bd_pins ddr4_3/sys_rst]"
}
eval $cmd

for {set i 0}  {$i < $cnfg(n_ddr_chan)} {incr i} {
    set cmd [format "connect_bd_net -net rst_ddr4_$i\_300M_peripheral_aresetn \[get_bd_pins axi_interconnect_0/M%02d_ARESETN] \[get_bd_pins ddr4_$i/c0_ddr4_aresetn] \[get_bd_pins rst_ddr4_$i\_300M/peripheral_aresetn]" $i]
    eval $cmd
    set cmd [format "connect_bd_net -net ddr4_$i\_c0_ddr4_ui_clk \[get_bd_pins axi_interconnect_0/M%02d_ACLK] \[get_bd_pins ddr4_$i/c0_ddr4_ui_clk] \[get_bd_pins rst_ddr4_$i\_300M/slowest_sync_clk]" $i]
    eval $cmd
    set cmd [format "connect_bd_net -net ddr4_$i\_c0_ddr4_ui_clk_sync_rst \[get_bd_pins ddr4_$i/c0_ddr4_ui_clk_sync_rst] \[get_bd_pins rst_ddr4_$i\_300M/ext_reset_in]" ]
    eval $cmd
}

set cmd_clk "connect_bd_net \[get_bd_ports aclk] \[get_bd_pins axi_interconnect_0/ACLK]"
set cmd_rst "connect_bd_net \[get_bd_ports aresetn] \[get_bd_pins axi_interconnect_0/ARESETN]"

for {set i 0}  {$i < $cnfg(n_mem_chan)} {incr i} {
    append cmd_clk [format " \[get_bd_pins axi_interconnect_0/S%02d_ACLK]" $i]
    append cmd_rst [format " \[get_bd_pins axi_interconnect_0/S%02d_ARESETN]" $i]
}

eval $cmd_clk
eval $cmd_rst

########################################################################################################
# Create address segments
########################################################################################################

# Range DIMM
set rng [expr {1 << $cnfg(ddr_size)}]

if {$ecc == 1} {
    for {set i 0} {$i < $cnfg(n_ddr_chan)} {incr i} {
        set cmd "create_bd_addr_seg -range 0x00008000 -offset 0x00000000 \[get_bd_addr_spaces axi_ctrl_ddr_$i] \[get_bd_addr_segs ddr4_$i/C0_DDR4_MEMORY_MAP_CTRL/C0_REG] SEG_ddr4_ctrl_$i\_C0_DDR4_ADDRESS_BLOCK"
        eval $cmd
    }
}

for {set i 0} {$i < $cnfg(n_mem_chan)} {incr i} {
    set offs 0
    for {set j 0} {$j < $cnfg(n_ddr_chan)} {incr j} {
        set offs [expr {$rng * $j}]
        set cmd "create_bd_addr_seg -range $rng -offset $offs \[get_bd_addr_spaces axi_ddr_in_$i] \[get_bd_addr_segs ddr4_$j/C0_DDR4_MEMORY_MAP/C0_DDR4_ADDRESS_BLOCK] SEG_ddr4_$i\_$j\_C0_DDR4_ADDRESS_BLOCK"
        eval $cmd
    }
}

# Restore current instance
current_bd_instance $oldCurInst

save_bd_design
close_bd_design $design_name

return 0
}