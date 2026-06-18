# Initialize vFPGA ILA with the correct configuration
# Important parameters that need to be set:
#   1. The number of probes 
#   2. Width of each probe, if different than 1
# NOTE: On Versal architecture, the IP is called axis_ila instead of ila
if {$cfg(fpga_arch) eq "ultrascale_plus"} {
    create_ip -name ila -vendor xilinx.com -library ip -module_name ila_perf_host
} elseif {$cfg(fpga_arch) eq "versal"} {
    create_ip -name axis_ila -vendor xilinx.com -library ip -module_name ila_perf_host
} else {
    puts "ERROR: Unsupported FPGA architecture: $cfg(fpga_arch)"
    exit 1
}
set_property -dict [list CONFIG.C_NUM_OF_PROBES {8} CONFIG.C_PROBE7_WIDTH {512} CONFIG.C_PROBE3_WIDTH {512} CONFIG.C_EN_STRG_QUAL {1} CONFIG.ALL_PROBE_SAME_MU_CNT {2}] [get_ips ila_perf_host]
