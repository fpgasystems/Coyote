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
    CONFIG.DATA_WIDTH {32} \
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
  for {set i 0}  {$i < $cnfg(n_xchan)} {incr i} {
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

  # Control main
  set cmd "set axi_main \[ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_main ]
          set_property -dict \[ list \
            CONFIG.ADDR_WIDTH {64} \
            CONFIG.DATA_WIDTH {512} \
            CONFIG.HAS_BRESP {1} \
            CONFIG.HAS_BURST {1} \
            CONFIG.HAS_CACHE {1} \
            CONFIG.HAS_LOCK {1} \
            CONFIG.HAS_PROT {1} \
            CONFIG.HAS_QOS {1} \
            CONFIG.HAS_REGION {1} \
            CONFIG.HAS_RRESP {1} \
            CONFIG.HAS_WSTRB {1} \
            CONFIG.NUM_READ_OUTSTANDING {8} \
            CONFIG.NUM_WRITE_OUTSTANDING {8} \
            CONFIG.PROTOCOL {AXI4} \
            CONFIG.READ_WRITE_MODE {READ_WRITE} \
          ] \$axi_main"
  eval $cmd

########################################################################################################
# Create ports
########################################################################################################

  # Main bd reset
  set xresetn [ create_bd_port -dir O -type rst xresetn ]

  # Main bd clock
  set cmd "set xclk \[ create_bd_port -dir O -type clk xclk ]
          set_property -dict \[ list \
              CONFIG.ASSOCIATED_BUSIF {"
              for {set i 0}  {$i < $cnfg(n_xchan)} {incr i} {
                append cmd "axis_dyn_out_$i:axis_dyn_in_$i"
                if {$i != $cnfg(n_xchan) - 1} {
                  append cmd ":"
                }
              } 
              append cmd "} \
              CONFIG.ASSOCIATED_RESET {xresetn} \
              ] \$xclk"
  eval $cmd
  set_property CONFIG.ASSOCIATED_RESET {xresetn:xresetn} [get_bd_ports /xclk]
  
  # PR reset
  set presetn [ create_bd_port -dir O -type rst presetn ]

  # PR clock
  set cmd "set pclk \[ create_bd_port -dir O -type clk pclk ]
          set_property -dict \[ list \
              CONFIG.ASSOCIATED_RESET {presetn} \
              CONFIG.FREQ_HZ {200000000} \
          ] \$pclk"
  eval $cmd

  # Debug reset
  set dresetn [ create_bd_port -dir O -type rst dresetn ]

  # Debug clock
  set cmd "set dclk \[ create_bd_port -dir O -type clk dclk ]
          set_property -dict \[ list \
              CONFIG.ASSOCIATED_RESET {dresetn} \
              CONFIG.FREQ_HZ {100000000} \
          ] \$dclk"
  eval $cmd

  # System reset
  set sresetn [ create_bd_port -dir O -type rst sresetn ]

  # User interrupts
  set cmd "set usr_irq \[ create_bd_port -dir I -from 1 -to 0 -type intr usr_irq ]
           set_property -dict \[ list \
           CONFIG.PortWidth {16} \
           ] \$usr_irq"
  eval $cmd

  # Locked
  set lckresetn [ create_bd_port -dir O -type rst lckresetn ]

  # Dynamic reset
  create_bd_port -dir I -type rst eos_resetn
  set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports eos_resetn]
  set_property CONFIG.ASSOCIATED_RESET {xresetn:sresetn:eos_resetn} [get_bd_ports /xclk]

########################################################################################################
# Create interconnect and components
########################################################################################################

  set clk_wiz_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0 ]
  set_property -dict [list \
   CONFIG.PRIM_IN_FREQ {100.000} \
   CONFIG.USE_LOCKED {true} \
   CONFIG.USE_RESET {false} \
   CONFIG.CLKIN1_JITTER_PS {40.0} \
   CONFIG.MMCM_DIVCLK_DIVIDE {5} \
   CONFIG.MMCM_CLKFBOUT_MULT_F {24.000} \
   CONFIG.MMCM_CLKIN1_PERIOD {4.000} \
   CONFIG.MMCM_CLKIN2_PERIOD {10.0} \
   CONFIG.CLKOUT1_JITTER {134.506} \
   CONFIG.CLKOUT1_PHASE_ERROR {154.678} \
  ] $clk_wiz_0

  set_property -dict [list CONFIG.OPTIMIZE_CLOCKING_STRUCTURE_EN {true} CONFIG.CLKOUT2_USED {true} CONFIG.NUM_OUT_CLKS {2} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200.000} CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {100.000}] [get_bd_cells clk_wiz_0]

  # Create instance: proc_sys_reset_1, and set properties
  set proc_sys_reset_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_1 ]

  set proc_sys_reset_p [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_p ]
  set proc_sys_reset_d [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_d ]
  set proc_sys_reset_x [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_x ]

  create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 util_vector_logic_0
  set_property -dict [list CONFIG.C_SIZE {1} CONFIG.C_OPERATION {and} CONFIG.LOGO_FILE {data/sym_orgate.png}] [get_bd_cells util_vector_logic_0]
 
  #set util_ds_buf [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:[expr {($cnfg(fdev) eq "u55c") ? 2.2:2.1}] util_ds_buf ]
  set util_ds_buf [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf util_ds_buf ]

  # Reset
  create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_0
  set_property -dict [list CONFIG.CONST_VAL {1}] [get_bd_cells xlconstant_0] 

  create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_1
  set_property -dict [list CONFIG.CONST_VAL {1}] [get_bd_cells xlconstant_1]  

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

  set bypass [expr {(1 << ($cnfg(n_xchan))) - 1}]
  set bypass [dec2bin $bypass]

if {$cnfg(fdev) eq "u250" || $cnfg(fdev) eq "u200"} {
    # Create instance: xdma_0, and set properties
    set cmd "set xdma_0 \[ create_bd_cell -type ip -vlnv xilinx.com:ip:xdma:4.1 xdma_0 ]
            set_property -dict \[ list \
              CONFIG.axi_bypass_64bit_en {true} \
              CONFIG.axi_bypass_prefetchable {true} \
              CONFIG.axilite_master_en {true} \
              CONFIG.pf0_msix_cap_table_bir {BAR_2} \
              CONFIG.pf0_msix_cap_pba_bir {BAR_2} \
              CONFIG.axil_master_64bit_en {true} \
              CONFIG.axil_master_prefetchable {true} \
              CONFIG.axi_data_width {512_bit} \
              CONFIG.axi_id_width {4} \
              CONFIG.axist_bypass_en {true} \
              CONFIG.axist_bypass_scale {Megabytes} \
              CONFIG.axist_bypass_size {256} \
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
              CONFIG.xdma_num_usr_irq {16} \
              CONFIG.xdma_rnum_chnl {[expr {$cnfg(n_xchan)}]} \
              CONFIG.xdma_sts_ports {true} \
              CONFIG.xdma_wnum_chnl {[expr {$cnfg(n_xchan)}]} \
              CONFIG.xdma_wnum_rids {32} \
              CONFIG.xdma_rnum_rids {32} \
              CONFIG.en_ext_ch_gt_drp {true} \
            ] \$xdma_0"
    eval $cmd
}

if {$cnfg(fdev) eq "u280" || $cnfg(fdev) eq "u55c"} {
    # Create instance: xdma_0, and set properties
    set cmd "set xdma_0 \[ create_bd_cell -type ip -vlnv xilinx.com:ip:xdma:4.1 xdma_0 ]
            set_property -dict \[ list \
              CONFIG.axi_bypass_64bit_en {true} \
              CONFIG.axi_bypass_prefetchable {true} \
              CONFIG.axilite_master_en {true} \
              CONFIG.pf0_msix_cap_table_bir {BAR_2} \
              CONFIG.pf0_msix_cap_pba_bir {BAR_2} \
              CONFIG.axil_master_64bit_en {true} \
              CONFIG.axil_master_prefetchable {true} \
              CONFIG.axi_data_width {512_bit} \
              CONFIG.axi_id_width {4} \
              CONFIG.axist_bypass_en {true} \
              CONFIG.axist_bypass_scale {Megabytes} \
              CONFIG.axist_bypass_size {256} \
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
              CONFIG.xdma_num_usr_irq {16} \
              CONFIG.xdma_rnum_chnl {[expr {$cnfg(n_xchan)}]} \
              CONFIG.xdma_sts_ports {true} \
              CONFIG.xdma_wnum_chnl {[expr {$cnfg(n_xchan)}]} \
              CONFIG.xdma_wnum_rids {32} \
              CONFIG.xdma_rnum_rids {32} \
              CONFIG.pcie_blk_locn {PCIE4C_X1Y1} \
              CONFIG.en_ext_ch_gt_drp {true} \
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
              CONFIG.axist_bypass_scale {Megabytes} \
              CONFIG.axist_bypass_size {256} \
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
              CONFIG.xdma_num_usr_irq {16} \
              CONFIG.xdma_rnum_chnl {[expr {$cnfg(n_xchan)}]} \
              CONFIG.xdma_sts_ports {true} \
              CONFIG.xdma_wnum_chnl {[expr {$cnfg(n_xchan)}]} \
              CONFIG.xdma_wnum_rids {32} \
              CONFIG.xdma_rnum_rids {32} \
              CONFIG.en_ext_ch_gt_drp {true} \
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
              CONFIG.axist_bypass_scale {Megabytes} \
              CONFIG.axist_bypass_size {256} \
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
              CONFIG.xdma_num_usr_irq {16} \
              CONFIG.xdma_rnum_chnl {[expr {$cnfg(n_xchan)}]} \
              CONFIG.xdma_sts_ports {true} \
              CONFIG.xdma_wnum_chnl {[expr {$cnfg(n_xchan)}]} \
              CONFIG.xdma_wnum_rids {32} \
              CONFIG.xdma_rnum_rids {32} \
              CONFIG.en_ext_ch_gt_drp {true} \
            ] \$xdma_0"
    eval $cmd
}
  

########################################################################################################
# Create interface connections
########################################################################################################
  
  # XDMA
  connect_bd_intf_net -intf_net diff_clock_rtl_0_1 [get_bd_intf_ports pcie_clk] [get_bd_intf_pins util_ds_buf/CLK_IN_D]
  connect_bd_intf_net -intf_net xdma_0_pcie_mgt [get_bd_intf_ports pcie_x16] [get_bd_intf_pins xdma_0/pcie_mgt]
  connect_bd_intf_net -intf_net xdma_0_dma_status_ports [get_bd_intf_ports dsc_status] [get_bd_intf_pins xdma_0/dma_status_ports]

  # Data lines
  for {set i 0}  {$i < $cnfg(n_xchan)} {incr i} { 
    set cmd "connect_bd_intf_net -intf_net axis_dyn_in_$i\_1 \[get_bd_intf_ports axis_dyn_in_$i] \[get_bd_intf_pins xdma_0/S_AXIS_C2H_$i]"
    eval $cmd

    set cmd "connect_bd_intf_net -intf_net xdma_0_M_AXIS_H2C_$i \[get_bd_intf_ports axis_dyn_out_$i] \[get_bd_intf_pins xdma_0/M_AXIS_H2C_$i]"
    eval $cmd

    set cmd "connect_bd_intf_net -intf_net dsc_bypass_c2h_$i\_1 \[get_bd_intf_ports dsc_bypass_c2h_$i] \[get_bd_intf_pins xdma_0/dsc_bypass_c2h_$i]"
    eval $cmd

    set cmd "connect_bd_intf_net -intf_net dsc_bypass_h2c_$i\_1 \[get_bd_intf_ports dsc_bypass_h2c_$i] \[get_bd_intf_pins xdma_0/dsc_bypass_h2c_$i]"
    eval $cmd
  }

  # Control lines
  connect_bd_intf_net [get_bd_intf_ports axi_cnfg] [get_bd_intf_pins xdma_0/M_AXI_LITE]
  connect_bd_intf_net [get_bd_intf_ports axi_main] [get_bd_intf_pins xdma_0/M_AXI_BYPASS]

########################################################################################################
# Create port connections
########################################################################################################

  # XDMA
  connect_bd_net -net reset_rtl_0_1 [get_bd_ports perst_n] [get_bd_pins xdma_0/sys_rst_n]
  connect_bd_net -net usr_irq_1 [get_bd_ports usr_irq] [get_bd_pins xdma_0/usr_irq_req]
  connect_bd_net -net util_ds_buf_IBUF_DS_ODIV2 [get_bd_pins util_ds_buf/IBUF_DS_ODIV2] [get_bd_pins xdma_0/sys_clk]
  connect_bd_net -net util_ds_buf_IBUF_OUT [get_bd_pins util_ds_buf/IBUF_OUT] [get_bd_pins xdma_0/sys_clk_gt]

  connect_bd_net [get_bd_pins xlconstant_0/dout] [get_bd_pins xdma_0/sys_rst_n]

  # Clocks and resets main

  connect_bd_net [get_bd_pins proc_sys_reset_p/ext_reset_in] [get_bd_pins xlconstant_1/dout]
  connect_bd_net [get_bd_pins proc_sys_reset_p/slowest_sync_clk] [get_bd_pins clk_wiz_0/clk_out1]
  connect_bd_net [get_bd_ports presetn] [get_bd_pins proc_sys_reset_p/peripheral_aresetn]

  connect_bd_net [get_bd_pins proc_sys_reset_d/ext_reset_in] [get_bd_pins xlconstant_1/dout]
  connect_bd_net [get_bd_pins proc_sys_reset_d/slowest_sync_clk] [get_bd_pins clk_wiz_0/clk_out2]
  connect_bd_net [get_bd_ports dresetn] [get_bd_pins proc_sys_reset_d/peripheral_aresetn]

  connect_bd_net [get_bd_pins util_vector_logic_0/Op1] [get_bd_pins xlconstant_1/dout]
  connect_bd_net [get_bd_pins util_vector_logic_0/Res] [get_bd_pins proc_sys_reset_x/ext_reset_in]
  connect_bd_net [get_bd_ports xresetn] [get_bd_pins proc_sys_reset_x/peripheral_aresetn]
  connect_bd_net [get_bd_ports eos_resetn] [get_bd_pins util_vector_logic_0/Op2]

  connect_bd_net [get_bd_pins xdma_0/ext_ch_gt_drpclk] [get_bd_pins clk_wiz_0/clk_in1]
  connect_bd_net [get_bd_ports pclk] [get_bd_pins clk_wiz_0/clk_out1]
  connect_bd_net [get_bd_ports dclk] [get_bd_pins clk_wiz_0/clk_out2]

  connect_bd_net [get_bd_ports lckresetn] [get_bd_pins clk_wiz_0/locked]

  connect_bd_net [get_bd_ports xclk] [get_bd_pins xdma_0/axi_aclk]
  connect_bd_net [get_bd_pins proc_sys_reset_x/slowest_sync_clk] [get_bd_pins xdma_0/axi_aclk]
  connect_bd_net [get_bd_pins proc_sys_reset_1/slowest_sync_clk] [get_bd_pins xdma_0/axi_aclk]

  connect_bd_net -net xdma_0_axi_aresetn_ns [get_bd_pins xdma_0/axi_aresetn] [get_bd_pins proc_sys_reset_1/ext_reset_in]
  connect_bd_net -net proc_sys_reset_1_peripheral_aresetn [get_bd_ports sresetn] [get_bd_pins proc_sys_reset_1/peripheral_aresetn]  

  

########################################################################################################
# Create address segments
########################################################################################################
  
  create_bd_addr_seg -range 256M -offset 0x0000000000000000 [get_bd_addr_spaces xdma_0/M_AXI_BYPASS] [get_bd_addr_segs axi_main/Reg] SEG_axi_main_Reg
  create_bd_addr_seg -range 1M -offset 0x00000000 [get_bd_addr_spaces xdma_0/M_AXI_LITE] [get_bd_addr_segs axi_cnfg/Reg] SEG_axi_cnfg_Reg

  # Restore current instance
  current_bd_instance $oldCurInst

  save_bd_design
  close_bd_design $design_name 

  return 0
}
# End of cr_bd_design_static()
