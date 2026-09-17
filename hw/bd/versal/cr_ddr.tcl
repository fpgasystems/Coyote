######################################################################################
# This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
# MIT Licence, Copyright (c) 2025, Systems Group, ETH Zurich
######################################################################################
#
# Versal DDR4-over-NoC card memory (VCK5000).
#
# The VCK5000 reaches its DDR4 (8 GB/channel, DDR4-3200, 16Gb x16) through the NoC via
# integrated DDR memory controllers (DDRMC) --- architecturally like the V80's HBM.
# design_ddr therefore mirrors design_hbm (hw/bd/versal/cr_hbm.tcl): a single axi_noc
# (inst_ddr_noc) hosts the AXI slave ports (axi_ddr_in_$i, 256-bit, fed by hbm_cc_dwc for
# CDC + width conversion) AND the integrated DDRMC(s). Keeping the AXI slaves and the MCs
# in the same NoC means the per-slave CONNECTIONS destinations (MC_$m) resolve locally ---
# no fragile cross-NoC INI routing. Physical DDR4 + 200 MHz sysclk are exposed to the top.
#
# DDRMC config values are taken verbatim from the VCK5000 board-automation DDR4 example
# (16Gb x16, DDR4-3200AA, 8 GB/channel), which is known-good for this board part.
#
# n_mc (physical DDR channels) is read from cfg(n_ddr_chan); it defaults to 1 for a first
# buildable milestone (8 GB card memory) and scales up to 4 (32 GB). Uses axi_noc:1.0 on
# 2023.2 (auto-selected to match the installed Vivado).

proc cr_bd_design_ddr { parentCell } {
  upvar #0 cfg cnfg

  set design_name design_ddr
  common::send_msg_id "BD_TCL-003" "INFO" "Creating <$design_name> ..."
  create_bd_design $design_name

  set noc_vlnv [lindex [lsort [get_ipdefs -all xilinx.com:ip:axi_noc:*]] end]

  if { $parentCell eq "" } { set parentCell [get_bd_cells /] }
  set parentObj [get_bd_cells $parentCell]
  set oldCurInst [current_bd_instance .]
  current_bd_instance $parentObj

  set n_mc $cnfg(n_ddr_chan)
  set n_si $cnfg(n_mem_chan)

  ####################################################################################
  # Ports
  ####################################################################################
  # Physical DDR4 + 200 MHz system clocks (one per channel) --- exposed to the top
  for {set m 0} {$m < $n_mc} {incr m} {
    create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 c${m}_ddr4
    set clk [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 c${m}_sys_clk_0 ]
    set_property CONFIG.FREQ_HZ {200000000} $clk
  }

  # AXI-MM card-memory inputs from the shell: 512-bit @ aclk, tied directly to axi_mem
  # (like the UltraScale+ design_ddr). The Versal NoC NMU accepts 512-bit, so --- unlike the
  # HBM path (256-bit + hbm_cc_dwc CDC to hclk) --- no width/clock converter is needed.
  for {set i 0} {$i < $n_si} {incr i} {
    set p [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_ddr_in_$i ]
    set_property -dict [ list \
      CONFIG.FREQ_HZ [expr {int($cnfg(aclk_f) * 1000000)}] \
      CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {512} CONFIG.ID_WIDTH {6} \
      CONFIG.HAS_BRESP {1} CONFIG.HAS_BURST {1} CONFIG.HAS_CACHE {1} CONFIG.HAS_LOCK {1} \
      CONFIG.HAS_PROT {1} CONFIG.HAS_QOS {0} CONFIG.HAS_REGION {0} CONFIG.HAS_RRESP {1} \
      CONFIG.HAS_WSTRB {1} CONFIG.NUM_READ_OUTSTANDING {8} CONFIG.NUM_WRITE_OUTSTANDING {8} \
      CONFIG.PROTOCOL {AXI4} CONFIG.READ_WRITE_MODE {READ_WRITE} \
    ] $p
  }

  # AXI clock for the NoC NMUs (shell clock domain)
  set aclk [ create_bd_port -dir I -type clk aclk ]
  set_property CONFIG.FREQ_HZ [expr {int($cnfg(aclk_f) * 1000000)}] $aclk

  ####################################################################################
  # Single NoC: AXI slaves + integrated DDRMC(s)
  ####################################################################################
  set ddr_noc [ create_bd_cell -type ip -vlnv $noc_vlnv inst_ddr_noc ]
  set_property -dict [ list \
    CONFIG.NUM_SI $n_si \
    CONFIG.NUM_MI {0} \
    CONFIG.NUM_CLKS {1} \
    CONFIG.NUM_MC $n_mc \
    CONFIG.NUM_MCP {4} \
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
  ] $ddr_noc

  # Per-MC physical DDR4 + sysclk board interfaces
  for {set m 0} {$m < $n_mc} {incr m} {
    set_property -dict [ list \
      CONFIG.CH0_DDR4_${m}_BOARD_INTERFACE "ddr4_sdram_c$m" \
      CONFIG.sys_clk${m}_BOARD_INTERFACE "ddr4_c${m}_sysclk" \
    ] $ddr_noc
  }

  # AXI slaves: each reaches every DDR channel (all-to-all, unified card memory)
  set dests {}
  for {set m 0} {$m < $n_mc} {incr m} { lappend dests "MC_$m {read_bw {1720} write_bw {1720} read_avg_burst {4} write_avg_burst {4}}" }
  for {set i 0} {$i < $n_si} {incr i} {
    set si [format "S%02d_AXI" $i]
    set_property -dict [ list CONFIG.CATEGORY {pl} CONFIG.CONNECTIONS [join $dests " "] ] [get_bd_intf_pins inst_ddr_noc/$si]
    connect_bd_intf_net [get_bd_intf_ports axi_ddr_in_$i] [get_bd_intf_pins inst_ddr_noc/$si]
  }
  set _busifs {}
  for {set i 0} {$i < $n_si} {incr i} { lappend _busifs [format "S%02d_AXI" $i] }
  set_property CONFIG.ASSOCIATED_BUSIF [join $_busifs ":"] [get_bd_pins inst_ddr_noc/aclk0]
  connect_bd_net [get_bd_ports aclk] [get_bd_pins inst_ddr_noc/aclk0]

  # Physical DDR4 + sysclk connections
  for {set m 0} {$m < $n_mc} {incr m} {
    connect_bd_intf_net [get_bd_intf_ports c${m}_ddr4]      [get_bd_intf_pins inst_ddr_noc/CH0_DDR4_$m]
    connect_bd_intf_net [get_bd_intf_ports c${m}_sys_clk_0] [get_bd_intf_pins inst_ddr_noc/sys_clk$m]
  }

  ####################################################################################
  # Address map: each AXI slave sees the full card memory (n_mc x 8 GB)
  ####################################################################################
  for {set i 0} {$i < $n_si} {incr i} {
    set si [format "S%02d_AXI" $i]
    foreach seg [get_bd_addr_segs -quiet inst_ddr_noc/$si/C*_DDR_*] {
      catch { assign_bd_address -target_address_space [get_bd_addr_spaces axi_ddr_in_$i] $seg -force }
    }
  }

  current_bd_instance $oldCurInst
  validate_bd_design
  save_bd_design
  close_bd_design $design_name
  return 0
}
# End of cr_bd_design_ddr()
