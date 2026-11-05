######################################################################################
# This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
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

# Initialize vFPGA ILA with the correct configuration
# Important parameters that need to be set:
#   1. The number of probes 
#   2. Width of each probe, if different than 1
# NOTE: On Versal architecture, the IP is called axis_ila instead of ila
# if {$cfg(fpga_arch) eq "ultrascale_plus"} {
#     create_ip -name ila -vendor xilinx.com -library ip -module_name ila_processing_node
# } elseif {$cfg(fpga_arch) eq "versal"} {
#     create_ip -name axis_ila -vendor xilinx.com -library ip -module_name ila_processing_node
# } else {
#     puts "ERROR: Unsupported FPGA architecture: $cfg(fpga_arch)"
#     exit 1
# }
# set_property -dict [list CONFIG.C_NUM_OF_PROBES {20} CONFIG.C_PROBE7_WIDTH {512} CONFIG.C_PROBE3_WIDTH {512} CONFIG.C_PROBE15_WIDTH {512} CONFIG.C_PROBE11_WIDTH {512} CONFIG.C_EN_STRG_QUAL {1} CONFIG.ALL_PROBE_SAME_MU_CNT {2} CONFIG.C_PROBE16_WIDTH {32} CONFIG.C_PROBE17_WIDTH {1} CONFIG.C_PROBE18_WIDTH {32} CONFIG.C_PROBE19_WIDTH {1}] [get_ips ila_processing_node]
