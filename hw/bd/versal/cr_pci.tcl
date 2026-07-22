######################################################################################
# This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
# 
# MIT Licence
# Copyright (c) 2025, Systems Group, ETH Zurich
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

# Static layer
proc cr_bd_design_static { parentCell } {
  upvar #0 cfg cnfg

  set design_name design_static

  common::send_msg_id "BD_TCL-003" "INFO" "Currently there is no design <$design_name> in project, so creating one..."

  create_bd_design $design_name

  set bCheckIPsPassed 1
  ########################################################################################################
  # CHECK IPs
  ########################################################################################################
  set bCheckIPs 1
  # Select the IP versions available in this Vivado (version-adaptive):
  #   axi_noc     1.1 on 2024.2, 1.0 on 2023.2/2022.1
  #   versal_cips 3.4 on 2023.2/2024.2, 3.2 on 2022.1  (the VCK5000 CPM4 QDMA only brings up
  #               its PCIe under 2022.1/CIPS 3.2, so the vck5000 flow must run on 2022.1)
  set noc_vlnv  [lindex [lsort [get_ipdefs -all xilinx.com:ip:axi_noc:*]] end]
  set cips_vlnv [lindex [lsort [get_ipdefs -all xilinx.com:ip:versal_cips:*]] end]

  if { $bCheckIPs == 1 } {
    set list_check_ips "\
      xilinx.com:ip:proc_sys_reset:5.0\
      xilinx.com:ip:util_vector_logic:2.0\
      $cips_vlnv\
      $noc_vlnv\
      xilinx.com:ip:smartconnect:1.0\
      xilinx.com:ip:xlconstant:1.1\
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
  # Shell config
  set axi_main [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_main ]
  set_property -dict [ list \
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
  ] $axi_main

  # Static config
  set axi_cnfg [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_cnfg ]
  set_property -dict [ list \
    CONFIG.ADDR_WIDTH {64} \
    CONFIG.DATA_WIDTH {32} \
    CONFIG.PROTOCOL {AXI4LITE} \
  ] $axi_cnfg

  # Debug Hub IP control
  set axi_debug_hub [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_debug_hub ]
  set_property -dict [ list \
    CONFIG.ADDR_WIDTH {64} \
    CONFIG.DATA_WIDTH {128} \
    CONFIG.PROTOCOL {AXI4} \
  ] $axi_debug_hub

  # QDMA status --- boundary kept identical to the V80 (eqdma_qsts). On the VCK5000 the
  # H2C status is derived internally from the CPM4 traffic-manager descriptor status.
  set h2c_status [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:eqdma_qsts_rtl:1.0 h2c_status ]
  set c2h_status [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:qdma_c2h_status_rtl:1.0 c2h_status ]

  # PCIe
  set pcie_clk [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 pcie_clk ]
  set_property -dict [ list \
    CONFIG.FREQ_HZ {100000000} \
  ] $pcie_clk
  set pcie_gt [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gt_rtl:1.0 pcie_gt ]

  # Data streams
  # NOTE: design_static's external boundary is kept identical across devices (eQDMA-style,
  # matching the V80). On the VCK5000 (CPM4, plain QDMA) the differences are converted
  # internally within this BD (see the vck5000 adapter block below), so the static_top
  # template and the qdma_rd/wr wrappers are device-independent.
  set s_axis_c2h [ create_bd_intf_port -mode Slave -vlnv xilinx.com:display_eqdma:s_axis_c2h_rtl:1.0 s_axis_c2h ]
  set m_axis_h2c [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_eqdma:m_axis_h2c_rtl:1.0 m_axis_h2c ]

  # Command streams
  set dsc_bypass_h2c [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_bypass_h2c ]
  set dsc_bypass_c2h [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_bypass_c2h ]

  # PR descriptor
  set dsc_pr [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_pr ]

  # User interrupts
  set usr_irq [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:qdma_usr_irq_rtl:1.0 usr_irq ]

  # VCK5000 only: physical DDR4 + 200 MHz system clock for the integrated DDR MC that backs
  # the CPM_PCIE_NOC path (see axi_noc_0 below). These are the only added design_static ports.
  if {$cnfg(fdev) eq "vck5000"} {
    create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 c0_ddr4
    set c0_sys_clk_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 c0_sys_clk_0 ]
    set_property CONFIG.FREQ_HZ {200000000} $c0_sys_clk_0
  }

########################################################################################################
# Create ports
########################################################################################################

  # Shell reset
  set xresetn [ create_bd_port -dir O -type rst xresetn ]

  # Static layer reset
  set sresetn [ create_bd_port -dir O -type rst sresetn ]

  # Reset after PR
  create_bd_port -dir I -type rst eos_resetn
  set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports eos_resetn]

  # Main clock
  set xclk [ create_bd_port -dir O -type clk xclk ]
  set_property -dict [ list \
    CONFIG.ASSOCIATED_BUSIF {m_axis_h2c:s_axis_c2h:axi_cnfg:axi_main:axi_debug_hub} \
    CONFIG.ASSOCIATED_RESET {xresetn:sresetn:eos_resetn} \
  ] $xclk

  # End-of-startup signal from PMC (asserted after parcial reconfiguration is done)
  set eos_pmc [ create_bd_port -dir O -type rst eos_pmc ]

########################################################################################################
# Create interconnect and components
########################################################################################################

  # Reset controllers
  set proc_sys_reset_s [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_s ]
  set proc_sys_reset_x [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_x ]

  # Constants
  set const_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_0 ]
  set_property CONFIG.CONST_VAL {0} $const_0

  set const_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_1 ]
  set_property CONFIG.CONST_VAL {1} $const_1

  # CIPS
  if {$cnfg(fdev) eq "v80"} {
    # If using a single Gen5x8 QDMA controller, PCIE1 must be selected to ensure compliance with PCI SIG
    # For more details, see: https://xilinx.github.io/AVED/latest/AVED%2BV80%2B-%2BCIPS%2BConfiguration.html#cpm5-basic-configuration
    if {$cnfg(pcie_gen) eq 5} {
      set versal_cips_0 [ create_bd_cell -type ip -vlnv $cips_vlnv versal_cips_0 ]
      set_property -dict [list \
        CONFIG.BOOT_MODE {Custom} \
        CONFIG.CLOCK_MODE {Custom} \
        CONFIG.CPM_CONFIG { \
          CPM_PCIE0_MODES {None} \
          CPM_PCIE1_DMA_INTF {AXI_MM_and_AXI_Stream} \
          CPM_PCIE1_DSC_BYPASS_RD {1} \
          CPM_PCIE1_DSC_BYPASS_WR {1} \
          CPM_PCIE1_LANE_REVERSAL_EN {0} \
          CPM_PCIE1_MODES {DMA} \
          CPM_PCIE1_MODE_SELECTION {Advanced} \
          CPM_PCIE1_PF0_BAR0_QDMA_64BIT {1} \
          CPM_PCIE1_PF0_BAR0_QDMA_AXCACHE {0} \
          CPM_PCIE1_PF0_BAR0_QDMA_PREFETCHABLE {1} \
          CPM_PCIE1_PF0_BAR0_QDMA_SCALE {Megabytes} \
          CPM_PCIE1_PF0_BAR0_QDMA_SIZE {1} \
          CPM_PCIE1_PF0_BAR0_QDMA_STEERING {CPM_PCIE_NOC_0} \
          CPM_PCIE1_PF0_BAR0_QDMA_TYPE {AXI_Bridge_Master} \
          CPM_PCIE1_PF0_BAR1_QDMA_AXCACHE {0} \
          CPM_PCIE1_PF0_BAR2_QDMA_AXCACHE {0} \
          CPM_PCIE1_PF0_BAR2_QDMA_64BIT {1} \
          CPM_PCIE1_PF0_BAR2_QDMA_ENABLED {1} \
          CPM_PCIE1_PF0_BAR2_QDMA_TYPE {DMA} \
          CPM_PCIE1_PF0_BAR3_QDMA_AXCACHE {0} \
          CPM_PCIE1_PF0_BAR4_QDMA_64BIT {1} \
          CPM_PCIE1_PF0_BAR4_QDMA_AXCACHE {0} \
          CPM_PCIE1_PF0_BAR4_QDMA_ENABLED {1} \
          CPM_PCIE1_PF0_BAR4_QDMA_PREFETCHABLE {1} \
          CPM_PCIE1_PF0_BAR4_QDMA_SCALE {Megabytes} \
          CPM_PCIE1_PF0_BAR4_QDMA_SIZE {256} \
          CPM_PCIE1_PF0_BAR4_QDMA_STEERING {CPM_PCIE_NOC_0} \
          CPM_PCIE1_PF0_BAR5_QDMA_AXCACHE {0} \
          CPM_PCIE1_PF0_MSIX_CAP_TABLE_SIZE {0x1F} \
          CPM_PCIE1_PF0_PCIEBAR2AXIBAR_QDMA_0 {0x020100000000} \
          CPM_PCIE1_PF0_PCIEBAR2AXIBAR_QDMA_2 {0x0} \
          CPM_PCIE1_PF0_PCIEBAR2AXIBAR_QDMA_4 {0x020800000000} \
          CPM_PCIE1_PL_LINK_CAP_MAX_LINK_WIDTH {X8} \
          CPM_PCIE1_MAX_LINK_SPEED {32.0_GT/s} \
          CPM_PCIE1_REF_CLK_FREQ {100_MHz} \
          PS_USE_PS_NOC_PCI_1 {1} \
        } \
        CONFIG.DEVICE_INTEGRITY_MODE {Custom} \
        CONFIG.PS_PMC_CONFIG { \
          BOOT_MODE {Custom} \
          CLOCK_MODE {Custom} \
          DESIGN_MODE {1} \
          DEVICE_INTEGRITY_MODE {Custom} \
          PCIE_APERTURES_DUAL_ENABLE {0} \
          PCIE_APERTURES_SINGLE_ENABLE {1} \
          PMC_CRP_PL0_REF_CTRL_FREQMHZ {33.3333333} \
          PMC_QSPI_FBCLK {{ENABLE 1} {IO {PMC_MIO 6}}} \
          PMC_QSPI_PERIPHERAL_ENABLE {0} \
          PMC_REF_CLK_FREQMHZ {33.333333} \
          PMC_SD0 {{CD_ENABLE 0} {CD_IO {PMC_MIO 24}} {POW_ENABLE 0} {POW_IO {PMC_MIO 17}} {RESET_ENABLE 0} {RESET_IO {PMC_MIO 17}} {WP_ENABLE 0} {WP_IO {PMC_MIO 25}}} \
          PMC_SD0_PERIPHERAL {{CLK_100_SDR_OTAP_DLY 0x00} {CLK_200_SDR_OTAP_DLY 0x00} {CLK_50_DDR_ITAP_DLY 0x00} {CLK_50_DDR_OTAP_DLY 0x00} {CLK_50_SDR_ITAP_DLY 0x00} {CLK_50_SDR_OTAP_DLY 0x00} {ENABLE 0}\
        {IO {PMC_MIO 13 .. 25}}} \
          PMC_SD0_SLOT_TYPE {SD 2.0} \
          PMC_SMAP_PERIPHERAL {{ENABLE 0} {IO {32 Bit}}} \
          PMC_USE_NOC_PMC_AXI0 {1} \
          PMC_USE_PMC_NOC_AXI0 {1} \
          PS_USE_STARTUP {1} \
          PS_BOARD_INTERFACE {Custom} \
          PS_CRL_CPM_TOPSW_REF_CTRL_FREQMHZ {1000} \
          PS_PCIE1_PERIPHERAL_ENABLE {0} \
          PS_PCIE2_PERIPHERAL_ENABLE {1} \
          PS_PCIE_EP_RESET1_IO {PMC_MIO 24} \
          PS_PCIE_EP_RESET2_IO {PMC_MIO 25} \
          PS_PCIE_RESET {ENABLE 1} \
          PS_USE_PMCPL_CLK0 {1} \
          SMON_ALARMS {Set_Alarms_On} \
          SMON_ENABLE_TEMP_AVERAGING {0} \
          SMON_OT {{THRESHOLD_LOWER -25} {THRESHOLD_UPPER 125}} \
          SMON_TEMP_AVERAGING_SAMPLES {0} \
          SMON_USER_TEMP {{THRESHOLD_LOWER 0} {THRESHOLD_UPPER 125} {USER_ALARM_TYPE window}} \
        } \
      ] $versal_cips_0
    } elseif {$cnfg(pcie_gen) eq 4} {
      # And, if using a Gen4x16 QDMA controller, PCIE0 must be selected
      set versal_cips_0 [ create_bd_cell -type ip -vlnv $cips_vlnv versal_cips_0 ]
      set_property -dict [list \
        CONFIG.BOOT_MODE {Custom} \
        CONFIG.CLOCK_MODE {Custom} \
        CONFIG.CPM_CONFIG { \
          CPM_PCIE1_MODES {None} \
          CPM_PCIE0_DMA_INTF {AXI_MM_and_AXI_Stream} \
          CPM_PCIE0_DSC_BYPASS_RD {1} \
          CPM_PCIE0_DSC_BYPASS_WR {1} \
          CPM_PCIE0_LANE_REVERSAL_EN {0} \
          CPM_PCIE0_MODES {DMA} \
          CPM_PCIE0_MODE_SELECTION {Advanced} \
          CPM_PCIE0_PF0_BAR0_QDMA_64BIT {1} \
          CPM_PCIE0_PF0_BAR0_QDMA_AXCACHE {0} \
          CPM_PCIE0_PF0_BAR0_QDMA_PREFETCHABLE {1} \
          CPM_PCIE0_PF0_BAR0_QDMA_SCALE {Megabytes} \
          CPM_PCIE0_PF0_BAR0_QDMA_SIZE {1} \
          CPM_PCIE0_PF0_BAR0_QDMA_STEERING {CPM_PCIE_NOC_0} \
          CPM_PCIE0_PF0_BAR0_QDMA_TYPE {AXI_Bridge_Master} \
          CPM_PCIE0_PF0_BAR1_QDMA_AXCACHE {0} \
          CPM_PCIE0_PF0_BAR2_QDMA_AXCACHE {0} \
          CPM_PCIE0_PF0_BAR2_QDMA_64BIT {1} \
          CPM_PCIE0_PF0_BAR2_QDMA_ENABLED {1} \
          CPM_PCIE0_PF0_BAR2_QDMA_TYPE {DMA} \
          CPM_PCIE0_PF0_BAR3_QDMA_AXCACHE {0} \
          CPM_PCIE0_PF0_BAR4_QDMA_64BIT {1} \
          CPM_PCIE0_PF0_BAR4_QDMA_AXCACHE {0} \
          CPM_PCIE0_PF0_BAR4_QDMA_ENABLED {1} \
          CPM_PCIE0_PF0_BAR4_QDMA_PREFETCHABLE {1} \
          CPM_PCIE0_PF0_BAR4_QDMA_SCALE {Megabytes} \
          CPM_PCIE0_PF0_BAR4_QDMA_SIZE {256} \
          CPM_PCIE0_PF0_BAR4_QDMA_STEERING {CPM_PCIE_NOC_0} \
          CPM_PCIE0_PF0_BAR5_QDMA_AXCACHE {0} \
          CPM_PCIE0_PF0_MSIX_CAP_TABLE_SIZE {0x1F} \
          CPM_PCIE0_PF0_PCIEBAR2AXIBAR_QDMA_0 {0x020100000000} \
          CPM_PCIE0_PF0_PCIEBAR2AXIBAR_QDMA_2 {0x0} \
          CPM_PCIE0_PF0_PCIEBAR2AXIBAR_QDMA_4 {0x020800000000} \
          CPM_PCIE0_PL_LINK_CAP_MAX_LINK_WIDTH {X16} \
          CPM_PCIE0_MAX_LINK_SPEED {16.0_GT/s} \
          CPM_PCIE0_REF_CLK_FREQ {100_MHz} \
          PS_USE_PS_NOC_PCI_1 {1} \
        } \
        CONFIG.DEVICE_INTEGRITY_MODE {Custom} \
        CONFIG.PS_PMC_CONFIG { \
          BOOT_MODE {Custom} \
          CLOCK_MODE {Custom} \
          DESIGN_MODE {1} \
          DEVICE_INTEGRITY_MODE {Custom} \
          PCIE_APERTURES_DUAL_ENABLE {0} \
          PCIE_APERTURES_SINGLE_ENABLE {1} \
          PMC_CRP_PL0_REF_CTRL_FREQMHZ {33.3333333} \
          PMC_QSPI_FBCLK {{ENABLE 1} {IO {PMC_MIO 6}}} \
          PMC_QSPI_PERIPHERAL_ENABLE {0} \
          PMC_REF_CLK_FREQMHZ {33.333333} \
          PMC_SD0 {{CD_ENABLE 0} {CD_IO {PMC_MIO 24}} {POW_ENABLE 0} {POW_IO {PMC_MIO 17}} {RESET_ENABLE 0} {RESET_IO {PMC_MIO 17}} {WP_ENABLE 0} {WP_IO {PMC_MIO 25}}} \
          PMC_SD0_PERIPHERAL {{CLK_100_SDR_OTAP_DLY 0x00} {CLK_200_SDR_OTAP_DLY 0x00} {CLK_50_DDR_ITAP_DLY 0x00} {CLK_50_DDR_OTAP_DLY 0x00} {CLK_50_SDR_ITAP_DLY 0x00} {CLK_50_SDR_OTAP_DLY 0x00} {ENABLE 0}\
        {IO {PMC_MIO 13 .. 25}}} \
          PMC_SD0_SLOT_TYPE {SD 2.0} \
          PMC_SMAP_PERIPHERAL {{ENABLE 0} {IO {32 Bit}}} \
          PMC_USE_NOC_PMC_AXI0 {1} \
          PMC_USE_PMC_NOC_AXI0 {1} \
          PS_USE_STARTUP {1} \
          PS_BOARD_INTERFACE {Custom} \
          PS_CRL_CPM_TOPSW_REF_CTRL_FREQMHZ {1000} \
          PS_PCIE1_PERIPHERAL_ENABLE {1} \
          PS_PCIE2_PERIPHERAL_ENABLE {0} \
          PS_PCIE_EP_RESET1_IO {PMC_MIO 24} \
          PS_PCIE_EP_RESET2_IO {PMC_MIO 25} \
          PS_PCIE_RESET {ENABLE 1} \
          PS_USE_PMCPL_CLK0 {1} \
          SMON_ALARMS {Set_Alarms_On} \
          SMON_ENABLE_TEMP_AVERAGING {0} \
          SMON_OT {{THRESHOLD_LOWER -25} {THRESHOLD_UPPER 125}} \
          SMON_TEMP_AVERAGING_SAMPLES {0} \
          SMON_USER_TEMP {{THRESHOLD_LOWER 0} {THRESHOLD_UPPER 125} {USER_ALARM_TYPE window}} \
        } \
      ] $versal_cips_0
    } else {
      puts "ERROR: Unsupported PCIe configuration: Gen$cnfg(pcie_gen). Supported configurations for V80 are Gen4x16 and Gen5x8."
      exit 1
    }
  } elseif {$cnfg(fdev) eq "vck5000"} {
    # VCK5000 (Versal VC1902) uses CPM4 (not CPM5). CPM4 QDMA is exposed via PCIE0 in
    # QDMA functional mode, giving the same descriptor-bypass + AXI_MM_and_AXI_Stream
    # interface family Coyote expects. The VCK5000 CPM4 link is PCIe Gen4x8 (X8, 16 GT/s).
    #
    # Built on versal_cips 3.2 (Vivado 2022.1) -- the only version that brings up the CPM4
    # QDMA PCIe on this board. The CPM_PCIE0_PF0_BAR{0,4}_QDMA_STEERING sub-keys are 3.4-only
    # (3.2 emits "Invalid parameter ... Ignoring") and are intentionally omitted: on 3.2 the
    # BAR-to-CPM_PCIE_NOC steering is implicit via PS_USE_PS_NOC_PCI_0 {1} below plus the
    # axi_noc_0 S00/S01 CONNECTIONS/DEST_IDS and the assign_bd_address mappings. This matches
    # the proven 2022.1/3.2 CPM4-QDMA config (opendpu cips_config.tcl), which also has no STEERING.
    set versal_cips_0 [ create_bd_cell -type ip -vlnv $cips_vlnv versal_cips_0 ]
    set_property -dict [list \
      CONFIG.BOOT_MODE {Custom} \
      CONFIG.CLOCK_MODE {Custom} \
      CONFIG.CPM_CONFIG { \
        CPM_PCIE1_MODES {None} \
        CPM_PCIE0_FUNCTIONAL_MODE {QDMA} \
        CPM_PCIE0_MODES {DMA} \
        CPM_PCIE0_MODE_SELECTION {Advanced} \
        CPM_PCIE0_DMA_INTF {AXI_MM_and_AXI_Stream} \
        CPM_PCIE0_DSC_BYPASS_RD {1} \
        CPM_PCIE0_DSC_BYPASS_WR {1} \
        CPM_PCIE0_MSI_X_OPTIONS {MSI-X_Internal} \
        CPM_PCIE0_LANE_REVERSAL_EN {0} \
        CPM_PCIE0_PF0_BAR0_QDMA_64BIT {1} \
        CPM_PCIE0_PF0_BAR0_QDMA_AXCACHE {0} \
        CPM_PCIE0_PF0_BAR0_QDMA_PREFETCHABLE {1} \
        CPM_PCIE0_PF0_BAR0_QDMA_SCALE {Megabytes} \
        CPM_PCIE0_PF0_BAR0_QDMA_SIZE {1} \
        CPM_PCIE0_PF0_BAR0_QDMA_TYPE {AXI_Bridge_Master} \
        CPM_PCIE0_PF0_BAR1_QDMA_AXCACHE {0} \
        CPM_PCIE0_PF0_BAR2_QDMA_AXCACHE {0} \
        CPM_PCIE0_PF0_BAR2_QDMA_64BIT {1} \
        CPM_PCIE0_PF0_BAR2_QDMA_ENABLED {1} \
        CPM_PCIE0_PF0_BAR2_QDMA_TYPE {DMA} \
        CPM_PCIE0_PF0_BAR3_QDMA_AXCACHE {0} \
        CPM_PCIE0_PF0_BAR4_QDMA_64BIT {1} \
        CPM_PCIE0_PF0_BAR4_QDMA_AXCACHE {0} \
        CPM_PCIE0_PF0_BAR4_QDMA_ENABLED {1} \
        CPM_PCIE0_PF0_BAR4_QDMA_PREFETCHABLE {1} \
        CPM_PCIE0_PF0_BAR4_QDMA_SCALE {Megabytes} \
        CPM_PCIE0_PF0_BAR4_QDMA_SIZE {256} \
        CPM_PCIE0_PF0_BAR5_QDMA_AXCACHE {0} \
        CPM_PCIE0_PF0_MSIX_CAP_TABLE_SIZE {0x1F} \
        CPM_PCIE0_PF0_PCIEBAR2AXIBAR_QDMA_0 {0x020100000000} \
        CPM_PCIE0_PF0_PCIEBAR2AXIBAR_QDMA_2 {0x0} \
        CPM_PCIE0_PF0_PCIEBAR2AXIBAR_QDMA_4 {0x020800000000} \
        CPM_PCIE0_PL_LINK_CAP_MAX_LINK_WIDTH {X16} \
        CPM_PCIE0_MAX_LINK_SPEED {8.0_GT/s} \
        CPM_PCIE0_REF_CLK_FREQ {100_MHz} \
        PS_USE_PS_NOC_PCI_0 {1} \
      } \
      CONFIG.DEVICE_INTEGRITY_MODE {Custom} \
      CONFIG.PS_PMC_CONFIG { \
        BOOT_MODE {Custom} \
        CLOCK_MODE {Custom} \
        DESIGN_MODE {1} \
        DEVICE_INTEGRITY_MODE {Custom} \
        PCIE_APERTURES_DUAL_ENABLE {0} \
        PCIE_APERTURES_SINGLE_ENABLE {1} \
        PMC_CRP_PL0_REF_CTRL_FREQMHZ {33.3333333} \
        PMC_REF_CLK_FREQMHZ {33.333333} \
        PMC_USE_NOC_PMC_AXI0 {1} \
        PMC_USE_PMC_NOC_AXI0 {1} \
        PS_USE_STARTUP {1} \
        PS_BOARD_INTERFACE {Custom} \
        PS_CRL_CPM_TOPSW_REF_CTRL_FREQMHZ {775} \
        PS_PCIE1_PERIPHERAL_ENABLE {1} \
        PS_PCIE2_PERIPHERAL_ENABLE {0} \
        PS_PCIE_EP_RESET1_IO {PMC_MIO 38} \
        PS_PCIE_RESET {ENABLE 1} \
        PS_USE_PMCPL_CLK0 {1} \
        SMON_ALARMS {Set_Alarms_On} \
        SMON_ENABLE_TEMP_AVERAGING {0} \
        SMON_OT {{THRESHOLD_LOWER -25} {THRESHOLD_UPPER 125}} \
        SMON_TEMP_AVERAGING_SAMPLES {0} \
        SMON_USER_TEMP {{THRESHOLD_LOWER 0} {THRESHOLD_UPPER 125} {USER_ALARM_TYPE window}} \
      } \
    ] $versal_cips_0
  } else {
    puts "ERROR: Unsupported FPGA part: $cnfg(fdev)"
    exit 1
  }

  # AXI NoC
  # The NoC is used to route AXI-MM interfaces from the QDMA to the shell
  # Additionally, it will perform clock-domain crossing, reducing the frequency from 1000 MHz to shell frequency
  set axi_noc_0 [ create_bd_cell -type ip -vlnv $noc_vlnv axi_noc_0 ]
  if {$cnfg(fdev) eq "vck5000"} {
    # VCK5000 CPM4: the CPM_PCIE_NOC path MUST reach a real NoC-backed memory target
    # (integrated DDR memory controller + a small BRAM) or the CPM enumerates as rev-ff
    # ghost functions. So axi_noc_0 hosts an integrated DDRMC (MC_0, 8 GB DDR4-3200 16Gb x16,
    # board interfaces ddr4_sdram_c0 / ddr4_c0_sysclk) plus one extra MI (M04_AXI) that drives
    # an on-chip BRAM. MC config is taken verbatim from cr_ddr.tcl (known-good on this board
    # part / Vivado 2023.2). NUM_MI 4 -> 5 (add M04_AXI BRAM); NUM_MC 0 -> 1 (+ NUM_MCP 4).
    set_property -dict [list \
      CONFIG.MI_SIDEBAND_PINS {0} \
      CONFIG.NUM_CLKS {5} \
      CONFIG.NUM_HBM_BLI {0} \
      CONFIG.NUM_MI {5} \
      CONFIG.NUM_SI {3} \
      CONFIG.NUM_MC {1} \
      CONFIG.NUM_MCP {4} \
      CONFIG.SI_SIDEBAND_PINS {} \
      CONFIG.MC_BOARD_INTRF_EN {true} \
      CONFIG.MC_COMPONENT_DENSITY {16Gb} \
      CONFIG.MC_COMPONENT_WIDTH {x16} \
      CONFIG.MC_MEM_DEVICE_WIDTH {x16} \
      CONFIG.MC_MEMORY_DEVICE_DENSITY {16Gb} \
      CONFIG.MC_MEMORY_DENSITY {8GB} \
      CONFIG.MC_MEMORY_SPEEDGRADE {DDR4-3200AA(22-22-22)} \
      CONFIG.MC_INPUT_FREQUENCY0 {200.000} \
      CONFIG.MC_INPUTCLK0_PERIOD {5000} \
      CONFIG.MC_ROWADDRESSWIDTH {17} \
      CONFIG.MC_USER_DEFINED_ADDRESS_MAP {17RA-2BA-1BG-10CA} \
      CONFIG.MC_CHAN_REGION0 {DDR_LOW0} \
      CONFIG.CH0_DDR4_0_BOARD_INTERFACE {ddr4_sdram_c0} \
      CONFIG.sys_clk0_BOARD_INTERFACE {ddr4_c0_sysclk} \
    ] $axi_noc_0
  } else {
    set_property -dict [list \
      CONFIG.MI_SIDEBAND_PINS {0} \
      CONFIG.NUM_CLKS {5} \
      CONFIG.NUM_HBM_BLI {0} \
      CONFIG.NUM_MI {4} \
      CONFIG.NUM_SI {3} \
      CONFIG.SI_SIDEBAND_PINS {} \
    ] $axi_noc_0
  }

  set_property -dict [ list \
    CONFIG.APERTURES {{0x201_0000_0000 1G}} \
    CONFIG.CATEGORY {pl} \
  ] [get_bd_intf_pins /axi_noc_0/M00_AXI]

  set_property -dict [ list \
    CONFIG.APERTURES {{0x208_0000_0000 1G}} \
    CONFIG.CATEGORY {pl} \
  ] [get_bd_intf_pins /axi_noc_0/M01_AXI]

  set_property -dict [ list \
    CONFIG.DATA_WIDTH {128} \
    CONFIG.AWUSER_WIDTH {0} \
    CONFIG.ARUSER_WIDTH {0} \
    CONFIG.CATEGORY {ps_pmc} \
  ] [get_bd_intf_pins /axi_noc_0/M02_AXI]

  set_property -dict [ list \
    CONFIG.APERTURES {{0x202_4000_0000 1G}} \
    CONFIG.DATA_WIDTH {128} \
    CONFIG.AWUSER_WIDTH {0} \
    CONFIG.ARUSER_WIDTH {0} \
    CONFIG.CATEGORY {pl} \
  ] [get_bd_intf_pins /axi_noc_0/M03_AXI]

  if {$cnfg(fdev) eq "vck5000"} {
    # M04_AXI -> on-chip BRAM (512-bit). Placed at a distinct aperture, away from the
    # register apertures (axi_cnfg 0x201.., axi_main 0x208.., debug 0x202_4..).
    set_property -dict [ list \
      CONFIG.APERTURES {{0x203_0000_0000 1G}} \
      CONFIG.DATA_WIDTH {512} \
      CONFIG.CATEGORY {pl} \
    ] [get_bd_intf_pins /axi_noc_0/M04_AXI]
  }

  # CPM_PCIE_NOC_0 is used for shell and static layer registers
  if {$cnfg(fdev) eq "vck5000"} {
    # Additionally reaches the integrated DDR (MC_0) and the BRAM (M04_AXI) so the CPM4
    # bridge/QDMA master has a live NoC-backed memory target (required for enumeration).
    set_property -dict [ list \
      CONFIG.CONNECTIONS {M00_AXI {read_bw {8} write_bw {8} read_avg_burst {4} write_avg_burst {4}} M01_AXI {read_bw {8} write_bw {8} read_avg_burst {4} write_avg_burst {4}} M04_AXI {read_bw {1720} write_bw {1720} read_avg_burst {4} write_avg_burst {4}} MC_0 {read_bw {1720} write_bw {1720} read_avg_burst {4} write_avg_burst {4}}} \
      CONFIG.DEST_IDS {M01_AXI:0x0:M00_AXI:0x40:M04_AXI:0x100:MC_0:0x140} \
      CONFIG.NOC_PARAMS {} \
      CONFIG.CATEGORY {ps_pcie} \
    ] [get_bd_intf_pins /axi_noc_0/S00_AXI]
  } else {
    set_property -dict [ list \
      CONFIG.CONNECTIONS {M00_AXI {read_bw {8} write_bw {8} read_avg_burst {4} write_avg_burst {4}} M01_AXI {read_bw {8} write_bw {8} read_avg_burst {4} write_avg_burst {4}}} \
      CONFIG.DEST_IDS {M01_AXI:0x0:M00_AXI:0x40} \
      CONFIG.NOC_PARAMS {} \
      CONFIG.CATEGORY {ps_pcie} \
    ] [get_bd_intf_pins /axi_noc_0/S00_AXI]
  }

  # CPM_PCIE_NOC_1 is used for QDMA MM data transfers
  if {$cnfg(fdev) eq "vck5000"} {
    # Also reaches the integrated DDR (MC_0) and the BRAM (M04_AXI) --- the QDMA MM data path.
    set_property -dict [ list \
      CONFIG.CONNECTIONS {M02_AXI {read_bw {6400} write_bw {6400} read_avg_burst {64} write_avg_burst {64}} M04_AXI {read_bw {1720} write_bw {1720} read_avg_burst {4} write_avg_burst {4}} MC_0 {read_bw {1720} write_bw {1720} read_avg_burst {4} write_avg_burst {4}}} \
      CONFIG.DEST_IDS {M02_AXI:0x80:M04_AXI:0x100:MC_0:0x140} \
      CONFIG.NOC_PARAMS {} \
      CONFIG.CATEGORY {ps_pcie} \
    ] [get_bd_intf_pins /axi_noc_0/S01_AXI]
  } else {
    set_property -dict [ list \
      CONFIG.CONNECTIONS {M02_AXI {read_bw {6400} write_bw {6400} read_avg_burst {64} write_avg_burst {64}}} \
      CONFIG.DEST_IDS {M02_AXI:0x80} \
      CONFIG.NOC_PARAMS {} \
      CONFIG.CATEGORY {ps_pcie} \
    ] [get_bd_intf_pins /axi_noc_0/S01_AXI]
  }

  # PMC_NOC is used for configuring the Debug Hub IP (which sets up ILAs, VIOs etc.)
  set_property -dict [ list \
    CONFIG.CONNECTIONS {M03_AXI {read_bw {1500} write_bw {1500} read_avg_burst {4} write_avg_burst {4}}} \
    CONFIG.DEST_IDS {M03_AXI:0x120} \
    CONFIG.NOC_PARAMS {} \
    CONFIG.CATEGORY {ps_pmc} \
  ] [get_bd_intf_pins /axi_noc_0/S02_AXI]

  set_property -dict [ list \
    CONFIG.ASSOCIATED_BUSIF {S00_AXI} \
  ] [get_bd_pins /axi_noc_0/aclk0]

  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {S01_AXI} \
  ] [get_bd_pins /axi_noc_0/aclk1]

  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {S02_AXI} \
  ] [get_bd_pins /axi_noc_0/aclk2]

  if {$cnfg(fdev) eq "vck5000"} {
    # Shell-clock domain masters: registers (M00/M01), debug hub (M03) and the BRAM (M04).
    # The integrated DDR MC needs no aclk (it runs off sys_clk0).
    set_property -dict [ list \
      CONFIG.ASSOCIATED_BUSIF {M00_AXI:M01_AXI:M03_AXI:M04_AXI} \
    ] [get_bd_pins /axi_noc_0/aclk3]
  } else {
    set_property -dict [ list \
      CONFIG.ASSOCIATED_BUSIF {M00_AXI:M01_AXI:M03_AXI} \
    ] [get_bd_pins /axi_noc_0/aclk3]
  }

  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF {M02_AXI} \
  ] [get_bd_pins /axi_noc_0/aclk4]

  # AXI SmartSwitch, connecting the NoC outputs to BD output interfaces
  set smartconnect_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0 ]
  set_property CONFIG.NUM_SI {1} $smartconnect_0
  set_property CONFIG.ADVANCED_PROPERTIES {__experimental_features__ {disable_low_area_mode 1} __view__ {functional {S00_Entry {SUPPORTS_WRAP 1 SUPPORTS_NARROW_BURST 1}}}} $smartconnect_0
  
  set smartconnect_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_1 ]
  set_property CONFIG.NUM_SI {1} $smartconnect_1
  set_property CONFIG.ADVANCED_PROPERTIES {__experimental_features__ {disable_low_area_mode 1} __view__ {functional {S00_Entry {SUPPORTS_WRAP 1 SUPPORTS_NARROW_BURST 1}}}} $smartconnect_1

  # VCK5000 only: on-chip BRAM reached from the CPM_PCIE_NOC path via axi_noc_0/M04_AXI.
  # 512-bit AXI BRAM controller + 512 KB URAM-backed memory (mirrors mini_bd.tcl's pl_mem).
  if {$cnfg(fdev) eq "vck5000"} {
    set bram_ctrl_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 bram_ctrl_0 ]
    set_property -dict [ list \
      CONFIG.DATA_WIDTH {512} \
      CONFIG.SINGLE_PORT_BRAM {1} \
    ] $bram_ctrl_0
    set bram_mem_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:emb_mem_gen:1.0 bram_mem_0 ]
    set_property -dict [ list \
      CONFIG.MEMORY_PRIMITIVE {URAM} \
      CONFIG.MEMORY_TYPE {Single_Port_RAM} \
    ] $bram_mem_0
    connect_bd_intf_net [get_bd_intf_pins bram_ctrl_0/BRAM_PORTA] [get_bd_intf_pins bram_mem_0/BRAM_PORTA]
  }

  # Main clock gen
  create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wizard:1.0 clk_wiz_0
  set cmd "set_property -dict \[list \
    CONFIG.CLKOUT_DRIVES {BUFG} \
    CONFIG.CLKOUT_REQUESTED_OUT_FREQUENCY {[expr {$cnfg(sclk_f)}]} \
    CONFIG.CLKOUT_USED {true} \
    CONFIG.PRIM_SOURCE {Global_Buffer} \
  ] \[get_bd_cells clk_wiz_0]"
  eval $cmd

########################################################################################################
# Create interface connections
########################################################################################################
  if {$cnfg(fdev) eq "vck5000"} {
    # VCK5000 CPM4 QDMA (PCIE0). Directly-mappable interfaces connect straight through; the
    # eQDMA<->QDMA data/status/completion differences are converted internally by cpm4_qdma_shim
    # so design_static's boundary stays identical to the V80.
    connect_bd_intf_net [get_bd_intf_ports pcie_clk] [get_bd_intf_pins versal_cips_0/gt_refclk0]
    connect_bd_intf_net [get_bd_intf_ports pcie_gt] [get_bd_intf_pins versal_cips_0/PCIE0_GT]
    connect_bd_intf_net [get_bd_intf_ports dsc_bypass_h2c] [get_bd_intf_pins versal_cips_0/dma0_h2c_byp_in_st]
    connect_bd_intf_net [get_bd_intf_ports usr_irq] [get_bd_intf_pins versal_cips_0/dma0_usr_irq]

    # Internal CPM4 <-> eQDMA shim (hw/hdl/static/cpm4_qdma_shim.v, added via cr_static)
    create_bd_cell -type module -reference cpm4_qdma_shim cpm4_shim_0
    # Boundary (eQDMA-style) interfaces -> design_static ports
    connect_bd_intf_net [get_bd_intf_ports m_axis_h2c]     [get_bd_intf_pins cpm4_shim_0/m_axis_h2c]
    connect_bd_intf_net [get_bd_intf_ports s_axis_c2h]     [get_bd_intf_pins cpm4_shim_0/s_axis_c2h]
    connect_bd_intf_net [get_bd_intf_ports h2c_status]     [get_bd_intf_pins cpm4_shim_0/h2c_status]
    connect_bd_intf_net [get_bd_intf_ports c2h_status]     [get_bd_intf_pins cpm4_shim_0/c2h_status]
    connect_bd_intf_net [get_bd_intf_ports dsc_bypass_c2h] [get_bd_intf_pins cpm4_shim_0/dsc_bypass_c2h]
    connect_bd_intf_net [get_bd_intf_ports dsc_pr]         [get_bd_intf_pins cpm4_shim_0/dsc_pr]

    # ---- shim CPM4-side scalars <-> versal_cips_0 QDMA pins ----
    # H2C data
    foreach s {tdata tvalid tlast tready qid port_id err mdata mty zero_byte} {
      connect_bd_net [get_bd_pins cpm4_shim_0/cpm_h2c_$s] [get_bd_pins versal_cips_0/dma0_m_axis_h2c_$s]
    }
    # C2H data (dpar tied inside shim)
    foreach s {tdata tvalid tlast tready mty dpar ctrl_marker ctrl_port_id ctrl_len ctrl_qid ctrl_dis_cmpt} {
      connect_bd_net [get_bd_pins cpm4_shim_0/cpm_c2h_$s] [get_bd_pins versal_cips_0/dma0_s_axis_c2h_$s]
    }
    # C2H completion stream: one 8B CMPT record per packet (shim-generated; consumed by the
    # driver's host CMPT ring -- the silicon-validated completion mechanism)
    foreach s {data dpar size tlast tvalid tready} {
      connect_bd_net [get_bd_pins cpm4_shim_0/cpm_c2h_cmpt_$s] [get_bd_pins versal_cips_0/dma0_s_axis_c2h_cmpt_$s]
    }
    # C2H command / descriptor bypass  (shim -> CPM4 dma0_c2h_byp_in_st_sim -- SIMPLE bypass,
    # armed-slot flow). SW arms the per-queue prefetch slot via 0x1408/0x140c; the shim submits
    # the FPGA-addressed descriptor on byp_in with an outstanding-limit of ONE (a byp_in beat
    # while the slot is busy is silently lost -- HW-verified); the slot frees on the
    # axis_c2h_status pulse. Must agree with prefetch-ctx bypass bit = 1 (simple) in the driver.
    foreach s {addr error func port_id qid ready valid} {
      connect_bd_net [get_bd_pins cpm4_shim_0/cpm_c2h_byp_$s] [get_bd_pins versal_cips_0/dma0_c2h_byp_in_st_sim_$s]
    }
    # C2H descriptor-bypass OUT (CPM4 -> shim): carries the per-packet marker responses that
    # synthesize the boundary c2h_status (CPM4's axis_c2h_status does not pulse in bypass mode)
    foreach s {valid mrkr_rsp st_mm qid error ready} {
      connect_bd_net [get_bd_pins cpm4_shim_0/cpm_c2h_byp_out_$s] [get_bd_pins versal_cips_0/dma0_c2h_byp_out_$s]
    }
    # PR MM descriptor  (shim -> CPM4 dma0_h2c_byp_in_mm)
    foreach s {radr wadr cidx error func len mrkr_req port_id qid ready sdi valid} {
      connect_bd_net [get_bd_pins cpm4_shim_0/cpm_pr_$s] [get_bd_pins versal_cips_0/dma0_h2c_byp_in_mm_$s]
    }
    # C2H status (CPM4 -> shim)
    foreach s {drop qid valid} {
      connect_bd_net [get_bd_pins cpm4_shim_0/cpm_c2h_sts_$s] [get_bd_pins versal_cips_0/dma0_axis_c2h_status_$s]
    }
    # H2C descriptor-bypass output = marker response = H2C completion (CPM4 -> shim)
    foreach s {valid mrkr_rsp error qid port_id ready} {
      connect_bd_net [get_bd_pins cpm4_shim_0/cpm_h2c_byp_$s] [get_bd_pins versal_cips_0/dma0_h2c_byp_out_$s]
    }
  } elseif {$cnfg(pcie_gen) eq 5} {
    # QDMA
    connect_bd_intf_net [get_bd_intf_ports pcie_clk] [get_bd_intf_pins versal_cips_0/gt_refclk1]
    connect_bd_intf_net [get_bd_intf_ports pcie_gt] [get_bd_intf_pins versal_cips_0/PCIE1_GT]

    # Descriptor status
    connect_bd_intf_net [get_bd_intf_ports c2h_status] [get_bd_intf_pins versal_cips_0/dma1_axis_c2h_status]
    connect_bd_intf_net [get_bd_intf_ports h2c_status] [get_bd_intf_pins versal_cips_0/dma1_qsts_out]

    # Data lines
    connect_bd_intf_net [get_bd_intf_ports s_axis_c2h] [get_bd_intf_pins versal_cips_0/dma1_s_axis_c2h]
    connect_bd_intf_net [get_bd_intf_ports m_axis_h2c] [get_bd_intf_pins versal_cips_0/dma1_m_axis_h2c]

    # Command lines
    connect_bd_intf_net [get_bd_intf_ports dsc_bypass_c2h] [get_bd_intf_pins versal_cips_0/dma1_c2h_byp_in_st_csh]
    connect_bd_intf_net [get_bd_intf_ports dsc_bypass_h2c] [get_bd_intf_pins versal_cips_0/dma1_h2c_byp_in_st]

    # PR
    connect_bd_intf_net [get_bd_intf_ports dsc_pr] [get_bd_intf_pins versal_cips_0/dma1_h2c_byp_in_mm_0]

    # Interrupts
    connect_bd_intf_net [get_bd_intf_ports usr_irq] [get_bd_intf_pins versal_cips_0/dma1_usr_irq]
  
  } elseif {$cnfg(pcie_gen) eq 4} {
    # QDMA
    connect_bd_intf_net [get_bd_intf_ports pcie_clk] [get_bd_intf_pins versal_cips_0/gt_refclk0]
    connect_bd_intf_net [get_bd_intf_ports pcie_gt] [get_bd_intf_pins versal_cips_0/PCIE0_GT] 

    # Descriptor status
    connect_bd_intf_net [get_bd_intf_ports c2h_status] [get_bd_intf_pins versal_cips_0/dma0_axis_c2h_status]
    connect_bd_intf_net [get_bd_intf_ports h2c_status] [get_bd_intf_pins versal_cips_0/dma0_qsts_out]

    # Data lines
    connect_bd_intf_net [get_bd_intf_ports s_axis_c2h] [get_bd_intf_pins versal_cips_0/dma0_s_axis_c2h]
    connect_bd_intf_net [get_bd_intf_ports m_axis_h2c] [get_bd_intf_pins versal_cips_0/dma0_m_axis_h2c]

    # Command lines
    connect_bd_intf_net [get_bd_intf_ports dsc_bypass_c2h] [get_bd_intf_pins versal_cips_0/dma0_c2h_byp_in_st_csh]
    connect_bd_intf_net [get_bd_intf_ports dsc_bypass_h2c] [get_bd_intf_pins versal_cips_0/dma0_h2c_byp_in_st]

    # PR
    connect_bd_intf_net [get_bd_intf_ports dsc_pr] [get_bd_intf_pins versal_cips_0/dma0_h2c_byp_in_mm_0]

    # Interrupts
    connect_bd_intf_net [get_bd_intf_ports usr_irq] [get_bd_intf_pins versal_cips_0/dma0_usr_irq]
  } else {
    puts "ERROR: Unsupported PCIe configuration: Gen$cnfg(pcie_gen). Supported configurations for V80 are Gen4x16 and Gen5x8."
    exit 1
  }
  
  # NoC
  connect_bd_intf_net [get_bd_intf_pins axi_noc_0/S00_AXI] [get_bd_intf_pins versal_cips_0/CPM_PCIE_NOC_0]
  connect_bd_intf_net [get_bd_intf_pins axi_noc_0/S01_AXI] [get_bd_intf_pins versal_cips_0/CPM_PCIE_NOC_1]
  connect_bd_intf_net [get_bd_intf_pins axi_noc_0/S02_AXI] [get_bd_intf_pins versal_cips_0/PMC_NOC_AXI_0]
  connect_bd_intf_net [get_bd_intf_pins axi_noc_0/M02_AXI] [get_bd_intf_pins versal_cips_0/NOC_PMC_AXI_0]

  # Shell config & control --- axi_main
  connect_bd_intf_net [get_bd_intf_pins smartconnect_1/S00_AXI] [get_bd_intf_pins axi_noc_0/M01_AXI]
  connect_bd_intf_net [get_bd_intf_ports axi_main] [get_bd_intf_pins smartconnect_1/M00_AXI]

  # Static config --- axi_cnfg
  connect_bd_intf_net [get_bd_intf_pins smartconnect_0/S00_AXI] [get_bd_intf_pins axi_noc_0/M00_AXI]
  connect_bd_intf_net [get_bd_intf_ports axi_cnfg] [get_bd_intf_pins smartconnect_0/M00_AXI]

  # Debug Hub config
  connect_bd_intf_net [get_bd_intf_pins axi_noc_0/M03_AXI] [get_bd_intf_ports axi_debug_hub]

  # VCK5000 only: BRAM datapath + physical DDR4 / sysclk for the integrated DDR MC.
  if {$cnfg(fdev) eq "vck5000"} {
    connect_bd_intf_net [get_bd_intf_pins axi_noc_0/M04_AXI] [get_bd_intf_pins bram_ctrl_0/S_AXI]
    connect_bd_intf_net [get_bd_intf_ports c0_ddr4]      [get_bd_intf_pins axi_noc_0/CH0_DDR4_0]
    connect_bd_intf_net [get_bd_intf_ports c0_sys_clk_0] [get_bd_intf_pins axi_noc_0/sys_clk0]
  }
########################################################################################################
# Create port connections
########################################################################################################

  if {$cnfg(fdev) eq "vck5000"} {
    # QDMA unused ready signals tied to 1 (h2c_byp_out.ready and c2h_byp_out.ready are driven
    # by the shim, not tied -- c2h_byp_out is the C2H credit stream for the pairing loop).
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma0_st_rx_msg_tready]
    # tm_dsc_sts is unused (H2C completion is taken from h2c_byp_out); accept its beats
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma0_tm_dsc_sts_rdy]
    # CPM4 uses dma0_soft_resetn (no dma0_intrfc_resetn); tie inactive (high)
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma0_soft_resetn]
    # Tie off unused CPM4 QDMA slave inputs (cache-bypass C2H, MM C2H, descriptor credit, mgmt).
    # C2H uses the SIMPLE bypass port (st_sim, shim-driven); the cache port (st_csh) is unused.
    connect_bd_net [get_bd_pins const_0/dout] [get_bd_pins versal_cips_0/dma0_c2h_byp_in_st_csh_valid]
    connect_bd_net [get_bd_pins const_0/dout] [get_bd_pins versal_cips_0/dma0_c2h_byp_in_mm_valid]
    connect_bd_net [get_bd_pins const_0/dout] [get_bd_pins versal_cips_0/dma0_dsc_crdt_in_valid]
    connect_bd_net [get_bd_pins const_0/dout] [get_bd_pins versal_cips_0/dma0_mgmt_req_vld]
  } elseif {$cnfg(pcie_gen) eq 5} {
    # QDMA unused ready signals are tied off to 1
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma1_st_rx_msg_tready]
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma1_tm_dsc_sts_rdy]
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma1_c2h_byp_out_ready]
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma1_h2c_byp_out_ready]

    # QDMA resetn is tied off to 1 (for now, keeping it consistent with rest of Coyote)
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma1_intrfc_resetn]
  
    # Tie off all MM descriptors other than host-to-card channel 0 for PR
    connect_bd_net  [get_bd_pins const_0/dout] [get_bd_pins versal_cips_0/dma1_h2c_byp_in_mm_1_valid]
    connect_bd_net  [get_bd_pins const_0/dout] [get_bd_pins versal_cips_0/dma1_c2h_byp_in_mm_1_valid]
    connect_bd_net  [get_bd_pins const_0/dout] [get_bd_pins versal_cips_0/dma1_c2h_byp_in_mm_0_valid]
  } elseif {$cnfg(pcie_gen) eq 4} {
    # QDMA unused ready signals are tied off to 1
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma0_st_rx_msg_tready]
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma0_tm_dsc_sts_rdy]
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma0_c2h_byp_out_ready]
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma0_h2c_byp_out_ready]

    # QDMA resetn is tied off to 1 (for now, keeping it consistent with rest of Coyote)
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma0_intrfc_resetn]

    # Tie off all MM descriptors other than host-to-card channel 0 for PR
    connect_bd_net  [get_bd_pins const_0/dout] [get_bd_pins versal_cips_0/dma0_h2c_byp_in_mm_1_valid]
    connect_bd_net  [get_bd_pins const_0/dout] [get_bd_pins versal_cips_0/dma0_c2h_byp_in_mm_1_valid]
    connect_bd_net  [get_bd_pins const_0/dout] [get_bd_pins versal_cips_0/dma0_c2h_byp_in_mm_0_valid]
  } else {
    puts "ERROR: Unsupported PCIe configuration: Gen$cnfg(pcie_gen). Supported configurations for V80 are Gen4x16 and Gen5x8."
    exit 1
  }
  
  # QDMA CPM IRQ interfaces should be tied off to 0 (reserved for future use)
  connect_bd_net [get_bd_pins const_0/dout] [get_bd_pins versal_cips_0/cpm_irq0]
  connect_bd_net [get_bd_pins const_0/dout] [get_bd_pins versal_cips_0/cpm_irq1]

  # NoC clocks
  connect_bd_net [get_bd_pins versal_cips_0/cpm_pcie_noc_axi0_clk] [get_bd_pins axi_noc_0/aclk0]
  connect_bd_net [get_bd_pins versal_cips_0/cpm_pcie_noc_axi1_clk] [get_bd_pins axi_noc_0/aclk1]
  connect_bd_net [get_bd_pins versal_cips_0/pmc_axi_noc_axi0_clk] [get_bd_pins axi_noc_0/aclk2]
  connect_bd_net [get_bd_pins versal_cips_0/noc_pmc_axi_axi0_clk] [get_bd_pins axi_noc_0/aclk4]
  
  # Main shell clock
  connect_bd_net [get_bd_pins versal_cips_0/pl0_ref_clk] [get_bd_pins clk_wiz_0/clk_in1]

  # Shell clock source: on the V80 (CPM5) the clk_wiz output drives the QDMA interface clock
  # (dma*_intrfc_clk) and the shell, so both share it. CPM4 has no dma0_intrfc_clk input --- its
  # QDMA AXIS run on the CPM output pcie0_user_clk --- so the VCK5000 shell runs directly on
  # pcie0_user_clk (keeping streams and shell synchronous, no extra CDC). clk_wiz is left driven
  # but unused for vck5000.
  if {$cnfg(fdev) eq "vck5000"} {
    set shell_clk [get_bd_pins versal_cips_0/pcie0_user_clk]
  } else {
    set shell_clk [get_bd_pins clk_wiz_0/clk_out1]
  }

  connect_bd_net $shell_clk [get_bd_ports xclk]
  connect_bd_net $shell_clk [get_bd_pins axi_noc_0/aclk3]
  connect_bd_net $shell_clk [get_bd_pins smartconnect_0/aclk]
  connect_bd_net $shell_clk [get_bd_pins smartconnect_1/aclk]
  if {$cnfg(fdev) eq "vck5000"} {
    # CPM4 QDMA has no dma0_intrfc_clk to drive
  } elseif {$cnfg(pcie_gen) eq 5} {
    connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins versal_cips_0/dma1_intrfc_clk]
  } elseif {$cnfg(pcie_gen) eq 4} {
    connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins versal_cips_0/dma0_intrfc_clk]
  } else {
    puts "ERROR: Unsupported PCIe configuration: Gen$cnfg(pcie_gen). Supported configurations for V80 are Gen4x16 and Gen5x8."
    exit 1
  }

  # System reset
  connect_bd_net [get_bd_ports sresetn] [get_bd_pins proc_sys_reset_s/peripheral_aresetn]
  connect_bd_net $shell_clk [get_bd_pins proc_sys_reset_s/slowest_sync_clk]

  if {$cnfg(fdev) eq "vck5000"} {
    # System reset from CPM4 QDMA AXI reset
    connect_bd_net [get_bd_pins versal_cips_0/dma0_axi_aresetn] [get_bd_pins proc_sys_reset_s/ext_reset_in]
    # SmartConnect reset
    connect_bd_net [get_bd_pins versal_cips_0/dma0_axi_aresetn] [get_bd_pins smartconnect_0/aresetn]
    connect_bd_net [get_bd_pins versal_cips_0/dma0_axi_aresetn] [get_bd_pins smartconnect_1/aresetn]
    # BRAM controller runs in the shell clock domain, reset by the QDMA AXI reset
    connect_bd_net $shell_clk [get_bd_pins bram_ctrl_0/s_axi_aclk]
    connect_bd_net [get_bd_pins versal_cips_0/dma0_axi_aresetn] [get_bd_pins bram_ctrl_0/s_axi_aresetn]
    # CPM4<->eQDMA shim: the C2H command FIFO (credit pairing) runs on the QDMA fabric clock
    # (= shell clock, pcie0_user_clk), reset by the QDMA AXI reset
    connect_bd_net $shell_clk [get_bd_pins cpm4_shim_0/aclk]
    connect_bd_net [get_bd_pins versal_cips_0/dma0_axi_aresetn] [get_bd_pins cpm4_shim_0/aresetn]
  } elseif {$cnfg(pcie_gen) eq 5} {
    # System reset
    connect_bd_net [get_bd_pins versal_cips_0/dma1_axi_aresetn] [get_bd_pins proc_sys_reset_s/ext_reset_in] 
    
    # SmartConnect reset
    connect_bd_net [get_bd_pins versal_cips_0/dma1_axi_aresetn] [get_bd_pins smartconnect_0/aresetn]
    connect_bd_net [get_bd_pins versal_cips_0/dma1_axi_aresetn] [get_bd_pins smartconnect_1/aresetn]
  } elseif {$cnfg(pcie_gen) eq 4} {
    # System reset
    connect_bd_net [get_bd_pins versal_cips_0/dma0_axi_aresetn] [get_bd_pins proc_sys_reset_s/ext_reset_in] 
    
    # SmartConnect reset
    connect_bd_net [get_bd_pins versal_cips_0/dma0_axi_aresetn] [get_bd_pins smartconnect_0/aresetn]
    connect_bd_net [get_bd_pins versal_cips_0/dma0_axi_aresetn] [get_bd_pins smartconnect_1/aresetn]
  } else {
    puts "ERROR: Unsupported PCIe configuration: Gen$cnfg(pcie_gen). Supported configurations for V80 are Gen4x16 and Gen5x8."
    exit 1
  }

  # Shell reset
  connect_bd_net [get_bd_ports xresetn] [get_bd_pins proc_sys_reset_x/peripheral_aresetn]
  connect_bd_net [get_bd_ports eos_resetn] [get_bd_pins proc_sys_reset_x/ext_reset_in]
  connect_bd_net [get_bd_pins proc_sys_reset_x/slowest_sync_clk] $shell_clk

  # EOS (PMC end-of-startup). If the CPM4 CIPS does not expose an 'eos' pin, tie the
  # eos_pmc port low (PR-completion signalling is refined during board bring-up).
  if {[llength [get_bd_pins -quiet versal_cips_0/eos]] > 0} {
    connect_bd_net [get_bd_pins versal_cips_0/eos] [get_bd_ports eos_pmc]
  } else {
    connect_bd_net [get_bd_pins const_0/dout] [get_bd_ports eos_pmc]
  }

########################################################################################################
# Create address segments
########################################################################################################
  # Shell & static config
  assign_bd_address -offset 0x020100000000 -range 1M -target_address_space [get_bd_addr_spaces versal_cips_0/CPM_PCIE_NOC_0] [get_bd_addr_segs axi_cnfg/Reg] -force
  assign_bd_address -offset 0x020800000000 -range 256M -target_address_space [get_bd_addr_spaces versal_cips_0/CPM_PCIE_NOC_0] [get_bd_addr_segs axi_main/Reg] -force
  
  # PR control (SBI CSR) --- currently unused
  # assign_bd_address -offset 0x000101220000 -range 64K -target_address_space [get_bd_addr_spaces versal_cips_0/CPM_PCIE_NOC_1] [get_bd_addr_segs versal_cips_0/NOC_PMC_AXI_0/pspmc_0_psv_pmc_slave_boot] -force

  # PR data (address to write partial PDI to)
  assign_bd_address -offset 0x000102100000 -range 64K -target_address_space [get_bd_addr_spaces versal_cips_0/CPM_PCIE_NOC_1] [get_bd_addr_segs versal_cips_0/NOC_PMC_AXI_0/pspmc_0_psv_pmc_slave_boot_stream] -force

  # PMC_NOC_AXI_0 for configuring the Debug Hub IP
  assign_bd_address -offset 0x020240000000 -range 2M -target_address_space [get_bd_addr_spaces versal_cips_0/PMC_NOC_AXI_0] [get_bd_addr_segs axi_debug_hub/Reg] -force

  # VCK5000 only: map the integrated DDR (fixed-address DDR_LOW0/1 segments) and the BRAM
  # into both CPM_PCIE_NOC address spaces. DDR segments carry a fixed base (no -offset); the
  # BRAM is placed at 0x0203_0000_0000 (matching its M04_AXI aperture).
  if {$cnfg(fdev) eq "vck5000"} {
    # S00_AXI carries CPM_PCIE_NOC_0, S01_AXI carries CPM_PCIE_NOC_1.
    foreach {sp si} {CPM_PCIE_NOC_0 S00_AXI CPM_PCIE_NOC_1 S01_AXI} {
      # BRAM (512 KB)
      catch { assign_bd_address -offset 0x020300000000 -range 512K -target_address_space [get_bd_addr_spaces versal_cips_0/$sp] [get_bd_addr_segs bram_ctrl_0/S_AXI/Mem0] -force }
      # DDR (all C*_DDR_* channel segments visible on this NoC slave port)
      foreach seg [get_bd_addr_segs -quiet axi_noc_0/$si/C*_DDR_*] {
        catch { assign_bd_address -target_address_space [get_bd_addr_spaces versal_cips_0/$sp] $seg -force }
      }
    }
  }

  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
  close_bd_design $design_name 

  return 0
}
# End of cr_bd_design_static()
