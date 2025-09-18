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
  if { $bCheckIPs == 1 } {
    set list_check_ips "\ 
      xilinx.com:ip:proc_sys_reset:5.0\
      xilinx.com:ip:util_vector_logic:2.0\
      xilinx.com:ip:versal_cips:3.4\
      xilinx.com:ip:axi_noc:1.1\
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

  # QDMA status
  set h2c_status [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:eqdma_qsts_rtl:1.0 h2c_status ]
  set c2h_status [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:qdma_c2h_status_rtl:1.0 c2h_status ]

  # PCIe
  set pcie_clk [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 pcie_clk ]
  set_property -dict [ list \
    CONFIG.FREQ_HZ {100000000} \
  ] $pcie_clk
  set pcie_gt [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gt_rtl:1.0 pcie_gt ]

  # Data streams
  set s_axis_c2h [ create_bd_intf_port -mode Slave -vlnv xilinx.com:display_eqdma:s_axis_c2h_rtl:1.0 s_axis_c2h ]
  set m_axis_h2c [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_eqdma:m_axis_h2c_rtl:1.0 m_axis_h2c ]

  # Command streams
  set dsc_bypass_h2c [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_bypass_h2c ]
  set dsc_bypass_c2h [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:qdma_dsc_byp_rtl:1.0 dsc_bypass_c2h ]

  # User interrupts
  set usr_irq [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:qdma_usr_irq_rtl:1.0 usr_irq ]

########################################################################################################
# Create ports
########################################################################################################

  # Main BD reset
  set xresetn [ create_bd_port -dir O -type rst xresetn ]

  # Main bd clock
  set xclk [ create_bd_port -dir O -type clk xclk ]
  set_property -dict [ list \
    CONFIG.ASSOCIATED_BUSIF {m_axis_h2c:s_axis_c2h:axi_cnfg:axi_main} \
    CONFIG.ASSOCIATED_RESET {xresetn} \
  ] $xclk

  # System reset
  set sresetn [ create_bd_port -dir O -type rst sresetn ]

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
      set versal_cips_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:versal_cips:3.4 versal_cips_0 ]
      set_property -dict [list \
        CONFIG.BOOT_MODE {Custom} \
        CONFIG.CLOCK_MODE {Custom} \
        CONFIG.CPM_CONFIG { \
          CPM_PCIE0_MODES {None} \
          CPM_PCIE1_DMA_INTF {AXI4S} \
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
          CPM_PCIE1_PF0_PCIEBAR2AXIBAR_QDMA_2 {0x020180000000} \
          CPM_PCIE1_PF0_PCIEBAR2AXIBAR_QDMA_4 {0x020800000000} \
          CPM_PCIE1_PL_LINK_CAP_MAX_LINK_WIDTH {X8} \
          CPM_PCIE1_MAX_LINK_SPEED {32.0_GT/s} \
          CPM_PCIE1_REF_CLK_FREQ {100_MHz} \
          PS_USE_PS_NOC_PCI_1 {0} \
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
      set versal_cips_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:versal_cips:3.4 versal_cips_0 ]
      set_property -dict [list \
        CONFIG.BOOT_MODE {Custom} \
        CONFIG.CLOCK_MODE {Custom} \
        CONFIG.CPM_CONFIG { \
          CPM_PCIE1_MODES {None} \
          CPM_PCIE0_DMA_INTF {AXI4S} \
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
          CPM_PCIE0_PF0_PCIEBAR2AXIBAR_QDMA_2 {0x020180000000} \
          CPM_PCIE0_PF0_PCIEBAR2AXIBAR_QDMA_4 {0x020800000000} \
          CPM_PCIE0_PL_LINK_CAP_MAX_LINK_WIDTH {X16} \
          CPM_PCIE0_MAX_LINK_SPEED {16.0_GT/s} \
          CPM_PCIE0_REF_CLK_FREQ {100_MHz} \
          PS_USE_PS_NOC_PCI_1 {0} \
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
  } else {
    puts "ERROR: Unsupported FPGA part: $cnfg(fdev)"
    exit 1
  }

  # AXI NoC
  # The NoC is used to route AXI-MM interfaces from the QDMA to the shell
  # Additionally, it will perform clock-domain crossing, reducing the frequency from 1000 MHz to shell frequency
  set axi_noc_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_noc:1.1 axi_noc_0 ]
  set_property -dict [list \
    CONFIG.MI_SIDEBAND_PINS {0} \
    CONFIG.NUM_CLKS {2} \
    CONFIG.NUM_HBM_BLI {0} \
    CONFIG.NUM_MI {2} \
    CONFIG.NUM_SI {1} \
    CONFIG.SI_SIDEBAND_PINS {} \
  ] $axi_noc_0

  set_property -dict [ list \
    CONFIG.APERTURES {{0x201_0000_0000 1G}} \
    CONFIG.CATEGORY {pl} \
  ] [get_bd_intf_pins /axi_noc_0/M00_AXI]

  set_property -dict [ list \
    CONFIG.APERTURES {{0x208_0000_0000 1G}} \
    CONFIG.CATEGORY {pl} \
  ] [get_bd_intf_pins /axi_noc_0/M01_AXI]

  set_property -dict [ list \
    CONFIG.CONNECTIONS {M00_AXI {read_bw {16} write_bw {16} read_avg_burst {4} write_avg_burst {4}} M01_AXI {read_bw {16} write_bw {16} read_avg_burst {4} write_avg_burst {4}}} \
    CONFIG.DEST_IDS {M01_AXI:0x0:M00_AXI:0x40} \
    CONFIG.NOC_PARAMS {} \
    CONFIG.CATEGORY {ps_pcie} \
  ] [get_bd_intf_pins /axi_noc_0/S00_AXI]

  set_property -dict [ list \
    CONFIG.ASSOCIATED_BUSIF {S00_AXI} \
  ] [get_bd_pins /axi_noc_0/aclk0]

  set_property -dict [ list \
    CONFIG.ASSOCIATED_BUSIF {M00_AXI:M01_AXI} \
  ] [get_bd_pins /axi_noc_0/aclk1]

  # AXI SmartSwitch, connecting the NoC outputs to BD output interfaces
  set smartconnect_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0 ]
  set_property CONFIG.NUM_SI {1} $smartconnect_0
  set_property CONFIG.ADVANCED_PROPERTIES {__experimental_features__ {disable_low_area_mode 1} __view__ {functional {S00_Entry {SUPPORTS_WRAP 1 SUPPORTS_NARROW_BURST 1}}}} $smartconnect_0
  
  set smartconnect_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_1 ]
  set_property CONFIG.NUM_SI {1} $smartconnect_1
  set_property CONFIG.ADVANCED_PROPERTIES {__experimental_features__ {disable_low_area_mode 1} __view__ {functional {S00_Entry {SUPPORTS_WRAP 1 SUPPORTS_NARROW_BURST 1}}}} $smartconnect_1

  # Main clock gen
  create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wizard:1.0 clk_wiz_0
  set cmd "set_property -dict \[list \
    CONFIG.CLKOUT_DRIVES {BUFG} \
    CONFIG.CLKOUT_REQUESTED_OUT_FREQUENCY {[expr {$cnfg(aclk_f)}]} \
    CONFIG.CLKOUT_USED {true} \
    CONFIG.PRIM_SOURCE {Global_Buffer} \
  ] \[get_bd_cells clk_wiz_0]"
  eval $cmd

########################################################################################################
# Create interface connections
########################################################################################################
  if {$cnfg(pcie_gen) eq 5} {
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

    # Interrupts
    connect_bd_intf_net [get_bd_intf_ports usr_irq] [get_bd_intf_pins versal_cips_0/dma0_usr_irq]
  } else {
    puts "ERROR: Unsupported PCIe configuration: Gen$cnfg(pcie_gen). Supported configurations for V80 are Gen4x16 and Gen5x8."
    exit 1
  }
  
  # NoC
  connect_bd_intf_net [get_bd_intf_pins axi_noc_0/S00_AXI] [get_bd_intf_pins versal_cips_0/CPM_PCIE_NOC_0]

  # Shell config & control --- axi_main
  connect_bd_intf_net [get_bd_intf_pins smartconnect_1/S00_AXI] [get_bd_intf_pins axi_noc_0/M01_AXI]
  connect_bd_intf_net [get_bd_intf_ports axi_main] [get_bd_intf_pins smartconnect_1/M00_AXI]

  # Static config --- axi_cnfg
  connect_bd_intf_net [get_bd_intf_pins smartconnect_0/S00_AXI] [get_bd_intf_pins axi_noc_0/M00_AXI]
  connect_bd_intf_net [get_bd_intf_ports axi_cnfg] [get_bd_intf_pins smartconnect_0/M00_AXI]

########################################################################################################
# Create port connections
########################################################################################################

  if {$cnfg(pcie_gen) eq 5} {
    # QDMA unused ready signals are tied off to 1
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma1_st_rx_msg_tready]
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma1_tm_dsc_sts_rdy]
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma1_c2h_byp_out_ready]
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma1_h2c_byp_out_ready]

    # QDMA resetn is tied off to 1 (for now, keeping it consistent with rest of Coyote)
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma1_intrfc_resetn]
  } elseif {$cnfg(pcie_gen) eq 4} {
    # QDMA unused ready signals are tied off to 1
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma0_st_rx_msg_tready]
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma0_tm_dsc_sts_rdy]
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma0_c2h_byp_out_ready]
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma0_h2c_byp_out_ready]

    # QDMA resetn is tied off to 1 (for now, keeping it consistent with rest of Coyote)
    connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins versal_cips_0/dma0_intrfc_resetn]
  } else {
    puts "ERROR: Unsupported PCIe configuration: Gen$cnfg(pcie_gen). Supported configurations for V80 are Gen4x16 and Gen5x8."
    exit 1
  }
  
  # QDMA CPM IRQ interfaces should be tied off to 0 (reserved for future use)
  connect_bd_net [get_bd_pins const_0/dout] [get_bd_pins versal_cips_0/cpm_irq0]
  connect_bd_net [get_bd_pins const_0/dout] [get_bd_pins versal_cips_0/cpm_irq1]

  # NoC clocks
  connect_bd_net [get_bd_pins versal_cips_0/cpm_pcie_noc_axi0_clk] [get_bd_pins axi_noc_0/aclk0]

  # Main shell clock
  connect_bd_net [get_bd_pins versal_cips_0/pl0_ref_clk] [get_bd_pins clk_wiz_0/clk_in1] 

  connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_ports xclk] 
  connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins axi_noc_0/aclk1] 
  connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins smartconnect_0/aclk]
  connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins smartconnect_1/aclk]
  if {$cnfg(pcie_gen) eq 5} {
    connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins versal_cips_0/dma1_intrfc_clk]
  } elseif {$cnfg(pcie_gen) eq 4} {
    connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins versal_cips_0/dma0_intrfc_clk]
  } else {
    puts "ERROR: Unsupported PCIe configuration: Gen$cnfg(pcie_gen). Supported configurations for V80 are Gen4x16 and Gen5x8."
    exit 1
  }

  # System reset
  connect_bd_net [get_bd_ports sresetn] [get_bd_pins proc_sys_reset_s/peripheral_aresetn]
  connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins proc_sys_reset_s/slowest_sync_clk]

  if {$cnfg(pcie_gen) eq 5} {
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

  # Shell reset --- TODO (Versal): Once PR is brought back, do the AND with eos_resetn
  connect_bd_net [get_bd_ports xresetn] [get_bd_pins proc_sys_reset_x/peripheral_aresetn]
  connect_bd_net [get_bd_pins const_1/dout] [get_bd_pins proc_sys_reset_x/ext_reset_in]
  connect_bd_net [get_bd_pins proc_sys_reset_x/slowest_sync_clk] [get_bd_pins clk_wiz_0/clk_out1]

########################################################################################################
# Create address segments
########################################################################################################
  assign_bd_address -offset 0x020100000000 -range 1M -target_address_space [get_bd_addr_spaces versal_cips_0/CPM_PCIE_NOC_0] [get_bd_addr_segs axi_cnfg/Reg] -force
  assign_bd_address -offset 0x020800000000 -range 256M -target_address_space [get_bd_addr_spaces versal_cips_0/CPM_PCIE_NOC_0] [get_bd_addr_segs axi_main/Reg] -force

  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
  close_bd_design $design_name 

  return 0
}
# End of cr_bd_design_static()
