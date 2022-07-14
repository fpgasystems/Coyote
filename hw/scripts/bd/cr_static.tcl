# Static layer
proc cr_bd_design_static { parentCell } {
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
  xilinx.com:ip:proc_sys_reset:5.0\
  xilinx.com:ip:util_ds_buf:[expr {($cnfg(fdev) eq "u55c") ? "2.2":"2.1"}]\
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
########################################################################################################
# STATIC
########################################################################################################
########################################################################################################

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
  
  # Main Clocks
  if {$cnfg(en_aclk) eq 1} {
    set xresetn "xresetn"
    set xclk "xclk"

    # Main system reset
    set aresetn [ create_bd_port -dir O -type rst aresetn ]
  
    # Main system clock
    set cmd "set aclk \[ create_bd_port -dir O -type clk aclk ]
            set_property -dict \[ list \
                CONFIG.ASSOCIATED_BUSIF {axi_cnfg"
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

    # Main bd reset
    set $xresetn [ create_bd_port -dir O -type rst $xresetn ]

    # Main bd clock
    set cmd "set $xclk \[ create_bd_port -dir O -type clk $xclk ]
            set_property -dict \[ list \
                CONFIG.ASSOCIATED_BUSIF {"
                for {set i 0}  {$i < $cnfg(n_chan)} {incr i} {
                  append cmd "axis_dyn_out_$i:axis_dyn_in_$i"
                  if {$i != $cnfg(n_chan) - 1} {
                    append cmd ":"
                  }
                } 
                append cmd "} \
                CONFIG.ASSOCIATED_RESET {$xresetn} \
                ] \$$xclk"
    eval $cmd
    set_property CONFIG.ASSOCIATED_RESET {xresetn:xresetn} [get_bd_ports /xclk]

  } else {
    set xresetn "aresetn"
    set xclk "aclk"

    # Main bd reset
    set $xresetn [ create_bd_port -dir O -type rst $xresetn ]

    # Main bd clock
    set cmd "set $xclk \[ create_bd_port -dir O -type clk $xclk ]
            set_property -dict \[ list \
                CONFIG.ASSOCIATED_BUSIF {axi_cnfg"
                for {set i 0}  {$i < $cnfg(n_reg)} {incr i} {
                  append cmd ":axi_ctrl_$i"
                }
                if {$cnfg(en_avx) eq 1} {
                  for {set i 0}  {$i < $cnfg(n_reg)} {incr i} {
                    append cmd ":axim_ctrl_$i"
                  }  
                }
                for {set i 0}  {$i < $cnfg(n_chan)} {incr i} {
                  append cmd ":axis_dyn_out_$i:axis_dyn_in_$i"
                } 
                append cmd "} \
                CONFIG.ASSOCIATED_RESET {$xresetn} \
                ] \$$xclk"
    eval $cmd
  }
  
  # Network reset
  set nresetn [ create_bd_port -dir O -type rst nresetn ]

  # Network clock
  set cmd "set nclk \[ create_bd_port -dir O -type clk nclk ]
          set_property -dict \[ list \
              CONFIG.ASSOCIATED_RESET {nresetn} \
          ] \$nclk"
  eval $cmd

  # User reset
  set uresetn [ create_bd_port -dir O -type rst uresetn ]

  # User clock
  set cmd "set uclk \[ create_bd_port -dir O -type clk uclk ]
          set_property -dict \[ list \
              CONFIG.ASSOCIATED_RESET {uresetn} \
          ] \$uclk"
  eval $cmd
  
  # PR reset
  set presetn [ create_bd_port -dir O -type rst presetn ]

  # PR clock
  set cmd "set pclk \[ create_bd_port -dir O -type clk pclk ]
          set_property -dict \[ list \
              CONFIG.ASSOCIATED_RESET {presetn} \
          ] \$pclk"
  eval $cmd

  # PCIe reset
  set perst_n [ create_bd_port -dir I -type rst perst_n ]
  set_property -dict [ list \
    CONFIG.POLARITY {ACTIVE_LOW} \
  ] $perst_n

  # External reset
  set sys_reset [ create_bd_port -dir I -type rst sys_reset ]
  set_property -dict [ list \
    CONFIG.POLARITY {ACTIVE_HIGH} \
  ] $sys_reset

  # User interrupts
  set cmd "set usr_irq \[ create_bd_port -dir I -from 1 -to 0 -type intr usr_irq ]
           set_property -dict \[ list \
           CONFIG.PortWidth {$cnfg(n_reg)} \
           ] \$usr_irq"
  eval $cmd

  # Locked
  create_bd_port -dir O -type rst lckresetn

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
          CONFIG.S00_HAS_REGSLICE {4} \
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

  # Create instance: clk_wiz_0, and set properties
  set clk_wiz_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0 ]
  set_property -dict [list \
    CONFIG.USE_PHASE_ALIGNMENT {true} \
    CONFIG.USE_PHASE_ALIGNMENT {true} \
    CONFIG.PRIM_SOURCE {Single_ended_clock_capable_pin} \
    CONFIG.PRIM_IN_FREQ {250.000} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT3_USED {true} \
    CONFIG.CLKOUT4_USED {true} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200.000} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {300.000} \
    CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {300.000} \
    CONFIG.CLKOUT4_REQUESTED_OUT_FREQ {300.000} \
    CONFIG.SECONDARY_SOURCE {Single_ended_clock_capable_pin} \
    CONFIG.CLKOUT1_DRIVES {Buffer} \
    CONFIG.CLKOUT2_DRIVES {Buffer} \
    CONFIG.CLKOUT3_DRIVES {Buffer} \
    CONFIG.CLKOUT4_DRIVES {Buffer} \
    CONFIG.CLKOUT5_DRIVES {Buffer} \
    CONFIG.CLKOUT6_DRIVES {Buffer} \
    CONFIG.CLKOUT7_DRIVES {Buffer} \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F {6.000} \
    CONFIG.MMCM_CLKOUT1_DIVIDE {4} \
    CONFIG.MMCM_CLKOUT2_DIVIDE {4} \
    CONFIG.MMCM_CLKOUT3_DIVIDE {4} \
    CONFIG.NUM_OUT_CLKS {4} \
    CONFIG.CLKOUT1_JITTER {102.086} \
    CONFIG.CLKOUT2_JITTER {94.862} \
    CONFIG.CLKOUT2_PHASE_ERROR {87.180} \
    CONFIG.CLKOUT3_JITTER {94.862} \
    CONFIG.CLKOUT3_PHASE_ERROR {87.180} \
    CONFIG.CLKOUT4_JITTER {94.862} \
    CONFIG.CLKOUT4_PHASE_ERROR {87.180} \
    CONFIG.CLKOUT4_PHASE_ERROR {163.860} \
  ] $clk_wiz_0

  set_property -dict [list CONFIG.OPTIMIZE_CLOCKING_STRUCTURE_EN {true}] [get_bd_cells clk_wiz_0]

  set cmd "set_property -dict \[list CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {$cnfg(nclk_f)}] \[get_bd_cells clk_wiz_0]"
  eval $cmd
  set cmd "set_property -dict \[list CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {$cnfg(uclk_f)}] \[get_bd_cells clk_wiz_0]"
  eval $cmd
  set cmd "set_property -dict \[list CONFIG.CLKOUT4_REQUESTED_OUT_FREQ {$cnfg(aclk_f)}] \[get_bd_cells clk_wiz_0]"
  eval $cmd

  # Create instance: proc_sys_reset_1, and set properties
  set proc_sys_reset_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_1 ]

  set proc_sys_reset_p [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_p ]
  set proc_sys_reset_n [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_n ]
  set proc_sys_reset_u [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_u ]
  
  if {$cnfg(en_aclk) eq 1} {
    set proc_sys_reset_a [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_a ]
  }

  # Create instance: util_ds_buf, and set properties
  # FIXME: 2.1 NOT work in vivado >= 2021.2
  #set util_ds_buf [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:[expr {($cnfg(fdev) eq "u55c") ? 2.2:2.1}] util_ds_buf ]
  set util_ds_buf [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf util_ds_buf ]

  set_property -dict [ list \
   CONFIG.C_BUF_TYPE {IBUFDSGTE} \
  ] $util_ds_buf

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

  set bypass [expr {(1 << ($cnfg(n_chan))) - 1}]
  set bypass [dec2bin $bypass]

if {$cnfg(fdev) eq "u250" || $cnfg(fdev) eq "u200"} {
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
              CONFIG.xdma_wnum_rids {32} \
              CONFIG.xdma_rnum_rids {32} \
            ] \$xdma_0"
    eval $cmd
}

if {$cnfg(fdev) eq "u280" || $cnfg(fdev) eq "u55c"} {
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
              CONFIG.xdma_wnum_rids {32} \
              CONFIG.xdma_rnum_rids {32} \
              CONFIG.pcie_blk_locn {PCIE4C_X1Y1} \
            ] \$xdma_0"
    eval $cmd
}

if {$cnfg(fdev) eq "u50"} {
    # Create instance: xdma_0, and set properties
    set cmd "set xdma_0 \[ create_bd_cell -type ip -vlnv xilinx.com:ip:xdma:4.1 xdma_0 ]
            set_property -dict \[ list \
              CONFIG.pcie_blk_locn {PCIE4C_X1Y0} \
              CONFIG.select_quad {GTY_Quad_227} \
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
              CONFIG.xdma_wnum_rids {32} \
              CONFIG.xdma_rnum_rids {32} \
            ] \$xdma_0"
    eval $cmd
}

if {$cnfg(fdev) eq "vcu118"} {
    # Create instance: xdma_0, and set properties
    set cmd "set xdma_0 \[ create_bd_cell -type ip -vlnv xilinx.com:ip:xdma:4.1 xdma_0 ]
            set_property -dict \[ list \
              CONFIG.PF0_DEVICE_ID_mqdma {903F} \
              CONFIG.PF2_DEVICE_ID_mqdma {903F} \
              CONFIG.PF3_DEVICE_ID_mqdma {903F} \
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
              CONFIG.pcie_blk_locn {X1Y2} \
              CONFIG.pciebar2axibar_axil_master {0x00000000} \
              CONFIG.pf0_base_class_menu {Memory_controller} \
              CONFIG.pf0_class_code {058000} \
              CONFIG.pf0_class_code_base {05} \
              CONFIG.pf0_class_code_interface {00} \
              CONFIG.pf0_class_code_sub {80} \
              CONFIG.pf0_device_id {903F} \
              CONFIG.pf0_msi_cap_multimsgcap {32_vectors} \
              CONFIG.pf0_msix_cap_pba_offset {00008FE0} \
              CONFIG.pf0_msix_cap_table_offset {00008000} \
              CONFIG.pf0_msix_cap_table_size {01F} \
              CONFIG.pf0_msix_enabled {true} \
              CONFIG.pf0_sub_class_interface_menu {Other_memory_controller} \
              CONFIG.pl_link_cap_max_link_speed {8.0_GT/s} \
              CONFIG.pl_link_cap_max_link_width {X16} \
              CONFIG.select_quad {GTY_Quad_227} \
              CONFIG.xdma_axi_intf_mm {AXI_Stream} \
              CONFIG.xdma_num_usr_irq {$cnfg(n_reg)} \
              CONFIG.xdma_rnum_chnl {[expr {$cnfg(n_chan)}]} \
              CONFIG.xdma_sts_ports {true} \
              CONFIG.xdma_wnum_chnl {[expr {$cnfg(n_chan)}]} \
              CONFIG.xdma_wnum_rids {32} \
              CONFIG.xdma_rnum_rids {32} \
            ] \$xdma_0"
    eval $cmd
}
  

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
  
  # External reset
  set cmd "connect_bd_net \[get_bd_ports sys_reset]"
  append cmd " \[get_bd_pins clk_wiz_0/reset]"
  append cmd " \[get_bd_pins proc_sys_reset_p/ext_reset_in]"
  append cmd " \[get_bd_pins proc_sys_reset_u/ext_reset_in]"
  append cmd " \[get_bd_pins proc_sys_reset_n/ext_reset_in]"
  if {$cnfg(en_aclk) eq 1} {
    append cmd " \[get_bd_pins proc_sys_reset_a/ext_reset_in]"
  }
  eval $cmd

  # XDMA
  connect_bd_net -net reset_rtl_0_1 [get_bd_ports perst_n] [get_bd_pins xdma_0/sys_rst_n]
  connect_bd_net -net usr_irq_1 [get_bd_ports usr_irq] [get_bd_pins xdma_0/usr_irq_req]
  connect_bd_net -net util_ds_buf_IBUF_DS_ODIV2 [get_bd_pins util_ds_buf/IBUF_DS_ODIV2] [get_bd_pins xdma_0/sys_clk]
  connect_bd_net -net util_ds_buf_IBUF_OUT [get_bd_pins util_ds_buf/IBUF_OUT] [get_bd_pins xdma_0/sys_clk_gt]

  # Clocks and resets main
  connect_bd_net -net p_aresetn_1 [get_bd_ports presetn] [get_bd_pins proc_sys_reset_p/peripheral_aresetn]
  connect_bd_net -net clk_wiz_0_clk_out1 [get_bd_ports pclk] [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins proc_sys_reset_p/slowest_sync_clk]

  connect_bd_net -net n_aresetn_1 [get_bd_ports nresetn] [get_bd_pins proc_sys_reset_n/peripheral_aresetn]
  connect_bd_net -net clk_wiz_0_clk_out3 [get_bd_ports nclk] [get_bd_pins clk_wiz_0/clk_out2] [get_bd_pins proc_sys_reset_n/slowest_sync_clk]

  connect_bd_net -net u_aresetn_1 [get_bd_ports uresetn] [get_bd_pins proc_sys_reset_u/peripheral_aresetn]
  connect_bd_net -net clk_wiz_0_clk_out4 [get_bd_ports uclk] [get_bd_pins clk_wiz_0/clk_out3] [get_bd_pins proc_sys_reset_u/slowest_sync_clk]
  
  if {$cnfg(en_aclk) eq 1} {
    connect_bd_net -net a_aresetn_1 [get_bd_ports aresetn] [get_bd_pins proc_sys_reset_a/peripheral_aresetn]
    connect_bd_net -net clk_wiz_0_clk_out2 [get_bd_ports aclk] [get_bd_pins clk_wiz_0/clk_out4] [get_bd_pins proc_sys_reset_a/slowest_sync_clk]
  }
  
  connect_bd_net [get_bd_ports lckresetn] [get_bd_pins clk_wiz_0/locked]

  connect_bd_net [get_bd_pins clk_wiz_0/clk_in1] [get_bd_pins xdma_0/axi_aclk]

  connect_bd_net -net xdma_0_axi_aresetn_ns [get_bd_pins xdma_0/axi_aresetn] [get_bd_pins proc_sys_reset_1/ext_reset_in]
  connect_bd_net -net proc_sys_reset_1_peripheral_aresetn [get_bd_ports $xresetn] [get_bd_pins proc_sys_reset_1/peripheral_aresetn]  

  # Xclk
  if {$cnfg(en_aclk) eq 1} {
    set cmd_clk "connect_bd_net \[get_bd_ports $xclk] \[get_bd_pins proc_sys_reset_1/slowest_sync_clk] \[get_bd_pins xdma_0/axi_aclk] \[get_bd_pins axi_interconnect_0/S00_ACLK]"
    set cmd_rst "connect_bd_net \[get_bd_pins proc_sys_reset_1/interconnect_aresetn] \[get_bd_pins axi_interconnect_0/S00_ARESETN]"

    eval $cmd_clk
    eval $cmd_rst
    
    set cmd_clk "connect_bd_net \[get_bd_ports aclk] \[get_bd_pins axi_interconnect_0/ACLK] \[get_bd_pins axi_interconnect_0/M00_ACLK]"
    set cmd_rst "connect_bd_net \[get_bd_pins proc_sys_reset_a/interconnect_aresetn] \[get_bd_pins axi_interconnect_0/ARESETN] \[get_bd_pins axi_interconnect_0/M00_ARESETN]"    
  } else {
    set cmd_clk "connect_bd_net \[get_bd_ports $xclk] \[get_bd_pins proc_sys_reset_1/slowest_sync_clk]\[get_bd_pins xdma_0/axi_aclk] \[get_bd_pins axi_interconnect_0/S00_ACLK] \[get_bd_pins axi_interconnect_0/ACLK] \[get_bd_pins axi_interconnect_0/M00_ACLK]"
    set cmd_rst "connect_bd_net \[get_bd_pins proc_sys_reset_1/interconnect_aresetn] \[get_bd_pins axi_interconnect_0/S00_ARESETN] \[get_bd_pins axi_interconnect_0/ARESETN] \[get_bd_pins axi_interconnect_0/M00_ARESETN] "
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

  # Restore current instance
  current_bd_instance $oldCurInst

  save_bd_design
  close_bd_design $design_name 

  return 0
}
# End of cr_bd_design_static()
