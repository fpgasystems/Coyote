######################################################################################
# This file is part of Coyote <https://github.com/fpgasystems/Coyote>
# 
# MIT Licence
# Copyright (c) 2026, Systems Group, ETH Zurich
# All rights reserved.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
######################################################################################

################################################################
# CHECK VIVADO VERSION CHECK
################################################################
# This BD only suppors DCMAC v3.0 which with the new GT IP; only supported in Vivado 2025.1
set scripts_vivado_version 2025.1
set current_vivado_version [version -short]

if { [string compare $current_vivado_version $scripts_vivado_version] < 0 } {
    catch {common::send_gid_msg -ssname BD::TCL -id 2042 -severity "ERROR" \
        "This script requires Vivado $scripts_vivado_version or newer \
        but is being run in Vivado $current_vivado_version."}
    return 1
}

##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
set bCheckIPsPassed 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
xilinx.com:ip:gtwiz_versal:1.0\
xilinx.com:ip:util_ds_buf:2.2\
xilinx.com:ip:xlconstant:1.1\
xilinx.com:ip:dcmac:3.0\
xilinx.com:ip:axis_data_fifo:2.0\
xilinx.com:ip:axis_dwidth_converter:1.1\
xilinx.com:ip:bufg_gt:1.0\
xilinx.com:ip:clk_wizard:1.0\
xilinx.com:ip:proc_sys_reset:5.0\
xilinx.com:ip:xpm_cdc_gen:1.0\
"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

    foreach ip_vlnv $list_check_ips {
        set ip_obj [get_ipdefs -all $ip_vlnv]
        if { $ip_obj eq "" } {
            lappend list_ips_missing $ip_vlnv
        }
    }

    if { $list_ips_missing ne "" } {
        catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
        set bCheckIPsPassed 0
    }
}

##################################################################
# CHECK Modules
##################################################################
set bCheckModules 1
if { $bCheckModules == 1 } {
   set list_check_mods "\ 
dcmac200g_ctl_port\
axis_seg_to_unseg_converter\
axis_unseg_to_seg_converter\
clk_to_flexif_clk\
clk_to_alt_serdes_clk\
clk_to_serdes_clk\
clk_to_ts_clk\
dcmac_reset_ctrl_wrapper\
"

    set list_mods_missing ""
    common::send_gid_msg -ssname BD::TCL -id 2020 -severity "INFO" "Checking if the following modules exist in the project's sources: $list_check_mods ."

    foreach mod_vlnv $list_check_mods {
        if { [can_resolve_reference $mod_vlnv] == 0 } {
            lappend list_mods_missing $mod_vlnv
        }
    }

    if { $list_mods_missing ne "" } {
        catch {common::send_gid_msg -ssname BD::TCL -id 2021 -severity "ERROR" "The following module(s) are not found in the project: $list_mods_missing" }
        common::send_gid_msg -ssname BD::TCL -id 2022 -severity "INFO" "Please add source files for the missing module(s) above."
        set bCheckIPsPassed 0
    }
}

if { $bCheckIPsPassed != 1 } {
   common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
   return 3
}

##################################################################
# DESIGN PROCs
##################################################################

# Hierarchical cell: bd_clock_reset_ctrl
proc create_hier_cell_bd_clock_reset_ctrl { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_bd_clock_reset_ctrl() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
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
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 gt_clk


  # Create pins
  create_bd_pin -dir O -from 0 -to 0 -type clk gt_ref_clk
  create_bd_pin -dir O -type clk dcmac_core_clk
  create_bd_pin -dir O -type clk dcmac_axis_clk
  create_bd_pin -dir O -type rst gt_reset
  create_bd_pin -dir I gt_reset_done_rx
  create_bd_pin -dir I gt_reset_done_tx
  create_bd_pin -dir O -type rst tx_core_reset
  create_bd_pin -dir O -from 5 -to 0 tx_chan_flush
  create_bd_pin -dir O -from 5 -to 0 -type rst tx_serdes_reset
  create_bd_pin -dir O -from 5 -to 0 rx_chan_flush
  create_bd_pin -dir O -type rst rx_core_reset
  create_bd_pin -dir O -from 5 -to 0 -type rst rx_serdes_reset
  create_bd_pin -dir I -type rst aresetn
  create_bd_pin -dir O -type rst axis_resetn
  create_bd_pin -dir O -type clk sys_clk

  # Create instance: diff_buff, and set properties
  set diff_buff [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 diff_buff ]
  set_property CONFIG.C_BUF_TYPE {IBUFDS_GTME5} $diff_buff


  # Create instance: bufgt_dcmac, and set properties
  set bufgt_dcmac [ create_bd_cell -type ip -vlnv xilinx.com:ip:bufg_gt:1.0 bufgt_dcmac ]

  # Create instance: const_1, and set properties
  set const_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_1 ]
  set_property CONFIG.CONST_VAL {1} $const_1


  # Create instance: clk_wizard_dcmac, and set properties
  set clk_wizard_dcmac [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wizard:1.0 clk_wizard_dcmac ]
  set_property -dict [list \
    CONFIG.CLKOUT_DRIVES {BUFG,BUFG,BUFG,BUFG,BUFG,BUFG,BUFG} \
    CONFIG.CLKOUT_DYN_PS {None,None,None,None,None,None,None} \
    CONFIG.CLKOUT_GROUPING {Auto,Auto,Auto,Auto,Auto,Auto,Auto} \
    CONFIG.CLKOUT_MATCHED_ROUTING {false,false,false,false,false,false,false} \
    CONFIG.CLKOUT_PORT {clk_out1,clk_out2,clk_out3,clk_out4,clk_out5,clk_out6,clk_out7} \
    CONFIG.CLKOUT_REQUESTED_DUTY_CYCLE {50.000,50.000,50.000,50.000,50.000,50.000,50.000} \
    CONFIG.CLKOUT_REQUESTED_OUT_FREQUENCY {782,390.625,100,100.000,100.000,100.000,100.000} \
    CONFIG.CLKOUT_REQUESTED_PHASE {0.000,0.000,0.000,0.000,0.000,0.000,0.000} \
    CONFIG.CLKOUT_USED {true,true,true,false,false,false,false} \
    CONFIG.OVERRIDE_PRIMITIVE {false} \
    CONFIG.PRIM_IN_FREQ {322.265625} \
    CONFIG.PRIM_SOURCE {Global_buffer} \
    CONFIG.USE_LOCKED {false} \
  ] $clk_wizard_dcmac


  # Create instance: dcmac_reset_ctrl, and set properties
  set block_name dcmac_reset_ctrl_wrapper
  set block_cell_name dcmac_reset_ctrl
  if { [catch {set dcmac_reset_ctrl [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $dcmac_reset_ctrl eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins diff_buff/CLK_IN_D1] [get_bd_intf_pins gt_clk]

  # Create port connections
  connect_bd_net -net aresetn_1  [get_bd_pins aresetn] \
  [get_bd_pins dcmac_reset_ctrl/async_resetn]
  connect_bd_net -net bufgt_dcmac_usrclk  [get_bd_pins bufgt_dcmac/usrclk] \
  [get_bd_pins clk_wizard_dcmac/clk_in1]
  connect_bd_net -net clk_wizard_dcmac_clk_out1  [get_bd_pins clk_wizard_dcmac/clk_out1] \
  [get_bd_pins dcmac_core_clk]
  connect_bd_net -net clk_wizard_dcmac_clk_out2  [get_bd_pins clk_wizard_dcmac/clk_out2] \
  [get_bd_pins dcmac_axis_clk] \
  [get_bd_pins dcmac_reset_ctrl/dcmac_clk]
  connect_bd_net -net clk_wizard_dcmac_clk_out3  [get_bd_pins clk_wizard_dcmac/clk_out3] \
  [get_bd_pins sys_clk] \
  [get_bd_pins dcmac_reset_ctrl/sys_clk]
  connect_bd_net -net const_1_dout  [get_bd_pins const_1/dout] \
  [get_bd_pins bufgt_dcmac/gt_bufgtce]
  connect_bd_net -net dcmac_reset_ctrl_axis_resetn  [get_bd_pins dcmac_reset_ctrl/axis_resetn] \
  [get_bd_pins axis_resetn]
  connect_bd_net -net dcmac_reset_ctrl_gt_reset  [get_bd_pins dcmac_reset_ctrl/gt_reset] \
  [get_bd_pins gt_reset]
  connect_bd_net -net dcmac_reset_ctrl_rx_chan_flush  [get_bd_pins dcmac_reset_ctrl/rx_chan_flush] \
  [get_bd_pins rx_chan_flush]
  connect_bd_net -net dcmac_reset_ctrl_rx_core_reset  [get_bd_pins dcmac_reset_ctrl/rx_core_reset] \
  [get_bd_pins rx_core_reset]
  connect_bd_net -net dcmac_reset_ctrl_rx_serdes_reset  [get_bd_pins dcmac_reset_ctrl/rx_serdes_reset] \
  [get_bd_pins rx_serdes_reset]
  connect_bd_net -net dcmac_reset_ctrl_tx_chan_flush  [get_bd_pins dcmac_reset_ctrl/tx_chan_flush] \
  [get_bd_pins tx_chan_flush]
  connect_bd_net -net dcmac_reset_ctrl_tx_core_reset  [get_bd_pins dcmac_reset_ctrl/tx_core_reset] \
  [get_bd_pins tx_core_reset]
  connect_bd_net -net dcmac_reset_ctrl_tx_serdes_reset  [get_bd_pins dcmac_reset_ctrl/tx_serdes_reset] \
  [get_bd_pins tx_serdes_reset]
  connect_bd_net -net diff_buff_IBUFDS_GTME5_O  [get_bd_pins diff_buff/IBUFDS_GTME5_O] \
  [get_bd_pins gt_ref_clk]
  connect_bd_net -net diff_buff_IBUFDS_GTME5_ODIV2  [get_bd_pins diff_buff/IBUFDS_GTME5_ODIV2] \
  [get_bd_pins bufgt_dcmac/outclk]
  connect_bd_net -net gt_reset_done_rx_1  [get_bd_pins gt_reset_done_rx] \
  [get_bd_pins dcmac_reset_ctrl/gt_reset_done_rx]
  connect_bd_net -net gt_reset_done_tx_1  [get_bd_pins gt_reset_done_tx] \
  [get_bd_pins dcmac_reset_ctrl/gt_reset_done_tx]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: datapath_rx
proc create_hier_cell_datapath_rx { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_datapath_rx() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
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
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 m_axis_rx

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 s_axis_rx


  # Create pins
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type clk dclk
  create_bd_pin -dir I -type rst dresetn

  # Create instance: rx_dwc_1024_to_512, and set properties
  set rx_dwc_1024_to_512 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 rx_dwc_1024_to_512 ]
  set_property -dict [list \
    CONFIG.HAS_TKEEP {1} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.HAS_TSTRB {0} \
    CONFIG.M_TDATA_NUM_BYTES {64} \
    CONFIG.S_TDATA_NUM_BYTES {128} \
    CONFIG.TUSER_BITS_PER_BYTE {1} \
  ] $rx_dwc_1024_to_512


  # Create instance: rx_cdc_fifo, and set properties
  set rx_cdc_fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 rx_cdc_fifo ]
  set_property -dict [list \
    CONFIG.FIFO_DEPTH {1024} \
    CONFIG.FIFO_MODE {1} \
    CONFIG.HAS_TKEEP {1} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.TDATA_NUM_BYTES {64} \
  ] $rx_cdc_fifo


  # Create instance: rx_reg_slice, and set properties
  set rx_reg_slice [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_register_slice:1.1 rx_reg_slice ]
  set_property CONFIG.REG_CONFIG {16} $rx_reg_slice


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins rx_cdc_fifo/M_AXIS] [get_bd_intf_pins m_axis_rx]
  connect_bd_intf_net -intf_net S_AXIS_1 [get_bd_intf_pins s_axis_rx] [get_bd_intf_pins rx_dwc_1024_to_512/S_AXIS]
  connect_bd_intf_net -intf_net rx_dwc_1024_to_512_M_AXIS [get_bd_intf_pins rx_dwc_1024_to_512/M_AXIS] [get_bd_intf_pins rx_reg_slice/S_AXIS]
  connect_bd_intf_net -intf_net rx_reg_slice_M_AXIS [get_bd_intf_pins rx_reg_slice/M_AXIS] [get_bd_intf_pins rx_cdc_fifo/S_AXIS]

  # Create port connections
  connect_bd_net -net aclk1_1  [get_bd_pins dclk] \
  [get_bd_pins rx_dwc_1024_to_512/aclk] \
  [get_bd_pins rx_cdc_fifo/s_axis_aclk] \
  [get_bd_pins rx_reg_slice/aclk]
  connect_bd_net -net aclk_1  [get_bd_pins aclk] \
  [get_bd_pins rx_cdc_fifo/m_axis_aclk]
  connect_bd_net -net aresetn_1  [get_bd_pins dresetn] \
  [get_bd_pins rx_dwc_1024_to_512/aresetn] \
  [get_bd_pins rx_cdc_fifo/s_axis_aresetn] \
  [get_bd_pins rx_reg_slice/aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: datapath_tx
proc create_hier_cell_datapath_tx { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_datapath_tx() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
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
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 s_axis_tx

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 m_axis_tx


  # Create pins
  create_bd_pin -dir I -type rst aresetn
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type clk dclk
  create_bd_pin -dir I -type rst dresetn

  # Create instance: tx_cdc_fifo, and set properties
  set tx_cdc_fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 tx_cdc_fifo ]
  set_property -dict [list \
    CONFIG.FIFO_DEPTH {128} \
    CONFIG.FIFO_MODE {2} \
    CONFIG.HAS_TKEEP {1} \
    CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.TDATA_NUM_BYTES {64} \
  ] $tx_cdc_fifo


  # Create instance: tx_reg_slice, and set properties
  set tx_reg_slice [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_register_slice:1.1 tx_reg_slice ]
  set_property CONFIG.REG_CONFIG {16} $tx_reg_slice


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins tx_cdc_fifo/S_AXIS] [get_bd_intf_pins s_axis_tx]
  connect_bd_intf_net -intf_net axis_register_slice_0_M_AXIS [get_bd_intf_pins m_axis_tx] [get_bd_intf_pins tx_reg_slice/M_AXIS]
  connect_bd_intf_net -intf_net tx_cdc_fifo_M_AXIS [get_bd_intf_pins tx_cdc_fifo/M_AXIS] [get_bd_intf_pins tx_reg_slice/S_AXIS]

  # Create port connections
  connect_bd_net -net aclk_1  [get_bd_pins aclk] \
  [get_bd_pins tx_cdc_fifo/s_axis_aclk]
  connect_bd_net -net aresetn1_1  [get_bd_pins dresetn] \
  [get_bd_pins tx_reg_slice/aresetn]
  connect_bd_net -net aresetn_1  [get_bd_pins aresetn] \
  [get_bd_pins tx_cdc_fifo/s_axis_aresetn]
  connect_bd_net -net m_axis_aclk_1  [get_bd_pins dclk] \
  [get_bd_pins tx_cdc_fifo/m_axis_aclk] \
  [get_bd_pins tx_reg_slice/aclk]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: dcmac_wrapper
proc create_hier_cell_dcmac_wrapper { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_dcmac_wrapper() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
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
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 m_axis_rx

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 s_axis_tx


  # Create pins
  create_bd_pin -dir O -from 255 -to 0 tx_data_0
  create_bd_pin -dir O -from 255 -to 0 tx_data_1
  create_bd_pin -dir O -from 255 -to 0 tx_data_2
  create_bd_pin -dir O -from 255 -to 0 tx_data_3
  create_bd_pin -dir I -from 255 -to 0 rx_data_0
  create_bd_pin -dir I -from 255 -to 0 rx_data_1
  create_bd_pin -dir I -from 255 -to 0 rx_data_2
  create_bd_pin -dir I -from 255 -to 0 rx_data_3
  create_bd_pin -dir I tx_clk
  create_bd_pin -dir I -type gt_usrclk tx_clk_alt
  create_bd_pin -dir I -type gt_usrclk rx_clk
  create_bd_pin -dir I rx_clk_alt
  create_bd_pin -dir I -type clk core_clk
  create_bd_pin -dir I -type clk axis_clk
  create_bd_pin -dir I -type rst axis_tx_resetn
  create_bd_pin -dir I -type rst axis_rx_resetn
  create_bd_pin -dir I -type rst tx_core_reset
  create_bd_pin -dir I -from 5 -to 0 tx_channel_flush
  create_bd_pin -dir I -from 5 -to 0 -type rst tx_serdes_reset
  create_bd_pin -dir I -type rst rx_core_reset
  create_bd_pin -dir I -from 5 -to 0 -type rst rx_serdes_reset
  create_bd_pin -dir I -from 5 -to 0 rx_channel_flush
  create_bd_pin -dir I -type clk ts_axil_clk

  # Create instance: dcmac, and set properties
  set dcmac [ create_bd_cell -type ip -vlnv xilinx.com:ip:dcmac:3.0 dcmac ]
  set_property -dict [list \
    CONFIG.DCMAC_LOCATION_C0 {DCMAC_X1Y1} \
    CONFIG.GT_REF_CLK_FREQ_C0 {322.265625} \
    CONFIG.IS_GT_WIZ_OLD {0} \
    CONFIG.MAC_PORT0_CONFIG_C0 {200GAUI-4} \
    CONFIG.MAC_PORT0_RX_STRIP_C0 {1} \
    CONFIG.MAC_PORT1_RX_STRIP_C0 {1} \
    CONFIG.MAC_PORT2_ENABLE_C0 {0} \
    CONFIG.MAC_PORT3_ENABLE_C0 {0} \
    CONFIG.MAC_PORT4_ENABLE_C0 {0} \
    CONFIG.MAC_PORT5_ENABLE_C0 {0} \
    CONFIG.USE_AXIS_ALMOSTFULL_INDICATION {0} \
  ] $dcmac


  # Create instance: dcmac200g_ctl_port, and set properties
  set block_name dcmac200g_ctl_port
  set block_cell_name dcmac200g_ctl_port
  if { [catch {set dcmac200g_ctl_port [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $dcmac200g_ctl_port eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: seg_to_axis, and set properties
  set block_name axis_seg_to_unseg_converter
  set block_cell_name seg_to_axis
  if { [catch {set seg_to_axis [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $seg_to_axis eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  set_property -dict [ list \
   CONFIG.FREQ_HZ {390998840} \
 ] [get_bd_intf_pins /dcmac_wrapper/seg_to_axis/m_axis0_pkt_out]

  # Create instance: const_0, and set properties
  set const_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_0 ]
  set_property CONFIG.CONST_VAL {0} $const_0


  # Create instance: flexif_clk_tx, and set properties
  set block_name clk_to_flexif_clk
  set block_cell_name flexif_clk_tx
  if { [catch {set flexif_clk_tx [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $flexif_clk_tx eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: alt_serdes_clk_tx, and set properties
  set block_name clk_to_alt_serdes_clk
  set block_cell_name alt_serdes_clk_tx
  if { [catch {set alt_serdes_clk_tx [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $alt_serdes_clk_tx eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: serdes_clk_tx, and set properties
  set block_name clk_to_serdes_clk
  set block_cell_name serdes_clk_tx
  if { [catch {set serdes_clk_tx [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $serdes_clk_tx eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: flexif_clk_rx, and set properties
  set block_name clk_to_flexif_clk
  set block_cell_name flexif_clk_rx
  if { [catch {set flexif_clk_rx [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $flexif_clk_rx eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: alt_serdes_clk_rx, and set properties
  set block_name clk_to_alt_serdes_clk
  set block_cell_name alt_serdes_clk_rx
  if { [catch {set alt_serdes_clk_rx [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $alt_serdes_clk_rx eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: ts_clk, and set properties
  set block_name clk_to_ts_clk
  set block_cell_name ts_clk
  if { [catch {set ts_clk [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $ts_clk eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: serdes_clk_rx, and set properties
  set block_name clk_to_serdes_clk
  set block_cell_name serdes_clk_rx
  if { [catch {set serdes_clk_rx [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $serdes_clk_rx eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: axis_to_seg, and set properties
  set block_name axis_to_dcmac_seg_wrapper
  set block_cell_name axis_to_seg
  if { [catch {set axis_to_seg [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $axis_to_seg eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: const_1, and set properties
  set const_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_1 ]

  # Create interface connections
  connect_bd_intf_net -intf_net s_axis_tx_1 [get_bd_intf_pins s_axis_tx] [get_bd_intf_pins axis_to_seg/s_axis]
  connect_bd_intf_net -intf_net seg_to_axis_m_axis0_pkt_out [get_bd_intf_pins m_axis_rx] [get_bd_intf_pins seg_to_axis/m_axis0_pkt_out]

  # Create port connections
  connect_bd_net -net alt_serdes_clk_rx_serdes_clk  [get_bd_pins alt_serdes_clk_rx/serdes_clk] \
  [get_bd_pins dcmac/rx_alt_serdes_clk]
  connect_bd_net -net alt_serdes_clk_tx_serdes_clk  [get_bd_pins alt_serdes_clk_tx/serdes_clk] \
  [get_bd_pins dcmac/tx_alt_serdes_clk]
  connect_bd_net -net aresetn_axis_seg_in_2  [get_bd_pins axis_rx_resetn] \
  [get_bd_pins seg_to_axis/aresetn_axis_seg_in]
  connect_bd_net -net axis_to_dcmac_seg_tx_data_0  [get_bd_pins axis_to_seg/tx_data_0] \
  [get_bd_pins dcmac/tx_axis_tdata0]
  connect_bd_net -net axis_to_dcmac_seg_tx_data_1  [get_bd_pins axis_to_seg/tx_data_1] \
  [get_bd_pins dcmac/tx_axis_tdata1]
  connect_bd_net -net axis_to_dcmac_seg_tx_data_2  [get_bd_pins axis_to_seg/tx_data_2] \
  [get_bd_pins dcmac/tx_axis_tdata2]
  connect_bd_net -net axis_to_dcmac_seg_tx_data_3  [get_bd_pins axis_to_seg/tx_data_3] \
  [get_bd_pins dcmac/tx_axis_tdata3]
  connect_bd_net -net axis_to_dcmac_seg_tx_ena_0  [get_bd_pins axis_to_seg/tx_ena_0] \
  [get_bd_pins dcmac/tx_axis_tuser_ena0]
  connect_bd_net -net axis_to_dcmac_seg_tx_ena_1  [get_bd_pins axis_to_seg/tx_ena_1] \
  [get_bd_pins dcmac/tx_axis_tuser_ena1]
  connect_bd_net -net axis_to_dcmac_seg_tx_ena_2  [get_bd_pins axis_to_seg/tx_ena_2] \
  [get_bd_pins dcmac/tx_axis_tuser_ena2]
  connect_bd_net -net axis_to_dcmac_seg_tx_ena_3  [get_bd_pins axis_to_seg/tx_ena_3] \
  [get_bd_pins dcmac/tx_axis_tuser_ena3]
  connect_bd_net -net axis_to_dcmac_seg_tx_eop_0  [get_bd_pins axis_to_seg/tx_eop_0] \
  [get_bd_pins dcmac/tx_axis_tuser_eop0]
  connect_bd_net -net axis_to_dcmac_seg_tx_eop_1  [get_bd_pins axis_to_seg/tx_eop_1] \
  [get_bd_pins dcmac/tx_axis_tuser_eop1]
  connect_bd_net -net axis_to_dcmac_seg_tx_eop_2  [get_bd_pins axis_to_seg/tx_eop_2] \
  [get_bd_pins dcmac/tx_axis_tuser_eop2]
  connect_bd_net -net axis_to_dcmac_seg_tx_eop_3  [get_bd_pins axis_to_seg/tx_eop_3] \
  [get_bd_pins dcmac/tx_axis_tuser_eop3]
  connect_bd_net -net axis_to_dcmac_seg_tx_err_0  [get_bd_pins axis_to_seg/tx_err_0] \
  [get_bd_pins dcmac/tx_axis_tuser_err0]
  connect_bd_net -net axis_to_dcmac_seg_tx_err_1  [get_bd_pins axis_to_seg/tx_err_1] \
  [get_bd_pins dcmac/tx_axis_tuser_err1]
  connect_bd_net -net axis_to_dcmac_seg_tx_err_2  [get_bd_pins axis_to_seg/tx_err_2] \
  [get_bd_pins dcmac/tx_axis_tuser_err2]
  connect_bd_net -net axis_to_dcmac_seg_tx_err_3  [get_bd_pins axis_to_seg/tx_err_3] \
  [get_bd_pins dcmac/tx_axis_tuser_err3]
  connect_bd_net -net axis_to_dcmac_seg_tx_mty_0  [get_bd_pins axis_to_seg/tx_mty_0] \
  [get_bd_pins dcmac/tx_axis_tuser_mty0]
  connect_bd_net -net axis_to_dcmac_seg_tx_mty_1  [get_bd_pins axis_to_seg/tx_mty_1] \
  [get_bd_pins dcmac/tx_axis_tuser_mty1]
  connect_bd_net -net axis_to_dcmac_seg_tx_mty_2  [get_bd_pins axis_to_seg/tx_mty_2] \
  [get_bd_pins dcmac/tx_axis_tuser_mty2]
  connect_bd_net -net axis_to_dcmac_seg_tx_mty_3  [get_bd_pins axis_to_seg/tx_mty_3] \
  [get_bd_pins dcmac/tx_axis_tuser_mty3]
  connect_bd_net -net axis_to_dcmac_seg_tx_sop_0  [get_bd_pins axis_to_seg/tx_sop_0] \
  [get_bd_pins dcmac/tx_axis_tuser_sop0]
  connect_bd_net -net axis_to_dcmac_seg_tx_sop_1  [get_bd_pins axis_to_seg/tx_sop_1] \
  [get_bd_pins dcmac/tx_axis_tuser_sop1]
  connect_bd_net -net axis_to_dcmac_seg_tx_sop_2  [get_bd_pins axis_to_seg/tx_sop_2] \
  [get_bd_pins dcmac/tx_axis_tuser_sop2]
  connect_bd_net -net axis_to_dcmac_seg_tx_sop_3  [get_bd_pins axis_to_seg/tx_sop_3] \
  [get_bd_pins dcmac/tx_axis_tuser_sop3]
  connect_bd_net -net axis_to_dcmac_seg_tx_valid  [get_bd_pins axis_to_seg/tx_valid] \
  [get_bd_pins dcmac/tx_axis_tvalid_0]
  connect_bd_net -net axis_tx_resetn_1  [get_bd_pins axis_tx_resetn] \
  [get_bd_pins axis_to_seg/aresetn]
  connect_bd_net -net const_0_dout  [get_bd_pins const_0/dout] \
  [get_bd_pins dcmac/rx_all_channel_mac_pm_tick] \
  [get_bd_pins dcmac/rx_port_pm_tick] \
  [get_bd_pins dcmac/tx_all_channel_mac_pm_tick] \
  [get_bd_pins dcmac/tx_port_pm_tick] \
  [get_bd_pins dcmac/s_axi_arvalid] \
  [get_bd_pins dcmac/s_axi_awvalid] \
  [get_bd_pins dcmac/s_axi_wvalid]
  connect_bd_net -net const_1_dout  [get_bd_pins const_1/dout] \
  [get_bd_pins dcmac/s_axi_bready] \
  [get_bd_pins dcmac/s_axi_rready] \
  [get_bd_pins dcmac/s_axi_aresetn]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id0  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id0] \
  [get_bd_pins dcmac/ctl_vl_marker_id0]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id1  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id1] \
  [get_bd_pins dcmac/ctl_vl_marker_id1]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id2  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id2] \
  [get_bd_pins dcmac/ctl_vl_marker_id2]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id3  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id3] \
  [get_bd_pins dcmac/ctl_vl_marker_id3]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id4  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id4] \
  [get_bd_pins dcmac/ctl_vl_marker_id4]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id5  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id5] \
  [get_bd_pins dcmac/ctl_vl_marker_id5]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id6  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id6] \
  [get_bd_pins dcmac/ctl_vl_marker_id6]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id7  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id7] \
  [get_bd_pins dcmac/ctl_vl_marker_id7]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id8  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id8] \
  [get_bd_pins dcmac/ctl_vl_marker_id8]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id9  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id9] \
  [get_bd_pins dcmac/ctl_vl_marker_id9]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id10  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id10] \
  [get_bd_pins dcmac/ctl_vl_marker_id10]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id11  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id11] \
  [get_bd_pins dcmac/ctl_vl_marker_id11]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id12  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id12] \
  [get_bd_pins dcmac/ctl_vl_marker_id12]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id13  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id13] \
  [get_bd_pins dcmac/ctl_vl_marker_id13]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id14  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id14] \
  [get_bd_pins dcmac/ctl_vl_marker_id14]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id15  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id15] \
  [get_bd_pins dcmac/ctl_vl_marker_id15]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id16  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id16] \
  [get_bd_pins dcmac/ctl_vl_marker_id16]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id17  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id17] \
  [get_bd_pins dcmac/ctl_vl_marker_id17]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id18  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id18] \
  [get_bd_pins dcmac/ctl_vl_marker_id18]
  connect_bd_net -net dcmac200g_ctl_port_ctl_tx_vl_marker_id19  [get_bd_pins dcmac200g_ctl_port/ctl_tx_vl_marker_id19] \
  [get_bd_pins dcmac/ctl_vl_marker_id19]
  connect_bd_net -net dcmac200g_ctl_port_default_vl_length_200GE_or_400GE  [get_bd_pins dcmac200g_ctl_port/default_vl_length_200GE_or_400GE] \
  [get_bd_pins dcmac/ctl_rx_custom_vl_length_minus1] \
  [get_bd_pins dcmac/ctl_tx_custom_vl_length_minus1]
  connect_bd_net -net dcmac_rx_axis_tdata0  [get_bd_pins dcmac/rx_axis_tdata0] \
  [get_bd_pins seg_to_axis/Seg2UnSegDat0_in]
  connect_bd_net -net dcmac_rx_axis_tdata1  [get_bd_pins dcmac/rx_axis_tdata1] \
  [get_bd_pins seg_to_axis/Seg2UnSegDat1_in]
  connect_bd_net -net dcmac_rx_axis_tdata2  [get_bd_pins dcmac/rx_axis_tdata2] \
  [get_bd_pins seg_to_axis/Seg2UnSegDat2_in]
  connect_bd_net -net dcmac_rx_axis_tdata3  [get_bd_pins dcmac/rx_axis_tdata3] \
  [get_bd_pins seg_to_axis/Seg2UnSegDat3_in]
  connect_bd_net -net dcmac_rx_axis_tuser_ena0  [get_bd_pins dcmac/rx_axis_tuser_ena0] \
  [get_bd_pins seg_to_axis/Seg2UnSegEna0_in]
  connect_bd_net -net dcmac_rx_axis_tuser_ena1  [get_bd_pins dcmac/rx_axis_tuser_ena1] \
  [get_bd_pins seg_to_axis/Seg2UnSegEna1_in]
  connect_bd_net -net dcmac_rx_axis_tuser_ena2  [get_bd_pins dcmac/rx_axis_tuser_ena2] \
  [get_bd_pins seg_to_axis/Seg2UnSegEna2_in]
  connect_bd_net -net dcmac_rx_axis_tuser_ena3  [get_bd_pins dcmac/rx_axis_tuser_ena3] \
  [get_bd_pins seg_to_axis/Seg2UnSegEna3_in]
  connect_bd_net -net dcmac_rx_axis_tuser_eop0  [get_bd_pins dcmac/rx_axis_tuser_eop0] \
  [get_bd_pins seg_to_axis/Seg2UnSegEop0_in]
  connect_bd_net -net dcmac_rx_axis_tuser_eop1  [get_bd_pins dcmac/rx_axis_tuser_eop1] \
  [get_bd_pins seg_to_axis/Seg2UnSegEop1_in]
  connect_bd_net -net dcmac_rx_axis_tuser_eop2  [get_bd_pins dcmac/rx_axis_tuser_eop2] \
  [get_bd_pins seg_to_axis/Seg2UnSegEop2_in]
  connect_bd_net -net dcmac_rx_axis_tuser_eop3  [get_bd_pins dcmac/rx_axis_tuser_eop3] \
  [get_bd_pins seg_to_axis/Seg2UnSegEop3_in]
  connect_bd_net -net dcmac_rx_axis_tuser_err0  [get_bd_pins dcmac/rx_axis_tuser_err0] \
  [get_bd_pins seg_to_axis/Seg2UnSegErr0_in]
  connect_bd_net -net dcmac_rx_axis_tuser_err1  [get_bd_pins dcmac/rx_axis_tuser_err1] \
  [get_bd_pins seg_to_axis/Seg2UnSegErr1_in]
  connect_bd_net -net dcmac_rx_axis_tuser_err2  [get_bd_pins dcmac/rx_axis_tuser_err2] \
  [get_bd_pins seg_to_axis/Seg2UnSegErr2_in]
  connect_bd_net -net dcmac_rx_axis_tuser_err3  [get_bd_pins dcmac/rx_axis_tuser_err3] \
  [get_bd_pins seg_to_axis/Seg2UnSegErr3_in]
  connect_bd_net -net dcmac_rx_axis_tuser_mty0  [get_bd_pins dcmac/rx_axis_tuser_mty0] \
  [get_bd_pins seg_to_axis/Seg2UnSegMty0_in]
  connect_bd_net -net dcmac_rx_axis_tuser_mty1  [get_bd_pins dcmac/rx_axis_tuser_mty1] \
  [get_bd_pins seg_to_axis/Seg2UnSegMty1_in]
  connect_bd_net -net dcmac_rx_axis_tuser_mty2  [get_bd_pins dcmac/rx_axis_tuser_mty2] \
  [get_bd_pins seg_to_axis/Seg2UnSegMty2_in]
  connect_bd_net -net dcmac_rx_axis_tuser_mty3  [get_bd_pins dcmac/rx_axis_tuser_mty3] \
  [get_bd_pins seg_to_axis/Seg2UnSegMty3_in]
  connect_bd_net -net dcmac_rx_axis_tuser_sop0  [get_bd_pins dcmac/rx_axis_tuser_sop0] \
  [get_bd_pins seg_to_axis/Seg2UnSegSop0_in]
  connect_bd_net -net dcmac_rx_axis_tuser_sop1  [get_bd_pins dcmac/rx_axis_tuser_sop1] \
  [get_bd_pins seg_to_axis/Seg2UnSegSop1_in]
  connect_bd_net -net dcmac_rx_axis_tuser_sop2  [get_bd_pins dcmac/rx_axis_tuser_sop2] \
  [get_bd_pins seg_to_axis/Seg2UnSegSop2_in]
  connect_bd_net -net dcmac_rx_axis_tuser_sop3  [get_bd_pins dcmac/rx_axis_tuser_sop3] \
  [get_bd_pins seg_to_axis/Seg2UnSegSop3_in]
  connect_bd_net -net dcmac_rx_axis_tvalid_0  [get_bd_pins dcmac/rx_axis_tvalid_0] \
  [get_bd_pins seg_to_axis/rx_axis_tvalid_i]
  connect_bd_net -net dcmac_tx_axis_tready_0  [get_bd_pins dcmac/tx_axis_tready_0] \
  [get_bd_pins axis_to_seg/tx_ready]
  connect_bd_net -net dcmac_txdata_out_0  [get_bd_pins dcmac/txdata_out_0] \
  [get_bd_pins tx_data_0]
  connect_bd_net -net dcmac_txdata_out_1  [get_bd_pins dcmac/txdata_out_1] \
  [get_bd_pins tx_data_1]
  connect_bd_net -net dcmac_txdata_out_2  [get_bd_pins dcmac/txdata_out_2] \
  [get_bd_pins tx_data_2]
  connect_bd_net -net dcmac_txdata_out_3  [get_bd_pins dcmac/txdata_out_3] \
  [get_bd_pins tx_data_3]
  connect_bd_net -net flexif_clk_rx_flexif_clk  [get_bd_pins flexif_clk_rx/flexif_clk] \
  [get_bd_pins dcmac/rx_flexif_clk]
  connect_bd_net -net flexif_clk_tx_flexif_clk  [get_bd_pins flexif_clk_tx/flexif_clk] \
  [get_bd_pins dcmac/tx_flexif_clk]
  connect_bd_net -net rx_axi_clk_1  [get_bd_pins axis_clk] \
  [get_bd_pins dcmac/rx_axi_clk] \
  [get_bd_pins dcmac/rx_macif_clk] \
  [get_bd_pins dcmac/tx_axi_clk] \
  [get_bd_pins dcmac/tx_macif_clk] \
  [get_bd_pins seg_to_axis/aclk_axis_seg_in] \
  [get_bd_pins flexif_clk_rx/clk] \
  [get_bd_pins flexif_clk_tx/clk] \
  [get_bd_pins axis_to_seg/aclk]
  connect_bd_net -net rx_channel_flush_1  [get_bd_pins rx_channel_flush] \
  [get_bd_pins dcmac/rx_channel_flush]
  connect_bd_net -net rx_clk_1  [get_bd_pins rx_clk] \
  [get_bd_pins serdes_clk_rx/clk]
  connect_bd_net -net rx_clk_alt_1  [get_bd_pins rx_clk_alt] \
  [get_bd_pins alt_serdes_clk_rx/clk]
  connect_bd_net -net rx_core_clk_1  [get_bd_pins core_clk] \
  [get_bd_pins dcmac/rx_core_clk] \
  [get_bd_pins dcmac/tx_core_clk]
  connect_bd_net -net rx_core_reset_1  [get_bd_pins rx_core_reset] \
  [get_bd_pins dcmac/rx_core_reset]
  connect_bd_net -net rx_serdes_reset_1  [get_bd_pins rx_serdes_reset] \
  [get_bd_pins dcmac/rx_serdes_reset]
  connect_bd_net -net rxdata_in_0_1  [get_bd_pins rx_data_0] \
  [get_bd_pins dcmac/rxdata_in_0]
  connect_bd_net -net rxdata_in_1_1  [get_bd_pins rx_data_1] \
  [get_bd_pins dcmac/rxdata_in_1]
  connect_bd_net -net rxdata_in_2_1  [get_bd_pins rx_data_2] \
  [get_bd_pins dcmac/rxdata_in_2]
  connect_bd_net -net rxdata_in_3_1  [get_bd_pins rx_data_3] \
  [get_bd_pins dcmac/rxdata_in_3]
  connect_bd_net -net serdes_clk_rx_serdes_clk  [get_bd_pins serdes_clk_rx/serdes_clk] \
  [get_bd_pins dcmac/rx_serdes_clk]
  connect_bd_net -net serdes_clk_tx_serdes_clk  [get_bd_pins serdes_clk_tx/serdes_clk] \
  [get_bd_pins dcmac/tx_serdes_clk]
  connect_bd_net -net ts_clk_1  [get_bd_pins ts_axil_clk] \
  [get_bd_pins ts_clk/clk] \
  [get_bd_pins dcmac/s_axi_aclk]
  connect_bd_net -net ts_clk_ts_clk  [get_bd_pins ts_clk/ts_clk] \
  [get_bd_pins dcmac/ts_clk]
  connect_bd_net -net tx_channel_flush_1  [get_bd_pins tx_channel_flush] \
  [get_bd_pins dcmac/tx_channel_flush]
  connect_bd_net -net tx_clk_1  [get_bd_pins tx_clk] \
  [get_bd_pins serdes_clk_tx/clk]
  connect_bd_net -net tx_clk_alt_1  [get_bd_pins tx_clk_alt] \
  [get_bd_pins alt_serdes_clk_tx/clk]
  connect_bd_net -net tx_core_reset_1  [get_bd_pins tx_core_reset] \
  [get_bd_pins dcmac/tx_core_reset]
  connect_bd_net -net tx_serdes_reset_1  [get_bd_pins tx_serdes_reset] \
  [get_bd_pins dcmac/tx_serdes_reset]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: gt_wrapper
proc create_hier_cell_gt_wrapper { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_gt_wrapper() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
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
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:gt_rtl:1.0 gt


  # Create pins
  create_bd_pin -dir O gt_rst_rx_done
  create_bd_pin -dir O gt_rst_tx_done
  create_bd_pin -dir I gt_rst
  create_bd_pin -dir I -type clk gt_ref_clk
  create_bd_pin -dir I -from 255 -to 0 tx_data_0
  create_bd_pin -dir I -from 255 -to 0 tx_data_1
  create_bd_pin -dir I -from 255 -to 0 tx_data_2
  create_bd_pin -dir I -from 255 -to 0 tx_data_3
  create_bd_pin -dir O -from 255 -to 0 rx_data_0
  create_bd_pin -dir O -from 255 -to 0 rx_data_1
  create_bd_pin -dir O -from 255 -to 0 rx_data_2
  create_bd_pin -dir O -from 255 -to 0 rx_data_3
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk tx_clk
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk rx_clk_alt
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk tx_clk_alt
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk rx_clk
  create_bd_pin -dir I -type clk gtwiz_freerun_clk

  # Create instance: gtwiz_versal, and set properties
  set gtwiz_versal [ create_bd_cell -type ip -vlnv xilinx.com:ip:gtwiz_versal:1.0 gtwiz_versal ]
  set_property -dict [list \
    CONFIG.GT_TYPE {GTM} \
    CONFIG.INTF0_GT_SETTINGS(LR0_SETTINGS) {RXPROGDIV_FREQ_VAL 664.062 RX_REFCLK_FREQUENCY 322.265625 TXPROGDIV_FREQ_VAL 664.062 TX_REFCLK_FREQUENCY 322.265625} \
    CONFIG.INTF0_NO_OF_LANES {4} \
    CONFIG.INTF0_PARENTID {undef} \
    CONFIG.INTF0_PRESET {GTM-PAM4_Ethernet_53G} \
    CONFIG.INTF_PARENT_PIN_LIST {QUAD0_RX0 {{}} QUAD0_RX1 {{}} QUAD0_RX2 {{}} QUAD0_RX3 {{}} QUAD0_TX0 {{}} QUAD0_TX1 {{}} QUAD0_TX2 {{}} QUAD0_TX3 {{}}} \
    CONFIG.NO_OF_QUADS {1} \
    CONFIG.QUAD0_CH0_LOOPBACK_EN {true} \
    CONFIG.QUAD0_CH1_LOOPBACK_EN {true} \
    CONFIG.QUAD0_CH2_LOOPBACK_EN {true} \
    CONFIG.QUAD0_CH3_LOOPBACK_EN {true} \
    CONFIG.QUAD0_GT_GPIO_EN {false} \
    CONFIG.QUAD0_REFCLK_STRING {HSCLK0_LCPLLGTREFCLK0 refclk_PROT0_R0_322.265625183611_MHz_unique1} \
  ] $gtwiz_versal

  set_property -dict [list \
    CONFIG.INTF0_PARENTID.VALUE_MODE {auto} \
    CONFIG.INTF_PARENT_PIN_LIST.VALUE_MODE {auto} \
  ] $gtwiz_versal


  # Create instance: mbufg_rx, and set properties
  set mbufg_rx [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 mbufg_rx ]
  set_property CONFIG.C_BUF_TYPE {MBUFG_GT} $mbufg_rx


  # Create instance: mbufg_tx, and set properties
  set mbufg_tx [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 mbufg_tx ]
  set_property CONFIG.C_BUF_TYPE {MBUFG_GT} $mbufg_tx


  # Create instance: const_1, and set properties
  set const_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_1 ]

  # Create instance: const_0, and set properties
  set const_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_0 ]
  set_property CONFIG.CONST_VAL {0} $const_0


  # Create instance: const_tx_main_cursor, and set properties
  set const_tx_main_cursor [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_tx_main_cursor ]
  set_property -dict [list \
    CONFIG.CONST_VAL {52} \
    CONFIG.CONST_WIDTH {7} \
  ] $const_tx_main_cursor


  # Create instance: const_tx_pre_post_cursor, and set properties
  set const_tx_pre_post_cursor [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_tx_pre_post_cursor ]
  set_property -dict [list \
    CONFIG.CONST_VAL {6} \
    CONFIG.CONST_WIDTH {6} \
  ] $const_tx_pre_post_cursor


  # Create instance: const_loopback, and set properties
  set const_loopback [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_loopback ]
  set_property -dict [list \
    CONFIG.CONST_VAL {0} \
    CONFIG.CONST_WIDTH {3} \
  ] $const_loopback


  # Create instance: const_gt_rate, and set properties
  set const_gt_rate [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_gt_rate ]
  set_property -dict [list \
    CONFIG.CONST_VAL {0} \
    CONFIG.CONST_WIDTH {8} \
  ] $const_gt_rate


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins gtwiz_versal/Quad0_GT_Serial] [get_bd_intf_pins gt]

  # Create port connections
  connect_bd_net -net INTF0_TX0_ch_txdata_1  [get_bd_pins tx_data_0] \
  [get_bd_pins gtwiz_versal/INTF0_TX0_ch_txdata]
  connect_bd_net -net INTF0_TX1_ch_txdata_1  [get_bd_pins tx_data_1] \
  [get_bd_pins gtwiz_versal/INTF0_TX1_ch_txdata]
  connect_bd_net -net INTF0_TX2_ch_txdata_1  [get_bd_pins tx_data_2] \
  [get_bd_pins gtwiz_versal/INTF0_TX2_ch_txdata]
  connect_bd_net -net INTF0_TX3_ch_txdata_1  [get_bd_pins tx_data_3] \
  [get_bd_pins gtwiz_versal/INTF0_TX3_ch_txdata]
  connect_bd_net -net MBUFG_GT_CE_1  [get_bd_pins const_1/dout] \
  [get_bd_pins mbufg_rx/MBUFG_GT_CE] \
  [get_bd_pins mbufg_tx/MBUFG_GT_CE]
  connect_bd_net -net QUAD0_GTREFCLK0_1  [get_bd_pins gt_ref_clk] \
  [get_bd_pins gtwiz_versal/QUAD0_GTREFCLK0]
  connect_bd_net -net const_0_dout  [get_bd_pins const_0/dout] \
  [get_bd_pins gtwiz_versal/INTF0_rst_rx_pll_and_datapath_in] \
  [get_bd_pins gtwiz_versal/INTF0_rst_tx_datapath_in] \
  [get_bd_pins gtwiz_versal/INTF0_rst_tx_pll_and_datapath_in] \
  [get_bd_pins gtwiz_versal/INTF0_rst_rx_datapath_in] \
  [get_bd_pins gtwiz_versal/INTF0_RX0_ch_rxcdrhold] \
  [get_bd_pins gtwiz_versal/INTF0_RX1_ch_rxcdrhold] \
  [get_bd_pins gtwiz_versal/INTF0_RX2_ch_rxcdrhold] \
  [get_bd_pins gtwiz_versal/INTF0_RX3_ch_rxcdrhold]
  connect_bd_net -net const_gt_rate_dout  [get_bd_pins const_gt_rate/dout] \
  [get_bd_pins gtwiz_versal/INTF0_RX0_ch_rxrate] \
  [get_bd_pins gtwiz_versal/INTF0_RX1_ch_rxrate] \
  [get_bd_pins gtwiz_versal/INTF0_RX2_ch_rxrate] \
  [get_bd_pins gtwiz_versal/INTF0_RX3_ch_rxrate] \
  [get_bd_pins gtwiz_versal/INTF0_TX0_ch_txrate] \
  [get_bd_pins gtwiz_versal/INTF0_TX1_ch_txrate] \
  [get_bd_pins gtwiz_versal/INTF0_TX2_ch_txrate] \
  [get_bd_pins gtwiz_versal/INTF0_TX3_ch_txrate]
  connect_bd_net -net const_loopback_dout  [get_bd_pins const_loopback/dout] \
  [get_bd_pins gtwiz_versal/QUAD0_ch0_loopback] \
  [get_bd_pins gtwiz_versal/QUAD0_ch1_loopback] \
  [get_bd_pins gtwiz_versal/QUAD0_ch2_loopback] \
  [get_bd_pins gtwiz_versal/QUAD0_ch3_loopback]
  connect_bd_net -net const_tx_main_cursor_dout  [get_bd_pins const_tx_main_cursor/dout] \
  [get_bd_pins gtwiz_versal/INTF0_TX0_ch_txmaincursor] \
  [get_bd_pins gtwiz_versal/INTF0_TX1_ch_txmaincursor] \
  [get_bd_pins gtwiz_versal/INTF0_TX2_ch_txmaincursor] \
  [get_bd_pins gtwiz_versal/INTF0_TX3_ch_txmaincursor]
  connect_bd_net -net const_tx_pre_post_cursor_dout  [get_bd_pins const_tx_pre_post_cursor/dout] \
  [get_bd_pins gtwiz_versal/INTF0_TX0_ch_txprecursor] \
  [get_bd_pins gtwiz_versal/INTF0_TX1_ch_txprecursor] \
  [get_bd_pins gtwiz_versal/INTF0_TX2_ch_txprecursor] \
  [get_bd_pins gtwiz_versal/INTF0_TX3_ch_txprecursor] \
  [get_bd_pins gtwiz_versal/INTF0_TX0_ch_txpostcursor] \
  [get_bd_pins gtwiz_versal/INTF0_TX1_ch_txpostcursor] \
  [get_bd_pins gtwiz_versal/INTF0_TX2_ch_txpostcursor] \
  [get_bd_pins gtwiz_versal/INTF0_TX3_ch_txpostcursor]
  connect_bd_net -net gt_rst_1  [get_bd_pins gt_rst] \
  [get_bd_pins gtwiz_versal/INTF0_rst_all_in]
  connect_bd_net -net gtwiz_freerun_clk_1  [get_bd_pins gtwiz_freerun_clk] \
  [get_bd_pins gtwiz_versal/gtwiz_freerun_clk]
  connect_bd_net -net gtwiz_versal_0_INTF0_rst_rx_done_out  [get_bd_pins gtwiz_versal/INTF0_rst_rx_done_out] \
  [get_bd_pins gt_rst_rx_done]
  connect_bd_net -net gtwiz_versal_0_INTF0_rst_tx_done_out  [get_bd_pins gtwiz_versal/INTF0_rst_tx_done_out] \
  [get_bd_pins gt_rst_tx_done]
  connect_bd_net -net gtwiz_versal_INTF0_RX0_ch_rxdata  [get_bd_pins gtwiz_versal/INTF0_RX0_ch_rxdata] \
  [get_bd_pins rx_data_0]
  connect_bd_net -net gtwiz_versal_INTF0_RX1_ch_rxdata  [get_bd_pins gtwiz_versal/INTF0_RX1_ch_rxdata] \
  [get_bd_pins rx_data_1]
  connect_bd_net -net gtwiz_versal_INTF0_RX2_ch_rxdata  [get_bd_pins gtwiz_versal/INTF0_RX2_ch_rxdata] \
  [get_bd_pins rx_data_2]
  connect_bd_net -net gtwiz_versal_INTF0_RX3_ch_rxdata  [get_bd_pins gtwiz_versal/INTF0_RX3_ch_rxdata] \
  [get_bd_pins rx_data_3]
  connect_bd_net -net gtwiz_versal_INTF0_RX_clr_out  [get_bd_pins gtwiz_versal/INTF0_RX_clr_out] \
  [get_bd_pins mbufg_rx/MBUFG_GT_CLR]
  connect_bd_net -net gtwiz_versal_INTF0_RX_clrb_leaf_out  [get_bd_pins gtwiz_versal/INTF0_RX_clrb_leaf_out] \
  [get_bd_pins mbufg_rx/MBUFG_GT_CLRB_LEAF]
  connect_bd_net -net gtwiz_versal_INTF0_TX_clr_out  [get_bd_pins gtwiz_versal/INTF0_TX_clr_out] \
  [get_bd_pins mbufg_tx/MBUFG_GT_CLR]
  connect_bd_net -net gtwiz_versal_INTF0_TX_clrb_leaf_out  [get_bd_pins gtwiz_versal/INTF0_TX_clrb_leaf_out] \
  [get_bd_pins mbufg_tx/MBUFG_GT_CLRB_LEAF]
  connect_bd_net -net gtwiz_versal_QUAD0_RX0_outclk  [get_bd_pins gtwiz_versal/QUAD0_RX0_outclk] \
  [get_bd_pins mbufg_rx/MBUFG_GT_I]
  connect_bd_net -net gtwiz_versal_QUAD0_TX0_outclk  [get_bd_pins gtwiz_versal/QUAD0_TX0_outclk] \
  [get_bd_pins mbufg_tx/MBUFG_GT_I]
  connect_bd_net -net mbufg_rx_MBUFG_GT_O1  [get_bd_pins mbufg_rx/MBUFG_GT_O1] \
  [get_bd_pins rx_clk]
  connect_bd_net -net mbufg_rx_MBUFG_GT_O2  [get_bd_pins mbufg_rx/MBUFG_GT_O2] \
  [get_bd_pins gtwiz_versal/QUAD0_RX0_usrclk] \
  [get_bd_pins gtwiz_versal/QUAD0_RX1_usrclk] \
  [get_bd_pins gtwiz_versal/QUAD0_RX2_usrclk] \
  [get_bd_pins gtwiz_versal/QUAD0_RX3_usrclk] \
  [get_bd_pins rx_clk_alt]
  connect_bd_net -net mbufg_tx_MBUFG_GT_O1  [get_bd_pins mbufg_tx/MBUFG_GT_O1] \
  [get_bd_pins tx_clk]
  connect_bd_net -net mbufg_tx_MBUFG_GT_O2  [get_bd_pins mbufg_tx/MBUFG_GT_O2] \
  [get_bd_pins gtwiz_versal/QUAD0_TX0_usrclk] \
  [get_bd_pins gtwiz_versal/QUAD0_TX1_usrclk] \
  [get_bd_pins gtwiz_versal/QUAD0_TX2_usrclk] \
  [get_bd_pins gtwiz_versal/QUAD0_TX3_usrclk] \
  [get_bd_pins tx_clk_alt]

  # Restore current instance
  current_bd_instance $oldCurInst
}

################################################################
# TOP-LEVEL
################################################################
proc cr_bd_dcmac { parentCell } {
    # Set up block design
    variable design_name
    set design_name dcmac_versal_axis_wrapper
    create_bd_design $design_name

    upvar #0 cfg cnfg

    if { $parentCell eq "" } {
        set parentCell [get_bd_cells /]
    }

    set parentObj [get_bd_cells $parentCell]
    if { $parentObj == "" } {
        catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
        return
    }

    set parentType [get_property TYPE $parentObj]
    if { $parentType ne "hier" } {
        catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
        return
    }

    set oldCurInst [current_bd_instance .]
    current_bd_instance $parentObj

    # Create interface ports
    set s_axis_tx [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 s_axis_tx ]
    set_property -dict [ list \
        CONFIG.HAS_TKEEP {1} \
        CONFIG.HAS_TLAST {1} \
        CONFIG.HAS_TREADY {1} \
        CONFIG.HAS_TSTRB {0} \
        CONFIG.LAYERED_METADATA {undef} \
        CONFIG.TDATA_NUM_BYTES {64} \
        CONFIG.TDEST_WIDTH {0} \
        CONFIG.TID_WIDTH {0} \
        CONFIG.TUSER_WIDTH {0} \
    ] $s_axis_tx

    set m_axis_rx [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 m_axis_rx ]

    set gt_clk [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 gt_clk ]
    set_property -dict [ list \
        CONFIG.FREQ_HZ {322265625} \
    ] $gt_clk

    set gt [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gt_rtl:1.0 gt ]

    # Create ports
    set aresetn [ create_bd_port -dir I -type rst aresetn ]
    
    set aclk [ create_bd_port -dir I -type clk aclk ]
    set cmd "set_property -dict \[ list \
      CONFIG.FREQ_HZ $cnfg(nclk_f)000000 \
      CONFIG.ASSOCIATED_BUSIF {s_axis_tx:m_axis_rx} \
      CONFIG.ASSOCIATED_RESET {aresetn} \
    ] \$aclk"

    # Create instances
    create_hier_cell_gt_wrapper [current_bd_instance .] gt_wrapper
    create_hier_cell_dcmac_wrapper [current_bd_instance .] dcmac_wrapper
    create_hier_cell_datapath_tx [current_bd_instance .] datapath_tx
    create_hier_cell_datapath_rx [current_bd_instance .] datapath_rx
    create_hier_cell_bd_clock_reset_ctrl [current_bd_instance .] bd_clock_reset_ctrl

    # Create interface connections
    connect_bd_intf_net [get_bd_intf_ports gt] [get_bd_intf_pins gt_wrapper/gt]
    connect_bd_intf_net [get_bd_intf_ports gt_clk] [get_bd_intf_pins bd_clock_reset_ctrl/gt_clk]

    connect_bd_intf_net [get_bd_intf_ports m_axis_rx] [get_bd_intf_pins datapath_rx/m_axis_rx]
    connect_bd_intf_net [get_bd_intf_pins dcmac_wrapper/m_axis_rx] [get_bd_intf_pins datapath_rx/s_axis_rx]
    
    connect_bd_intf_net [get_bd_intf_ports s_axis_tx] [get_bd_intf_pins datapath_tx/s_axis_tx]
    connect_bd_intf_net [get_bd_intf_pins dcmac_wrapper/s_axis_tx] [get_bd_intf_pins datapath_tx/m_axis_tx]

    # Create port connections
    connect_bd_net [get_bd_ports aclk] [get_bd_pins datapath_tx/aclk] [get_bd_pins datapath_rx/aclk]
    connect_bd_net [get_bd_ports aresetn] [get_bd_pins datapath_tx/aresetn] [get_bd_pins bd_clock_reset_ctrl/aresetn]
    
    connect_bd_net [get_bd_pins dcmac_wrapper/tx_data_0] [get_bd_pins gt_wrapper/tx_data_0]
    connect_bd_net [get_bd_pins dcmac_wrapper/tx_data_1] [get_bd_pins gt_wrapper/tx_data_1]
    connect_bd_net [get_bd_pins dcmac_wrapper/tx_data_2] [get_bd_pins gt_wrapper/tx_data_2]
    connect_bd_net [get_bd_pins dcmac_wrapper/tx_data_3] [get_bd_pins gt_wrapper/tx_data_3]
    
    connect_bd_net [get_bd_pins gt_wrapper/rx_data_0] [get_bd_pins dcmac_wrapper/rx_data_0]
    connect_bd_net [get_bd_pins gt_wrapper/rx_data_1] [get_bd_pins dcmac_wrapper/rx_data_1]
    connect_bd_net [get_bd_pins gt_wrapper/rx_data_2] [get_bd_pins dcmac_wrapper/rx_data_2]
    connect_bd_net [get_bd_pins gt_wrapper/rx_data_3] [get_bd_pins dcmac_wrapper/rx_data_3]

    connect_bd_net [get_bd_pins bd_clock_reset_ctrl/gt_reset] [get_bd_pins gt_wrapper/gt_rst]
    connect_bd_net [get_bd_pins bd_clock_reset_ctrl/gt_ref_clk] [get_bd_pins gt_wrapper/gt_ref_clk]
    connect_bd_net [get_bd_pins gt_wrapper/gt_rst_rx_done] [get_bd_pins bd_clock_reset_ctrl/gt_reset_done_rx]
    connect_bd_net [get_bd_pins gt_wrapper/gt_rst_tx_done] [get_bd_pins bd_clock_reset_ctrl/gt_reset_done_tx]
    
    connect_bd_net [get_bd_pins bd_clock_reset_ctrl/dcmac_axis_clk] \
    [get_bd_pins dcmac_wrapper/axis_clk] \
    [get_bd_pins datapath_tx/dclk] \
    [get_bd_pins datapath_rx/dclk]

    connect_bd_net [get_bd_pins bd_clock_reset_ctrl/axis_resetn] \
    [get_bd_pins dcmac_wrapper/axis_tx_resetn] \
    [get_bd_pins datapath_tx/dresetn] \
    [get_bd_pins datapath_rx/dresetn] \
    [get_bd_pins dcmac_wrapper/axis_rx_resetn]

    connect_bd_net [get_bd_pins gt_wrapper/rx_clk] [get_bd_pins dcmac_wrapper/rx_clk]
    connect_bd_net [get_bd_pins gt_wrapper/tx_clk] [get_bd_pins dcmac_wrapper/tx_clk]
    connect_bd_net [get_bd_pins gt_wrapper/rx_clk_alt] [get_bd_pins dcmac_wrapper/rx_clk_alt]
    connect_bd_net [get_bd_pins gt_wrapper/tx_clk_alt] [get_bd_pins dcmac_wrapper/tx_clk_alt]
    connect_bd_net [get_bd_pins bd_clock_reset_ctrl/dcmac_core_clk] [get_bd_pins dcmac_wrapper/core_clk]
    connect_bd_net [get_bd_pins bd_clock_reset_ctrl/sys_clk] [get_bd_pins dcmac_wrapper/ts_axil_clk] [get_bd_pins gt_wrapper/gtwiz_freerun_clk]

    connect_bd_net [get_bd_pins bd_clock_reset_ctrl/tx_core_reset] [get_bd_pins dcmac_wrapper/tx_core_reset]
    connect_bd_net [get_bd_pins bd_clock_reset_ctrl/tx_chan_flush] [get_bd_pins dcmac_wrapper/tx_channel_flush]
    connect_bd_net [get_bd_pins bd_clock_reset_ctrl/tx_serdes_reset] [get_bd_pins dcmac_wrapper/tx_serdes_reset]

    connect_bd_net [get_bd_pins bd_clock_reset_ctrl/rx_core_reset] [get_bd_pins dcmac_wrapper/rx_core_reset]
    connect_bd_net [get_bd_pins bd_clock_reset_ctrl/rx_chan_flush] [get_bd_pins dcmac_wrapper/rx_channel_flush]
    connect_bd_net [get_bd_pins bd_clock_reset_ctrl/rx_serdes_reset] [get_bd_pins dcmac_wrapper/rx_serdes_reset]

    # Restore current instance, validate design and save
    current_bd_instance $oldCurInst

    validate_bd_design
    save_bd_design
    close_bd_design $design_name 

    return 0
}
