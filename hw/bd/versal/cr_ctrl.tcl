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

# Shell ctrl layer
proc cr_bd_design_ctrl { parentCell } {
  upvar #0 cfg cnfg

  set design_name design_ctrl

  common::send_msg_id "BD_TCL-003" "INFO" "Currently there is no design <$design_name> in project, so creating one..."

  create_bd_design $design_name

########################################################################################################
########################################################################################################
# SHELL CTRL
########################################################################################################
########################################################################################################

########################################################################################################
# CHECK IPs
########################################################################################################
    set bCheckIPs 1
    set bCheckIPsPassed 1

    if { $bCheckIPs == 1 } {
        set list_check_ips "\ 
        xilinx.com:ip:smartconnect:1.0\
        xilinx.com:ip:clk_wiz:6.0\
        xilinx.com:ip:axi_dbg_hub:2.0\
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

########################################################################################################
# Create interface ports
########################################################################################################
  
  # Shell config
  set axi_cnfg [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_cnfg ]
  set_property -dict [ list \
    CONFIG.ADDR_WIDTH {64} \
    CONFIG.DATA_WIDTH {64} \
    CONFIG.PROTOCOL {AXI4LITE} \
  ] $axi_cnfg

  set axi_main [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_main ]
  set_property -dict [list \
    CONFIG.MAX_BURST_LENGTH {16} \
    CONFIG.ID_WIDTH {6} \
    CONFIG.NUM_WRITE_OUTSTANDING {8} \
    CONFIG.NUM_READ_OUTSTANDING {8} \
    CONFIG.SUPPORTS_NARROW_BURST {0} \
    CONFIG.ADDR_WIDTH {64} \
    CONFIG.PROTOCOL {AXI4} \
    CONFIG.DATA_WIDTH {512} \
    CONFIG.NUM_READ_THREADS {2} \
    CONFIG.NUM_WRITE_THREADS {2} \
  ] $axi_main

  # Debug Hub IP control
  set axi_debug_hub [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_debug_hub ]
  set_property -dict [ list \
    CONFIG.ADDR_WIDTH {64} \
    CONFIG.DATA_WIDTH {128} \
    CONFIG.ID_WIDTH {2} \
    CONFIG.PROTOCOL {AXI4} \
  ] $axi_debug_hub

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
  
  # Host reset
  set xresetn [ create_bd_port -dir I -type rst xresetn ]

  # Input clock from the static layer
  set xclk [ create_bd_port -dir I -type clk xclk ]  
  set cmd "set_property -dict \[ list \
    CONFIG.FREQ_HZ $cnfg(sclk_f)000000 \
    CONFIG.ASSOCIATED_BUSIF {axi_main:axi_debug_hub} \
    CONFIG.ASSOCIATED_RESET {xresetn} \
  ] \$xclk"
  eval $cmd
  
  # Shell reset
  set aresetn [ create_bd_port -dir O -type rst aresetn ]

  # Shell clock
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

  # Net reset
  set nresetn [ create_bd_port -dir O -type rst nresetn ]

  # Net clock
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

  # Locked and reset
  create_bd_port -dir O -type rst lckresetn
  create_bd_port -dir I -type rst sys_reset
  set_property CONFIG.POLARITY ACTIVE_HIGH [get_bd_ports sys_reset]

########################################################################################################
# Create interconnect and components
########################################################################################################
  
  # AXI interconnect
  if {$cnfg(en_avx) eq 1} {
    set ic0_mi [expr {2*$cnfg(n_reg) + 1}]
  } else {
    set ic0_mi [expr {$cnfg(n_reg) + 1}]
  }

  set axi_interconnect_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_interconnect_0 ]
  set cmd "set_property -dict \[list \
    CONFIG.NUM_CLKS {2} \
    CONFIG.NUM_MI {$ic0_mi} \
    CONFIG.NUM_SI {1} \
  ] \[get_bd_cells axi_interconnect_0]"
  eval $cmd 
  set_property CONFIG.ADVANCED_PROPERTIES {__experimental_features__ {disable_low_area_mode 1} __view__ {functional {S00_Entry {SUPPORTS_WRAP 1 SUPPORTS_NARROW_BURST 1}}}} $axi_interconnect_0
  
  # Clocking
  create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wizard:1.0 clk_wiz_0
  set cmd "set_property -dict \[list \
    CONFIG.CLKOUT_DRIVES {BUFG,BUFG,BUFG} \
    CONFIG.CLKOUT_REQUESTED_OUT_FREQUENCY {[expr {$cnfg(aclk_f)}],[expr {$cnfg(nclk_f)}],[expr {$cnfg(uclk_f)}]} \
    CONFIG.CLKOUT_USED {true,true,true} \
    CONFIG.PRIM_IN_FREQ {[expr {$cnfg(sclk_f)}]} \
    CONFIG.PRIM_SOURCE {No_Buffer} \
    CONFIG.USE_PHASE_ALIGNMENT {true} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_RESET {true} \
  ] \[get_bd_cells clk_wiz_0]"
  eval $cmd

  # Reset controllers
  create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_a
  create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_n
  create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_u

  # Debug Hub IP
  set axi_dbg_hub_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dbg_hub:2.0 axi_dbg_hub_0 ]

########################################################################################################
# Create interface connections
########################################################################################################
  
  connect_bd_intf_net -intf_net axi_interconnect_0_M00_AXI [get_bd_intf_ports axi_cnfg] [get_bd_intf_pins axi_interconnect_0/M00_AXI]
  connect_bd_intf_net -intf_net axi_interconnect_0_S00_AXI [get_bd_intf_ports axi_main] [get_bd_intf_pins axi_interconnect_0/S00_AXI]

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

  connect_bd_intf_net [get_bd_intf_ports axi_debug_hub] [get_bd_intf_pins axi_dbg_hub_0/S_AXI]

########################################################################################################
# Create port connections
########################################################################################################
  connect_bd_net [get_bd_ports xclk] [get_bd_pins axi_interconnect_0/aclk]
  connect_bd_net [get_bd_ports xclk] [get_bd_pins axi_dbg_hub_0/aclk]

  connect_bd_net [get_bd_ports xresetn] [get_bd_pins axi_interconnect_0/aresetn]
  connect_bd_net [get_bd_ports xresetn] [get_bd_pins axi_dbg_hub_0/aresetn]

  connect_bd_net [get_bd_ports xclk] [get_bd_pins clk_wiz_0/clk_in1]
  connect_bd_net [get_bd_ports nclk] [get_bd_pins clk_wiz_0/clk_out2]
  connect_bd_net [get_bd_ports uclk] [get_bd_pins clk_wiz_0/clk_out3]
  connect_bd_net [get_bd_pins proc_sys_reset_a/slowest_sync_clk] [get_bd_pins clk_wiz_0/clk_out1]
  connect_bd_net [get_bd_pins proc_sys_reset_n/slowest_sync_clk] [get_bd_pins clk_wiz_0/clk_out2]
  connect_bd_net [get_bd_pins proc_sys_reset_u/slowest_sync_clk] [get_bd_pins clk_wiz_0/clk_out3]
  connect_bd_net [get_bd_ports aresetn] [get_bd_pins proc_sys_reset_a/peripheral_aresetn]
  connect_bd_net [get_bd_ports nresetn] [get_bd_pins proc_sys_reset_n/peripheral_aresetn]
  connect_bd_net [get_bd_ports uresetn] [get_bd_pins proc_sys_reset_u/peripheral_aresetn]
  connect_bd_net [get_bd_ports xresetn] [get_bd_pins proc_sys_reset_a/ext_reset_in]
  connect_bd_net [get_bd_ports xresetn] [get_bd_pins proc_sys_reset_n/ext_reset_in]
  connect_bd_net [get_bd_ports xresetn] [get_bd_pins proc_sys_reset_u/ext_reset_in]
  connect_bd_net [get_bd_ports lckresetn] [get_bd_pins clk_wiz_0/locked]
  connect_bd_net [get_bd_ports sys_reset] [get_bd_pins clk_wiz_0/reset]
  
  connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_ports aclk]
  connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins axi_interconnect_0/aclk1]
  
########################################################################################################
# Create address segments
########################################################################################################
  
  create_bd_addr_seg -range 0x00008000 -offset 0x00000000 [get_bd_addr_spaces /axi_main] [get_bd_addr_segs axi_cnfg/Reg] SEG_axi_cnfg_Reg

  if {$cnfg(en_avx) eq 1} { 
    for {set i 0}  {$i < $cnfg(n_reg)} {incr i} {
      set cmd [format "create_bd_addr_seg -range 0x00040000 -offset 0x000%02x0000 \[get_bd_addr_spaces /axi_main] \[get_bd_addr_segs axi_ctrl_$i/Reg] SEG_axi_ctrl_$i\_Reg" [expr {0x10 + $i * 4}]]
      eval $cmd
      set cmd [format "create_bd_addr_seg -range 0x00040000 -offset 0x00%03x0000 \[get_bd_addr_spaces /axi_main] \[get_bd_addr_segs axim_ctrl_$i/Reg] SEG_axim_ctrl_$i\_Reg" [expr {0x100 + $i * 4}]]
      eval $cmd
    }
  } else {
    for {set i 0}  {$i < $cnfg(n_reg)} {incr i} {
      set cmd [format "create_bd_addr_seg -range 0x00040000 -offset 0x000%02x0000 \[get_bd_addr_spaces /axi_main] \[get_bd_addr_segs axi_ctrl_$i/Reg] SEG_axi_ctrl_$i\_Reg" [expr {0x10 + $i * 4}]]
      eval $cmd
    }
  }

  assign_bd_address -offset 0x020240000000 -range 2M -target_address_space [get_bd_addr_spaces axi_debug_hub] [get_bd_addr_segs axi_dbg_hub_0/S_AXI_DBG_HUB/Mem0] -force

  validate_bd_design

  save_bd_design
  close_bd_design $design_name 

  return 0
}
# End of cr_bd_design_ctrl()
