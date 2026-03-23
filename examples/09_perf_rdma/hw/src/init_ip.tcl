if {$cfg(fpga_arch) eq "ultrascale_plus"} {
    create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_perf_rdma
} elseif {$cfg(fpga_arch) eq "versal"} {
    create_ip -name axis_ila -vendor xilinx.com -library ip -module_name ila_perf_rdma
} else {
    puts "ERROR: Unsupported FPGA architecture: $cfg(fpga_arch)"
    exit 1
}
set_property -dict [list CONFIG.C_NUM_OF_PROBES {16} CONFIG.C_EN_STRG_QUAL {1} CONFIG.ALL_PROBE_SAME_MU_CNT {2}] [get_ips ila_perf_rdma]