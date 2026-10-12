######################################################################################
# This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
#
# MIT Licence
# Copyright (c) 2021-2026, Systems Group, ETH Zurich
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

# Uncomment this single sentinel line to instantiate the PL-NVMe ILA/VIO debug cores.
set ::plnvme_debug 0
# set ::plnvme_debug 1

proc cr_bd_plnvme_debug_enabled {} {
  return [expr {$::plnvme_debug != 0}]
}

########################################################################################################
# QDMA AXI write-data buffering hierarchy
########################################################################################################
# Hierarchical cell: qdma_0_w_fifo
proc cr_bd_plnvme_axi_w_fifo { parentCell nameHier } {
  if { $parentCell eq "" || $nameHier eq "" } {
    catch {common::send_msg_id "BD_TCL-102" "ERROR" "cr_bd_plnvme_axi_w_fifo() - Empty argument(s)!"}
    return
  }

  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
    catch {common::send_msg_id "BD_TCL-100" "ERROR" "Unable to find parent cell <$parentCell>!"}
    return
  }

  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
    catch {common::send_msg_id "BD_TCL-101" "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
    return
  }

  set oldCurInst [current_bd_instance .]
  current_bd_instance $parentObj

  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Match the QDMA M_AXI_BRIDGE definition explicitly so that the downstream
  # SmartConnect does not have to infer the bus widths and capabilities through
  # the channel-level FIFO connections inside this hierarchy.
  # Hierarchical interface parameters are read-only in IP Integrator. The
  # explicitly configured register slices below drive their definitions.
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M_AXI

  # The hierarchy is in the QDMA AXI domain. Leave FREQ_HZ unset here so it is
  # inherited from qdma_0/axi_aclk rather than from the configurable shell clock.
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type rst aresetn

  # The register slices provide complete AXI endpoints at the hierarchy
  # boundary. Their channels are bypassed; only W is intentionally buffered.
  set reg_slice_properties [list \
    CONFIG.ADDR_WIDTH {64} \
    CONFIG.ARUSER_WIDTH {55} \
    CONFIG.AWUSER_WIDTH {55} \
    CONFIG.BUSER_WIDTH {0} \
    CONFIG.DATA_WIDTH {512} \
    CONFIG.HAS_BRESP {1} \
    CONFIG.HAS_BURST {0} \
    CONFIG.HAS_CACHE {1} \
    CONFIG.HAS_LOCK {1} \
    CONFIG.HAS_PROT {1} \
    CONFIG.HAS_QOS {0} \
    CONFIG.HAS_REGION {0} \
    CONFIG.HAS_RRESP {1} \
    CONFIG.HAS_WSTRB {1} \
    CONFIG.ID_WIDTH {4} \
    CONFIG.MAX_BURST_LENGTH {256} \
    CONFIG.NUM_READ_OUTSTANDING {32} \
    CONFIG.NUM_READ_THREADS {1} \
    CONFIG.NUM_WRITE_OUTSTANDING {32} \
    CONFIG.NUM_WRITE_THREADS {1} \
    CONFIG.PROTOCOL {AXI4} \
    CONFIG.READ_WRITE_MODE {READ_WRITE} \
    CONFIG.REG_AR {0} \
    CONFIG.REG_AW {0} \
    CONFIG.REG_B {0} \
    CONFIG.REG_R {0} \
    CONFIG.REG_W {0} \
    CONFIG.RUSER_WIDTH {0} \
    CONFIG.SUPPORTS_NARROW_BURST {0} \
    CONFIG.WUSER_WIDTH {0}]

  set axi_in [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_register_slice:2.1 axi_in]
  set_property -dict $reg_slice_properties $axi_in
  set axi_out [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_register_slice:2.1 axi_out]
  set_property -dict $reg_slice_properties $axi_out

  set w_fifo [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 w_fifo]
  set_property -dict [list \
    CONFIG.FIFO_DEPTH {32} \
    CONFIG.FIFO_MODE {1} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.HAS_TSTRB {1} \
    CONFIG.IS_ACLK_ASYNC {0} \
    CONFIG.TDATA_NUM_BYTES {64} \
  ] $w_fifo

  # Keep AR/R/AW/B as one complete AXI connection and override only its W
  # channel with the AXIS FIFO below.
  connect_bd_intf_net -intf_net axi_passthrough \
    [get_bd_intf_pins axi_in/M_AXI] \
    [get_bd_intf_pins axi_out/S_AXI]

  connect_bd_net [get_bd_pins axi_in/m_axi_wdata] [get_bd_pins w_fifo/s_axis_tdata]
  connect_bd_net [get_bd_pins axi_in/m_axi_wstrb] [get_bd_pins w_fifo/s_axis_tstrb]
  connect_bd_net [get_bd_pins axi_in/m_axi_wlast] [get_bd_pins w_fifo/s_axis_tlast]
  connect_bd_net [get_bd_pins axi_in/m_axi_wvalid] [get_bd_pins w_fifo/s_axis_tvalid]
  connect_bd_net [get_bd_pins w_fifo/s_axis_tready] [get_bd_pins axi_in/m_axi_wready]
  connect_bd_net [get_bd_pins w_fifo/m_axis_tdata] [get_bd_pins axi_out/s_axi_wdata]
  connect_bd_net [get_bd_pins w_fifo/m_axis_tstrb] [get_bd_pins axi_out/s_axi_wstrb]
  connect_bd_net [get_bd_pins w_fifo/m_axis_tlast] [get_bd_pins axi_out/s_axi_wlast]
  connect_bd_net [get_bd_pins w_fifo/m_axis_tvalid] [get_bd_pins axi_out/s_axi_wvalid]
  connect_bd_net [get_bd_pins axi_out/s_axi_wready] [get_bd_pins w_fifo/m_axis_tready]

  connect_bd_net [get_bd_pins aclk] \
    [get_bd_pins axi_in/aclk] \
    [get_bd_pins axi_out/aclk] \
    [get_bd_pins w_fifo/s_axis_aclk]
  connect_bd_net [get_bd_pins aresetn] \
    [get_bd_pins axi_in/aresetn] \
    [get_bd_pins axi_out/aresetn] \
    [get_bd_pins w_fifo/s_axis_aresetn]

  # Connect the complete hierarchy interfaces last, after the internal
  # channel-level wiring has been established.
  connect_bd_intf_net [get_bd_intf_pins S_AXI] [get_bd_intf_pins axi_in/S_AXI]
  connect_bd_intf_net [get_bd_intf_pins axi_out/M_AXI] [get_bd_intf_pins M_AXI]

  current_bd_instance $oldCurInst
}

########################################################################################################
# PL-connected NVMe PCIe support hierarchy
########################################################################################################
# Hierarchical cell: qdma_0_support
proc cr_bd_plnvme_qdma_support { parentCell nameHier } {

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_msg_id "BD_TCL-102" "ERROR" "cr_bd_plnvme_qdma_support() - Empty argument(s)!"}
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
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:gt_rtl:1.0 pcie_mgt

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 pcie_refclk

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 m_axis_cq

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 m_axis_rc

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:pcie_cfg_fc_rtl:1.1 pcie_cfg_fc

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:pcie3_cfg_interrupt_rtl:1.0 pcie_cfg_interrupt

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:pcie3_cfg_msg_received_rtl:1.0 pcie_cfg_mesg_rcvd

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:pcie3_cfg_mesg_tx_rtl:1.0 pcie_cfg_mesg_tx

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 s_axis_cc

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 s_axis_rq

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:pcie5_cfg_control_rtl:1.0 pcie_cfg_control

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:pcie4_cfg_mgmt_rtl:1.0 pcie_cfg_mgmt

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:pcie5_cfg_status_rtl:1.0 pcie_cfg_status

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:pcie3_transmit_fc_rtl:1.0 pcie_transmit_fc


  # Create pins
  set sys_reset [create_bd_pin -dir I -type rst sys_reset]
  create_bd_pin -dir O phy_rdy_out
  create_bd_pin -dir O -type clk user_clk
  create_bd_pin -dir O user_lnk_up
  set user_reset [create_bd_pin -dir O -type rst user_reset]

  # Create instance: pcie, and set properties
  set pcie [ create_bd_cell -type ip -vlnv xilinx.com:ip:pcie_versal:1.1 pcie ]
  # The generated artifact set xlnx_ref_board=V80, but Vivado 2025.2 does not
  # offer V80 as a legal pcie_versal reference-board preset for this part. The
  # functional V80 selection is carried by xlnx_ref_board-independent link,
  # block-location, PHY, and GT properties below.
  set_property -dict [list \
    CONFIG.AXISTEN_IF_CQ_ALIGNMENT_MODE {Address_Aligned} \
    CONFIG.AXISTEN_IF_RQ_ALIGNMENT_MODE {DWORD_Aligned} \
    CONFIG.PF0_AER_CAP_ECRC_GEN_AND_CHECK_CAPABLE {false} \
    CONFIG.PF0_DEVICE_ID {B0D4} \
    CONFIG.PF0_INTERRUPT_PIN {INTA} \
    CONFIG.PF0_LINK_STATUS_SLOT_CLOCK_CONFIG {true} \
    CONFIG.PF0_REVISION_ID {00} \
    CONFIG.PF0_SRIOV_VF_DEVICE_ID {C054} \
    CONFIG.PF0_SUBSYSTEM_ID {0007} \
    CONFIG.PF1_DEVICE_ID {9011} \
    CONFIG.PF1_MSI_CAP_MULTIMSGCAP {1_vector} \
    CONFIG.PF1_REVISION_ID {00} \
    CONFIG.PF1_SUBSYSTEM_ID {0007} \
    CONFIG.PF1_SUBSYSTEM_VENDOR_ID {10EE} \
    CONFIG.PF2_DEVICE_ID {0007} \
    CONFIG.PF2_MSI_CAP_MULTIMSGCAP {1_vector} \
    CONFIG.PF2_REVISION_ID {00} \
    CONFIG.PF2_SUBSYSTEM_ID {0007} \
    CONFIG.PF2_SUBSYSTEM_VENDOR_ID {10EE} \
    CONFIG.PF3_DEVICE_ID {0007} \
    CONFIG.PF3_MSI_CAP_MULTIMSGCAP {1_vector} \
    CONFIG.PF3_REVISION_ID {00} \
    CONFIG.PF3_SUBSYSTEM_ID {0007} \
    CONFIG.PF3_SUBSYSTEM_VENDOR_ID {10EE} \
    CONFIG.PL_DISABLE_LANE_REVERSAL {TRUE} \
    CONFIG.PL_LINK_CAP_MAX_LINK_SPEED {32.0_GT/s} \
    CONFIG.PL_LINK_CAP_MAX_LINK_WIDTH {X4} \
    CONFIG.REF_CLK_FREQ {100_MHz} \
    CONFIG.VFG0_MSIX_CAP_TABLE_OFFSET {4000} \
    CONFIG.VFG1_MSIX_CAP_TABLE_OFFSET {4000} \
    CONFIG.VFG2_MSIX_CAP_TABLE_OFFSET {4000} \
    CONFIG.VFG3_MSIX_CAP_TABLE_OFFSET {4000} \
    CONFIG.acs_ext_cap_enable {false} \
    CONFIG.all_speeds_all_sides {NO} \
    CONFIG.axisten_freq {250} \
    CONFIG.axisten_if_enable_client_tag {true} \
    CONFIG.axisten_if_enable_msg_route {1EFFF} \
    CONFIG.axisten_if_enable_msg_route_override {true} \
    CONFIG.axisten_if_width {512_bit} \
    CONFIG.cfg_ext_if {false} \
    CONFIG.cfg_mgmt_if {true} \
    CONFIG.copy_pf0 {true} \
    CONFIG.coreclk_freq {500} \
    CONFIG.dedicate_perst {false} \
    CONFIG.device_port_type {Root_Port_of_PCI_Express_Root_Complex} \
    CONFIG.en_dbg_descramble {false} \
    CONFIG.en_ext_clk {FALSE} \
    CONFIG.en_l23_entry {false} \
    CONFIG.en_parity {false} \
    CONFIG.en_transceiver_status_ports {false} \
    CONFIG.enable_auto_rxeq {False} \
    CONFIG.enable_ccix {FALSE} \
    CONFIG.enable_dvsec {FALSE} \
    CONFIG.enable_gen4 {true} \
    CONFIG.enable_gtwizard {true} \
    CONFIG.enable_ibert {false} \
    CONFIG.enable_jtag_dbg {false} \
    CONFIG.enable_more_clk {false} \
    CONFIG.ext_pcie_cfg_space_enabled {false} \
    CONFIG.extended_tag_field {true} \
    CONFIG.insert_cips {false} \
    CONFIG.lane_order {Bottom} \
    CONFIG.legacy_ext_pcie_cfg_space_enabled {false} \
    CONFIG.mode_selection {Advanced} \
    CONFIG.pcie_blk_locn {X1Y2} \
    CONFIG.pcie_link_debug {false} \
    CONFIG.pcie_link_debug_axi4_st {false} \
    CONFIG.pf0_ari_enabled {false} \
    CONFIG.pf0_bar0_64bit {true} \
    CONFIG.pf0_bar0_enabled {true} \
    CONFIG.pf0_bar0_prefetchable {true} \
    CONFIG.pf0_bar0_scale {Terabytes} \
    CONFIG.pf0_bar0_size {16} \
    CONFIG.pf0_bar2_enabled {false} \
    CONFIG.pf0_bar4_enabled {false} \
    CONFIG.pf0_class_code_base {06} \
    CONFIG.pf0_class_code_interface {00} \
    CONFIG.pf0_class_code_sub {0A} \
    CONFIG.pf0_dev_cap_max_payload {1024_bytes} \
    CONFIG.pf0_expansion_rom_enabled {false} \
    CONFIG.pf0_msi_enabled {false} \
    CONFIG.pf0_msix_enabled {false} \
    CONFIG.pf0_sriov_bar0_64bit {true} \
    CONFIG.pf0_sriov_bar0_enabled {true} \
    CONFIG.pf0_sriov_bar0_prefetchable {true} \
    CONFIG.pf0_sriov_bar0_scale {Kilobytes} \
    CONFIG.pf0_sriov_bar0_size {4} \
    CONFIG.pf0_sriov_bar2_64bit {true} \
    CONFIG.pf0_sriov_bar2_enabled {true} \
    CONFIG.pf0_sriov_bar2_prefetchable {true} \
    CONFIG.pf0_sriov_bar2_scale {Kilobytes} \
    CONFIG.pf0_sriov_bar2_size {4} \
    CONFIG.pf0_sriov_bar4_enabled {false} \
    CONFIG.pf0_sriov_bar5_prefetchable {false} \
    CONFIG.pf0_vc_cap_enabled {true} \
    CONFIG.pf1_class_code_base {06} \
    CONFIG.pf1_class_code_interface {00} \
    CONFIG.pf1_class_code_sub {0A} \
    CONFIG.pf1_msix_enabled {false} \
    CONFIG.pf1_sriov_bar5_prefetchable {false} \
    CONFIG.pf1_vendor_id {10EE} \
    CONFIG.pf2_class_code_base {06} \
    CONFIG.pf2_class_code_interface {00} \
    CONFIG.pf2_class_code_sub {0A} \
    CONFIG.pf2_msix_enabled {false} \
    CONFIG.pf2_sriov_bar5_prefetchable {false} \
    CONFIG.pf2_vendor_id {10EE} \
    CONFIG.pf3_class_code_base {06} \
    CONFIG.pf3_class_code_interface {00} \
    CONFIG.pf3_class_code_sub {0A} \
    CONFIG.pf3_msix_enabled {false} \
    CONFIG.pf3_sriov_bar5_prefetchable {false} \
    CONFIG.pf3_vendor_id {10EE} \
    CONFIG.pipe_line_stage {2} \
    CONFIG.pipe_sim {false} \
    CONFIG.replace_uram_with_bram {false} \
    CONFIG.sys_reset_polarity {ACTIVE_LOW} \
    CONFIG.vendor_id {10EE} \
    CONFIG.warm_reboot_sbr_fix {false} \
  ] $pcie


  # Create instance: pcie_phy, and set properties
  set pcie_phy [ create_bd_cell -type ip -vlnv xilinx.com:ip:pcie_phy_versal:1.1 pcie_phy ]
  set_property -dict [list \
    CONFIG.PL_LINK_CAP_MAX_LINK_SPEED {32.0_GT/s} \
    CONFIG.PL_LINK_CAP_MAX_LINK_WIDTH {X4} \
    CONFIG.aspm {No_ASPM} \
    CONFIG.async_mode {SRNS} \
    CONFIG.datapath_reorder {false} \
    CONFIG.disable_double_pipe {YES} \
    CONFIG.en_gt_pclk {false} \
    CONFIG.enable_gtwizard {true} \
    CONFIG.ins_loss_profile {Add-in_Card} \
    CONFIG.lane_order {Bottom} \
    CONFIG.lane_reversal {false} \
    CONFIG.phy_async_en {true} \
    CONFIG.phy_coreclk_freq {500_MHz} \
    CONFIG.phy_refclk_freq {100_MHz} \
    CONFIG.phy_userclk_freq {250_MHz} \
    CONFIG.pipeline_stages {2} \
    CONFIG.sim_model {NO} \
    CONFIG.tx_preset {4} \
  ] $pcie_phy


  # Create instance: bufg_gt_sysclk, and set properties
  set bufg_gt_sysclk [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 bufg_gt_sysclk ]
  set_property -dict [list \
    CONFIG.C_BUFG_GT_SYNC {true} \
    CONFIG.C_BUF_TYPE {BUFG_GT} \
  ] $bufg_gt_sysclk


  # Create instance: gtwiz_versal_0, and set properties
  set gtwiz_versal_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:gtwiz_versal:1.0 gtwiz_versal_0 ]
  set_property -dict [list \
    CONFIG.GT_TYPE {GTYP} \
    CONFIG.INTF0_GT_SETTINGS(GT_DIRECTION) {DUPLEX} \
    CONFIG.INTF0_GT_SETTINGS(GT_TYPE) {GTYP} \
    CONFIG.INTF0_GT_SETTINGS(LR0_SETTINGS) {TX_BUFFER_MODE 0 PCIE_ENABLE true TX_PLL_TYPE LCPLL TX_REFCLK_SOURCE R0 TXPROGDIV_FREQ_ENABLE true TXPROGDIV_FREQ_SOURCE RPLL TX_OUTCLK_SOURCE TXPROGDIVCLK TX_DIFF_SWING_EMPH_MODE\
CUSTOM TX_BUFFER_BYPASS_MODE Fast_Sync TX_DATA_ENCODING 8B10B TX_LINE_RATE 2.5 TX_USER_DATA_WIDTH 16 TX_INT_DATA_WIDTH 20 TX_REFCLK_FREQUENCY 100 PCIE_USERCLK_FREQ 250 TXPROGDIV_FREQ_VAL 500.000 PCIE_USERCLK2_FREQ\
250 OOB_ENABLE true RX_BUFFER_MODE 1 RXPROGDIV_FREQ_ENABLE false RX_CC_LEN_SEQ 1 RX_CC_NUM_SEQ 1 RX_CC_K_0_0 true RX_CC_MASK_0_0 false RX_CC_VAL_0_0 00011100 RX_CC_KEEP_IDLE ENABLE RX_COMMA_ALIGN_WORD\
1 RX_COMMA_PRESET K28.5 RX_COMMA_M_ENABLE true RX_COMMA_P_ENABLE true RX_COMMA_MASK 1111111111 RX_COMMA_M_VAL 0101111100 RX_COMMA_P_VAL 1010000011 RX_COMMA_DOUBLE_ENABLE false RX_JTOL_FC 1 RX_PLL_TYPE\
LCPLL RX_SLIDE_MODE OFF RX_REFCLK_SOURCE R0 RX_OUTCLK_SOURCE RXOUTCLKPMA RX_EQ_MODE LPM RX_SSC_PPM 0 INS_LOSS_NYQ 20 RX_DATA_DECODING 8B10B RX_LINE_RATE 2.5 RX_PPM_OFFSET 0 RX_USER_DATA_WIDTH 16 RX_INT_DATA_WIDTH\
20 RX_REFCLK_FREQUENCY 100} \
    CONFIG.INTF0_GT_SETTINGS(LR1_SETTINGS) {TX_BUFFER_MODE 0 PCIE_ENABLE true TX_PLL_TYPE LCPLL TX_REFCLK_SOURCE R0 TXPROGDIV_FREQ_ENABLE true TXPROGDIV_FREQ_SOURCE RPLL TX_OUTCLK_SOURCE TXPROGDIVCLK TX_DIFF_SWING_EMPH_MODE\
CUSTOM TX_BUFFER_BYPASS_MODE Fast_Sync TX_DATA_ENCODING 8B10B TX_LINE_RATE 5.0 TX_USER_DATA_WIDTH 16 TX_INT_DATA_WIDTH 20 TX_REFCLK_FREQUENCY 100 PCIE_USERCLK_FREQ 250 TXPROGDIV_FREQ_VAL 500.000 PCIE_USERCLK2_FREQ\
250 OOB_ENABLE true RX_BUFFER_MODE 1 RXPROGDIV_FREQ_ENABLE false RX_CC_LEN_SEQ 1 RX_CC_NUM_SEQ 1 RX_CC_K_0_0 true RX_CC_MASK_0_0 false RX_CC_VAL_0_0 00011100 RX_CC_KEEP_IDLE ENABLE RX_COMMA_ALIGN_WORD\
1 RX_COMMA_PRESET K28.5 RX_COMMA_M_ENABLE true RX_COMMA_P_ENABLE true RX_COMMA_MASK 1111111111 RX_COMMA_M_VAL 0101111100 RX_COMMA_P_VAL 1010000011 RX_COMMA_DOUBLE_ENABLE false RX_JTOL_FC 1 RX_PLL_TYPE\
LCPLL RX_SLIDE_MODE OFF RX_REFCLK_SOURCE R0 RX_OUTCLK_SOURCE RXOUTCLKPMA RX_EQ_MODE LPM RX_SSC_PPM 0 INS_LOSS_NYQ 20 RX_DATA_DECODING 8B10B RX_LINE_RATE 5.0 RX_PPM_OFFSET 0 RX_USER_DATA_WIDTH 16 RX_INT_DATA_WIDTH\
20 RX_REFCLK_FREQUENCY 100} \
    CONFIG.INTF0_GT_SETTINGS(LR2_SETTINGS) {TX_BUFFER_MODE 0 PCIE_ENABLE true TX_PLL_TYPE LCPLL TX_REFCLK_SOURCE R0 TXPROGDIV_FREQ_ENABLE true TXPROGDIV_FREQ_SOURCE RPLL TX_OUTCLK_SOURCE TXPROGDIVCLK TX_DIFF_SWING_EMPH_MODE\
CUSTOM TX_BUFFER_BYPASS_MODE Fast_Sync TX_DATA_ENCODING 128B130B TX_LINE_RATE 8.0 TX_USER_DATA_WIDTH 32 TX_INT_DATA_WIDTH 32 TX_REFCLK_FREQUENCY 100 PCIE_USERCLK_FREQ 250 TXPROGDIV_FREQ_VAL 500.000 PCIE_USERCLK2_FREQ\
250 OOB_ENABLE true RX_BUFFER_MODE 1 RXPROGDIV_FREQ_ENABLE false RX_CC_LEN_SEQ 1 RX_CC_NUM_SEQ 1 RX_CC_K_0_0 true RX_CC_MASK_0_0 false RX_CC_VAL_0_0 00011100 RX_CC_KEEP_IDLE ENABLE RX_COMMA_ALIGN_WORD\
1 RX_COMMA_PRESET K28.5 RX_COMMA_M_ENABLE true RX_COMMA_P_ENABLE true RX_COMMA_MASK 1111111111 RX_COMMA_M_VAL 0101111100 RX_COMMA_P_VAL 1010000011 RX_COMMA_DOUBLE_ENABLE false RX_JTOL_FC 1 RX_PLL_TYPE\
LCPLL RX_SLIDE_MODE OFF RX_REFCLK_SOURCE R0 RX_OUTCLK_SOURCE RXOUTCLKPMA RX_EQ_MODE DFE RX_SSC_PPM 0 INS_LOSS_NYQ 20 RX_DATA_DECODING 128B130B RX_LINE_RATE 8.0 RX_PPM_OFFSET 0 RX_USER_DATA_WIDTH 32 RX_INT_DATA_WIDTH\
32 RX_REFCLK_FREQUENCY 100} \
    CONFIG.INTF0_GT_SETTINGS(LR3_SETTINGS) {TX_BUFFER_MODE 0 PCIE_ENABLE true TX_PLL_TYPE LCPLL TX_REFCLK_SOURCE R0 TXPROGDIV_FREQ_ENABLE true TXPROGDIV_FREQ_SOURCE RPLL TX_OUTCLK_SOURCE TXPROGDIVCLK TX_DIFF_SWING_EMPH_MODE\
CUSTOM TX_BUFFER_BYPASS_MODE Fast_Sync TX_DATA_ENCODING 128B130B TX_LINE_RATE 16.0 TX_USER_DATA_WIDTH 32 TX_INT_DATA_WIDTH 32 TX_REFCLK_FREQUENCY 100 PCIE_USERCLK_FREQ 250 TXPROGDIV_FREQ_VAL 500.000 PCIE_USERCLK2_FREQ\
250 OOB_ENABLE true RX_BUFFER_MODE 1 RXPROGDIV_FREQ_ENABLE false RX_CC_LEN_SEQ 1 RX_CC_NUM_SEQ 1 RX_CC_K_0_0 true RX_CC_MASK_0_0 false RX_CC_VAL_0_0 00011100 RX_CC_KEEP_IDLE ENABLE RX_COMMA_ALIGN_WORD\
1 RX_COMMA_PRESET K28.5 RX_COMMA_M_ENABLE true RX_COMMA_P_ENABLE true RX_COMMA_MASK 1111111111 RX_COMMA_M_VAL 0101111100 RX_COMMA_P_VAL 1010000011 RX_COMMA_DOUBLE_ENABLE false RX_JTOL_FC 1 RX_PLL_TYPE\
LCPLL RX_SLIDE_MODE OFF RX_REFCLK_SOURCE R0 RX_OUTCLK_SOURCE RXOUTCLKPMA RX_EQ_MODE DFE RX_SSC_PPM 0 INS_LOSS_NYQ 20 RX_DATA_DECODING 128B130B RX_LINE_RATE 16.0 RX_PPM_OFFSET 0 RX_USER_DATA_WIDTH 32 RX_INT_DATA_WIDTH\
32 RX_REFCLK_FREQUENCY 100} \
    CONFIG.INTF0_GT_SETTINGS(LR4_SETTINGS) {TX_BUFFER_MODE 0 PCIE_ENABLE true TX_PLL_TYPE LCPLL TX_REFCLK_SOURCE R0 TXPROGDIV_FREQ_ENABLE true TXPROGDIV_FREQ_SOURCE RPLL TX_OUTCLK_SOURCE TXPROGDIVCLK TX_DIFF_SWING_EMPH_MODE\
CUSTOM TX_BUFFER_BYPASS_MODE Fast_Sync TX_DATA_ENCODING 128B130B TX_LINE_RATE 32.0 TX_USER_DATA_WIDTH 64 TX_INT_DATA_WIDTH 64 TX_REFCLK_FREQUENCY 100 PCIE_USERCLK_FREQ 250 TXPROGDIV_FREQ_VAL 500.000 PCIE_USERCLK2_FREQ\
250 TX_ACTUAL_REFCLK_FREQUENCY 100.0 TX_FRACN_ENABLED false TX_FRACN_NUMERATOR 0 TX_PIPM_ENABLE false TX_64B66B_SCRAMBLER false TX_64B66B_ENCODER false TX_64B66B_CRC false TX_RATE_GROUP A TX_BUFFER_RESET_ON_RATE_CHANGE\
ENABLE PRESET None INTERNAL_PRESET None OOB_ENABLE true RX_BUFFER_MODE 1 RXPROGDIV_FREQ_ENABLE false RX_CC_LEN_SEQ 1 RX_CC_NUM_SEQ 1 RX_CC_K_0_0 false RX_CC_MASK_0_0 false RX_CC_VAL_0_0 00011100 RX_CC_KEEP_IDLE\
ENABLE RX_COMMA_ALIGN_WORD 1 RX_COMMA_PRESET K28.5 RX_COMMA_M_ENABLE true RX_COMMA_P_ENABLE true RX_COMMA_MASK 1111111111 RX_COMMA_M_VAL 0101111100 RX_COMMA_P_VAL 1010000011 RX_COMMA_DOUBLE_ENABLE false\
RX_JTOL_FC 1 RX_PLL_TYPE LCPLL RX_SLIDE_MODE OFF RX_REFCLK_SOURCE R0 RX_OUTCLK_SOURCE RXOUTCLKPMA RX_EQ_MODE DFE RX_SSC_PPM 0 INS_LOSS_NYQ 20 RX_DATA_DECODING 128B130B RX_LINE_RATE 32.0 RX_PPM_OFFSET 0\
RX_USER_DATA_WIDTH 64 RX_INT_DATA_WIDTH 64 RX_REFCLK_FREQUENCY 100 RESET_SEQUENCE_INTERVAL 0 RXPROGDIV_FREQ_SOURCE LCPLL RXPROGDIV_FREQ_VAL 322.265625 RX_64B66B_CRC false RX_64B66B_DECODER false RX_64B66B_DESCRAMBLER\
false RX_ACTUAL_REFCLK_FREQUENCY 100.0 RX_BUFFER_BYPASS_MODE Fast_Sync RX_BUFFER_BYPASS_MODE_LANE MULTI RX_BUFFER_RESET_ON_CB_CHANGE ENABLE RX_BUFFER_RESET_ON_COMMAALIGN DISABLE RX_BUFFER_RESET_ON_RATE_CHANGE\
ENABLE RX_CB_DISP 00000000 RX_CB_DISP_0_0 false RX_CB_DISP_0_1 false RX_CB_DISP_0_2 false RX_CB_DISP_0_3 false RX_CB_DISP_1_0 false RX_CB_DISP_1_1 false RX_CB_DISP_1_2 false RX_CB_DISP_1_3 false RX_CB_K\
00000000 RX_CB_K_0_0 false RX_CB_K_0_1 false RX_CB_K_0_2 false RX_CB_K_0_3 false RX_CB_K_1_0 false RX_CB_K_1_1 false RX_CB_K_1_2 false RX_CB_K_1_3 false RX_CB_LEN_SEQ 1 RX_CB_MASK 00000000 RX_CB_MASK_0_0\
false RX_CB_MASK_0_1 false RX_CB_MASK_0_2 false RX_CB_MASK_0_3 false RX_CB_MASK_1_0 false RX_CB_MASK_1_1 false RX_CB_MASK_1_2 false RX_CB_MASK_1_3 false RX_CB_MAX_LEVEL 1 RX_CB_MAX_SKEW 1 RX_CB_NUM_SEQ\
0 RX_CB_VAL 00000000000000000000000000000000000000000000000000000000000000000000000000000000 RX_CB_VAL_0_0 00000000 RX_CB_VAL_0_1 00000000 RX_CB_VAL_0_2 00000000 RX_CB_VAL_0_3 00000000 RX_CB_VAL_1_0 00000000\
RX_CB_VAL_1_1 00000000 RX_CB_VAL_1_2 00000000 RX_CB_VAL_1_3 00000000 RX_CC_DISP 00000000 RX_CC_DISP_0_0 false RX_CC_DISP_0_1 false RX_CC_DISP_0_2 false RX_CC_DISP_0_3 false RX_CC_DISP_1_0 false RX_CC_DISP_1_1\
false RX_CC_DISP_1_2 false RX_CC_DISP_1_3 false RX_CC_K 00000000 RX_CC_K_0_1 false RX_CC_K_0_2 false RX_CC_K_0_3 false RX_CC_K_1_0 false RX_CC_K_1_1 false RX_CC_K_1_2 false RX_CC_K_1_3 false RX_CC_MASK\
00000000 RX_CC_MASK_0_1 false RX_CC_MASK_0_2 false RX_CC_MASK_0_3 false RX_CC_MASK_1_0 false RX_CC_MASK_1_1 false RX_CC_MASK_1_2 false RX_CC_MASK_1_3 false RX_CC_PERIODICITY 5000 RX_CC_PRECEDENCE ENABLE\
RX_CC_REPEAT_WAIT 0 RX_CC_VAL 00000000000000000000000000000000000000000000000000000000000000000000000000011100 RX_CC_VAL_0_1 00000000 RX_CC_VAL_0_2 00000000 RX_CC_VAL_0_3 00000000 RX_CC_VAL_1_0 00000000\
RX_CC_VAL_1_1 00000000 RX_CC_VAL_1_2 00000000 RX_CC_VAL_1_3 00000000 RX_COMMA_SHOW_REALIGN_ENABLE true RX_COMMA_VALID_ONLY 0 RX_COUPLING AC RX_FRACN_ENABLED false RX_FRACN_NUMERATOR 0 RX_JTOL_LF_SLOPE\
-20 RX_RATE_GROUP A RX_TERMINATION PROGRAMMABLE RX_TERMINATION_PROG_VALUE 800} \
    CONFIG.INTF0_PARENTID {design_plnvme_pcie_phy_0} \
    CONFIG.INTF0_PCIE_ENABLE {true} \
    CONFIG.INTF_PARENT_PIN_LIST {QUAD0_RX0 /qdma_0_support/pcie_phy/GT_RX0 QUAD0_RX1 /qdma_0_support/pcie_phy/GT_RX1 QUAD0_RX2 /qdma_0_support/pcie_phy/GT_RX2 QUAD0_RX3 /qdma_0_support/pcie_phy/GT_RX3\
QUAD0_TX0 /qdma_0_support/pcie_phy/GT_TX0 QUAD0_TX1 /qdma_0_support/pcie_phy/GT_TX1 QUAD0_TX2 /qdma_0_support/pcie_phy/GT_TX2 QUAD0_TX3 /qdma_0_support/pcie_phy/GT_TX3} \
    CONFIG.QUAD0_REFCLK_STRING {HSCLK0_LCPLLGTREFCLK0 refclk_PROT0_R0_100_MHz_unique1 HSCLK0_RPLLGTREFCLK0 refclk_PROT0_R0_100_MHz_unique1 HSCLK1_LCPLLGTREFCLK0 refclk_PROT0_R0_100_MHz_unique1 HSCLK1_RPLLGTREFCLK0\
refclk_PROT0_R0_100_MHz_unique1} \
  ] $gtwiz_versal_0

  set_property -dict [list \
    CONFIG.INTF0_GT_SETTINGS.VALUE_MODE {auto} \
    CONFIG.INTF0_PARENTID.VALUE_MODE {auto} \
    CONFIG.INTF_PARENT_PIN_LIST.VALUE_MODE {auto} \
  ] $gtwiz_versal_0


  # Create instance: refclk_ibuf, and set properties
  set refclk_ibuf [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 refclk_ibuf ]
  set_property CONFIG.C_BUF_TYPE {IBUFDSGTE} $refclk_ibuf


  # Create instance: ilconstant_0, and set properties
  set ilconstant_0 [ create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 ilconstant_0 ]
  set_property CONFIG.CONST_VAL {1} $ilconstant_0

  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins pcie_phy/pcie_mgt] [get_bd_intf_pins pcie_mgt]
  connect_bd_intf_net -intf_net Conn2 [get_bd_intf_pins refclk_ibuf/CLK_IN_D] [get_bd_intf_pins pcie_refclk]
  connect_bd_intf_net -intf_net Conn3 [get_bd_intf_pins pcie/m_axis_cq] [get_bd_intf_pins m_axis_cq]
  connect_bd_intf_net -intf_net Conn4 [get_bd_intf_pins pcie/m_axis_rc] [get_bd_intf_pins m_axis_rc]
  connect_bd_intf_net -intf_net Conn5 [get_bd_intf_pins pcie/pcie_cfg_fc] [get_bd_intf_pins pcie_cfg_fc]
  connect_bd_intf_net -intf_net Conn6 [get_bd_intf_pins pcie/pcie_cfg_interrupt] [get_bd_intf_pins pcie_cfg_interrupt]
  connect_bd_intf_net -intf_net Conn7 [get_bd_intf_pins pcie/pcie_cfg_mesg_rcvd] [get_bd_intf_pins pcie_cfg_mesg_rcvd]
  connect_bd_intf_net -intf_net Conn8 [get_bd_intf_pins pcie/pcie_cfg_mesg_tx] [get_bd_intf_pins pcie_cfg_mesg_tx]
  connect_bd_intf_net -intf_net Conn9 [get_bd_intf_pins pcie/s_axis_cc] [get_bd_intf_pins s_axis_cc]
  connect_bd_intf_net -intf_net Conn10 [get_bd_intf_pins pcie/s_axis_rq] [get_bd_intf_pins s_axis_rq]
  connect_bd_intf_net -intf_net Conn11 [get_bd_intf_pins pcie/pcie_cfg_control] [get_bd_intf_pins pcie_cfg_control]
  connect_bd_intf_net -intf_net Conn12 [get_bd_intf_pins pcie/pcie_cfg_mgmt] [get_bd_intf_pins pcie_cfg_mgmt]
  connect_bd_intf_net -intf_net Conn13 [get_bd_intf_pins pcie/pcie_cfg_status] [get_bd_intf_pins pcie_cfg_status]
  connect_bd_intf_net -intf_net Conn14 [get_bd_intf_pins pcie/pcie_transmit_fc] [get_bd_intf_pins pcie_transmit_fc]
  connect_bd_intf_net -intf_net gtwiz_versal_0_Quad0_GT0_BUFGT [get_bd_intf_pins pcie_phy/GT_BUFGT] [get_bd_intf_pins gtwiz_versal_0/Quad0_GT0_BUFGT]
  connect_bd_intf_net -intf_net gtwiz_versal_0_Quad0_GT_Serial [get_bd_intf_pins pcie_phy/GT0_Serial] [get_bd_intf_pins gtwiz_versal_0/Quad0_GT_Serial]
  connect_bd_intf_net -intf_net pcie_phy_GT_RX0 [get_bd_intf_pins pcie_phy/GT_RX0] [get_bd_intf_pins gtwiz_versal_0/INTF0_RX0_GT_IP_Interface]
  connect_bd_intf_net -intf_net pcie_phy_GT_RX1 [get_bd_intf_pins pcie_phy/GT_RX1] [get_bd_intf_pins gtwiz_versal_0/INTF0_RX1_GT_IP_Interface]
  connect_bd_intf_net -intf_net pcie_phy_GT_RX2 [get_bd_intf_pins pcie_phy/GT_RX2] [get_bd_intf_pins gtwiz_versal_0/INTF0_RX2_GT_IP_Interface]
  connect_bd_intf_net -intf_net pcie_phy_GT_RX3 [get_bd_intf_pins pcie_phy/GT_RX3] [get_bd_intf_pins gtwiz_versal_0/INTF0_RX3_GT_IP_Interface]
  connect_bd_intf_net -intf_net pcie_phy_GT_TX0 [get_bd_intf_pins pcie_phy/GT_TX0] [get_bd_intf_pins gtwiz_versal_0/INTF0_TX0_GT_IP_Interface]
  connect_bd_intf_net -intf_net pcie_phy_GT_TX1 [get_bd_intf_pins pcie_phy/GT_TX1] [get_bd_intf_pins gtwiz_versal_0/INTF0_TX1_GT_IP_Interface]
  connect_bd_intf_net -intf_net pcie_phy_GT_TX2 [get_bd_intf_pins pcie_phy/GT_TX2] [get_bd_intf_pins gtwiz_versal_0/INTF0_TX2_GT_IP_Interface]
  connect_bd_intf_net -intf_net pcie_phy_GT_TX3 [get_bd_intf_pins pcie_phy/GT_TX3] [get_bd_intf_pins gtwiz_versal_0/INTF0_TX3_GT_IP_Interface]
  connect_bd_intf_net -intf_net pcie_phy_gt_rxmargin_q0 [get_bd_intf_pins pcie_phy/gt_rxmargin_q0] [get_bd_intf_pins gtwiz_versal_0/QUAD0_GT_RXMARGIN_INTF]
  connect_bd_intf_net -intf_net pcie_phy_mac_rx [get_bd_intf_pins pcie_phy/phy_mac_rx] [get_bd_intf_pins pcie/phy_mac_rx]
  connect_bd_intf_net -intf_net pcie_phy_mac_tx [get_bd_intf_pins pcie_phy/phy_mac_tx] [get_bd_intf_pins pcie/phy_mac_tx]
  connect_bd_intf_net -intf_net pcie_phy_phy_mac_command [get_bd_intf_pins pcie_phy/phy_mac_command] [get_bd_intf_pins pcie/phy_mac_command]
  connect_bd_intf_net -intf_net pcie_phy_phy_mac_rx_margining [get_bd_intf_pins pcie_phy/phy_mac_rx_margining] [get_bd_intf_pins pcie/phy_mac_rx_margining]
  connect_bd_intf_net -intf_net pcie_phy_phy_mac_status [get_bd_intf_pins pcie_phy/phy_mac_status] [get_bd_intf_pins pcie/phy_mac_status]
  connect_bd_intf_net -intf_net pcie_phy_phy_mac_tx_drive [get_bd_intf_pins pcie_phy/phy_mac_tx_drive] [get_bd_intf_pins pcie/phy_mac_tx_drive]
  connect_bd_intf_net -intf_net pcie_phy_phy_mac_tx_eq [get_bd_intf_pins pcie_phy/phy_mac_tx_eq] [get_bd_intf_pins pcie/phy_mac_tx_eq]

  # Create port connections
  connect_bd_net -net bufg_gt_sysclk_BUFG_GT_O  [get_bd_pins bufg_gt_sysclk/BUFG_GT_O] \
  [get_bd_pins pcie_phy/phy_refclk] \
  [get_bd_pins pcie/sys_clk] \
  [get_bd_pins gtwiz_versal_0/gtwiz_freerun_clk]
  connect_bd_net -net gtwiz_versal_0_QUAD0_RX0_outclk  [get_bd_pins gtwiz_versal_0/QUAD0_RX0_outclk] \
  [get_bd_pins pcie_phy/gt_rxoutclk]
  connect_bd_net -net gtwiz_versal_0_QUAD0_TX0_outclk  [get_bd_pins gtwiz_versal_0/QUAD0_TX0_outclk] \
  [get_bd_pins pcie_phy/gt_txoutclk]
  connect_bd_net -net gtwiz_versal_0_QUAD0_ch0_phyready  [get_bd_pins gtwiz_versal_0/QUAD0_ch0_phyready] \
  [get_bd_pins pcie_phy/ch0_phyready]
  connect_bd_net -net gtwiz_versal_0_QUAD0_ch0_phystatus  [get_bd_pins gtwiz_versal_0/QUAD0_ch0_phystatus] \
  [get_bd_pins pcie_phy/ch0_phystatus]
  connect_bd_net -net gtwiz_versal_0_QUAD0_ch1_phyready  [get_bd_pins gtwiz_versal_0/QUAD0_ch1_phyready] \
  [get_bd_pins pcie_phy/ch1_phyready]
  connect_bd_net -net gtwiz_versal_0_QUAD0_ch1_phystatus  [get_bd_pins gtwiz_versal_0/QUAD0_ch1_phystatus] \
  [get_bd_pins pcie_phy/ch1_phystatus]
  connect_bd_net -net gtwiz_versal_0_QUAD0_ch2_phyready  [get_bd_pins gtwiz_versal_0/QUAD0_ch2_phyready] \
  [get_bd_pins pcie_phy/ch2_phyready]
  connect_bd_net -net gtwiz_versal_0_QUAD0_ch2_phystatus  [get_bd_pins gtwiz_versal_0/QUAD0_ch2_phystatus] \
  [get_bd_pins pcie_phy/ch2_phystatus]
  connect_bd_net -net gtwiz_versal_0_QUAD0_ch3_phyready  [get_bd_pins gtwiz_versal_0/QUAD0_ch3_phyready] \
  [get_bd_pins pcie_phy/ch3_phyready]
  connect_bd_net -net gtwiz_versal_0_QUAD0_ch3_phystatus  [get_bd_pins gtwiz_versal_0/QUAD0_ch3_phystatus] \
  [get_bd_pins pcie_phy/ch3_phystatus]
  connect_bd_net -net ilconstant_0_dout  [get_bd_pins ilconstant_0/dout] \
  [get_bd_pins bufg_gt_sysclk/BUFG_GT_CE]
  connect_bd_net -net pcie_pcie_ltssm_state  [get_bd_pins pcie/pcie_ltssm_state] \
  [get_bd_pins pcie_phy/pcie_ltssm_state]
  connect_bd_net -net pcie_phy_gt_pcieltssm  [get_bd_pins pcie_phy/gt_pcieltssm] \
  [get_bd_pins gtwiz_versal_0/QUAD0_pcieltssm]
  connect_bd_net -net pcie_phy_gtrefclk  [get_bd_pins pcie_phy/gtrefclk] \
  [get_bd_pins gtwiz_versal_0/QUAD0_GTREFCLK0]
  connect_bd_net -net pcie_phy_pcierstb  [get_bd_pins pcie_phy/pcierstb] \
  [get_bd_pins gtwiz_versal_0/QUAD0_ch0_pcierstb] \
  [get_bd_pins gtwiz_versal_0/QUAD0_ch1_pcierstb] \
  [get_bd_pins gtwiz_versal_0/QUAD0_ch2_pcierstb] \
  [get_bd_pins gtwiz_versal_0/QUAD0_ch3_pcierstb]
  connect_bd_net -net pcie_phy_phy_coreclk  [get_bd_pins pcie_phy/phy_coreclk] \
  [get_bd_pins pcie/phy_coreclk]
  connect_bd_net -net pcie_phy_phy_mcapclk  [get_bd_pins pcie_phy/phy_mcapclk] \
  [get_bd_pins pcie/phy_mcapclk]
  connect_bd_net -net pcie_phy_phy_pclk  [get_bd_pins pcie_phy/phy_pclk] \
  [get_bd_pins pcie/phy_pclk] \
  [get_bd_pins gtwiz_versal_0/QUAD0_TX0_usrclk] \
  [get_bd_pins gtwiz_versal_0/QUAD0_RX0_usrclk] \
  [get_bd_pins gtwiz_versal_0/QUAD0_TX1_usrclk] \
  [get_bd_pins gtwiz_versal_0/QUAD0_RX1_usrclk] \
  [get_bd_pins gtwiz_versal_0/QUAD0_TX2_usrclk] \
  [get_bd_pins gtwiz_versal_0/QUAD0_RX2_usrclk] \
  [get_bd_pins gtwiz_versal_0/QUAD0_TX3_usrclk] \
  [get_bd_pins gtwiz_versal_0/QUAD0_RX3_usrclk]
  connect_bd_net -net pcie_phy_phy_userclk  [get_bd_pins pcie_phy/phy_userclk] \
  [get_bd_pins pcie/phy_userclk]
  connect_bd_net -net pcie_phy_phy_userclk2  [get_bd_pins pcie_phy/phy_userclk2] \
  [get_bd_pins pcie/phy_userclk2]
  connect_bd_net -net pcie_phy_rdy_out  [get_bd_pins pcie/phy_rdy_out] \
  [get_bd_pins phy_rdy_out]
  connect_bd_net -net pcie_user_clk  [get_bd_pins pcie/user_clk] \
  [get_bd_pins user_clk]
  connect_bd_net -net pcie_user_lnk_up  [get_bd_pins pcie/user_lnk_up] \
  [get_bd_pins user_lnk_up]
  connect_bd_net -net pcie_user_reset  [get_bd_pins pcie/user_reset] \
  [get_bd_pins user_reset]
  connect_bd_net -net refclk_ibuf_IBUF_DS_ODIV2  [get_bd_pins refclk_ibuf/IBUF_DS_ODIV2] \
  [get_bd_pins bufg_gt_sysclk/BUFG_GT_I]
  connect_bd_net -net refclk_ibuf_IBUF_OUT  [get_bd_pins refclk_ibuf/IBUF_OUT] \
  [get_bd_pins pcie_phy/phy_gtrefclk] \
  [get_bd_pins pcie/sys_clk_gt]
  connect_bd_net -net sys_reset_1  [get_bd_pins sys_reset] \
  [get_bd_pins pcie_phy/phy_rst_n] \
  [get_bd_pins pcie/sys_reset]

  # Restore current instance
  current_bd_instance $oldCurInst
}


# Create the PL-connected NVMe block design.
proc cr_bd_design_plnvme { parentCell } {
  upvar #0 cfg cnfg

  set design_name design_plnvme
  set en_plnvme_debug [cr_bd_plnvme_debug_enabled]
  # The wide PCIe trace has a high-fanout internal capture-control timing path.
  # Keep the shallow enum/setup ILAs while the wide trace is disabled.
  set en_plnvme_pcie_perf_debug 0
  # set en_plnvme_pcie_perf_debug 1
  # The Coyote-facing side follows the configured shell clock. The QDMA-facing
  # side keeps the PCIe IP's user clock and the SmartConnects provide the CDC.
  set aclk_freq_hz [expr {int($cnfg(aclk_f) * 1000000)}]

  common::send_msg_id "BD_TCL-003" "INFO" "Creating block design <$design_name> (debug=$en_plnvme_debug)..."
  create_bd_design $design_name
  current_bd_design $design_name

  # Check functional IPs. Debug IPs are dependencies only when the one-line
  # sentinel at the top of this file is uncommented.
  set list_check_ips [list \
    xilinx.com:inline_hdl:ilconstant:1.0 \
    xilinx.com:ip:axi_register_slice:2.1 \
    xilinx.com:ip:axis_data_fifo:2.0 \
    xilinx.com:ip:qdma:5.1 \
    xilinx.com:ip:smartconnect:1.0 \
    xilinx.com:ip:xpm_cdc_gen:1.0 \
    xilinx.com:ip:pcie_versal:1.1 \
    xilinx.com:ip:pcie_phy_versal:1.1 \
    xilinx.com:ip:util_ds_buf:2.2 \
    xilinx.com:ip:gtwiz_versal:1.0]
  if {$en_plnvme_debug} {
    lappend list_check_ips xilinx.com:ip:axis_ila:1.3
    lappend list_check_ips xilinx.com:ip:axis_vio:1.0
  }

  set list_ips_missing ""
  foreach ip_vlnv $list_check_ips {
    if {[get_ipdefs -all $ip_vlnv] eq ""} {
      lappend list_ips_missing $ip_vlnv
    }
  }
  if {$list_ips_missing ne ""} {
    catch {common::send_msg_id "BD_TCL-115" "ERROR" "Missing PL-NVMe IPs: $list_ips_missing"}
    return 3
  }

  if {[can_resolve_reference pl_pcie_nvme_top_wrapper] == 0} {
    catch {common::send_msg_id "BD_TCL-2021" "ERROR" "Missing module reference <pl_pcie_nvme_top_wrapper>; add hw/hdl/plpcie/nvme before creating the BD."}
    return 3
  }

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


  # Create interface ports
  set nvme_pcie_clk [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 nvme_pcie_clk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {100000000} \
   ] $nvme_pcie_clk

  set nvme_pcie_gt [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gt_rtl:1.0 nvme_pcie_gt ]

  set axi_nvme_mmio [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_nvme_mmio ]
  set_property -dict [ list \
   CONFIG.ADDR_WIDTH {64} \
   CONFIG.ARUSER_WIDTH {0} \
   CONFIG.AWUSER_WIDTH {0} \
   CONFIG.BUSER_WIDTH {0} \
   CONFIG.DATA_WIDTH {512} \
   CONFIG.FREQ_HZ $aclk_freq_hz \
   CONFIG.HAS_BRESP {1} \
   CONFIG.HAS_BURST {1} \
   CONFIG.HAS_CACHE {1} \
   CONFIG.HAS_LOCK {1} \
   CONFIG.HAS_PROT {1} \
   CONFIG.HAS_QOS {1} \
   CONFIG.HAS_REGION {1} \
   CONFIG.HAS_RRESP {1} \
   CONFIG.HAS_WSTRB {1} \
   CONFIG.ID_WIDTH {6} \
   CONFIG.MAX_BURST_LENGTH {64} \
   CONFIG.NUM_READ_OUTSTANDING {16} \
   CONFIG.NUM_READ_THREADS {1} \
   CONFIG.NUM_WRITE_OUTSTANDING {16} \
   CONFIG.NUM_WRITE_THREADS {1} \
   CONFIG.PROTOCOL {AXI4} \
   CONFIG.READ_WRITE_MODE {READ_WRITE} \
   CONFIG.RUSER_BITS_PER_BYTE {0} \
   CONFIG.RUSER_WIDTH {0} \
   CONFIG.SUPPORTS_NARROW_BURST {1} \
   CONFIG.WUSER_BITS_PER_BYTE {0} \
   CONFIG.WUSER_WIDTH {0} \
   ] $axi_nvme_mmio

  set axi_nvme_prp [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_nvme_prp ]
  set_property -dict [ list \
   CONFIG.ADDR_WIDTH {64} \
   CONFIG.DATA_WIDTH {64} \
   CONFIG.FREQ_HZ $aclk_freq_hz \
   CONFIG.NUM_READ_OUTSTANDING {8} \
   CONFIG.NUM_WRITE_OUTSTANDING {8} \
   CONFIG.PROTOCOL {AXI4} \
   ] $axi_nvme_prp

  set axi_nvme_sq [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_nvme_sq ]
  set_property -dict [ list \
   CONFIG.ADDR_WIDTH {64} \
   CONFIG.DATA_WIDTH {512} \
   CONFIG.FREQ_HZ $aclk_freq_hz \
   CONFIG.NUM_READ_OUTSTANDING {8} \
   CONFIG.NUM_WRITE_OUTSTANDING {8} \
   CONFIG.PROTOCOL {AXI4} \
   ] $axi_nvme_sq

  set axi_nvme_cq [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_nvme_cq ]
  set_property -dict [ list \
   CONFIG.ADDR_WIDTH {64} \
   CONFIG.DATA_WIDTH {128} \
   CONFIG.FREQ_HZ $aclk_freq_hz \
   CONFIG.NUM_READ_OUTSTANDING {8} \
   CONFIG.NUM_WRITE_OUTSTANDING {8} \
   CONFIG.PROTOCOL {AXI4} \
   ] $axi_nvme_cq

  set axi_nvme_card [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_nvme_card ]
  set_property -dict [ list \
   CONFIG.ADDR_WIDTH {64} \
   CONFIG.DATA_WIDTH {512} \
   CONFIG.FREQ_HZ $aclk_freq_hz \
   CONFIG.NUM_READ_OUTSTANDING {32} \
   CONFIG.NUM_WRITE_OUTSTANDING {32} \
   CONFIG.PROTOCOL {AXI4} \
   ] $axi_nvme_card

  set axi_nvme_host [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_nvme_host ]
  set_property -dict [ list \
   CONFIG.ADDR_WIDTH {64} \
   CONFIG.DATA_WIDTH {512} \
   CONFIG.FREQ_HZ $aclk_freq_hz \
   CONFIG.NUM_READ_OUTSTANDING {32} \
   CONFIG.NUM_WRITE_OUTSTANDING {32} \
   CONFIG.PROTOCOL {AXI4} \
   ] $axi_nvme_host


  # Create ports
  set aclk [ create_bd_port -dir I -type clk -freq_hz $aclk_freq_hz aclk ]
  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {axi_nvme_mmio:axi_nvme_prp:axi_nvme_sq:axi_nvme_cq:axi_nvme_card:axi_nvme_host} \
   CONFIG.ASSOCIATED_RESET {aresetn} \
 ] $aclk
  set aresetn [ create_bd_port -dir I -type rst aresetn ]
  set_property CONFIG.POLARITY {ACTIVE_LOW} $aresetn
  set nvme_setup_done [ create_bd_port -dir O nvme_setup_done ]
  set nvme_setup_error [ create_bd_port -dir O nvme_setup_error ]
  set nvme_setup_error_code [ create_bd_port -dir O -from 7 -to 0 nvme_setup_error_code ]
  set nvme_namespace_info_valid [ create_bd_port -dir O nvme_namespace_info_valid ]
  set nvme_target_nsid_found [ create_bd_port -dir O nvme_target_nsid_found ]
  set nvme_discovered_nsid [ create_bd_port -dir O -from 31 -to 0 nvme_discovered_nsid ]
  set nvme_discovered_nsze [ create_bd_port -dir O -from 63 -to 0 nvme_discovered_nsze ]
  set nvme_discovered_lba_bytes [ create_bd_port -dir O -from 31 -to 0 nvme_discovered_lba_bytes ]
  set nvme_discovered_mdts [ create_bd_port -dir O -from 7 -to 0 nvme_discovered_mdts ]
  set nvme_cap [ create_bd_port -dir O -from 63 -to 0 nvme_cap ]

  if {$en_plnvme_debug} {
  # Create instance: axis_ila_0, and set properties
  # Link/reset status is included in axis_ila_pcie_perf below.
  # set axis_ila_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_ila:1.3 axis_ila_0 ]
  # set_property CONFIG.C_NUM_OF_PROBES {3} $axis_ila_0


  # Create instance: axis_ila_1, and set properties
  # 1024 is the minimum BRAM depth supported by Versal axis_ila:1.3.
  # Enum/setup only need a final-state snapshot (Run Trigger Immediate).
  set axis_ila_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_ila:1.3 axis_ila_1 ]
  set_property -dict [list \
    CONFIG.ALL_PROBE_SAME_MU_CNT {2} \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_NUM_OF_PROBES {34} \
    CONFIG.C_PROBE12_WIDTH {64} \
    CONFIG.C_PROBE13_WIDTH {64} \
    CONFIG.C_PROBE14_WIDTH {64} \
    CONFIG.C_PROBE15_WIDTH {64} \
    CONFIG.C_PROBE16_WIDTH {64} \
    CONFIG.C_PROBE19_WIDTH {64} \
    CONFIG.C_PROBE20_WIDTH {32} \
    CONFIG.C_PROBE21_WIDTH {32} \
    CONFIG.C_PROBE22_WIDTH {32} \
    CONFIG.C_PROBE23_WIDTH {32} \
    CONFIG.C_PROBE24_WIDTH {64} \
    CONFIG.C_PROBE25_WIDTH {64} \
    CONFIG.C_PROBE26_WIDTH {8} \
    CONFIG.C_PROBE27_WIDTH {8} \
    CONFIG.C_PROBE28_WIDTH {3} \
    CONFIG.C_PROBE29_WIDTH {3} \
    CONFIG.C_PROBE30_WIDTH {3} \
    CONFIG.C_PROBE31_WIDTH {3} \
    CONFIG.C_PROBE32_WIDTH {3} \
    CONFIG.C_PROBE33_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {8} \
    CONFIG.C_PROBE4_WIDTH {8} \
    CONFIG.C_PROBE7_WIDTH {16} \
    CONFIG.C_PROBE8_WIDTH {16} \
    CONFIG.C_PROBE9_WIDTH {24} \
  ] $axis_ila_1


  # Create instance: axis_ila_2, and set properties
  set axis_ila_2 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_ila:1.3 axis_ila_2 ]
  set_property -dict [list \
    CONFIG.ALL_PROBE_SAME_MU_CNT {2} \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_NUM_OF_PROBES {72} \
    CONFIG.C_PROBE11_WIDTH {16} \
    CONFIG.C_PROBE12_WIDTH {16} \
    CONFIG.C_PROBE13_WIDTH {32} \
    CONFIG.C_PROBE14_WIDTH {32} \
    CONFIG.C_PROBE15_WIDTH {8} \
    CONFIG.C_PROBE16_WIDTH {8} \
    CONFIG.C_PROBE17_WIDTH {8} \
    CONFIG.C_PROBE18_WIDTH {32} \
    CONFIG.C_PROBE19_WIDTH {32} \
    CONFIG.C_PROBE20_WIDTH {64} \
    CONFIG.C_PROBE21_WIDTH {64} \
    CONFIG.C_PROBE22_WIDTH {64} \
    CONFIG.C_PROBE23_WIDTH {8} \
    CONFIG.C_PROBE24_WIDTH {8} \
    CONFIG.C_PROBE25_WIDTH {6} \
    CONFIG.C_PROBE26_WIDTH {8} \
    CONFIG.C_PROBE27_WIDTH {16} \
    CONFIG.C_PROBE28_WIDTH {32} \
    CONFIG.C_PROBE29_WIDTH {8} \
    CONFIG.C_PROBE30_WIDTH {8} \
    CONFIG.C_PROBE31_WIDTH {8} \
    CONFIG.C_PROBE32_WIDTH {16} \
    CONFIG.C_PROBE33_WIDTH {16} \
    CONFIG.C_PROBE34_WIDTH {16} \
    CONFIG.C_PROBE35_WIDTH {128} \
    CONFIG.C_PROBE36_WIDTH {32} \
    CONFIG.C_PROBE37_WIDTH {64} \
    CONFIG.C_PROBE38_WIDTH {32} \
    CONFIG.C_PROBE39_WIDTH {16} \
    CONFIG.C_PROBE40_WIDTH {16} \
    CONFIG.C_PROBE41_WIDTH {1} \
    CONFIG.C_PROBE42_WIDTH {32} \
    CONFIG.C_PROBE43_WIDTH {32} \
    CONFIG.C_PROBE44_WIDTH {32} \
    CONFIG.C_PROBE45_WIDTH {4} \
    CONFIG.C_PROBE46_WIDTH {64} \
    CONFIG.C_PROBE47_WIDTH {2} \
    CONFIG.C_PROBE49_WIDTH {1} \
    CONFIG.C_PROBE50_WIDTH {1} \
    CONFIG.C_PROBE51_WIDTH {32} \
    CONFIG.C_PROBE52_WIDTH {5} \
    CONFIG.C_PROBE53_WIDTH {80} \
    CONFIG.C_PROBE54_WIDTH {8} \
    CONFIG.C_PROBE55_WIDTH {64} \
    CONFIG.C_PROBE56_WIDTH {8} \
    CONFIG.C_PROBE57_WIDTH {8} \
    CONFIG.C_PROBE58_WIDTH {80} \
    CONFIG.C_PROBE59_WIDTH {32} \
    CONFIG.C_PROBE60_WIDTH {32} \
    CONFIG.C_PROBE61_WIDTH {32} \
    CONFIG.C_PROBE62_WIDTH {64} \
    CONFIG.C_PROBE63_WIDTH {64} \
    CONFIG.C_PROBE64_WIDTH {1} \
    CONFIG.C_PROBE65_WIDTH {64} \
    CONFIG.C_PROBE66_WIDTH {128} \
    CONFIG.C_PROBE67_WIDTH {128} \
    CONFIG.C_PROBE68_WIDTH {64} \
    CONFIG.C_PROBE69_WIDTH {128} \
    CONFIG.C_PROBE70_WIDTH {64} \
    CONFIG.C_PROBE71_WIDTH {64} \
  ] $axis_ila_2


  # Create instance: axis_ila_3, and set properties
  # set axis_ila_3 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_ila:1.3 axis_ila_3 ]
  # set_property -dict [list \
  #   CONFIG.C_NUM_OF_PROBES {2} \
  #   CONFIG.C_PROBE0_WIDTH {64} \
  # ] $axis_ila_3


  # Create instance: axis_ila_5, and set properties
  # set axis_ila_5 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_ila:1.3 axis_ila_5 ]
  # set_property -dict [list \
  #   CONFIG.C_DATA_DEPTH {4096} \
  #   CONFIG.C_MON_TYPE {Interface_Monitor} \
  # ] $axis_ila_5


  # Create instance: axis_ila_6
  # Monitor inbound SSD transactions at the QDMA master bridge before
  # SmartConnect performs address decoding and routes them to SQ/CQ/PRP/HBM.
  set axis_ila_6 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_ila:1.3 axis_ila_6 ]
  set_property -dict [list \
    CONFIG.C_DATA_DEPTH {4096} \
    CONFIG.C_MON_TYPE {Interface_Monitor} \
    CONFIG.C_SLOT_0_INTF_TYPE {xilinx.com:interface:aximm_rtl:1.0} \
  ] $axis_ila_6


  # Create instance: axis_ila_cq
  # Monitor the existing CQ AXIS interface outside qdma_0_support.
  # set axis_ila_cq [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_ila:1.3 axis_ila_cq ]
  # set_property -dict [list \
  #   CONFIG.C_DATA_DEPTH {4096} \
  #   CONFIG.C_MON_TYPE {Interface_Monitor} \
  #   CONFIG.C_SLOT_0_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0} \
  # ] $axis_ila_cq

  # One synchronous capture, outside qdma_0_support: incoming requests (CQ),
  # SQ/PRP completions (CC), outgoing doorbells (RQ), and PCIe credits/status.
  # Use complete AXIS monitor connections, as with the original CQ ILA.
  # Minimum depth keeps the three wide interfaces cheaper than the old deep
  # AXI/CQ ILAs. Capture all cycles when measuring latency (1024 = 4.096 us
  # at the project's PCIe user clock); no protocol checker is required.
  if {$en_plnvme_pcie_perf_debug} {
  set axis_ila_pcie_perf [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_ila:1.3 axis_ila_pcie_perf]
  set_property -dict [list \
    CONFIG.C_MON_TYPE {Mixed} \
    CONFIG.C_NUM_MONITOR_SLOTS {3} \
    CONFIG.C_SLOT_0_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0} \
    CONFIG.C_SLOT_1_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0} \
    CONFIG.C_SLOT_2_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0} \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {2} \
    CONFIG.C_NUM_OF_PROBES {20} \
    CONFIG.C_PROBE0_WIDTH {2} \
    CONFIG.C_PROBE1_WIDTH {6} \
    CONFIG.C_PROBE2_WIDTH {3} \
    CONFIG.C_PROBE3_WIDTH {8} \
    CONFIG.C_PROBE4_WIDTH {12} \
    CONFIG.C_PROBE5_WIDTH {8} \
    CONFIG.C_PROBE6_WIDTH {12} \
    CONFIG.C_PROBE7_WIDTH {8} \
    CONFIG.C_PROBE8_WIDTH {12} \
    CONFIG.C_PROBE9_WIDTH {2} \
    CONFIG.C_PROBE10_WIDTH {2} \
    CONFIG.C_PROBE11_WIDTH {2} \
    CONFIG.C_PROBE12_WIDTH {2} \
    CONFIG.C_PROBE13_WIDTH {2} \
    CONFIG.C_PROBE14_WIDTH {2} \
  ] $axis_ila_pcie_perf
  }


  # Create instance: axis_vio_1, and set properties
  set axis_vio_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_vio:1.0 axis_vio_1 ]
  set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN {0} \
    CONFIG.C_NUM_PROBE_OUT {3} \
    CONFIG.C_PROBE_OUT1_WIDTH {11} \
    CONFIG.C_PROBE_OUT2_WIDTH {1} \
    CONFIG.C_PROBE_OUT2_INIT_VAL {0x0} \
  ] $axis_vio_1
  } else {
    # The module-reference debug RAM controls are functional inputs. Keep them
    # quiescent when the optional VIO is absent.
    set debug_enable_const [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 debug_enable_const]
    set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {1}] $debug_enable_const
    set debug_addr_const [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 debug_addr_const]
    set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {11}] $debug_addr_const
  }

  # Create instance: ilconstant_0, and set properties
  set ilconstant_0 [ create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 ilconstant_0 ]
  set_property CONFIG.CONST_VAL {1} $ilconstant_0

  # Create instance: pl_pcie_nvme_top_wra_0, and set properties
  set block_name pl_pcie_nvme_top_wrapper
  set block_cell_name pl_pcie_nvme_top_wra_0
  if { [catch {set pl_pcie_nvme_top_wra_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_msg_id "BD_TCL-2095" "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $pl_pcie_nvme_top_wra_0 eq "" } {
     catch {common::send_msg_id "BD_TCL-2096" "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  # Request 512-byte MPS, bounded at run time
  # by the endpoint capability discovered by the enumeration FSM.
  set_property CONFIG.IO_QUEUE_DEPTH $cnfg(nvme_queue_depth) $pl_pcie_nvme_top_wra_0
  set_property CONFIG.PCIE_TARGET_MPS {2} $pl_pcie_nvme_top_wra_0
  set_property CONFIG.ENABLE_SETUP_DEBUG $en_plnvme_debug $pl_pcie_nvme_top_wra_0

  # Create instance: qdma_0, and set properties
  set qdma_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:qdma:5.1 qdma_0 ]
  set_property -dict [list \
    CONFIG.axibar_notranslate {true} \
    CONFIG.axibar_num {2} \
    CONFIG.cfg_ext_if {false} \
    CONFIG.device_port_type {Root_Port_of_PCI_Express_Root_Complex} \
    CONFIG.dma_reset_source_sel {Phy_Ready} \
    CONFIG.functional_mode {AXI_Bridge} \
    CONFIG.mode_selection {Advanced} \
    CONFIG.pcie_blk_locn {X1Y2} \
    CONFIG.pf0_bar0_prefetchable_qdma {true} \
    CONFIG.pf0_bar0_scale_qdma {Terabytes} \
    CONFIG.pf0_bar0_size_qdma {16} \
    CONFIG.pl_link_cap_max_link_speed {32.0_GT/s} \
    CONFIG.pl_link_cap_max_link_width {X4} \
  ] $qdma_0


  # Create instance: qdma_0_support
  cr_bd_plnvme_qdma_support [current_bd_instance .] qdma_0_support

  # Create instance: qdma_0_w_fifo
  cr_bd_plnvme_axi_w_fifo [current_bd_instance .] qdma_0_w_fifo

  # Create instance: smartconnect_0, and set properties
  set smartconnect_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0 ]
  set_property -dict [list \
    CONFIG.NUM_CLKS {2} \
    CONFIG.NUM_SI {2} \
  ] $smartconnect_0


  # Create instance: smartconnect_1, and set properties
  set smartconnect_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_1 ]
  set_property -dict [list \
    CONFIG.NUM_CLKS {2} \
    CONFIG.NUM_SI {1} \
  ] $smartconnect_1


  # Create instance: smartconnect_2, and set properties
  set smartconnect_2 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_2 ]
  set_property -dict [list \
    CONFIG.NUM_CLKS {2} \
    CONFIG.NUM_SI {1} \
  ] $smartconnect_2


  # Split CQ traffic before the ordinary decoder. The router fences CQ
  # publication on real payload B responses and restores upstream B order.
  set nvme_cq_router [create_bd_cell -type module \
    -reference pl_pcie_nvme_cq_router_wrapper nvme_cq_router]

  # CQ has its own width conversion and asynchronous clock crossing. It no
  # longer changes the active destination of the ordinary ID-0 write stream.
  set smartconnect_cq [create_bd_cell -type ip \
    -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_cq]
  set_property -dict [list CONFIG.NUM_CLKS {2} CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $smartconnect_cq

  # Create instance: smartconnect_3, and set properties
  set smartconnect_3 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_3 ]
  set_property -dict [list \
    CONFIG.NUM_CLKS {2} \
    CONFIG.NUM_MI {5} \
    CONFIG.NUM_SI {1} \
  ] $smartconnect_3


  # Create instance: xpm_cdc_gen_0, and set properties
  set xpm_cdc_gen_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xpm_cdc_gen:1.0 xpm_cdc_gen_0 ]
  set_property -dict [list \
    CONFIG.CDC_TYPE {xpm_cdc_single} \
    CONFIG.INIT_SYNC_FF {false} \
    CONFIG.SIM_ASSERT_CHK {true} \
    CONFIG.SRC_INPUT_REG {true} \
  ] $xpm_cdc_gen_0


  # Create instance: xpm_cdc_gen_1, and set properties
  set xpm_cdc_gen_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xpm_cdc_gen:1.0 xpm_cdc_gen_1 ]
  set_property CONFIG.CDC_TYPE {xpm_cdc_single} $xpm_cdc_gen_1


  # Create instance: xpm_cdc_gen_2, and set properties
  set xpm_cdc_gen_2 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xpm_cdc_gen:1.0 xpm_cdc_gen_2 ]
  set_property CONFIG.CDC_TYPE {xpm_cdc_single} $xpm_cdc_gen_2


  # Create interface connections
  connect_bd_intf_net -intf_net S01_AXI_0_1 [get_bd_intf_ports axi_nvme_mmio] [get_bd_intf_pins smartconnect_0/S01_AXI]
  connect_bd_intf_net -intf_net nvme_pcie_clk_1 [get_bd_intf_ports nvme_pcie_clk] [get_bd_intf_pins qdma_0_support/pcie_refclk]
  connect_bd_intf_net -intf_net nvme_pcie_enum_wrapp_0_m_axi_mmio [get_bd_intf_pins pl_pcie_nvme_top_wra_0/m_axi_mmio] [get_bd_intf_pins smartconnect_0/S00_AXI]
  connect_bd_intf_net -intf_net pl_pcie_nvme_top_wra_0_m_axil_csr [get_bd_intf_pins pl_pcie_nvme_top_wra_0/m_axil_csr] [get_bd_intf_pins smartconnect_1/S00_AXI]
  connect_bd_intf_net -intf_net pl_pcie_nvme_top_wra_0_m_axil_ecam [get_bd_intf_pins pl_pcie_nvme_top_wra_0/m_axil_ecam] [get_bd_intf_pins smartconnect_2/S00_AXI]
  connect_bd_intf_net -intf_net qdma_0_M_AXI_BRIDGE [get_bd_intf_pins qdma_0/M_AXI_BRIDGE] [get_bd_intf_pins qdma_0_w_fifo/S_AXI]
  connect_bd_intf_net -intf_net qdma_0_w_fifo_M_AXI [get_bd_intf_pins qdma_0_w_fifo/M_AXI] [get_bd_intf_pins nvme_cq_router/S_AXI]
  connect_bd_intf_net [get_bd_intf_pins nvme_cq_router/M_DATA] [get_bd_intf_pins smartconnect_3/S00_AXI]
  connect_bd_intf_net [get_bd_intf_pins nvme_cq_router/M_CQ] [get_bd_intf_pins smartconnect_cq/S00_AXI]
  if {$en_plnvme_debug} {
    connect_bd_intf_net -intf_net [get_bd_intf_nets qdma_0_M_AXI_BRIDGE] [get_bd_intf_pins qdma_0/M_AXI_BRIDGE] [get_bd_intf_pins axis_ila_6/SLOT_0_AXI]
  }
  connect_bd_intf_net -intf_net qdma_0_pcie_cfg_control_if [get_bd_intf_pins qdma_0/pcie_cfg_control_if] [get_bd_intf_pins qdma_0_support/pcie_cfg_control]
  connect_bd_intf_net -intf_net qdma_0_pcie_cfg_interrupt [get_bd_intf_pins qdma_0/pcie_cfg_interrupt] [get_bd_intf_pins qdma_0_support/pcie_cfg_interrupt]
  connect_bd_intf_net -intf_net qdma_0_pcie_cfg_mgmt_if [get_bd_intf_pins qdma_0/pcie_cfg_mgmt_if] [get_bd_intf_pins qdma_0_support/pcie_cfg_mgmt]
  connect_bd_intf_net -intf_net qdma_0_s_axis_cc [get_bd_intf_pins qdma_0/s_axis_cc] [get_bd_intf_pins qdma_0_support/s_axis_cc]
  connect_bd_intf_net -intf_net qdma_0_s_axis_rq [get_bd_intf_pins qdma_0/s_axis_rq] [get_bd_intf_pins qdma_0_support/s_axis_rq]
  connect_bd_intf_net -intf_net qdma_0_support_m_axis_cq [get_bd_intf_pins qdma_0/m_axis_cq] [get_bd_intf_pins qdma_0_support/m_axis_cq]
  # if {$en_plnvme_debug} {
  #   connect_bd_intf_net -intf_net [get_bd_intf_nets qdma_0_support_m_axis_cq] \
  #     [get_bd_intf_pins qdma_0/m_axis_cq] \
  #     [get_bd_intf_pins axis_ila_cq/SLOT_0_AXIS]
  # }
  connect_bd_intf_net -intf_net qdma_0_support_m_axis_rc [get_bd_intf_pins qdma_0/m_axis_rc] [get_bd_intf_pins qdma_0_support/m_axis_rc]
  connect_bd_intf_net -intf_net qdma_0_support_pcie_cfg_fc [get_bd_intf_pins qdma_0/pcie_cfg_fc] [get_bd_intf_pins qdma_0_support/pcie_cfg_fc]
  connect_bd_intf_net -intf_net qdma_0_support_pcie_cfg_mesg_rcvd [get_bd_intf_pins qdma_0/pcie_cfg_mesg_rcvd] [get_bd_intf_pins qdma_0_support/pcie_cfg_mesg_rcvd]
  connect_bd_intf_net -intf_net qdma_0_support_pcie_cfg_mesg_tx [get_bd_intf_pins qdma_0/pcie_cfg_mesg_tx] [get_bd_intf_pins qdma_0_support/pcie_cfg_mesg_tx]
  connect_bd_intf_net -intf_net qdma_0_support_pcie_cfg_status [get_bd_intf_pins qdma_0/pcie_cfg_status_if] [get_bd_intf_pins qdma_0_support/pcie_cfg_status]
  connect_bd_intf_net -intf_net qdma_0_support_pcie_mgt [get_bd_intf_ports nvme_pcie_gt] [get_bd_intf_pins qdma_0_support/pcie_mgt]
  connect_bd_intf_net -intf_net qdma_0_support_pcie_transmit_fc [get_bd_intf_pins qdma_0/pcie_transmit_fc_if] [get_bd_intf_pins qdma_0_support/pcie_transmit_fc]
  if {$en_plnvme_debug && $en_plnvme_pcie_perf_debug} {
    connect_bd_intf_net -intf_net [get_bd_intf_nets qdma_0_support_m_axis_cq] \
      [get_bd_intf_pins qdma_0_support/m_axis_cq] \
      [get_bd_intf_pins axis_ila_pcie_perf/SLOT_0_AXIS]
    connect_bd_intf_net -intf_net [get_bd_intf_nets qdma_0_s_axis_cc] \
      [get_bd_intf_pins qdma_0/s_axis_cc] \
      [get_bd_intf_pins axis_ila_pcie_perf/SLOT_1_AXIS]
    connect_bd_intf_net -intf_net [get_bd_intf_nets qdma_0_s_axis_rq] \
      [get_bd_intf_pins qdma_0/s_axis_rq] \
      [get_bd_intf_pins axis_ila_pcie_perf/SLOT_2_AXIS]

    # Native sideband taps: ALWAYS start at the actual output driver. Preserve
    # each existing consumer explicitly when tapping an interface member;
    # connecting only an input pin and a probe can otherwise leave both tied
    # off. For cross-hierarchy taps omit -net (UG835 connect_bd_net); Vivado
    # routes the connection across the existing hierarchy. No manual support
    # ports, duplicated interface definitions, or changes to cfg_fc_sel.
    # Columns: probe, output driver, existing input consumer (if any).
    foreach {probe source sink} {
       0 qdma_0/pcie_cq_np_req_sd                 qdma_0_support/pcie/pcie_cq_np_req
       1 qdma_0_support/pcie/pcie_cq_np_req_count  qdma_0/pcie_cq_np_req_count_sd
       2 qdma_0/cfg_fc_sel_sd                     qdma_0_support/pcie/cfg_fc_sel
       3 qdma_0_support/pcie/cfg_fc_ph            qdma_0/cfg_fc_ph_sd
       4 qdma_0_support/pcie/cfg_fc_pd            {}
       5 qdma_0_support/pcie/cfg_fc_nph           qdma_0/cfg_fc_nph_sd
       6 qdma_0_support/pcie/cfg_fc_npd           {}
       7 qdma_0_support/pcie/cfg_fc_cplh          {}
       8 qdma_0_support/pcie/cfg_fc_cpld          {}
       9 qdma_0_support/pcie/cfg_fc_ph_scale      {}
      10 qdma_0_support/pcie/cfg_fc_pd_scale      {}
      11 qdma_0_support/pcie/cfg_fc_nph_scale     qdma_0/cfg_fc_nph_scale_sd
      12 qdma_0_support/pcie/cfg_fc_npd_scale     {}
      13 qdma_0_support/pcie/cfg_fc_cplh_scale    {}
      14 qdma_0_support/pcie/cfg_fc_cpld_scale    {}
      17 qdma_0_support/pcie/cfg_err_cor_out      qdma_0/cfg_err_cor_out_sd
      18 qdma_0_support/pcie/cfg_err_nonfatal_out qdma_0/cfg_err_nonfatal_out_sd
      19 qdma_0_support/pcie/cfg_err_fatal_out    qdma_0/cfg_err_fatal_out_sd
    } {
      set source_pin [get_bd_pins $source]
      if {[get_property DIR $source_pin] ne "O"} {
        error "PL-NVMe performance probe $probe must tap an output: $source"
      }
      set probe_pins [list $source_pin [get_bd_pins axis_ila_pcie_perf/probe$probe]]
      if {$sink ne ""} {
        lappend probe_pins [get_bd_pins $sink]
      }
      connect_bd_net {*}$probe_pins
    }
  }
  connect_bd_intf_net -intf_net smartconnect_0_M00_AXI [get_bd_intf_pins smartconnect_0/M00_AXI] [get_bd_intf_pins qdma_0/S_AXI_BRIDGE]
  # if {$en_plnvme_debug} {
  #   connect_bd_intf_net -intf_net [get_bd_intf_nets smartconnect_0_M00_AXI] [get_bd_intf_pins smartconnect_0/M00_AXI] [get_bd_intf_pins axis_ila_5/SLOT_0_AXI]
  # }
  connect_bd_intf_net -intf_net smartconnect_1_M00_AXI [get_bd_intf_pins smartconnect_1/M00_AXI] [get_bd_intf_pins qdma_0/S_AXI_LITE_CSR]
  connect_bd_intf_net -intf_net smartconnect_2_M00_AXI [get_bd_intf_pins smartconnect_2/M00_AXI] [get_bd_intf_pins qdma_0/S_AXI_LITE]
  connect_bd_intf_net -intf_net smartconnect_3_M00_AXI [get_bd_intf_pins smartconnect_3/M00_AXI] [get_bd_intf_pins pl_pcie_nvme_top_wra_0/s_axi_dma]
  connect_bd_intf_net -intf_net smartconnect_3_M01_AXI [get_bd_intf_ports axi_nvme_prp] [get_bd_intf_pins smartconnect_3/M01_AXI]
  connect_bd_intf_net -intf_net smartconnect_3_M02_AXI [get_bd_intf_ports axi_nvme_sq] [get_bd_intf_pins smartconnect_3/M02_AXI]
  connect_bd_intf_net -intf_net smartconnect_cq_M00_AXI [get_bd_intf_ports axi_nvme_cq] [get_bd_intf_pins smartconnect_cq/M00_AXI]
  connect_bd_intf_net -intf_net smartconnect_3_M03_AXI [get_bd_intf_ports axi_nvme_card] [get_bd_intf_pins smartconnect_3/M03_AXI]
  connect_bd_intf_net -intf_net smartconnect_3_M04_AXI [get_bd_intf_ports axi_nvme_host] [get_bd_intf_pins smartconnect_3/M04_AXI]

  # Create port connections
  # The PCIe/PHY reset is active-low and deliberately held deasserted; the V80
  # MCIO integration does not expose PERST#.
  connect_bd_net -net plnvme_reset_deasserted [get_bd_pins ilconstant_0/dout] \
    [get_bd_pins qdma_0_support/sys_reset]

  # Export the setup result to Coyote. These values are synchronous to aclk and
  # remain stable after the setup FSM reaches its terminal state. Coyote adds a
  # pipeline before using them at the shell/dynamic boundary.
  connect_bd_net -net plnvme_setup_done [get_bd_pins pl_pcie_nvme_top_wra_0/setup_done] \
    [get_bd_ports nvme_setup_done]
  connect_bd_net -net plnvme_setup_error [get_bd_pins pl_pcie_nvme_top_wra_0/setup_error] \
    [get_bd_ports nvme_setup_error]
  connect_bd_net -net plnvme_setup_error_code [get_bd_pins pl_pcie_nvme_top_wra_0/setup_error_code] \
    [get_bd_ports nvme_setup_error_code]
  connect_bd_net -net plnvme_namespace_info_valid [get_bd_pins pl_pcie_nvme_top_wra_0/namespace_info_valid] \
    [get_bd_ports nvme_namespace_info_valid]
  connect_bd_net -net plnvme_target_nsid_found [get_bd_pins pl_pcie_nvme_top_wra_0/target_nsid_found] \
    [get_bd_ports nvme_target_nsid_found]
  connect_bd_net -net plnvme_discovered_nsid [get_bd_pins pl_pcie_nvme_top_wra_0/discovered_first_nsid] \
    [get_bd_ports nvme_discovered_nsid]
  connect_bd_net -net plnvme_discovered_nsze [get_bd_pins pl_pcie_nvme_top_wra_0/discovered_nsze] \
    [get_bd_ports nvme_discovered_nsze]
  connect_bd_net -net plnvme_discovered_lba_bytes [get_bd_pins pl_pcie_nvme_top_wra_0/discovered_lba_bytes] \
    [get_bd_ports nvme_discovered_lba_bytes]
  connect_bd_net -net plnvme_discovered_mdts [get_bd_pins pl_pcie_nvme_top_wra_0/discovered_controller_mdts] \
    [get_bd_ports nvme_discovered_mdts]
  connect_bd_net -net plnvme_cap [get_bd_pins pl_pcie_nvme_top_wra_0/nvme_cap] \
    [get_bd_ports nvme_cap]

  if {$en_plnvme_debug} {
  connect_bd_net -net axis_vio_1_probe_out0  [get_bd_pins axis_vio_1/probe_out0] \
  [get_bd_pins pl_pcie_nvme_top_wra_0/debug_ram_read_enable]
  connect_bd_net -net axis_vio_1_probe_out1  [get_bd_pins axis_vio_1/probe_out1] \
  [get_bd_pins pl_pcie_nvme_top_wra_0/debug_ram_read_addr]
  # A 0->1 transition refreshes the read-only snapshot after setup. The VIO,
  # sequencer and existing setup ILA all use aclk (not the PCIe user clock).
  connect_bd_net -net plnvme_health_snapshot_request [get_bd_pins axis_vio_1/probe_out2] \
    [get_bd_pins pl_pcie_nvme_top_wra_0/health_snapshot_request]
  # Capture when health_snapshot_done rises, or immediately for stable results.
  connect_bd_net -net plnvme_health_snapshot_busy [get_bd_pins pl_pcie_nvme_top_wra_0/health_snapshot_busy] \
    [get_bd_pins axis_ila_2/probe49]
  connect_bd_net -net plnvme_health_snapshot_done [get_bd_pins pl_pcie_nvme_top_wra_0/health_snapshot_done] \
    [get_bd_pins axis_ila_2/probe50]
  connect_bd_net -net plnvme_health_snapshot_count [get_bd_pins pl_pcie_nvme_top_wra_0/health_snapshot_count] \
    [get_bd_pins axis_ila_2/probe51]
  connect_bd_net -net plnvme_health_valid [get_bd_pins pl_pcie_nvme_top_wra_0/health_valid] \
    [get_bd_pins axis_ila_2/probe52]
  connect_bd_net -net plnvme_health_command_status [get_bd_pins pl_pcie_nvme_top_wra_0/health_command_status] \
    [get_bd_pins axis_ila_2/probe53]
  connect_bd_net -net plnvme_health_error_code [get_bd_pins pl_pcie_nvme_top_wra_0/health_error_code] \
    [get_bd_pins axis_ila_2/probe54]
  connect_bd_net -net plnvme_health_firmware_revision [get_bd_pins pl_pcie_nvme_top_wra_0/health_firmware_revision] \
    [get_bd_pins axis_ila_2/probe55]
  connect_bd_net -net plnvme_health_npss [get_bd_pins pl_pcie_nvme_top_wra_0/health_npss] \
    [get_bd_pins axis_ila_2/probe56]
  connect_bd_net -net plnvme_health_apsta [get_bd_pins pl_pcie_nvme_top_wra_0/health_apsta] \
    [get_bd_pins axis_ila_2/probe57]
  connect_bd_net -net plnvme_health_thermal_caps [get_bd_pins pl_pcie_nvme_top_wra_0/health_thermal_caps] \
    [get_bd_pins axis_ila_2/probe58]
  connect_bd_net -net plnvme_health_power_management [get_bd_pins pl_pcie_nvme_top_wra_0/health_power_management] \
    [get_bd_pins axis_ila_2/probe59]
  connect_bd_net -net plnvme_health_apst [get_bd_pins pl_pcie_nvme_top_wra_0/health_apst] \
    [get_bd_pins axis_ila_2/probe60]
  connect_bd_net -net plnvme_health_hctm [get_bd_pins pl_pcie_nvme_top_wra_0/health_hctm] \
    [get_bd_pins axis_ila_2/probe61]
  connect_bd_net -net plnvme_health_ps0_summary [get_bd_pins pl_pcie_nvme_top_wra_0/health_ps0_summary] \
    [get_bd_pins axis_ila_2/probe62]
  connect_bd_net -net plnvme_health_current_ps_summary [get_bd_pins pl_pcie_nvme_top_wra_0/health_current_ps_summary] \
    [get_bd_pins axis_ila_2/probe63]
  connect_bd_net -net plnvme_health_current_ps_valid [get_bd_pins pl_pcie_nvme_top_wra_0/health_current_ps_valid] \
    [get_bd_pins axis_ila_2/probe64]
  connect_bd_net -net plnvme_health_smart_status [get_bd_pins pl_pcie_nvme_top_wra_0/health_smart_status] \
    [get_bd_pins axis_ila_2/probe65]
  connect_bd_net -net plnvme_health_media_errors [get_bd_pins pl_pcie_nvme_top_wra_0/health_media_errors] \
    [get_bd_pins axis_ila_2/probe66]
  connect_bd_net -net plnvme_health_error_log_entries [get_bd_pins pl_pcie_nvme_top_wra_0/health_error_log_entries] \
    [get_bd_pins axis_ila_2/probe67]
  connect_bd_net -net plnvme_health_temperature_time [get_bd_pins pl_pcie_nvme_top_wra_0/health_temperature_time] \
    [get_bd_pins axis_ila_2/probe68]
  connect_bd_net -net plnvme_health_temperature_sensors [get_bd_pins pl_pcie_nvme_top_wra_0/health_temperature_sensors] \
    [get_bd_pins axis_ila_2/probe69]
  connect_bd_net -net plnvme_health_thermal_transitions [get_bd_pins pl_pcie_nvme_top_wra_0/health_thermal_transitions] \
    [get_bd_pins axis_ila_2/probe70]
  connect_bd_net -net plnvme_health_thermal_time [get_bd_pins pl_pcie_nvme_top_wra_0/health_thermal_time] \
    [get_bd_pins axis_ila_2/probe71]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_admin_cq_head  [get_bd_pins pl_pcie_nvme_top_wra_0/admin_cq_head] \
  [get_bd_pins axis_ila_2/probe40]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_admin_cq_phase  [get_bd_pins pl_pcie_nvme_top_wra_0/admin_cq_phase] \
  [get_bd_pins axis_ila_2/probe41]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_admin_sq_tail  [get_bd_pins pl_pcie_nvme_top_wra_0/admin_sq_tail] \
  [get_bd_pins axis_ila_2/probe39]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_allocated_io_queues  [get_bd_pins pl_pcie_nvme_top_wra_0/allocated_io_queues] \
  [get_bd_pins axis_ila_2/probe44]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_bar_is_64  [get_bd_pins pl_pcie_nvme_top_wra_0/bar_is_64] \
  [get_bd_pins axis_ila_1/probe10]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_bar_pcie_address  [get_bd_pins pl_pcie_nvme_top_wra_0/bar_pcie_address] \
  [get_bd_pins axis_ila_1/probe13]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_bar_prefetchable  [get_bd_pins pl_pcie_nvme_top_wra_0/bar_prefetchable] \
  [get_bd_pins axis_ila_1/probe11]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_bar_size  [get_bd_pins pl_pcie_nvme_top_wra_0/bar_size] \
  [get_bd_pins axis_ila_1/probe12]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_bdf_table_programmed  [get_bd_pins pl_pcie_nvme_top_wra_0/bdf_table_programmed] \
  [get_bd_pins axis_ila_1/probe18]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_class_code  [get_bd_pins pl_pcie_nvme_top_wra_0/class_code] \
  [get_bd_pins axis_ila_1/probe9]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_controller_info_valid  [get_bd_pins pl_pcie_nvme_top_wra_0/controller_info_valid] \
  [get_bd_pins axis_ila_2/probe7]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_cq_poll_count  [get_bd_pins pl_pcie_nvme_top_wra_0/cq_poll_count] \
  [get_bd_pins axis_ila_2/probe43]
  # connect_bd_net -net pl_pcie_nvme_top_wra_0_debug_ram_granted [get_bd_pins pl_pcie_nvme_top_wra_0/debug_ram_granted] \
  #   [get_bd_pins axis_ila_3/probe1]
  # connect_bd_net -net pl_pcie_nvme_top_wra_0_debug_ram_read_data [get_bd_pins pl_pcie_nvme_top_wra_0/debug_ram_read_data] \
  #   [get_bd_pins axis_ila_3/probe0]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_device_id  [get_bd_pins pl_pcie_nvme_top_wra_0/device_id] \
  [get_bd_pins axis_ila_1/probe8]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_device_present  [get_bd_pins pl_pcie_nvme_top_wra_0/device_present] \
  [get_bd_pins axis_ila_1/probe5]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_discovered_active_nsid_count  [get_bd_pins pl_pcie_nvme_top_wra_0/discovered_active_nsid_count] \
  [get_bd_pins axis_ila_2/probe19]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_discovered_controller_cqes  [get_bd_pins pl_pcie_nvme_top_wra_0/discovered_controller_cqes] \
  [get_bd_pins axis_ila_2/probe17]
  connect_bd_net -net [get_bd_nets plnvme_discovered_mdts] [get_bd_pins axis_ila_2/probe15]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_discovered_controller_nn  [get_bd_pins pl_pcie_nvme_top_wra_0/discovered_controller_nn] \
  [get_bd_pins axis_ila_2/probe14]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_discovered_controller_sqes  [get_bd_pins pl_pcie_nvme_top_wra_0/discovered_controller_sqes] \
  [get_bd_pins axis_ila_2/probe16]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_discovered_controller_ssvid  [get_bd_pins pl_pcie_nvme_top_wra_0/discovered_controller_ssvid] \
  [get_bd_pins axis_ila_2/probe12]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_discovered_controller_version  [get_bd_pins pl_pcie_nvme_top_wra_0/discovered_controller_version] \
  [get_bd_pins axis_ila_2/probe13]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_discovered_controller_vid  [get_bd_pins pl_pcie_nvme_top_wra_0/discovered_controller_vid] \
  [get_bd_pins axis_ila_2/probe11]
  connect_bd_net -net [get_bd_nets plnvme_discovered_nsid] [get_bd_pins axis_ila_2/probe18]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_discovered_flbas  [get_bd_pins pl_pcie_nvme_top_wra_0/discovered_flbas] \
  [get_bd_pins axis_ila_2/probe24]
  connect_bd_net -net [get_bd_nets plnvme_discovered_lba_bytes] [get_bd_pins axis_ila_2/probe28]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_discovered_lba_format_index  [get_bd_pins pl_pcie_nvme_top_wra_0/discovered_lba_format_index] \
  [get_bd_pins axis_ila_2/probe25]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_discovered_lbads  [get_bd_pins pl_pcie_nvme_top_wra_0/discovered_lbads] \
  [get_bd_pins axis_ila_2/probe26]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_discovered_metadata_bytes  [get_bd_pins pl_pcie_nvme_top_wra_0/discovered_metadata_bytes] \
  [get_bd_pins axis_ila_2/probe27]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_discovered_ncap  [get_bd_pins pl_pcie_nvme_top_wra_0/discovered_ncap] \
  [get_bd_pins axis_ila_2/probe21]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_discovered_nlbaf  [get_bd_pins pl_pcie_nvme_top_wra_0/discovered_nlbaf] \
  [get_bd_pins axis_ila_2/probe23]
  connect_bd_net -net [get_bd_nets plnvme_discovered_nsze] [get_bd_pins axis_ila_2/probe20]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_discovered_nuse  [get_bd_pins pl_pcie_nvme_top_wra_0/discovered_nuse] \
  [get_bd_pins axis_ila_2/probe22]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_discovery_done  [get_bd_pins pl_pcie_nvme_top_wra_0/discovery_done] \
  [get_bd_pins axis_ila_2/probe5]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_discovery_valid  [get_bd_pins pl_pcie_nvme_top_wra_0/discovery_valid] \
  [get_bd_pins axis_ila_2/probe6]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_dma_bridge_state  [get_bd_pins pl_pcie_nvme_top_wra_0/dma_bridge_state] \
  [get_bd_pins axis_ila_2/probe45]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_dma_last_axi_addr  [get_bd_pins pl_pcie_nvme_top_wra_0/dma_last_axi_addr] \
  [get_bd_pins axis_ila_2/probe46]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_dma_last_axi_resp  [get_bd_pins pl_pcie_nvme_top_wra_0/dma_last_axi_resp] \
  [get_bd_pins axis_ila_2/probe47]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_dma_protocol_error  [get_bd_pins pl_pcie_nvme_top_wra_0/dma_protocol_error] \
  [get_bd_pins axis_ila_2/probe48]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_enum_busy  [get_bd_pins pl_pcie_nvme_top_wra_0/enum_busy] \
  [get_bd_pins axis_ila_1/probe0]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_enum_done  [get_bd_pins pl_pcie_nvme_top_wra_0/enum_done] \
  [get_bd_pins axis_ila_1/probe1]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_enum_error  [get_bd_pins pl_pcie_nvme_top_wra_0/enum_error] \
  [get_bd_pins axis_ila_1/probe2]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_enum_error_code  [get_bd_pins pl_pcie_nvme_top_wra_0/enum_error_code] \
  [get_bd_pins axis_ila_1/probe4]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_enum_state  [get_bd_pins pl_pcie_nvme_top_wra_0/enum_state] \
  [get_bd_pins axis_ila_1/probe3]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_rp_pcie_cap_offset \
  [get_bd_pins pl_pcie_nvme_top_wra_0/rp_pcie_cap_offset] \
  [get_bd_pins axis_ila_1/probe26]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_ep_pcie_cap_offset \
  [get_bd_pins pl_pcie_nvme_top_wra_0/ep_pcie_cap_offset] \
  [get_bd_pins axis_ila_1/probe27]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_rp_mps_supported \
  [get_bd_pins pl_pcie_nvme_top_wra_0/rp_mps_supported] \
  [get_bd_pins axis_ila_1/probe28]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_ep_mps_supported \
  [get_bd_pins pl_pcie_nvme_top_wra_0/ep_mps_supported] \
  [get_bd_pins axis_ila_1/probe29]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_selected_mps \
  [get_bd_pins pl_pcie_nvme_top_wra_0/selected_mps] \
  [get_bd_pins axis_ila_1/probe30]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_rp_mps_configured \
  [get_bd_pins pl_pcie_nvme_top_wra_0/rp_mps_configured] \
  [get_bd_pins axis_ila_1/probe31]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_ep_mps_configured \
  [get_bd_pins pl_pcie_nvme_top_wra_0/ep_mps_configured] \
  [get_bd_pins axis_ila_1/probe32]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_mps_programmed \
  [get_bd_pins pl_pcie_nvme_top_wra_0/mps_programmed] \
  [get_bd_pins axis_ila_1/probe33]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_last_cfg_addr  [get_bd_pins pl_pcie_nvme_top_wra_0/last_cfg_addr] \
  [get_bd_pins axis_ila_1/probe21]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_last_cid  [get_bd_pins pl_pcie_nvme_top_wra_0/last_cid] \
  [get_bd_pins axis_ila_2/probe32]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_last_completion_cid  [get_bd_pins pl_pcie_nvme_top_wra_0/last_completion_cid] \
  [get_bd_pins axis_ila_2/probe33]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_last_completion_status  [get_bd_pins pl_pcie_nvme_top_wra_0/last_completion_status] \
  [get_bd_pins axis_ila_2/probe34]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_last_cqe  [get_bd_pins pl_pcie_nvme_top_wra_0/last_cqe] \
  [get_bd_pins axis_ila_2/probe35]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_last_csr_addr  [get_bd_pins pl_pcie_nvme_top_wra_0/last_csr_addr] \
  [get_bd_pins axis_ila_1/probe22]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_last_csr_write_data  [get_bd_pins pl_pcie_nvme_top_wra_0/last_csr_write_data] \
  [get_bd_pins axis_ila_1/probe23]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_last_mmio_addr  [get_bd_pins pl_pcie_nvme_top_wra_0/last_mmio_addr] \
  [get_bd_pins axis_ila_1/probe24]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_last_mmio_offset  [get_bd_pins pl_pcie_nvme_top_wra_0/last_mmio_offset] \
  [get_bd_pins axis_ila_2/probe36]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_last_mmio_rdata  [get_bd_pins pl_pcie_nvme_top_wra_0/last_mmio_rdata] \
  [get_bd_pins axis_ila_2/probe37]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_last_opcode  [get_bd_pins pl_pcie_nvme_top_wra_0/last_opcode] \
  [get_bd_pins axis_ila_2/probe31]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_last_read_data  [get_bd_pins pl_pcie_nvme_top_wra_0/last_read_data] \
  [get_bd_pins axis_ila_1/probe25]
  connect_bd_net -net [get_bd_nets plnvme_namespace_info_valid] [get_bd_pins axis_ila_2/probe9]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_namespace_list_valid  [get_bd_pins pl_pcie_nvme_top_wra_0/namespace_list_valid] \
  [get_bd_pins axis_ila_2/probe8]
  connect_bd_net -net [get_bd_nets plnvme_cap] [get_bd_pins axis_ila_1/probe19]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_nvme_class_match  [get_bd_pins pl_pcie_nvme_top_wra_0/nvme_class_match] \
  [get_bd_pins axis_ila_1/probe6]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_nvme_vs  [get_bd_pins pl_pcie_nvme_top_wra_0/nvme_vs] \
  [get_bd_pins axis_ila_1/probe20]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_queues_ready  [get_bd_pins pl_pcie_nvme_top_wra_0/queues_ready] \
  [get_bd_pins axis_ila_2/probe2]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_ready_poll_count  [get_bd_pins pl_pcie_nvme_top_wra_0/ready_poll_count] \
  [get_bd_pins axis_ila_2/probe42]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_rp_dma_bar_programmed  [get_bd_pins pl_pcie_nvme_top_wra_0/rp_dma_bar_programmed] \
  [get_bd_pins axis_ila_1/probe17]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_rp_dma_bar_size  [get_bd_pins pl_pcie_nvme_top_wra_0/rp_dma_bar_size] \
  [get_bd_pins axis_ila_1/probe14]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_rp_dma_pcie_base  [get_bd_pins pl_pcie_nvme_top_wra_0/rp_dma_pcie_base] \
  [get_bd_pins axis_ila_1/probe15]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_rp_dma_pcie_limit  [get_bd_pins pl_pcie_nvme_top_wra_0/rp_dma_pcie_limit] \
  [get_bd_pins axis_ila_1/probe16]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_setup_busy  [get_bd_pins pl_pcie_nvme_top_wra_0/setup_busy] \
  [get_bd_pins axis_ila_2/probe1]
  connect_bd_net -net [get_bd_nets plnvme_setup_done] [get_bd_pins axis_ila_2/probe3]
  connect_bd_net -net [get_bd_nets plnvme_setup_error] [get_bd_pins axis_ila_2/probe4]
  connect_bd_net -net [get_bd_nets plnvme_setup_error_code] [get_bd_pins axis_ila_2/probe30]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_setup_started  [get_bd_pins pl_pcie_nvme_top_wra_0/setup_started] \
  [get_bd_pins axis_ila_2/probe0]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_setup_state  [get_bd_pins pl_pcie_nvme_top_wra_0/setup_state] \
  [get_bd_pins axis_ila_2/probe29]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_submitted_command_count  [get_bd_pins pl_pcie_nvme_top_wra_0/submitted_command_count] \
  [get_bd_pins axis_ila_2/probe38]
  connect_bd_net -net [get_bd_nets plnvme_target_nsid_found] [get_bd_pins axis_ila_2/probe10]
  connect_bd_net -net pl_pcie_nvme_top_wra_0_vendor_id  [get_bd_pins pl_pcie_nvme_top_wra_0/vendor_id] \
  [get_bd_pins axis_ila_1/probe7]
  } else {
    connect_bd_net -net plnvme_debug_enable_low [get_bd_pins debug_enable_const/dout] \
      [get_bd_pins pl_pcie_nvme_top_wra_0/debug_ram_read_enable] \
      [get_bd_pins pl_pcie_nvme_top_wra_0/health_snapshot_request]
    connect_bd_net -net plnvme_debug_addr_low [get_bd_pins debug_addr_const/dout] \
      [get_bd_pins pl_pcie_nvme_top_wra_0/debug_ram_read_addr]
  }
  connect_bd_net -net proc_sys_reset_0_peripheral_aresetn  [get_bd_ports aresetn] \
  [get_bd_pins smartconnect_1/aresetn] \
  [get_bd_pins smartconnect_2/aresetn] \
  [get_bd_pins smartconnect_0/aresetn] \
  [get_bd_pins pl_pcie_nvme_top_wra_0/aresetn]
  connect_bd_net -net qdma_0_axi_aclk  [get_bd_pins qdma_0/axi_aclk] \
  [get_bd_pins qdma_0_w_fifo/aclk] \
  [get_bd_pins nvme_cq_router/aclk] \
  [get_bd_pins smartconnect_cq/aclk] \
  [get_bd_pins smartconnect_0/aclk1] \
  [get_bd_pins smartconnect_1/aclk1] \
  [get_bd_pins smartconnect_2/aclk1] \
  [get_bd_pins smartconnect_3/aclk]
  connect_bd_net -net qdma_0_axi_aresetn  [get_bd_pins qdma_0/axi_aresetn] \
  [get_bd_pins qdma_0_w_fifo/aresetn] \
  [get_bd_pins nvme_cq_router/aresetn] \
  [get_bd_pins smartconnect_cq/aresetn] \
  [get_bd_pins smartconnect_3/aresetn]
  connect_bd_net -net qdma_0_csr_prog_done  [get_bd_pins qdma_0/csr_prog_done] \
  [get_bd_pins xpm_cdc_gen_2/src_in]
  connect_bd_net -net qdma_0_support_phy_rdy_out  [get_bd_pins qdma_0_support/phy_rdy_out] \
  [get_bd_pins qdma_0/phy_rdy_out_sd] \
  [get_bd_pins xpm_cdc_gen_1/src_in]
  connect_bd_net -net qdma_0_support_user_clk  [get_bd_pins qdma_0_support/user_clk] \
  [get_bd_pins xpm_cdc_gen_1/src_clk] \
  [get_bd_pins xpm_cdc_gen_0/src_clk] \
  [get_bd_pins xpm_cdc_gen_2/src_clk] \
  [get_bd_pins qdma_0/user_clk_sd]
  connect_bd_net -net qdma_0_support_user_lnk_up  [get_bd_pins qdma_0_support/user_lnk_up] \
  [get_bd_pins qdma_0/user_lnk_up_sd] \
  [get_bd_pins xpm_cdc_gen_0/src_in]
  connect_bd_net -net qdma_0_support_user_reset  [get_bd_pins qdma_0_support/user_reset] \
  [get_bd_pins qdma_0/user_reset_sd]
  connect_bd_net -net versal_cips_0_pl0_ref_clk  [get_bd_ports aclk] \
  [get_bd_pins xpm_cdc_gen_0/dest_clk] \
  [get_bd_pins xpm_cdc_gen_1/dest_clk] \
  [get_bd_pins xpm_cdc_gen_2/dest_clk] \
  [get_bd_pins smartconnect_0/aclk] \
  [get_bd_pins smartconnect_1/aclk] \
  [get_bd_pins smartconnect_2/aclk] \
  [get_bd_pins smartconnect_3/aclk1] \
  [get_bd_pins smartconnect_cq/aclk1] \
  [get_bd_pins pl_pcie_nvme_top_wra_0/aclk]
  if {$en_plnvme_debug} {
    # connect_bd_net -net [get_bd_nets qdma_0_axi_aclk] [get_bd_pins axis_ila_5/clk]
    # connect_bd_net -net [get_bd_nets qdma_0_axi_aresetn] [get_bd_pins axis_ila_5/resetn]
    connect_bd_net -net [get_bd_nets qdma_0_axi_aclk] [get_bd_pins axis_ila_6/clk]
    connect_bd_net -net [get_bd_nets qdma_0_axi_aresetn] [get_bd_pins axis_ila_6/resetn]
    # connect_bd_net -net [get_bd_nets qdma_0_support_user_clk] \
    #   [get_bd_pins axis_ila_cq/clk]
    # connect_bd_net -net [get_bd_nets plnvme_reset_deasserted] \
    #   [get_bd_pins axis_ila_cq/resetn]
    # connect_bd_net -net [get_bd_nets qdma_0_csr_prog_done] [get_bd_pins axis_ila_0/probe2]
    # connect_bd_net -net [get_bd_nets qdma_0_support_phy_rdy_out] [get_bd_pins axis_ila_0/probe0]
    # connect_bd_net -net [get_bd_nets qdma_0_support_user_clk] [get_bd_pins axis_ila_0/clk]
    # connect_bd_net -net [get_bd_nets qdma_0_support_user_lnk_up] [get_bd_pins axis_ila_0/probe1]
    if {$en_plnvme_pcie_perf_debug} {
    connect_bd_net -net [get_bd_nets qdma_0_support_user_clk] \
      [get_bd_pins axis_ila_pcie_perf/clk]
    # Same active-low deasserted reset as the previous working CQ ILA. Do not
    # connect active-high PCIe user_reset directly to an ILA resetn input.
    connect_bd_net -net [get_bd_nets plnvme_reset_deasserted] \
      [get_bd_pins axis_ila_pcie_perf/resetn]
    connect_bd_net -net [get_bd_nets qdma_0_support_user_lnk_up] \
      [get_bd_pins axis_ila_pcie_perf/probe15]
    connect_bd_net -net [get_bd_nets qdma_0_support_user_reset] \
      [get_bd_pins axis_ila_pcie_perf/probe16]
    }
    connect_bd_net -net [get_bd_nets versal_cips_0_pl0_ref_clk] \
      [get_bd_pins axis_vio_1/clk] \
      [get_bd_pins axis_ila_2/clk] \
      [get_bd_pins axis_ila_1/clk]
    # connect_bd_net -net [get_bd_nets versal_cips_0_pl0_ref_clk] [get_bd_pins axis_ila_3/clk]
  }
  connect_bd_net -net xpm_cdc_gen_0_dest_out  [get_bd_pins xpm_cdc_gen_0/dest_out] \
  [get_bd_pins pl_pcie_nvme_top_wra_0/user_lnk_up]
  connect_bd_net -net xpm_cdc_gen_1_dest_out  [get_bd_pins xpm_cdc_gen_1/dest_out] \
  [get_bd_pins pl_pcie_nvme_top_wra_0/phy_ready]
  connect_bd_net -net xpm_cdc_gen_2_dest_out  [get_bd_pins xpm_cdc_gen_2/dest_out] \
  [get_bd_pins pl_pcie_nvme_top_wra_0/csr_prog_done]

  # Fixed windows for 16 device IDs and up to 256 entries, whatever the
  # configured depth: SQ 16 KiB/device, CQ 4 KiB/device, PRP 1 MiB/device.
  # Bases must align to the full window: BRAM controllers use low address bits.
  # Create address segments
  # The router decodes the existing 16-TiB local aperture internally; its
  # two independent master spaces retain all original destination addresses.
  assign_bd_address -offset 0x000000000000 -range 0x100000000000 -target_address_space [get_bd_addr_spaces qdma_0/M_AXI_BRIDGE] [get_bd_addr_segs nvme_cq_router/S_AXI/reg0] -force
  assign_bd_address -offset 0x100000000000 -range 0x100000000000 -target_address_space [get_bd_addr_spaces pl_pcie_nvme_top_wra_0/m_axi_mmio] [get_bd_addr_segs qdma_0/S_AXI_BRIDGE/BAR0] -force
  assign_bd_address -offset 0x80000000 -range 0x00100000 -target_address_space [get_bd_addr_spaces pl_pcie_nvme_top_wra_0/m_axi_mmio] [get_bd_addr_segs qdma_0/S_AXI_BRIDGE/BAR1] -force
  assign_bd_address -offset 0x00000000 -range 0x10000000 -target_address_space [get_bd_addr_spaces pl_pcie_nvme_top_wra_0/m_axil_csr] [get_bd_addr_segs qdma_0/S_AXI_LITE_CSR/CTL0] -force
  assign_bd_address -offset 0x00000000 -range 0x10000000 -target_address_space [get_bd_addr_spaces pl_pcie_nvme_top_wra_0/m_axil_ecam] [get_bd_addr_segs qdma_0/S_AXI_LITE/CTL0] -force
  assign_bd_address -offset 0x080000000000 -range 0x040000000000 -target_address_space [get_bd_addr_spaces nvme_cq_router/M_DATA] [get_bd_addr_segs axi_nvme_card/Reg] -force
  assign_bd_address -offset 0x0FFFF4020000 -range 0x00010000 -target_address_space [get_bd_addr_spaces nvme_cq_router/M_CQ] [get_bd_addr_segs axi_nvme_cq/Reg] -force
  assign_bd_address -offset 0x000000000000 -range 0x080000000000 -target_address_space [get_bd_addr_spaces nvme_cq_router/M_DATA] [get_bd_addr_segs axi_nvme_host/Reg] -force
  assign_bd_address -offset 0x0FFFF5000000 -range 0x01000000 -target_address_space [get_bd_addr_spaces nvme_cq_router/M_DATA] [get_bd_addr_segs axi_nvme_prp/Reg] -force
  assign_bd_address -offset 0x0FFFF4040000 -range 0x00040000 -target_address_space [get_bd_addr_spaces nvme_cq_router/M_DATA] [get_bd_addr_segs axi_nvme_sq/Reg] -force
  assign_bd_address -offset 0x0FFFFFFFC000 -range 0x00004000 -target_address_space [get_bd_addr_spaces nvme_cq_router/M_DATA] [get_bd_addr_segs pl_pcie_nvme_top_wra_0/s_axi_dma/reg0] -force
  assign_bd_address -offset 0x100000000000 -range 0x100000000000 -target_address_space [get_bd_addr_spaces axi_nvme_mmio] [get_bd_addr_segs qdma_0/S_AXI_BRIDGE/BAR0] -force
  assign_bd_address -offset 0x80000000 -range 0x00100000 -target_address_space [get_bd_addr_spaces axi_nvme_mmio] [get_bd_addr_segs qdma_0/S_AXI_BRIDGE/BAR1] -force


  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
  close_bd_design $design_name
  return 0
}
# End of cr_bd_design_plnvme()
