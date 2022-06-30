
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

  # Create instance: interconnect, and set properties
  set interconnect_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 interconnect_0 ]
  set_property -dict [ list \
   CONFIG.ADVANCED_PROPERTIES {__view__ {functional {S00_Entry {SUPPORTS_WRAP 0}} timing {S00_Entry {MMU_REGSLICE 1} M00_Exit {REGSLICE 1}}}} \
   CONFIG.NUM_CLKS {2} \
   CONFIG.NUM_SI {1} \
 ] $interconnect_0

  # Create instance: slice, and set properties
  set slice_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_register_slice:2.1 slice_0]
  set_property -dict [ list \
   CONFIG.REG_AR {7} \
   CONFIG.REG_AW {7} \
   CONFIG.REG_B {7} \
   CONFIG.REG_R {1} \
   CONFIG.REG_W {1} \
 ] $slice_0

  # Create interface connections
  connect_bd_intf_net [get_bd_intf_pins S_AXI] [get_bd_intf_pins interconnect_0/S00_AXI]
  connect_bd_intf_net [get_bd_intf_pins interconnect_0/M00_AXI] [get_bd_intf_pins slice_0/S_AXI]
  connect_bd_intf_net [get_bd_intf_pins slice_0/M_AXI] [get_bd_intf_pins M_AXI]

  # Create port connections
  connect_bd_net [get_bd_pins aclk] [get_bd_pins interconnect_0/aclk]
  connect_bd_net [get_bd_pins aresetn] [get_bd_pins interconnect_0/aresetn]
  connect_bd_net [get_bd_pins hclk] [get_bd_pins interconnect_0/aclk1] [get_bd_pins slice_0/aclk]
  connect_bd_net [get_bd_pins hresetn] [get_bd_pins slice_0/aresetn]

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
  if {$cnfg(en_hbm) eq 1} {
      for {set i 0}  {$i < $cnfg(n_hbm_chan)} {incr i} {   
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
               ] \$axi_hbm_in_$i"
      eval $cmd
      }
   }

  set S_AXI_CTRL [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI_CTRL ]
  set_property -dict [ list \
   CONFIG.ADDR_WIDTH {23} \
   CONFIG.PROTOCOL {AXI4LITE} \
   ] $S_AXI_CTRL

  set DRAM_0_STAT_TEMP [ create_bd_port -dir O -from 6 -to 0 DRAM_0_STAT_TEMP ]
  set DRAM_1_STAT_TEMP [ create_bd_port -dir O -from 6 -to 0 DRAM_1_STAT_TEMP ]
  set DRAM_STAT_CATTRIP [ create_bd_port -dir O -from 0 -to 0 -type intr DRAM_STAT_CATTRIP ]

  # Clocks and resets

  # System clock
  set cmd "set aclk \[ create_bd_port -dir I -type clk -freq_hz [format "%d000000" $cnfg(aclk_f)]  aclk ]
        set_property -dict \[ list \
            CONFIG.ASSOCIATED_BUSIF {" 
            for {set i 0}  {$i < 1+$cnfg(n_reg)} {incr i} {
               append cmd "axi_hbm_in_$i"
               if {$i != 1+$cnfg(n_reg) - 1} {
                  append cmd ":"
               }
            }
            append cmd "} \
            CONFIG.ASSOCIATED_RESET {aresetn} \
            CONFIG.FREQ_HZ {$cnfg(aclk_f)} \
        ] \$aclk"
  eval $cmd

  set aresetn [ create_bd_port -dir I -type rst aresetn ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_LOW} \
 ] $aresetn  

  # HBM clock
  set cmd "set hclk \[ create_bd_port -dir I -type clk -freq_hz [format "%d000000" $cnfg(hclk_f)] hclk ]
   set_property -dict \[ list \
   CONFIG.FREQ_HZ {[format "%d000000" $cnfg(hclk_f)]} \
   ] \$hclk"
  eval $cmd

  set hresetn [ create_bd_port -dir I -type rst hresetn ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_LOW} \
 ] $hresetn

  # HBM reference clock
  set hrefclk [ create_bd_port -dir I -type clk -freq_hz 100000000 hrefclk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {100000000} \
 ] $hrefclk  

 set hrefresetn [ create_bd_port -dir I -type rst hrefresetn ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_LOW} \
 ] $hrefresetn

  set hbm_mc_init_seq_complete [ create_bd_port -dir O hbm_mc_init_seq_complete ]
  
  # Components

  # Create instance: axi_apb_bridge_inst, and set properties
  set axi_apb_bridge_inst [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_apb_bridge:3.0 axi_apb_bridge_inst ]
  set_property -dict [ list \
   CONFIG.C_APB_NUM_SLAVES {2} \
   CONFIG.C_M_APB_PROTOCOL {apb3} \
 ] $axi_apb_bridge_inst

  # Create instance: hbm_inst, and set properties
  set cmd "set hbm_inst \[ create_bd_cell -type ip -vlnv xilinx.com:ip:hbm:1.0 hbm_inst ]
   set_property -dict \[ list \
     CONFIG.USER_AXI_CLK_FREQ {[expr {$cnfg(hclk_f)}]} \
     CONFIG.USER_AXI_CLK1_FREQ {[expr {$cnfg(hclk_f)}]} \
     CONFIG.USER_CLK_SEL_LIST0 {AXI_15_ACLK} \
     CONFIG.USER_CLK_SEL_LIST1 {AXI_31_ACLK} \
     CONFIG.USER_DIS_REF_CLK_BUFG {TRUE} \
     CONFIG.USER_HBM_DENSITY {[expr {($cnfg(fdev) eq "u55c") ? "16GB":"8GB"}]} \
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
     CONFIG.USER_SAXI_00 {true} \
     CONFIG.USER_SAXI_01 {true} \
     CONFIG.USER_SAXI_02 {true} \
     CONFIG.USER_SAXI_03 {true} \
     CONFIG.USER_SAXI_04 {true} \
     CONFIG.USER_SAXI_05 {true} \
     CONFIG.USER_SAXI_06 {true} \
     CONFIG.USER_SAXI_07 {true} \
     CONFIG.USER_SAXI_08 {true} \
     CONFIG.USER_SAXI_09 {true} \
     CONFIG.USER_SAXI_10 {true} \
     CONFIG.USER_SAXI_11 {true} \
     CONFIG.USER_SAXI_12 {true} \
     CONFIG.USER_SAXI_13 {true} \
     CONFIG.USER_SAXI_14 {true} \
     CONFIG.USER_SAXI_15 {true} \
     CONFIG.USER_SAXI_16 {true} \
     CONFIG.USER_SAXI_17 {true} \
     CONFIG.USER_SAXI_18 {true} \
     CONFIG.USER_SAXI_19 {true} \
     CONFIG.USER_SAXI_20 {true} \
     CONFIG.USER_SAXI_21 {true} \
     CONFIG.USER_SAXI_22 {true} \
     CONFIG.USER_SAXI_23 {true} \
     CONFIG.USER_SAXI_24 {true} \
     CONFIG.USER_SAXI_25 {true} \
     CONFIG.USER_SAXI_26 {true} \
     CONFIG.USER_SAXI_27 {true} \
     CONFIG.USER_SAXI_28 {true} \
     CONFIG.USER_SAXI_29 {true} \
     CONFIG.USER_SAXI_30 {true} \
     CONFIG.USER_SAXI_31 {true} \
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

 # set_property generate_synth_checkpoint 0 [get_files axis_data_fifo_hbm_r.xci]
 # set_property generate_synth_checkpoint 0 [get_files axis_data_fifo_hbm_w.xci]
 # set_property generate_synth_checkpoint 0 [get_files axis_data_fifo_hbm_b.xci]

########################################################################################################
# Create interconnect
########################################################################################################


 # Path
 for {set i 0}  {$i < $cnfg(n_hbm_chan)} {incr i} {  
    create_hier_cell_path [current_bd_instance .] path_$i
    connect_bd_net [get_bd_ports aclk] [get_bd_pins path_$i/aclk]
    connect_bd_net [get_bd_ports aresetn] [get_bd_pins path_$i/aresetn]
    connect_bd_net [get_bd_ports hclk] [get_bd_pins path_$i/hclk]
    connect_bd_net [get_bd_ports hresetn] [get_bd_pins path_$i/hresetn]
   if {$cnfg(fdev) eq "u55c"} {
    set cmd "[format "connect_bd_intf_net \[get_bd_intf_pins hbm_inst/SAXI_%02d_8HI] -boundary_type upper \[get_bd_intf_pins path_$i/M_AXI]" $i]"
   } else {
    set cmd "[format "connect_bd_intf_net \[get_bd_intf_pins hbm_inst/SAXI_%02d] -boundary_type upper \[get_bd_intf_pins path_$i/M_AXI]" $i]"
   }
    eval $cmd
    connect_bd_intf_net [get_bd_intf_ports axi_hbm_in_$i] -boundary_type upper [get_bd_intf_pins path_$i/S_AXI]
 }

# AXI vip to tie-off the unused ports on hbm_inst
for {set i 0}  {$i < 32 - $cnfg(n_hbm_chan)} {incr i} {  

   set vip_$i [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vip:1.1 vip_$i ]
   set_property -dict [ list \
      CONFIG.INTERFACE_MODE {MASTER} \
      CONFIG.PROTOCOL {AXI3} \
      CONFIG.ADDR_WIDTH {33} \
      CONFIG.DATA_WIDTH {256} \
      CONFIG.ID_WIDTH {6} \
   ] [get_bd_cells vip_$i]

   if {$cnfg(fdev) eq "u55c"} {
      connect_bd_intf_net [get_bd_intf_pins vip_$i/M_AXI] [get_bd_intf_pins [format "hbm_inst/SAXI_%02d_8HI" [expr $i + $cnfg(n_hbm_chan)]]]
   } else {
      connect_bd_intf_net [get_bd_intf_pins vip_$i/M_AXI] [get_bd_intf_pins [format "hbm_inst/SAXI_%02d" [expr $i + $cnfg(n_hbm_chan)]]]
   }
   connect_bd_net [get_bd_ports hclk] [get_bd_pins vip_$i/aclk]
   connect_bd_net [get_bd_ports hresetn] [get_bd_pins vip_$i/aresetn]
}

 
 # Create instance: init_logic
  create_hier_cell_init_logic [current_bd_instance .] init_logic

 # Create interface connections
 connect_bd_intf_net [get_bd_intf_ports S_AXI_CTRL] [get_bd_intf_pins axi_apb_bridge_inst/AXI4_LITE]
 connect_bd_intf_net [get_bd_intf_pins axi_apb_bridge_inst/APB_M] [get_bd_intf_pins hbm_inst/SAPB_0]
 connect_bd_intf_net [get_bd_intf_pins axi_apb_bridge_inst/APB_M2] [get_bd_intf_pins hbm_inst/SAPB_1]

 # Create port connections
 connect_bd_net [get_bd_ports DRAM_STAT_CATTRIP] [get_bd_pins hbm_reset_sync_SLR0/aux_reset_in] [get_bd_pins util_vector_logic/Res]
 connect_bd_net [get_bd_ports hrefclk] [get_bd_pins axi_apb_bridge_inst/s_axi_aclk] [get_bd_pins hbm_inst/APB_0_PCLK] [get_bd_pins hbm_inst/APB_1_PCLK]
 connect_bd_net [get_bd_ports hrefresetn] [get_bd_pins axi_apb_bridge_inst/s_axi_aresetn] [get_bd_pins hbm_inst/APB_0_PRESET_N] [get_bd_pins hbm_inst/APB_1_PRESET_N]
 
 connect_bd_net [get_bd_ports hclk] [get_bd_pins hbm_reset_sync_SLR0/slowest_sync_clk]
 for {set i 0}  {$i < 32} {incr i} {
   connect_bd_net [get_bd_ports hclk] [get_bd_pins [format "hbm_inst/AXI_%02d_ACLK" $i]]
 }


 connect_bd_net [get_bd_ports hresetn] [get_bd_pins hbm_reset_sync_SLR0/ext_reset_in]
 connect_bd_net [get_bd_pins hbm_inst/DRAM_0_STAT_CATTRIP] [get_bd_pins util_vector_logic/Op1]
 connect_bd_net [get_bd_ports DRAM_0_STAT_TEMP] [get_bd_pins hbm_inst/DRAM_0_STAT_TEMP]
 connect_bd_net [get_bd_pins hbm_inst/DRAM_1_STAT_CATTRIP] [get_bd_pins util_vector_logic/Op2]
 connect_bd_net [get_bd_ports DRAM_1_STAT_TEMP] [get_bd_pins hbm_inst/DRAM_1_STAT_TEMP]
 connect_bd_net [get_bd_pins hbm_inst/apb_complete_0] [get_bd_pins init_logic/In0]
 connect_bd_net [get_bd_pins hbm_inst/apb_complete_1] [get_bd_pins init_logic/In1]
 connect_bd_net [get_bd_ports hrefclk] [get_bd_pins hbm_inst/HBM_REF_CLK_0] [get_bd_pins hbm_inst/HBM_REF_CLK_1]
 

 for {set i 0}  {$i < 32} {incr i} {
  connect_bd_net [get_bd_pins hbm_reset_sync_SLR0/interconnect_aresetn] [get_bd_pins [format "hbm_inst/AXI_%02d_ARESET_N" $i]]
 }

 connect_bd_net [get_bd_ports hbm_mc_init_seq_complete] [get_bd_pins init_logic/hbm_mc_init_seq_complete]

#########################################################################################################
## Create address segments
#########################################################################################################
 assign_bd_address -offset 0x00000000 -range 0x00400000 -target_address_space [get_bd_addr_spaces S_AXI_CTRL] [get_bd_addr_segs hbm_inst/SAPB_0/Reg] -force
 assign_bd_address -offset 0x00400000 -range 0x00400000 -target_address_space [get_bd_addr_spaces S_AXI_CTRL] [get_bd_addr_segs hbm_inst/SAPB_1/Reg] -force

# for {set j 0}  {$j < 32} {incr j} {   
#    for {set i 0}  {$i < $cnfg(n_hbm_chan)} {incr i} {   
#       set cmd "[format "assign_bd_address -offset 0x%x -range 0x10000000 -target_address_space [get_bd_addr_spaces axi_hbm_in_%d] [get_bd_addr_segs hbm_inst/SAXI_%02d/HBM_MEM%02d] -force" [expr (1 << 28) * $j] $i $i $j]"
#       eval $cmd
#    }
# }

 assign_bd_address

 # Restore current instance
 current_bd_instance $oldCurInst

 save_bd_design
 close_bd_design $design_name 

 return 0
}