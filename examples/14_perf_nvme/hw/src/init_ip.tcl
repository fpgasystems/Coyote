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

# NOTE: On Versal architecture, the IP is called axis_ila instead of ila
if {$cfg(fpga_arch) eq "ultrascale_plus"} {
    create_ip -name ila -vendor xilinx.com -library ip -module_name ila_perf_nvme
} elseif {$cfg(fpga_arch) eq "versal"} {
    create_ip -name axis_ila -vendor xilinx.com -library ip -module_name ila_perf_nvme
} else {
    puts "ERROR: Unsupported FPGA architecture: $cfg(fpga_arch)"
    exit 1
}

set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {32} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} \
    CONFIG.C_DATA_DEPTH {8192} \
    CONFIG.C_PROBE0_WIDTH  {8}  \
    CONFIG.C_PROBE1_WIDTH  {2}  \
    CONFIG.C_PROBE2_WIDTH  {32} \
    CONFIG.C_PROBE3_WIDTH  {32} \
    CONFIG.C_PROBE4_WIDTH  {1}  \
    CONFIG.C_PROBE5_WIDTH  {2}  \
    CONFIG.C_PROBE6_WIDTH  {1}  \
    CONFIG.C_PROBE7_WIDTH  {1}  \
    CONFIG.C_PROBE8_WIDTH  {1}  \
    CONFIG.C_PROBE9_WIDTH  {4}  \
    CONFIG.C_PROBE10_WIDTH {32} \
    CONFIG.C_PROBE11_WIDTH {16} \
    CONFIG.C_PROBE12_WIDTH {1}  \
    CONFIG.C_PROBE13_WIDTH {16} \
    CONFIG.C_PROBE14_WIDTH {4}  \
    CONFIG.C_PROBE15_WIDTH {1}  \
    CONFIG.C_PROBE16_WIDTH {1}  \
    CONFIG.C_PROBE17_WIDTH {4}  \
    CONFIG.C_PROBE18_WIDTH {4}  \
    CONFIG.C_PROBE19_WIDTH {32} \
    CONFIG.C_PROBE20_WIDTH {48} \
    CONFIG.C_PROBE21_WIDTH {48} \
    CONFIG.C_PROBE22_WIDTH {28} \
    CONFIG.C_PROBE23_WIDTH {9}  \
    CONFIG.C_PROBE24_WIDTH {1}  \
    CONFIG.C_PROBE25_WIDTH {8}  \
    CONFIG.C_PROBE26_WIDTH {15} \
    CONFIG.C_PROBE27_WIDTH {1}  \
    CONFIG.C_PROBE28_WIDTH {1}  \
    CONFIG.C_PROBE29_WIDTH {32} \
    CONFIG.C_PROBE30_WIDTH {32} \
    CONFIG.C_PROBE31_WIDTH {32} \
] [get_ips ila_perf_nvme]
