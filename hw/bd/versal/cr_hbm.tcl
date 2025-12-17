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

# Utility block for HBM AXI clock cross (CC) & data width conversion (DWC)
# The NoC inputs cannot be wider than 256 bits, so do a clock crossing and a data width conversion through a SmartConnect
proc cr_bd_hbm_cc_dwc { parentCell } {
   upvar #0 cfg cnfg

   set design_name hbm_cc_dwc

   common::send_msg_id "BD_TCL-003" "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

########################################################################################################
# Check IPs
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
# Create interface ports
########################################################################################################
   if {$cnfg(hbm_impl) eq "unified"} {
      # In the unified HBM implemenation, striping is enabled by default
      # Therefore, the maximum number of outstanding transactions is dictate by 
      # N_OUTSTANDING (shell-wide) and striping, which partitions each PMTU-sized request 
      # into STRIPE_FRAG_SIZE requests.
      set n_outsanding [expr {$cnfg(n_outs) * $cnfg(pmtu) / $cnfg(stripe_frag_size)}]
   } elseif {$cnfg(hbm_impl) eq "block"} {
      # In the block HBM implementation, each HBM_NMU accesses one specific HBM PC
      # With no striping, there it at most N_OUTSTANDING outstanding requests
      set n_outsanding [expr {$cnfg(n_outs)}]
   } else {
      puts "ERROR: Requested unsupported Versal HBM implementation: $cnfg(hbm_impl); available: unified, block"
      exit 1
   }

   set S_AXI [create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI]
   set cmd "set_property -dict \[list \
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
      CONFIG.NUM_READ_OUTSTANDING {$n_outsanding} \
      CONFIG.NUM_READ_THREADS {8} \
      CONFIG.NUM_WRITE_OUTSTANDING {$n_outsanding} \
      CONFIG.NUM_WRITE_THREADS {8} \
      CONFIG.PROTOCOL {AXI4} \
      CONFIG.READ_WRITE_MODE {READ_WRITE} \
      CONFIG.RUSER_BITS_PER_BYTE {0} \
      CONFIG.RUSER_WIDTH {0} \
      CONFIG.SUPPORTS_NARROW_BURST {0} \
      CONFIG.WUSER_BITS_PER_BYTE {0} \
      CONFIG.WUSER_WIDTH {0} \
   ] \$S_AXI"
   eval $cmd

   set M_AXI [create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M_AXI]
   set cmd "set_property -dict \[list \
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
      CONFIG.NUM_READ_OUTSTANDING {$n_outsanding} \
      CONFIG.NUM_WRITE_OUTSTANDING {$n_outsanding} \
      CONFIG.PROTOCOL {AXI4} \
      CONFIG.READ_WRITE_MODE {READ_WRITE} \
   ] \$M_AXI"
   eval $cmd

########################################################################################################
# Create ports
########################################################################################################   
   # Input clock and the associated reset; coming from the shell
   set cmd "set aclk \[ create_bd_port -dir I -type clk aclk ]
         set_property -dict \[ list \
            CONFIG.ASSOCIATED_BUSIF {S_AXI} \
            CONFIG.ASSOCIATED_RESET {aresetn} \
            CONFIG.FREQ_HZ {$cnfg(aclk_f)000000} \
         ] \$aclk"
   eval $cmd

   set aresetn [ create_bd_port -dir I -type rst aresetn ]
   set_property -dict [ list \
      CONFIG.POLARITY {ACTIVE_LOW} \
   ] $aresetn  

   # HBM clock; to the NoC
   set cmd "set hclk \[ create_bd_port -dir I -type clk hclk ]
         set_property -dict \[ list \
            CONFIG.ASSOCIATED_BUSIF {M_AXI} \
            CONFIG.FREQ_HZ {$cnfg(hclk_f)000000} \
         ] \$hclk"
   eval $cmd

########################################################################################################
# Create components
########################################################################################################
   # AXI SmartConnect for clock crossing & data width conversion
   set inst_smartconnect [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 inst_smartconnect]
   set_property -dict [list \
      CONFIG.NUM_CLKS {2} \
      CONFIG.NUM_SI {1} \
      CONFIG.NUM_MI {1} \
   ] $inst_smartconnect

########################################################################################################
# Create interface connections
########################################################################################################
   connect_bd_intf_net [get_bd_intf_ports S_AXI] [get_bd_intf_pins $inst_smartconnect/S00_AXI]
   connect_bd_intf_net [get_bd_intf_pins $inst_smartconnect/M00_AXI] [get_bd_intf_ports M_AXI]

########################################################################################################
# Create port connections
########################################################################################################
   connect_bd_net [get_bd_ports aclk] [get_bd_pins $inst_smartconnect/aclk]
   connect_bd_net [get_bd_ports hclk] [get_bd_pins $inst_smartconnect/aclk1]
   connect_bd_net [get_bd_ports aresetn] [get_bd_pins $inst_smartconnect/aresetn]

########################################################################################################
# Create address segments
########################################################################################################
   assign_bd_address -offset 0x0 -range 16E -target_address_space [get_bd_addr_spaces S_AXI] [get_bd_addr_segs M_AXI/Reg]

   # Restore current instance
   current_bd_instance $oldCurInst

   # Validate and save
   validate_bd_design
   save_bd_design
   close_bd_design $design_name
}

# Main HBM design through the Versal NoC
# There are two possible implementation: 'unified' and 'block'
# 'unified' means that each card stream (HBM_NMU) can access each HBM pseudo-channel (PC), meaning each card
# stream has access to the full HBM memory space. While simpler to program with, this implementation
# can lead to significant data movement in the horizontal NoC (HNOC) which limits throughput. However,
# the 'unified' implementation is the closest to previous implementations on UltraScale+ devices.
# 'block' partitions the HBM space into blocks, so that each card stream accesses one port of one HBM PC
# with no interference from other card streams, leading to higher throughput with no HNOC crossings.
# For example, the v80 has 32 PCs with 2 ports each ==> the memory space would be fragmented into 64 blocks
# of 512 MBand each vFPGA card stream could access exactly one of these blocks. The target block
#  can be configured from software through the mem_block parameter.
proc cr_bd_design_hbm { parentCell } {   
   upvar #0 cfg cnfg

   set design_name design_hbm

   common::send_msg_id "BD_TCL-003" "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

########################################################################################################
# Check IPs
########################################################################################################
   set bCheckIPs 1
   set bCheckIPsPassed 1

   if { $bCheckIPs == 1 } {
      set list_check_ips "\ 
         xilinx.com:ip:axi_noc:1.1\
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
# HBM MAIN
########################################################################################################
########################################################################################################

########################################################################################################
# Create interface ports
########################################################################################################
   if {$cnfg(hbm_impl) eq "unified"} {
      # In the unified HBM implemenation, striping is enabled by default
      # Therefore, the maximum number of outstanding transactions is dictate by 
      # N_OUTSTANDING (shell-wide) and striping, which partitions each PMTU-sized request 
      # into STRIPE_FRAG_SIZE requests.
      set n_outsanding [expr {$cnfg(n_outs) * $cnfg(pmtu) / $cnfg(stripe_frag_size)}]
   } elseif {$cnfg(hbm_impl) eq "block"} {
      # In the block HBM implementation, each HBM_NMU accesses one specific HBM PC
      # With no striping, there it at most N_OUTSTANDING outstanding requests
      set n_outsanding [expr {$cnfg(n_outs)}]
   } else {
      puts "ERROR: Requested unsupported Versal HBM implementation: $cnfg(hbm_impl); available: unified, block"
      exit 1
   }

   # AXI-MM ports
   for {set i 0}  {$i < $cnfg(n_mem_chan)} {incr i} {   
      set cmd "set axi_hbm_in_$i \[ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_hbm_in_$i ]
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
                  CONFIG.NUM_READ_OUTSTANDING {$n_outsanding} \
                  CONFIG.NUM_READ_THREADS {8} \
                  CONFIG.NUM_WRITE_OUTSTANDING {$n_outsanding} \
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

########################################################################################################
# Create ports
########################################################################################################
   # Clock associated with the AXI-MM interfaces
   set cmd "set hclk \[ create_bd_port -dir I -type clk hclk ]
         set_property -dict \[ list \
            CONFIG.ASSOCIATED_BUSIF {" 
            for {set i 0}  {$i < $cnfg(n_mem_chan)} {incr i} {
               append cmd "axi_hbm_in_$i"
               if {$i != $cnfg(n_mem_chan) - 1} {
                  append cmd ":"
               }
            }
            append cmd "} \
            CONFIG.FREQ_HZ {$cnfg(hclk_f)000000} \
         ] \$hclk"
   eval $cmd

########################################################################################################
# Create components
########################################################################################################
   # (HBM_SIZE == 35) => 2 ^ 35 GiB ~ 32 GiB ~ 16 HBM channels x 2 GB on the V80
   if {$cnfg(hbm_size) == 35} {
      set n_hbm_chan 16
   } else {
      puts "[color $clr_error "** CERR: Unknown HBM size specified. Ensure HBM_SIZE in CMake config is set correctly. **"]"
      puts "[color $clr_error "**"]"
      exit 1
   }

   # vFPGA card streams access HBM through the HBM NMUs
   # Offload & sync access HBM through the PL NoC interface, which has lower performance than the HBM_NMU
   set inst_hbm_noc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_noc:1.1 inst_hbm_noc ]
   
   if {$cnfg(hbm_impl) eq "unified"} {
      set cmd "set_property -dict \[list \
         CONFIG.HBM_CHNL0_CONFIG {HBM_REORDER_EN FALSE HBM_MAINTAIN_COHERENCY TRUE HBM_Q_AGE_LIMIT 0x7F HBM_CLOSE_PAGE_REORDER FALSE HBM_LOOKAHEAD_PCH TRUE HBM_COMMAND_PARITY FALSE HBM_DQ_WR_PARITY FALSE HBM_DQ_RD_PARITY\
      FALSE HBM_RD_DBI TRUE HBM_WR_DBI TRUE HBM_REFRESH_MODE SINGLE_BANK_REFRESH HBM_PC0_PRE_DEFINED_ADDRESS_MAP ROW_BANK_COLUMN_BGO HBM_PC1_PRE_DEFINED_ADDRESS_MAP ROW_BANK_COLUMN_BGO HBM_PC0_USER_DEFINED_ADDRESS_MAP\
      NONE HBM_PC1_USER_DEFINED_ADDRESS_MAP NONE HBM_PC0_ADDRESS_MAP RA14,RA13,RA12,RA11,RA10,RA9,RA8,RA7,RA6,RA5,RA4,RA3,RA2,RA1,RA0,SID,BA1,BA0,BA3,CA5,CA4,CA3,CA2,CA1,BA2,NC,NA,NA,NA,NA HBM_PC1_ADDRESS_MAP\
      RA14,RA13,RA12,RA11,RA10,RA9,RA8,RA7,RA6,RA5,RA4,RA3,RA2,RA1,RA0,SID,BA1,BA0,BA3,CA5,CA4,CA3,CA2,CA1,BA2,NC,NA,NA,NA,NA HBM_PWR_DWN_IDLE_TIMEOUT_ENTRY FALSE HBM_SELF_REF_IDLE_TIMEOUT_ENTRY FALSE HBM_IDLE_TIME_TO_ENTER_PWR_DWN_MODE\
      0x0001000 HBM_IDLE_TIME_TO_ENTER_SELF_REF_MODE 1X HBM_ECC_CORRECTION_EN FALSE HBM_WRITE_BACK_CORRECTED_DATA TRUE HBM_ECC_SCRUBBING FALSE HBM_ECC_INITIALIZE_EN FALSE HBM_ECC_SCRUB_SIZE 1092 HBM_WRITE_DATA_MASK\
      TRUE HBM_REF_PERIOD_TEMP_COMP FALSE HBM_PARITY_LATENCY 3 HBM_PC0_PAGE_HIT 100.000 HBM_PC1_PAGE_HIT 100.000 HBM_PC0_READ_RATE 25.000 HBM_PC1_READ_RATE 25.000 HBM_PC0_WRITE_RATE 25.000 HBM_PC1_WRITE_RATE\
      25.000 HBM_PC0_PHY_ACTIVE ENABLED HBM_PC1_PHY_ACTIVE ENABLED HBM_PC0_SCRUB_START_ADDRESS 0x0000000 HBM_PC0_SCRUB_END_ADDRESS 0x3FFFBFF HBM_PC0_SCRUB_INTERVAL 24.000 HBM_PC1_SCRUB_START_ADDRESS 0x0000000\
      HBM_PC1_SCRUB_END_ADDRESS 0x3FFFBFF HBM_PC1_SCRUB_INTERVAL 24.000} \
         CONFIG.HBM_NUM_CHNL {$n_hbm_chan} \
         CONFIG.NUM_HBM_BLI {[expr {$cnfg(n_mem_chan) - 1}]} \
         CONFIG.NUM_MI {0} \
         CONFIG.NUM_SI {1} \
      ] \$inst_hbm_noc"
      eval $cmd
   } elseif {$cnfg(hbm_impl) eq "block"} {      
      set cmd "set_property -dict \[list \
         CONFIG.HBM_CHNL0_CONFIG {HBM_REORDER_EN FALSE HBM_MAINTAIN_COHERENCY TRUE HBM_Q_AGE_LIMIT 0x7F HBM_CLOSE_PAGE_REORDER FALSE HBM_LOOKAHEAD_PCH TRUE HBM_COMMAND_PARITY FALSE HBM_DQ_WR_PARITY FALSE HBM_DQ_RD_PARITY\
      FALSE HBM_RD_DBI TRUE HBM_WR_DBI TRUE HBM_REFRESH_MODE SINGLE_BANK_REFRESH HBM_PC0_PRE_DEFINED_ADDRESS_MAP USER_DEFINED_ADDRESS_MAP HBM_PC1_PRE_DEFINED_ADDRESS_MAP USER_DEFINED_ADDRESS_MAP HBM_PC0_USER_DEFINED_ADDRESS_MAP\
      1BG-15RA-1SID-2BA-5CA-1BG HBM_PC1_USER_DEFINED_ADDRESS_MAP 1BG-15RA-1SID-2BA-5CA-1BG HBM_PC0_ADDRESS_MAP BA3,RA14,RA13,RA12,RA11,RA10,RA9,RA8,RA7,RA6,RA5,RA4,RA3,RA2,RA1,RA0,SID,BA1,BA0,CA5,CA4,CA3,CA2,CA1,BA2,NC,NA,NA,NA,NA\
      HBM_PC1_ADDRESS_MAP BA3,RA14,RA13,RA12,RA11,RA10,RA9,RA8,RA7,RA6,RA5,RA4,RA3,RA2,RA1,RA0,SID,BA1,BA0,CA5,CA4,CA3,CA2,CA1,BA2,NC,NA,NA,NA,NA HBM_PWR_DWN_IDLE_TIMEOUT_ENTRY FALSE HBM_SELF_REF_IDLE_TIMEOUT_ENTRY\
      FALSE HBM_IDLE_TIME_TO_ENTER_PWR_DWN_MODE 0x0001000 HBM_IDLE_TIME_TO_ENTER_SELF_REF_MODE 1X HBM_ECC_CORRECTION_EN FALSE HBM_WRITE_BACK_CORRECTED_DATA TRUE HBM_ECC_SCRUBBING FALSE HBM_ECC_INITIALIZE_EN\
      FALSE HBM_ECC_SCRUB_SIZE 1092 HBM_WRITE_DATA_MASK TRUE HBM_REF_PERIOD_TEMP_COMP FALSE HBM_PARITY_LATENCY 3 HBM_PC0_PAGE_HIT 100.000 HBM_PC1_PAGE_HIT 100.000 HBM_PC0_READ_RATE 25.000 HBM_PC1_READ_RATE 25.000\
      HBM_PC0_WRITE_RATE 25.000 HBM_PC1_WRITE_RATE 25.000 HBM_PC0_PHY_ACTIVE ENABLED HBM_PC1_PHY_ACTIVE ENABLED HBM_PC0_SCRUB_START_ADDRESS 0x0000000 HBM_PC0_SCRUB_END_ADDRESS 0x3FFFBFF HBM_PC0_SCRUB_INTERVAL\
      24.000 HBM_PC1_SCRUB_START_ADDRESS 0x0000000 HBM_PC1_SCRUB_END_ADDRESS 0x3FFFBFF HBM_PC1_SCRUB_INTERVAL 24.000} \
         CONFIG.HBM_NUM_CHNL {$n_hbm_chan} \
         CONFIG.NUM_HBM_BLI {[expr {$cnfg(n_mem_chan) - 1}]} \
         CONFIG.NUM_MI {0} \
         CONFIG.NUM_SI {1} \
      ] \$inst_hbm_noc"
      eval $cmd
   } else {
      puts "ERROR: Requested unsupported Versal HBM implementation: $cnfg(hbm_impl); available: unified, block"
      exit 1
   }

   # The average burst length is TRANSFER_SIZE [B] / 256 [b] (data width of NoC) * 8 [B]
   if {$cnfg(hbm_impl) eq "unified"} {
      # With striping, requests are of size STRIPE_FRAG_SIZE
      set avg_burst [expr {$cnfg(stripe_frag_size) / 256 * 8}]
   } elseif {$cnfg(hbm_impl) eq "block"} {
      # Without striping requests are typically of PMTU_SIZE
      set avg_burst [expr {($cnfg(pmtu) * 8) / 256}]
   } else {
      puts "ERROR: Requested unsupported Versal HBM implementation: $cnfg(hbm_impl); available: unified, block"
      exit 1
   }

   # Set offload/sync channel properties and connect to all PCs, to allow access to all of HBM's address space
   # Since the sync/offload channel is not on the critical path, it can accesses the HBM through the PL, 
   # which has lower performance than the HBM_NMU (which are reserved for the vFPGA card streams)
   set_property -dict [ list \
      CONFIG.CONNECTIONS {HBM10_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM15_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM10_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM5_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM15_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM5_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM1_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM1_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM6_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM12_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM0_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM6_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM14_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM12_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM0_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM8_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM8_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM14_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM3_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM3_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM4_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM4_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM9_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM2_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM11_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM9_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM11_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM7_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM13_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM7_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM13_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM2_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}}} \
      CONFIG.NOC_PARAMS {} \
      CONFIG.CATEGORY {pl} \
   ] [get_bd_intf_pins /inst_hbm_noc/S00_AXI]

   # Set HBM_NMU properties
   # Each HBM memory controller (MC) has two pseudo-channels (PC0 and PC1), each with two ports
   # Therefore, each HBM_NMU can connect to up to 64 ports
   if {$cnfg(hbm_impl) eq "unified"} {
      # In the unified implementation, each HBM_NMU can access the entire memory space (all-to-all)
      for {set i 1}  {$i < $cnfg(n_mem_chan)} {incr i} {
         set nmu_idx [expr {$i - 1}]
         set cmd [format "set_property -dict \[ list \
            CONFIG.CONNECTIONS {HBM10_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM15_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM10_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM5_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM15_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM5_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM1_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM1_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM6_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM12_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM0_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM6_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM14_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM12_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM0_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM8_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM8_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM14_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM3_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM3_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM4_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM4_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM9_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM2_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM11_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM9_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM11_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM7_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM13_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM7_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM13_PORT0 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} HBM2_PORT2 {read_bw {250} write_bw {250} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}}} \
            CONFIG.NOC_PARAMS {} \
            CONFIG.CATEGORY {pl_hbm} \
         ] \[get_bd_intf_pins inst_hbm_noc/HBM%02d_AXI]" $nmu_idx]
         eval $cmd
      }
      
   } elseif {$cnfg(hbm_impl) eq "block"} {
      # In the block implementation, each HBM_NMU accesses one port of one HBM PC
      # For the best performance and timing closure, connect each HBM_NMU to the closest HBM PC;
      # that is, there are no horizontal NoC (HNOC) traversals
      for {set i 1}  {$i < $cnfg(n_mem_chan)} {incr i} {
         set nmu_idx [expr {$i - 1}]
         set mc_idx [expr {$nmu_idx / 4}]
         set port_idx [expr {$nmu_idx % 4}]
         set cmd [format "set_property -dict \[ list \
            CONFIG.PHYSICAL_LOC {NOC_NMU_HBM2E_X%dY0} \
            CONFIG.CONNECTIONS {HBM%d_PORT%d {read_bw {12000} write_bw {12000} read_avg_burst {$avg_burst} write_avg_burst {$avg_burst}} } \
            CONFIG.NOC_PARAMS {} \
            CONFIG.CATEGORY {pl_hbm} \
         ] \[get_bd_intf_pins inst_hbm_noc/HBM%02d_AXI]" $nmu_idx $mc_idx $port_idx $nmu_idx]
         eval $cmd
      }
   } else {
      puts "ERROR: Requested unsupported Versal HBM implementation: $cnfg(hbm_impl); available: unified, block"
      exit 1
   }
   
   # Set associated clock
   set cmd "set_property -dict \[ list \
      CONFIG.ASSOCIATED_BUSIF {S00_AXI:" 
      for {set i 0}  {$i < $cnfg(n_mem_chan) - 1} {incr i} {
         append cmd [format "HBM%02d_AXI" $i]
         if {$i != $cnfg(n_mem_chan) - 2} {
            append cmd ":"
         }
      }
      append cmd "} \
   ] \[get_bd_pins inst_hbm_noc/aclk0]"
   eval $cmd

########################################################################################################
# Create interface connections
########################################################################################################
   # Connect sync/offload channel to NoC controller
   connect_bd_intf_net [get_bd_intf_port axi_hbm_in_0] [get_bd_intf_pins inst_hbm_noc/S00_AXI]

   # Connect HBM channels to NoC NMUs
   for {set i 1}  {$i < $cnfg(n_mem_chan)} {incr i} {       
      set nmu_idx [ expr {$i - 1} ] 
      set cmd "[format "connect_bd_intf_net \[get_bd_intf_port axi_hbm_in_%d] \[get_bd_intf_pins inst_hbm_noc/HBM%02d_AXI]" $i $nmu_idx ]"
      eval $cmd
   }

########################################################################################################
# Create port connections
########################################################################################################
   connect_bd_net [get_bd_ports hclk] [get_bd_pins inst_hbm_noc/aclk0]

########################################################################################################
# Create address segments
########################################################################################################
   assign_bd_address

   # Restore current instance
   current_bd_instance $oldCurInst

   # Validate and save
   validate_bd_design
   save_bd_design
   close_bd_design $design_name 

   return 0
}
