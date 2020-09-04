# Proc to create BD design_static
proc cr_bd_design_static_vcu118 { parentCell } {
  upvar #0 cfg cnfg

   # CHANGE DESIGN NAME HERE
  set design_name design_static

  common::send_msg_id "BD_TCL-003" "INFO" "Currently there is no design <$design_name> in project, so creating one..."

  create_bd_design $design_name

  set bCheckIPsPassed 1
  ########################################################################################################
  # CHECK IPs
  ########################################################################################################
  set bCheckIPs 1
  if { $bCheckIPs == 1 } {
     set list_check_ips "\ 
  xilinx.com:ip:clk_wiz:6.0\
  xilinx.com:ip:ddr4:2.2\
  xilinx.com:ip:proc_sys_reset:5.0\
  xilinx.com:ip:util_ds_buf:2.1\
  xilinx.com:ip:xdma:4.1\
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
# Create interface ports
########################################################################################################
  # Static config
  set axi_cnfg [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_cnfg ]
  set_property -dict [ list \
    CONFIG.ADDR_WIDTH {64} \
    CONFIG.DATA_WIDTH {64} \
    CONFIG.PROTOCOL {AXI4LITE} \
  ] $axi_cnfg

  # XDMA status
  set dsc_status [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_xdma:xdma_status_ports_rtl:1.0 dsc_status ]
  
  # PCIe
  set pcie_clk [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 pcie_clk ]
  set_property -dict [ list \
    CONFIG.FREQ_HZ {100000000} \
  ] $pcie_clk
  set pcie_x16 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:pcie_7x_mgt_rtl:1.0 pcie_x16 ]

  # DDRs
  if {$cnfg(en_ddr) eq 1} { 
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
  }

  set nn 0
  if {$cnfg(en_pr) eq 1} {
    incr nn
  }

  # Streams and XDMA control
  for {set i 0}  {$i < $cnfg(n_chan)} {incr i} {
    # Host source
    set cmd "set axis_dyn_in_$i \[ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 axis_dyn_in_$i ]
            set_property -dict \[ list \
              CONFIG.HAS_TKEEP {1} \
              CONFIG.HAS_TLAST {1} \
              CONFIG.HAS_TREADY {1} \
              CONFIG.HAS_TSTRB {0} \
              CONFIG.LAYERED_METADATA {undef} \
              CONFIG.TDATA_NUM_BYTES {64} \
              CONFIG.TDEST_WIDTH {0} \
              CONFIG.TID_WIDTH {0} \
              CONFIG.TUSER_WIDTH {0} \
            ] \$axis_dyn_in_$i"
    eval $cmd

    # Host sink
    set cmd "set axis_dyn_out_$i \[ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 axis_dyn_out_$i ]"
    eval $cmd

    # Host source control
    set cmd "set dsc_bypass_c2h_$i \[ create_bd_intf_port -mode Slave -vlnv xilinx.com:display_xdma:dsc_bypass_rtl:1.0 dsc_bypass_c2h_$i ]"
    eval $cmd

    # Host sink control
    set cmd "set dsc_bypass_h2c_$i \[ create_bd_intf_port -mode Slave -vlnv xilinx.com:display_xdma:dsc_bypass_rtl:1.0 dsc_bypass_h2c_$i ]"
    eval $cmd
  }

  # DDR channels
  if {$cnfg(en_ddr) eq 1} {
    for {set i 0}  {$i < $cnfg(n_ddr_chan) * 2} {incr i} {   
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
                CONFIG.ID_WIDTH {1} \
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

  # Dynamic control
  for {set i 0}  {$i < $cnfg(n_reg)} {incr i} {    
    set cmd "set axi_ctrl_$i \[ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_ctrl_$i ]
            set_property -dict \[ list \
            CONFIG.ADDR_WIDTH {64} \
            CONFIG.DATA_WIDTH {64} \
            CONFIG.PROTOCOL {AXI4LITE} \
            ] \$axi_ctrl_$i"
    eval $cmd
  }

  # AVX control
  if {$cnfg(en_avx) eq 1} {
    for {set i 0}  {$i < $cnfg(n_reg)} {incr i} {    
      set cmd "set axim_ctrl_$i \[ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 axim_ctrl_$i ]
              set_property -dict \[ list \
                CONFIG.ADDR_WIDTH {64} \
                CONFIG.DATA_WIDTH {256} \
                CONFIG.HAS_BRESP {1} \
                CONFIG.HAS_BURST {1} \
                CONFIG.HAS_CACHE {1} \
                CONFIG.HAS_LOCK {1} \
                CONFIG.HAS_PROT {1} \
                CONFIG.HAS_QOS {0} \
                CONFIG.HAS_REGION {0} \
                CONFIG.HAS_RRESP {1} \
                CONFIG.HAS_WSTRB {1} \
                CONFIG.NUM_READ_OUTSTANDING {8} \
                CONFIG.NUM_WRITE_OUTSTANDING {8} \
                CONFIG.PROTOCOL {AXI4} \
                CONFIG.READ_WRITE_MODE {READ_WRITE} \
              ] \$axim_ctrl_$i"
      eval $cmd
    }
  }

########################################################################################################
# Create ports
########################################################################################################
  # Main reset
  set aresetn [ create_bd_port -dir O -type rst aresetn ]

  set nn 0
  if {$cnfg(en_pr) eq 1} {
    incr nn
  }

  # Main clock
  set cmd "set aclk \[ create_bd_port -dir O -type clk aclk ]
          set_property -dict \[ list \
          CONFIG.ASSOCIATED_BUSIF {axi_cnfg"
  for {set i 0}  {$i < $cnfg(n_chan)} {incr i} {
    append cmd ":axis_dyn_out_$i:axis_dyn_in_$i"
  }
  if {$cnfg(en_ddr) eq 1} {
    for {set i 0}  {$i < $cnfg(n_ddr_chan) * 2} {incr i} {
      append cmd ":axi_ddr_in_$i"
    }
  }
  for {set i 0}  {$i < $cnfg(n_reg)} {incr i} {
    append cmd ":axi_ctrl_$i"
  }
  if {$cnfg(en_avx) eq 1} {
    for {set i 0}  {$i < $cnfg(n_reg)} {incr i} {
      append cmd ":axim_ctrl_$i"
    }  
  } 
  append cmd "} \
              CONFIG.ASSOCIATED_RESET {aresetn} \
              ] \$aclk"
  eval $cmd

  # PCIe reset
  set perst_n [ create_bd_port -dir I -type rst perst_n ]
  set_property -dict [ list \
    CONFIG.POLARITY {ACTIVE_LOW} \
  ] $perst_n

  # External reset
  set reset_0 [ create_bd_port -dir I -type rst reset_0 ]
  set_property -dict [ list \
    CONFIG.POLARITY {ACTIVE_HIGH} \
  ] $reset_0

  # User interrupts
  set cmd "set usr_irq \[ create_bd_port -dir I -from 1 -to 0 -type intr usr_irq ]
           set_property -dict \[ list \
           CONFIG.PortWidth {$cnfg(n_reg)} \
           ] \$usr_irq"
  eval $cmd

  # PR clock and reset
  if {$cnfg(en_pr) eq 1} {
    set pclk [ create_bd_port -dir O -type clk pclk ]
    set presetn [ create_bd_port -dir O -from 0 -to 0 -type rst presetn ]
  }

########################################################################################################
# Create interconnect and components
########################################################################################################
  # Create instance: axi_interconnect_0, and set properties
  if {$cnfg(en_avx) eq 1} {
    set ic0_mi [expr {2*$cnfg(n_reg) + 1}]
  } else {
    set ic0_mi [expr {$cnfg(n_reg) + 1}]
  }

  set cmd "set axi_interconnect_0 \[ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0 ]
          set_property -dict \[ list \
          CONFIG.NUM_MI {$ic0_mi} \
          CONFIG.S00_HAS_DATA_FIFO {2} \
          CONFIG.STRATEGY {2} \ "
  if {$cnfg(en_avx) eq 1} {
    for {set i 0} {$i <= 2 * $cnfg(n_reg)} {incr i} {
      append cmd [format " CONFIG.M%02d_HAS_REGSLICE {4}"  $i]
    }
  } else {
    for {set i 0} {$i <= $cnfg(n_reg)} {incr i} {
      append cmd [format " CONFIG.M%02d_HAS_REGSLICE {4}"  $i]
    }
  }
  append cmd "] \$axi_interconnect_0"
  eval $cmd

  # Create instance: axi_interconnect_1(2), and set properties
  if {$cnfg(en_ddr) eq 1} {
    set ic1_si 2
    set ic1_mi 1
    for {set i 1} {$i <= $cnfg(n_ddr_chan)} {incr i} {
      set cmd "set axi_interconnect_$i \[ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_$i ]
            set_property -dict \[ list \
            CONFIG.NUM_MI {$ic1_mi} \
            CONFIG.NUM_SI {$ic1_si} \
            CONFIG.S00_HAS_REGSLICE {4} \
            CONFIG.STRATEGY {2} \ "
      append cmd "[format " CONFIG.M%02d_HAS_DATA_FIFO {0} CONFIG.M%02d_HAS_REGSLICE {4}" 0 0]"
      for {set j 0}  {$j < 2} {incr j} {
          append cmd "[format " CONFIG.S%02d_HAS_REGSLICE {4}" $j]"
      }
      append cmd "] \$axi_interconnect_$i"
      eval $cmd
    }

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

        # Create instance: rst_ddr4_0_300M, and set properties
        set rst_ddr4_1_300M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ddr4_1_300M ]
    }

    if {$cnfg(ddr_2) eq 1} {
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

        # Create instance: rst_ddr4_0_300M, and set properties
        set rst_ddr4_1_300M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ddr4_1_300M ]
    }

    if {$cnfg(ddr_3) eq 1} {
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

        # Create instance: rst_ddr4_0_300M, and set properties
        set rst_ddr4_1_300M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ddr4_1_300M ]
    }
  }

  if {$cnfg(en_pr) eq 1} {
    # Create instance: clk_wiz_0, and set properties
    set clk_wiz_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0 ]
    set_property -dict [ list \
      CONFIG.CLKIN1_JITTER_PS {40.0} \
      CONFIG.CLKOUT1_JITTER {119.392} \
      CONFIG.CLKOUT1_PHASE_ERROR {154.678} \
      CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200.000} \
      CONFIG.MMCM_CLKFBOUT_MULT_F {24.000} \
      CONFIG.MMCM_CLKIN1_PERIOD {4.000} \
      CONFIG.MMCM_CLKIN2_PERIOD {10.0} \
      CONFIG.MMCM_CLKOUT0_DIVIDE_F {6.000} \
      CONFIG.MMCM_DIVCLK_DIVIDE {5} \
      CONFIG.PRIM_IN_FREQ {250.000} \
    ] $clk_wiz_0

    # Create instance: proc_sys_reset_0, and set properties
    set proc_sys_reset_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0 ]
  }

  # Create instance: util_ds_buf, and set properties
  set util_ds_buf [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.1 util_ds_buf ]
  set_property -dict [ list \
   CONFIG.C_BUF_TYPE {IBUFDSGTE} \
  ] $util_ds_buf

  # Create instance: proc_sys_reset_1, and set properties
  set proc_sys_reset_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_1 ]

  proc dec2bin i {
    #returns a string, e.g. dec2bin 10 => 1010 
    set res {} 
    while {$i>0} {
        set res [expr {$i%2}]$res
        set i [expr {$i/2}]
    }
    if {$res == {}} {set res 0}
    return $res
  }

  set nn 0
  if {$cnfg(en_pr) eq 1} {
    incr nn
  }

  set bypass [expr {(1 << ($cnfg(n_chan))) - 1}]
  set bypass [dec2bin $bypass]

    # Create instance: xdma_0, and set properties
  set cmd "set xdma_0 \[ create_bd_cell -type ip -vlnv xilinx.com:ip:xdma:4.1 xdma_0 ]
          set_property -dict \[ list \
            CONFIG.axi_bypass_64bit_en {true} \
            CONFIG.axi_bypass_prefetchable {true} \
            CONFIG.axi_data_width {512_bit} \
            CONFIG.axi_id_width {4} \
            CONFIG.axist_bypass_en {true} \
            CONFIG.axist_bypass_scale {Gigabytes} \
            CONFIG.axist_bypass_size {1} \
            CONFIG.axisten_freq {250} \
            CONFIG.cfg_mgmt_if {false} \
            CONFIG.dsc_bypass_rd {[format "%04d" $bypass]} \
            CONFIG.dsc_bypass_wr {[format "%04d" $bypass]} \
            CONFIG.pciebar2axibar_axil_master {0x00000000} \
            CONFIG.pf0_msi_cap_multimsgcap {32_vectors} \
            CONFIG.pf0_msix_cap_pba_offset {00008FE0} \
            CONFIG.pf0_msix_cap_table_offset {00008000} \
            CONFIG.pf0_msix_cap_table_size {01F} \
            CONFIG.pf0_msix_enabled {true} \
            CONFIG.pl_link_cap_max_link_speed {8.0_GT/s} \
            CONFIG.pl_link_cap_max_link_width {X16} \
            CONFIG.xdma_axi_intf_mm {AXI_Stream} \
            CONFIG.xdma_num_usr_irq {$cnfg(n_reg)} \
            CONFIG.xdma_rnum_chnl {[expr {$cnfg(n_chan)}]} \
            CONFIG.xdma_sts_ports {true} \
            CONFIG.xdma_wnum_chnl {[expr {$cnfg(n_chan)}]} \
            CONFIG.xdma_wnum_rids {16} \
            CONFIG.xdma_rnum_rids {16} \
          ] \$xdma_0"
  eval $cmd

########################################################################################################
# Create interface connections
########################################################################################################
  # XDMA
  connect_bd_intf_net -intf_net diff_clock_rtl_0_1 [get_bd_intf_ports pcie_clk] [get_bd_intf_pins util_ds_buf/CLK_IN_D]
  connect_bd_intf_net -intf_net xdma_0_pcie_mgt [get_bd_intf_ports pcie_x16] [get_bd_intf_pins xdma_0/pcie_mgt]
  connect_bd_intf_net -intf_net axi_interconnect_0_M00_AXI [get_bd_intf_ports axi_cnfg] [get_bd_intf_pins axi_interconnect_0/M00_AXI]
  connect_bd_intf_net -intf_net xdma_0_M_AXI_BYPASS [get_bd_intf_pins axi_interconnect_0/S00_AXI] [get_bd_intf_pins xdma_0/M_AXI_BYPASS]
  connect_bd_intf_net -intf_net xdma_0_dma_status_ports [get_bd_intf_ports dsc_status] [get_bd_intf_pins xdma_0/dma_status_ports]

  # Dynamic control
  if {$cnfg(en_avx) eq 1} {
    for {set i 0}  {$i < $cnfg(n_reg)} {incr i} { 
      set j [expr {$i*2 + 1}]
      set cmd [format "connect_bd_intf_net -intf_net axi_interconnect_0_M%02d_AXI \[get_bd_intf_ports axi_ctrl_%d] \[get_bd_intf_pins axi_interconnect_0/M%02d_AXI]" $j $i $j]
      eval $cmd 
      set j [expr {$i*2 + 2}]
      set cmd [format "connect_bd_intf_net -intf_net axi_interconnect_0_M%02d_AXI \[get_bd_intf_ports axim_ctrl_%d] \[get_bd_intf_pins axi_interconnect_0/M%02d_AXI]" $j $i $j]
      eval $cmd 
    }
  } else {
    for {set i 0}  {$i < $cnfg(n_reg)} {incr i} { 
      set j [expr {$i + 1}]
      set cmd [format "connect_bd_intf_net -intf_net axi_interconnect_0_M%02d_AXI \[get_bd_intf_ports axi_ctrl_%d] \[get_bd_intf_pins axi_interconnect_0/M%02d_AXI]" $j $i $j]
      eval $cmd 
    }
  }

  # DDRs
  if {$cnfg(en_ddr) eq 1} {
    for {set i 1}  {$i <= $cnfg(n_ddr_chan)} {incr i} {
      set nn [expr {$i - 1}]
      set cmd [format "connect_bd_intf_net -intf_net axi_interconnect_%d_M00_AXI \[get_bd_intf_pins axi_interconnect_%d/M00_AXI] \[get_bd_intf_pins ddr4_%d/C0_DDR4_S_AXI]" $i $i $nn]
      eval $cmd
      set cmd [format "connect_bd_intf_net -intf_net ddr4_%d_C0_DDR4 [get_bd_intf_ports c$nn\_ddr4] [get_bd_intf_pins ddr4_$nn/C0_DDR4]" $nn]
      eval $cmd
      set cmd [format "connect_bd_intf_net -intf_net diff_clock_rtl_%d_2 [get_bd_intf_ports c$nn\_sys_clk_0] [get_bd_intf_pins ddr4_$nn/C0_SYS_CLK]" $nn $nn $nn]
      eval $cmd
      set cmd "connect_bd_intf_net [get_bd_intf_ports axi_ctrl_ddr_$nn] [get_bd_intf_pins ddr4_$nn/C0_DDR4_S_AXI_CTRL]"
      eval $cmd

      for {set j 0}  {$j < 2} {incr j} {
        set nn [expr {$i - 1 + $j*$cnfg(n_ddr_chan)}]
        set cmd [format "connect_bd_intf_net -intf_net axi_ddr_in_$nn\_1 \[get_bd_intf_ports axi_ddr_in_$nn] \[get_bd_intf_pins axi_interconnect_%d/S%02d_AXI]" $i $j]
        eval $cmd
      }
    }
  }

  set nn 0
  if {$cnfg(en_pr) eq 1} { 
    incr nn
  }

  # Data lines
  for {set i 0}  {$i < $cnfg(n_chan)} {incr i} { 
    set cmd "connect_bd_intf_net -intf_net axis_dyn_in_$i\_1 \[get_bd_intf_ports axis_dyn_in_$i] \[get_bd_intf_pins xdma_0/S_AXIS_C2H_$i]"
    eval $cmd

    set cmd "connect_bd_intf_net -intf_net xdma_0_M_AXIS_H2C_$i \[get_bd_intf_ports axis_dyn_out_$i] \[get_bd_intf_pins xdma_0/M_AXIS_H2C_$i]"
    eval $cmd

    set cmd "connect_bd_intf_net -intf_net dsc_bypass_c2h_$i\_1 \[get_bd_intf_ports dsc_bypass_c2h_$i] \[get_bd_intf_pins xdma_0/dsc_bypass_c2h_$i]"
    eval $cmd

    set cmd "connect_bd_intf_net -intf_net dsc_bypass_h2c_$i\_1 \[get_bd_intf_ports dsc_bypass_h2c_$i] \[get_bd_intf_pins xdma_0/dsc_bypass_h2c_$i]"
    eval $cmd
  }

########################################################################################################
# Create port connections
########################################################################################################
  # PR
  if {$cnfg(en_pr) eq 1} { 
    connect_bd_net -net pr_aresetn_1 [get_bd_ports presetn] [get_bd_pins proc_sys_reset_0/peripheral_aresetn]
    connect_bd_net -net clk_wiz_0_clk_out1 [get_bd_ports pclk] [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
  }

  # XDMA
  connect_bd_net -net reset_rtl_0_1 [get_bd_ports perst_n] [get_bd_pins xdma_0/sys_rst_n]
  connect_bd_net -net usr_irq_1 [get_bd_ports usr_irq] [get_bd_pins xdma_0/usr_irq_req]
  connect_bd_net -net util_ds_buf_IBUF_DS_ODIV2 [get_bd_pins util_ds_buf/IBUF_DS_ODIV2] [get_bd_pins xdma_0/sys_clk]
  connect_bd_net -net util_ds_buf_IBUF_OUT [get_bd_pins util_ds_buf/IBUF_OUT] [get_bd_pins xdma_0/sys_clk_gt]

  # External reset
  set cmd "connect_bd_net -net reset_rtl_0_0_1 \[get_bd_ports reset_0] \[get_bd_pins clk_wiz_0/reset] \[get_bd_pins proc_sys_reset_0/ext_reset_in]"
  if {$cnfg(en_ddr) eq 1} { 
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
  }
  eval $cmd

  # DDRs
  if {$cnfg(en_ddr) eq 1} { 
    for {set i 1}  {$i <= $cnfg(n_ddr_chan)} {incr i} {
      set nn [expr {$i - 1}]
      set cmd [format "connect_bd_net -net rst_ddr4_$nn\_300M_peripheral_aresetn \[get_bd_pins axi_interconnect_$i/M00_ARESETN] \[get_bd_pins ddr4_$nn/c0_ddr4_aresetn] \[get_bd_pins rst_ddr4_$nn\_300M/peripheral_aresetn]"]
      eval $cmd 
      set cmd [format "connect_bd_net -net ddr4_$nn\_c0_ddr4_ui_clk \[get_bd_pins axi_interconnect_$i/M00_ACLK] \[get_bd_pins ddr4_$nn/c0_ddr4_ui_clk] \[get_bd_pins rst_ddr4_$nn\_300M/slowest_sync_clk]"]
      eval $cmd
      set cmd [format "connect_bd_net -net ddr4_$nn\_c0_ddr4_ui_clk_sync_rst \[get_bd_pins ddr4_$nn/c0_ddr4_ui_clk_sync_rst] \[get_bd_pins rst_ddr4_$nn\_300M/ext_reset_in]" ]
      eval $cmd
    }
  }

  # XDMA
  connect_bd_net -net xdma_0_axi_aresetn_ns [get_bd_pins xdma_0/axi_aresetn] [get_bd_pins proc_sys_reset_1/ext_reset_in]
  connect_bd_net -net proc_sys_reset_1_peripheral_aresetn [get_bd_ports aresetn] [get_bd_pins proc_sys_reset_1/peripheral_aresetn]

  set cmd_clk "connect_bd_net -net xdma_0_axi_aclk \[get_bd_ports aclk] \[get_bd_pins proc_sys_reset_1/slowest_sync_clk] \[get_bd_pins axi_interconnect_0/ACLK] \[get_bd_pins axi_interconnect_0/M00_ACLK] \[get_bd_pins xdma_0/axi_aclk] \[get_bd_pins axi_interconnect_0/S00_ACLK]"
  set cmd_rst "connect_bd_net -net xdma_0_axi_aresetn_s \[get_bd_pins axi_interconnect_0/ARESETN] \[get_bd_pins proc_sys_reset_1/interconnect_aresetn] \[get_bd_pins axi_interconnect_0/M00_ARESETN] \[get_bd_pins axi_interconnect_0/S00_ARESETN]"
  
  set nn 1
  if {$cnfg(en_pr) eq 1} { 
    append cmd_clk " \[get_bd_pins clk_wiz_0/clk_in1]"
  }

  if {$cnfg(en_avx) eq 1} { 
    for {set i 1}  {$i <= 2 * $cnfg(n_reg)} {incr i} {
      append cmd_clk [format " \[get_bd_pins axi_interconnect_0/M%02d_ACLK]" $i]
      append cmd_rst [format " \[get_bd_pins axi_interconnect_0/M%02d_ARESETN]" $i]
    }
  } else {
    for {set i 1}  {$i <= $cnfg(n_reg)} {incr i} {
      append cmd_clk [format " \[get_bd_pins axi_interconnect_0/M%02d_ACLK]" $i]
      append cmd_rst [format " \[get_bd_pins axi_interconnect_0/M%02d_ARESETN]" $i]
    }
  }
    
  if {$cnfg(en_ddr) eq 1} { 
    for {set i 1}  {$i <= $cnfg(n_ddr_chan)} {incr i} {
      append cmd_clk " \[get_bd_pins axi_interconnect_$i/ACLK]"
      append cmd_rst " \[get_bd_pins axi_interconnect_$i/ARESETN]"
      for {set j 0}  {$j < 2} {incr j} {
        append cmd_clk [format " \[get_bd_pins axi_interconnect_$i/S%02d_ACLK]" $j]
        append cmd_rst [format " \[get_bd_pins axi_interconnect_$i/S%02d_ARESETN]" $j]
      }
    }
  }

  eval $cmd_clk
  eval $cmd_rst

########################################################################################################
# Create address segments
########################################################################################################
  # Static config
  create_bd_addr_seg -range 0x00008000 -offset 0x00000000 [get_bd_addr_spaces xdma_0/M_AXI_BYPASS] [get_bd_addr_segs axi_cnfg/Reg] SEG_axi_cnfg_Reg

  if {$cnfg(en_avx) eq 1} { 
    for {set i 0}  {$i < $cnfg(n_reg)} {incr i} {
      set cmd [format "create_bd_addr_seg -range 0x00040000 -offset 0x000%02x0000 \[get_bd_addr_spaces xdma_0/M_AXI_BYPASS] \[get_bd_addr_segs axi_ctrl_$i/Reg] SEG_axi_ctrl_$i\_Reg" [expr {0x10 + $i *4}]]
      eval $cmd
      set cmd [format "create_bd_addr_seg -range 0x00040000 -offset 0x00%03x0000 \[get_bd_addr_spaces xdma_0/M_AXI_BYPASS] \[get_bd_addr_segs axim_ctrl_$i/Reg] SEG_axim_ctrl_$i\_Reg" [expr {0x100 + $i *4}]]
      eval $cmd
    }
  } else {
    for {set i 0}  {$i < $cnfg(n_reg)} {incr i} {
      set cmd [format "create_bd_addr_seg -range 0x00040000 -offset 0x000%02x0000 \[get_bd_addr_spaces xdma_0/M_AXI_BYPASS] \[get_bd_addr_segs axi_ctrl_$i/Reg] SEG_axi_ctrl_$i\_Reg" [expr {0x10 + $i *4}]]
      eval $cmd
    }
  }
  
  # DDRs
  if {$cnfg(en_ddr) eq 1} { 
    for {set i 0} {$i < $cnfg(n_ddr_chan)} {incr i} {
      for {set j 0} {$j < 2} {incr j} {
        set nn [expr {$i + $j * $cnfg(n_ddr_chan)}]
        set cmd "create_bd_addr_seg -range 0x80000000 -offset 0x00000000 \[get_bd_addr_spaces axi_ddr_in_$nn] \[get_bd_addr_segs ddr4_$i/C0_DDR4_MEMORY_MAP/C0_DDR4_ADDRESS_BLOCK] SEG_ddr4_$i\_$j\_C0_DDR4_ADDRESS_BLOCK"
        eval $cmd
      }

      set cmd "create_bd_addr_seg -range 0x00008000 -offset 0x00000000 \[get_bd_addr_spaces axi_ctrl_ddr_$i] \[get_bd_addr_segs ddr4_$i/C0_DDR4_MEMORY_MAP_CTRL/C0_REG] SEG_ddr4_ctrl_$i\_C0_DDR4_ADDRESS_BLOCK"
      eval $cmd
    }
  }

  # Restore current instance
  current_bd_instance $oldCurInst

  save_bd_design
  close_bd_design $design_name 
}
# End of cr_bd_design_static()
