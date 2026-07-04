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

# Dynamic crossbar; one crossbar per region/vFPGA
proc cr_bd_dyn_xbar { idx } {
  upvar #0 cfg cnfg

  set design_name "dyn_crossbar_$idx"

  common::send_msg_id "BD_TCL-003" "INFO" "Currently there is no design <$design_name> in project, so creating one..."

  create_bd_design $design_name

########################################################################################################
########################################################################################################
# DYNAMIC XBAR
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
    set S00_AXI [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S00_AXI ]
    set cmd "set_property -dict \[ list \
        CONFIG.ADDR_WIDTH {64} \
        CONFIG.DATA_WIDTH {64} \
        CONFIG.FREQ_HZ {$cnfg(aclk_f)000000} \
        CONFIG.PROTOCOL {AXI4LITE} \
    ] \$S00_AXI"
    eval $cmd

    set M00_AXI [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M00_AXI ]
    set cmd "set_property -dict \[ list \
        CONFIG.ADDR_WIDTH {64} \
        CONFIG.DATA_WIDTH {64} \
        CONFIG.FREQ_HZ {$cnfg(aclk_f)000000} \
        CONFIG.PROTOCOL {AXI4LITE} \
    ] \$M00_AXI"
    eval $cmd

    set M01_AXI [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M01_AXI ]
    set cmd "set_property -dict \[ list \
        CONFIG.ADDR_WIDTH {64} \
        CONFIG.DATA_WIDTH {64} \
        CONFIG.FREQ_HZ {$cnfg(aclk_f)000000} \
        CONFIG.PROTOCOL {AXI4LITE} \
    ] \$M01_AXI"
    eval $cmd

    set M02_AXI [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M02_AXI ]
    set cmd "set_property -dict \[ list \
        CONFIG.ADDR_WIDTH {64} \
        CONFIG.DATA_WIDTH {64} \
        CONFIG.FREQ_HZ {$cnfg(aclk_f)000000} \
        CONFIG.PROTOCOL {AXI4LITE} \
    ] \$M02_AXI"
    eval $cmd

    set M03_AXI [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M03_AXI ]
    set cmd "set_property -dict \[ list \
        CONFIG.ADDR_WIDTH {64} \
        CONFIG.DATA_WIDTH {64} \
        CONFIG.FREQ_HZ {$cnfg(aclk_f)000000} \
        CONFIG.PROTOCOL {AXI4LITE} \
    ] \$M03_AXI"
    eval $cmd

########################################################################################################
# Create ports
########################################################################################################
    set aclk [ create_bd_port -dir I -type clk aclk ]
    set cmd "set_property -dict \[ list \
        CONFIG.FREQ_HZ {$cnfg(aclk_f)000000} \
        CONFIG.ASSOCIATED_BUSIF {M00_AXI:M01_AXI:M02_AXI:M03_AXI:S00_AXI} \
        CONFIG.ASSOCIATED_RESET {aresetn} \
    ] \$aclk"
    eval $cmd

    set aresetn [ create_bd_port -dir I -type rst aresetn ]

########################################################################################################
# Create instances
########################################################################################################
    set smartconnect_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0 ]
    set_property -dict [list \
        CONFIG.NUM_MI {4} \
        CONFIG.NUM_SI {1} \
    ] $smartconnect_0  
    set_property CONFIG.ADVANCED_PROPERTIES {__experimental_features__ {disable_low_area_mode 1} __view__ {functional {S00_Entry {SUPPORTS_WRAP 1 SUPPORTS_NARROW_BURST 1}}}} $smartconnect_0

########################################################################################################
# Create interface connections
########################################################################################################
    connect_bd_intf_net -intf_net S00_AXI_1 [get_bd_intf_pins smartconnect_0/S00_AXI] [get_bd_intf_ports S00_AXI]
    connect_bd_intf_net -intf_net smartconnect_0_M00_AXI [get_bd_intf_pins smartconnect_0/M00_AXI] [get_bd_intf_ports M00_AXI]
    connect_bd_intf_net -intf_net smartconnect_0_M01_AXI [get_bd_intf_pins smartconnect_0/M01_AXI] [get_bd_intf_ports M01_AXI]
    connect_bd_intf_net -intf_net smartconnect_0_M02_AXI [get_bd_intf_pins smartconnect_0/M02_AXI] [get_bd_intf_ports M02_AXI]
    connect_bd_intf_net -intf_net smartconnect_0_M03_AXI [get_bd_intf_pins smartconnect_0/M03_AXI] [get_bd_intf_ports M03_AXI]

########################################################################################################
# Create port connections
########################################################################################################
    connect_bd_net -net aclk_1 [get_bd_ports aclk] [get_bd_pins smartconnect_0/aclk]
    connect_bd_net -net aresetn_1 [get_bd_ports aresetn] [get_bd_pins smartconnect_0/aresetn]

########################################################################################################
# Create address segments
########################################################################################################
    set offs [expr {0x10 + $idx * 4}]
    set cmd [format "assign_bd_address -offset 0x0000000000%02x0000 -range 0x00010000 -target_address_space \[get_bd_addr_spaces S00_AXI\] \[get_bd_addr_segs M00_AXI/Reg\] -force" $offs ]
    eval $cmd
    
    set cmd [format "assign_bd_address -offset 0x0000000000%02x0000 -range 0x00010000 -target_address_space \[get_bd_addr_spaces S00_AXI\] \[get_bd_addr_segs M01_AXI/Reg\] -force" [expr {$offs + 1}] ]
    eval $cmd
    
    set cmd [format "assign_bd_address -offset 0x0000000000%02x0000 -range 0x00010000 -target_address_space \[get_bd_addr_spaces S00_AXI\] \[get_bd_addr_segs M02_AXI/Reg\] -force" [expr {$offs + 2}] ]
    eval $cmd
    
    set cmd [format "assign_bd_address -offset 0x0000000000%02x0000 -range 0x00010000 -target_address_space \[get_bd_addr_spaces S00_AXI\] \[get_bd_addr_segs M03_AXI/Reg\] -force" [expr {$offs + 3}] ]
    eval $cmd
    
    validate_bd_design
    save_bd_design
    close_bd_design $design_name 

    return 0
}
# End of cr_bd_dyn_xbar()