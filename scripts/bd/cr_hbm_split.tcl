
# Util HBM
proc create_hier_cell_init_logic { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_msg_id "BD_TCL-102" "ERROR" "create_hier_cell_init_logic() - Empty argument(s)!"}
     return
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

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins

  # Create pins
  create_bd_pin -dir I -from 0 -to 0 In0
  create_bd_pin -dir I -from 0 -to 0 In1
  create_bd_pin -dir O hbm_mc_init_seq_complete

  # Create instance: init_concat, and set properties
  set init_concat [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 init_concat ]
  set_property -dict [ list \
   CONFIG.NUM_PORTS {2} \
 ] $init_concat

  # Create instance: init_reduce, and set properties
  set init_reduce [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_reduced_logic:2.0 init_reduce ]
  set_property -dict [ list \
   CONFIG.C_OPERATION {and} \
   CONFIG.C_SIZE {2} \
 ] $init_reduce

  # Create port connections
  connect_bd_net -net hbm_inst_apb_complete_0 [get_bd_pins In0] [get_bd_pins init_concat/In0]
  connect_bd_net -net hbm_inst_apb_complete_1 [get_bd_pins In1] [get_bd_pins init_concat/In1]
  connect_bd_net -net init_concat_dout [get_bd_pins init_concat/dout] [get_bd_pins init_reduce/Op1]
  connect_bd_net -net init_reduce_Res [get_bd_pins hbm_mc_init_seq_complete] [get_bd_pins init_reduce/Res]

  # Restore current instance
  current_bd_instance $oldCurInst
}

proc create_hier_cell_path { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_msg_id "BD_TCL-102" "ERROR" "create_hier_cell_path() - Empty argument(s)!"}
     return
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

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M_AXI
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI

  # Create pins
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type rst aresetn
  create_bd_pin -dir I -type rst hresetn
  create_bd_pin -dir I -type clk hclk

  # Create instance: slice, and set properties
  set slice_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_register_slice:2.1 slice_0]
  set_property -dict [ list \
   CONFIG.REG_AR {10} \
   CONFIG.REG_AW {10} \
   CONFIG.REG_B {10} \
   CONFIG.REG_R {10} \
   CONFIG.REG_W {10} \
 ] $slice_0

 create_bd_cell -type ip -vlnv xilinx.com:ip:axi_clock_converter:2.1 axi_clock_converter_0
 create_bd_cell -type ip -vlnv xilinx.com:ip:rama:1.1 rama_0
 set_property -dict [list CONFIG.G_MEM_INTERLEAVE_TYPE {per_memory} CONFIG.G_MEM_COUNT {16} CONFIG.G_REORDER_QUEUE_DEPTH {512}] [get_bd_cells rama_0]

  # Create interface connections
  connect_bd_intf_net [get_bd_intf_pins S_AXI] [get_bd_intf_pins slice_0/S_AXI] 
  connect_bd_intf_net [get_bd_intf_pins slice_0/M_AXI] [get_bd_intf_pins axi_clock_converter_0/S_AXI]
  connect_bd_intf_net [get_bd_intf_pins axi_clock_converter_0/M_AXI] [get_bd_intf_pins rama_0/s_axi]
  connect_bd_intf_net [get_bd_intf_pins rama_0/m_axi] [get_bd_intf_pins M_AXI]
  

  # Create port connections
  connect_bd_net [get_bd_pins aclk] [get_bd_pins axi_clock_converter_0/s_axi_aclk] [get_bd_pins slice_0/aclk] 
  connect_bd_net [get_bd_pins aresetn] [get_bd_pins axi_clock_converter_0/s_axi_aresetn] [get_bd_pins slice_0/aresetn] 
  connect_bd_net [get_bd_pins hclk] [get_bd_pins axi_clock_converter_0/m_axi_aclk] [get_bd_pins rama_0/axi_aclk]
  connect_bd_net [get_bd_pins hresetn] [get_bd_pins axi_clock_converter_0/m_axi_aresetn] [get_bd_pins rama_0/axi_aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}


# Main HBM
proc cr_bd_design_hbm { parentCell } {
  upvar #0 cfg cnfg

  # CHANGE DESIGN NAME HERE
  set design_name design_hbm

  common::send_msg_id "BD_TCL-003" "INFO" "Currently there is no design <$design_name> in project, so creating one..."

  create_bd_design $design_name

  set bCheckIPsPassed 1
  ########################################################################################################
  # CHECK IPs
  ########################################################################################################
  set bCheckIPs 1
  if { $bCheckIPs == 1 } {
     set list_check_ips "\ 
  xilinx.com:ip:hbm:1.0\
  xilinx.com:ip:proc_sys_reset:5.0\
  xilinx.com:ip:axi_apb_bridge:3.0\
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
# HBM
########################################################################################################
########################################################################################################

########################################################################################################
# Create all ports
########################################################################################################

   # AXI ports
   for {set i 0}  {$i < $cnfg(n_mem_chan)} {incr i} {   
      set cmd "set axi_hbm_in_$i \[ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_hbm_in_$i ]
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
               ] \$axi_hbm_in_$i"
      eval $cmd
   }

   for {set i 0}  {$i < 2 * (16 - $cnfg(n_mem_chan))} {incr i} {   
      set cmd "set axi_toff_in_$i \[ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_toff_in_$i ]
               set_property -dict \[ list \
                  CONFIG.ADDR_WIDTH {64} \
                  CONFIG.ARUSER_WIDTH {0} \
                  CONFIG.AWUSER_WIDTH {0} \
                  CONFIG.BUSER_WIDTH {0} \
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
                  CONFIG.ID_WIDTH {6} \
                  CONFIG.MAX_BURST_LENGTH {64} \
                  CONFIG.NUM_READ_OUTSTANDING {8} \
                  CONFIG.NUM_READ_THREADS {8} \
                  CONFIG.NUM_WRITE_OUTSTANDING {8} \
                  CONFIG.NUM_WRITE_THREADS {8} \
                  CONFIG.PROTOCOL {AXI3} \
                  CONFIG.READ_WRITE_MODE {READ_WRITE} \
                  CONFIG.RUSER_BITS_PER_BYTE {0} \
                  CONFIG.RUSER_WIDTH {0} \
                  CONFIG.SUPPORTS_NARROW_BURST {0} \
                  CONFIG.WUSER_BITS_PER_BYTE {0} \
                  CONFIG.WUSER_WIDTH {0} \
               ] \$axi_toff_in_$i"
      eval $cmd
   }

  # Internal
  set cmd "set hclk_int \[ create_bd_port -dir O -type clk hclk_int ]
   set_property -dict \[ list \
   CONFIG.FREQ_HZ {$cnfg(hclk_f)000000} \
   CONFIG.ASSOCIATED_BUSIF {" 
   for {set i 0}  {$i < 2 * (16 - $cnfg(n_mem_chan))} {incr i} {
      append cmd "axi_toff_in_$i"
      if {$i != 2 * (16 - $cnfg(n_mem_chan)) - 1} {
         append cmd ":"
      }
   }
   append cmd "} \
   ] \$hclk_int"
  eval $cmd

  set S_AXI_CTRL [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI_CTRL ]
  set_property -dict [ list \
   CONFIG.ADDR_WIDTH {23} \
   CONFIG.PROTOCOL {AXI4LITE} \
   ] $S_AXI_CTRL

  set DRAM_0_STAT_TEMP [ create_bd_port -dir O -from 6 -to 0 DRAM_0_STAT_TEMP ]
  set DRAM_1_STAT_TEMP [ create_bd_port -dir O -from 6 -to 0 DRAM_1_STAT_TEMP ]
  set DRAM_STAT_CATTRIP [ create_bd_port -dir O -from 0 -to 0 -type intr DRAM_STAT_CATTRIP ]

  # Clocks and resets
  create_bd_port -dir I -type rst sys_reset
  set_property CONFIG.POLARITY ACTIVE_HIGH [get_bd_ports sys_reset]

  # System clock
  set cmd "set aclk \[ create_bd_port -dir I -type clk aclk ]
        set_property -dict \[ list \
            CONFIG.ASSOCIATED_BUSIF {" 
            for {set i 0}  {$i < $cnfg(n_mem_chan)} {incr i} {
               append cmd "axi_hbm_in_$i"
               if {$i != $cnfg(n_mem_chan) - 1} {
                  append cmd ":"
               }
            }
            append cmd "} \
            CONFIG.ASSOCIATED_RESET {aresetn} \
            CONFIG.FREQ_HZ {$cnfg(aclk_f)000000} \
        ] \$aclk"
  eval $cmd

  set aresetn [ create_bd_port -dir I -type rst aresetn ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_LOW} \
 ] $aresetn  

  # HBM clock
  set cmd "set hclk \[ create_bd_port -dir I -type clk hclk ]
   set_property -dict \[ list \
   CONFIG.FREQ_HZ {100000000} \
   ] \$hclk"
  eval $cmd

  set hresetn [ create_bd_port -dir I -type rst hresetn ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_LOW} \
 ] $hresetn

  # Debug clock
  set cmd "set dclk \[ create_bd_port -dir I -type clk dclk ]
   set_property -dict \[ list \
   CONFIG.FREQ_HZ {100000000} \
   ] \$dclk"
  eval $cmd

  set dresetn [ create_bd_port -dir I -type rst dresetn ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_LOW} \
 ] $dresetn
  set_property CONFIG.ASSOCIATED_RESET {dresetn} [get_bd_ports /dclk]

  set hbm_mc_init_seq_complete [ create_bd_port -dir O hbm_mc_init_seq_complete ]
  
  # Components

  # Create instance: axi_apb_bridge_inst, and set properties
  set axi_apb_bridge_inst [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_apb_bridge:3.0 axi_apb_bridge_inst ]
  set_property -dict [ list \
   CONFIG.C_APB_NUM_SLAVES {2} \
   CONFIG.C_M_APB_PROTOCOL {apb3} \
 ] $axi_apb_bridge_inst

  # Create instance: hbm_inst, and set properties
  # Set density first
  if {$cnfg(hbm_size) == 33} {
    set hbm_density "8GB"
  } else {
    set hbm_density "16GB"
  }

  set cmd "set hbm_inst \[ create_bd_cell -type ip -vlnv xilinx.com:ip:hbm:1.0 hbm_inst ]
   set_property -dict \[ list \
     CONFIG.USER_AXI_CLK_FREQ {[expr {$cnfg(hclk_f)}]} \
     CONFIG.USER_AXI_CLK1_FREQ {[expr {$cnfg(hclk_f)}]} \
     CONFIG.USER_CLK_SEL_LIST0 {AXI_15_ACLK} \
     CONFIG.USER_CLK_SEL_LIST1 {AXI_31_ACLK} \
     CONFIG.USER_DIS_REF_CLK_BUFG {TRUE} \
     CONFIG.USER_HBM_DENSITY {$hbm_density} \
     CONFIG.USER_HBM_STACK {2} \
     CONFIG.USER_INIT_TIMEOUT_VAL {0} \
     CONFIG.USER_MC0_ECC_SCRUB_PERIOD {0x0032} \
     CONFIG.USER_MC0_ENABLE_ECC_CORRECTION {true} \
     CONFIG.USER_MC0_ENABLE_ECC_SCRUBBING {true} \
     CONFIG.USER_MC0_EN_DATA_MASK {false} \
     CONFIG.USER_MC0_INITILIZE_MEM_USING_ECC_SCRUB {true} \
     CONFIG.USER_MC0_TEMP_CTRL_SELF_REF_INTVL {true} \
     CONFIG.USER_MC10_ECC_SCRUB_PERIOD {0x0032} \
     CONFIG.USER_MC10_ENABLE_ECC_CORRECTION {true} \
     CONFIG.USER_MC10_ENABLE_ECC_SCRUBBING {true} \
     CONFIG.USER_MC10_EN_DATA_MASK {false} \
     CONFIG.USER_MC10_INITILIZE_MEM_USING_ECC_SCRUB {true} \
     CONFIG.USER_MC10_TEMP_CTRL_SELF_REF_INTVL {true} \
     CONFIG.USER_MC11_ECC_SCRUB_PERIOD {0x0032} \
     CONFIG.USER_MC11_ENABLE_ECC_CORRECTION {true} \
     CONFIG.USER_MC11_ENABLE_ECC_SCRUBBING {true} \
     CONFIG.USER_MC11_EN_DATA_MASK {false} \
     CONFIG.USER_MC11_INITILIZE_MEM_USING_ECC_SCRUB {true} \
     CONFIG.USER_MC11_TEMP_CTRL_SELF_REF_INTVL {true} \
     CONFIG.USER_MC12_ECC_SCRUB_PERIOD {0x0032} \
     CONFIG.USER_MC12_ENABLE_ECC_CORRECTION {true} \
     CONFIG.USER_MC12_ENABLE_ECC_SCRUBBING {true} \
     CONFIG.USER_MC12_EN_DATA_MASK {false} \
     CONFIG.USER_MC12_INITILIZE_MEM_USING_ECC_SCRUB {true} \
     CONFIG.USER_MC12_TEMP_CTRL_SELF_REF_INTVL {true} \
     CONFIG.USER_MC13_ECC_SCRUB_PERIOD {0x0032} \
     CONFIG.USER_MC13_ENABLE_ECC_CORRECTION {true} \
     CONFIG.USER_MC13_ENABLE_ECC_SCRUBBING {true} \
     CONFIG.USER_MC13_EN_DATA_MASK {false} \
     CONFIG.USER_MC13_INITILIZE_MEM_USING_ECC_SCRUB {true} \
     CONFIG.USER_MC13_TEMP_CTRL_SELF_REF_INTVL {true} \
     CONFIG.USER_MC14_ECC_SCRUB_PERIOD {0x0032} \
     CONFIG.USER_MC14_ENABLE_ECC_CORRECTION {true} \
     CONFIG.USER_MC14_ENABLE_ECC_SCRUBBING {true} \
     CONFIG.USER_MC14_EN_DATA_MASK {false} \
     CONFIG.USER_MC14_INITILIZE_MEM_USING_ECC_SCRUB {true} \
     CONFIG.USER_MC14_TEMP_CTRL_SELF_REF_INTVL {true} \
     CONFIG.USER_MC15_ECC_SCRUB_PERIOD {0x0032} \
     CONFIG.USER_MC15_ENABLE_ECC_CORRECTION {true} \
     CONFIG.USER_MC15_ENABLE_ECC_SCRUBBING {true} \
     CONFIG.USER_MC15_EN_DATA_MASK {false} \
     CONFIG.USER_MC15_INITILIZE_MEM_USING_ECC_SCRUB {true} \
     CONFIG.USER_MC15_TEMP_CTRL_SELF_REF_INTVL {true} \
     CONFIG.USER_MC1_ECC_SCRUB_PERIOD {0x0032} \
     CONFIG.USER_MC1_ENABLE_ECC_CORRECTION {true} \
     CONFIG.USER_MC1_ENABLE_ECC_SCRUBBING {true} \
     CONFIG.USER_MC1_EN_DATA_MASK {false} \
     CONFIG.USER_MC1_INITILIZE_MEM_USING_ECC_SCRUB {true} \
     CONFIG.USER_MC1_TEMP_CTRL_SELF_REF_INTVL {true} \
     CONFIG.USER_MC2_ECC_SCRUB_PERIOD {0x0032} \
     CONFIG.USER_MC2_ENABLE_ECC_CORRECTION {true} \
     CONFIG.USER_MC2_ENABLE_ECC_SCRUBBING {true} \
     CONFIG.USER_MC2_EN_DATA_MASK {false} \
     CONFIG.USER_MC2_INITILIZE_MEM_USING_ECC_SCRUB {true} \
     CONFIG.USER_MC2_TEMP_CTRL_SELF_REF_INTVL {true} \
     CONFIG.USER_MC3_ECC_SCRUB_PERIOD {0x0032} \
     CONFIG.USER_MC3_ENABLE_ECC_CORRECTION {true} \
     CONFIG.USER_MC3_ENABLE_ECC_SCRUBBING {true} \
     CONFIG.USER_MC3_EN_DATA_MASK {false} \
     CONFIG.USER_MC3_INITILIZE_MEM_USING_ECC_SCRUB {true} \
     CONFIG.USER_MC3_TEMP_CTRL_SELF_REF_INTVL {true} \
     CONFIG.USER_MC4_ECC_SCRUB_PERIOD {0x0032} \
     CONFIG.USER_MC4_ENABLE_ECC_CORRECTION {true} \
     CONFIG.USER_MC4_ENABLE_ECC_SCRUBBING {true} \
     CONFIG.USER_MC4_EN_DATA_MASK {false} \
     CONFIG.USER_MC4_INITILIZE_MEM_USING_ECC_SCRUB {true} \
     CONFIG.USER_MC4_TEMP_CTRL_SELF_REF_INTVL {true} \
     CONFIG.USER_MC5_ECC_SCRUB_PERIOD {0x0032} \
     CONFIG.USER_MC5_ENABLE_ECC_CORRECTION {true} \
     CONFIG.USER_MC5_ENABLE_ECC_SCRUBBING {true} \
     CONFIG.USER_MC5_EN_DATA_MASK {false} \
     CONFIG.USER_MC5_INITILIZE_MEM_USING_ECC_SCRUB {true} \
     CONFIG.USER_MC5_TEMP_CTRL_SELF_REF_INTVL {true} \
     CONFIG.USER_MC6_ECC_SCRUB_PERIOD {0x0032} \
     CONFIG.USER_MC6_ENABLE_ECC_CORRECTION {true} \
     CONFIG.USER_MC6_ENABLE_ECC_SCRUBBING {true} \
     CONFIG.USER_MC6_EN_DATA_MASK {false} \
     CONFIG.USER_MC6_INITILIZE_MEM_USING_ECC_SCRUB {true} \
     CONFIG.USER_MC6_TEMP_CTRL_SELF_REF_INTVL {true} \
     CONFIG.USER_MC7_ECC_SCRUB_PERIOD {0x0032} \
     CONFIG.USER_MC7_ENABLE_ECC_CORRECTION {true} \
     CONFIG.USER_MC7_ENABLE_ECC_SCRUBBING {true} \
     CONFIG.USER_MC7_EN_DATA_MASK {false} \
     CONFIG.USER_MC7_INITILIZE_MEM_USING_ECC_SCRUB {true} \
     CONFIG.USER_MC7_TEMP_CTRL_SELF_REF_INTVL {true} \
     CONFIG.USER_MC8_ECC_SCRUB_PERIOD {0x0032} \
     CONFIG.USER_MC8_ENABLE_ECC_CORRECTION {true} \
     CONFIG.USER_MC8_ENABLE_ECC_SCRUBBING {true} \
     CONFIG.USER_MC8_EN_DATA_MASK {false} \
     CONFIG.USER_MC8_INITILIZE_MEM_USING_ECC_SCRUB {true} \
     CONFIG.USER_MC8_TEMP_CTRL_SELF_REF_INTVL {true} \
     CONFIG.USER_MC9_ECC_SCRUB_PERIOD {0x0032} \
     CONFIG.USER_MC9_ENABLE_ECC_CORRECTION {true} \
     CONFIG.USER_MC9_ENABLE_ECC_SCRUBBING {true} \
     CONFIG.USER_MC9_EN_DATA_MASK {false} \
     CONFIG.USER_MC9_INITILIZE_MEM_USING_ECC_SCRUB {true} \
     CONFIG.USER_MC9_TEMP_CTRL_SELF_REF_INTVL {true} \
     CONFIG.USER_MC_ENABLE_00 {TRUE} \
     CONFIG.USER_MC_ENABLE_01 {TRUE} \
     CONFIG.USER_MC_ENABLE_02 {TRUE} \
     CONFIG.USER_MC_ENABLE_03 {TRUE} \
     CONFIG.USER_MC_ENABLE_04 {TRUE} \
     CONFIG.USER_MC_ENABLE_05 {TRUE} \
     CONFIG.USER_MC_ENABLE_06 {TRUE} \
     CONFIG.USER_MC_ENABLE_07 {TRUE} \
     CONFIG.USER_MC_ENABLE_08 {TRUE} \
     CONFIG.USER_MC_ENABLE_09 {TRUE} \
     CONFIG.USER_MC_ENABLE_10 {TRUE} \
     CONFIG.USER_MC_ENABLE_11 {TRUE} \
     CONFIG.USER_MC_ENABLE_12 {TRUE} \
     CONFIG.USER_MC_ENABLE_13 {TRUE} \
     CONFIG.USER_MC_ENABLE_14 {TRUE} \
     CONFIG.USER_MC_ENABLE_15 {TRUE} \
     CONFIG.USER_SWITCH_ENABLE_01 {TRUE} \
     CONFIG.USER_XSDB_INTF_EN {TRUE} \
   ] \$hbm_inst"
  eval $cmd

 # Create instance: hbm_reset_sync_SLR0, and set properties
  set hbm_reset_sync_SLR0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 hbm_reset_sync_SLR0 ]
  set_property -dict [ list \
   CONFIG.C_AUX_RESET_HIGH {1} \
 ] $hbm_reset_sync_SLR0

  # Create instance: util_vector_logic, and set properties
  set util_vector_logic [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 util_vector_logic ]
  set_property -dict [ list \
   CONFIG.C_OPERATION {or} \
   CONFIG.C_SIZE {1} \
   CONFIG.LOGO_FILE {data/sym_orgate.png} \
 ] $util_vector_logic

 set_property generate_synth_checkpoint 0 [get_files axis_data_fifo_hbm_r.xci]
 set_property generate_synth_checkpoint 0 [get_files axis_data_fifo_hbm_w.xci]
 set_property generate_synth_checkpoint 0 [get_files axis_data_fifo_hbm_b.xci]

 create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0
 set cmd "set_property -dict \[list CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {$cnfg(hclk_f).000} CONFIG.USE_LOCKED {false} CONFIG.USE_RESET {false}] \[get_bd_cells clk_wiz_0]"
 eval $cmd
 #set_property -dict [list CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {250.000} CONFIG.USE_LOCKED {false} CONFIG.USE_RESET {false}] [get_bd_cells clk_wiz_0] 
 set_property -dict [list CONFIG.USE_RESET {true} CONFIG.RESET_TYPE {ACTIVE_LOW} CONFIG.RESET_PORT {resetn}] [get_bd_cells clk_wiz_0]

  connect_bd_net [get_bd_ports hclk] [get_bd_pins clk_wiz_0/clk_in1]
 #connect_bd_net [get_bd_ports get_bd_pins hbm_reset_sync_SLR0/interconnect_aresetn] [get_bd_pins clk_wiz_0/resetn]

 connect_bd_net [get_bd_ports hclk_int] [get_bd_pins clk_wiz_0/clk_out1]
 connect_bd_net [get_bd_ports hresetn] [get_bd_pins clk_wiz_0/resetn]

 set_property CONFIG.ASSOCIATED_BUSIF {S_AXI_CTRL} [get_bd_ports /dclk]

########################################################################################################
# Create interconnect
########################################################################################################

# Combiner
for {set i 0}  {$i < $cnfg(n_mem_chan)} {incr i} {   
   create_bd_cell -type module -reference hbm_wide hbm_wide_$i   
   set cmd [format "set_property -dict \[list CONFIG.HBM_CHAN_SIZE {$cnfg(hbm_size)}] \[get_bd_cells hbm_wide_$i]"]
   eval $cmd
   connect_bd_net [get_bd_ports aclk] [get_bd_pins hbm_wide_$i/aclk]
   connect_bd_net [get_bd_ports aresetn] [get_bd_pins hbm_wide_$i/aresetn]
}

 # Path
 for {set i 0}  {$i < 2 * $cnfg(n_mem_chan)} {incr i} {  
    create_hier_cell_path [current_bd_instance .] path_$i
    connect_bd_net [get_bd_ports aclk] [get_bd_pins path_$i/aclk]
    connect_bd_net [get_bd_ports aresetn] [get_bd_pins path_$i/aresetn]
    connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins path_$i/hclk]
    connect_bd_net [get_bd_pins hbm_reset_sync_SLR0/interconnect_aresetn] [get_bd_pins path_$i/hresetn]
 }

for {set i 0}  {$i < $cnfg(n_mem_chan)} {incr i} {  
   set cmd "[format "connect_bd_intf_net \[get_bd_intf_pins hbm_inst/SAXI_%02d_8HI] -boundary_type upper \[get_bd_intf_pins path_$i/M_AXI]" $i]"
   eval $cmd
}

for {set i 0}  {$i < $cnfg(n_mem_chan)} {incr i} {  
   set cmd "[format "connect_bd_intf_net \[get_bd_intf_pins hbm_inst/SAXI_%02d_8HI] -boundary_type upper \[get_bd_intf_pins path_%d/M_AXI]" [expr {$i + 16}] [expr {$i + $cnfg(n_mem_chan)}]]"
   eval $cmd
}

if {$cnfg(fdev) eq "u55c"} {
   for {set i $cnfg(n_mem_chan)}  {$i < 16} {incr i} {   
      set cmd "[format "connect_bd_intf_net \[get_bd_intf_pins hbm_inst/SAXI_%02d_8HI] -boundary_type upper \[get_bd_intf_ports axi_toff_in_%d]" $i [expr {$i - $cnfg(n_mem_chan)}]]"
      eval $cmd
      set cmd "[format "connect_bd_intf_net \[get_bd_intf_pins hbm_inst/SAXI_%02d_8HI] -boundary_type upper \[get_bd_intf_ports axi_toff_in_%d]" [expr {$i + 16}] [expr {($i - $cnfg(n_mem_chan)) + (16 - $cnfg(n_mem_chan))}]]"
      eval $cmd
   }
} else {
   for {set i $cnfg(n_mem_chan)}  {$i < 16} {incr i} {   
      set cmd "[format "connect_bd_intf_net \[get_bd_intf_pins hbm_inst/SAXI_%02d] -boundary_type upper \[get_bd_intf_ports axi_toff_in_%d]" $i [expr {$i - $cnfg(n_mem_chan)}]]"
      eval $cmd
      set cmd "[format "connect_bd_intf_net \[get_bd_intf_pins hbm_inst/SAXI_%02d] -boundary_type upper \[get_bd_intf_ports axi_toff_in_%d]" [expr {$i + 16}] [expr {($i - $cnfg(n_mem_chan)) + (16 - $cnfg(n_mem_chan))}]]"
      eval $cmd
   }
}

 
 for {set i 0}  {$i < $cnfg(n_mem_chan)} {incr i} {   
     set nn [expr {$i + $cnfg(n_mem_chan)}]
     connect_bd_intf_net -boundary_type upper [get_bd_intf_pins path_$i/S_AXI] [get_bd_intf_pins hbm_wide_$i/m_axi_0]
     connect_bd_intf_net -boundary_type upper [get_bd_intf_pins path_$nn/S_AXI] [get_bd_intf_pins hbm_wide_$i/m_axi_1]
     connect_bd_intf_net [get_bd_intf_ports axi_hbm_in_$i] [get_bd_intf_pins hbm_wide_$i/s_axi]
 }
 
 # Create instance: init_logic
  create_hier_cell_init_logic [current_bd_instance .] init_logic

 # Create interface connections
 connect_bd_intf_net [get_bd_intf_ports S_AXI_CTRL] [get_bd_intf_pins axi_apb_bridge_inst/AXI4_LITE]
 connect_bd_intf_net [get_bd_intf_pins axi_apb_bridge_inst/APB_M] [get_bd_intf_pins hbm_inst/SAPB_0]
 connect_bd_intf_net [get_bd_intf_pins axi_apb_bridge_inst/APB_M2] [get_bd_intf_pins hbm_inst/SAPB_1]

 # Create port connections
 connect_bd_net [get_bd_ports DRAM_STAT_CATTRIP] [get_bd_pins hbm_reset_sync_SLR0/aux_reset_in] [get_bd_pins util_vector_logic/Res]
 connect_bd_net [get_bd_ports dclk] [get_bd_pins axi_apb_bridge_inst/s_axi_aclk] [get_bd_pins hbm_inst/APB_0_PCLK] [get_bd_pins hbm_inst/APB_1_PCLK]
 connect_bd_net [get_bd_ports dresetn] [get_bd_pins axi_apb_bridge_inst/s_axi_aresetn] [get_bd_pins hbm_inst/APB_0_PRESET_N] [get_bd_pins hbm_inst/APB_1_PRESET_N]
 connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins hbm_inst/AXI_00_ACLK] [get_bd_pins hbm_inst/AXI_01_ACLK] [get_bd_pins hbm_inst/AXI_02_ACLK] [get_bd_pins hbm_inst/AXI_03_ACLK] [get_bd_pins hbm_inst/AXI_04_ACLK] [get_bd_pins hbm_inst/AXI_05_ACLK] [get_bd_pins hbm_inst/AXI_06_ACLK] [get_bd_pins hbm_inst/AXI_07_ACLK] [get_bd_pins hbm_inst/AXI_08_ACLK] [get_bd_pins hbm_inst/AXI_09_ACLK] [get_bd_pins hbm_inst/AXI_10_ACLK] [get_bd_pins hbm_inst/AXI_11_ACLK] [get_bd_pins hbm_inst/AXI_12_ACLK] [get_bd_pins hbm_inst/AXI_13_ACLK] [get_bd_pins hbm_inst/AXI_14_ACLK] [get_bd_pins hbm_inst/AXI_15_ACLK] [get_bd_pins hbm_inst/AXI_16_ACLK] [get_bd_pins hbm_inst/AXI_17_ACLK] [get_bd_pins hbm_inst/AXI_18_ACLK] [get_bd_pins hbm_inst/AXI_19_ACLK] [get_bd_pins hbm_inst/AXI_20_ACLK] [get_bd_pins hbm_inst/AXI_21_ACLK] [get_bd_pins hbm_inst/AXI_22_ACLK] [get_bd_pins hbm_inst/AXI_23_ACLK] [get_bd_pins hbm_inst/AXI_24_ACLK] [get_bd_pins hbm_inst/AXI_25_ACLK] [get_bd_pins hbm_inst/AXI_26_ACLK] [get_bd_pins hbm_inst/AXI_27_ACLK] [get_bd_pins hbm_inst/AXI_28_ACLK] [get_bd_pins hbm_inst/AXI_29_ACLK] [get_bd_pins hbm_inst/AXI_30_ACLK] [get_bd_pins hbm_inst/AXI_31_ACLK] [get_bd_pins hbm_reset_sync_SLR0/slowest_sync_clk]
 connect_bd_net [get_bd_pins hresetn] [get_bd_pins hbm_reset_sync_SLR0/ext_reset_in]
 connect_bd_net [get_bd_pins hbm_inst/DRAM_0_STAT_CATTRIP] [get_bd_pins util_vector_logic/Op1]
 connect_bd_net [get_bd_ports DRAM_0_STAT_TEMP] [get_bd_pins hbm_inst/DRAM_0_STAT_TEMP]
 connect_bd_net [get_bd_pins hbm_inst/DRAM_1_STAT_CATTRIP] [get_bd_pins util_vector_logic/Op2]
 connect_bd_net [get_bd_ports DRAM_1_STAT_TEMP] [get_bd_pins hbm_inst/DRAM_1_STAT_TEMP]
 connect_bd_net [get_bd_pins hbm_inst/apb_complete_0] [get_bd_pins init_logic/In0]
 connect_bd_net [get_bd_pins hbm_inst/apb_complete_1] [get_bd_pins init_logic/In1]
 connect_bd_net [get_bd_ports hclk] [get_bd_pins hbm_inst/HBM_REF_CLK_0] [get_bd_pins hbm_inst/HBM_REF_CLK_1]
 connect_bd_net [get_bd_pins hbm_inst/AXI_00_ARESET_N] [get_bd_pins hbm_inst/AXI_01_ARESET_N] [get_bd_pins hbm_inst/AXI_02_ARESET_N] [get_bd_pins hbm_inst/AXI_03_ARESET_N] [get_bd_pins hbm_inst/AXI_04_ARESET_N] [get_bd_pins hbm_inst/AXI_05_ARESET_N] [get_bd_pins hbm_inst/AXI_06_ARESET_N] [get_bd_pins hbm_inst/AXI_07_ARESET_N] [get_bd_pins hbm_inst/AXI_08_ARESET_N] [get_bd_pins hbm_inst/AXI_09_ARESET_N] [get_bd_pins hbm_inst/AXI_10_ARESET_N] [get_bd_pins hbm_inst/AXI_11_ARESET_N] [get_bd_pins hbm_inst/AXI_12_ARESET_N] [get_bd_pins hbm_inst/AXI_13_ARESET_N] [get_bd_pins hbm_inst/AXI_14_ARESET_N] [get_bd_pins hbm_inst/AXI_15_ARESET_N] [get_bd_pins hbm_inst/AXI_16_ARESET_N] [get_bd_pins hbm_inst/AXI_17_ARESET_N] [get_bd_pins hbm_inst/AXI_18_ARESET_N] [get_bd_pins hbm_inst/AXI_19_ARESET_N] [get_bd_pins hbm_inst/AXI_20_ARESET_N] [get_bd_pins hbm_inst/AXI_21_ARESET_N] [get_bd_pins hbm_inst/AXI_22_ARESET_N] [get_bd_pins hbm_inst/AXI_23_ARESET_N] [get_bd_pins hbm_inst/AXI_24_ARESET_N] [get_bd_pins hbm_inst/AXI_25_ARESET_N] [get_bd_pins hbm_inst/AXI_26_ARESET_N] [get_bd_pins hbm_inst/AXI_27_ARESET_N] [get_bd_pins hbm_inst/AXI_28_ARESET_N] [get_bd_pins hbm_inst/AXI_29_ARESET_N] [get_bd_pins hbm_inst/AXI_30_ARESET_N] [get_bd_pins hbm_inst/AXI_31_ARESET_N] [get_bd_pins hbm_reset_sync_SLR0/interconnect_aresetn]
 connect_bd_net [get_bd_ports hbm_mc_init_seq_complete] [get_bd_pins init_logic/hbm_mc_init_seq_complete]

########################################################################################################
# Create address segments
########################################################################################################
 assign_bd_address -offset 0x00000000 -range 0x00400000 -target_address_space [get_bd_addr_spaces S_AXI_CTRL] [get_bd_addr_segs hbm_inst/SAPB_0/Reg] -force
 assign_bd_address -offset 0x00400000 -range 0x00400000 -target_address_space [get_bd_addr_spaces S_AXI_CTRL] [get_bd_addr_segs hbm_inst/SAPB_1/Reg] -force

  assign_bd_address

 # Restore current instance
 current_bd_instance $oldCurInst

 validate_bd_design
 save_bd_design
 close_bd_design $design_name 

 return 0
}