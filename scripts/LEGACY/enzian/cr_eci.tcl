# Proc to create BD design_static (Enzian)
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
  xilinx.com:ip:util_ds_buf:2.1\
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

  set axi_ctrl_main [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_ctrl_main ]
  set_property -dict [list \
    CONFIG.MAX_BURST_LENGTH {1} \
    CONFIG.NUM_WRITE_OUTSTANDING {4} \
    CONFIG.NUM_READ_OUTSTANDING {4} \
    CONFIG.SUPPORTS_NARROW_BURST {0} \
    CONFIG.ADDR_WIDTH {64} \
    CONFIG.ID_WIDTH {0} \
    CONFIG.PROTOCOL {AXI4LITE} \
    CONFIG.DATA_WIDTH {64}\
  ] $axi_ctrl_main

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
########################################################################################################
# Create ports
########################################################################################################  

  # Main system reset
  set aresetn [ create_bd_port -dir O -type rst aresetn ]

  # Main system clock
  set cmd "set aclk \[ create_bd_port -dir I -type clk aclk ]
            set_property -dict \[ list \
            CONFIG.FREQ_HZ $cnfg(aclk_f)000000 \
            CONFIG.ASSOCIATED_BUSIF {axi_cnfg"
            for {set i 0}  {$i < $cnfg(n_reg)} {incr i} {
                append cmd ":axi_ctrl_$i"
            }
            append cmd "} \
              CONFIG.ASSOCIATED_RESET {aresetn} \
  ] \$aclk"
  eval $cmd

  # ECI reset
  set xresetn [ create_bd_port -dir I -type rst xresetn ]

  # ECI clock
  set cmd "set xclk \[ create_bd_port -dir I -type clk xclk ]
            set_property -dict \[ list \
            CONFIG.FREQ_HZ 322265625 \
            CONFIG.ASSOCIATED_BUSIF {axi_ctrl_main"
            append cmd "} \
            CONFIG.ASSOCIATED_RESET {xresetn} \
  ] \$xclk"
  eval $cmd

  # Net clk
  set nclk [ create_bd_port -dir I -type clk -freq_hz 250000000 nclk ]
  set nresetn [ create_bd_port -dir O -type rst nresetn ]
  set_property CONFIG.ASSOCIATED_RESET {nresetn} [get_bd_ports /nclk]

  # User clk
  set uclk [ create_bd_port -dir I -type clk -freq_hz 300000000 uclk ]
  set uresetn [ create_bd_port -dir O -type rst uresetn ]
  set_property CONFIG.ASSOCIATED_RESET {uresetn} [get_bd_ports /uclk]

  # PR clk
  set pclk [ create_bd_port -dir I -type clk -freq_hz 100000000 pclk ]
  set presetn [ create_bd_port -dir O -type rst presetn ]
  set_property CONFIG.ASSOCIATED_RESET {presetn} [get_bd_ports /pclk]
  
  set sys_reset [ create_bd_port -dir O -type rst sys_reset ]

########################################################################################################
# Create interconnect and components
########################################################################################################
  # Create instance: axi_interconnect_0, and set properties
  set ic0_mi [expr {$cnfg(n_reg) + 1}]

  set cmd "set axi_interconnect_0 \[ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0 ]
          set_property -dict \[ list \
          CONFIG.S00_HAS_REGSLICE {4} \
          CONFIG.NUM_MI {$ic0_mi} \
          CONFIG.S00_HAS_DATA_FIFO {2} \
          CONFIG.STRATEGY {2} \ "
    for {set i 0} {$i <= $cnfg(n_reg)} {incr i} {
      append cmd [format " CONFIG.M%02d_HAS_REGSLICE {4}"  $i]
    }
  append cmd "] \$axi_interconnect_0"
  eval $cmd

  set proc_sys_reset_p [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_p ]
  set proc_sys_reset_n [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_n ]
  set proc_sys_reset_u [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_u ]
  set proc_sys_reset_a [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_a ]

  create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_0
  create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_1
  set_property -dict [list CONFIG.CONST_VAL {0}] [get_bd_cells xlconstant_1]

########################################################################################################
# Create interface connections
########################################################################################################
  connect_bd_intf_net -intf_net axi_interconnect_0_M00_AXI [get_bd_intf_ports axi_cnfg] [get_bd_intf_pins axi_interconnect_0/M00_AXI]

  # Dynamic control
  for {set i 0}  {$i < $cnfg(n_reg)} {incr i} { 
    set j [expr {$i + 1}]
    set cmd [format "connect_bd_intf_net -intf_net axi_interconnect_0_M%02d_AXI \[get_bd_intf_ports axi_ctrl_%d] \[get_bd_intf_pins axi_interconnect_0/M%02d_AXI]" $j $i $j]
    eval $cmd 
  }

########################################################################################################
# Create port connections
########################################################################################################

  # Clocks and resets main
  connect_bd_net -net p_aresetn_1 [get_bd_ports presetn] [get_bd_pins proc_sys_reset_p/peripheral_aresetn]
  connect_bd_net -net clk_wiz_0_clk_out1 [get_bd_ports pclk] [get_bd_pins proc_sys_reset_p/slowest_sync_clk]

  connect_bd_net -net n_aresetn_1 [get_bd_ports nresetn] [get_bd_pins proc_sys_reset_n/peripheral_aresetn]
  connect_bd_net -net clk_wiz_0_clk_out3 [get_bd_ports nclk] [get_bd_pins proc_sys_reset_n/slowest_sync_clk]

  connect_bd_net -net u_aresetn_1 [get_bd_ports uresetn] [get_bd_pins proc_sys_reset_u/peripheral_aresetn]
  connect_bd_net -net clk_wiz_0_clk_out4 [get_bd_ports uclk] [get_bd_pins proc_sys_reset_u/slowest_sync_clk]

  connect_bd_net -net a_aresetn_1 [get_bd_ports aresetn] [get_bd_pins proc_sys_reset_a/peripheral_aresetn]
  connect_bd_net -net clk_wiz_0_clk_out2 [get_bd_ports aclk] [get_bd_pins proc_sys_reset_a/slowest_sync_clk]

  connect_bd_net [get_bd_pins xlconstant_0/dout] [get_bd_pins proc_sys_reset_a/ext_reset_in]
  connect_bd_net [get_bd_pins xlconstant_0/dout] [get_bd_pins proc_sys_reset_n/ext_reset_in]
  connect_bd_net [get_bd_pins xlconstant_0/dout] [get_bd_pins proc_sys_reset_u/ext_reset_in]
  connect_bd_net [get_bd_pins xlconstant_0/dout] [get_bd_pins proc_sys_reset_p/ext_reset_in]

  connect_bd_net [get_bd_ports sys_reset] [get_bd_pins xlconstant_1/dout]

  # Main
  connect_bd_intf_net [get_bd_intf_ports axi_ctrl_main] -boundary_type upper [get_bd_intf_pins axi_interconnect_0/S00_AXI]
  connect_bd_net [get_bd_ports xclk] [get_bd_pins axi_interconnect_0/S00_ACLK]
  connect_bd_net [get_bd_ports xresetn] [get_bd_pins axi_interconnect_0/S00_ARESETN]

  set cmd_clk "connect_bd_net \[get_bd_ports aclk] \[get_bd_pins axi_interconnect_0/ACLK] \[get_bd_pins axi_interconnect_0/M00_ACLK]"
  set cmd_rst "connect_bd_net \[get_bd_pins proc_sys_reset_a/interconnect_aresetn] \[get_bd_pins axi_interconnect_0/ARESETN] \[get_bd_pins axi_interconnect_0/M00_ARESETN]"

  for {set i 1}  {$i <= $cnfg(n_reg)} {incr i} {
    append cmd_clk [format " \[get_bd_pins axi_interconnect_0/M%02d_ACLK]" $i]
    append cmd_rst [format " \[get_bd_pins axi_interconnect_0/M%02d_ARESETN]" $i]
  }
    
  eval $cmd_clk
  eval $cmd_rst

########################################################################################################
# Create address segments
########################################################################################################
  # Static config
  create_bd_addr_seg -range 0x00008000 -offset 0x00000000 [get_bd_addr_spaces /axi_ctrl_main] [get_bd_addr_segs axi_cnfg/Reg] SEG_axi_cnfg_Reg

  for {set i 0}  {$i < $cnfg(n_reg)} {incr i} {
    set cmd [format "create_bd_addr_seg -range 0x00040000 -offset 0x000%02x0000 \[get_bd_addr_spaces /axi_ctrl_main] \[get_bd_addr_segs axi_ctrl_$i/Reg] SEG_axi_ctrl_$i\_Reg" [expr {0x10 + $i *4}]]
    eval $cmd
  }

  # Restore current instance
  current_bd_instance $oldCurInst

  save_bd_design
  close_bd_design $design_name 

  return 0
}
# End of cr_bd_design_static()
